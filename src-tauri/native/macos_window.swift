import AppKit
import Foundation
import CoreGraphics
import ObjectiveC

// Metadata from this process only. Callers use NSApplication's synchronous
// getter rather than treating a cached NSRunningApplication value as proof of
// the effective startup policy. This helper never changes activation policy.
func applicationPolicyMetadataFields() -> [Int64] {
    let application = NSApplication.shared
    let agent = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool
    return [1, Int64(application.activationPolicy().rawValue),
            Int64(NSRunningApplication.current.activationPolicy.rawValue),
            agent.map { $0 ? Int64(1) : Int64(0) } ?? -1,
            application.isActive ? 1 : 0, Int64(application.windows.count),
            Int64(ProcessInfo.processInfo.processIdentifier), Thread.isMainThread ? 1 : 0]
}

@_cdecl("echolingo_application_policy_metadata")
public func echoLingoApplicationPolicyMetadata(_ output: UnsafeMutablePointer<Int64>?,
                                               _ count: Int32) -> Int32 {
    guard Thread.isMainThread else { return -1 }
    guard let output = output else { return -2 }
    guard count >= 8 else { return -3 }
    let fields = applicationPolicyMetadataFields()
    for index in fields.indices { output[index] = fields[index] }
    return 0
}

// Full-screen/space/Stage Manager groups contain mutually exclusive flags.
// The version is explicit so pure fixtures can exercise the macOS12 fallback
// even when running on a newer system. Unknown unrelated bits are preserved.
func popupCollectionBehavior(_ current: NSWindow.CollectionBehavior,
                             joinsAllApplications: Bool) -> NSWindow.CollectionBehavior {
    var result = current
    result.remove([.moveToActiveSpace, .fullScreenPrimary, .fullScreenNone])
    result.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
    // Raw values are SDK-defined (NSWindow.h), available since macOS13. Do not
    // leave modern primary/auxiliary flags competing with the overlay role.
    let stageManagerRoles = NSWindow.CollectionBehavior(rawValue: (1 << 16) | (1 << 17) | (1 << 18))
    result.remove(stageManagerRoles)
    if joinsAllApplications {
        result.insert(NSWindow.CollectionBehavior(rawValue: 1 << 18))
    }
    return result
}

func popupCollectionBehavior(_ current: NSWindow.CollectionBehavior) -> NSWindow.CollectionBehavior {
    if #available(macOS 13.0, *) {
        return popupCollectionBehavior(current, joinsAllApplications: true)
    }
    return popupCollectionBehavior(current, joinsAllApplications: false)
}

// This pure ABI also lets Rust test the exact production mask policy without
// creating a window, showing UI, or querying any privacy permission.
@_cdecl("echolingo_popup_behavior_mask")
public func echoLingoPopupBehaviorMask(_ current: UInt64) -> UInt64 {
    UInt64(popupCollectionBehavior(NSWindow.CollectionBehavior(rawValue: UInt(current))).rawValue)
}

@_cdecl("echolingo_popup_behavior_mask_for_version")
public func echoLingoPopupBehaviorMaskForVersion(_ current: UInt64, _ modern: Int32) -> UInt64 {
    UInt64(popupCollectionBehavior(NSWindow.CollectionBehavior(rawValue: UInt(current)),
                                 joinsAllApplications: modern != 0).rawValue)
}

// Called only with Tauri's borrowed, valid NSWindow on the application main
// thread. No showing, ordering, activation, focus, geometry or pin changes.
// Cocoa style-mask changes and full-screen transitions can alter window state;
// presentation callers reassert this policy after preparing the popup.
@_cdecl("echolingo_ensure_popup_behavior")
public func echoLingoEnsurePopupBehavior(_ pointer: UnsafeMutableRawPointer?) -> Int32 {
    guard Thread.isMainThread else { return -1 }
    guard let pointer = pointer,
          let window = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSWindow else { return -2 }
    let behavior = popupCollectionBehavior(window.collectionBehavior)
    window.collectionBehavior = behavior
    window.level = .floating
    return window.level.rawValue > NSWindow.Level.normal.rawValue && window.collectionBehavior == behavior ? 0 : -3
}

