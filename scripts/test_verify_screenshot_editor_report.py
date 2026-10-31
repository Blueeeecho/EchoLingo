import copy
import json
import hashlib
import unittest
from verify_screenshot_editor_report import EXPECTED_CASES, verify, verify_report, verify_installed_acceptance


def complete(installed=False):
    report = {field: True for field in ('ok', 'actualApplicationTested', 'screenshotEditorTestsRequested',
        'defaultCaptureWithoutEnvironmentRequested', 'captureBackendEnvironmentAbsent', 'rustCaptureRequested',
        'uiAutomationSelectorsUsed', 'screenshotOutputIsOwnedTemporaryDirectory',
        'ownApplicationTreeStopped', 'ownedDirectoriesRemoved')}
    report.update(screenshotOwnedClipboardCleared=True, screenshotClipboardPolicySelfTests=5,
        screenshotClipboardCleanup='verified-owned-generation-cleared')
    report.update(installedPackageTested=installed, desktopDirectoryWritten=False, credentialsCreated=False,
        translationBackend='not-invoked-local-image-only', applicationSha256='a'*64, expectedNativeCaptureSha256='b'*64,
        screenshotNetworkEvidenceScope='configured-loopback-provider-trap; no global packet capture',
        screenshotOcrInvocationCount=0, screenshotHttpConnections=0, screenshotTranslationHistoryCount=0,
        screenshotRequiredCases=3, screenshotPassedCases=3, verifiedNativeCaptureGenerations=3)
    report['screenshotCases'] = [{'case': case, 'ok': True, 'shortcut': 'F1', 'hotkeyPresses': 1} for case in EXPECTED_CASES]
    report['screenshotCases'][1].update({field: True for field in ('allExportPixelsMatchSystemClipboard', 'noOverwrite',
        'noHiddenPngMetadataOrTrailingData', 'nativeSaveAsCancelPreservedImage', 'nativeOpenCancelPreservedImage')})
    report['screenshotCases'][1].update(savedPngCount=2, copiedPixelSize=[624, 94])
    report['screenshotCases'][2].update(visibleWindowPixelSize=[700, 200], expectedWindowDimensions=[700, 200])
    report.update(screenshotLocalOpenRequiredCases=2, screenshotLocalOpenPassedCases=2,
        screenshotFinalExportCount=4, screenshotEditorSurvivedOwnedFocusLoss=True)
    report['screenshotLocalOpenCases'] = [dict(format=kind, ok=True, nativeDialogSubmitted=True,
        savedFlattenedPngPixelsMatched=True, sourceBytesUnchanged=True, copiedPixelSize=[24, 16])
        for kind in ('png', 'jpeg')]
    report['screenshotNativeCompletion'] = dict(nativeCaptureBackend=1, attemptStage=4, helperResponseReceived=1,
        nativeHostStopped=1, ocrInvocationCount=0, hookRunningAfterStop=0, inputPlaneRemainingAfterCleanup=0,
        currentHostSessionReserved=0, currentHostOwnedButtons=0)
    return report


