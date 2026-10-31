import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

// All capture UI and capture APIs execute inside the statically linked app.
// Coordinates used by the selector are AppKit global logical points (y up).
// ScreenCaptureKit's sourceRect is display-local logical points (y down).
struct CaptureDisplayGeometry: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let scale: CGFloat
}

enum CapturePurpose: Equatable { case region, screenshot }

struct CaptureWindowTarget: Equatable {
    let id: CGWindowID
    let pid: Int32
    // AppKit global logical points, not Retina pixels.
    let frame: CGRect
}

struct CaptureRegionPlan {
    let region: CGRect
    let scale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    let displays: [CaptureDisplayGeometry]
    var window: CaptureWindowTarget? = nil
}

// Strict projection of public WindowServer metadata. Never read window names.
func captureWindowNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let value = number.doubleValue
    return value.isFinite ? value : nil
}

func captureWindowTarget(_ record: [String: Any], primaryHeight: CGFloat, excludingPID: Int32) -> CaptureWindowTarget? {
    guard let pid = captureWindowNumber(record[kCGWindowOwnerPID as String]), pid > 0,
          pid <= Double(Int32.max), pid.rounded(.towardZero) == pid, Int32(pid) != excludingPID,
          let id = captureWindowNumber(record[kCGWindowNumber as String]), id > 0,
          id <= Double(UInt32.max), id.rounded(.towardZero) == id,
          captureWindowNumber(record[kCGWindowLayer as String]) == 0,
          record[kCGWindowIsOnscreen as String] as? Bool == true,
          let alpha = captureWindowNumber(record[kCGWindowAlpha as String]), alpha > 0, alpha <= 1,
          let sharing = captureWindowNumber(record[kCGWindowSharingState as String]), sharing == 1 || sharing == 2,
          let dictionary = record[kCGWindowBounds as String] as? [String: Any],
          let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
          [quartz.minX, quartz.minY, quartz.width, quartz.height, primaryHeight].allSatisfy({ $0.isFinite }),
          quartz.width >= 2, quartz.height >= 2 else { return nil }
    return CaptureWindowTarget(id: CGWindowID(id), pid: Int32(pid),
        frame: CGRect(x: quartz.minX, y: primaryHeight - quartz.maxY, width: quartz.width, height: quartz.height))
}

func captureHoverWindow(_ records: [[String: Any]], at point: CGPoint, primaryHeight: CGFloat,
                        excludingPID: Int32, hitTest: ((Int) -> Int)? = nil) -> CaptureWindowTarget? {
    guard point.x.isFinite, point.y.isFinite, primaryHeight.isFinite,
          hitTest != nil || Thread.isMainThread else { return nil }
    // A window's metadata rectangle need not be opaque or mouse-hittable.
    // Ask AppKit for the actual mouse-down target, which accounts for point
    // transparency and ignoresMouseEvents. Never whitelist a process/layer.
    // Only proven own-PID hits may be stepped past (our selectors/editor).
    var below = 0
    var seen = Set<Int>()
    for _ in 0..<min(records.count + 1, 64) {
        let hit = hitTest?(below) ?? NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: below)
        guard hit > 0, UInt64(hit) <= UInt64(UInt32.max), seen.insert(hit).inserted else { return nil }
        let matches = records.filter { captureWindowNumber($0[kCGWindowNumber as String]) == Double(hit) }
        guard matches.count == 1, let record = matches.first else { return nil }
        if captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(excludingPID) {
            below = hit
            continue
        }
        // Unknown, protected, ineligible or inconsistent REAL hits fail closed;
        // do not look through them for a different foreign window underneath.
        guard let target = captureWindowTarget(record, primaryHeight: primaryHeight, excludingPID: excludingPID),
              target.frame.contains(point) else { return nil }
        return target
    }
    return nil
}

func captureCurrentWindows() -> [[String: Any]]? {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
}

func captureWindowIsCurrent(_ expected: CaptureWindowTarget, records: [[String: Any]],
                            primaryHeight: CGFloat, excludingPID: Int32) -> Bool {
    records.contains { record in
        captureWindowTarget(record, primaryHeight: primaryHeight, excludingPID: excludingPID) == expected
    }
}

func captureValidateWindow(_ expected: CaptureWindowTarget?) throws {
    guard let expected = expected else { return }
    guard CGPreflightScreenCaptureAccess(), let records = captureCurrentWindows(),
          captureWindowIsCurrent(expected, records: records, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height,
                                 excludingPID: ProcessInfo.processInfo.processIdentifier) else {
        throw NativeError("CAPTURE_WINDOW_CHANGED: 窗口已移动、关闭或无法安全截图，请重新选择。")
    }
}

func captureVisibleWindowRectangle(_ frame: CGRect, displays: [CaptureDisplayGeometry]) -> CGRect {
    let parts = displays.map { frame.intersection($0.frame) }.filter { !$0.isNull && !$0.isEmpty }
    guard let first = parts.first else { return .null }
    let visible = parts.dropFirst().reduce(first) { $0.union($1) }
    // Stay inside the selected window, even if WindowServer reports fractions.
    return CGRect(x: ceil(visible.minX), y: ceil(visible.minY),
                  width: floor(visible.maxX) - ceil(visible.minX), height: floor(visible.maxY) - ceil(visible.minY))
}

func captureRectangle(_ first: CGPoint, _ second: CGPoint) -> CGRect {
    CGRect(x: min(first.x, second.x), y: min(first.y, second.y),
           width: abs(first.x - second.x), height: abs(first.y - second.y))
}

func captureDisplay(at point: CGPoint, displays: [CaptureDisplayGeometry]) -> CGDirectDisplayID? {
    displays.first { $0.frame.contains(point) }?.id
}

func captureSourceRectangle(_ region: CGRect, display: CaptureDisplayGeometry) -> CGRect {
    let clipped = region.intersection(display.frame)
    guard !clipped.isNull, !clipped.isEmpty else { return .null }
    return CGRect(x: clipped.minX - display.frame.minX, y: display.frame.maxY - clipped.maxY,
                  width: clipped.width, height: clipped.height)
}

func capturePlan(_ region: CGRect, displays: [CaptureDisplayGeometry]) throws -> CaptureRegionPlan {
    guard [region.minX, region.minY, region.width, region.height].allSatisfy({ $0.isFinite }),
          region.width >= 2, region.height >= 2 else {
        throw NativeError("CANCELLED: 框选区域太小；请按住左键拖动选择区域。")
    }
    let selected = displays.filter { !$0.frame.intersection(region).isEmpty }
    guard !selected.isEmpty,
          selected.allSatisfy({ $0.scale.isFinite && $0.scale > 0 && $0.scale <= 8 &&
              [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height].allSatisfy { $0.isFinite } }) else {
        throw NativeError("CAPTURE: 无法读取选区所在屏幕；请重新框选。")
    }
    // Integral logical coordinates give stable pixel edges across 1x/2x screens.
    // The largest selected scale preserves Retina text when crossing displays.
    let integral = region.integral
    let scale = selected.map(\.scale).max() ?? 1
    let width = ceil(integral.width * scale), height = ceil(integral.height * scale)
    guard width > 0, height > 0, width <= 16384, height <= 16384,
          width * height <= 32 * 1024 * 1024 else {
        throw NativeError("CAPTURE_TOO_LARGE: 选区过大，请缩小区域后重试。")
    }
    return CaptureRegionPlan(region: integral, scale: scale, pixelWidth: Int(width),
                             pixelHeight: Int(height), displays: selected)
}

