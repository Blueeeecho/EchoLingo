"""A previously owned but destroyed HWND may be omitted, never accepted as ready."""
from pathlib import Path
import re
import unittest

APP = (Path(__file__).resolve().parent / 'windows-application-smoke.ps1').read_text()


class DestroyedInputPlaneContract(unittest.TestCase):
    def test_absence_requires_every_identity_observation_to_be_empty(self):
        body = APP.split('static bool ConclusiveDestroyedPlaneRow(', 1)[1].split('static bool PreviouslyVerifiedPlaneDestroyed(', 1)[0]
        expression = re.search(r'return (.*?);', body, re.S).group(1)
        self.assertEqual(expression.split('&&'), [
            'verifiedOwnedRow ', ' !existsBefore ', ' ownerBefore==0 ', ' threadBefore==0\n            ',
            ' classLength==0 ', ' ownerAfter==0 ', ' threadAfter==0 ', ' !existsAfter'])
        # The actual C# fixture runs positive/negative classifier tests before input.
        tests = APP.split('static void VerifyDestroyedPlaneRowClassifier()', 1)[1].split('static long hiddenPlaneStyleChecks', 1)[0]
        self.assertEqual(tests.count('ConclusiveDestroyedPlaneRow('), 10)
        for evidence in ('false,false,0,0,0,0,0,false', 'true,true,0,0,0,0,0,false',
                         'true,false,1,0,0,0,0,false', 'true,false,0,1,0,0,0,false',
                         'true,false,0,0,1,0,0,false', 'true,false,0,0,-1,0,0,false',
                         'true,false,0,0,0,1,0,false', 'true,false,0,0,0,0,1,false',
                         'true,false,0,0,0,0,0,true'):
            self.assertIn('!ConclusiveDestroyedPlaneRow(' + evidence + ')', tests)
        run = APP.split('public static Dictionary<string, object> Run(', 1)[1]
        self.assertLess(run.index('VerifyDestroyedPlaneRowClassifier();'), run.index('report["destroyedPlaneRowClassifierVerified"]=true'))

    def test_native_absence_observation_is_bracketed_and_read_only(self):
        body = APP.split('static bool PreviouslyVerifiedPlaneDestroyed(', 1)[1].split('static void VerifyDestroyedPlaneRowClassifier()', 1)[0]
        self.assertIn('VerifiedNativeChildren.ContainsKey(verifiedOwner)', body)
        self.assertEqual(body.count('GetWindowThreadProcessId('), 2)
        self.assertEqual(body.count('IsWindow('), 2)
        self.assertEqual(body.count('GetClassName('), 1)
        ordered = ['bool existsBefore=IsWindow(window)', 'GetWindowThreadProcessId(window,out before)',
                   'GetClassName(window,name,name.Capacity)', 'GetWindowThreadProcessId(window,out after)',
                   'bool existsAfter=IsWindow(window)', 'return ConclusiveDestroyedPlaneRow(']
        self.assertEqual([body.index(item) for item in ordered], sorted(body.index(item) for item in ordered))
        for forbidden in ('rejectedHelper', 'Thread.Sleep', 'SendInput', 'SetWindow', 'ShowWindow', 'result.Add', 'catch'):
            self.assertNotIn(forbidden, body)

    def test_scan_proves_ownership_first_and_does_not_count_destroyed_rows(self):
        body = APP.split('static List<AppEdge> AppInputPlanes(', 1)[1].split('static int AppOverlays(', 1)[0]
        first = body.index('PreviouslyVerifiedPlaneDestroyed(')
        for proof in ('!IsInputPlane(window,owner)', 'if (parent != appId) return true;', 'if(!RequireNativeChild(owner,window))return true;'):
            self.assertLess(body.index(proof), first)
        skips = re.findall(r'if \(PreviouslyVerifiedPlaneDestroyed\(window,owner,parent\)\) \{(.*?)\n                \}', body, re.S)
        self.assertEqual(len(skips), 2)
        for skip in skips:
            self.assertIn('return true;', skip)
            self.assertNotIn('result.Add', skip)
        self.assertIn('throw new InputPlaneStyleException', body)
        self.assertIn('Assert(false,"Cannot inspect actual input plane rectangle.");', body)
        self.assertIn('if ((style&required)!=required || (style&(0x00080000L|0x20L))!=0)', body)
        self.assertIn('if (requireTopmost) visiblePlaneStyleChecks++', body)
        self.assertNotIn('owner==rejectedHelper && !', body)
        self.assertEqual(body.count('result.Add('), 1)


if __name__ == '__main__':
    unittest.main()
