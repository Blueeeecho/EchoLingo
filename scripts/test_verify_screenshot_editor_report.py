import copy
import json
import hashlib
import unittest
from unittest import mock
from verify_screenshot_editor_report import EXPECTED_CASES, PIN_CASES, PIN_FIELDS, verify, verify_report, verify_installed_acceptance, verify_pin_client_frame


def adjustment(action):
    return dict(webInitialAction=action, webActionClickCount=1, webAdjustmentHandleCount=8,
                webAdjustmentVisible=True, initialWebAdjustmentPreservedSourceForeground=True,
                webActionOwnedTargetVerified=True, selectionHelperExitedBeforeAdjustment=True, toolSelectionDidNotCapturePixels=True)


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
        screenshotRequiredCases=3, screenshotPassedCases=3, verifiedF1SelectionGenerations=8, verifiedDeferredPixelCaptures=6, verifiedNativeCaptureAttempts=14, verifiedFirstStrokeReleaseChecks=4)
    report['screenshotCases'] = [{'case': case, 'ok': True, 'shortcut': 'F1', 'hotkeyPresses': 1} for case in EXPECTED_CASES]
    for case, count in zip(report['screenshotCases'], (1, 3, 2)): case['hotkeyPresses'] = count
    report.update(screenshotPinOnly=False, screenshotPinRequiredCases=2, screenshotPinPassedCases=2, screenshotPinCases=[])
    for annotated, name in zip((False, True), PIN_CASES):
        source = dict(isGeneratedSource=True, isEditor=False, isPin=False, isMain=False, isApp=False, isZero=False)
        editor = dict(isGeneratedSource=False, isEditor=True, isPin=False, isMain=False, isApp=True, isZero=False)
        case = dict(case=name, shortcut='F1', hotkeyPresses=1, ok=True, **{field: True for field in PIN_FIELDS})
        case.update(annotationApplied=annotated, editedRasterVisible=annotated, passiveShowPreservedSourceForeground=not annotated,
            pinInputMethod='uia-invoke-from-active-editor' if annotated else 'owned-web-adjustment-click', physicalPinClickCount=0 if annotated else 1,
            nativeNoActivateBeforePhysicalClick=not annotated, physicalPinClickOwnedTargetVerified=not annotated, handoffForegroundSamples=1,
            foregroundBeforePinInvoke=copy.deepcopy(editor if annotated else source), foregroundAfterPinInvoke=copy.deepcopy(editor if annotated else source),
            foregroundDuringPinHandoff=copy.deepcopy(source), foregroundAtVisibleHandoff=copy.deepcopy(source))
        case.update(nativePinStyle=0x00C00000, nativePinClientFrame=dict(dpi=96, windowsBuild=26100, frameThickness=8, insets=[8,1,8,8]))
        case.update(nativeDecoratedSourceRejected=True, nativeDecoratedSourceFrame=dict(nativePinStyle=0x00C00000,nativePinClientFrame=dict(dpi=96,windowsBuild=26100,frameThickness=8,insets=[8,31,8,8])))
        case.update(adjustment('solid' if annotated else 'pin'))
        if annotated: case.update(explicitEditorInteractionVerified=True, postCaptureInteractionTarget="selected-solid-tool", postCaptureInteractionClicks=1, webInitialToolSelected=True, initialEditorShowPreservedSourceForeground=True)
        report['screenshotPinCases'].append(case)
    report['screenshotCases'][1].update({field: True for field in ('allExportPixelsMatchSystemClipboard', 'noOverwrite',
        'noHiddenPngMetadataOrTrailingData', 'nativeSaveAsCancelPreservedImage', 'nativeOpenCancelPreservedImage')})
    report['screenshotCases'][1].update(savedPngCount=2, copiedPixelSize=[624, 94], inplaceCopyAndSavesDismissed=True,
        savedCaptureReopenedThroughSettings=True, standaloneCollisionNumberingVerified=True, standaloneCollisionSaveCount=2, recapturedSaveSessions=[dict(shortcut='F1', hotkeyPresses=1) for _ in range(2)])
    report['screenshotCases'][2].update(copyInputMethod='owned-passive-physical-click',copyClickCount=1,copyPhysicalTargetOwned=True,copyNoActivateVerified=True,copySourceForegroundBefore=True,copySourceForegroundAfterClick=True,copySourceForegroundAfterCommit=True)
    report['screenshotCases'][2].update(visibleWindowPixelSize=[700, 200], expectedWindowDimensions=[700, 200], inplaceCopyDismissed=True,
        inplaceCancelPreservedClipboard=True, cancelSession=dict(shortcut='F1', hotkeyPresses=1))
    report['screenshotCases'][1].update(adjustment('solid'))
    for saved in report['screenshotCases'][1]['recapturedSaveSessions']: saved.update(adjustment('solid'))
    report['screenshotCases'][2].update(adjustment('select'))
    report['screenshotCases'][2]['cancelSession'].update(adjustment('select'))
    report.update(screenshotLocalOpenRequiredCases=2, screenshotLocalOpenPassedCases=2,
        screenshotFinalExportCount=6, screenshotEditorSurvivedOwnedFocusLoss=True)
    report['screenshotLocalOpenCases'] = [dict(format=kind, ok=True, nativeDialogSubmitted=True,
        savedFlattenedPngPixelsMatched=True, sourceBytesUnchanged=True, copiedPixelSize=[24, 16])
        for kind in ('png', 'jpeg')]
    report['screenshotNativeCompletion'] = dict(nativeCaptureBackend=1, attemptStage=4, helperResponseReceived=1,
        nativeHostStopped=1, ocrInvocationCount=0, hookRunningAfterStop=0, inputPlaneRemainingAfterCleanup=0,
        currentHostSessionReserved=0, currentHostOwnedButtons=0)
    return report


