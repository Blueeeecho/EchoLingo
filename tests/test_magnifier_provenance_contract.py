"""Coordinate-free provenance diagnoses a strict pixel failure; it cannot pass it."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT / 'src-tauri/src/windows_capture_native.rs').read_text()
FIXTURE = (ROOT / 'tests/windows-native-capture-smoke.ps1').read_text()
PLATFORM = (ROOT / 'src-tauri/src/platform.rs').read_text()


class MagnifierProvenanceContract(unittest.TestCase):
    def test_worker_retains_owned_immutable_frame_timing_without_an_extra_capture(self):
        body = NATIVE.split('impl ScreenSampler {', 1)[1].split('impl Drop for ScreenSampler', 1)[0]
        self.assertEqual(body.count('raw.copy_screen_timed('), 1)
        self.assertEqual(body.count('let pixels = raw.pixels()?'), 1)
        ordered = ['let capture_started =', 'raw.copy_screen_timed(', 'let pixels = raw.pixels()?',
                   'let capture_finished =', 'captured_ms: [capture_started, capture_finished]']
        offsets = [body.index(item) for item in ordered]
        self.assertEqual(offsets, sorted(offsets))
        self.assertIn('sync_channel::<CaptureSampleTicket>(1)', body)
        self.assertNotIn('GetTickCount64', body)

    def test_first_matching_publication_requires_fresh_accepted_frame_and_completed_paint(self):
        body = NATIVE.split('fn render_loupe(', 1)[1].split('fn select(', 1)[0]
        self.assertIn('if self.sample_pointer != Some(p)', body)
        self.assertIn('self.sample_pointer_matched = false;', body)
        self.assertIn('self.sample_displayed = Some((frame.ticket, frame.captured_ms));', body)
        self.assertLess(body.index('self.sample_policy.complete(frame.ticket, now)'), body.index('self.sample_displayed = Some('))
        self.assertLess(body.index('self.cancel.requested()?'), body.index('w::UpdateWindow(self.loupe.hwnd)'))
        self.assertLess(body.index('w::UpdateWindow(self.loupe.hwnd)'), body.index('if fresh && !self.sample_pointer_matched'))
        self.assertIn('if ticket.sample == sample', body)
        self.assertIn('self.health.insert(field, value.min(10_000_000));', body)
        self.assertIn('fn magnifier_provenance_is_bounded_numeric_metadata_without_pointer_content()', PLATFORM)
        self.assertIn('"magnifierPointerXY": [12, 34]', PLATFORM)

    def test_observer_intervals_remain_ineligible_when_the_pixel_read_crosses_deadline(self):
        body = FIXTURE.split('sealed class MotionPixelObserver', 1)[1].split('static void VerifyLiveMagnifierPixels(', 1)[0]
        for exact in ('bool eligible=elapsed<956', 'if(eligible&&elapsed>=756&&atFinal&&cyan)finalMatched=true',
                      'colors.Count>=3&&maximumRefresh<=200&&finalMatched',
                      '"screenReadEndMilliseconds",screenReadEnded', '"classificationEndMilliseconds",classified'):
            self.assertIn(exact, body)
        self.assertEqual(body.count('CopyFromScreen('), 1)
        self.assertNotIn('magnifierCurrentPaintReturnedMilliseconds', body)
        self.assertNotIn('magnifierCurrentSampleMatched', body)
        self.assertIn('"phaseClockOriginTickModuloMilliseconds",phaseTickModulo', FIXTURE)
        self.assertIn('"crossProcessClockTypicalResolutionMilliseconds",16', FIXTURE)


if __name__ == '__main__':
    unittest.main()
