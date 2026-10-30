// Routed AppKit edge probe: events are addressed ONLY to this fixture window.
// This cannot prove WindowServer outside-edge targeting or physical hit width.
import AppKit
import Foundation

final class NativeEdgeProbe {
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 300),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    var monitor: Any?
    var index = 0
    var before = NSRect.zero
    var completed = false
    var pendingMouseUp = false
    var settlingCase: Int?
    var idleObservers: [NSObjectProtocol] = []
    let cases: [(String, NSPoint, NSPoint)] = [
        ("west-inside-1", NSPoint(x: 1, y: 150), NSPoint(x: -20, y: 150)),
        ("west-exact", NSPoint(x: 0, y: 150), NSPoint(x: -20, y: 150)),
        ("west-outside-1-routed", NSPoint(x: -1, y: 150), NSPoint(x: -20, y: 150)),
        ("east-inside-1", NSPoint(x: 499, y: 150), NSPoint(x: 520, y: 150)),
        ("south-inside-1", NSPoint(x: 250, y: 1), NSPoint(x: 250, y: -20)),
        ("north-inside-1", NSPoint(x: 250, y: 299), NSPoint(x: 250, y: 320))
    ]
    func start() {
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 160, height: 100)
        let pointer = Unmanaged.passUnretained(window).toOpaque()
        precondition(echoLingoConfigureWindowFrame(pointer, 1) == 0)
        precondition(echoLingoSetContentSizeSync(pointer, 500, 300) == 0)
        window.orderFrontRegardless()
        // Local application event monitor, never a global input hook. AppKit
        // tracking loops may consume mouse-up without calling NSWindow.sendEvent.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self, self.pendingMouseUp, event.windowNumber == self.window.windowNumber,
                  event.eventNumber == self.index * 3 + 2 else { return event }
            self.pendingMouseUp = false
            let expectedIndex = self.index
            DispatchQueue.main.async { self.recordAndAdvance(expectedIndex: expectedIndex) }
            return event
        }
        for (name, object) in [(NSWindow.didEndLiveResizeNotification, window as AnyObject?),
                               (NSApplication.didUpdateNotification, nil)] {
            idleObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                guard Thread.isMainThread, let self, let expectedIndex = self.settlingCase else { return }
                self.recordAndAdvance(expectedIndex: expectedIndex)
            })
        }
        DispatchQueue.main.async { self.runCase() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [self] in
            if !completed {
                FileHandle.standardError.write(Data("FAIL edge probe: own-window event sequence did not finish\n".utf8))
                exit(1)
            }
        }
    }
    func runCase() {
        guard index < cases.count else {
            completed = true
            if let monitor { NSEvent.removeMonitor(monitor) }
            for observer in idleObservers { NotificationCenter.default.removeObserver(observer) }
            print("NOT VERIFIED: WindowServer event targeting outside the frame, physical resize usability, or an 8px external hit region. Routed synthetic non-resize is inconclusive.")
            exit(0)
        }
        window.setFrame(NSRect(x: 200, y: 200, width: 500, height: 300), display: true)
        before = window.frame
        let (_, down, dragged) = cases[index]
        pendingMouseUp = true
        let sequence: [(NSEvent.EventType, NSPoint)] = [(.leftMouseDown, down), (.leftMouseDragged, dragged), (.leftMouseUp, dragged)]
        for (offset, item) in sequence.enumerated() {
            let event = NSEvent.mouseEvent(with: item.0, location: item.1, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + Double(offset) * 0.01,
                windowNumber: window.windowNumber, context: nil, eventNumber: index * 3 + offset,
                clickCount: 1, pressure: item.0 == .leftMouseUp ? 0 : 1)!
            NSApplication.shared.postEvent(event, atStart: false)
        }
    }
    func recordAndAdvance(expectedIndex: Int) {
        guard !completed, index == expectedIndex, index < cases.count else { return }
        // A local monitor runs before dispatch. Nested tracking may still be
        // active on the async turn; never measure/reset its frame until idle.
        guard !window.inLiveResize else { settlingCase = expectedIndex; return }
        settlingCase = nil
        let after = window.frame
        let resized = abs(after.width - before.width) > 1 || abs(after.height - before.height) > 1
        let record: [String: Any] = ["case": cases[index].0, "routedToOwnWindow": true,
            "nativeResized": resized, "before": NSStringFromRect(before), "after": NSStringFromRect(after),
            "physicalOutsideTargetingVerified": false]
        let json = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print(String(data: json, encoding: .utf8)!)
        index += 1
        DispatchQueue.main.async { self.runCase() }
    }
}
@main struct NativeEdgeExperiment {
    static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        let probe = NativeEdgeProbe()
        probe.start()
        withExtendedLifetime(probe) { NSApplication.shared.run() }
    }
}