enum CaptureSelectorEvent {
    case move(CGPoint)
    case leftDown(CGPoint)
    case leftDrag(CGPoint)
    case leftUp(CGPoint)
    case cancel
}

enum CaptureSelectorOutcome: Equatable {
    case selected(CGRect)
    case windowSelected(CaptureWindowTarget)
    case cancelled
}

struct CaptureSelectorState {
    let displays: [CaptureDisplayGeometry]
    var purpose: CapturePurpose = .region
    var candidate: CaptureWindowTarget?
    private(set) var pressedWindow: CaptureWindowTarget?
    private(set) var dragExceeded = false
    private(set) var highlightedDisplay: CGDirectDisplayID?
    private(set) var anchor: CGPoint?
    private(set) var selection: CGRect?
    private(set) var outcome: CaptureSelectorOutcome?

    // The window outline is a hint in both modes. Only F1 can retain a
    // pressed window as a click target; OCR remains a free rectangle drag.
    var canQueryWindowHint: Bool { outcome == nil && anchor == nil }
    var windowHint: CaptureWindowTarget? {
        guard outcome == nil else { return nil }
        if anchor == nil { return candidate }
        return purpose == .screenshot && !dragExceeded ? pressedWindow : nil
    }

    mutating func receive(_ event: CaptureSelectorEvent) {
        guard outcome == nil else { return }
        switch event {
        case .cancel:
            outcome = .cancelled
        case .move(let point):
            highlightedDisplay = captureDisplay(at: point, displays: displays)
            if purpose == .screenshot, let anchor = anchor {
                dragExceeded = dragExceeded || abs(point.x - anchor.x) > 4 || abs(point.y - anchor.y) > 4
                if dragExceeded { selection = captureRectangle(anchor, point) }
            }
        case .leftDown(let point):
            guard captureDisplay(at: point, displays: displays) != nil else { return }
            highlightedDisplay = captureDisplay(at: point, displays: displays)
            guard anchor == nil else { return }
            anchor = point
            pressedWindow = purpose == .screenshot ? candidate.flatMap { $0.frame.contains(point) ? $0 : nil } : nil
            dragExceeded = false
            selection = nil
        case .leftDrag(let point):
            highlightedDisplay = captureDisplay(at: point, displays: displays)
            if let anchor = anchor {
                dragExceeded = dragExceeded || abs(point.x - anchor.x) > 4 || abs(point.y - anchor.y) > 4
                selection = captureRectangle(anchor, point)
            }
        case .leftUp(let point):
            guard let anchor = anchor else { return }
            let rectangle = captureRectangle(anchor, point)
            dragExceeded = dragExceeded || rectangle.width > 4 || rectangle.height > 4
            if purpose == .screenshot && !dragExceeded {
                outcome = pressedWindow.map { .windowSelected($0) } ?? .cancelled
            } else if rectangle.width >= 2 && rectangle.height >= 2 {
                selection = rectangle
                outcome = .selected(rectangle)
            } else {
                // An ordinary click is not a capture.
                // Stay armed, allowing the user to start another left drag.
                self.anchor = nil
                selection = nil
            }
        }
    }
}

final class CaptureScreenshotOperation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

final class CaptureScreenshotOperations {
    static let shared = CaptureScreenshotOperations()
    private let lock = NSLock()
    private var operations: [String: CaptureScreenshotOperation] = [:]
    func begin() throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard operations.count < 16 else { throw NativeError("CAPTURE_BUSY: 截图请求仍在结束。") }
        let id = UUID().uuidString
        operations[id] = CaptureScreenshotOperation()
        return id
    }
    func lookup(_ id: String) -> CaptureScreenshotOperation? {
        lock.lock(); defer { lock.unlock() }; return operations[id]
    }
    func end(_ id: String) {
        lock.lock(); let operation = operations.removeValue(forKey: id); lock.unlock()
        operation?.cancel()
    }
}

final class CaptureResultWaiter<T> {
    private let condition = NSCondition()
    private var result: Result<T, Error>?
    private var abandoned = false

    func finish(_ value: Result<T, Error>) {
        condition.lock()
        defer { condition.unlock() }
        guard result == nil, !abandoned else { return }
        result = value
        condition.signal()
    }

    func wait(until deadline: Date, cancelled: (() -> Bool)? = nil) throws -> T {
        guard !Thread.isMainThread else {
            throw NativeError("CAPTURE: 截图需要由应用后台任务启动。")
        }
        condition.lock()
        defer { condition.unlock() }
        while result == nil && Date() < deadline {
            if cancelled?() == true {
                abandoned = true
                throw NativeError("CANCELLED: 截图请求已取消。")
            }
            _ = condition.wait(until: cancelled == nil ? deadline : min(deadline, Date().addingTimeInterval(0.05)))
        }
        if cancelled?() == true {
            abandoned = true
            throw NativeError("CANCELLED: 截图请求已取消。")
        }
        guard let result = result else {
            abandoned = true
            throw NativeError("CANCELLED: 截图操作超时，已取消。")
        }
        return try result.get()
    }
}

// Shared by the worker and its queued AppKit presentation. A request owns one
// absolute deadline, including time spent waiting for the main queue. Cancelling
// before that queue runs permanently prevents it from opening a late selector.
final class CaptureSelectionLifetime {
    private enum Phase { case queued, started, finished }
    private let lock = NSLock()
    private var phase = Phase.queued
    let deadline: Date

    init(deadline: Date) { self.deadline = deadline }

    func begin(at now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .queued else { return false }
        guard now < deadline else { phase = .finished; return false }
        phase = .started
        return true
    }

    func canPresent(at now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .started else { return false }
        guard now < deadline else { phase = .finished; return false }
        return true
    }

    func finish() {
        lock.lock()
        phase = .finished
        lock.unlock()
    }
}

final class CaptureSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

let captureLoupeSample: CGFloat = 52
let captureLoupeZoom: CGFloat = 3
let captureLoupeCaption: CGFloat = 16
let captureLoupeGap: CGFloat = 18

func captureLoupeFrame(anchor: CGPoint, viewSize: CGSize) -> CGRect {
    let view = captureLoupeSample * captureLoupeZoom
    let width = view
    let height = view + captureLoupeCaption
    let sample = CGRect(x: anchor.x - captureLoupeSample / 2, y: anchor.y - captureLoupeSample / 2,
                         width: captureLoupeSample, height: captureLoupeSample)
    var origin = CGPoint(x: sample.maxX + captureLoupeGap, y: sample.maxY + captureLoupeGap)
    if origin.x + width > viewSize.width { origin.x = sample.minX - captureLoupeGap - width }
    if origin.y + height > viewSize.height { origin.y = sample.minY - captureLoupeGap - height }
    origin.x = min(max(0, origin.x), max(0, viewSize.width - width))
    origin.y = min(max(0, origin.y), max(0, viewSize.height - height))
    var frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    if frame.intersects(sample) || frame.contains(anchor) {
        let left = anchor.x > viewSize.width / 2
        let below = anchor.y > viewSize.height / 2
        origin.x = left ? 0 : max(0, viewSize.width - width)
        origin.y = below ? 0 : max(0, viewSize.height - height)
        frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }
    return frame
}