// Cocoa screen and window frames are both in points with a bottom-left origin.
// Keep the original top-left-local press anchor, never an unrelated currentEvent
// or a global coordinate mistaken for an NSWindow-local mouse event.
func popupDragOrigin(frame: NSRect, pointer: NSPoint, anchor: NSPoint, area: NSRect) -> NSPoint {
    let x = pointer.x - anchor.x
    let y = pointer.y - (frame.height - anchor.y)
    return NSPoint(x: min(max(x, area.minX), max(area.minX, area.maxX - frame.width)),
                   y: min(max(y, area.minY), max(area.minY, area.maxY - frame.height)))
}

// Event counters identify one physical press. A release followed by a new
// press must not make an old queued drag valid again merely because left is down.
func popupDragPressIdentity() -> UInt64 {
    let down = CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown)
    let up = CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseUp)
    return (UInt64(down) << 32) | UInt64(up)
}
func popupDragPressMatches(_ expected: UInt64, _ current: UInt64, _ leftDown: Bool) -> Bool {
    leftDown && expected == current
}
@_cdecl("echolingo_popup_drag_press_identity")
public func echoLingoPopupDragPressIdentity() -> UInt64 { popupDragPressIdentity() }

// checkOnly starts a gesture without moving anything. Every actual move checks
// the physical button again, so an IPC arriving after release cannot move UI.
@_cdecl("echolingo_popup_drag")
public func echoLingoPopupDrag(_ pointer: UnsafeMutableRawPointer?, _ anchorX: Double,
                               _ anchorY: Double, _ pressIdentity: UInt64, _ checkOnly: Int32) -> Int32 {
    guard Thread.isMainThread else { return -1 }
    guard let pointer,
          let window = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSWindow else { return -2 }
    guard window.isVisible, !window.isMiniaturized, popupDragFrameAllowed(window),
          popupDragPressMatches(pressIdentity, popupDragPressIdentity(), NSEvent.pressedMouseButtons & 1 != 0) else { return -3 }
    let frame = window.frame
    guard anchorX.isFinite, anchorY.isFinite, anchorX >= 0, anchorX <= frame.width,
          anchorY >= 0, anchorY <= min(48, frame.height) else { return -4 }
    guard checkOnly == 0 else { return 0 }
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? window.screen else { return -5 }
    let next = popupDragOrigin(frame: frame, pointer: mouse,
                               anchor: NSPoint(x: anchorX, y: anchorY), area: screen.visibleFrame)
    guard popupDragPressMatches(pressIdentity, popupDragPressIdentity(), NSEvent.pressedMouseButtons & 1 != 0) else { return -3 }
    if next != frame.origin { window.setFrameOrigin(next) }
    return 0
}

