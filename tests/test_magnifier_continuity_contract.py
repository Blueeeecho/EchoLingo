"""Wire pure frame-lifecycle decisions to native visibility; Windows tests observe events."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT / "src-tauri/src/windows_capture_native.rs").read_text()


class MagnifierContinuityContract(unittest.TestCase):
    def test_throttle_retains_frame_instead_of_hiding(self):
        select = NATIVE.split("    fn select(&mut self)", 1)[1].split("    fn cleanup(&mut self)", 1)[0]
        self.assertIn("let frame_action = self.redraw.frame_action(", select)
        self.assertIn("else if frame_action == CaptureFrameAction::Render", select)
        self.assertIn("else if frame_action == CaptureFrameAction::Hide", select)
        self.assertNotIn("} else {\n                self.loupe.hide();", select)

    def test_sample_surface_is_session_owned_not_frame_allocated(self):
        render = NATIVE.split("    fn render_loupe(&mut self", 1)[1].split("    fn select(&mut self)", 1)[0]
        self.assertNotIn("Surface::new", render)
        self.assertNotIn("w::EnableWindow", render)
        self.assertIn("let raw = &self.loupe_sample;", render)
        self.assertIn("raw.clear(", render)
        self.assertIn("raw.copy_screen(", render)
        self.assertEqual(NATIVE.count("let loupe_sample = Surface::new("), 1)

    def test_live_fixture_observes_stationary_motion_and_drag_events(self):
        fixture = (ROOT / "tests/windows-native-capture-smoke.ps1").read_text()
        self.assertIn("SetWinEventHook(0x8002,0x800b,IntPtr.Zero,callback,(uint)helper,0,0)", fixture)
        self.assertIn("invisible==0&&hides==0", fixture)
        self.assertIn('"eventObserverPositiveControl",locations>0', fixture)
        self.assertIn('Need(locations>0,', fixture)
        self.assertIn('ObserveMagnifierContinuity(helper,source,report,"armed")', fixture)
        self.assertIn('ObserveMagnifierContinuity(helper,source,report,"dragging")', fixture)
        self.assertIn("positions.Count>=12", fixture)
        self.assertIn("ok&&cases.Count==16", fixture)


if __name__ == "__main__":
    unittest.main()
