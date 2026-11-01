"""Source contracts supplement (not replace) native runtime acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT/'src-tauri/src/windows_capture_native.rs').read_text()
DISPATCH = (ROOT/'src-tauri/native-capture/src/main.rs').read_text()

class WindowsSingleOverlayContract(unittest.TestCase):
    def test_geometry_handoff_has_no_png_or_native_adjustment(self):
        self.assertIn('CapturePurpose::Screenshot && !request.selection_only', NATIVE)
        self.assertIn('self.selection_only && self.selection.adjusting', NATIVE)
        run = NATIVE.split('pub fn run(request: Request)', 1)[1]
        handoff = run.split('if request.selection_only {', 1)[1].split('return Ok(Vec::new());', 1)[0]
        for guard in ('picker.validate()?', 'picker.validate_window()?', 'picker.cancel.requested()?', 'selection_plan_value'):
            self.assertIn(guard, handoff)
        for forbidden in ('Surface::new', 'copy_screen', '.png()', 'initial_action ='):
            self.assertNotIn(forbidden, handoff)
        self.assertIn('Ok(_) if selection_only => {}', DISPATCH)

    def test_deferred_capture_revalidates_without_input_host_or_cache(self):
        capture = NATIVE.split('pub fn capture_selected_region(', 1)[1].split('pub fn run(', 1)[0]
        for guard in ('deferred::request(bytes, owner)?', 'cancel.requested()?', 'input_desktop()?', 'selection_plan_value(&current, source, owner)? != plan', 'capture_window_is_current(expected, actual)', 'DwmFlush()', 'selected.intersect(display.bounds)', 'validate()?;'):
            self.assertIn(guard, capture)
        self.assertGreaterEqual(capture.count('validate()?'), 4)
        for forbidden in ('Picker::new', 'Host::new', 'SetForegroundWindow', 'Clipboard', 'PrintWindow'):
            self.assertNotIn(forbidden, capture)
        self.assertIn('stdin().take(65_537)', DISPATCH)
        self.assertIn('Deferred capture does not accept an input host', DISPATCH)

    def test_suspend_resume_retains_native_host_and_router(self):
        overlay = (ROOT/'src-tauri/src/windows_screenshot_overlay.rs').read_text()
        phase = overlay.split('pub fn suspend(', 1)[1].split('pub fn hide(', 1)[0]
        self.assertIn('verify_retained_host(window)?', phase)
        self.assertIn('hide_webview_window(window)', phase)
        self.assertIn('show_without_activation(window)', phase)
        for forbidden in ('start_keys(', 'stop_keys(', 'prepare(', 'SetWindowLong', 'HOST.take', '.hide()'):
            self.assertNotIn(forbidden, phase)

    def test_alt_s_and_legacy_screenshot_remain_explicit(self):
        self.assertIn('Some("capture-image") => policy::CapturePurpose::Region', DISPATCH)
        self.assertIn('Some("capture-screenshot") if owner.is_some_and', DISPATCH)
        self.assertIn('selection_only: mode.as_deref() == Some("select-screenshot")', DISPATCH)

if __name__ == '__main__':
    unittest.main()