#if ECHOLINGO_WINDOW_FIXTURE
// Compile only for the explicit standalone fixture. It creates its own hidden
// window and calls the production C ABI above, never any user's app window.
@main
struct PopupBehaviorFixture {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: -1200, y: -1200, width: 680, height: 240),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let pointer = Unmanaged.passUnretained(window).toOpaque()
        let originalFrame = window.frame
        let visible = window.isVisible
        let key = window.isKeyWindow
        let main = window.isMainWindow
        let active = application.isActive
        var metadata = [Int64](repeating: -99, count: 8)
        let metadataResult = metadata.withUnsafeMutableBufferPointer {
            echoLingoApplicationPolicyMetadata($0.baseAddress, Int32($0.count))
        }
        let metadataPassed = metadataResult == 0 && metadata[0] == 1
            && metadata[1] == Int64(application.activationPolicy().rawValue)
            && metadata[5] == Int64(application.windows.count)
            && metadata[6] == Int64(ProcessInfo.processInfo.processIdentifier)
            && metadata[7] == 1 && echoLingoApplicationPolicyMetadata(nil, 8) == -2
            && metadata.withUnsafeMutableBufferPointer {
                echoLingoApplicationPolicyMetadata($0.baseAddress, 7) == -3
            }
        let unrelated: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle, .fullScreenDisallowsTiling]
        // These are Cocoa points, not physical pixels or a synthetic event's
        // local coordinates. Retina scale does not enter this transformation.
        let dragFrame = NSRect(x: -1200, y: 200, width: 680, height: 300)
        let dragArea = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let anchor = NSPoint(x: 140, y: 18)
        let dragGeometryPassed = popupDragOrigin(frame: dragFrame,
            pointer: NSPoint(x: -1060, y: 482), anchor: anchor, area: dragArea) == dragFrame.origin
            && popupDragOrigin(frame: dragFrame, pointer: NSPoint(x: -1000, y: 512),
                anchor: anchor, area: dragArea) == NSPoint(x: -1140, y: 230)
            && popupDragOrigin(frame: dragFrame, pointer: NSPoint(x: -2500, y: -400),
                anchor: anchor, area: dragArea) == NSPoint(x: -1920, y: -200)
            && popupDragOrigin(frame: dragFrame, pointer: NSPoint(x: 100, y: 1000),
                anchor: anchor, area: dragArea) == NSPoint(x: -680, y: 580)
            && popupDragOrigin(frame: dragFrame, pointer: NSPoint(x: 2400, y: 900),
                anchor: anchor, area: NSRect(x: 1920, y: 0, width: 2560, height: 1440)) == NSPoint(x: 2260, y: 618)
            && echoLingoPopupDrag(pointer, 100, 18, 0, 1) == -3 // hidden windows never move
            && echoLingoPopupDrag(nil, 100, 18, 0, 0) == -2
        let originalPress: UInt64 = (10 << 32) | 9
        let released: UInt64 = (10 << 32) | 10
        let newPress: UInt64 = (11 << 32) | 10
        let dragPressPassed = popupDragPressMatches(originalPress, originalPress, true)
            && !popupDragPressMatches(originalPress, originalPress, false)
            && !popupDragPressMatches(originalPress, released, false)
            && !popupDragPressMatches(originalPress, newPress, true)
        var steps = 0
        var passed = !visible && !key && !main && metadataPassed && dragGeometryPassed && dragPressPassed
        for style: NSWindow.StyleMask in [[.borderless, .resizable], [.titled, .closable, .resizable], [.borderless, .resizable]] {
            window.styleMask = style
            // A native full-screen cycle can leave normal level behind. Seed
            // that state explicitly, without entering fullscreen or showing UI.
            window.level = .normal
            window.collectionBehavior = unrelated.union([.moveToActiveSpace, .fullScreenNone])
            let frameBefore = window.frame
            let result = echoLingoEnsurePopupBehavior(pointer)
            let expected = popupCollectionBehavior(unrelated)
            passed = passed && result == 0 && window.level.rawValue > NSWindow.Level.normal.rawValue
                && window.collectionBehavior == expected && window.frame == frameBefore
                && window.isVisible == visible && window.isKeyWindow == key
                && window.isMainWindow == main && application.isActive == active
            steps += 1
        }
        // The normal production operation does not alter the current frame;
        // style changes in the fixture itself may adjust a titled frame.
        let maskBefore = window.collectionBehavior
        let frameBefore = window.frame
        let second = echoLingoEnsurePopupBehavior(pointer)
        passed = passed && second == 0 && window.collectionBehavior == maskBefore && window.frame == frameBefore
        passed = passed && echoLingoEnsurePopupBehavior(nil) == -2
        let finished = DispatchSemaphore(value: 0)
        var rejectedBackgroundCall = false
        DispatchQueue.global().async {
            rejectedBackgroundCall = echoLingoEnsurePopupBehavior(nil) == -1
                && echoLingoApplicationPolicyMetadata(nil, 8) == -1
            finished.signal()
        }
        passed = passed && finished.wait(timeout: .now() + 2) == .success && rejectedBackgroundCall
        let report: [String: Any] = [
            "popupBehaviorFixturePassed": passed,
            "popupDragGeometryPassed": dragGeometryPassed,
            "popupDragPressIdentityPassed": dragPressPassed,
            "fixtureSteps": steps,
            "levelAboveNormal": window.level.rawValue > NSWindow.Level.normal.rawValue,
            "windowVisible": window.isVisible,
            "windowKey": window.isKeyWindow,
            "windowMain": window.isMainWindow,
            "appActiveUnchanged": application.isActive == active,
            "frameUnchangedByRepair": window.frame == frameBefore,
            "initialFrameRecorded": originalFrame.width == 680 && originalFrame.height == 240,
            "backgroundCallRejected": rejectedBackgroundCall,
            "ownApplicationMetadataPassed": metadataPassed,
            "nsApplicationPolicy": metadata[1],
            "userWindowAccessed": false,
            "permissionRequested": false,
            "screenCaptured": false,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
        window.close()
        exit(passed ? 0 : 1)
    }
}
#endif

// Keep Cocoa point coordinates; no manual backing-scale multiplication. This
// preserves the top-left edge on negative-origin and mixed-DPI displays too.
func popupSizedFrame(_ current: NSRect, frameSize: NSSize) -> NSRect {
    NSRect(x: current.minX, y: current.maxY - frameSize.height,
           width: frameSize.width, height: frameSize.height)
}