func captureLoupeImage(at screenPoint: CGPoint, windowID: CGWindowID) -> NSImage? {
    let primary = CGDisplayBounds(CGMainDisplayID()).height
    let rect = CGRect(x: screenPoint.x - captureLoupeSample / 2,
                      y: primary - screenPoint.y - captureLoupeSample / 2,
                      width: captureLoupeSample, height: captureLoupeSample)
    guard rect.width > 1, rect.height > 1 else { return nil }
    let list: CGWindowListOption = windowID == 0 ? .optionOnScreenOnly : .optionOnScreenBelowWindow
    guard let image = CGWindowListCreateImage(rect, list, windowID, [.bestResolution, .boundsIgnoreFraming]) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: captureLoupeSample, height: captureLoupeSample))
}

func configureCaptureSelectionPanel(_ panel: CaptureSelectionPanel) {
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = .none
    panel.ignoresMouseEvents = false
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovable = false
    panel.acceptsMouseMovedEvents = true
    panel.level = .screenSaver
    // A genuine nonactivating panel, an accessory application policy and the
    // macOS13+ cross-application role allow entry into another app's full-screen
    // Space. A high level alone does not place a regular app in that Space.
    // App activation policy is configured once at startup, never toggled here.
    panel.collectionBehavior = popupCollectionBehavior([.stationary, .ignoresCycle])
    panel.sharingType = .none
}

struct CaptureLoupe {
    let image: NSImage
    let frame: CGRect
    let label: String
}

final class CaptureSelectionView: NSView {
    var highlighted = false
    var selection: CGRect?
    var hoveredWindow: CGRect?
    var loupeAnchor: CGPoint?
    var loupe: CaptureLoupe?
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // No fill, frozen screenshot or dimming layer: the live desktop stays
        // readable. Both outlines are entirely inside this transparent panel.
        NSColor(calibratedRed: 0.10, green: 0.48, blue: 1.0, alpha: 1).setStroke()
        if highlighted {
            let edge = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            edge.lineWidth = 2
            edge.stroke()
        }
        if let hoveredWindow = hoveredWindow, !hoveredWindow.isEmpty {
            let outline = NSBezierPath(rect: hoveredWindow.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()
        }
        if let selection = selection, !selection.isEmpty {
            let outline = NSBezierPath(rect: selection.insetBy(dx: 0.75, dy: 0.75))
            outline.lineWidth = 1.5
            outline.stroke()
        }
        guard let loupe = loupe else { return }
        let plate = NSBezierPath(roundedRect: loupe.frame, xRadius: 6, yRadius: 6)
        NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
        plate.fill()
        NSColor(calibratedRed: 0.10, green: 0.48, blue: 1.0, alpha: 1).setStroke()
        plate.lineWidth = 1
        plate.stroke()
        let imageRect = NSRect(x: loupe.frame.minX, y: loupe.frame.minY + captureLoupeCaption,
                               width: captureLoupeSample * captureLoupeZoom, height: captureLoupeSample * captureLoupeZoom)
        loupe.image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.22, alpha: 0.95).setStroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: imageRect.midX, y: imageRect.minY))
        cross.line(to: NSPoint(x: imageRect.midX, y: imageRect.maxY))
        cross.move(to: NSPoint(x: imageRect.minX, y: imageRect.midY))
        cross.line(to: NSPoint(x: imageRect.maxX, y: imageRect.midY))
        cross.lineWidth = 1
        cross.stroke()
        let text = NSAttributedString(string: loupe.label, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white
        ])
        text.draw(at: NSPoint(x: loupe.frame.minX + 6, y: loupe.frame.minY + 1))
    }

    // The local event monitor handles the capture gesture. Do not invoke a
    // default right-button context menu or forward mouse clicks to a source app.
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {}
}

// Main-thread only. Keeping the session until finish guarantees a single
// selector and deterministic disposal of every panel, timer and event monitor.
private var activeCaptureSelection: CaptureSelectionSession?

final class CaptureSelectionSession {
    private var state: CaptureSelectorState
    private var panels: [(CaptureDisplayGeometry, CaptureSelectionPanel, CaptureSelectionView)] = []
    private var monitor: Any?
    private var pointerTimer: Timer?
    private var timeoutTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private let waiter: CaptureResultWaiter<CaptureRegionPlan>
    fileprivate let lifetime: CaptureSelectionLifetime
    private var completed = false
    private var pointer = NSEvent.mouseLocation
    private var lastWindowQuery = Date.distantPast
    private let operation: CaptureScreenshotOperation?

    init(displays: [CaptureDisplayGeometry], waiter: CaptureResultWaiter<CaptureRegionPlan>,
         lifetime: CaptureSelectionLifetime, purpose: CapturePurpose = .region,
         operation: CaptureScreenshotOperation? = nil) {
        self.state = CaptureSelectorState(displays: displays, purpose: purpose)
        self.operation = operation
        self.waiter = waiter
        self.lifetime = lifetime
    }

