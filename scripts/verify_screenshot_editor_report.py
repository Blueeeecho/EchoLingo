#!/usr/bin/env python3
"""Verify real application F1 editing; browser mock IPC is not native evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re

EXPECTED_CASES = ('escape-cancel', 'drag-redact-crop-copy-save-twice', 'click-window-close-cancel-confirm')


def verify_report(report, expected_sha=None, installed=False):
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
    for field in ('screenshotRequiredCases', 'screenshotPassedCases'):
        if type(report.get(field)) is not int or report[field] != 3:
            raise ValueError('All three real F1 editor workflows must pass')
    if type(report.get('verifiedNativeCaptureGenerations')) is not int or report['verifiedNativeCaptureGenerations'] < 3:
        raise ValueError('At least three byte-verified native capture generations are required')
    cases = report.get('screenshotCases')
    if (not isinstance(cases, list) or len(cases) != 3
            or any(not isinstance(case, dict) for case in cases)
            or tuple(case.get('case') for case in cases) != EXPECTED_CASES):
        raise ValueError('Exact ordered F1 editor workflow inventory is required')
    for case in cases:
        if (case.get('ok') is not True or case.get('shortcut') != 'F1'
                or type(case.get('hotkeyPresses')) is not int or case['hotkeyPresses'] != 1):
            raise ValueError('Each F1 workflow requires exactly one real shortcut and success')
    drag = cases[1]
    for field in ('allExportPixelsMatchSystemClipboard', 'noOverwrite', 'noHiddenPngMetadataOrTrailingData',
                  'nativeSaveAsCancelPreservedImage', 'nativeOpenCancelPreservedImage'):
        if drag.get(field) is not True:
            raise ValueError('Real image export/cancellation evidence is absent: ' + field)
    if type(drag.get('savedPngCount')) is not int or drag['savedPngCount'] != 2 or drag.get('copiedPixelSize') != [624, 94]:
        raise ValueError('Actual cropped clipboard pixels and two collision-safe PNGs are required')
    click = cases[2]
    size = click.get('visibleWindowPixelSize')
    if (not isinstance(size, list) or len(size) != 2 or any(type(value) is not int or value <= 0 for value in size)
            or size != click.get('expectedWindowDimensions')):
        raise ValueError('Clicked-window exported pixels must match independently measured native bounds')
    for field, value in (('screenshotLocalOpenRequiredCases', 2), ('screenshotLocalOpenPassedCases', 2),
                         ('screenshotFinalExportCount', 4)):
        if type(report.get(field)) is not int or report[field] != value:
            raise ValueError('Both native local image imports and four final exports are required: ' + field)
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
    for field, value in (('nativeCaptureBackend', 1), ('attemptStage', 4), ('helperResponseReceived', 1),
                         ('nativeHostStopped', 1), ('ocrInvocationCount', 0), ('hookRunningAfterStop', 0),
                         ('inputPlaneRemainingAfterCleanup', 0), ('currentHostSessionReserved', 0), ('currentHostOwnedButtons', 0)):
        if type(health.get(field)) is not int or health[field] != value:
            raise ValueError('Actual native F1 completion or cleanup is incomplete: ' + field)
    return report


def verify(text, expected_sha=None, installed=False):
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
    return verify_report(reports[0], expected_sha, installed)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--application', type=Path, required=True)
    parser.add_argument('--installed', action='store_true')
    args = parser.parse_args()
    expected_sha = hashlib.sha256(args.application.read_bytes()).hexdigest()
    verify(args.report.read_text(encoding='utf-8-sig'), expected_sha, args.installed)
    print('PASS: all three real F1 workflows, both native local image imports, native exports and bounded zero-OCR/provider/history evidence verified.')
