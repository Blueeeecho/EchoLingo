// Isolated feasibility probe, not a product change. Creates only its own hidden
// NSWindow; does not read screenshots, source apps, clipboard or permissions.
import AppKit
import Foundation

@main struct NativeFrameExperiment {
    static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 680, height: 280),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let pointer = Unmanaged.passUnretained(window).toOpaque()
        var reports: [[String: Any]] = []
        for popup in [true, false, true] {
            if popup { window.styleMask.insert(.fullSizeContentView) }
            else { window.styleMask.remove(.fullSizeContentView) }
            window.titleVisibility = popup ? .hidden : .visible
            window.titlebarAppearsTransparent = popup
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = popup
            }
            for size in [NSSize(width: 713, height: 160), NSSize(width: 713, height: 469)] {
                let top = window.frame.maxY
                let status = echoLingoSetContentSizeSync(pointer, size.width, size.height)
                let content = window.contentRect(forFrameRect: window.frame)
                let view = window.contentView!.bounds
                reports.append([
                    "popup": popup, "requestedWidth": size.width, "requestedHeight": size.height,
                    "helperStatus": status, "contentWidth": content.width, "contentHeight": content.height,
                    "viewWidth": view.width, "viewHeight": view.height,
                    "layoutHeight": window.contentLayoutRect.height, "frameHeight": window.frame.height,
                    "topPreserved": abs(window.frame.maxY - top) <= 1,
                    "titled": window.styleMask.contains(.titled), "resizable": window.styleMask.contains(.resizable),
                    "fullSize": window.styleMask.contains(.fullSizeContentView),
                    "titleHidden": window.titleVisibility == .hidden,
                    "closeButtonHidden": window.standardWindowButton(.closeButton)?.isHidden ?? true,
                    "visible": window.isVisible, "key": window.isKeyWindow,
                ])
                precondition(status == 0 && abs(content.height - size.height) <= 1)
                precondition(window.styleMask.contains([.titled, .resizable]))
                precondition(abs(window.frame.maxY - top) <= 1 && !window.isVisible && !window.isKeyWindow)
                // Distinguish contentRect from full-size NSView bounds. Do not
                // silently claim the existing borderless sizing math fits both.
            }
        }
        let data = try! JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        print("EXPERIMENT ONLY: native frame/style feasibility; no physical edge-hit or WebKit visual acceptance")
    }
}