    func show() throws {
        guard lifetime.canPresent(), operation?.isCancelled != true else { throw NativeError("CANCELLED: 截图操作超时或已取消。") }
        guard !state.displays.isEmpty else { throw NativeError("CAPTURE: 未找到可截图的屏幕。") }
        for geometry in state.displays {
            let panel = CaptureSelectionPanel(contentRect: geometry.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            configureCaptureSelectionPanel(panel)
            let view = CaptureSelectionView(frame: NSRect(origin: .zero, size: geometry.frame.size))
            panel.contentView = view
            panels.append((geometry, panel, view))
        }
        let mask: NSEvent.EventTypeMask = [.keyDown, .mouseMoved, .rightMouseDown, .rightMouseDragged,
                                           .rightMouseUp, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self, !self.completed else { return event }
            let isCaptureWindow = self.panels.contains { $0.1 === event.window }
            // Making a nonactivating panel key routes Esc locally, even when
            // Accessibility/Input Monitoring were never granted.
            if event.type == .keyDown {
                guard isCaptureWindow else { return event }
                if event.keyCode == 53 { self.receive(.cancel) }
                return nil
            }
            guard isCaptureWindow else { return event }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            switch event.type {
            case .mouseMoved: self.receive(.move(point))
            case .leftMouseDown: self.receive(.leftDown(point))
            case .leftMouseDragged: self.receive(.leftDrag(point))
            case .leftMouseUp: self.receive(.leftUp(point))
            case .rightMouseDown:
                if self.state.purpose == .screenshot { self.receive(.cancel) }
            default: break
            }
            return nil
        }
        guard monitor != nil else { throw NativeError("CAPTURE: 无法启动截图框选，请重试。") }
        receive(.move(NSEvent.mouseLocation))
        for (_, panel, _) in panels {
            // Recheck immediately before each visible mutation; creating the
            // backing panels may itself have consumed the remaining budget.
            guard lifetime.canPresent(), operation?.isCancelled != true else { throw NativeError("CANCELLED: 截图操作超时或已取消。") }
            panel.orderFrontRegardless()
        }
        guard lifetime.canPresent(), operation?.isCancelled != true else { throw NativeError("CANCELLED: 截图操作超时或已取消。") }
        if let panel = panels.first(where: { $0.0.id == state.highlightedDisplay }) ?? panels.first {
            panel.1.makeKey()
            panel.1.makeFirstResponder(panel.2)
        }
        // Only pointer position is sampled, and only while this explicit
        // selector is armed. This needs no global hooks or input permission.
        pointerTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.receive(.move(NSEvent.mouseLocation))
        }
        if let pointerTimer = pointerTimer { RunLoop.main.add(pointerTimer, forMode: .common) }
        timeoutTimer = Timer(timeInterval: max(0.001, lifetime.deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            self?.receive(.cancel)
        }
        if let timeoutTimer = timeoutTimer { RunLoop.main.add(timeoutTimer, forMode: .common) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.receive(.cancel)
            }
    }

    func receive(_ event: CaptureSelectorEvent) {
        guard !completed else { return }
        switch event {
        case .move(let point), .leftDown(let point), .leftDrag(let point), .leftUp(let point):
            pointer = point
        case .cancel:
            break
        }
        if operation?.isCancelled == true { state.receive(.cancel) }
        if state.canQueryWindowHint {
            let now = Date()
            let isPress: Bool
            if case .leftDown = event { isPress = true } else { isPress = false }
            if isPress || now.timeIntervalSince(lastWindowQuery) >= 0.08 {
                lastWindowQuery = now
                state.candidate = captureCurrentWindows().flatMap {
                    captureHoverWindow($0, at: pointer, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height,
                                       excludingPID: ProcessInfo.processInfo.processIdentifier)
                }
            } else if state.candidate?.frame.contains(pointer) != true { state.candidate = nil }
        }
        state.receive(event)
        if let outcome = state.outcome {
            switch outcome {
            case .cancelled: finish(.failure(NativeError("CANCELLED: 已取消截图。")))
            case .selected(let rectangle):
                do { finish(.success(try capturePlan(rectangle, displays: state.displays))) }
                catch { finish(.failure(error)) }
            case .windowSelected(let window):
                do {
                    try captureValidateWindow(window)
                    let rectangle = captureVisibleWindowRectangle(window.frame, displays: state.displays)
                    var plan = try capturePlan(rectangle, displays: state.displays)
                    plan.window = window
                    finish(.success(plan))
                } catch { finish(.failure(error)) }
            }
            return
        }
        for (geometry, panel, view) in panels {
            let pointerOnDisplay = state.highlightedDisplay == geometry.id
            let highlight = pointerOnDisplay && state.purpose == .region
            let hovered = state.windowHint?.frame.intersection(geometry.frame)
            let localHovered = hovered.flatMap { rectangle -> CGRect? in
                if rectangle.isEmpty || rectangle.isNull { return nil }
                return rectangle.offsetBy(dx: -geometry.frame.minX, dy: -geometry.frame.minY)
            }
            let clipped = state.selection?.intersection(geometry.frame)
            let local = clipped.flatMap { rectangle -> CGRect? in
                if rectangle.isEmpty || rectangle.isNull { return nil }
                return rectangle.offsetBy(dx: -geometry.frame.minX, dy: -geometry.frame.minY)
            }
            let localPointer = geometry.frame.contains(pointer) && pointerOnDisplay
                ? CGPoint(x: pointer.x - geometry.frame.minX, y: pointer.y - geometry.frame.minY) : nil
            let pointerMoved: Bool = {
                switch (view.loupeAnchor, localPointer) {
                case (nil, nil): return false
                case let (previous?, next?): return abs(previous.x - next.x) >= 1 || abs(previous.y - next.y) >= 1
                default: return true
                }
            }()
            let loupeChanged = view.selection != local || pointerMoved
            if view.highlighted != highlight || view.hoveredWindow != localHovered || loupeChanged {
                view.highlighted = highlight
                view.hoveredWindow = localHovered
                view.selection = local
                view.loupeAnchor = localPointer
                // Metadata-only hint changes redraw the outline without
                // taking another magnifier sample at an unchanged pointer.
                if loupeChanged, let localPointer = localPointer {
                    let number = panel.windowNumber
                    let windowID: CGWindowID = number > 0 ? CGWindowID(number) : 0
                    if let image = captureLoupeImage(at: pointer, windowID: windowID) {
                        let label: String
                        if let selection = state.selection, selection.width >= 2, selection.height >= 2 {
                            label = "\(Int(selection.width.rounded())) × \(Int(selection.height.rounded()))"
                        } else { label = "3×" }
                        view.loupe = CaptureLoupe(image: image, frame: captureLoupeFrame(anchor: localPointer, viewSize: view.bounds.size), label: label)
                    } else { view.loupe = nil }
                } else if localPointer == nil { view.loupe = nil }
                view.needsDisplay = true
            }
        }
    }

    func finish(_ result: Result<CaptureRegionPlan, Error>) {
        guard !completed else { return }
        completed = true
        lifetime.finish()
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pointerTimer?.invalidate(); pointerTimer = nil
        timeoutTimer?.invalidate(); timeoutTimer = nil
        if let screenObserver = screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for (_, panel, _) in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        // Flush ordering transactions before the worker starts capture; capture
        // filters also exclude this process's windows as a second protection.
        NSApp.updateWindows()
        if activeCaptureSelection === self { activeCaptureSelection = nil }
        waiter.finish(result)
    }
}

func selectNativeCaptureRegion(purpose: CapturePurpose = .region, operation: CaptureScreenshotOperation? = nil) throws -> CaptureRegionPlan {
    guard !Thread.isMainThread else { throw NativeError("CAPTURE: 截图需要由应用后台任务启动。") }
    let waiter = CaptureResultWaiter<CaptureRegionPlan>()
    let lifetime = CaptureSelectionLifetime(deadline: Date().addingTimeInterval(120))
    DispatchQueue.main.async {
        guard lifetime.begin(), operation?.isCancelled != true else {
            waiter.finish(.failure(NativeError("CANCELLED: 截图操作超时或已取消。")))
            return
        }
        guard activeCaptureSelection == nil else {
            lifetime.finish()
            waiter.finish(.failure(NativeError("CAPTURE_BUSY: 已有截图框选正在进行。")))
            return
        }
        let screens = NSScreen.screens.compactMap { screen -> CaptureDisplayGeometry? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CaptureDisplayGeometry(id: number.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
        }
        let selection = CaptureSelectionSession(displays: screens, waiter: waiter, lifetime: lifetime, purpose: purpose, operation: operation)
        activeCaptureSelection = selection
        do { try selection.show() }
        catch { selection.finish(.failure(error)) }
    }
    do { return try waiter.wait(until: lifetime.deadline, cancelled: operation.map { operation in { operation.isCancelled } }) }
    catch {
        lifetime.finish()
        DispatchQueue.main.async {
            // A stale cleanup cannot cancel a different request that reached
            // the main queue after this worker's deadline.
            if let session = activeCaptureSelection, session.lifetime === lifetime {
                session.receive(.cancel)
            }
        }
        throw error
    }
}

@available(macOS 12.3, *)
private func captureFailure(_ error: Error?) -> NativeError {
    if let error = error as NSError?, error.domain == SCStreamErrorDomain, error.code == -3801 {
        return NativeError("PERMISSION: macOS 尚未允许此次屏幕捕获，请在设置中检查 EchoLingo 的屏幕录制权限。")
    }
    return NativeError("CAPTURE: macOS 未能完成区域截图，请检查屏幕录制权限后重试。")
}

@available(macOS 14.0, *)
func captureScreenKitImage(_ plan: CaptureRegionPlan, operation: CaptureScreenshotOperation? = nil) throws -> CGImage {
    try captureValidateWindow(plan.window)
    let deadline = Date().addingTimeInterval(15)
    let contentWaiter = CaptureResultWaiter<SCShareableContent>()
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
        if let content = content { contentWaiter.finish(.success(content)) }
        else { contentWaiter.finish(.failure(captureFailure(error))) }
    }
    let content = try contentWaiter.wait(until: deadline, cancelled: operation.map { operation in { operation.isCancelled } })
    let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
    guard let context = CGContext(data: nil, width: plan.pixelWidth, height: plan.pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: plan.pixelWidth * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NativeError("CAPTURE_TOO_LARGE: 无法分配截图内存，请缩小区域后重试。")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: plan.pixelWidth, height: plan.pixelHeight))
    for geometry in plan.displays {
        try captureValidateWindow(plan.window)
        guard Date() < deadline,
              let display = content.displays.first(where: { $0.displayID == geometry.id }) else {
            throw NativeError("CAPTURE: 屏幕配置已变化或截图超时，请重新框选。")
        }
        let part = plan.region.intersection(geometry.frame)
        let source = captureSourceRectangle(plan.region, display: geometry)
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        if #available(macOS 14.2, *) { filter.includeMenuBar = true }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        configuration.width = Int(ceil(part.width * plan.scale))
        configuration.height = Int(ceil(part.height * plan.scale))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        let imageWaiter = CaptureResultWaiter<CGImage>()
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            if let image = image { imageWaiter.finish(.success(image)) }
            else { imageWaiter.finish(.failure(captureFailure(error))) }
        }
        let image = try imageWaiter.wait(until: deadline, cancelled: operation.map { operation in { operation.isCancelled } })
        let destination = CGRect(x: (part.minX - plan.region.minX) * plan.scale,
                                 y: (part.minY - plan.region.minY) * plan.scale,
                                 width: part.width * plan.scale, height: part.height * plan.scale)
        context.draw(image, in: destination)
    }
    guard let image = context.makeImage() else { throw NativeError("CAPTURE: 无法完成截图图像。") }
    try captureValidateWindow(plan.window)
    return image
}

