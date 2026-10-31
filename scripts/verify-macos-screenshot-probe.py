#!/usr/bin/env python3
"""Classify genuine native Mac evidence without treating permission blocks as passes."""
import json
import re
from pathlib import Path
import sys

MODES = ('window-phase1', 'rectangle-phase1', 'escape-cancel', 'request-cancel', 'window-phase2')
INDEPENDENT = ('privatePasteboardImageRoundtripPassed', 'nativePNGJPEGFileRoundtripPassed',
               'nativeSavePanelCancelPassed', 'nativeSavePanelHiddenBeforeCapture')
SOURCES = {'src-tauri/native/macos.swift', 'src-tauri/native/macos_capture.swift', 'src-tauri/native/macos_window.swift'}


def verify(report):
    if not isinstance(report, dict) or report.get('schema') != 'echolingo-macos-screenshot-native-v1':
        raise ValueError('Missing native Mac screenshot report schema')
    for flag in ('permissionRequested', 'securitySettingsChanged', 'generalClipboardTouched',
                 'userContentCaptured', 'physicalF1Tested', 'packagedEditorTested',
                 'rustClipboardBackendTested', 'physicalMultiDisplayTested', 'monitorGapRuntimeTested'):
        if report.get(flag) is not False:
            raise ValueError('Native probe scope is missing or overstated: ' + flag)
    if (report.get('productionNativeEntryPoint') != 'capture-screenshot'
            or report.get('captureGesturesOwnAppKitOnly') is not True):
        raise ValueError('Missing exact native entry point or scoped AppKit event evidence')
    setup = report.get('globalSystemUISetupEventDispatched')
    if (type(setup) is not bool or report.get('ownAppKitEventsOnly') is not (not setup)
            or type(report.get('globalSystemUISetupEscapePairs')) is not int
            or report['globalSystemUISetupEscapePairs'] != int(setup)):
        raise ValueError('Global setup input must be explicitly scoped to zero or one Escape pair')
    if setup:
        for flag in ('systemUISetupGitHubHosted', 'systemUISetupAccessibilityPreflightGranted', 'systemUISetupExactDockOwnerVerified',
                     'systemUISetupGeneratedSourceFrontmost', 'systemUISetupExactSourceRevalidated'):
            if report.get(flag) is not True:
                raise ValueError('Global setup Escape lacks preapproved trust and exact source/Dock ownership')
    digest = lambda value: isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None
    sources = report.get('productionSourceSha256')
    if (not digest(report.get('fixtureBinarySha256')) or not isinstance(sources, dict)
            or set(sources) != SOURCES or any(not digest(value) for value in sources.values())):
        raise ValueError('Exact fixture binary and three production source SHA-256 identities are required')
    status = report.get('status')
    if status == 'failed':
        if report.get('ok') is not False or report.get('nativeProcessExitCode') == 0:
            raise ValueError('Failed probe cannot report success')
        return 1
    if any(report.get(flag) is not True for flag in INDEPENDENT):
        raise ValueError('Native image/pasteboard/file/dialog subtests did not pass')
    if report.get('ownedSourceCleanupConfirmed') is not True:
        raise ValueError('Generated source cleanup was not confirmed')
    if status == 'blocked':
        if (report.get('ok') is not False or report.get('reason') != 'screen-recording-preflight-false'
                or report.get('screenCapturePreflightGranted') is not False
                or report.get('captureCasesPassed') is not False or report.get('cases') != []
                or report.get('nativeProcessExitCode') != 2):
            raise ValueError('Permission-blocked probe was misclassified as a successful capture')
        return 2
    if (status != 'passed' or report.get('ok') is not True or report.get('captureCasesPassed') is not True
            or report.get('screenCapturePreflightGranted') is not True or report.get('nativeProcessExitCode') != 0):
        raise ValueError('Native capture pass lacks successful permission/runtime evidence')
    if (report.get('sourceWindowServerReady') is not True
            or type(report.get('sourceReadinessObservations')) is not int
            or report['sourceReadinessObservations'] <= 0):
        raise ValueError('Exact generated WindowServer source readiness was not observed')
    if report.get('sourceWindowServerReadinessMethod') not in ('exact-geometric-metadata', 'independent-composited-pixels'):
        raise ValueError('The source readiness method must distinguish geometry from actual composite pixels')
    if setup and report.get('systemUISetupOcclusionCleared') is not True:
        raise ValueError('The original foreign-occlusion guard must clear after setup Escape')
    if any(key.startswith('visibilityOracle') for key in report):
        for flag in ('nativePickerStartedAfterVisibilityOracle', 'visibilityOracleHostedRunnerVerified',
                     'visibilityOraclePassed', 'visibilityOracleGeneratedOccluderRejected', 'visibilityOracleOwnedOccluderHidden',
                     'visibilityOracleOverlaySharingGuardVerified'):
            if report.get(flag) is not True:
                raise ValueError('Independent full-ROI positive/negative visibility proof is incomplete')
        if (type(report.get('visibilityOracleExcludedWindowCount')) is not int
                or report['visibilityOracleExcludedWindowCount'] != 0
                or report.get('visibilityOraclePixelBytesRetained') is not False
                or report.get('visibilityOracleRegion') != 'exact-generated-source-512x320'
                or report.get('sourceWindowServerReadinessMethod') != 'independent-composited-pixels'):
            raise ValueError('Visibility oracle must retain no pixels and exclude no windows from the exact source ROI')
        if (type(report.get('visibilityOracleIntersectingSharedOverlayCount')) is not int
                or report['visibilityOracleIntersectingSharedOverlayCount'] < 0):
            raise ValueError('The independent oracle must record its protected-overlay metadata guard')
    cases = report.get('cases')
    if (not isinstance(cases, list) or len(cases) != len(MODES) or any(not isinstance(case, dict) for case in cases)
            or tuple(case.get('mode') for case in cases) != MODES):
        raise ValueError('All five native screenshot cases must execute in order')
    for case in cases:
        for flag in ('ok', 'hoverOutlineVerified', 'exactOwnedSourceRevalidated'):
            if case.get(flag) is not True:
                raise ValueError('Native screenshot case evidence is incomplete')
        endpoint_cancel = case['mode'] == 'request-cancel'
        if (case.get('ownAppKitEventDispatched') is not (not endpoint_cancel)
                or case.get('nativeCancellationEndpointDispatched') is not endpoint_cancel):
            raise ValueError('Request cancellation must not be labeled as an AppKit input event')
        if type(case.get('visiblePanelsAfter')) is not int or case['visiblePanelsAfter'] != 0:
            raise ValueError('Native selector cleanup is incomplete')
        if any(field in case for field in ('imageBase64', 'text', 'pixels')):
            raise ValueError('Probe must not retain captured pixels or text')
        if case['mode'] in ('escape-cancel', 'request-cancel'):
            if case.get('nativeCancelled') is not True or 'imageWidth' in case or 'imageHeight' in case:
                raise ValueError('Native cancellation must return no image')
        else:
            if any(type(case.get(field)) is not int or case[field] <= 0 for field in ('imageWidth', 'imageHeight')):
                raise ValueError('Native screenshot has no actual image dimensions')
            if case.get('generatedVisiblePixelsVerified') is not True or case.get('ownOverlayPixelsAbsent') is not True:
                raise ValueError('Real generated visible pixels and overlay exclusion must be verified')
    return 0


if __name__ == '__main__':
    report = json.loads(Path(sys.argv[1]).read_text())
    result = verify(report)
    print(('PASS: native generated-window capture probe; not packaged/physical F1 acceptance.' if result == 0 else
           'BLOCKED: screen recording is not preapproved; independent native image/pasteboard/dialog checks passed.' if result == 2 else
           'FAILED: native screenshot coverage probe.'))
    raise SystemExit(result)
