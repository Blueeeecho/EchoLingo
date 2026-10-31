"""Wiring/privacy checks; real clipboard behavior is exercised by the Windows fixture."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT / "src-tauri/native/windows.ps1").read_text()


class ClipboardSnapshotContract(unittest.TestCase):
    def test_native_marker_classification_is_read_only_and_generation_guarded(self):
        check = NATIVE.split("    static void RequireEmptySmartPasteMarker(", 1)[1].split("    static object CloneClipboardValue(", 1)[0]
        for required in ("RequireCurrentSequence", "OpenClipboard", "IsClipboardFormatAvailable", "SnapshotGetClipboardData", "Marshal.GetLastWin32Error", "payload != IntPtr.Zero || error != 0", "finally { CloseClipboard(); }"):
            self.assertIn(required, check)
        for forbidden in ("EmptyClipboard", "SetClipboardData", "Clipboard.Set", "Thread.Sleep", "while (", "for ("):
            self.assertNotIn(forbidden, check)

    def test_only_exact_empty_marker_can_be_normalized(self):
        clone = NATIVE.split("    static object CloneClipboardValue(", 1)[1].split("    static DataObject SnapshotClipboard(", 1)[0]
        self.assertIn("String.Equals(format, WebKitSmartPasteFormat, StringComparison.Ordinal)", clone)
        self.assertIn("RequireEmptySmartPasteMarker(generation);", clone)
        self.assertIn("throw new ClipboardSnapshotException(4);", clone)
        self.assertIn("if (!completed) copy.Dispose();", clone)
        self.assertNotIn("value.GetType().Name", clone)

    def test_diagnostics_do_not_survive_a_new_attempt(self):
        reset = NATIVE.split("    public static void ResetSelection() {", 1)[1].split("    public static int ResetSelectionSelfTest()", 1)[0]
        self.assertIn('key.StartsWith("copySnapshot", StringComparison.Ordinal)', reset)
        selftest = NATIVE.split("    public static int ResetSelectionSelfTest()", 1)[1].split("    public static Dictionary<string, long> Snapshot()", 1)[0]
        self.assertIn('values.ContainsKey("copySnapshotEmptyMarkers")', selftest)
        self.assertIn('values.ContainsKey("copySnapshotFailureKind")', selftest)

    def test_windows_fixture_runs_before_clipboard_writing_smokes(self):
        for filename in ("ci.yml", "release-checks.yml"):
            workflow = (ROOT / ".github/workflows" / filename).read_text()
            marker = workflow.index("-File tests/windows-clipboard-marker-smoke.ps1 -IsolatedTestSession")
            self.assertLess(marker, workflow.index("-File src-tauri/native/windows.ps1 -Mode self-test"))


if __name__ == "__main__":
    unittest.main()
