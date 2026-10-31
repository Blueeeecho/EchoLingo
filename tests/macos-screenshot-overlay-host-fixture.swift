// Generated native windows only: no screen pixels, TCC requests, clipboard
// content or synthetic input. Run only in an isolated desktop session.
import AppKit
import Foundation
import WebKit

private func need(_ condition: Bool, _ message: String) throws {
    if !condition { throw NativeError("OVERLAY_HOST_FIXTURE: " + message) }
}
private func emit(_ value: [String: Any]) {
    let encoded = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
    FileHandle.standardOutput.write(encoded + Data([10]))
}

// A distinct process is essential: an auxiliary window over its own app's
// fullscreen window would not prove the user's cross-application Space case.
private final class FullscreenSource: NSObject, NSWindowDelegate {
    var window: NSWindow!
    func start() {
        guard let screen = NSScreen.screens.first else { emit(["event": "error"]); exit(1) }
        window = NSWindow(contentRect: screen.frame.insetBy(dx: 80, dy: 80),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Generated fullscreen source — no user content"
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.window.toggleFullScreen(nil) }
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                DispatchQueue.main.async {
                    if line == "probe" { self.snapshot("probe") }
                    else if line == "stop" { self.window.close(); exit(0) }
                }
            }
            DispatchQueue.main.async { exit(1) }
        }
        // Bound orphan lifetime even if the fixture parent fails unexpectedly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { exit(1) }
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.snapshot("ready") }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { emit(["event": "error"]); exit(1) }
    func snapshot(_ event: String) {
        emit(["event": event, "pid": ProcessInfo.processInfo.processIdentifier,
              "window": window.windowNumber, "fullscreen": window.styleMask.contains(.fullScreen),
              "activeSpace": window.isOnActiveSpace, "visible": window.isVisible])
    }
}

