"""Source-level host guards; runtime Space/IME acceptance is still required."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT / "src-tauri/native/macos_capture.swift").read_text()
ENTRY = (ROOT / "src-tauri/native/macos.swift").read_text()


class MacScreenshotOverlayContract(unittest.TestCase):
    def test_host_is_a_genuine_nonactivating_panel_not_a_focused_normal_window(self):
        host = NATIVE.split("private final class CaptureScreenshotEditorPanel", 1)[1].split("let captureLoupeSample", 1)[0]
        self.assertIn("NSPanel", host)
        self.assertIn("[.borderless, .nonactivatingPanel]", host)
        self.assertIn("popupCollectionBehavior([.stationary, .ignoresCycle])", host)
        self.assertIn("host.panel.isOnActiveSpace", host)
        self.assertNotIn("activate(", host)
        self.assertNotIn("makeKeyAndOrderFront", host)
        self.assertNotIn("object_setClass", host)
        self.assertIn("!owner.isVisible", host)
        self.assertIn("panel.level = .floating", host)
        self.assertNotIn("panel.level = .screenSaver", host)
        self.assertIn("screens.dropFirst().reduce(first, { $0.union($1) }) == frame", host)

    def test_existing_webview_is_reused_and_restored_without_keyboard_interception(self):
        host = NATIVE.split("private final class CaptureScreenshotEditorHost", 1)[1].split("let captureLoupeSample", 1)[0]
        self.assertIn("WKWebView", host)
        self.assertIn("host.panel.makeFirstResponder(host.webView)", host)
        self.assertIn("owner.contentView = content", host)
        self.assertIn("content.autoresizingMask = contentMask", host)
        self.assertIn("NSWindow.willCloseNotification", host)
        self.assertIn("removeValue(forKey:", host)
        self.assertNotIn("addLocalMonitorForEvents", host)
        self.assertNotIn("keyCode", host)

    def test_screenshot_metadata_uses_the_same_plan_as_the_frozen_image(self):
        self.assertIn("let image = try captureNativePlannedImage(plan, purpose: purpose, operation: operation, trace: trace)", NATIVE)
        self.assertIn("return (image, plan)", NATIVE)
        self.assertIn('"captureGeometry": try captureEditorGeometry(captured.plan, primaryHeight: captured.plan.primaryHeight)', ENTRY)
        self.assertIn('return try captureScreenshotResponse(cancellation: operation)', ENTRY)
        self.assertIn('case "--capture-image": return ["ok": true, "imageBase64": try captureImage(cancellation: captureInputOperation(input))]', ENTRY)
        capture = ENTRY.split("func captureScreenshotResponse(", 1)[1].split("func screenCapturePermissionFields", 1)[0]
        self.assertNotIn("NSPasteboard", capture)
        self.assertNotIn("write(to", capture)
        self.assertIn("cancellation.isCancelled", capture)
        self.assertIn("captured.plan.displays.map", capture)
        self.assertIn("captured.plan.primaryHeight - usable.maxY", capture)
        self.assertIn("screen.visibleFrame.intersection(display.frame)", capture)
        self.assertIn("$0.frame == display.frame && $0.backingScaleFactor == display.scale", capture)
        self.assertIn("try onMainThread", capture)
        self.assertIn('"captureScreens": captureScreens', capture)

    def test_geometry_has_native_mixed_scale_and_negative_coordinate_cases(self):
        self.assertIn('editor["screenX"] == -1920', NATIVE)
        self.assertIn('editor["scale"] == 2', NATIVE)
        self.assertIn('aboveEditor["screenY"] == -720', NATIVE)
        self.assertIn('aboveEditor["scale"] == 1', NATIVE)

    def test_panels_bind_the_target_screen_and_verify_global_frame(self):
        selector = NATIVE.split("func show() throws", 1)[1].split("func receive(_ event", 1)[0]
        self.assertIn('== geometry.id', selector)
        self.assertIn('$0.frame == geometry.frame && $0.backingScaleFactor == geometry.scale', selector)
        self.assertIn('capturePanelContentRectangle(geometry.frame, screenFrame: screen.frame)', selector)
        self.assertIn('defer: false, screen: screen)', selector)
        self.assertLess(selector.index('panel.setFrame(geometry.frame'), selector.index('panel.orderFrontRegardless()'))
        self.assertIn('panel.frame == geometry.frame', selector)
        host = NATIVE.split('public func echoLingoPrepareScreenshotOverlay', 1)[1].split('@_cdecl("echolingo_resume', 1)[0]
        self.assertIn('capturePanelDisplay(selection, displays: displays)', host)
        self.assertIn('guard frame.contains(selection)', host)
        self.assertIn('host.panel.frame == frame', host)
        self.assertNotIn('NSScreen.main', host)
        rust = (ROOT / 'src-tauri/src/screenshot_overlay.rs').read_text()
        for call in ('echolingo_prepare_screenshot_overlay', 'echolingo_show_screenshot_overlay'):
            self.assertEqual(rust.count('fn ' + call + '('), 1)
        self.assertEqual(rust.count('selection_x: f64'), 2)
        self.assertEqual(rust.count('            geometry.x,'), 2)
        self.assertIn('local.offsetBy(dx: display.frame.minX, dy: display.frame.minY) == display.frame', NATIVE)
        self.assertIn('scale: 1.5', NATIVE)
        self.assertIn('area > 0 && area >= largest', NATIVE)

    def test_fullscreen_fixture_is_external_and_checks_native_window_order(self):
        fixture = (ROOT / "tests/macos-screenshot-overlay-host-fixture.swift").read_text()
        self.assertIn('private func emitOverlayFixture(', fixture)
        self.assertNotIn('func emit(', fixture)
        self.assertIn('source.arguments = ["--isolated-test-session", "--fullscreen-source"]', fixture)
        self.assertIn("window.toggleFullScreen(nil)", fixture)
        self.assertIn('window.styleMask.contains(.fullScreen)', fixture)
        self.assertIn("NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier", fixture)
        self.assertIn("overlayIndex < sourceIndex", fixture)
        self.assertIn("panel.isOnActiveSpace", fixture)
        self.assertIn('"physicalImeTested": false', fixture)
        self.assertIn('awaitStacking(panel, phase: "initial")', fixture)
        self.assertIn('awaitStacking(repeatedPanel, phase: "repeat")', fixture)
        self.assertIn('deadline: ProcessInfo.processInfo.systemUptime + 2', fixture)
        self.assertIn('probe { [self] in', fixture)
        self.assertIn('panel.windowNumber == windowNumber && content.window === panel', fixture)
        self.assertIn('if let missing = try checkStacking(panel)', fixture)
        self.assertIn('ProcessInfo.processInfo.systemUptime < deadline', fixture)
        self.assertIn('"windowMetadataSamples": metadataSamples', fixture)
        self.assertNotIn("CGWindowListCreateImage", fixture)
        self.assertNotIn("CGRequestScreenCaptureAccess", fixture)


if __name__ == "__main__":
    unittest.main()