// Legacy captures must compose only other processes' windows. Filtering the
// small PID/ID projection keeps a pinned translator visible without recognizing
// its own text. Preserve WindowServer's front-to-back ordering; do not inspect
// titles or fall back to a full-desktop image when metadata is incomplete.
func captureLegacyWindowIds(_ records: [[String: Any]], excludingPID: Int32) -> [CGWindowID] {
    var included: [CGWindowID] = []
    var seen = Set<CGWindowID>()
    for record in records {
        guard let owner = record[kCGWindowOwnerPID as String] as? NSNumber,
              let number = record[kCGWindowNumber as String] as? NSNumber,
              CFGetTypeID(owner) != CFBooleanGetTypeID(),
              CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
        let pid = owner.doubleValue
        let id = number.doubleValue
        guard pid.isFinite, pid.rounded(.towardZero) == pid, pid >= 0, pid <= Double(Int32.max),
              Int32(pid) != excludingPID,
              id.isFinite, id.rounded(.towardZero) == id, id > 0, id <= Double(UInt32.max) else { continue }
        let window = CGWindowID(id)
        if seen.insert(window).inserted { included.append(window) }
    }
    return included
}

func captureLegacyWindowArray(_ ids: [CGWindowID]) throws -> CFArray {
    // This API requires raw CGWindowID values, not an NSArray of NSNumber
    // objects. Nil callbacks prevent CFArray from retaining/releasing the IDs.
    guard let array = CFArrayCreateMutable(kCFAllocatorDefault, ids.count, nil) else {
        throw NativeError("CAPTURE: 无法准备窗口截图列表，请重试。")
    }
    for id in ids {
        guard id != 0, let value = UnsafeRawPointer(bitPattern: UInt(id)) else {
            throw NativeError("CAPTURE: 窗口截图列表无效，请重试。")
        }
        CFArrayAppendValue(array, value)
    }
    return array
}

func captureNativeRegionImage(purpose: CapturePurpose = .region, operation: CaptureScreenshotOperation? = nil) throws -> CGImage {
    let plan = try selectNativeCaptureRegion(purpose: purpose, operation: operation)
    if operation?.isCancelled == true { throw NativeError("CANCELLED: 截图请求已取消。") }
    try captureValidateWindow(plan.window)
    if #available(macOS 14.0, *) { return try captureScreenKitImage(plan, operation: operation) }
    // Legacy path is restricted to macOS 12/13; new macOS releases use the
    // public ScreenCaptureKit screenshot API without a child TCC identity.
    let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
    let rectangle = CGRect(x: plan.region.minX, y: primaryHeight - plan.region.maxY,
                           width: plan.region.width, height: plan.region.height)
    guard let records = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
        throw NativeError("CAPTURE: 无法读取用于区域截图的窗口列表，请重试。")
    }
    let ids = captureLegacyWindowIds(records, excludingPID: ProcessInfo.processInfo.processIdentifier)
    guard !ids.isEmpty else {
        throw NativeError("CAPTURE: 没有可用于区域截图的外部窗口，请重新框选。")
    }
    let windows = try captureLegacyWindowArray(ids)
    if purpose == .screenshot {
        // The legacy window-array API can include backing pixels outside real
        // displays. Compose only display intersections, just like ScreenKit;
        // blank monitor gaps are never reconstructed from window contents.
        guard let context = CGContext(data: nil, width: plan.pixelWidth, height: plan.pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: plan.pixelWidth * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NativeError("CAPTURE_TOO_LARGE: 无法分配截图内存，请缩小区域后重试。")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: plan.pixelWidth, height: plan.pixelHeight))
        for geometry in plan.displays {
            if operation?.isCancelled == true { throw NativeError("CANCELLED: 截图请求已取消。") }
            try captureValidateWindow(plan.window)
            let part = plan.region.intersection(geometry.frame)
            let source = CGRect(x: part.minX, y: primaryHeight - part.maxY, width: part.width, height: part.height)
            guard let image = CGImage(windowListFromArrayScreenBounds: source, windowArray: windows,
                                      imageOption: [.bestResolution, .boundsIgnoreFraming]) else {
                throw NativeError("CAPTURE: macOS 未能完成可见区域截图。")
            }
            let destination = CGRect(x: (part.minX - plan.region.minX) * plan.scale,
                                     y: (part.minY - plan.region.minY) * plan.scale,
                                     width: part.width * plan.scale, height: part.height * plan.scale)
            context.draw(image, in: destination)
        }
        try captureValidateWindow(plan.window)
        guard let image = context.makeImage() else { throw NativeError("CAPTURE: 无法完成截图图像。") }
        return image
    }
    guard let image = CGImage(windowListFromArrayScreenBounds: rectangle, windowArray: windows,
                              imageOption: [.bestResolution, .boundsIgnoreFraming]) else {
        throw NativeError("CAPTURE: macOS 未能完成区域截图，请检查屏幕录制权限。")
    }
    try captureValidateWindow(plan.window)
    return image
}

