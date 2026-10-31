#!/usr/bin/env python3
"""Require every isolated F1 selector case and exact native session cleanup."""
import json
from pathlib import Path
import sys

EXPECTED_MODES = (
    'click-visible-window', 'click-small-jitter', 'drag-rectangle-wins',
    'drag-out-and-back-is-not-click', 'moved-target-fails-closed',
    'hidden-target-fails-closed', 'protected-target-fails-closed',
    'visible-overlap-stays-in-image', 'escape-cancels', 'next-request-after-cancel',
)
REJECTED = {
    'drag-out-and-back-is-not-click': 'CANCELLED:',
    'moved-target-fails-closed': 'CAPTURE_WINDOW_CHANGED:',
    'hidden-target-fails-closed': 'CAPTURE_WINDOW_CHANGED:',
    'protected-target-fails-closed': 'CAPTURE_WINDOW_CHANGED:',
    'escape-cancels': 'CANCELLED:',
}


def verify(text):
    reports = []
    for line in text.lstrip('\ufeff').splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict) and 'screenshotPurpose' in value:
            reports.append(value)
    if len(reports) != 1:
        raise ValueError('Exactly one F1 native selector report is required')
    report = reports[0]
    for field in ('ok', 'screenshotPurpose', 'productionModulesImported'):
        if report.get(field) is not True:
            raise ValueError('F1 success or production purpose evidence is absent')
    for field in ('userContentCaptured', 'clipboardAccessed', 'ocrInvoked'):
        if report.get(field) is not False:
            raise ValueError('F1 generated-image-only scope is absent or invalid')
    stopped = report.get('hostShutdown')
    if (type(report.get('startedGenerations')) is not int or report['startedGenerations'] != 10
            or report.get('hostExitedNormally') is not True
            or report.get('hostShutdownError') is not None
            or not isinstance(stopped, dict) or stopped.get('event') != 'stopped'
            or stopped.get('ok') is not True or stopped.get('productionObserverStopRequested') is not True
            or type(stopped.get('completedGenerations')) is not int or stopped['completedGenerations'] != 10):
        raise ValueError('F1 host must normally stop after exactly 10 native generations')
    cases = report.get('cases')
    if (not isinstance(cases, list) or len(cases) != len(EXPECTED_MODES)
            or any(not isinstance(case, dict) for case in cases)
            or tuple(case.get('mode') for case in cases) != EXPECTED_MODES):
        raise ValueError('All 10 distinct F1 native cases must execute in order')
    for generation, case in enumerate(cases, 1):
        for field in ('ok', 'hoverWindowOutlineVerified', 'zeroUnderlyingInput'):
            if case.get(field) is not True:
                raise ValueError('F1 case lacks success, hover outline or input ownership')
        if type(case.get('generation')) is not int or case['generation'] != generation:
            raise ValueError('F1 native generations must advance exactly once')
        setup = case.get('generatedSourceSetup')
        if not isinstance(setup, dict):
            raise ValueError('Exact generated-source readiness evidence is required before F1 input')
        for field in ('exactEndpointReadinessConfirmed', 'firstRootIsSourceA', 'lastRootIsSourceB',
                      'foregroundIsSourceA', 'exactFramesUnchanged', 'firstRootSameProcess', 'lastRootSameProcess'):
            if setup.get(field) is not True:
                raise ValueError('Generated source readiness was not established: ' + field)
        for field in ('firstRootIsBackground', 'lastRootIsBackground'):
            if setup.get(field) is not False:
                raise ValueError('Generated input must not hit the fixture background')
        if type(setup.get('observations')) is not int or setup['observations'] < 3:
            raise ValueError('At least three exact read-only readiness observations are required')
        closed = case.get('hostSessionClosure')
        rejected = case['mode'] in REJECTED
        if (not isinstance(closed, dict) or closed.get('event') != 'closed'
                or type(closed.get('generation')) is not int or closed['generation'] != generation
                or closed.get('sessionCloseCalled') is not True
                or closed.get('helperDeadlineKilled') is not False
                or type(closed.get('hostThreadId')) is not int or closed['hostThreadId'] <= 0
                or type(closed.get('helperExitCode')) is not int
                or closed['helperExitCode'] != (1 if rejected else 0)):
            raise ValueError('F1 session did not close normally with its exact generation')
        native = case.get('helperDiagnostics')
        if not isinstance(native, dict) or native.get('ok') is not (not rejected):
            raise ValueError('F1 expected native success or fail-closed result is absent')
        if native.get('nativeBackend') != 'rust-win32-capture':
            raise ValueError('F1 report must identify the actual Rust native backend')
        health = native.get('captureHealth')
        if not isinstance(health, dict):
            raise ValueError('F1 native input ownership and cleanup health is required')
        for field, expected in (
            ('nativeCaptureBackend', 1), ('nativeHostReady', 1),
            ('nativeHostArmed', 1), ('nativeHostStopped', 1),
            ('inputPlaneRemainingAfterCleanup', 0), ('inputPlaneVisibleCount', 0),
            ('hookRunningAfterStop', 0),
        ):
            if type(health.get(field)) is not int or health[field] != expected:
                raise ValueError('F1 native backend/cleanup health is incomplete: ' + field)
        if any(key in native or key in case for key in ('imageBase64', 'text')):
            raise ValueError('F1 report must not retain image pixels or selected text')
        if rejected:
            if not isinstance(native.get('error'), str) or not native['error'].startswith(REJECTED[case['mode']]):
                raise ValueError('F1 rejection was not the expected fail-closed condition')
            if 'imageWidth' in case or 'imageHeight' in case:
                raise ValueError('A rejected F1 case must not produce image dimensions')
        else:
            if any(type(case.get(field)) is not int or case[field] <= 0 for field in ('imageWidth', 'imageHeight')):
                raise ValueError('Successful F1 capture requires actual positive image dimensions')
    return report


if __name__ == '__main__':
    verify(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    print('PASS: all 10 F1 native selector cases and exact session cleanup verified; packaged editor is separate.')
