// Explicit development fixture. --selector-preview uses the production selector
// and returns geometry only: no desktop pixels, OCR, credentials or API request.
// --host creates a separate synthetic source process for native fullscreen tests.
import AppKit
import Foundation

private final class FullscreenSourceView: NSView {
    var tick = 0
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let text = "EchoLingo fullscreen source fixture\n\nSelect this English test sentence.\nSynthetic content only — 12345\n\nLive counter: \(tick)"
        text.draw(in: bounds.insetBy(dx: 80, dy: 100), withAttributes: [
            .font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black,
        ])
    }
}

@main
struct FullscreenSelectorFixture {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        func value(_ flag: String, fallback: String) -> String {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return fallback }
            return arguments[index + 1]
        }
        let mode = value("--mode", fallback: "hidden-self-test")
        let policyName = value("--policy", fallback: "accessory")
        guard ["hidden-self-test", "selector-preview", "host"].contains(mode),
              ["regular", "accessory"].contains(policyName),
              let delay = Double(value("--delay", fallback: "3")), delay.isFinite, (0...30).contains(delay) else {
            fputs("Expected --mode hidden-self-test|selector-preview|host --policy regular|accessory --delay 0...30 [--report absolute.json].\n", stderr)
            exit(2)
        }
        let reportPath = value("--report", fallback: "")
        if !reportPath.isEmpty && (!reportPath.hasPrefix("/") || !reportPath.hasSuffix(".json")) {
            fputs("The optional report must be an absolute .json path in an existing fixture directory.\n", stderr)
            exit(2)
        }
        let reportURL = reportPath.isEmpty ? nil : URL(fileURLWithPath: reportPath)
        let application = NSApplication.shared
        let policy: NSApplication.ActivationPolicy = policyName == "accessory" ? .accessory : .regular
        let policyAccepted = application.setActivationPolicy(policy)
        guard policyAccepted || application.activationPolicy() == policy else {
            fputs("Could not set this fixture process's activation policy.\n", stderr)
            exit(1)
        }
        func report(_ fields: [String: Any], terminal: Bool = false) {
            var record = fields
            record["mode"] = mode
            record["requestedPolicy"] = policyName
            record["actualPolicy"] = application.activationPolicy().rawValue
            record["fixturePid"] = ProcessInfo.processInfo.processIdentifier
            record["applicationActive"] = application.isActive
            record["frontmostIsFixtureProcess"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            record["screenCaptured"] = false
            record["permissionRequested"] = false
            record["credentialsRead"] = false
            guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
            if let reportURL = reportURL { try? data.write(to: reportURL, options: .atomic) }
            if terminal {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([10]))
            }
        }
        func panelMetadata() -> [[String: Any]] {
            application.windows.compactMap { window in
                guard let panel = window as? CaptureSelectionPanel else { return nil }
                return ["windowNumber": panel.windowNumber, "level": panel.level.rawValue,
                        "collectionBehavior": panel.collectionBehavior.rawValue,
                        "visible": panel.isVisible, "onActiveSpace": panel.isOnActiveSpace,
                        "key": panel.isKeyWindow, "main": panel.isMainWindow,
                        "nonactivating": panel.styleMask.contains(.nonactivatingPanel),
                        "floatingPanel": panel.isFloatingPanel,
                        "highlighted": (panel.contentView as? CaptureSelectionView)?.highlighted ?? false,
                        "frame": ["x": panel.frame.minX, "y": panel.frame.minY,
                                  "width": panel.frame.width, "height": panel.frame.height]]
            }
        }
        if mode == "hidden-self-test" {
            do {
                try captureOverlayBehaviorSelfTest()
                let panel = CaptureSelectionPanel(contentRect: NSRect(x: -2000, y: -2000, width: 300, height: 200),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                let before = panel.frame
                let activeBefore = application.isActive
                configureCaptureSelectionPanel(panel)
                let expected = popupCollectionBehavior([.stationary, .ignoresCycle])
                let passed = !panel.isVisible && !panel.isKeyWindow && !panel.isMainWindow
                    && panel.frame == before && application.isActive == activeBefore
                    && panel.level == .screenSaver && panel.collectionBehavior == expected
                    && panel.isFloatingPanel && !panel.hidesOnDeactivate
                    && panel.styleMask.contains(.nonactivatingPanel) && panel.sharingType == .none
                report(["phase": "completed", "overlayPolicyFixturePassed": passed,
                        "productionPanelConfigured": true, "panels": panelMetadata(),
                        "userWindowAccessed": false], terminal: true)
                panel.close()
                exit(passed ? 0 : 1)
            } catch {
                report(["phase": "failed", "error": String(describing: error)], terminal: true)
                exit(1)
            }
        }
        if mode == "host" {
            // The root agent explicitly starts/operates this fixture process.
            // Its full-screen state is native AppKit, not a borderless imitation.
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1000, height: 700),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "EchoLingo synthetic fullscreen test"
            window.collectionBehavior = [.fullScreenPrimary]
            let view = FullscreenSourceView(frame: NSRect(origin: .zero, size: window.frame.size))
            window.contentView = view
            DispatchQueue.main.async {
                application.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.toggleFullScreen(nil)
            }
            let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
                DispatchQueue.main.async {
                    view.tick += 1
                    view.needsDisplay = true
                    report(["phase": "host", "nativeFullscreen": window.styleMask.contains(.fullScreen),
                            "visible": window.isVisible, "onActiveSpace": window.isOnActiveSpace,
                            "liveCounter": view.tick])
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            DispatchQueue.main.asyncAfter(deadline: .now() + 180) { application.terminate(nil) }
            application.run()
            return
        }
        var latestPanels: [[String: Any]] = []
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async {
                let current = panelMetadata()
                if !current.isEmpty { latestPanels = current }
                report(["phase": current.isEmpty ? "queued" : "selecting", "panels": current])
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            let result = Result { try selectNativeCaptureRegion() }
            DispatchQueue.main.async {
                timer.invalidate()
                var fields: [String: Any] = ["panelsAfter": panelMetadata(), "lastArmedPanels": latestPanels]
                var status: Int32 = 0
                switch result {
                case .success(let plan):
                    fields["phase"] = "selected"
                    fields["region"] = ["x": plan.region.minX, "y": plan.region.minY,
                                        "width": plan.region.width, "height": plan.region.height]
                case .failure(let error):
                    let message = String(describing: error)
                    fields["phase"] = message.contains("CANCELLED:") ? "cancelled" : "failed"
                    fields["error"] = message
                    if fields["phase"] as? String == "failed" { status = 1 }
                }
                report(fields, terminal: true)
                exit(status)
            }
        }
        application.run()
    }
}