class ScreenshotEditorReport(unittest.TestCase):
    def test_historical_dispatch_is_bound_to_full_binary_hash_and_size(self):
        digest = 'cdee16da380d9746c5e1ea212b27bad615605ec543f57a29bfc8a1b6e6e53c25'
        with mock.patch('verify_screenshot_editor_report.hashlib.sha256') as sha, mock.patch('verify_screenshot_editor_baseline_report.verify_installed_acceptance', return_value={'historical': True}) as baseline:
            sha.return_value.hexdigest.return_value = digest
            self.assertEqual(verify_installed_acceptance('{}', b'x' * 7944192), {'historical': True})
            baseline.assert_called_once()
            baseline.reset_mock()
            with self.assertRaises(ValueError): verify_installed_acceptance('{}', b'x' * 7944191)
            baseline.assert_not_called()
            sha.return_value.hexdigest.return_value = 'f' * 64
            with self.assertRaises(ValueError): verify_installed_acceptance('{}', b'x' * 7944192)
            baseline.assert_not_called()

    def test_pin_lifecycle_evidence_is_mandatory(self):
        for index in (0, 1):
            for field in PIN_FIELDS:
                report = complete()
                del report['screenshotPinCases'][index][field]
                with self.assertRaises(ValueError): verify_report(report)

    def test_both_distinct_pin_modes_and_foreground_contracts_are_mandatory(self):
        for mutate in (
            lambda r: r.update(screenshotPinCases=r['screenshotPinCases'][:1]),
            lambda r: r['screenshotPinCases'].reverse(),
            lambda r: r['screenshotPinCases'][0].update(physicalPinClickCount=True),
            lambda r: r['screenshotPinCases'][0].update(nativeNoActivateBeforePhysicalClick=False),
            lambda r: r['screenshotPinCases'][0].update(physicalPinClickOwnedTargetVerified=False),
            lambda r: r['screenshotPinCases'][0].update(pinInputMethod='uia-invoke-from-active-editor'),
            lambda r: r['screenshotPinCases'][1].update(annotationApplied=False),
            lambda r: r['screenshotPinCases'][1].update(editedRasterVisible=False),
            lambda r: r['screenshotPinCases'][1].update(passiveShowPreservedSourceForeground=True),
            lambda r: r['screenshotPinCases'][1]['foregroundBeforePinInvoke'].update(isEditor=False),
            lambda r: r['screenshotPinCases'][0]['foregroundAtVisibleHandoff'].update(isGeneratedSource=False),
            lambda r: r['screenshotPinCases'][0]['foregroundAfterPinInvoke'].update(isGeneratedSource=False, isEditor=True, isApp=True),
            lambda r: r['screenshotPinCases'][0]['foregroundAfterPinInvoke'].update(isGeneratedSource=False),
            lambda r: r['screenshotPinCases'][0]['foregroundDuringPinHandoff'].update(isPin=True),
            lambda r: r['screenshotPinCases'][1]['foregroundDuringPinHandoff'].update(isMain=True),
            lambda r: r['screenshotPinCases'][1]['foregroundAfterPinInvoke'].update(isMain=True),
            lambda r: r['screenshotPinCases'][1]['foregroundAtVisibleHandoff'].update(isPin=True),
            lambda r: r.update(verifiedF1SelectionGenerations=7),
            lambda r: r.update(verifiedF1SelectionGenerations=9),
        ):
            report = complete()
            mutate(report)
            with self.assertRaises(ValueError): verify_report(report)

    def test_native_adjustment_fields_and_exact_action_cannot_be_omitted_or_forged(self):
        for index in (0, 1):
            for field, value in (
                ('webInitialAction', 'copy'), ('webActionClickCount', True),
                ('webActionClickCount', 2), ('webAdjustmentHandleCount', 7),
                ('webAdjustmentHandleCount', 8.0),
                ('webAdjustmentVisible', False), ('webActionOwnedTargetVerified', False),
                ('webAdjustmentGeometryRestored', False), ('webAdjustmentMoveResizeVerified', False)):
                report = complete()
                report['screenshotPinCases'][index][field] = value
                with self.assertRaises(ValueError): verify_report(report)
        for field in ('webInitialToolSelected', 'initialEditorShowPreservedSourceForeground'):
            report = complete()
            del report['screenshotPinCases'][1][field]
            with self.assertRaises(ValueError): verify_report(report)

    def test_every_full_capture_requires_explicit_native_action_after_adjustment(self):
        for target in ('drag', 'save0', 'save1', 'click', 'cancel'):
            report = complete()
            drag, click = report['screenshotCases'][1:]
            case = {'drag': drag, 'save0': drag['recapturedSaveSessions'][0],
                    'save1': drag['recapturedSaveSessions'][1], 'click': click,
                    'cancel': click['cancelSession']}[target]
            del case['webActionOwnedTargetVerified']
            with self.assertRaises(ValueError): verify_report(report)

    def test_persistent_overlay_counts_and_no_capture_oracles_are_strict(self):
        for field in ('verifiedF1SelectionGenerations', 'verifiedDeferredPixelCaptures', 'verifiedNativeCaptureAttempts', 'verifiedFirstStrokeReleaseChecks'):
            for invalid in (None, False, 1, float(complete()[field])):
                report = complete()
                report[field] = invalid
                with self.assertRaises(ValueError): verify_report(report)
        for field in ('toolSelectionDidNotCapturePixels', 'selectionHelperExitedBeforeAdjustment', 'explicitEditorInteractionVerified'):
            report = complete()
            del report['screenshotPinCases'][1][field]
            with self.assertRaises(ValueError): verify_report(report)
        for field, invalid in (('postCaptureInteractionTarget', 'forced-foreground'), ('postCaptureInteractionClicks', True), ('postCaptureInteractionClicks', 2)):
            report = complete()
            report['screenshotPinCases'][1][field] = invalid
            with self.assertRaises(ValueError): verify_report(report)
        for invalid in (None, True, 8.0, 7):
            report = complete()
            report['screenshotPinCases'][0]['webAdjustmentHandleCount'] = invalid
            with self.assertRaises(ValueError): verify_report(report)

    def test_pin_only_cannot_substitute_for_complete_editor(self):
        report = complete()
        report.update(screenshotPinOnly=True, screenshotFinalExportCount=0, verifiedF1SelectionGenerations=3, verifiedDeferredPixelCaptures=2, verifiedNativeCaptureAttempts=5, verifiedFirstStrokeReleaseChecks=1)
        report['screenshotNativeCompletion'].pop('nativeHostStopped')
        report['screenshotNativeCompletion'].update(nativeDeferredCapture=1, resultOk=1)
        report['screenshotCases'] = report['screenshotCases'][:1]
        self.assertEqual(verify_report(report, pin_only=True), report)
        with self.assertRaises(ValueError): verify_report(report)
        report['screenshotFinalExportCount'] = 1
        with self.assertRaises(ValueError): verify_report(report, pin_only=True)

    def test_pin_only_requires_exact_three_native_generations(self):
        for count in (2, 4, True, 3.0):
            report = complete()
            report.update(screenshotPinOnly=True, screenshotFinalExportCount=0, verifiedF1SelectionGenerations=count)
            report['screenshotCases'] = report['screenshotCases'][:1]
            with self.assertRaises(ValueError): verify_report(report, pin_only=True)

    def test_pin_only_requires_integer_counts_and_complete_native_cleanup(self):
        report = complete()
        report.update(screenshotPinOnly=True, screenshotFinalExportCount=0, verifiedF1SelectionGenerations=3, verifiedDeferredPixelCaptures=2, verifiedNativeCaptureAttempts=5, verifiedFirstStrokeReleaseChecks=1)
        report['screenshotNativeCompletion'].pop('nativeHostStopped')
        report['screenshotNativeCompletion'].update(nativeDeferredCapture=1, resultOk=1)
        report['screenshotCases'] = report['screenshotCases'][:1]
        for field, invalid in (('screenshotFinalExportCount', False), ('verifiedF1SelectionGenerations', 2.0)):
            changed = copy.deepcopy(report)
            changed[field] = invalid
            with self.assertRaises(ValueError): verify_report(changed, pin_only=True)
        for field in report['screenshotNativeCompletion']:
            changed = copy.deepcopy(report)
            del changed['screenshotNativeCompletion'][field]
            with self.assertRaises(ValueError): verify_report(changed, pin_only=True)

    def test_pin_only_requires_its_real_cancel_baseline(self):
        report = complete()
        report.update(screenshotPinOnly=True, screenshotFinalExportCount=0, verifiedF1SelectionGenerations=3, verifiedDeferredPixelCaptures=2, verifiedNativeCaptureAttempts=5, verifiedFirstStrokeReleaseChecks=1)
        report['screenshotNativeCompletion'].pop('nativeHostStopped')
        report['screenshotNativeCompletion'].update(nativeDeferredCapture=1, resultOk=1)
        for cases in ([], report['screenshotCases'], [dict(case='escape-cancel', ok=True, shortcut='F1', hotkeyPresses=True)]):
            report['screenshotCases'] = cases
            with self.assertRaises(ValueError): verify_report(report, pin_only=True)

    def test_inplace_exports_require_fresh_sessions_and_legacy_collision_proof(self):
        for field in ('inplaceCopyAndSavesDismissed', 'savedCaptureReopenedThroughSettings', 'standaloneCollisionNumberingVerified', 'standaloneCollisionSaveCount', 'recapturedSaveSessions'):
            report = complete()
            del report['screenshotCases'][1][field]
            with self.assertRaises(ValueError): verify_report(report)

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
        for field in ('screenshotRequiredCases','screenshotPassedCases','verifiedF1SelectionGenerations'):
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