class ScreenshotEditorReport(unittest.TestCase):
    def installed_acceptance(self):
        stage = b"synthetic-stage-" + b"__TAURI_BUNDLE_TYPE_VAR_UNK" + b"-tail"
        installed = stage.replace(b"__TAURI_BUNDLE_TYPE_VAR_UNK", b"__TAURI_BUNDLE_TYPE_VAR_NSS")
        expected = hashlib.sha256(installed).hexdigest()
        outer = {field: True for field in ('ok', 'windowsRuntimeExecuted', 'installerExecuted', 'realModelExecuted',
                 'installedPackageTested', 'installedScreenshotEditorVerified', 'rulesRemoved', 'ownedInstallRemoved')}
        outer.update(mockTranslationUsed=False, applicationSha256=expected, installedScreenshotEditor=complete(True))
        outer['installedScreenshotEditor']['applicationSha256'] = expected
        outer['applicationIdentity'] = dict(stageSha256=hashlib.sha256(stage).hexdigest(), installedSha256=expected,
            expectedNsisSha256=expected, markerOffset=stage.index(b'__TAURI'), stageMarker='__TAURI_BUNDLE_TYPE_VAR_UNK',
            installedMarker='__TAURI_BUNDLE_TYPE_VAR_NSS', changedBytes=3, comparedBytes=len(stage), actualExecutablesModified=False)
        return stage, outer

    def test_required_installed_editor_is_bound_to_complete_staged_bytes(self):
        stage, outer = self.installed_acceptance()
        self.assertEqual(verify_installed_acceptance(json.dumps(outer), stage), outer['installedScreenshotEditor'])
        with self.assertRaises(ValueError): verify_installed_acceptance(json.dumps(outer), stage + b'changed')
        outer['applicationIdentity']['changedBytes'] = 4
        with self.assertRaises(ValueError): verify_installed_acceptance(json.dumps(outer), stage)

    def test_installed_coverage_and_cleanup_cannot_be_optional(self):
        for field in ('installedScreenshotEditorVerified', 'rulesRemoved', 'ownedInstallRemoved', 'realModelExecuted'):
            stage, outer = self.installed_acceptance(); outer[field] = False
            with self.assertRaises(ValueError): verify_installed_acceptance(json.dumps(outer), stage)
        stage, outer = self.installed_acceptance()
        outer['installedScreenshotEditor']['screenshotLocalOpenPassedCases'] = 1
        with self.assertRaises(ValueError): verify_installed_acceptance(json.dumps(outer), stage)

    def rejects(self, report, **kwargs):
        with self.assertRaises(ValueError): verify_report(report, **kwargs)

    def test_complete_built_and_installed_reports_pass(self):
        self.assertEqual(verify('\ufeffrunner text\n'+json.dumps(complete()), 'a'*64), complete())
        self.assertEqual(verify_report(complete(True), 'a'*64, True), complete(True))

    def test_missing_duplicate_reports_fail(self):
        for text in ('none', json.dumps(complete())+'\n'+json.dumps(complete())):
            with self.assertRaises(ValueError): verify(text)

    def test_exact_binary_and_installation_identity_required(self):
        self.rejects(complete(), expected_sha='b'*64)
        self.rejects(complete(), installed=True)
        self.rejects(complete(True))
        report=complete();report['applicationSha256']='';self.rejects(report)

    def test_required_scope_and_cleanup_cannot_be_missing(self):
        for field in ('ok', 'actualApplicationTested', 'screenshotEditorTestsRequested', 'uiAutomationSelectorsUsed',
                      'captureBackendEnvironmentAbsent', 'screenshotOutputIsOwnedTemporaryDirectory',
                      'ownApplicationTreeStopped', 'ownedDirectoriesRemoved', 'desktopDirectoryWritten',
                      'credentialsCreated', 'screenshotNetworkEvidenceScope', 'translationBackend'):
            report=complete();del report[field];self.rejects(report)

    def test_exact_three_cases_no_duplicates_or_retries(self):
        for kind in ('missing','duplicate','reordered','retry','failed'):
            report=complete()
            if kind=='missing':report['screenshotCases'].pop()
            if kind=='duplicate':report['screenshotCases'][1]=copy.deepcopy(report['screenshotCases'][0])
            if kind=='reordered':report['screenshotCases'].reverse()
            if kind=='retry':report['screenshotCases'][0]['hotkeyPresses']=2
            if kind=='failed':report['screenshotCases'][0]['ok']=False
            self.rejects(report)
        for field in ('screenshotRequiredCases','screenshotPassedCases','verifiedNativeCaptureGenerations'):
            report=complete();report[field]=2;self.rejects(report)

    def test_zero_effects_require_actual_integer_measurements(self):
        for field in ('screenshotOcrInvocationCount','screenshotHttpConnections','screenshotTranslationHistoryCount'):
            for value in (None, False, 1):
                report=complete();report[field]=value;self.rejects(report)

    def test_real_pixel_exports_and_dialog_cancellation_required(self):
        for field in ('allExportPixelsMatchSystemClipboard','noOverwrite','noHiddenPngMetadataOrTrailingData',
                      'nativeSaveAsCancelPreservedImage','nativeOpenCancelPreservedImage','savedPngCount','copiedPixelSize'):
            report=complete();del report['screenshotCases'][1][field];self.rejects(report)
        report=complete();report['screenshotCases'][2]['visibleWindowPixelSize']=[699,200];self.rejects(report)

    def test_finally_cleanup_requires_exact_owned_image_generation(self):
        for field, values in (
            ('screenshotOwnedClipboardCleared', (None, False)),
            ('screenshotClipboardPolicySelfTests', (None, True, 4)),
            ('screenshotClipboardCleanup', (None, 'already-empty', 'foreign-generation-preserved')),
        ):
            for value in values:
                report=complete();report[field]=value;self.rejects(report)

    def test_actual_local_png_and_jpeg_open_are_mandatory(self):
        for field in ('screenshotLocalOpenRequiredCases', 'screenshotLocalOpenPassedCases',
                      'screenshotFinalExportCount', 'screenshotEditorSurvivedOwnedFocusLoss', 'screenshotLocalOpenCases'):
            report=complete();del report[field];self.rejects(report)
        for kind in ('missing', 'duplicate', 'reordered', 'failed', 'changed-source', 'wrong-pixels', 'no-native-dialog'):
            report=complete();cases=report['screenshotLocalOpenCases']
            if kind=='missing':cases.pop()
            if kind=='duplicate':cases[1]=copy.deepcopy(cases[0])
            if kind=='reordered':cases.reverse()
            if kind=='failed':cases[0]['ok']=False
            if kind=='changed-source':cases[0]['sourceBytesUnchanged']=False
            if kind=='wrong-pixels':cases[1]['copiedPixelSize']=[25,16]
            if kind=='no-native-dialog':cases[1]['nativeDialogSubmitted']=False
            self.rejects(report)

    def test_every_native_completion_field_is_required(self):
        for field in complete()['screenshotNativeCompletion']:
            report=complete();del report['screenshotNativeCompletion'][field];self.rejects(report)
        report=complete();report['screenshotNativeCompletion']['nativeCaptureBackend']=True;self.rejects(report)


if __name__ == '__main__': unittest.main()
