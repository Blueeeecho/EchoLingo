"""The explicit core-functional policy must not hide quality misses or skip cleanup."""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parent / 'windows-native-capture-smoke.ps1').read_text()


class NativeCoreQualityContract(unittest.TestCase):
    def test_policy_is_explicit_and_quality_cannot_mark_core_passed(self):
        self.assertIn('{"acceptancePolicy","core-functional-v1"}', SOURCE)
        self.assertIn('{"fineQualityBlocking",false}', SOURCE)
        body = SOURCE.split('static void MagnifierQuality(', 1)[1].split('sealed class MotionPixelObserver', 1)[0]
        for forbidden in ('report["ok"]', 'report["coreOk"]', 'Send(', 'Escape(', 'catch'):
            self.assertNotIn(forbidden, body)
        self.assertIn('issues.Count<16', body)
        self.assertIn('if(!issues.Contains(issue))', body)
        self.assertIn('report["qualityOk"]=false', body)
        codes = set(re.findall(r'"([a-z]+(?:-[a-z]+)+)"', body))
        self.assertEqual(codes, {'stationary-refresh', 'motion-observer-failed', 'moving-color-count',
                                'moving-color-refresh', 'final-pixel-deadline', 'event-positive-control',
                                'visibility-continuity', 'motion-follow-density'})

    def test_fine_misses_continue_but_observer_lifetime_and_basic_visibility_remain_hard(self):
        moving = SOURCE.split('public void Finish(Dictionary<string,object> report,string phase)', 1)[1].split('static void VerifyLiveMagnifierPixels(', 1)[0]
        self.assertIn('Need(stopped,"Moving-pixel observer did not stop.")', moving)
        self.assertIn('MagnifierQuality(report,phase,finalMatched,"final-pixel-deadline")', moving)
        self.assertIn('MagnifierQuality(report,phase,!failed,"motion-observer-failed")', moving)
        self.assertIn('{"observerFailed",failed}', moving)
        continuity = SOURCE.split('static void ObserveMagnifierContinuity(', 1)[1].split('static Dictionary<string,object> SafeReply(', 1)[0]
        self.assertIn('Need(matches==1&&IsWindowVisible(loupe)', continuity)
        self.assertIn('Need(pid==helper&&Alive(helper)', continuity)
        self.assertIn('Need(IsWindowVisible(loupe),"Basic magnifier visibility was lost after generated motion.")', continuity)
        self.assertIn('Need(stopped,"Generated visibility hook did not close.")', continuity)
        self.assertIn('finally', continuity)
        self.assertIn('if(pixels!=null)pixels.Dispose()', continuity)
        # Original measurements are retained, rather than relabeled as success.
        for metric in ('elapsed<956', 'finalSnapshots.Count<6', 'maximumRefresh<=200', 'positions.Count>=12', 'invisible==0&&hides==0'):
            self.assertIn(metric, SOURCE)

    def test_core_success_is_only_assigned_after_capture_and_cleanup(self):
        case = SOURCE.split('static Dictionary<string,object> Case(', 1)[1].split('public static Dictionary<string,object> Run(', 1)[0]
        ordered = ['ObserveMagnifierContinuity(helper,source,report,"armed")',
                   'ObserveMagnifierContinuity(helper,source,report,"dragging")',
                   'Need((bool)reply["ok"],"Delegated capture failed.")',
                   '"First-release free ROI dimensions changed."',
                   '"Helper/input plane cleanup did not finish."',
                   '"Closing delegated generation still consumed or duplicated normal input."',
                   'try{source.Dispose();}', 'report["coreOk"]=(bool)report["ok"]']
        positions = [case.index(item) for item in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('catch(Exception cleanup){report["ok"]=false;', case)
        self.assertIn('"Actual Esc did not cancel."', case)
        self.assertIn('"Blue hint pixels entered generated ROI."', case)
        self.assertNotIn('if((bool)report["qualityOk"])', case)
        self.assertNotIn('catch(Exception error){report["ok"]=true;', case)


if __name__ == '__main__':
    unittest.main()