// Tauri/Tao queues setContentSize even from the UI thread. Layout's reply must
// instead follow the actual mutation. This is geometry acknowledgement only:
// it does not claim WebKit has committed a painted/composited frame.
@_cdecl("echolingo_set_content_size_sync")
public func echoLingoSetContentSizeSync(_ pointer: UnsafeMutableRawPointer?,
                                      _ width: Double, _ height: Double) -> Int32 {
    guard Thread.isMainThread else { return -1 }
    guard width.isFinite, height.isFinite, width > 0, height > 0,
          width <= 100_000, height <= 100_000 else { return -3 }
    guard let pointer = pointer,
          let window = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSWindow else { return -2 }
    let frameSize = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height)).size
    let frame = popupSizedFrame(window.frame, frameSize: frameSize)
    window.setFrame(frame, display: false, animate: false)
    let actual = window.contentRect(forFrameRect: window.frame).size
    return abs(actual.width - width) <= 1 && abs(actual.height - height) <= 1 ? 0 : -4
}

// FIFO barrier behind Tao's queued style-mask change, not a delay or a paint
// claim. Ownership of context returns exactly once to the supplied callback.
@_cdecl("echolingo_after_window_changes")
public func echoLingoAfterWindowChanges(_ callback: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void,
                                       _ context: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async { callback(context) }
}

private var liveResizeObserverKey: UInt8 = 0
private final class PopupLiveResizeObserver: NSObject {
    let callback: @convention(c) (UnsafeMutableRawPointer?, Int32, Double) -> Void
    let release: @convention(c) (UnsafeMutableRawPointer?) -> Void
    let context: UnsafeMutableRawPointer?
    var tokens: [NSObjectProtocol] = []
    init(window: NSWindow,
         callback: @escaping @convention(c) (UnsafeMutableRawPointer?, Int32, Double) -> Void,
         release: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void,
         context: UnsafeMutableRawPointer?) {
        self.callback = callback; self.release = release; self.context = context
        super.init()
        for (name, phase) in [(NSWindow.willStartLiveResizeNotification, Int32(0)),
                              (NSWindow.didEndLiveResizeNotification, Int32(1))] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) {
                [weak self, weak window] _ in
                guard Thread.isMainThread, let self = self, let window = window else { return }
                self.callback(self.context, phase, window.contentRect(forFrameRect: window.frame).height)
            })
        }
    }
    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        release(context)
    }
}

