// Local NSApplication dispatch through the production monitor with a WKWebView.
// Constructed NSEvents + injected physical state: not hardware/Window Server acceptance.
// No event posting, event tap, permissions, private text or general pasteboard.
import AppKit
import WebKit
private var epoch: UInt64 = 1
private var token: UInt64 = 0
private var serial: UInt64 = 0
private var downs = 0
private var stopped: Int32 = 0
private var physical = HeaderDragInput(pointer: .zero, press: 1, leftDown: false)
private func routeCallback(_ context: UnsafeMutableRawPointer?, _ action: Int32, _ e: UInt64, _ id: UInt64,
                           _ press: UInt64, _ x: Double, _ y: Double, _ reason: Int32) -> UInt64 {
    if action == 3 && reason == 20 { downs += 1 }
    if action == 0 { guard e == epoch else { return 0 }; serial += 1; token = serial; return token }
    if action == 1 { return e != epoch ? 2 : token == id ? 1 : 6 }
    if action == 2 && token == id { token = 0; stopped = reason }
    return 0
}
@main struct HeaderEventRouteFixture {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 520, height: 400), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isMovable = false // Same explicit policy as the production popup.
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
        window.contentView = web
        web.loadHTMLString("<p id='source'>A neutral selected sentence.</p><p id='result'>A neutral result.</p><button>Action</button>", baseURL: nil)
        window.orderFrontRegardless()
        let observer = PopupHeaderDragObserver(window: window, callback: routeCallback, release: { _ in }, context: nil)
        observer.input = { physical }
        observer.configure(revision: 1, epoch: epoch, region: NSRect(x: 40, y: 0, width: 400, height: 28), viewport: web.bounds.size)
        func javascript(_ code: String) {
            var done = false; var failed = false
            web.evaluateJavaScript(code) { _, error in failed = error != nil; done = true }
            let deadline = Date().addingTimeInterval(10)
            while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            precondition(done && !failed, "WKWebView fixture script failed")
        }
        let deadline = Date().addingTimeInterval(10)
        while web.isLoading && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        javascript("document.readyState")
        func dispatch(_ type: NSEvent.EventType, top: Double) {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 180, y: web.bounds.height-top), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: Int(serial+1), clickCount: 1, pressure: 1)!
            app.sendEvent(event) // Exercises local monitor installation, not observer.event directly.
        }
        for element in ["source", "result"] {
            javascript("getSelection().selectAllChildren(document.getElementById('\(element)'))")
            physical.leftDown = false; dispatch(.leftMouseUp, top: 80)
            precondition(token == 0)
            window.resignKey() // Non-key fixture; cannot claim OS first-click activation behavior.
            physical.press += 1; physical.leftDown = true
            physical.pointer = window.convertPoint(toScreen: NSPoint(x: 180, y: web.bounds.height-14))
            let before = window.frame.origin; let previousDowns = downs
            dispatch(.leftMouseDown, top: 14)
            precondition(downs == previousDowns+1 && token != 0, "NSApplication route missed production monitor")
            let held = token
            for index in 1...5 {
                javascript("document.getElementById('result').textContent += ' Neutral streamed result.'")
                observer.configure(revision: UInt64(serial*10+index), epoch: epoch, region: NSRect(x: 40, y: 0, width: 400, height: 28), viewport: web.bounds.size)
                physical.pointer.x += 12
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                precondition(token == held)
            }
            precondition(window.frame.origin != before)
            physical.leftDown = false; dispatch(.leftMouseUp, top: 14)
            observer.sample(); precondition(token == 0 && stopped == HeaderDragStop.released.rawValue)
            let released = window.frame; physical.pointer.x += 100; observer.sample()
            precondition(window.frame == released)
        }
        window.close()
        print("{\"ok\":true,\"scope\":\"NSApplication.sendEvent + WKWebView + production local monitor, injected physical samples\",\"windowServerDragTested\":false,\"physicalMac\":false,\"inputPosted\":false,\"permissionsChanged\":false}")
    }
}