func captureSelectionSelfTest() throws {
    let primary = CaptureDisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    let left = CaptureDisplayGeometry(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)
    let above = CaptureDisplayGeometry(id: 3, frame: CGRect(x: 0, y: 900, width: 1280, height: 720), scale: 1)
    let displays = [primary, left, above]
    func expect(_ value: Bool) throws {
        if !value { throw NativeError("SELF_TEST: Capture selector geometry/state fixture failed.") }
    }
    try expect(captureDisplay(at: CGPoint(x: -1, y: 0), displays: displays) == 2)
    try expect(captureDisplay(at: CGPoint(x: 10, y: 1000), displays: displays) == 3)
    try expect(captureDisplay(at: CGPoint(x: 1500, y: 1000), displays: displays) == nil)
    try expect(captureRectangle(CGPoint(x: 100, y: 80), CGPoint(x: -40, y: 10)) == CGRect(x: -40, y: 10, width: 140, height: 70))
    try expect(captureSourceRectangle(CGRect(x: -1800, y: 720, width: 100, height: 80), display: left) == CGRect(x: 120, y: 100, width: 100, height: 80))
    let plan = try capturePlan(CGRect(x: -100, y: 100, width: 300, height: 200), displays: displays)
    try expect(plan.displays.count == 2 && plan.scale == 2 && plan.pixelWidth == 600 && plan.pixelHeight == 400)
    let abovePlan = try capturePlan(CGRect(x: 20, y: 920, width: 100, height: 80), displays: displays)
    try expect(abovePlan.pixelWidth == 100 && abovePlan.pixelHeight == 80)
    let fractional = try capturePlan(CGRect(x: 10.25, y: 20.25, width: 10.25, height: 20.25), displays: displays)
    try expect(fractional.region == CGRect(x: 10, y: 20, width: 11, height: 21) && fractional.pixelWidth == 22)
    for invalid in [CGRect(x: 0, y: 0, width: 1, height: 100), CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10),
                    CGRect(x: 2000, y: 2000, width: 100, height: 100), CGRect(x: 0, y: 0, width: 20000, height: 20000)] {
        do { _ = try capturePlan(invalid, displays: displays); throw NativeError("SELF_TEST: Invalid capture geometry was accepted.") }
        catch let error as NativeError { if error.message.hasPrefix("SELF_TEST:") { throw error } }
    }
    var state = CaptureSelectorState(displays: displays)
    state.receive(.move(CGPoint(x: 100, y: 100)))
    try expect(state.highlightedDisplay == 1 && state.anchor == nil && state.selection == nil && state.outcome == nil)
    state.receive(.move(CGPoint(x: -100, y: 100)))
    try expect(state.highlightedDisplay == 2 && state.outcome == nil)
    state.receive(.leftUp(CGPoint(x: -100, y: 100)))
    try expect(state.outcome == nil)
    state.receive(.leftDown(CGPoint(x: -100, y: 100)))
    state.receive(.leftUp(CGPoint(x: -100, y: 100)))
    try expect(state.anchor == nil && state.outcome == nil)
    state.receive(.leftDown(CGPoint(x: -100, y: 100)))
    state.receive(.leftDrag(CGPoint(x: 200, y: 300)))
    try expect(state.highlightedDisplay == 1 && state.selection == plan.region && state.outcome == nil)
    let interior = captureLoupeFrame(anchor: CGPoint(x: 200, y: 200), viewSize: CGSize(width: 1440, height: 900))
    let sample = CGRect(x: 174, y: 174, width: 52, height: 52)
    try expect(interior.minX >= sample.maxX && interior.maxX <= 1440 && interior.maxY <= 900 && !interior.intersects(sample))
    let corner = captureLoupeFrame(anchor: CGPoint(x: 1430, y: 880), viewSize: CGSize(width: 1440, height: 900))
    try expect(corner.maxX <= 1440 && corner.maxY <= 900 && !corner.contains(CGPoint(x: 1430, y: 880)))
    state.receive(.leftUp(CGPoint(x: 200, y: 300)))
    try expect(state.outcome == .selected(plan.region))
    state.receive(.cancel)
    try expect(state.outcome == .selected(plan.region))
    var cancelled = CaptureSelectorState(displays: displays)
    cancelled.receive(.leftDown(CGPoint(x: 100, y: 100)))
    cancelled.receive(.cancel)
    cancelled.receive(.leftUp(CGPoint(x: 200, y: 200)))
    try expect(cancelled.outcome == .cancelled)
    try captureScreenshotSelfTest()
    try captureWindowHintSelfTest()
    try captureLegacyExclusionSelfTest()
    try captureSelectionDeadlineSelfTest()
    try captureOverlayBehaviorSelfTest()
}

func captureOverlayBehaviorSelfTest() throws {
    let legacyRequired: UInt64 = (1 << 0) | (1 << 8)
    let modernRole: UInt64 = 1 << 18
    let conflicts: UInt64 = (1 << 1) | (1 << 7) | (1 << 9) | (1 << 16) | (1 << 17) | modernRole
    let preserved: UInt64 = (1 << 4) | (1 << 6) | (1 << 12) | (1 << 40)
    for modern: Int32 in [0, 1] {
        for value: UInt64 in [0, conflicts, legacyRequired, preserved, preserved | conflicts] {
            let expected = (value & ~conflicts) | legacyRequired | (modern == 1 ? modernRole : 0)
            let actual = echoLingoPopupBehaviorMaskForVersion(value, modern)
            guard actual == expected, echoLingoPopupBehaviorMaskForVersion(actual, modern) == actual else {
                throw NativeError("SELF_TEST: Capture fullscreen collection behavior fixture failed.")
            }
        }
    }
}

