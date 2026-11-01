"""Focused bridge guardrails, not a substitute for native full-screen/IME QA."""
from pathlib import Path
import json
import tomllib
import unittest
ROOT = Path(__file__).resolve().parents[1]
def read(name): return (ROOT / name).read_text()
class ScreenshotOverlayContract(unittest.TestCase):
    def test_overlay_ready_never_uses_ordinary_focus_branch(self):
        source = read('src-tauri/src/screenshot.rs')
        config = json.loads(read('src-tauri/tauri.conf.json'))
        cargo = tomllib.loads(read('src-tauri/Cargo.toml'))
        # Tauri's build-time allowlist requires configuration and Cargo feature
        # agreement even while the pinned runtime treats this as compatibility.
        self.assertTrue(config['app']['macOSPrivateApi'])
        self.assertIn('macos-private-api', cargo['dependencies']['tauri']['features'])
        self.assertIn('.transparent(true)', source)
        ready = source.split('pub async fn screenshot_editor_ready(', 1)[1].split('pub async fn focus_screenshot_overlay(', 1)[0]
        self.assertLess(ready.index('capture_geometry.as_ref()'), ready.index('.show()'))
        self.assertIn('return super::screenshot_overlay::show(', ready)
        start = source.split('pub fn start_capture(', 1)[1].split('#[cfg(test)]', 1)[0]
        self.assertIn('capture_screenshot_with_geometry_cancelable', start)
        self.assertNotIn('set_image(', start)
        self.assertNotIn('save_new_png(', start)
        self.assertIn('super::screenshot_overlay::hide(&window)', start)
    def test_hidden_owner_dialogs_are_not_allowed_in_capture_overlay(self):
        source = read('src-tauri/src/screenshot.rs')
        self.assertIn('if save_as && image.public.capture_geometry.is_some()', source)
        self.assertIn('请先完成或取消原地截图，再打开本地图片', source)
        self.assertRegex(source, r'\.screenshots\s*\.current\(hide_id\)')
        self.assertIn('state.image.is_none()', source)
        dismiss = source.split('fn dismiss_current(', 1)[1].split('#[cfg(test)]', 1)[0]
        self.assertLess(dismiss.index('dismiss()?'), dismiss.index('*state = SessionState::default()'))
        close = source.split('pub async fn close_screenshot_editor(', 1)[1].split('#[derive(Serialize)]', 1)[0]
        self.assertLess(close.index('dismiss_current('), close.index('emit_cleared('))
    def test_windows_geometry_is_from_selected_pixels_and_process_finishes(self):
        source = read('src-tauri/src/windows_capture_native.rs')
        self.assertRegex(source, r'selected\.x,\s*selected\.y,\s*selected\.width,\s*selected\.height')
        self.assertIn('let capture_geometry = if result.is_ok()', source)
        self.assertIn('picker.cleanup();', source)
        reply = read('src-tauri/native-capture/src/main.rs')
        self.assertIn('output["captureGeometry"]', reply)
        self.assertIn('output["imageBase64"]', reply)
        self.assertNotIn('copy_screenshot', reply)
    def test_windows_initial_show_and_text_focus_are_separate(self):
        source = read('src-tauri/src/windows_screenshot_overlay.rs')
        show = source.split('pub fn show(', 1)[1].split('pub fn hide(', 1)[0]
        self.assertIn('show_without_activation', show)
        self.assertNotIn('set_focus', show)
        self.assertIn('KeyOwnership::new(preheld)', source)
        self.assertIn('KeyRoute::Dispatch', source)
        self.assertIn('state.active.load(Ordering::SeqCst)', source)
        self.assertIn('foreground == state.source', source)
        self.assertIn('stop_keys();', source.split('pub fn hide(', 1)[1])
        self.assertRegex(source.split('pub fn hide(', 1)[1], r'SetWindowPos\(\s*native,\s*-2isize as w::H')
        self.assertIn('*saved_host = None;', source.split('pub fn hide(', 1)[1])
        self.assertRegex(source.split('pub fn focus_text(', 1)[1], r'webview\s*\.set_focus\(\)')
if __name__ == '__main__': unittest.main()
