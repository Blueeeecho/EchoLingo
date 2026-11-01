"""Cleanup wiring; real native clipboard semantics require the Windows bridge."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parent / "windows-browser-selection-bridge.cs").read_text()


class BrowserClipboardCleanupContract(unittest.TestCase):
    def test_cleanup_locks_then_revalidates_owned_generation_and_payload(self):
        cleanup = SOURCE.split("    static bool ClearOwnedClipboard(){", 1)[1].split("    static Dictionary<string,object> GuardMouseStart", 1)[0]
        self.assertLess(cleanup.index("OpenClipboard"), cleanup.index("ReclaimOwnedClipboard"))
        for expected in ("GetClipboardSequenceNumber()==ownedClipboard", "OwnedPayloadsLocked", "EmptyClipboard()", "CountClipboardFormats()==0", "Marshal.GetLastWin32Error()==0", "finally{CloseClipboard();ownedSeed=null;}"):
            self.assertIn(expected, cleanup)
        self.assertNotIn("Clipboard.Clear();", cleanup)
        self.assertNotIn("Thread.Sleep", cleanup)

    def test_policy_does_not_read_foreign_generation_or_clear_changed_payload(self):
        self.assertIn("return same()&&content()&&same()&&clear();", SOURCE)
        self.assertIn("RawPayloadSelfTest();ClipboardCleanupPolicySelfTest();", SOURCE)
        for label in ("FOREIGN_GENERATION_PRESERVED", "CHANGED_CONTENT_PRESERVED", "CHANGED_DURING_READ_PRESERVED", "OWNED_GENERATION_CLEARED", "FAILURE_REPORTED"):
            self.assertIn("CLEANUP_" + label, SOURCE)

    def test_failed_ole_ownership_does_not_replace_consumer_verdict(self):
        policy = SOURCE.split("    static bool FailedOleCleanupGeneration", 1)[1].split("    static bool ClearOwnedClipboard", 1)[0]
        for key in ("originalVerdict", "sequenceBeforeRead", "sequenceAfterRead", "nonceVerified", "unicodeExactEqual", "rtfExactEqual", "htmlExactEqual", "sequenceBeforeLock", "sequenceWhileLocked", "sequenceAfterUnlock"):
            self.assertIn('"' + key + '"', policy)
        self.assertNotIn("GetClipboardData", policy)
        self.assertNotIn("OpenClipboard", policy)
        self.assertIn("FailedOleCleanupPolicySelfTest();", SOURCE)
        for label in ("OWNED_NATIVE_GENERATION_ACCEPTED", "VERDICT_PRESERVED", "NEW_GENERATION_REJECTED", "INCOMPLETE_EVIDENCE_REJECTED", "CHANGED_EVIDENCE_REJECTED", "NO_PROBE_REJECTED"):
            self.assertIn("FAILED_OLE_" + label, policy)
        self.assertIn('bool verified=!NoClipboardProbe&&FailedOleCleanupGeneration(clipboardObservation,observed);', SOURCE)
        self.assertIn('if(verified)ownedClipboard=observed;', SOURCE)
        self.assertIn('metadata["ok"]=exact&&foregroundAlways&&Convert.ToBoolean(metadata["richClipboardRestored"])', SOURCE)

    def test_com_probe_is_failure_only_same_object_and_never_reacquires(self):
        self.assertIn('if(!matches&&!NoClipboardProbe){', SOURCE)
        self.assertIn('ObserveFailedOleCom(actual,expected,observation)', SOURCE)
        probe = SOURCE.split("    static Dictionary<string,object> ObserveFailedOleCom", 1)[1].split("    static Dictionary<string,object> QueryDiagnostics", 1)[0]
        self.assertIn("actual as ComTypes.IDataObject", probe)
        self.assertEqual(probe.count("com.GetData(ref format,out medium)"), 1)
        for forbidden in ("Clipboard.GetDataObject(", "OleGetClipboard(", "OpenClipboard(", "Thread.Sleep(", "ReleaseComObject(", 'observation["originalVerdict"]=', 'metadata["ok"]='):
            self.assertNotIn(forbidden, probe)
        self.assertLess(probe.index("FailedOleCleanupGeneration"), probe.index("com.GetData("))
        self.assertLess(probe.index("generationChangedBeforePayloadRead"), probe.index("Marshal.Copy"))
        self.assertIn("cfFormat=13", probe)
        self.assertIn("lindex=-1", probe)
        self.assertIn("tymed=ComTypes.TYMED.TYMED_HGLOBAL", probe)

    def test_com_probe_bounds_and_releases_owned_medium_on_all_success_paths(self):
        probe = SOURCE.split("    static Dictionary<string,object> ObserveFailedOleCom", 1)[1].split("    static Dictionary<string,object> QueryDiagnostics", 1)[0]
        self.assertLess(probe.index("size>65536"), probe.index("Marshal.Copy"))
        self.assertIn("finally{GlobalUnlock(medium.unionmember);}", probe)
        self.assertIn("if(received){try{ReleaseStgMedium(ref medium);", probe)
        self.assertIn('catch(COMException error){result["hresult"]=error.ErrorCode;', probe)
        self.assertIn('result["fixedSeedExactEqual"]=ExactPayload(bytes,wanted,true)?1:0;', probe)
        self.assertNotIn('result["payload"]', probe)


if __name__ == "__main__":
    unittest.main()