func captureLegacyExclusionSelfTest() throws {
    let ownPID: Int32 = 901
    let owner = kCGWindowOwnerPID as String
    let number = kCGWindowNumber as String
    let records: [[String: Any]] = [
        [owner: ownPID, number: 100], // The visible pinned translator.
        [owner: 902, number: 51],
        [number: 77], // Unknown owner must not accidentally include this app.
        [owner: ownPID, number: 101], // Another window in the same process.
        [owner: 903, number: 7],
        [owner: 903, number: 7], // Do not composite duplicate entries.
        [owner: 904, number: 0],
        [owner: 904, number: -1],
        [owner: 904, number: Double(UInt32.max) + 1],
        [owner: 904, number: 9.5],
        [owner: "unknown", number: 80],
        [owner: true, number: 81],
        [owner: 905, number: 4_000_000_000],
    ]
    let expected: [CGWindowID] = [51, 7, 4_000_000_000]
    let ids = captureLegacyWindowIds(records, excludingPID: ownPID)
    guard ids == expected else {
        throw NativeError("SELF_TEST: Legacy capture included own/unknown windows or changed stacking order.")
    }
    let array = try captureLegacyWindowArray(ids)
    guard CFArrayGetCount(array) == expected.count else {
        throw NativeError("SELF_TEST: Legacy capture window ID array has the wrong size.")
    }
    for (index, id) in expected.enumerated() {
        guard UInt(bitPattern: CFArrayGetValueAtIndex(array, index)) == UInt(id) else {
            throw NativeError("SELF_TEST: Legacy capture did not encode raw CGWindowID values.")
        }
    }
    guard captureLegacyWindowIds([[owner: ownPID, number: 100]], excludingPID: ownPID).isEmpty else {
        throw NativeError("SELF_TEST: Legacy capture failed to exclude its own process.")
    }
}

func captureSelectionDeadlineSelfTest() throws {
    let origin = Date(timeIntervalSince1970: 1_000)
    let deadline = origin.addingTimeInterval(120)
    func expect(_ value: Bool) throws {
        if !value { throw NativeError("SELF_TEST: Capture selector deadline/lifetime fixture failed.") }
    }
    let queuedExpired = CaptureSelectionLifetime(deadline: deadline)
    try expect(!queuedExpired.begin(at: deadline))
    try expect(!queuedExpired.begin(at: origin))
    let queuedCancelled = CaptureSelectionLifetime(deadline: deadline)
    queuedCancelled.finish()
    try expect(!queuedCancelled.begin(at: origin) && !queuedCancelled.canPresent(at: origin))
    let active = CaptureSelectionLifetime(deadline: deadline)
    try expect(!active.canPresent(at: origin))
    try expect(active.begin(at: origin.addingTimeInterval(90)))
    try expect(!active.begin(at: origin.addingTimeInterval(91)))
    try expect(active.canPresent(at: deadline.addingTimeInterval(-0.001)))
    try expect(!active.canPresent(at: deadline))
    try expect(!active.canPresent(at: origin.addingTimeInterval(91)))
    active.finish()
    try expect(!active.canPresent(at: origin.addingTimeInterval(91)))
    let completed = CaptureSelectionLifetime(deadline: deadline)
    try expect(completed.begin(at: origin))
    completed.finish()
    try expect(!completed.begin(at: origin) && !completed.canPresent(at: origin))
    // Model a blocked main queue resumed after expiry: its one-shot start gate
    // refuses the queued presentation, rather than allocating any UI objects.
    let delayed = CaptureSelectionLifetime(deadline: deadline)
    var presentationCount = 0
    if delayed.begin(at: deadline.addingTimeInterval(30)) { presentationCount += 1 }
    try expect(presentationCount == 0)
}

// Pure mode/visual policy: sharing a decorative hint must not enable OCR
// whole-window clicks or make an unavailable hint a prerequisite for dragging.
func captureWindowHintSelfTest() throws {
    func expect(_ value: Bool) throws {
        if !value { throw NativeError("SELF_TEST: Capture window hint policy fixture failed.") }
    }
    let display = CaptureDisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    let target = CaptureWindowTarget(id: 51, pid: 41, frame: CGRect(x: 100, y: 100, width: 500, height: 300))
    let anchor = CGPoint(x: 200, y: 200), end = CGPoint(x: 400, y: 350)
    let rectangle = captureRectangle(anchor, end)
    for purpose in [CapturePurpose.region, .screenshot] {
        var state = CaptureSelectorState(displays: [display], purpose: purpose)
        try expect(state.canQueryWindowHint && state.windowHint == nil)
        state.candidate = target
        state.receive(.move(anchor))
        try expect(state.canQueryWindowHint && state.windowHint == target)
        state.receive(.leftDown(anchor))
        try expect(!state.canQueryWindowHint)
        try expect(state.windowHint == (purpose == .screenshot ? target : nil))
        try expect(state.pressedWindow == (purpose == .screenshot ? target : nil))
        state.receive(.leftUp(anchor))
        if purpose == .region {
            // Repeated OCR clicks stay armed; they never capture the hint.
            try expect(state.outcome == nil && state.anchor == nil && state.windowHint == target)
            state.receive(.leftDown(anchor)); state.receive(.leftUp(anchor))
            try expect(state.outcome == nil && state.canQueryWindowHint)
        } else {
            try expect(state.outcome == .windowSelected(target))
            try expect(!state.canQueryWindowHint && state.windowHint == nil)
        }
        var drag = CaptureSelectorState(displays: [display], purpose: purpose, candidate: target)
        drag.receive(.leftDown(anchor)); drag.receive(.leftDrag(end))
        try expect(!drag.canQueryWindowHint && drag.windowHint == nil)
        drag.receive(.leftUp(end))
        try expect(drag.outcome == .selected(rectangle) && drag.windowHint == nil)
        var cancelled = CaptureSelectorState(displays: [display], purpose: purpose, candidate: target)
        cancelled.receive(.cancel); cancelled.receive(.leftDown(anchor))
        try expect(cancelled.outcome == .cancelled && !cancelled.canQueryWindowHint && cancelled.windowHint == nil)
        // No stale target after cancel/restart. Missing/protected/unsupported
        // metadata resolves to nil and cannot block a new rectangle selection.
        var unavailable = CaptureSelectorState(displays: [display], purpose: purpose)
        try expect(unavailable.canQueryWindowHint && unavailable.windowHint == nil)
        unavailable.receive(.leftDown(anchor)); unavailable.receive(.leftDrag(end)); unavailable.receive(.leftUp(end))
        try expect(unavailable.outcome == .selected(rectangle))
    }
    // OCR retains its original 2-point ROI minimum, not F1's 4-point click jitter.
    var small = CaptureSelectorState(displays: [display], candidate: target)
    small.receive(.leftDown(anchor)); small.receive(.leftUp(CGPoint(x: 203, y: 203)))
    try expect(small.outcome == .selected(CGRect(x: 200, y: 200, width: 3, height: 3)))
}