private final class OverlayHostFixture: NSObject, WKNavigationDelegate {
    let owner = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 640, height: 480),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    let source = Process()
    let sourceInput = Pipe()
    let sourceOutput = Pipe()
    var received = Data()
    var sourceWindow = 0
    var pendingProbe: (() throws -> Void)?
    var completed = false
    var fullscreenVerified = false
    var stackingVerified = false

    func start() {
        owner.isReleasedWhenClosed = false
        owner.contentView = content
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)
        webView.navigationDelegate = self
        source.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        source.arguments = ["--isolated-test-session", "--fullscreen-source"]
        source.standardInput = sourceInput
        source.standardOutput = sourceOutput
        sourceOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.receive(data) }
        }
        do { try source.run() } catch { complete(false, "source-launch: \(error)"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.complete(false, "native-host-timeout")
        }
    }
    func receive(_ data: Data) {
        guard !completed else { return }
        guard !data.isEmpty else { complete(false, "source-exited"); return }
        received.append(data)
        while let newline = received.firstIndex(of: 10) {
            let line = Data(received[..<newline])
            received.removeSubrange(...newline)
            do {
                guard let state = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let event = state["event"] as? String,
                      event == "ready" || event == "probe" else {
                    throw NativeError("OVERLAY_HOST_FIXTURE: source fullscreen failed")
                }
                try need((state["pid"] as? NSNumber)?.int32Value == source.processIdentifier,
                         "source identity changed")
                try need(state["fullscreen"] as? Bool == true && state["activeSpace"] as? Bool == true
                         && state["visible"] as? Bool == true, "source left fullscreen/current Space")
                try need(NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier,
                         "generated source is no longer foreground")
                guard let number = (state["window"] as? NSNumber)?.intValue, number > 0 else {
                    throw NativeError("OVERLAY_HOST_FIXTURE: source window missing")
                }
                if event == "ready" {
                    try need(sourceWindow == 0, "duplicate source readiness")
                    sourceWindow = number
                    webView.loadHTMLString("<html><body><textarea id='text'>中文 fixture</textarea></body></html>", baseURL: nil)
                } else {
                    try need(sourceWindow == number, "source window replaced")
                    guard let continuation = pendingProbe else { throw NativeError("OVERLAY_HOST_FIXTURE: unsolicited probe") }
                    pendingProbe = nil
                    try continuation()
                }
            } catch { complete(false, String(describing: error)); return }
        }
    }
    func probe(_ continuation: @escaping () throws -> Void) {
        pendingProbe = continuation
        sourceInput.fileHandleForWriting.write(Data("probe\n".utf8))
    }
    func checkStacking(_ panel: NSPanel) throws {
        // Window IDs/PIDs/ordering are public metadata, including without
        // screen-recording permission. Never inspect/retain titles or pixels.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let overlayIndex = windows.firstIndex(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == panel.windowNumber &&
                  ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ProcessInfo.processInfo.processIdentifier
              }),
              let sourceIndex = windows.firstIndex(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == sourceWindow &&
                  ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == source.processIdentifier
              }) else { throw NativeError("OVERLAY_HOST_FIXTURE: on-screen window metadata missing") }
        try need(overlayIndex < sourceIndex, "editor is behind fullscreen source")
        try need(panel.isOnActiveSpace && panel.isVisible && !owner.isVisible, "panel Space/visibility")
        try need(panel.level == .floating, "editor floating-level policy")
        stackingVerified = true
        fullscreenVerified = true
    }
    func complete(_ ok: Bool, _ reason: String) {
        guard !completed else { return }
        completed = true
        pendingProbe = nil
        let pointer = Unmanaged.passUnretained(owner).toOpaque()
        _ = echoLingoHideScreenshotOverlay(pointer)
        owner.close()
        sourceOutput.fileHandleForReading.readabilityHandler = nil
        if source.isRunning { source.terminate(); source.waitUntilExit() }
        emit(["schema": "echolingo-macos-screenshot-overlay-host-v1", "ok": ok,
              "reason": reason, "screenCaptured": false, "permissionRequested": false,
              "clipboardWritten": false, "physicalImeTested": false,
              "fullscreenSpaceTested": fullscreenVerified, "fullscreenStackingTested": stackingVerified])
        exit(ok ? 0 : 1)
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        guard !completed else { return }
        do {
            guard let screen = NSScreen.screens.first else { throw NativeError("OVERLAY_HOST_FIXTURE: no display") }
            let frame = screen.frame
            let y = CGDisplayBounds(CGMainDisplayID()).height - frame.maxY
            let pointer = Unmanaged.passUnretained(owner).toOpaque()
            let original = content.frame
            let clipboard = NSPasteboard.general.changeCount
            try need(echoLingoPrepareScreenshotOverlay(pointer, Double(frame.minX), Double(y), Double(frame.width), Double(frame.height)) == 0, "prepare")
            guard let panel = content.window as? NSPanel else { throw NativeError("OVERLAY_HOST_FIXTURE: not a panel") }
            try need(panel.styleMask.contains(.nonactivatingPanel) && !panel.isVisible && !owner.isVisible, "prepare visibility")
            try need(abs(content.frame.width - frame.width) < 1 && abs(webView.frame.width - frame.width) < 1, "webview viewport")
            try need(echoLingoShowScreenshotOverlay(pointer, Double(frame.minX), Double(y), Double(frame.width), Double(frame.height)) == 0, "show")
            try need(panel.firstResponder === webView, "webview first responder")
            probe { [self] in
                try checkStacking(panel)
                webView.evaluateJavaScript("document.getElementById('text').focus(); [innerWidth, innerHeight, document.activeElement.id]") { [weak self] result, error in
                    guard let self = self, !self.completed else { return }
                    do {
                        guard let values = result as? [Any], values.count == 3,
                              let width = values[0] as? Double, let height = values[1] as? Double else {
                            throw NativeError("OVERLAY_HOST_FIXTURE: viewport JS failed \(String(describing: error))")
                        }
                        try need(abs(width - frame.width) < 1 && abs(height - frame.height) < 1 && (values[2] as? String) == "text", "layout/focus")
                        try need(echoLingoHideScreenshotOverlay(pointer) == 0, "hide")
                        try need(self.content.window === self.owner && self.content.frame == original && !panel.isVisible, "restore")
                        try need(echoLingoHideScreenshotOverlay(pointer) == 0, "idempotent hide")
                        try need(echoLingoPrepareScreenshotOverlay(pointer, Double(frame.minX), Double(y), Double(frame.width), Double(frame.height)) == 0, "repeat prepare")
                        try need(echoLingoShowScreenshotOverlay(pointer, Double(frame.minX), Double(y), Double(frame.width), Double(frame.height)) == 0, "repeat show")
                        guard let repeatedPanel = self.content.window as? NSPanel else { throw NativeError("OVERLAY_HOST_FIXTURE: repeated panel missing") }
                        self.probe {
                            try self.checkStacking(repeatedPanel)
                            self.owner.close()
                            try need(self.content.window === self.owner && !NSApp.windows.contains(where: { $0 is NSPanel && $0.isVisible }), "owner-close cleanup")
                            try need(NSPasteboard.general.changeCount == clipboard, "clipboard changed")
                            self.complete(true, "host-lifecycle-and-generated-fullscreen-passed")
                        }
                    } catch { self.complete(false, String(describing: error)) }
                }
            }
        } catch { complete(false, String(describing: error)) }
    }
}

@main
private struct OverlayHostFixtureMain {
    static func main() {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" || CommandLine.arguments.contains("--isolated-test-session") else {
            FileHandle.standardError.write(Data("ISOLATION_REQUIRED\n".utf8)); exit(2)
        }
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--fullscreen-source") {
            application.setActivationPolicy(.regular)
            let source = FullscreenSource()
            DispatchQueue.main.async { source.start() }
            application.run()
            withExtendedLifetime(source) {}
        } else {
            application.setActivationPolicy(.accessory)
            let fixture = OverlayHostFixture()
            DispatchQueue.main.async { fixture.start() }
            application.run()
            withExtendedLifetime(fixture) {}
        }
    }
}