@_cdecl("echolingo_observe_live_resize")
public func echoLingoObserveLiveResize(_ pointer: UnsafeMutableRawPointer?,
    _ callback: @escaping @convention(c) (UnsafeMutableRawPointer?, Int32, Double) -> Void,
    _ release: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void,
    _ context: UnsafeMutableRawPointer?) -> Int32 {
    guard Thread.isMainThread else { return -1 }
    guard let pointer = pointer,
          let window = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSWindow else { return -2 }
    if objc_getAssociatedObject(window, &liveResizeObserverKey) != nil { release(context); return 0 }
    let observer = PopupLiveResizeObserver(window: window, callback: callback, release: release, context: context)
    objc_setAssociatedObject(window, &liveResizeObserverKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return 0
}

// One-shot coordination with a genuine AppKit live resize. A didUpdate probe
// recovers a missed end notification by reading actual window state; closing
// releases the waiter as cancelled rather than applying geometry to a dead UI.
private var resizeIdleTaskKey: UInt8 = 0
private final class WindowResizeIdleTask {
    weak var window: NSWindow?
    let epoch: UInt64
    let callback: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    let context: UnsafeMutableRawPointer?
    var tokens: [NSObjectProtocol] = []
    var finished = false
    init(window: NSWindow, epoch: UInt64, callback: @escaping @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void,
         context: UnsafeMutableRawPointer?) {
        self.window = window; self.epoch = epoch; self.callback = callback; self.context = context
    }
    func start() {
        precondition(Thread.isMainThread)
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [self] _ in probe() })
        tokens.append(center.addObserver(forName: NSApplication.didUpdateNotification, object: NSApplication.shared, queue: .main) { [self] _ in probe() })
        tokens.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [self] _ in finish(closing: true) })
        probe()
    }
    func probe() {
        precondition(Thread.isMainThread)
        guard let window = window else { finish(closing: true); return }
        if !window.inLiveResize { finish(closing: false) }
    }
    func finish(closing: Bool) {
        guard !finished else { return }; finished = true
        for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens.removeAll()
        if let window = window, objc_getAssociatedObject(window, &resizeIdleTaskKey) as? WindowResizeIdleTask === self {
            objc_setAssociatedObject(window, &resizeIdleTaskKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let callback = callback, context = context
        // Invoke while the observed AppKit state is still current. Scheduling
        // another block would let a new live resize start before the callback.
        callback(context, closing ? 1 : 0)
    }
}

@_cdecl("echolingo_after_live_resize")
public func echoLingoAfterLiveResize(_ pointer: UnsafeMutableRawPointer?, _ epoch: UInt64,
    _ callback: @escaping @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void,
    _ context: UnsafeMutableRawPointer?) {
    precondition(Thread.isMainThread)
    guard let pointer = pointer,
          let window = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSWindow else {
        callback(context, 1); return
    }
    (objc_getAssociatedObject(window, &resizeIdleTaskKey) as? WindowResizeIdleTask)?.finish(closing: true)
    // Normal streamed layout allocates no waiter or notification subscriptions.
    if !window.inLiveResize { callback(context, 0); return }
    let task = WindowResizeIdleTask(window: window, epoch: epoch, callback: callback, context: context)
    objc_setAssociatedObject(window, &resizeIdleTaskKey, task, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    task.start()
}

@_cdecl("echolingo_cancel_stale_resize_wait")
public func echoLingoCancelStaleResizeWait(_ pointer: UnsafeMutableRawPointer?, _ epoch: UInt64) {
    precondition(Thread.isMainThread)
    guard let pointer = pointer,
          let window = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSWindow,
          let task = objc_getAssociatedObject(window, &resizeIdleTaskKey) as? WindowResizeIdleTask,
          task.epoch != epoch else { return }
    task.finish(closing: true)
}

private var popupNativeFrameKey: UInt8 = 0
func popupDragFrameAllowed(_ window: NSWindow) -> Bool {
    !window.styleMask.contains(.titled)
        || (objc_getAssociatedObject(window, &popupNativeFrameKey) as? NSNumber)?.boolValue == true
}

// A titled/resizable NSWindow retains AppKit's system edge resizing. Keep the
// content full-size and title controls hidden instead of using borderless UI.
// Rust sets Tao's decorations=true first, so its cache agrees with AppKit.
@_cdecl("echolingo_configure_window_frame")
public func echoLingoConfigureWindowFrame(_ pointer: UnsafeMutableRawPointer?, _ popup: Int32) -> Int32 {
    guard Thread.isMainThread else { return -1 }
    guard let pointer = pointer,
          let window = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSWindow else { return -2 }
    guard window.styleMask.contains([.titled, .resizable]) else { return -3 }
    let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
    // AppKit may change the frame while adding/removing full-size content.
    // Sizing afterwards preserves only its then-current origin, so anchor the
    // style transition itself too, including an explicit responder failure.
    defer {
        let frame = window.frame
        let origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        if frame.origin != origin { window.setFrameOrigin(origin) }
    }
    let isPopup = popup != 0
    var mask = window.styleMask
    if isPopup { mask.insert(.fullSizeContentView) } else { mask.remove(.fullSizeContentView) }
    if window.styleMask != mask {
        let responder = window.firstResponder
        window.styleMask = mask
        // Tao likewise restores its WebView responder after changing style.
        // Preserve the existing input responder; do not activate the window or
        // redirect focus to some unrelated view/field on the user's behalf.
        if let responder = responder {
            if let view = responder as? NSView, view.window !== window { return -4 }
            guard window.makeFirstResponder(responder) else { return -4 }
        }
    }
    let visibility: NSWindow.TitleVisibility = isPopup ? .hidden : .visible
    if window.titleVisibility != visibility { window.titleVisibility = visibility }
    if window.titlebarAppearsTransparent != isPopup { window.titlebarAppearsTransparent = isPopup }
    for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
        if let button = window.standardWindowButton(kind), button.isHidden != isPopup { button.isHidden = isPopup }
    }
    // The floating popup uses its explicit toolbar drag controller. Do not let
    // native transparent-title dragging compete with its original press anchor.
    if window.isMovable == isPopup { window.isMovable = !isPopup }
    if (objc_getAssociatedObject(window, &popupNativeFrameKey) as? NSNumber)?.boolValue != isPopup {
        objc_setAssociatedObject(window, &popupNativeFrameKey, NSNumber(value: isPopup), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    return 0
}
