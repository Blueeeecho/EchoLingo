// Same native observer/timer and real owned NSWindow, injected physical samples.
// No input posting, global event tap, TCC changes, screen capture or user content.
import AppKit
import Foundation
private var fixtureEpoch: UInt64 = 7
private var currentToken: UInt64 = 0
private var nextToken: UInt64 = 0
private var stops: [Int32] = []
private var physical = HeaderDragInput(pointer: .zero, press: 1, leftDown: true)
private func callback(_ context: UnsafeMutableRawPointer?, _ action: Int32, _ epoch: UInt64, _ id: UInt64,
                      _ press: UInt64, _ x: Double, _ y: Double, _ reason: Int32) -> UInt64 {
    if action == 0 { guard epoch == fixtureEpoch else { return 0 }; nextToken += 1; currentToken = nextToken; return currentToken }
    if action == 1 { return epoch != fixtureEpoch ? 2 : id == currentToken ? 1 : 6 }
    if action == 2 && id == currentToken { currentToken = 0; stops.append(reason) }
    return 0
}
@main struct HeaderDragFixture {
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main else { fatalError("No fixture screen") }
        let area = screen.visibleFrame
        let frame = NSRect(x: area.minX + 100, y: area.minY + 100, width: 320, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.orderFront(nil)
        let observer = PopupHeaderDragObserver(window: window, callback: callback, release: { _ in }, context: nil)
        observer.input = { physical }
        let region = NSRect(x: 40, y: 0, width: 200, height: 28)
        observer.configure(revision: 1, epoch: 7, region: region, viewport: window.contentView!.bounds.size)
        func event(_ type: NSEvent.EventType, x: Double = 100, top: Double = 14) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: window.contentView!.bounds.height - top), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func press(initialDelta: Double = 0) {
            physical.press += 1; physical.leftDown = true
            physical.pointer = NSPoint(x: window.frame.minX + 100 + initialDelta, y: window.frame.maxY - 14)
            precondition(observer.event(event(.leftMouseDown)) == nil)
        }
        func sample(dx: Double, dy: Double = 0) { physical.pointer.x += dx; physical.pointer.y += dy; observer.sample() }
        // Prepared hidden epoch -> native resume -> first grab, without a DOM reply.
        observer.adoptPresentation(previous: 7, next: 8); fixtureEpoch = 8
        press(); physical.leftDown = false; observer.sample()
        observer.adoptPresentation(previous: 7, next: 9) // Stale show cannot rebind current region.
        precondition(observer.epoch == 8)
        observer.adoptPresentation(previous: 8, next: 7) // No backwards adoption.
        precondition(observer.epoch == 8)
        // A queued original down followed by release/new press cannot arm.
        physical.leftDown = true
        physical.lastReleaseTime = ProcessInfo.processInfo.systemUptime + 1
        precondition(observer.event(event(.leftMouseDown)) != nil && observer.machine.id == 0)
        physical.lastReleaseTime = -.infinity
        // Text/source/result presses and released selections never become window drag.
        for top in [60.0, 140.0] {
            precondition(observer.event(event(.leftMouseDown, top: top)) != nil)
            precondition(observer.machine.id == 0)
            precondition(observer.event(event(.leftMouseUp, top: top)) != nil)
            press(); let before = window.frame.origin; sample(dx: 20); precondition(window.frame.origin != before)
            physical.leftDown = false; observer.sample(); precondition(observer.machine.id == 0)
        }
        // Fast movement already occurred before native down dispatch.
        let beforeDelayedDown = window.frame.origin
        press(initialDelta: 40); observer.sample()
        precondition(window.frame.origin != beforeDelayedDown)
        physical.leftDown = false; observer.sample()
        // Result-driven height changes retain the same top-relative header and width.
        window.setContentSize(NSSize(width: 320, height: 240))
        press(); let begin = window.frame.origin
        let heldToken = observer.machine.id
        observer.configure(revision: 2, epoch: fixtureEpoch, region: region, viewport: window.contentView!.bounds.size)
        precondition(observer.machine.id == heldToken)
        _ = observer.event(event(.leftMouseUp)) // Old queued up while the same physical press is still down.
        precondition(observer.machine.id == heldToken)
        sample(dx: 2); precondition(window.frame.origin == begin)
        sample(dx: 40); precondition(window.frame.origin != begin)
        // No DOM events/IPC/rAF are delivered while the actual native timer runs.
        physical.pointer.x += 70
        let prior = window.frame.origin
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        precondition(window.frame.origin != prior)
        window.resignKey(); sample(dx: 10) // Key/WebView focus is not a physical release.
        // Far beyond the starting WebView, clamp, then reverse while still held.
        physical.pointer.x = area.maxX + 500; observer.sample()
        precondition(abs(window.frame.maxX - area.maxX) < 1 && observer.machine.id != 0)
        physical.pointer.x = area.maxX - 250; observer.sample(); precondition(window.frame.maxX < area.maxX)
        let releasedFrame = window.frame
        physical.leftDown = false; sample(dx: 100); precondition(window.frame == releasedFrame && stops.last == HeaderDragStop.released.rawValue)
        press(); physical.press += 1; let beforeReplacement = window.frame; sample(dx: 60)
        precondition(window.frame == beforeReplacement && stops.last == HeaderDragStop.replaced.rawValue)
        press(); fixtureEpoch += 1; let beforeEpoch = window.frame; sample(dx: 60)
        precondition(window.frame == beforeEpoch && stops.last == HeaderDragStop.presentation.rawValue)
        observer.configure(revision: 3, epoch: fixtureEpoch, region: region, viewport: window.contentView!.bounds.size)
        press(); observer.configure(revision: 4, epoch: fixtureEpoch, region: .zero, viewport: window.contentView!.bounds.size)
        precondition(stops.last == HeaderDragStop.disabled.rawValue)
        observer.configure(revision: 3, epoch: fixtureEpoch, region: region, viewport: window.contentView!.bounds.size)
        precondition(observer.region.isEmpty) // Late pre-modal config cannot re-enable.
        observer.configure(revision: 5, epoch: fixtureEpoch, region: region, viewport: window.contentView!.bounds.size)
        press(); window.orderOut(nil); observer.sample(); precondition(stops.last == HeaderDragStop.hidden.rawValue)
        window.orderFront(nil)
        for x in [1.0, 2.0, 318.0, 319.0] {
            precondition(observer.event(event(.leftMouseDown, x: x, top: 30)) != nil && observer.machine.id == 0)
        }
        window.orderOut(nil)
        print("{\"ok\":true,\"scope\":\"real owned NSWindow and AppKit timer with injected physical samples; not physical device\",\"nativeTimerWithoutWebViewPassed\":true,\"selectionThenHeaderPassed\":true,\"releaseReplacementEpochModalHidePassed\":true,\"clampReversePassed\":true,\"edgeIsolationPassed\":true,\"inputPosted\":false,\"permissionsChanged\":false}")
    }
}
