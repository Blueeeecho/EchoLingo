"""Generated pin setup waits for metadata without retrying production capture."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parent / 'macos-screenshot-native-fixture.swift').read_text()
READINESS = SOURCE.split('func awaitReadyPinMetadata(', 1)[1].split('func verifyPixels(', 1)[0]
CAPTURE = SOURCE.split('func verifyReadyPinCapture()', 1)[1].split('func awaitReadyPinMetadata(', 1)[0]


class MacPinReadinessFixtureContract(unittest.TestCase):
    def test_metadata_wait_has_one_deadline_and_ignores_late_callbacks(self):
        self.assertEqual(READINESS.count('Date().addingTimeInterval(3)'), 1)
        self.assertIn('DispatchQueue.main.asyncAfter(deadline: .now() + 3)', READINESS)
        self.assertIn('Date() < deadline', READINESS)
        self.assertIn('!self.finished && self.pinReadinessToken == token', READINESS)
        self.assertIn('self.pinReadinessToken = nil; completion()', READINESS)
        self.assertIn('pinReadinessToken = nil', SOURCE.split('func finish(', 1)[1].split('func start()', 1)[0])
        self.assertEqual(READINESS.count('completion()'), 1)

    def test_only_exact_generated_window_objects_and_metadata_can_be_ready(self):
        for guard in ('self.pinProofWindows[0] === pin', 'self.pinProofWindows[1] === helper',
                      'ids[0] != ids[1]', 'captureValidateReadyPins(snapshot)',
                      'snapshot.ids == Set([ids[0]])', 'NSApp.windows.contains(where: { $0 === window })',
                      '!window.isMiniaturized', 'window.sharingType == .readOnly',
                      'window.windowNumber == Int(id) && window.frame == frame',
                      'captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(ownPID)',
                      'captureWindowNumber(record[kCGWindowSharingState as String]) == 1',
                      'captureWindowNumber(record[kCGWindowLayer as String]) == Double(window.level.rawValue)',
                      'record[kCGWindowIsOnscreen as String] as? Bool == true',
                      'rectangle == quartzFrame', '$0.windowID == id',
                      'window.owningApplication?.processID == ownPID, window.frame == quartzFrame'):
            self.assertIn(guard, READINESS)
        self.assertIn('SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true)', READINESS)
        self.assertIn('guard error == nil, let content = content else { fail(', READINESS)
        self.assertIn('guard let window = matches.first else { ready = false; continue }', READINESS)
        self.assertIn('guard let record = matches.first else { ready = false; continue }', READINESS)
        self.assertIn('if publicReady && shareableReady', READINESS)

    def test_wait_cannot_capture_or_change_windows_permissions_or_input(self):
        for forbidden in ('captureImage(', 'captureNativePlannedImage(', 'recognizeFixture(',
                          'orderFront', 'orderOut', '.activate(', 'CGRequest', 'CGEvent(',
                          'SCContentFilter', 'Thread.sleep', 'kCGWindowName', 'kCGWindowOwnerName'):
            self.assertNotIn(forbidden, READINESS)
        self.assertIn('self.finish("failed", reason: reason)', READINESS)
        self.assertNotIn('finish("passed"', READINESS)

    def test_capture_and_ocr_are_still_single_strict_operations_after_readiness(self):
        self.assertEqual(CAPTURE.count('captureNativePlannedImage(plan, purpose: .region)'), 1)
        self.assertEqual(CAPTURE.count('recognizeFixture(image)'), 1)
        self.assertLess(CAPTURE.index('awaitReadyPinMetadata(pin: pin'), CAPTURE.index('captureNativePlannedImage('))
        for guard in ('normalized == "EchoLingo pin 97531"', 'captureValidateReadyPins(snapshot)',
                      'staleRejected', 'captureReadyPinSnapshot().windows.isEmpty',
                      'reason: "pin-proof-capture-ocr-failed"'):
            self.assertIn(guard, CAPTURE)
        self.assertIn('self.recordCompletedCase(checked)', SOURCE)
        self.assertIn('if index == modes.count { verifyReadyPinCapture() }', SOURCE)


if __name__ == '__main__':
    unittest.main()
