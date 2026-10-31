"""The actual shortcut fixture may scroll only its exact owned UI target."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'tests/windows-shortcuts-uia-fixture.cs').read_text()


class ShortcutVisibilityFixtureContract(unittest.TestCase):
    def test_scrolling_is_allowlisted_bounded_and_has_no_input_or_focus_fallback(self):
        body = SOURCE.split('void RevealActionTarget(', 1)[1].split('static double CenteredScrollPercent(', 1)[0]
        for expected in ('name==Save||name==Record', 'name==Selection||name==Ocr',
                         'Need(matches.Count==1', 'visibilityOperations.Count<32', 'depth<32',
                         'Automation.Compare(cursor,root)', 'Need(reached,"SCROLL_TARGET_LEFT_OWN_ROOT")'):
            self.assertIn(expected, body)
        self.assertEqual(body.count('.ScrollIntoView()'), 1)
        self.assertEqual(body.count('.SetScrollPercent('), 1)
        for forbidden in ('SetFocus(', 'SendInput(', '.Invoke()', '.Toggle()', 'AutomationElement.RootElement'):
            self.assertNotIn(forbidden, body)
        self.assertIn('if(!offscreen)return true', body)
        self.assertIn('Find(name,type)!=null', body)
        self.assertIn('2000,"SHORTCUT_TARGET_NOT_VISIBLE_AFTER_SCROLL"', body)

    def test_action_refinds_visible_target_after_scroll_without_retrying_action(self):
        invoke = SOURCE.split('void Invoke(string name)', 1)[1].split('bool Status(', 1)[0]
        self.assertLess(invoke.index('RevealActionTarget(name,ControlType.Button)'), invoke.index('Find(name,ControlType.Button)'))
        self.assertIn('Need(e!=null,"SHORTCUT_BUTTON_NOT_VISIBLE")', invoke)
        self.assertEqual(invoke.count('((InvokePattern)invocation).Invoke()'), 1)
        self.assertEqual(invoke.count('((TogglePattern)toggle).Toggle()'), 1)
        self.assertIn('else if(name==Record&&supportsToggle)', invoke)
        self.assertNotIn('catch', invoke)
        self.assertIn('FieldsVisible()&&Field(name)==value', SOURCE)
        self.assertIn('report["casesExpected"]=6', SOURCE)
        self.assertIn('const int TotalMilliseconds = 180000, UiaCallMilliseconds = 5000', SOURCE)

    def test_scroll_geometry_centers_target_instead_of_guessing_document_end(self):
        body = SOURCE.split('static double CenteredScrollPercent(', 1)[1].split('string Field(', 1)[0]
        self.assertIn('height*(100/view-1)', body)
        self.assertIn('current+(target-center)*100/range', body)
        self.assertIn('Double.IsNaN', body)
        self.assertIn('view>0&&view<100', body)
        # Same documented UIA percent/view-size calculation, including clamping.
        def percent(current, view, height, target, center):
            return max(0, min(100, current + (target-center)*100/(height*(100/view-1))))
        self.assertAlmostEqual(percent(0, 25, 500, 650, 250), 26.666666666666668)
        self.assertEqual(percent(50, 50, 400, 200, 400), 0)
        self.assertEqual(percent(50, 50, 400, 1200, 400), 100)


if __name__ == '__main__':
    unittest.main()
