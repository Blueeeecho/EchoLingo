"""Privacy/lifecycle boundaries complement native screenshot and Rust pixel tests."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ScreenshotBackendContract(unittest.TestCase):
    def assertCode(self, expected, source):
        self.assertIn(re.sub(r"\s+", "", expected), re.sub(r"\s+", "", source))

    def test_f1_branches_before_ocr_and_never_enters_text_pipeline(self):
        main = (ROOT / 'src-tauri/src/main.rs').read_text()
        body = main.split('fn start_action(', 1)[1].split('async fn hide_native_capture_window', 1)[0]
        self.assertLess(body.index('screenshot::start_capture(app)'), body.index('cloud_ocr'))
        screenshot = (ROOT / 'src-tauri/src/screenshot.rs').read_text()
        self.assertIn('platform::capture_screenshot_with_geometry_cancelable', screenshot)
        for forbidden in ['ocr::recognize(', 'load_ocr_key', 'finish_translation(', 'history.json', 'reqwest::', 'platform::capture_ocr']:
            self.assertNotIn(forbidden, screenshot)

    def test_screenshot_window_has_no_general_file_or_clipboard_plugin_permissions(self):
        config = json.loads((ROOT / 'src-tauri/tauri.conf.json').read_text())
        editor = next(item for item in config['app']['windows'] if item['label'] == 'screenshot-editor')
        self.assertEqual(editor['url'], 'screenshot.html')
        self.assertFalse(editor['visible'])
        self.assertFalse(editor['create'])
        capability = json.loads((ROOT / 'src-tauri/capabilities/default.json').read_text())
        self.assertEqual(capability['permissions'], ['core:default'])
        self.assertIn('screenshot-editor', capability['windows'])

    def test_saves_are_atomic_new_png_pixels_only_and_os_desktop_is_resolved(self):
        source = (ROOT / 'src-tauri/src/screenshot.rs').read_text()
        self.assertCode('app.path().desktop_dir()', source)
        self.assertCode('.create_new(true)', source)
        self.assertCode('ImageFormat::Jpeg', source)
        self.assertCode('PngEncoder::new', source)
        self.assertCode('MAX_ENCODED_BYTES: usize = 32 * 1024 * 1024', source)
        self.assertCode('MAX_PIXELS: u64 = 32_000_000', source)
        self.assertCode('reader.limits(limits)', source)
        self.assertCode('bounded_reader(bytes, format).into_decoder()', source)
        self.assertCode('image.apply_orientation(orientation)', source)
        self.assertCode('options.custom_flags(libc::O_NONBLOCK)', source)
        self.assertCode('file.take((MAX_ENCODED_BYTES + 1)', source)
        self.assertNotRegex(source, r'home_dir\([^)]*\).*join\("Desktop"\)')
        capture = source.split('pub fn start_capture(', 1)[1].split('#[cfg(test)]', 1)[0]
        self.assertNotIn('save_new_png(', capture)
        self.assertNotIn('set_image(', capture)

    def test_stale_sessions_are_checked_after_dialogs_and_before_native_side_effects(self):
        source = (ROOT / 'src-tauri/src/screenshot.rs').read_text()
        self.assertCode('native_tasks.publish(request', source)
        self.assertCode('WebviewWindowBuilder::from_config', source)
        self.assertCode('ensure_editor_window(app, request).await?', source)
        self.assertCode('native_tasks.enter(&worker_request)', source)
        self.assertCode('screenshots.with_image(session_id', source)
        self.assertCode('screenshot-session-cleared', source)
        self.assertNotIn('emit_session(app, None)', source)
        main = (ROOT / 'src-tauri/src/main.rs').read_text()
        self.assertCode('screenshot-close-requested', main)
        self.assertNotIn('screenshot::invalidate', main)
        self.assertCode('screenshot::cancel_pending', main)
        self.assertCode('settings.screenshot_save_directory = locked(&state.settings)?.screenshot_save_directory.clone()', main)
        self.assertCode('native_tasks.enter_effect()', source)
        self.assertCode('screenshots.operations.acquire().await', source)
        self.assertCode('.set_parent(&window)', source)
        close = source.split('pub async fn close_screenshot_editor(', 1)[1].split('#[derive(Serialize)]', 1)[0]
        self.assertCode('dialog(&app, move ||', close)
        self.assertCode('state.screenshots.dialog_active.load(Ordering::SeqCst)', close)
        self.assertNotIn('operations.try_acquire', close)


if __name__ == '__main__':
    unittest.main()
