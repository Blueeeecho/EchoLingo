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

struct CaptureRegionPlan {
    let region: CGRect
    let scale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    let displays: [CaptureDisplayGeometry]
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
    case cancelled
}

struct CaptureSelectorState {
    let displays: [CaptureDisplayGeometry]
    private(set) var highlightedDisplay: CGDirectDisplayID?
    private(set) var anchor: CGPoint?
    private(set) var selection: CGRect?
    private(set) var outcome: CaptureSelectorOutcome?

    mutating func receive(_ event: CaptureSelectorEvent) {
        guard outcome == nil else { return }
        switch event {
        case .cancel:
            outcome = .cancelled
        case .move(let point):
            highlightedDisplay = captureDisplay(at: point, displays: displays)
        case .leftDown(let point):
            guard captureDisplay(at: point, displays: displays) != nil else { return }
            highlightedDisplay = captureDisplay(at: point, displays: displays)
            anchor = point
            selection = nil
        case .leftDrag(let point):
            highlightedDisplay = captureDisplay(at: point, displays: displays)
            if let anchor = anchor { selection = captureRectangle(anchor, point) }
        case .leftUp(let point):
            guard let anchor = anchor else { return }
            let rectangle = captureRectangle(anchor, point)
            if rectangle.width >= 2 && rectangle.height >= 2 {
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

    func wait(until deadline: Date) throws -> T {
        guard !Thread.isMainThread else {
            throw NativeError("CAPTURE: 截图需要由应用后台任务启动。")
        }
        condition.lock()
        defer { condition.unlock() }
        while result == nil && Date() < deadline { _ = condition.wait(until: deadline) }
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

final class CaptureSelectionView: NSView {
    var highlighted = false
    var selection: CGRect?
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
        if let selection = selection, !selection.isEmpty {
            let outline = NSBezierPath(rect: selection.insetBy(dx: 0.75, dy: 0.75))
            outline.lineWidth = 1.5
            outline.stroke()
        }
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

    init(displays: [CaptureDisplayGeometry], waiter: CaptureResultWaiter<CaptureRegionPlan>,
         lifetime: CaptureSelectionLifetime) {
        self.state = CaptureSelectorState(displays: displays)
        self.waiter = waiter
        self.lifetime = lifetime
    }

    func show() throws {
        guard lifetime.canPresent() else { throw NativeError("CANCELLED: 截图操作超时或已取消。") }
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
            default: break
            }
            return nil
        }
        guard monitor != nil else { throw NativeError("CAPTURE: 无法启动截图框选，请重试。") }
        receive(.move(NSEvent.mouseLocation))
        for (_, panel, _) in panels {
            // Recheck immediately before each visible mutation; creating the
            // backing panels may itself have consumed the remaining budget.
            guard lifetime.canPresent() else { throw NativeError("CANCELLED: 截图操作超时或已取消。") }
            panel.orderFrontRegardless()
        }
        guard lifetime.canPresent() else { throw NativeError("CANCELLED: 截图操作超时或已取消。") }
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
        state.receive(event)
        if let outcome = state.outcome {
            switch outcome {
            case .cancelled: finish(.failure(NativeError("CANCELLED: 已取消截图。")))
            case .selected(let rectangle):
                do { finish(.success(try capturePlan(rectangle, displays: state.displays))) }
                catch { finish(.failure(error)) }
            }
            return
        }
        for (geometry, _, view) in panels {
            let highlight = state.highlightedDisplay == geometry.id
            let clipped = state.selection?.intersection(geometry.frame)
            let local = clipped.flatMap { rectangle -> CGRect? in
                if rectangle.isEmpty || rectangle.isNull { return nil }
                return rectangle.offsetBy(dx: -geometry.frame.minX, dy: -geometry.frame.minY)
            }
            if view.highlighted != highlight || view.selection != local {
                view.highlighted = highlight
                view.selection = local
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

func selectNativeCaptureRegion() throws -> CaptureRegionPlan {
    guard !Thread.isMainThread else { throw NativeError("CAPTURE: 截图需要由应用后台任务启动。") }
    let waiter = CaptureResultWaiter<CaptureRegionPlan>()
    let lifetime = CaptureSelectionLifetime(deadline: Date().addingTimeInterval(120))
    DispatchQueue.main.async {
        guard lifetime.begin() else {
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
        let selection = CaptureSelectionSession(displays: screens, waiter: waiter, lifetime: lifetime)
        activeCaptureSelection = selection
        do { try selection.show() }
        catch { selection.finish(.failure(error)) }
    }
    do { return try waiter.wait(until: lifetime.deadline) }
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
func captureScreenKitImage(_ plan: CaptureRegionPlan) throws -> CGImage {
    let deadline = Date().addingTimeInterval(15)
    let contentWaiter = CaptureResultWaiter<SCShareableContent>()
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
        if let content = content { contentWaiter.finish(.success(content)) }
        else { contentWaiter.finish(.failure(captureFailure(error))) }
    }
    let content = try contentWaiter.wait(until: deadline)
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
        let image = try imageWaiter.wait(until: deadline)
        let destination = CGRect(x: (part.minX - plan.region.minX) * plan.scale,
                                 y: (part.minY - plan.region.minY) * plan.scale,
                                 width: part.width * plan.scale, height: part.height * plan.scale)
        context.draw(image, in: destination)
    }
    guard let image = context.makeImage() else { throw NativeError("CAPTURE: 无法完成截图图像。") }
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

func captureNativeRegionImage() throws -> CGImage {
    let plan = try selectNativeCaptureRegion()
    if #available(macOS 14.0, *) { return try captureScreenKitImage(plan) }
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
    guard let image = CGImage(windowListFromArrayScreenBounds: rectangle, windowArray: windows,
                              imageOption: [.bestResolution, .boundsIgnoreFraming]) else {
        throw NativeError("CAPTURE: macOS 未能完成区域截图，请检查屏幕录制权限。")
    }
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
    state.receive(.leftUp(CGPoint(x: 200, y: 300)))
    try expect(state.outcome == .selected(plan.region))
    state.receive(.cancel)
    try expect(state.outcome == .selected(plan.region))
    var cancelled = CaptureSelectorState(displays: displays)
    cancelled.receive(.leftDown(CGPoint(x: 100, y: 100)))
    cancelled.receive(.cancel)
    cancelled.receive(.leftUp(CGPoint(x: 200, y: 200)))
    try expect(cancelled.outcome == .cancelled)
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