// Pure metadata, geometry, gesture and cancellation fixtures. No window-server
// queries, capture APIs, permissions, synthetic input or general clipboard.
func captureScreenshotSelfTest() throws {
    func expect(_ value: Bool) throws {
        if !value { throw NativeError("SELF_TEST: F1 screenshot window policy fixture failed.") }
    }
    let primary = CaptureDisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    let left = CaptureDisplayGeometry(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)
    let displays = [primary, left]
    let quartz = CGRect(x: -200, y: 400, width: 500, height: 300)
    let record: [String: Any] = [kCGWindowOwnerPID as String: NSNumber(value: 41),
        kCGWindowNumber as String: NSNumber(value: 51), kCGWindowLayer as String: NSNumber(value: 0),
        kCGWindowIsOnscreen as String: true, kCGWindowAlpha as String: NSNumber(value: 1.0),
        kCGWindowSharingState as String: NSNumber(value: 1),
        kCGWindowBounds as String: quartz.dictionaryRepresentation]
    guard let target = captureWindowTarget(record, primaryHeight: 900, excludingPID: 91) else {
        throw NativeError("SELF_TEST: F1 screenshot valid metadata was rejected.")
    }
    try expect(target.frame == CGRect(x: -200, y: 200, width: 500, height: 300))
    let point = CGPoint(x: -100, y: 250)
    try expect(captureHoverWindow([record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { _ in 51 }) == target)
    try expect(captureWindowTarget(record, primaryHeight: 900, excludingPID: 41) == nil)
    for (key, value) in [(kCGWindowOwnerPID as String, NSNumber(value: true) as Any),
                         (kCGWindowNumber as String, NSNumber(value: 0) as Any),
                         (kCGWindowLayer as String, NSNumber(value: 3) as Any),
                         (kCGWindowIsOnscreen as String, false as Any),
                         (kCGWindowAlpha as String, NSNumber(value: 0) as Any),
                         (kCGWindowSharingState as String, NSNumber(value: 0) as Any)] {
        var invalid = record; invalid[key] = value
        try expect(captureWindowTarget(invalid, primaryHeight: 900, excludingPID: 91) == nil)
        try expect(!captureWindowIsCurrent(target, records: [invalid], primaryHeight: 900, excludingPID: 91))
    }
    var protected = record; protected.removeValue(forKey: kCGWindowSharingState as String)
    protected[kCGWindowNumber as String] = NSNumber(value: 52)
    try expect(captureHoverWindow([protected, record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { _ in 52 }) == nil)
    var overlay = record; overlay[kCGWindowNumber as String] = NSNumber(value: 53)
    overlay[kCGWindowLayer as String] = NSNumber(value: 20)
    // A non-hittable covering rectangle does not replace the OS's actual hit.
    try expect(captureHoverWindow([overlay, record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { _ in 51 }) == target)
    try expect(captureHoverWindow([overlay, record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { _ in 53 }) == nil)
    var own = overlay; own[kCGWindowOwnerPID as String] = NSNumber(value: 91)
    var ownSecond = own; ownSecond[kCGWindowNumber as String] = NSNumber(value: 54)
    ownSecond[kCGWindowSharingState as String] = NSNumber(value: 0)
    var queriedBelow: [Int] = []
    try expect(captureHoverWindow([own, ownSecond, record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { below in
        queriedBelow.append(below)
        return below == 0 ? 53 : below == 53 ? 54 : 51
    }) == target)
    try expect(queriedBelow == [0, 53, 54])
    var loopQueries = 0
    try expect(captureHoverWindow([own, record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { _ in
        loopQueries += 1; return 53
    }) == nil)
    try expect(loopQueries == 2)
    for hit in [0, -1, 999, Int(UInt32.max) + 1] {
        try expect(captureHoverWindow([record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { _ in hit }) == nil)
    }
    try expect(captureHoverWindow([record, record], at: point, primaryHeight: 900, excludingPID: 91, hitTest: { _ in 51 }) == nil)
    try expect(captureHoverWindow([record], at: CGPoint(x: 800, y: 700), primaryHeight: 900, excludingPID: 91, hitTest: { _ in 51 }) == nil)
    for key in [kCGWindowNumber as String, kCGWindowOwnerPID as String] {
        var replaced = record; replaced[key] = NSNumber(value: 999)
        try expect(!captureWindowIsCurrent(target, records: [replaced], primaryHeight: 900, excludingPID: 91))
    }
    var moved = record; moved[kCGWindowBounds as String] = quartz.offsetBy(dx: 1, dy: 0).dictionaryRepresentation
    try expect(!captureWindowIsCurrent(target, records: [moved], primaryHeight: 900, excludingPID: 91))
    try expect(!captureWindowIsCurrent(target, records: [], primaryHeight: 900, excludingPID: 91))
    let anchor = CGPoint(x: -100, y: 250)
    var click = CaptureSelectorState(displays: displays, purpose: .screenshot, candidate: target)
    click.receive(.leftDown(anchor)); click.candidate = nil
    click.receive(.leftUp(CGPoint(x: -96, y: 253)))
    try expect(click.outcome == .windowSelected(target))
    var missing = CaptureSelectorState(displays: displays, purpose: .screenshot)
    missing.receive(.leftDown(anchor)); missing.receive(.leftUp(CGPoint(x: -96, y: 254)))
    try expect(missing.outcome == .cancelled)
    var drag = CaptureSelectorState(displays: displays, purpose: .screenshot, candidate: target)
    drag.receive(.leftDown(anchor)); drag.receive(.leftDrag(CGPoint(x: 30, y: 330)))
    drag.receive(.leftUp(CGPoint(x: 30, y: 330)))
    try expect(drag.outcome == .selected(CGRect(x: -100, y: 250, width: 130, height: 80)))
    var returned = CaptureSelectorState(displays: displays, purpose: .screenshot, candidate: target)
    returned.receive(.leftDown(anchor)); returned.receive(.leftDrag(CGPoint(x: -50, y: 300)))
    returned.receive(.leftUp(CGPoint(x: -97, y: 253)))
    try expect(returned.outcome == .selected(CGRect(x: -100, y: 250, width: 3, height: 3)))
    var cancelled = CaptureSelectorState(displays: displays, purpose: .screenshot, candidate: target)
    cancelled.receive(.leftDown(anchor)); cancelled.receive(.cancel); cancelled.receive(.leftUp(anchor))
    try expect(cancelled.outcome == .cancelled)
    let clipped = captureVisibleWindowRectangle(CGRect(x: -2000, y: -200, width: 2200, height: 500), displays: displays)
    try expect(clipped == CGRect(x: -1920, y: -180, width: 2120, height: 480))
    let plan = try capturePlan(target.frame, displays: displays)
    try expect(plan.scale == 2 && plan.pixelWidth == 1000 && plan.pixelHeight == 600 && plan.displays.count == 2)
    let operations = CaptureScreenshotOperations()
    let first = try operations.begin(), second = try operations.begin()
    guard let old = operations.lookup(first), let current = operations.lookup(second) else {
        throw NativeError("SELF_TEST: F1 cancellation token was not registered.")
    }
    old.cancel(); try expect(old.isCancelled && !current.isCancelled)
    operations.end(first); try expect(operations.lookup(first) == nil && !current.isCancelled)
    operations.end(second); try expect(current.isCancelled && operations.lookup(second) == nil)
}
