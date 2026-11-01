from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT / 'src-tauri/native/windows.ps1').read_text()
POLICY = (ROOT / 'tests/windows-selection-policy-fixture.cs').read_text()
FIXTURE = (ROOT / 'tests/windows-clipboard-readiness-fixture.cs').read_text()


class ClipboardReadinessContract(unittest.TestCase):
    def test_gate_does_not_open_read_write_or_wait(self):
        gate = NATIVE.split('public static string ReadPublishedUnicode(', 1)[1].split('\n    }', 1)[0]
        self.assertIn('return available ? read() : null;', gate)
        for forbidden in ('OpenClipboard', 'GetClipboardData', 'EmptyClipboard', 'Thread.Sleep', 'Task.', 'Thread('):
            self.assertNotIn(forbidden, gate)
        adapter = NATIVE.split('static string ReadSelectionClipboardText()', 1)[1].split('sealed class ClipboardSnapshotException', 1)[0]
        self.assertIn('bool available = IsClipboardFormatAvailable(13);', adapter)
        self.assertEqual(adapter.count('ReadPublishedUnicode(available,'), 2)
        self.assertIn('if (!trace) return', adapter)
        self.assertIn('data.GetDataPresent(DataFormats.UnicodeText, false)', adapter)
        self.assertIn('stage=ole-object-finished', adapter)

    def test_deadline_and_sequence_policy_not_relaxed(self):
        self.assertIn('bool expired = elapsedMilliseconds >= 1200;', NATIVE)
        self.assertIn('if (before != after) return expired ? Observation.UnfinishedTimeout : Observation.Waiting;', NATIVE)
        for text in ('Absent format must not enter blocking OLE', 'Non-text updates retain the original 1200ms limit', 'Only the completed generation restores'):
            self.assertIn(text, POLICY)

    def test_generated_trace_cannot_escape_as_native_stderr_failure(self):
        self.assertIn('if(trace) Console.SetError(diagnostic);', FIXTURE)
        self.assertIn('if(trace) { Console.SetError(originalError); row["generatedTrace"]=diagnostic.ToString(); }', FIXTURE)
        self.assertIn('finally {', FIXTURE)
        self.assertIn('catch { row["errorKind"]=1; }', FIXTURE)

    def test_native_fixture_checks_synthesized_unicode_and_both_adapter_modes(self):
        self.assertIn('new uint[]{13,1,7,0}', FIXTURE)
        self.assertIn('new bool[]{false,true}', FIXTURE)
        self.assertIn('GetMethod("ReadSelectionClipboardText",BindingFlags.NonPublic|BindingFlags.Static)', FIXTURE)
        self.assertIn('Need(ready==(format!=0));', FIXTURE)
        self.assertIn('if(format==0) Need(GetClipboardSequenceNumber()==before);', FIXTURE)
        self.assertIn('generation==GetClipboardSequenceNumber() && OwnLocked(marker,nonce)', FIXTURE)
        self.assertNotIn('Clipboard.Clear(', FIXTURE)
        self.assertNotIn('Thread.Sleep(', FIXTURE)
        self.assertIn('if(!(bool)row["cleanup"]) { row["ok"]=false; break; }', FIXTURE)


if __name__ == '__main__':
    unittest.main()
