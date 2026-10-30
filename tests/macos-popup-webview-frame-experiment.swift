// Own-window WebKit feasibility probe. No screenshots of other apps, global
// event hooks, translation requests, clipboard access or privacy prompts.
import AppKit
import Foundation
import WebKit

final class ProbeWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class WebViewFrameProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 713, height: 469),
                          styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    var webView: ProbeWebView!
    var finished = false
    var typing = false
    func start() {
        window.isReleasedWhenClosed = false
        let pointer = Unmanaged.passUnretained(window).toOpaque()
        precondition(echoLingoConfigureWindowFrame(pointer, 1) == 0)
        precondition(echoLingoSetContentSizeSync(pointer, 713, 469) == 0)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "probe")
        webView = ProbeWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        window.contentView!.addSubview(webView)
        window.orderFrontRegardless()
        precondition(!window.isKeyWindow)
        webView.loadHTMLString("""
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>
        *{box-sizing:border-box}html,body{margin:0;background:white;font:14px -apple-system}
        header{height:36px;background:#f5f1ff}button{position:absolute;left:8px;top:4px;width:48px;height:28px}
        main{padding:8px}#result{border:1px solid #eee;padding:12px}
        </style><header><button id="pin">固定</button></header><main>明白<input id="typing" aria-label="Own keyboard fixture"><div id="result">Clear</div></main>
        <script>document.querySelector('#pin').addEventListener('click',()=>window.webkit.messageHandlers.probe.postMessage({clicked:true,width:innerWidth,height:innerHeight,top:document.querySelector('header').getBoundingClientRect().top}));document.querySelector('#typing').addEventListener('input',event=>window.webkit.messageHandlers.probe.postMessage({typed:event.target.value}));</script>
        """, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [self] in
            if !finished { fail("own-window toolbar click or post-transition keyboard input was not delivered; do not infer real edge support") }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("({width:innerWidth,height:innerHeight,top:document.querySelector('header').getBoundingClientRect().top})") { [self] value, error in
            guard error == nil, let metrics = value as? [String: Any],
                  (metrics["width"] as? Int) == 713, (metrics["height"] as? Int) == 469,
                  (metrics["top"] as? Int) == 0 else { fail("WebKit viewport does not fill native full-size content: \(String(describing: value))"); return }
            let point = NSPoint(x: 32, y: window.frame.height - 18)
            // Deliver only to this fixture's NSWindow through AppKit's event
            // queue; never post global CGEvents or target another application.
            let events: [(NSEvent.EventType, Int)] = [(.leftMouseDown, 1), (.leftMouseUp, 2)]
            for (type, number) in events {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: number, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { fail("cannot construct own-window mouse event"); return }
                NSApplication.shared.postEvent(event, atStart: false)
            }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["clicked"] as? Bool == true && !typing {
            typing = true
            // This phase models an explicit input action, unlike passive show.
            window.makeKeyAndOrderFront(nil)
            precondition(window.makeFirstResponder(webView))
            webView.evaluateJavaScript("document.querySelector('#typing').focus()") { [self] _, error in
                guard error == nil, let responder = window.firstResponder else { fail("input responder missing"); return }
                let pointer = Unmanaged.passUnretained(window).toOpaque()
                let top = NSPoint(x: window.frame.minX, y: window.frame.maxY)
                for popup: Int32 in [0, 1] {
                    guard echoLingoConfigureWindowFrame(pointer, popup) == 0,
                          window.firstResponder === responder else { fail("style transition lost the original WebKit responder"); return }
                }
                precondition(echoLingoSetContentSizeSync(pointer, 713, 469) == 0)
                precondition(abs(window.frame.minX - top.x) <= 1 && abs(window.frame.maxY - top.y) <= 1)
                for type: NSEvent.EventType in [.keyDown, .keyUp] {
                    let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7)!
                    NSApplication.shared.postEvent(event, atStart: false)
                }
            }
            return
        }
        guard typing, body["typed"] as? String == "x" else { return }
        finished = true
        print("PASS EXPERIMENT: production native frame; WebKit viewport 713x469/header y0; own AppKit toolbar click and typed x survive management/popup style transitions")
        print("NOT VERIFIED: WindowServer external resize hit width, physical pointer dragging, installed-app first frame")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "probe")
        exit(0)
    }
    func fail(_ message: String) {
        finished = true
        FileHandle.standardError.write(Data(("FAIL EXPERIMENT: " + message + "\n").utf8))
        exit(1)
    }
}
@main struct WebViewFrameExperiment {
    static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        let probe = WebViewFrameProbe()
        probe.start()
        withExtendedLifetime(probe) { NSApplication.shared.run() }
    }
}
