"""Source safety boundaries; real native clipboard/file effects need platform QA."""
from pathlib import Path
import unittest
SOURCE = (Path(__file__).resolve().parents[1] / 'src-tauri/src/screenshot.rs').read_text()

class SaveCopyContract(unittest.TestCase):
    def test_cancel_and_preflight_precede_all_effects(self):
        save = SOURCE.split('pub async fn save_screenshot_image(', 1)[1].split('#[tauri::command]', 1)[0]
        for marker in ('ensure_editor(&window)?', 'try_acquire()', 'check_image_revision(',
                       'Some(PathBuf::from(destination?.path).join(name))', 'return Ok(None);'):
            self.assertLess(save.index(marker), save.index('write_image_clipboard(&pixels)'))
        self.assertEqual(save.count('from_base64(&png_base64, true)'), 1)
        self.assertEqual(save.count('write_image_clipboard(&pixels)'), 1)
        self.assertEqual(save.count('save_new_png(&path, &bytes)'), 1)
        self.assertLess(save.index('write_image_clipboard(&pixels)'), save.index('encode(&pixels)'))
        worker = save.split('spawn_blocking(move || {', 1)[1]
        self.assertLess(worker.index('enter_effect()'), worker.index('check_image_revision('))
        self.assertLess(worker.index('check_image_revision('), worker.index('write_image_clipboard('))
        self.assertIn('SaveResult::from_outcomes(clipboard, saved)', save)
        self.assertNotIn('save_new_png(&path, &bytes)?', save)

    def test_copy_uses_same_helper_but_never_saves(self):
        copy = SOURCE.split('pub async fn copy_screenshot_image(', 1)[1].split('fn write_image_clipboard(', 1)[0]
        self.assertIn('let _physical = state.native_tasks.enter_effect()?;', copy)
        self.assertIn('write_image_clipboard(&pixels)', copy)
        self.assertNotIn('save_new_png', copy)
        self.assertEqual(SOURCE.count('.set_image(arboard::ImageData'), 1)
        self.assertIn('fn save_result_preserves_independent_effect_outcomes()', SOURCE)

if __name__ == '__main__': unittest.main()
