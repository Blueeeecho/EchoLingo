"""Focused bridge guardrails, not a substitute for native full-screen/IME QA."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
def read(name): return (ROOT / name).read_text()
class ScreenshotOverlayContract(unittest.TestCase):
    def test_overlay_ready_never_uses_ordinary_focus_branch(self):
        source = read('src-tauri/src/screenshot.rs')
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
        self.assertIn('.screenshots.current(hide_id)', source)
        self.assertIn('state.image.is_none()', source)
    def test_windows_geometry_is_from_selected_pixels_and_process_finishes(self):
        source = read('src-tauri/src/windows_capture_native.rs')
        self.assertIn('selected.x, selected.y, selected.width, selected.height', source)
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
        self.assertIn('webview.set_focus()', source.split('pub fn focus_text(', 1)[1])
if __name__ == '__main__': unittest.main()