class PassiveWindowCopyTests(unittest.TestCase):
    def test_exact_passive_click_and_source_preservation_required(self):
        for key, invalid in (('copyClickCount', True), ('copyClickCount', 2), ('copyInputMethod', 'uia'), ('copyPhysicalTargetOwned', False), ('copyNoActivateVerified', False), ('copySourceForegroundBefore', False), ('copySourceForegroundAfterClick', False), ('copySourceForegroundAfterCommit', False)):
            report=complete();report['screenshotCases'][2][key]=invalid
            with self.assertRaises(ValueError): verify_report(report)

class PinClientFrameTests(unittest.TestCase):
    def test_complete_report_requires_actual_decorated_negative_control(self):
        for field, value in (('nativeDecoratedSourceRejected', False), ('nativeDecoratedSourceFrame', {}), ('nativePinClientFrame', {})):
            report=complete();report['screenshotPinCases'][0][field]=value
            with self.assertRaises(ValueError): verify_report(report)
        report=complete();case=report['screenshotPinCases'][0]
        case['nativeDecoratedSourceFrame']['nativePinClientFrame']['insets']=[9,1,8,8]
        with self.assertRaises(ValueError): verify_report(report)

    def test_tao_shadow_insets_accept_caption_bits_but_reject_caption_geometry(self):
        for dpi, frame in ((96,8),(144,12),(192,16)):
            for build in (19045,26100):
                top=(dpi+48)//96 if build>=22000 else 0
                case=dict(nativePinStyle=0x00C00000, nativePinClientFrame=dict(dpi=dpi,windowsBuild=build,frameThickness=frame,insets=[frame,top,frame,frame]))
                verify_pin_client_frame(case)
                for bad_top in (top+1,top+23,top+31):
                    invalid=copy.deepcopy(case);invalid['nativePinClientFrame']['insets'][1]=bad_top
                    with self.assertRaises(ValueError): verify_pin_client_frame(invalid)
                for invalid_insets in ([-1,top,frame,frame],[frame,top,frame], [frame,True,frame,frame]):
                    invalid=copy.deepcopy(case);invalid['nativePinClientFrame']['insets']=invalid_insets
                    with self.assertRaises(ValueError): verify_pin_client_frame(invalid)

if __name__ == "__main__":
    unittest.main()
