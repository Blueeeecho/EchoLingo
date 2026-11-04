"""Keep the tested native-size commit on both macOS completion paths."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = (ROOT / 'src-tauri/src/window_layout.rs').read_text()


class MacResizeCompletionContract(unittest.TestCase):
    def test_end_notification_commits_before_frontend_remeasurement(self):
        observer = LAYOUT.split('fn install_mac_resize_observer(')[1].split('pub fn cancel_stale_native_layout(')[0]
        self.assertIn('finish_native_resize_at_idle(&window, &state, presentation.epoch)', observer)
        self.assertLess(observer.index('finish_native_resize_at_idle('), observer.index('app.emit('))
        # Finishing only height here consumes the token before width can commit.
        self.assertNotIn('manual.finish(', observer)

    def test_idle_recovery_commits_before_each_queued_fit(self):
        fit = LAYOUT.split('async fn fit(')[1].split('fn finish_native_resize_at_idle(')[0]
        self.assertEqual(fit.count('finish_native_resize_at_idle(&native, &state, gate_epoch)'), 2)
        self.assertLess(fit.rindex('finish_native_resize_at_idle('), fit.rindex('fit_inner('))
        completion = LAYOUT.split('fn finish_native_resize_at_idle(')[1].split('fn configure_mac_window_frame(')[0]
        self.assertIn('manual.finish_native_popup(', completion)
        self.assertIn('state.schedule_save()', completion)
        self.assertNotIn('content_width', completion)


    def test_completion_rechecks_epoch_after_waiting_for_popup_lock(self):
        completion = LAYOUT.split('fn finish_native_resize_at_idle(')[1].split('fn configure_mac_window_frame(')[0]
        self.assertEqual(completion.count('.presentation()?'), 2)
        self.assertLess(completion.index('state.popup.lock()'), completion.rindex('.presentation()?'))
        self.assertLess(completion.rindex('.presentation()?'), completion.index('manual.finish_native_popup('))
        self.assertLess(completion.rindex('presentation.epoch != epoch'), completion.index('manual.finish_native_popup('))


if __name__ == '__main__':
    unittest.main()
