import AppKit
import Foundation

@main struct WindowSizeChecks {
    static func main() {
        _ = NSApplication.shared
        precondition(Thread.isMainThread)
        for style: NSWindow.StyleMask in [[], [.titled, .resizable]] {
            let window = NSWindow(contentRect: NSRect(x: -900, y: 140, width: 680, height: 240),
                                  styleMask: style, backing: .buffered, defer: false)
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            for size in [NSSize(width: 713, height: 469), NSSize(width: 713, height: 160),
                         NSSize(width: 420, height: 300), NSSize(width: 713, height: 469)] {
                precondition(echoLingoSetContentSizeSync(pointer, size.width, size.height) == 0)
                // No dispatch/runloop turn is allowed between call and readback.
                let actual = window.contentRect(forFrameRect: window.frame).size
                precondition(abs(actual.width - size.width) <= 1 && abs(actual.height - size.height) <= 1)
                precondition(abs(window.frame.minX - topLeft.x) <= 1 && abs(window.frame.maxY - topLeft.y) <= 1)
                precondition(!window.isVisible && !window.isKeyWindow)
            }
            let before = window.frame
            for width in [Double.nan, Double.infinity, -1, 0, 100_001] {
                precondition(echoLingoSetContentSizeSync(pointer, width, 240) == -3)
                precondition(window.frame == before)
            }
        }
        precondition(echoLingoSetContentSizeSync(nil, 680, 240) == -2)
        let transitionWindow = NSWindow(contentRect: NSRect(x: -500, y: 140, width: 680, height: 480),
                                        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let context = Unmanaged.passRetained(transitionWindow).toOpaque()
        // Reproduce Tao's FIFO style change rather than testing a fixed style.
        DispatchQueue.main.async { transitionWindow.styleMask = [.resizable] }
        echoLingoAfterWindowChanges({ context in
            let window = Unmanaged<NSWindow>.fromOpaque(context!).takeUnretainedValue()
            precondition(!window.styleMask.contains(.titled))
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            precondition(echoLingoSetContentSizeSync(context, 713, 160) == 0)
            precondition(window.contentRect(forFrameRect: window.frame).height == 160)
            precondition(window.frame.minX == topLeft.x && window.frame.maxY == topLeft.y)
            precondition(!window.isVisible && !window.isKeyWindow)
            DispatchQueue.main.async { window.styleMask = [.titled, .resizable] }
            echoLingoAfterWindowChanges({ context in
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
        dispatchMain()
    }
}
