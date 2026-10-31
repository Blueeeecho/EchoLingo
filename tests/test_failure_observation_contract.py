"""Failure-only generated metadata must never repair or relax acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'tests/windows-application-smoke.ps1').read_text()
WPF = (ROOT / 'tests/windows-selection-wpf-fixture.cs').read_text()


class FailureObservationContract(unittest.TestCase):
    def test_plane_observation_does_not_change_strict_live_style_gate(self):
        self.assertIn('if ((style&required)!=required || (style&(0x00080000L|0x20L))!=0)', APP)
        self.assertIn('throw new InputPlaneStyleException', APP)
        self.assertIn('if (rejectedHelper!=0 && owner==rejectedHelper && !exists)', APP)
        body = APP.split('static Dictionary<string,object> PlaneFailureIdentity(', 1)[1].split('static long hiddenPlaneStyleChecks', 1)[0]
        for forbidden in ('SetWindowLong', 'ShowWindow', 'SetWindowPos', 'SendInput', 'Thread.Sleep', 'GetWindowText', 'MainModule.FileName'):
            self.assertNotIn(forbidden, body)
        for field in ('expectedGeneratedClass', 'classMatchesExpected', 'ownerIdentityStable', 'verifiedHelperStartUtcTicks', 'helperStartUtcTicksAtFailure', 'extendedStyleAfterFailure', 'sameVerifiedHelperGeneration'):
            self.assertIn(field, body)

    def test_failure_export_keeps_one_bounded_request(self):
        body = APP.split('static void ObserveFailedWorkflow(', 1)[1].split('sealed class PinnedVisibilityWatch', 1)[0]
        self.assertEqual(body.count('secondary=Process.Start(start)'), 1)
        self.assertIn('bool captureFailure=report.ContainsKey("inputPlaneStyleFailure")', body)
        self.assertIn('captureFailure?CaptureFields:FailureHealthFields()', body)
        self.assertIn('while(budget.ElapsedMilliseconds<2000)', body)
        self.assertIn('captureFailure?"--capture-diagnostics":"--selection-diagnostics"', body)

    def test_wpf_observes_failure_without_selection_repair_or_retry(self):
        self.assertIn('if(editor.Selection.Text!=texts[index])ObserveMouseSelectionFailure(index,first,last,row);Need(editor.Selection.Text==texts[index],"WPF_MOUSE_SELECTION_NOT_EXACT_NO_PROGRAMMATIC_REPAIR")', WPF)
        body = WPF.split('void ObserveMouseSelectionFailure(', 1)[1].split('void SelectWithMouse(', 1)[0]
        for forbidden in ('SendInput', 'SetCursorPos', 'Thread.Sleep', '.Select(', 'AutomationElement', 'Selection.Text='):
            self.assertNotIn(forbidden, body)
        for field in ('expectedLength', 'lastMouseUpScreen', 'selectionStartSymbolOffset', 'selectionEndSymbolOffset', 'generatedSubstringStart', 'pointerHitOwnSource'):
            self.assertIn(field, body)
        self.assertIn('report["sameHotkeyRetries"]=0', WPF)
        self.assertIn('passed==3&&cleanupErrors.Count==0', WPF)


if __name__ == '__main__':
    unittest.main()
