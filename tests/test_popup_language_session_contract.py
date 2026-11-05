"""Native session wiring guards; lifecycle behavior is tested in Rust separately."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def body(source, name):
    start = source.index(name)
    return source[start:source.index('\n}', start) + 2]


class PopupLanguageSessionContract(unittest.TestCase):
    def test_only_settings_cancellation_preserves_language_session(self):
        source = (ROOT / 'src-tauri/src/main.rs').read_text()
        cancel = body(source, 'fn cancel_active_translation_with_reason(')
        compact = ''.join(cancel.split())
        self.assertIn('matches!(reason,popup_health::CancellationReason::SettingsAction)', compact)
        self.assertIn('state.translation_requests.suspend_preserving_language_session()', compact)
        self.assertIn('}else{state.translation_requests.suspend()}', compact)
        self.assertIn('announce_presentation(app,presentation)', compact)

    def test_retained_popup_preserves_session_but_nonretained_capture_ends_it(self):
        source = (ROOT / 'src-tauri/src/main.rs').read_text()
        native = ''.join(body(source, 'fn begin_native_action_presentation(').split())
        self.assertIn('ifkeep_popup{requests.invalidate()}else{requests.suspend()}', native)

    def test_windows_observations_reconstruct_current_session_not_zero(self):
        source = (ROOT / 'src-tauri/src/main.rs').read_text()
        for epoch in ('click.token.epoch', 'token.epoch'):
            with self.subTest(epoch=epoch):
                literal = source.split('epoch: ' + epoch + ',', 1)[1].split('}', 1)[0]
                self.assertIn('language_session: current.language_session', literal)

    def test_presentation_exposes_camel_case_session_and_snapshot(self):
        source = (ROOT / 'src-tauri/src/translation_requests.rs').read_text()
        self.assertIn('#[serde(rename_all = "camelCase")]\npub struct Presentation', source)
        self.assertIn('pub language_session: u64', source)
        self.assertIn('self.invalidate_presentation(Some(false), true)', source)
        self.assertIn('self.invalidate_presentation(Some(false), false)', source)
        self.assertIn('self.invalidate_presentation(None, false)', source)
        self.assertNotIn('language_session =', body(source, '    pub fn resume('))


if __name__ == '__main__':
    unittest.main()
