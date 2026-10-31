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
                  captureGesturesOwnAppKitOnly=True, globalSystemUISetupEventDispatched=False,
                  globalSystemUISetupEscapePairs=0,
                  ownedSourceCleanupConfirmed=True, captureCasesPassed=True,
                  screenCapturePreflightGranted=True, nativeProcessExitCode=0, cases=[],
                  sourceWindowServerReady=True, sourceReadinessObservations=1,
                  sourceWindowServerReadinessMethod='exact-geometric-metadata',
                  sourcePhaseAcknowledged=2,
                  fixtureBinarySha256='1' * 64, productionSourceSha256={path: '2' * 64 for path in module.SOURCES})
    for flag in ('permissionRequested', 'securitySettingsChanged', 'generalClipboardTouched', 'userContentCaptured',
                 'physicalF1Tested', 'packagedEditorTested', 'rustClipboardBackendTested',
                 'physicalMultiDisplayTested', 'monitorGapRuntimeTested'):
        report[flag] = False
    for flag in module.INDEPENDENT:
        report[flag] = True
    for mode in module.MODES:
        case = dict(mode=mode, ok=True, hoverOutlineVerified=True, exactOwnedSourceRevalidated=True,
                    exactSelectorRetirementVerified=True, selectorRetirementObservations=1,
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

    def test_global_setup_escape_is_single_scoped_and_never_an_occlusion_exemption(self):
        report = passed()
        report.update(ownAppKitEventsOnly=False, globalSystemUISetupEventDispatched=True,
                      globalSystemUISetupEscapePairs=1, systemUISetupOcclusionCleared=True)
        for flag in ('systemUISetupGitHubHosted', 'systemUISetupAccessibilityPreflightGranted', 'systemUISetupExactDockOwnerVerified',
                     'systemUISetupGeneratedSourceFrontmost', 'systemUISetupExactSourceRevalidated'):
            report[flag] = True
        self.assertEqual(module.verify(report), 0)
        for field, value in [('ownAppKitEventsOnly', True), ('globalSystemUISetupEscapePairs', 2),
                             ('systemUISetupGitHubHosted', False),
                             ('systemUISetupAccessibilityPreflightGranted', False),
                             ('systemUISetupExactDockOwnerVerified', False),
                             ('systemUISetupGeneratedSourceFrontmost', False),
                             ('systemUISetupExactSourceRevalidated', False),
                             ('systemUISetupOcclusionCleared', False)]:
            invalid = copy.deepcopy(report); invalid[field] = value
            with self.assertRaises(ValueError): module.verify(invalid)

    def test_pixel_oracle_never_replaces_actual_five_native_cases(self):
        report = passed()
        report.update(nativePickerStartedAfterVisibilityOracle=True, visibilityOracleHostedRunnerVerified=True,
                      visibilityOraclePassed=True, visibilityOracleGeneratedOccluderRejected=True,
                      visibilityOracleOwnedOccluderHidden=True, sourceWindowServerReadinessMethod='independent-composited-pixels',
                      visibilityOracleOverlaySharingGuardVerified=True, visibilityOracleIntersectingSharedOverlayCount=1,
                      visibilityOracleExcludedWindowCount=0, visibilityOraclePixelBytesRetained=False,
                      visibilityOracleRegion='exact-generated-source-512x320')
        report.update(phase2CurrentCompositeVerified=True, phase2ReadinessUsedSingleDeadline=True,
                      phase2ReadinessMismatchCategory=0, phase2ReadinessObservations=3, phase2KnownPriorPhaseObservations=2)
        for case in report['cases']:
            case.update(preCaseFullCompositeVerified=True, postCaseFullCompositeVerified=True)
        self.assertEqual(module.verify(report), 0)
        for field in ('preCaseFullCompositeVerified', 'postCaseFullCompositeVerified'):
            invalid = copy.deepcopy(report); del invalid['cases'][0][field]
            with self.assertRaises(ValueError): module.verify(invalid)
        for field, value in [('visibilityOraclePassed', False), ('visibilityOracleGeneratedOccluderRejected', False),
                             ('visibilityOracleOwnedOccluderHidden', False),
                             ('visibilityOracleOverlaySharingGuardVerified', False),
                             ('visibilityOracleIntersectingSharedOverlayCount', -1),
                             ('sourceWindowServerReadinessMethod', 'exact-geometric-metadata'),
                             ('visibilityOracleHostedRunnerVerified', False), ('visibilityOracleExcludedWindowCount', 1),
                             ('visibilityOraclePixelBytesRetained', True), ('visibilityOracleRegion', 'smaller-patch'),
                             ('sourcePhaseAcknowledged', 1), ('phase2CurrentCompositeVerified', False),
                             ('phase2ReadinessUsedSingleDeadline', False), ('phase2ReadinessMismatchCategory', 1),
                             ('phase2ReadinessObservations', 1), ('phase2KnownPriorPhaseObservations', -1),
                             ('cases', [])]:
            invalid = copy.deepcopy(report); invalid[field] = value
            with self.assertRaises(ValueError): module.verify(invalid)

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
        self.assertIn('NSRunningApplication(processIdentifier: Int32(pid))', swift)
        self.assertIn('ownerBundleIdentifier', swift)
        self.assertIn('ownerExecutablePath', swift)
        self.assertNotIn('runningApplications', swift)
        self.assertNotIn('localizedName', swift)
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

    def test_exact_selector_retirement_is_required(self):
        for field, value in [('exactSelectorRetirementVerified', False), ('selectorRetirementObservations', 0),
                             ('selectorRetirementObservations', True)]:
            report = passed(); report['cases'][2][field] = value
            with self.assertRaises(ValueError): module.verify(report)
        root = Path(__file__).resolve().parents[1]
        swift = (root/'tests/macos-screenshot-native-fixture.swift').read_text()
        retirement = swift.split('func awaitSelectorRetirement(', 1)[1].split('func acceptCaseResponse(', 1)[0]
        self.assertIn('activeSelectorFrames.first', retirement)
        self.assertIn('Double(ownPID)', retirement)
        self.assertIn('== expected', retirement)
        self.assertIn('Date() < deadline', retirement)
        self.assertLess(retirement.index('Date() <= deadline'), retirement.index('captureCurrentWindows()'))
        self.assertLess(retirement.index('Date() <= deadline'), retirement.index('acceptCaseResponse('))
        self.assertIn('unknown own window remains', retirement)
        self.assertNotIn('send(', retirement)
        self.assertIn('caseStarted.addingTimeInterval(6)', swift)

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
        for forbidden in ('CGRequestScreenCaptureAccess(', 'AXIsProcessTrustedWithOptions(', 'NSPasteboard.general', 'CGWindowListCreateImage('):
            self.assertNotIn(forbidden, swift)
        self.assertNotIn('.post(tap:', swift)
        oracle = swift.split('func beginVisibilityOracle()', 1)[1].split('func sourceIdentityDiagnostic(', 1)[0]
        self.assertIn('environment["GITHUB_ACTIONS"] == "true"', oracle)
        self.assertIn('environment["RUNNER_ENVIRONMENT"] == "github-hosted"', oracle)
        self.assertIn('cases.isEmpty, operation == nil', oracle)
        self.assertIn('SCContentFilter(display: display, excludingWindows: [])', oracle)
        self.assertIn('configuration.sourceRect = roi', oracle)
        self.assertIn('configuration.scalesToFit = false', oracle)
        self.assertIn('self.oracleToken == token', oracle)
        self.assertGreaterEqual(oracle.count('try verifyOracleWindows()'), 3)
        self.assertIn('stage: "generated-occlusion", occluded: true', oracle)
        self.assertIn('visibilityOracleGeneratedOccluderRejected', oracle)
        self.assertIn('guard !window.isVisible else', oracle)
        self.assertIn('independent-composited-pixels', oracle)
        self.assertIn('NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)', oracle)
        self.assertIn('captureHoverWindow($0, at: point', oracle)
        for forbidden in ('desktopIndependentWindow', 'captureScreenKitImage(', 'captureNativeRegionImage(', '.candidate ='):
            self.assertNotIn(forbidden, oracle)
        identity = swift.split('func oracleSourceIdentity(', 1)[1].split('func beginVisibilityOracle()', 1)[0]
        self.assertIn('sharing == 1 || sharing == 2', identity)
        self.assertIn('protected or unknown-sharing overlay', identity)
        self.assertIn('verifyPixels(image', swift)
        self.assertIn('try captureScreenshotSelfTest()', swift)
        self.assertIn('stage: "pre-case-" + mode, occluded: false, phase: sourcePhase', swift)
        self.assertIn('stage: "post-case-" + mode, occluded: false, phase: sourcePhase', swift)
        self.assertIn('readinessDeadline ?? Date().addingTimeInterval(8)', swift)
        self.assertIn('readinessDeadline: deadline, priorPhaseObservations: priorPhaseObservations + 1', swift)
        self.assertIn('stage == "pre-case-window-phase2", phase == 2, !occluded', swift)
        self.assertIn('self.operation == nil, self.activeCase == nil', swift)
        self.assertIn('if priorMatched && Date() < deadline', swift)
        live = swift.split('func verifyCaseSource()', 1)[1].split('func beginCase()', 1)[0]
        self.assertIn('captureWindowIsCurrent(target', live)
        self.assertIn('captureHoverWindow(records, at: point', live)
        self.assertIn('$0 is CaptureSelectionPanel && $0.isVisible', live)
        self.assertIn('selectorIDs.contains', live)
        self.assertIn('sharing == 1 || sharing == 2', live)
        self.assertNotIn('com.apple.dock', live)
        self.assertIn('owned-source-cleanup-or-cursor-restore-failed', swift)

if __name__ == '__main__': unittest.main()
