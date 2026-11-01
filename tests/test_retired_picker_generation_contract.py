"""Restart accepts only the new picker, not an already rejected helper's teardown."""
from pathlib import Path
import re
import unittest

APP = (Path(__file__).resolve().parent / 'windows-application-smoke.ps1').read_text()


def reject(verified, owner, started, rejected, rejected_start):
    body = APP.split('static bool RejectPreviousPlaneGeneration(', 1)[1].split('static bool ValidInputPlaneStyle(', 1)[0]
    expression = re.search(r'return (.*?);', body, re.S).group(1)
    expression = expression.replace('&&', ' and ').replace('\n', ' ')
    return eval(expression, {'__builtins__': {}}, dict(verifiedNativeChild=verified,
        owner=owner, observedStart=started, rejectedHelper=rejected, rejectedStart=rejected_start))


class RetiredPickerGenerationContract(unittest.TestCase):
    def test_only_verified_exact_previous_generation_is_excluded(self):
        self.assertTrue(reject(True, 4056, 100, 4056, 100))
        for args in [(False, 4056, 100, 4056, 100), (True, 4057, 101, 4056, 100),
                     (True, 4056, 101, 4056, 100), (True, 4056, 0, 4056, 100),
                     (True, 4056, 100, 4056, 0), (True, 4056, 100, 0, 100),
                     (True, 0, 100, 0, 100)]:
            with self.subTest(args=args):
                self.assertFalse(reject(*args))

    def test_exclusion_precedes_style_and_cannot_contribute_to_readiness(self):
        body = APP.split('static List<AppEdge> AppInputPlanes(', 1)[1].split('static int AppOverlays(', 1)[0]
        steps = ['!IsInputPlane(window,owner)', 'if (parent != appId)',
                 'if(!RequireNativeChild(owner,window))',
                 'VerifiedNativeChildren.TryGetValue(owner,out observedStart)',
                 'if(RejectPreviousPlaneGeneration(', 'if (!ValidInputPlaneStyle(', 'result.Add(']
        self.assertEqual([body.index(s) for s in steps], sorted(body.index(s) for s in steps))
        skip = body.split('if(RejectPreviousPlaneGeneration(', 1)[1].split('}', 1)[0]
        self.assertIn('retiredGenerationRowsExcluded++;return true;', skip)
        self.assertNotIn('result.Add', skip)
        self.assertIn('throw new InputPlaneStyleException', body)

    def test_generation_is_frozen_before_single_restart_input(self):
        body = APP.split('static Dictionary<string,object> StartPinnedPicker(', 1)[1].split('static bool ProcessExited(', 1)[0]
        self.assertLess(body.index('VerifiedNativeChildren.TryGetValue(rejectedPid,out rejectedStart)'), body.index('Shortcut(form,0x53)'))
        self.assertEqual(body.count('Shortcut('), 1)
        self.assertIn('probe,rejectedPid,time,rejectedStart)', body)
        self.assertIn('!=rejectedPid;', body)
        self.assertIn('},25,', body)
        self.assertIn('ProcessExited(oldPid)', APP)

    def test_windows_fixture_executes_current_and_reused_pid_negative_cases(self):
        body = APP.split('static void VerifyPreviousPlaneGenerationPolicy()', 1)[1].split('static long retiredGenerationRowsExcluded', 1)[0]
        self.assertIn('!RejectPreviousPlaneGeneration(true,4057,101,4056,100)&&!ValidInputPlaneStyle(layered,required)', body)
        self.assertIn('!RejectPreviousPlaneGeneration(true,4056,101,4056,100)&&!ValidInputPlaneStyle(layered,required)', body)
        self.assertIn('new long[]{0x00200000L,0x08000000L,0x80L,8L}', body)
        self.assertIn('VerifyPreviousPlaneGenerationPolicy();', APP)
        self.assertIn('return (style&required)==required && (style&(0x00080000L|0x20L))==0;', APP)


if __name__ == '__main__':
    unittest.main()
