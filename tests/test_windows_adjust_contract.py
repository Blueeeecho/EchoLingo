"""Wiring checks; behavioral adjustment cases live in Rust's pure policy tests."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
POLICY = (ROOT / 'src-tauri/src/windows_capture_policy.rs').read_text()
HOST = (ROOT / 'src-tauri/src/windows_capture_native.rs').read_text()
WIRE = (ROOT / 'src-tauri/native-capture/src/main.rs').read_text()


class WindowsAdjustmentContract(unittest.TestCase):
    def test_exact_action_allowlist_and_cancel_remains_non_image(self):
        block = POLICY.split('pub const SCREENSHOT_ACTIONS:', 1)[1].split('];', 1)[0]
        self.assertEqual(re.findall(r'"([a-z]+)"', block), [
            'select', 'rectangle', 'arrow', 'text', 'number', 'pen',
            'highlight', 'mosaic', 'solid', 'crop', 'copy', 'save', 'pin', 'cancel'])
        self.assertRegex(POLICY, r'if action == "cancel"\s*\{\s*self\.cancel\(\);')
        self.assertIn('output["initialAction"] = serde_json::json!(action)', WIRE)

    def test_only_screenshot_enters_adjusting_phase(self):
        self.assertIn('self.purpose == CapturePurpose::Screenshot && !self.cancelled', POLICY)
        self.assertIn('fn alt_s_region_still_finishes_on_first_release_without_action()', POLICY)
        self.assertIn('fn f1_waits_for_explicit_paired_action_and_reports_exact_wire_value()', POLICY)

    def test_all_owned_decorations_are_hidden_and_destroyed_with_existing_cleanup(self):
        compact = re.sub(r'\s+', '', HOST)
        self.assertIn('self.edges.iter().chain(&self.actions).chain(&self.handles)', compact)
        self.assertIn('self.edges.iter_mut().chain(&mutself.actions).chain(&mutself.handles)', compact)
        self.assertIn('Role::Edge(_) | Role::Action(_) | Role::Handle | Role::Hint => EDGE_EX', HOST)
        self.assertIn('return Some(3);', HOST)  # MA_NOACTIVATE unchanged

    def test_final_capture_still_revalidates_display_and_clicked_source(self):
        capture = HOST.split('pub fn run(request: Request)', 1)[1]
        self.assertLess(capture.index('let selected = picker.select()?;'), capture.index('image.copy_screen('))
        self.assertGreaterEqual(capture.count('picker.validate_window()?;'), 2)
        self.assertGreaterEqual(capture.count('picker.validate()?;'), 2)
        self.assertIn('result.as_ref().ok().and(picker.selection.initial_action)', re.sub(r'\s+', '', capture))

    def test_enter_is_owned_until_release_without_changing_region_keys(self):
        self.assertIn('CaptureConfirmKey::new(down(0x0d))', HOST)
        self.assertIn('Event::ConfirmCopy => self.selection.confirm_copy()', HOST)
        self.assertIn('self.state.confirm.ownership.request_close()', HOST)
        self.assertIn('hook_state.confirm.ownership.may_exit()', HOST)
        self.assertIn('fn region_keys_remain_foreign_and_preheld_enter_cannot_confirm()', POLICY)
        self.assertIn('fn modified_enter_is_owned_without_copy_and_shutdown_drains_keyup()', POLICY)
        self.assertIn('enabled && unmodified && eligible', POLICY)

    def test_toolbar_stays_in_existing_real_display_work_area(self):
        self.assertIn('let area = screenshot_toolbar_bounds(display)?;', HOST)
        self.assertIn('if bounds.len() != SCREENSHOT_ACTIONS.len()', HOST)
        self.assertIn('fn toolbar_wraps_inside_negative_coordinate_mixed_dpi_work_area()', POLICY)
        self.assertIn('Do not move a pressed button underneath its release.', POLICY)


if __name__ == '__main__':
    unittest.main()
