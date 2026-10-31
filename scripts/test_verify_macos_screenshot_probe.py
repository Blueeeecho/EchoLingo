import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('mac_probe', Path(__file__).with_name('verify-macos-screenshot-probe.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def passed():
    report = dict(schema='echolingo-macos-screenshot-native-v1', ok=True, status='passed',
                  productionNativeEntryPoint='capture-screenshot', ownAppKitEventsOnly=True,
                  ownedSourceCleanupConfirmed=True, captureCasesPassed=True,
                  screenCapturePreflightGranted=True, nativeProcessExitCode=0, cases=[],
                  sourceWindowServerReady=True, sourceReadinessObservations=1,
                  fixtureBinarySha256='1' * 64, productionSourceSha256={path: '2' * 64 for path in module.SOURCES})
    for flag in ('permissionRequested', 'securitySettingsChanged', 'generalClipboardTouched', 'userContentCaptured',
                 'physicalF1Tested', 'packagedEditorTested', 'rustClipboardBackendTested',
                 'physicalMultiDisplayTested', 'monitorGapRuntimeTested'):
        report[flag] = False
    for flag in module.INDEPENDENT:
        report[flag] = True
    for mode in module.MODES:
        case = dict(mode=mode, ok=True, hoverOutlineVerified=True, exactOwnedSourceRevalidated=True,
                    ownAppKitEventDispatched=mode != 'request-cancel', nativeCancellationEndpointDispatched=mode == 'request-cancel', visiblePanelsAfter=0)
        if 'cancel' in mode:
            case['nativeCancelled'] = True
        else:
            case.update(imageWidth=512, imageHeight=320, generatedVisiblePixelsVerified=True, ownOverlayPixelsAbsent=True)
        report['cases'].append(case)
    return report


class MacScreenshotProbeContract(unittest.TestCase):
    def test_full_native_evidence_is_passed(self):
        self.assertEqual(module.verify(passed()), 0)

    def test_window_server_readiness_is_required_without_weakening_capture(self):
        for field, value in [('sourceWindowServerReady', False), ('sourceReadinessObservations', 0)]:
            report = passed(); report[field] = value
            with self.assertRaises(ValueError): module.verify(report)
        root = Path(__file__).resolve().parents[1]
        swift = (root/'tests/macos-screenshot-native-fixture.swift').read_text()
        self.assertIn('self.awaitInitialSource(deadline: Date().addingTimeInterval(2)', swift)
        self.assertIn('if phase == 1 {', swift)
        self.assertIn('productionProjectionAccepted', swift)
        self.assertIn('exactProductionTargetMatches', swift)
        self.assertIn('image.setPixel(pixel.baseAddress!', swift)
        self.assertNotIn('image.setColor(.green', swift)
        self.assertIn('window.orderFrontRegardless()', swift)
        self.assertIn('!panel.isVisible && !owner.isVisible && owner.attachedSheet == nil', swift)
        self.assertIn('sourceOccluderDiagnostic', swift)
        self.assertIn('try fixtureNeed(frame.intersection(target.frame).isEmpty', swift)
        self.assertNotIn('kCGWindowName', swift)
        diagnostics = swift.split('func sourceIdentityDiagnostic(', 1)[1].split('func verifySourceVisible()', 1)[0]
        self.assertIn('Double(target.pid)', diagnostics)
        self.assertIn('Double(target.id)', diagnostics)
        self.assertNotIn('kCGWindowName', diagnostics)

    def test_preflight_block_is_nonzero_not_successful_skip(self):
        report = passed()
        report.update(ok=False, status='blocked', reason='screen-recording-preflight-false',
                      screenCapturePreflightGranted=False, captureCasesPassed=False, cases=[], nativeProcessExitCode=2)
        self.assertEqual(module.verify(report), 2)
        for field, value in [('ok', True), ('nativeProcessExitCode', 0), ('captureCasesPassed', True)]:
            invalid = copy.deepcopy(report); invalid[field] = value
            with self.assertRaises(ValueError): module.verify(invalid)

    def test_scope_and_permission_changes_are_never_accepted(self):
        for field in ('permissionRequested', 'securitySettingsChanged', 'physicalF1Tested', 'packagedEditorTested', 'generalClipboardTouched'):
            report = passed(); report[field] = True
            with self.assertRaises(ValueError): module.verify(report)

    def test_no_missing_or_duplicate_native_case(self):
        for cases in [passed()['cases'][:-1], passed()['cases'] + [passed()['cases'][0]]]:
            report = passed(); report['cases'] = cases
            with self.assertRaises(ValueError): module.verify(report)

    def test_pixels_or_cleanup_failure_cannot_pass(self):
        for field, value in [('generatedVisiblePixelsVerified', False), ('ownOverlayPixelsAbsent', False),
                             ('visiblePanelsAfter', 1), ('imageBase64', 'private'), ('imageWidth', 0)]:
            report = passed(); report['cases'][0][field] = value
            with self.assertRaises(ValueError): module.verify(report)

    def test_independent_native_subtests_remain_required(self):
        for flag in module.INDEPENDENT:
            report = passed(); report[flag] = False
            with self.assertRaises(ValueError): module.verify(report)

    def test_cancel_does_not_retain_image(self):
        report = passed(); report['cases'][2]['imageWidth'] = 1
        with self.assertRaises(ValueError): module.verify(report)

    def test_provenance_cannot_be_missing_malformed_or_wrong_source_set(self):
        for field, value in [('fixtureBinarySha256', None), ('fixtureBinarySha256', 'not-a-hash'),
                             ('productionSourceSha256', {}),
                             ('productionSourceSha256', {path: 'g' * 64 for path in module.SOURCES})]:
            report = passed(); report[field] = value
            with self.assertRaises(ValueError): module.verify(report)

    def test_request_cancellation_is_not_mislabeled_as_appkit_input(self):
        report = passed(); report['cases'][3]['ownAppKitEventDispatched'] = True
        with self.assertRaises(ValueError): module.verify(report)
        report = passed(); report['cases'][3]['nativeCancellationEndpointDispatched'] = False
        with self.assertRaises(ValueError): module.verify(report)

    def test_fixture_only_uses_public_preflight_and_owned_events(self):
        root = Path(__file__).resolve().parents[1]
        swift = (root/'tests/macos-screenshot-native-fixture.swift').read_text()
        self.assertIn('CGPreflightScreenCaptureAccess()', swift)
        self.assertIn('nativeResponse(mode: "--capture-screenshot"', swift)
        self.assertIn('NSApplication.shared.sendEvent(event)', swift)
        self.assertIn('captureWindowIsCurrent(target', swift)
        for forbidden in ('CGRequestScreenCaptureAccess(', 'AXIsProcessTrustedWithOptions(', '.post(tap:', 'NSPasteboard.general', 'CGWindowListCreateImage('):
            self.assertNotIn(forbidden, swift)
        self.assertIn('verifyPixels(image', swift)
        self.assertIn('owned-source-cleanup-or-cursor-restore-failed', swift)

if __name__ == '__main__': unittest.main()
