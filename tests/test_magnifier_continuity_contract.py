"""Wire pure frame-lifecycle decisions to native visibility; Windows tests observe events."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT / "src-tauri/src/windows_capture_native.rs").read_text()


class MagnifierContinuityContract(unittest.TestCase):
    def test_final_marker_was_occluded_and_cannot_match_an_old_motion_frame(self):
        # Coordinates relative to the generated First point, independent of DPI.
        marker = (108, 28, 12, 12)
        old_loupe = (50, -6, 156, 174)  # Last motion target: (+8,+20), offset (+42,-26).
        self.assertTrue(old_loupe[0] <= marker[0] and old_loupe[1] <= marker[1])
        self.assertTrue(old_loupe[0] + old_loupe[2] >= marker[0] + marker[2])
        self.assertTrue(old_loupe[1] + old_loupe[3] >= marker[1] + marker[3])
        for step in range(24):
            pointer_x = (step if step <= 12 else 24 - step) * 8
            self.assertLess(pointer_x - 8, marker[0])
        self.assertEqual((120 - 8, 40 - 8), (112, 32))
        self.assertTrue(108 <= 112 and 112 + 3 <= 120 and 28 <= 32 and 32 + 3 <= 40)

    def test_final_spatial_target_is_painted_before_helper_not_during_final_move(self):
        fixture = (ROOT / "tests/windows-native-capture-smoke.ps1").read_text()
        case = fixture.split("static Dictionary<string,object> Case(", 1)[1]
        self.assertLess(case.index("PrepareFinalPixelTarget(source,report)"), case.index("host.Begin()"))
        observe = fixture.split("static void ObserveMagnifierContinuity(", 1)[1].split("static Dictionary<string,object> SafeReply", 1)[0]
        self.assertNotIn("PreviewPatch=", observe)
        self.assertIn("if(eligible&&elapsed>=756&&atFinal&&cyan)finalMatched=true;", fixture)
        self.assertIn("bool eligible=elapsed<956", fixture)
        self.assertIn('"finalSnapshotEvidence",finalSnapshots', fixture)
    def test_throttle_retains_frame_instead_of_hiding(self):
        select = NATIVE.split("    fn select(&mut self)", 1)[1].split("    fn cleanup(&mut self)", 1)[0]
        self.assertIn("let frame_action = self.redraw.frame_action(", select)
        self.assertIn("else if frame_action == CaptureFrameAction::Render", select)
        self.assertIn("else if frame_action == CaptureFrameAction::Hide", select)
        self.assertNotIn("} else {\n                self.loupe.hide();", select)

    def test_frame_wait_uses_post_render_clock_not_an_extra_full_frame(self):
        select = NATIVE.split("    fn select(&mut self)", 1)[1].split("    fn cleanup(&mut self)", 1)[0]
        self.assertIn("let wait = self.redraw.wait_milliseconds(", select)
        self.assertIn("self.started.elapsed().as_millis() as i64,", select)
        self.assertIn("wait_messages(wait);", select)
        self.assertNotIn("wait_messages();", select)
        wait = NATIVE.split("fn wait_messages(", 1)[1].split("fn hover(", 1)[0]
        self.assertIn("w::MsgWaitForMultipleObjects(0, null(), 0, milliseconds, 0x04ff)", wait)

    def test_sample_surface_is_session_owned_not_frame_allocated(self):
        render = NATIVE.split("    fn render_loupe(&mut self", 1)[1].split("    fn select(&mut self)", 1)[0]
        self.assertNotIn("Surface::new", render)
        self.assertNotIn("w::EnableWindow", render)
        self.assertIn("let raw = &self.loupe_sample;", render)
        self.assertIn("self.loupe_sample.write_pixels(&frame.pixels)", render)
        self.assertNotIn(".copy_screen", render)
        worker = NATIVE.split("impl ScreenSampler", 1)[1].split("impl Drop for ScreenSampler", 1)[0]
        self.assertRegex(worker, r"let raw =\s+Surface::new\(")
        self.assertIn("let pixels = raw.pixels()?", worker)
        self.assertIn(".try_send(ticket)", worker)
        self.assertNotIn("unsafe impl Send", NATIVE)

    def test_async_sampler_is_bounded_and_placement_precedes_dispatch(self):
        render = NATIVE.split("    fn render_loupe(", 1)[1].split("    fn select(", 1)[0]
        self.assertIn("magnifier_place_avoiding(", render)
        self.assertIn("self.sample_policy.pending_bounds()", render)
        self.assertIn("self.sample_policy.complete(frame.ticket, now)", render)
        self.assertIn("self.cancel.requested()?", render)
        self.assertLess(render.index("set_bounds(self.loupe.hwnd"), render.index("self.sampler.request(request)"))
        cleanup = NATIVE.split("    fn cleanup(&mut self)", 1)[1].split("impl Drop for Picker", 1)[0]
        self.assertIn("self.sampler.stop();", cleanup)
        self.assertIn("sampler_stopped.is_none()", cleanup)
        self.assertIn("Duration::from_millis(600)", cleanup)
        self.assertNotIn("recv_timeout", cleanup)

    def test_motion_pixel_oracle_identifies_frame_inside_same_snapshot(self):
        fixture = (ROOT / "tests/windows-native-capture-smoke.ps1").read_text()
        self.assertIn("class MotionPixelObserver", fixture)
        self.assertIn("ImageLockMode.ReadOnly", fixture)
        self.assertIn("colors.Count>=3&&maximumRefresh<=200&&finalMatched", fixture)
        self.assertIn("pixels.Finish(report,phase)", fixture)
        self.assertIn("new Rectangle(133,48,12,12)", fixture)

    def test_preview_is_device_compatible_but_png_remains_readable(self):
        self.assertIn("Some(Surface::preview(156, 174)?)", NATIVE)
        self.assertIn("w::CreateCompatibleBitmap(screen, width, height)", NATIVE)
        self.assertNotIn("w::CreateCompatibleBitmap(dc, width, height)", NATIVE)
        self.assertIn("let mut image = Surface::new(selected.width, selected.height)?", NATIVE)
        png = NATIVE.split("    fn png(", 1)[1].split("impl Drop for Surface", 1)[0]
        self.assertLess(png.index("self.bits.is_null()"), png.index("std::slice::from_raw_parts_mut"))
        self.assertIn("w::GdiFlush()", png)

    def test_screen_sample_subphases_preserve_the_native_sequence(self):
        sample = NATIVE.split("    fn copy_screen_timed(", 1)[1].split("    fn png(", 1)[0]
        self.assertEqual(sample.count("w::GetDC(null_mut())"), 1)
        self.assertEqual(sample.count("w::BitBlt("), 1)
        self.assertEqual(sample.count("w::ReleaseDC(null_mut(), screen)"), 1)
        self.assertLess(sample.index("w::GetDC("), sample.index("w::BitBlt("))
        self.assertLess(sample.index("w::BitBlt("), sample.index("w::ReleaseDC("))
        self.assertNotIn("GdiFlush", sample)
        self.assertIn("Ok([acquire, blit, release])", sample)

    def test_live_color_probe_is_outside_unchanged_motion_window(self):
        fixture = (ROOT / "tests/windows-native-capture-smoke.ps1").read_text()
        self.assertIn("VerifyLiveMagnifierPixels(loupe,source,report,phase);", fixture)
        self.assertIn("changedColors==3", fixture)
        self.assertIn("clock.ElapsedMilliseconds<200", fixture)
        self.assertIn("while(clock.ElapsedMilliseconds<956)", fixture)
        self.assertIn("positions.Count>=12", fixture)

    def test_live_fixture_observes_stationary_motion_and_drag_events(self):
        fixture = (ROOT / "tests/windows-native-capture-smoke.ps1").read_text()
        self.assertIn("SetWinEventHook(0x8002,0x800b,IntPtr.Zero,callback,(uint)helper,0,0)", fixture)
        self.assertIn("invisible==0&&hides==0", fixture)
        self.assertIn('"eventObserverPositiveControl",locations>0', fixture)
        self.assertIn('Need(locations>0,', fixture)
        self.assertIn('ObserveMagnifierContinuity(helper,source,report,"armed")', fixture)
        self.assertIn('ObserveMagnifierContinuity(helper,source,report,"dragging")', fixture)
        self.assertIn("positions.Count>=12", fixture)
        self.assertIn('"motionPositionTransitions",motionTransitions', fixture)
        self.assertIn('"motionLocationEvents",motionLocations', fixture)
        self.assertIn("ok&&cases.Count==16", fixture)


if __name__ == "__main__":
    unittest.main()
