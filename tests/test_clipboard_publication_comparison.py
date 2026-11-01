"""Static safety wiring; desktop/COM behavior must run on Windows."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).parent / 'windows-native-smoke.ps1').read_text()


class PublicationComparisonContract(unittest.TestCase):
    def test_explicit_diagnostic_never_replaces_default_acceptance(self):
        self.assertIn('[switch]$ClipboardPublicationComparison', SOURCE)
        self.assertIn('} else { [EchoLingoDesktopSmoke]::Run($HelperPath) }', SOURCE)
        self.assertIn('AssertSuccess(CaptureFixtureSelection(form, helperPath), CopyFallbackControl.Selection, "Clear then delayed Ctrl+C publication")', SOURCE)
        self.assertIn('if (-not $result[\'ok\']) { exit 1 }', SOURCE)
        self.assertIn('publicationTimer.Interval = 80;', SOURCE)
        self.assertNotIn('1200', SOURCE)

    def test_exactly_two_modes_with_single_helper_call_per_case(self):
        body = SOURCE.split('RunPublicationComparison(string helperPath)', 1)[1].split('public static Dictionary<string, object> Run(', 1)[0]
        self.assertIn('foreach (bool native in new bool[] { false, true })', body)
        self.assertEqual(body.count('CaptureFixtureSelection(form, helperPath)'), 1)
        self.assertIn('source.CopyCount - before == 1', body)
        self.assertIn('cases.Count == 2 && (bool)cases[0]["ok"] && (bool)cases[1]["ok"]', body)
        self.assertNotIn('SavedClipboard', body)
        self.assertNotIn('reply.Text;', body)
        self.assertIn('FRESH_NATIVE_EMPTY_REQUIRED', body)
        self.assertIn('PREDECESSOR_CLIPBOARD_PRESERVED', body)

    def test_native_clear_requires_owned_generation_and_bounded_payload(self):
        self.assertIn('return same() && matches() && same() && clear();', SOURCE)
        self.assertIn('size > 65536', SOURCE)
        self.assertIn('finally { GlobalUnlock(handle); }', SOURCE)
        self.assertIn('finally { CloseClipboard(); }', SOURCE)
        self.assertIn('source.PublishedSequence != 0 ? source.PublishedSequence : seeded', SOURCE)
        self.assertIn('PublicationPolicySelfTest();', SOURCE)
        for label in ('FOREIGN_GENERATION_UNREAD', 'WRONG_NONCE_PRESERVED', 'GENERATION_CHANGED_DURING_READ_PRESERVED', 'OWNED_GENERATION_ALLOWED'):
            self.assertIn(label, SOURCE)
        self.assertIn('if (!cleaned) row["ok"] = false;', SOURCE)

    def test_only_fixed_owner_sequence_and_format_metadata(self):
        body = SOURCE.split('static Dictionary<string, object> PublicationMetadata()', 1)[1].split('static bool ExactGeneratedHandle', 1)[0]
        for key in ('sequence', 'ownerPresent', 'ownerIsFixtureProcess', 'ownerIsCallingThread', 'unicodeAvailable'):
            self.assertIn('"' + key + '"', body)
        for forbidden in ('GetClipboardData', 'GetText', 'GetWindowText', 'GetDataObject'):
            self.assertNotIn(forbidden, body)


if __name__ == '__main__':
    unittest.main()
