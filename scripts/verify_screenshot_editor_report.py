#!/usr/bin/env python3
"""Verify real application F1 editing; browser mock IPC is not native evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re

EXPECTED_CASES = ('escape-cancel', 'inplace-drag-copy-recapture-save-twice', 'click-window-copy-then-cancel')


PIN_CASES = ('inplace-pin-passive-physical', 'inplace-pin-annotated-active-editor')
PIN_FIELDS = ('rasterVisible', 'initialNativeAdjustmentPreservedSourceForeground', 'pinAndMainNotObservedForeground',
              'nativeAdjustmentVisible', 'nativeAdjustmentMoveResizeVerified', 'nativeAdjustmentGeometryRestored', 'nativeActionOwnedTargetVerified',
              'decodedReferenceVisibleAndCaptureDismissed', 'nativeTopmostInitially',
              'initialOuterFrameWithinSourceWorkArea', 'nativeUnpinVerified', 'nativeRepinVerified',
              'nativeMoveResizeVerified', 'rasterRetainedAfterResize', 'nativeWindowDestroyed',
              'clipboardUnchanged', 'exportDirectoryUnchanged')


NATIVE_COMPLETION = (('nativeCaptureBackend', 1), ('attemptStage', 4), ('helperResponseReceived', 1),
                     ('nativeHostStopped', 1), ('ocrInvocationCount', 0), ('hookRunningAfterStop', 0),
                     ('inputPlaneRemainingAfterCleanup', 0), ('currentHostSessionReserved', 0), ('currentHostOwnedButtons', 0))


def verify_adjustment(case, action):
    if (not isinstance(case, dict) or case.get('nativeInitialAction') != action
            or type(case.get('nativeActionClickCount')) is not int or case['nativeActionClickCount'] != 1
            or type(case.get('nativeAdjustmentHandleCount')) is not int or case['nativeAdjustmentHandleCount'] != 8):
        raise ValueError('Exact native adjustment action and eight handles are required')
    for field in ('nativeAdjustmentVisible', 'nativeAdjustmentHintVisible', 'initialNativeAdjustmentPreservedSourceForeground', 'nativeActionOwnedTargetVerified'):
        if case.get(field) is not True:
            raise ValueError('Native adjustment evidence absent: ' + field)


def verify_pin(report):
    if any(type(report.get(field)) is not int or report[field] != 2 for field in ('screenshotPinRequiredCases', 'screenshotPinPassedCases')):
        raise ValueError('Both passive and annotated native pin cases are required')
    cases = report.get('screenshotPinCases')
    if (not isinstance(cases, list) or len(cases) != 2 or any(not isinstance(case, dict) for case in cases)
            or tuple(case.get('case') for case in cases) != PIN_CASES):
        raise ValueError('Exact ordered native pin case inventory is required')
    for annotated, case in zip((False, True), cases):
        if case.get('shortcut') != 'F1' or type(case.get('hotkeyPresses')) is not int or case['hotkeyPresses'] != 1 or case.get('ok') is not True:
            raise ValueError('Each native pin must start with one real F1')
        for field in PIN_FIELDS:
            if case.get(field) is not True:
                raise ValueError('Native pin evidence absent: ' + field)
        verify_adjustment(case, 'solid' if annotated else 'pin')
        if annotated and (case.get('initialEditorShowPreservedSourceForeground') is not True or case.get('nativeInitialToolClaimed') is not True):
            raise ValueError('Native solid action must be claimed before intentional editor annotation')
        if case.get('annotationApplied') is not annotated or case.get('editedRasterVisible') is not annotated:
            raise ValueError('Annotated and pristine raster evidence must not be conflated')
        if case.get('passiveShowPreservedSourceForeground') is not (not annotated):
            raise ValueError('Only passive physical pinning claims source foreground preservation')
        if case.get('pinInputMethod') != ('uia-invoke-from-active-editor' if annotated else 'owned-native-adjustment-click'):
            raise ValueError('Pin input must represent the tested foreground state')
        if type(case.get('physicalPinClickCount')) is not int or case['physicalPinClickCount'] != (0 if annotated else 1):
            raise ValueError('Only the passive case sends exactly one physical pin click')
        if not annotated:
            for field in ('nativeNoActivateBeforePhysicalClick', 'physicalPinClickOwnedTargetVerified'):
                if case.get(field) is not True:
                    raise ValueError('Passive click ownership evidence absent: ' + field)
        if type(case.get('handoffForegroundSamples')) is not int or case['handoffForegroundSamples'] < 1:
            raise ValueError('Native handoff foreground samples are required')
        for phase in ('foregroundBeforePinInvoke', 'foregroundAfterPinInvoke', 'foregroundDuringPinHandoff', 'foregroundAtVisibleHandoff'):
            state = case.get(phase)
            if not isinstance(state, dict) or any(type(state.get(field)) is not bool for field in ('isGeneratedSource', 'isEditor', 'isPin', 'isMain', 'isApp', 'isZero')):
                raise ValueError('Exact bounded foreground phase evidence is required')
            if state['isPin'] or state['isMain']:
                raise ValueError('Pin/main activated during the handoff')
            if phase == 'foregroundBeforePinInvoke' and state['isEditor' if annotated else 'isGeneratedSource'] is not True:
                raise ValueError('Pin action began in the wrong foreground state')
            if not annotated and not (state['isGeneratedSource'] or state['isZero']):
                raise ValueError('Passive pin observed non-source foreground')
            if not annotated and phase == 'foregroundAtVisibleHandoff' and not state['isGeneratedSource']:
                raise ValueError('Passive completed handoff did not preserve source foreground')


def verify_report(report, expected_sha=None, installed=False, pin_only=False):
    if not isinstance(report, dict):
        raise ValueError('A real application screenshot report is required')
    for field in ('ok', 'actualApplicationTested', 'screenshotEditorTestsRequested',
                  'defaultCaptureWithoutEnvironmentRequested', 'captureBackendEnvironmentAbsent', 'rustCaptureRequested',
                  'uiAutomationSelectorsUsed', 'screenshotOutputIsOwnedTemporaryDirectory',
                  'ownApplicationTreeStopped', 'ownedDirectoriesRemoved'):
        if report.get(field) is not True:
            raise ValueError('Required real F1 application evidence is absent: ' + field)
    if report.get('screenshotOwnedClipboardCleared') is not True:
        raise ValueError('Exact owned image clipboard generation must be cleared in fixture cleanup')
    if report.get('screenshotClipboardCleanup') != 'verified-owned-generation-cleared':
        raise ValueError('Successful F1 workflows require exact owned-generation cleanup, not unknown or empty clipboard')
    if type(report.get('screenshotClipboardPolicySelfTests')) is not int or report['screenshotClipboardPolicySelfTests'] != 5:
        raise ValueError('All five clipboard ownership policy self-tests are required')
    if report.get('installedPackageTested') is not installed:
        raise ValueError('Built and installed application coverage must not be conflated')
    if report.get('desktopDirectoryWritten') is not False or report.get('credentialsCreated') is not False:
        raise ValueError('Generated F1 fixture must not write a real Desktop or create credentials')
    if report.get('translationBackend') != 'not-invoked-local-image-only':
        raise ValueError('F1 editor must not invoke a translation provider')
    if report.get('screenshotNetworkEvidenceScope') != 'configured-loopback-provider-trap; no global packet capture':
        raise ValueError('The bounded network observation scope must be explicit')
    native_sha = report.get('expectedNativeCaptureSha256')
    if not isinstance(native_sha, str) or re.fullmatch(r'[0-9a-f]{64}', native_sha) is None:
        raise ValueError('Exact native screenshot helper identity is required')
    sha = report.get('applicationSha256')
    if not isinstance(sha, str) or re.fullmatch(r'[0-9a-f]{64}', sha) is None or (expected_sha is not None and sha != expected_sha):
        raise ValueError('Screenshot application hash differs from the exact expected binary')
    for field in ('screenshotOcrInvocationCount', 'screenshotHttpConnections', 'screenshotTranslationHistoryCount'):
        if type(report.get(field)) is not int or report[field] != 0:
            raise ValueError('F1 must have zero observed OCR/provider/history effects: ' + field)
    verify_pin(report)
    if report.get('screenshotPinOnly') is not pin_only:
        raise ValueError('Pin-only and complete editor evidence must not be conflated')
    if pin_only:
        cancelled = report.get('screenshotCases')
        if (not isinstance(cancelled, list) or len(cancelled) != 1 or not isinstance(cancelled[0], dict)
                or cancelled[0].get('case') != 'escape-cancel' or cancelled[0].get('ok') is not True
                or cancelled[0].get('shortcut') != 'F1' or type(cancelled[0].get('hotkeyPresses')) is not int
                or cancelled[0]['hotkeyPresses'] != 1):
            raise ValueError('Pin-only requires its successful single-F1 cancellation baseline')
        if type(report.get('screenshotFinalExportCount')) is not int or report['screenshotFinalExportCount'] != 0 or type(report.get('verifiedNativeCaptureGenerations')) is not int or report['verifiedNativeCaptureGenerations'] != 3:
            raise ValueError('Pin-only path must retain zero exports and verified cancel/pin generations')
        health = report.get('screenshotNativeCompletion', {})
        for field, value in NATIVE_COMPLETION:
            if type(health.get(field)) is not int or health[field] != value:
                raise ValueError('Pin native cleanup incomplete: ' + field)
        return report
    for field in ('screenshotRequiredCases', 'screenshotPassedCases'):
        if type(report.get(field)) is not int or report[field] != 3:
            raise ValueError('All three real F1 editor workflows must pass')
    if type(report.get('verifiedNativeCaptureGenerations')) is not int or report['verifiedNativeCaptureGenerations'] != 8:
        raise ValueError('Exactly eight byte-verified native capture generations are required')
    cases = report.get('screenshotCases')
    if (not isinstance(cases, list) or len(cases) != 3
            or any(not isinstance(case, dict) for case in cases)
            or tuple(case.get('case') for case in cases) != EXPECTED_CASES):
        raise ValueError('Exact ordered F1 editor workflow inventory is required')
    for case, presses in zip(cases, (1, 3, 2)):
        if (case.get('ok') is not True or case.get('shortcut') != 'F1'
                or type(case.get('hotkeyPresses')) is not int or case['hotkeyPresses'] != presses):
            raise ValueError('F1 workflows must preserve exact cancel/copy/save-recapture counts')
    drag = cases[1]
    verify_adjustment(drag, 'solid')
    for field in ('allExportPixelsMatchSystemClipboard', 'noOverwrite', 'noHiddenPngMetadataOrTrailingData',
                  'nativeSaveAsCancelPreservedImage', 'nativeOpenCancelPreservedImage'):
        if drag.get(field) is not True:
            raise ValueError('Real image export/cancellation evidence is absent: ' + field)
    if type(drag.get('savedPngCount')) is not int or drag['savedPngCount'] != 2 or drag.get('copiedPixelSize') != [624, 94]:
        raise ValueError('Actual cropped clipboard pixels and two collision-safe PNGs are required')
    for field in ('inplaceCopyAndSavesDismissed', 'savedCaptureReopenedThroughSettings', 'standaloneCollisionNumberingVerified'):
        if drag.get(field) is not True:
            raise ValueError('Current in-place workflow evidence absent: ' + field)
    if type(drag.get('standaloneCollisionSaveCount')) is not int or drag['standaloneCollisionSaveCount'] != 2:
        raise ValueError('Both standalone collision-numbered saves are required')
    saves = drag.get('recapturedSaveSessions')
    if not isinstance(saves, list) or len(saves) != 2 or any(not isinstance(item, dict) or item.get('shortcut') != 'F1' or type(item.get('hotkeyPresses')) is not int or item['hotkeyPresses'] != 1 for item in saves):
        raise ValueError('Both saves require a fresh native capture')
    for saved in saves:
        verify_adjustment(saved, 'solid')
    click = cases[2]
    verify_adjustment(click, 'select')
    if click.get('inplaceCopyDismissed') is not True or click.get('inplaceCancelPreservedClipboard') is not True or not isinstance(click.get('cancelSession'), dict) or click['cancelSession'].get('shortcut') != 'F1' or type(click['cancelSession'].get('hotkeyPresses')) is not int or click['cancelSession']['hotkeyPresses'] != 1:
        raise ValueError('Clicked capture must copy-dismiss then cancel a fresh capture')
    verify_adjustment(click['cancelSession'], 'select')
    size = click.get('visibleWindowPixelSize')
    if (not isinstance(size, list) or len(size) != 2 or any(type(value) is not int or value <= 0 for value in size)
            or size != click.get('expectedWindowDimensions')):
        raise ValueError('Clicked-window exported pixels must match independently measured native bounds')
    for field, value in (('screenshotLocalOpenRequiredCases', 2), ('screenshotLocalOpenPassedCases', 2),
                         ('screenshotFinalExportCount', 6)):
        if type(report.get(field)) is not int or report[field] != value:
            raise ValueError('Both native local image imports and six final exports are required: ' + field)
    if report.get('screenshotEditorSurvivedOwnedFocusLoss') is not True:
        raise ValueError('Dedicated editor must survive unrelated owned-window focus loss')
    opened = report.get('screenshotLocalOpenCases')
    if (not isinstance(opened, list) or len(opened) != 2
            or any(not isinstance(case, dict) for case in opened)
            or tuple(case.get('format') for case in opened) != ('png', 'jpeg')):
        raise ValueError('Exactly one generated PNG and JPEG must pass actual native Open')
    for case in opened:
        for field in ('ok', 'nativeDialogSubmitted', 'savedFlattenedPngPixelsMatched', 'sourceBytesUnchanged'):
            if case.get(field) is not True:
                raise ValueError('Native local image import evidence is absent: ' + field)
        size = case.get('copiedPixelSize')
        if (not isinstance(size, list) or len(size) != 2
                or any(type(value) is not int for value in size) or size != [24, 16]):
            raise ValueError('Actual local image clipboard pixels must match the generated source dimensions')
    health = report.get('screenshotNativeCompletion')
    if not isinstance(health, dict):
        raise ValueError('Actual packaged native completion is required')
    for field, value in NATIVE_COMPLETION:
        if type(health.get(field)) is not int or health[field] != value:
            raise ValueError('Actual native F1 completion or cleanup is incomplete: ' + field)
    return report


def verify(text, expected_sha=None, installed=False, pin_only=False):
    reports = []
    for line in text.lstrip('\ufeff').splitlines():
        try:
            report = json.loads(line)
        except ValueError:
            continue
        if isinstance(report, dict) and 'screenshotEditorTestsRequested' in report:
            reports.append(report)
    if len(reports) != 1:
        raise ValueError('Exactly one actual application screenshot report is required')
    return verify_report(reports[0], expected_sha, installed, pin_only)


def verify_installed_acceptance(text, stage_bytes):
    """Bind the mandatory installed editor report to this complete staged app."""
    # Only the already hash-pinned historical resource-reuse executable may
    # retain its old editor contract. Never trust a report version/flag for this.
    if (len(stage_bytes) == 7944192 and hashlib.sha256(stage_bytes).hexdigest()
            == 'cdee16da380d9746c5e1ea212b27bad615605ec543f57a29bfc8a1b6e6e53c25'):
        from verify_screenshot_editor_baseline_report import verify_installed_acceptance as verify_baseline
        return verify_baseline(text, stage_bytes)
    report = json.loads(text.lstrip('\ufeff'))
    for field in ('ok', 'windowsRuntimeExecuted', 'installerExecuted', 'realModelExecuted',
                  'installedPackageTested', 'installedScreenshotEditorVerified',
                  'rulesRemoved', 'ownedInstallRemoved'):
        if report.get(field) is not True:
            raise ValueError('Actual installed acceptance is incomplete: ' + field)
    if report.get('mockTranslationUsed') is not False:
        raise ValueError('Installed real-model acceptance must not be mocked')
    marker, replacement = b'__TAURI_BUNDLE_TYPE_VAR_UNK', b'__TAURI_BUNDLE_TYPE_VAR_NSS'
    if stage_bytes.count(marker) != 1:
        raise ValueError('Exactly one staged Tauri bundle marker is required')
    offset = stage_bytes.index(marker)
    stage_sha = hashlib.sha256(stage_bytes).hexdigest()
    installed_sha = hashlib.sha256(stage_bytes[:offset] + replacement + stage_bytes[offset + len(marker):]).hexdigest()
    identity = report.get('applicationIdentity')
    if not isinstance(identity, dict):
        raise ValueError('Actual installed application identity is absent')
    expected = dict(stageSha256=stage_sha, installedSha256=installed_sha,
                    expectedNsisSha256=installed_sha, markerOffset=offset,
                    stageMarker=marker.decode(), installedMarker=replacement.decode(),
                    changedBytes=3, comparedBytes=len(stage_bytes), actualExecutablesModified=False)
    for field, value in expected.items():
        if type(identity.get(field)) is not type(value) or identity[field] != value:
            raise ValueError('Installed bytes do not match the complete stage identity: ' + field)
    if report.get('applicationSha256') != installed_sha:
        raise ValueError('Installed application hash differs from this build')
    return verify_report(report.get('installedScreenshotEditor'), installed_sha, installed=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--application', type=Path, required=True)
    parser.add_argument('--installed', action='store_true')
    parser.add_argument('--pin-only', action='store_true')
    parser.add_argument('--installed-acceptance', action='store_true',
                        help='Verify nested actual NSIS editor evidence against the complete staged app')
    args = parser.parse_args()
    stage_bytes = args.application.read_bytes()
    text = args.report.read_text(encoding='utf-8-sig')
    if args.installed_acceptance:
        verify_installed_acceptance(text, stage_bytes)
    else:
        verify(text, hashlib.sha256(stage_bytes).hexdigest(), args.installed, args.pin_only)
    print('PASS: native pin lifecycle verified.' if args.pin_only else 'PASS: current in-place F1 workflows, native pin lifecycle, local imports/exports and bounded zero-OCR/provider/history evidence verified.')
