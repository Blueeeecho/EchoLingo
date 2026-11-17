"""The owned occluder metadata wait precedes, never retries, strict capture."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'tests/macos-screenshot-native-fixture.swift').read_text()
WAIT = SOURCE.split('    func awaitOwnedOracleWindowMetadata(', 1)[1].split('    // Only the generated, process-owned', 1)[0]

class OwnedOracleReadinessContract(unittest.TestCase):
    def test_only_missing_owned_metadata_waits_under_one_deadline(self):
        for expected in ('Date() <= deadline', 'oracleSourceIdentity(target)', 'oracleOccluder === window',
                         'window.frame == expectedFrame', 'window.level == .normal', 'window.sharingType == .readOnly',
                         'kCGWindowNumber', 'kCGWindowOwnerPID', 'matches.count == 1',
                         'captureWindowIsCurrent(identity', 'if matches.isEmpty {',
                         'deadline: deadline', 'observations: observations + 1', '.now() + 0.025'):
            self.assertIn(expected, WAIT)
        self.assertNotIn('addingTimeInterval', WAIT)
        self.assertIn('finish("failed"', WAIT)
        self.assertIn('deadline: Date().addingTimeInterval(3)', SOURCE)

    def test_wait_never_captures_changes_windows_or_permissions(self):
        for forbidden in ('captureImage(', 'SCContentFilter', 'captureVisibilityOracle(', 'orderFront', 'orderOut',
                          '.activate(', 'CGRequest', 'CGEvent(', 'kCGWindowName', 'kCGWindowOwnerName', 'finish("passed"'):
            self.assertNotIn(forbidden, WAIT)

    def test_strict_occlusion_and_restoration_checks_remain(self):
        self.assertEqual(SOURCE.count('stage: "generated-occlusion", occluded: true'), 1)
        self.assertLess(SOURCE.index('self.awaitOwnedOracleWindowMetadata(window'), SOURCE.index('stage: "generated-occlusion"'))
        for expected in ('SCContentFilter(display: display, excludingWindows: [])',
                         'owned oracle occluder identity/frame/sharing changed',
                         'unobstructed oracle accepted generated occlusion',
                         'stage: "restored", occluded: false'):
            self.assertIn(expected, SOURCE)

if __name__ == '__main__':
    unittest.main()
