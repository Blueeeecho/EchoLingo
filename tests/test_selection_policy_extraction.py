"""Keep desktop-free C# fixture slices free from native diagnostic classes."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PureSelectionExtraction(unittest.TestCase):
    def test_production_policy_slice_is_still_desktop_free(self):
        native = (ROOT / "src-tauri/native/windows.ps1").read_text()
        start = "public static class SelectionCopyPolicy {"
        end = "public static class EchoLingoNative {"
        for filename in ("windows-selection-policy-smoke.ps1", "windows-selection-copy-ticket-smoke.ps1"):
            script = (ROOT / "tests" / filename).read_text()
            self.assertIn("IndexOf('" + start + "'", script)
            self.assertIn("IndexOf('" + end + "'", script)
        policy = native[native.index(start):native.index(end)]
        self.assertIn("public static class SelectionCopyPolicy", policy)
        for dependency in ("DllImport", "ClipboardHtmlProbe", "CaptureHealth", "OpenClipboard"):
            self.assertNotIn(dependency, policy)
        ticket = native[native.index("public sealed class SelectionCopyTicket {"):
                        native.index("// Created only immediately before the single clipboard fallback injection.")]
        self.assertNotIn("ClipboardHtmlProbe", ticket)
        self.assertNotIn("DllImport", ticket)
        self.assertEqual(native.count("public sealed class ClipboardHtmlProbe {"), 1)


if __name__ == "__main__":
    unittest.main()
