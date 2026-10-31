// Tests only a generated, hidden own window. No screen capture, privacy prompts,
// other application access, or assertion about physical first-frame sharpness.
import AppKit
import Foundation
import WebKit

final class HiddenViewportProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 713, height: 469),
        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    var webView: WKWebView!
    let sizes = [NSSize(width: 420, height: 160), NSSize(width: 713, height: 469), NSSize(width: 640, height: 720)]
    var phase = -1
    var finished = false
    var phaseStarted = 0.0
    func start() {
        window.isReleasedWhenClosed = false
        let pointer = Unmanaged.passUnretained(window).toOpaque()
        precondition(echoLingoConfigureWindowFrame(pointer, 1) == 0)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "viewport")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        window.contentView!.addSubview(webView)
        webView.loadHTMLString("""
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0;font:14px -apple-system}p{max-width:100%}</style>
        <p>Generated hidden viewport fixture — line wrapping before reveal.</p>
        <script>function report(){window.webkit.messageHandlers.viewport.postMessage({width:innerWidth,height:innerHeight,scale:devicePixelRatio})}addEventListener('resize',report)</script>
        """, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [self] in
            if !finished { fail("hidden WKWebView did not acknowledge native viewport; do not ship a show gate on this runtime") }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { next() }
    func next() {
        phase += 1
        if phase == sizes.count {
            finished = true
            precondition(!window.isVisible && !window.isKeyWindow)
            print("PASS: hidden WKWebView acknowledges three native geometry changes before show; no physical/compositor clarity claim")
            exit(0)
        }
        let pointer = Unmanaged.passUnretained(window).toOpaque()
        let top = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let size = sizes[phase]
        phaseStarted = ProcessInfo.processInfo.systemUptime
        precondition(echoLingoSetContentSizeSync(pointer, size.width, size.height) == 0)
        precondition(window.frame.minX == top.x && window.frame.maxY == top.y)
        // JS evaluation is deliberately separate from the synchronous geometry
        // mutation: it may report the old viewport before the resize event.
        webView.evaluateJavaScript("report()") { [self] _, error in
            if let error = error { fail("cannot observe own hidden viewport: \(error)") }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard phase >= 0 && phase < sizes.count, let body = message.body as? [String: Any],
            let width = body["width"] as? Double, let height = body["height"] as? Double,
            let scale = body["scale"] as? Double else { return }
        precondition(!window.isVisible && !window.isKeyWindow)
        let expected = sizes[phase]
        guard abs(width - expected.width) <= 1 && abs(height - expected.height) <= 1
            && abs(scale - window.backingScaleFactor) < 0.01 else { return }
        guard ProcessInfo.processInfo.systemUptime - phaseStarted < 1.5 else {
            fail("hidden viewport missed the production 1.5-second failure deadline"); return
        }
        next()
    }
    func fail(_ reason: String) {
        finished = true
        FileHandle.standardError.write(Data(("FAIL: \(reason)\n").utf8))
        exit(1)
    }
}
@main struct HiddenViewportCheck {
    static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        let probe = HiddenViewportProbe()
        probe.start()
        withExtendedLifetime(probe) { NSApplication.shared.run() }
    }
}
