"""No desktop execution: preserve the strict generated-window oracle contract."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'tests/macos-screenshot-native-fixture.swift').read_text()

class OracleDiagnosticContract(unittest.TestCase):
    def test_only_owned_exact_window_fixed_metadata_is_reported(self):
        body = SOURCE.split('func recordOwnedOracleWindow(', 1)[1].split('@available(macOS 14.0, *)', 1)[0]
        self.assertIn('kCGWindowNumber as String]) == Double(id)', body)
        self.assertIn('kCGWindowOwnerPID as String]) == Double(pid)', body)
        self.assertIn('own.count == 1', body)
        for key in ('expectedFrame', 'appKitFrame', 'observedSharing', 'observedLayer', 'observedOnScreen', 'observedQuartzFrame', 'ownMatchingRecordCount'):
            self.assertIn('"' + key + '"', body)
        for forbidden in ('kCGWindowName', 'kCGWindowOwnerName', 'captureImage(', 'orderFront', 'Thread.sleep', 'activate('):
            self.assertNotIn(forbidden, body)

    def test_phase_is_set_before_identity_verification_without_relaxing_gate(self):
        body = SOURCE.split('func captureVisibilityOracle(', 1)[1]
        self.assertLess(body.index('report["visibilityOracleStage"] = stage'), body.index('let screen = try oracleSourceIdentity(expected)'))
        self.assertIn('Date().addingTimeInterval(8)', body)
        self.assertIn('guard window.isVisible, window.windowNumber > 0, window.frame == expectedFrame,', body)
        self.assertIn('try fixtureNeed(captureWindowIsCurrent(identity, records: records,', body)
        self.assertIn('"owned oracle occluder identity/frame/sharing changed"', body)
        self.assertLess(body.index('self.recordOwnedOracleWindow('), body.index('try fixtureNeed(captureWindowIsCurrent(identity'))

if __name__ == '__main__':
    unittest.main()
