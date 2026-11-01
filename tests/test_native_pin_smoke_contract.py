"""Source wiring only; native runtime and binary absence are separate CI gates."""
from pathlib import Path
import unittest
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


class NativePinSmokeContract(unittest.TestCase):
    def test_debug_only_module_and_entry(self):
        source = (ROOT / 'src-tauri/src/main.rs').read_text()
        self.assertIn('#[cfg(all(target_os = "macos", debug_assertions))]\nmod native_pin_smoke;', source)
        self.assertIn('#[cfg(all(target_os = "macos", debug_assertions))]\n    if std::env::args().nth(1).as_deref() == Some("--native-pin-smoke")', source)
        fixture = (ROOT / 'src-tauri/src/native_pin_smoke.rs').read_text()
        self.assertIn('["--native-pin-smoke", "--isolated-test-session"]', fixture)
        self.assertNotIn('plugin(', fixture)
        self.assertNotIn('app_data_dir()', fixture)
        self.assertIn('context.config_mut().app.windows.clear()', fixture)

    def test_real_production_commands_and_bundled_page_not_mocked(self):
        source = (ROOT / 'src-tauri/src/native_pin_smoke.rs').read_text()
        for required in ('screenshot_pins::pin_screenshot_image(', 'screenshot_pins::get_pinned_screenshot,',
                         'screenshot_pins::pinned_screenshot_ready,', 'screenshot_pins::set_screenshot_pinned,',
                         'screenshot_pins::close_pinned_screenshot,', 'native_smoke_counts(&app)? == (1, 0)',
                         'native_smoke_counts(&app)? == (0, 0)', 'for id in 1..=2',
                         'foreground_pid() == before', 'SMOKE_RESIZE_READBACK'):
            self.assertIn(required, source)
        self.assertNotIn('__TAURI_INTERNALS__', source)
        self.assertIn('Duration::from_secs(40)', source)

    def test_callback_uses_take_once_ownership_for_tauri_fn(self):
        source = (ROOT / 'src-tauri/src/native_pin_smoke.rs').read_text()
        self.assertIn('-> impl Fn(String) + Send', source)
        self.assertIn('let pending = Mutex::new(Some(send));', source)
        self.assertIn('if let Some(send) = pending.take()', source)
        self.assertIn('.eval_with_callback(script, js_callback(send))', source)
        self.assertIn('repeated_fn_callback_keeps_first_result', source)
        self.assertIn('callback_after_timeout_or_receiver_drop_is_harmless', source)

    def test_single_context_macro_and_matching_objc_declarations(self):
        main = (ROOT / 'src-tauri/src/main.rs').read_text()
        fixture = (ROOT / 'src-tauri/src/native_pin_smoke.rs').read_text()
        self.assertEqual(main.count('tauri::generate_context!()'), 1)
        self.assertNotIn('tauri::generate_context!', fixture)
        self.assertIn('native_pin_smoke::run(app_context())', main)
        self.assertIn('.build(app_context())', main)
        self.assertIn('pub fn run(mut context: tauri::Context<tauri::Wry>)', fixture)
        self.assertIn('type Selector = *const c_void;', fixture)
        self.assertIn('fn objc_msgSend(receiver: Object, selector: Selector);', fixture)
        self.assertNotIn('as unsafe extern "C" fn()', fixture)

    def test_runner_checks_release_bytes_and_keeps_failed_evidence(self):
        source = (ROOT / 'tests/macos-pin-native-smoke.sh').read_text()
        for required in ('DEBUG_SMOKE_ENTRY_PRESENT_IN_RELEASE', 'timeout=70',
                         "'release-entry-absence.json'", "'stdout.log'", "'stderr.log'",
                         'exist_ok=False', "b'generated-pin-fixture'", 'NATIVE_PIN_SMOKE_FAILED_SEE_PRESERVED_LOGS'):
            self.assertIn(required, source)
        self.assertNotIn('tccutil', source)
        self.assertNotIn('sudo ', source)

    def test_binary_absence_checker_rejects_each_fixture_marker(self):
        checker = ROOT / 'scripts/verify-native-pin-release-absence.py'
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'generated-executable'
            binary.write_bytes(b'generated release fixture bytes')
            self.assertEqual(subprocess.run([sys.executable, str(checker), str(binary)], capture_output=True).returncode, 0)
            for marker in (b'--native-pin-smoke', b'SMOKE_EXTERNAL_FOREGROUND_REQUIRED', b'generated-pin-fixture'):
                binary.write_bytes(b'generated ' + marker)
                self.assertNotEqual(subprocess.run([sys.executable, str(checker), str(binary)], capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
