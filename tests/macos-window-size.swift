import AppKit
import Foundation

// Deterministic own-window fixture: exercise notification ordering while
// overriding only AppKit's read-only live-resize state, not production code.
final class ResizeStateWindow: NSWindow {
    var fixtureLiveResize = false
    override var inLiveResize: Bool { fixtureLiveResize }
}

@main struct WindowSizeChecks {
    static func trace(_ value: String) { FileHandle.standardError.write(Data(("geometry-check: " + value + "\n").utf8)) }
    static var observedPhases: [Int32] = []
    static var releasedContexts = 0
    static var idleResults: [Int32] = []
    static func main() {
        trace("before NSApplication.shared")
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        trace("after NSApplication.shared")
        precondition(Thread.isMainThread)
        for style: NSWindow.StyleMask in [[], [.titled, .resizable]] {
            trace("create style \(style.rawValue)")
            let window = NSWindow(contentRect: NSRect(x: -900, y: 140, width: 680, height: 240),
                                  styleMask: style, backing: .buffered, defer: false)
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            for size in [NSSize(width: 713, height: 469), NSSize(width: 713, height: 160),
                         NSSize(width: 420, height: 300), NSSize(width: 713, height: 469)] {
                trace("before size \(size)")
                precondition(echoLingoSetContentSizeSync(pointer, size.width, size.height) == 0)
                trace("after size \(size)")
                // No dispatch/runloop turn is allowed between call and readback.
                let actual = window.contentRect(forFrameRect: window.frame).size
                precondition(abs(actual.width - size.width) <= 1 && abs(actual.height - size.height) <= 1)
                precondition(abs(window.frame.minX - topLeft.x) <= 1 && abs(window.frame.maxY - topLeft.y) <= 1)
                precondition(!window.isVisible && !window.isKeyWindow)
            }
            trace("before invalid inputs")
            let before = window.frame
            for width in [Double.nan, Double.infinity, -1, 0, 100_001] {
                precondition(echoLingoSetContentSizeSync(pointer, width, 240) == -3)
                precondition(window.frame == before)
            }
        }
        precondition(echoLingoSetContentSizeSync(nil, 680, 240) == -2)
        trace("create transition window")
        let observedWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 280),
                                      styleMask: [.resizable], backing: .buffered, defer: false)
        let observedPointer = Unmanaged.passUnretained(observedWindow).toOpaque()
        precondition(echoLingoObserveLiveResize(observedPointer, { _, phase, _ in
            WindowSizeChecks.observedPhases.append(phase)
        }, { _ in WindowSizeChecks.releasedContexts += 1 }, nil) == 0)
        precondition(echoLingoSetContentSizeSync(observedPointer, 713, 469) == 0)
        precondition(observedPhases.isEmpty, "Programmatic resizing must not be mistaken for a live user gesture")
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: observedWindow)
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: observedWindow)
        precondition(observedPhases == [0, 1])
        precondition(echoLingoObserveLiveResize(observedPointer, { _, _, _ in
            preconditionFailure("Duplicate observer must not be installed")
        }, { _ in WindowSizeChecks.releasedContexts += 1 }, nil) == 0)
        precondition(releasedContexts == 1)
        observedPhases = []
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: observedWindow)
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: observedWindow)
        precondition(observedPhases == [0, 1])
        let idleWindow = ResizeStateWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 280),
                                           styleMask: [.resizable], backing: .buffered, defer: false)
        let idlePointer = Unmanaged.passUnretained(idleWindow).toOpaque()
        idleWindow.fixtureLiveResize = true
        echoLingoAfterLiveResize(idlePointer, 10, { _, status in WindowSizeChecks.idleResults.append(status) }, nil)
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: NSApplication.shared)
        precondition(idleResults.isEmpty)
        // Latest same-epoch layout replaces, cancels and releases the former.
        echoLingoAfterLiveResize(idlePointer, 10, { _, status in WindowSizeChecks.idleResults.append(status) }, nil)
        precondition(idleResults == [1])
        // A hidden/closed/new-source epoch cancels without waiting for an end.
        echoLingoCancelStaleResizeWait(idlePointer, 11)
        precondition(idleResults == [1, 1])
        echoLingoAfterLiveResize(idlePointer, 11, { _, status in WindowSizeChecks.idleResults.append(status) }, nil)
        // Lost didEnd is recovered from actual state on the next AppKit update.
        idleWindow.fixtureLiveResize = false
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: NSApplication.shared)
        precondition(idleResults == [1, 1, 0])
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: idleWindow)
        precondition(idleResults == [1, 1, 0], "Completion is exactly once")
        idleWindow.fixtureLiveResize = true
        echoLingoAfterLiveResize(idlePointer, 12, { _, status in WindowSizeChecks.idleResults.append(status) }, nil)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: idleWindow)
        precondition(idleResults == [1, 1, 0, 1])
        // An already idle window does not install a permanent waiter.
        idleWindow.fixtureLiveResize = false
        echoLingoAfterLiveResize(idlePointer, 13, { _, status in WindowSizeChecks.idleResults.append(status) }, nil)
        precondition(idleResults == [1, 1, 0, 1, 0])
        let transitionWindow = NSWindow(contentRect: NSRect(x: -500, y: 140, width: 680, height: 480),
                                        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let context = Unmanaged.passRetained(transitionWindow).toOpaque()
        // Reproduce Tao's FIFO style change rather than testing a fixed style.
        DispatchQueue.main.async { precondition(Thread.isMainThread); transitionWindow.styleMask = [.resizable] }
        echoLingoAfterWindowChanges({ context in
            WindowSizeChecks.trace("first FIFO continuation main=\(Thread.isMainThread)")
            let window = Unmanaged<NSWindow>.fromOpaque(context!).takeUnretainedValue()
            precondition(!window.styleMask.contains(.titled))
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            precondition(echoLingoSetContentSizeSync(context, 713, 160) == 0)
            precondition(window.contentRect(forFrameRect: window.frame).height == 160)
            precondition(window.frame.minX == topLeft.x && window.frame.maxY == topLeft.y)
            precondition(!window.isVisible && !window.isKeyWindow)
            DispatchQueue.main.async { precondition(Thread.isMainThread); window.styleMask = [.titled, .resizable] }
            echoLingoAfterWindowChanges({ context in
                WindowSizeChecks.trace("second FIFO continuation main=\(Thread.isMainThread)")
                let window = Unmanaged<NSWindow>.fromOpaque(context!).takeRetainedValue()
                precondition(window.styleMask.contains(.titled))
                let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
                precondition(echoLingoSetContentSizeSync(context, 640, 720) == 0)
                precondition(window.contentRect(forFrameRect: window.frame).height == 720)
                precondition(window.frame.minX == topLeft.x && window.frame.maxY == topLeft.y)
                precondition(!window.isVisible && !window.isKeyWindow)
                print("PASS: synchronous geometry and FIFO style transitions; no show/focus")
                exit(0)
            }, context)
        }, context)
        // dispatchMain terminates the main thread on this macOS runtime;
        // AppKit's next style update then runs on a libdispatch worker. Use the
        // same live application run loop as Tauri, not a command-line drain.
        trace("enter NSApplication.run")
        NSApplication.shared.run()
    }
}
