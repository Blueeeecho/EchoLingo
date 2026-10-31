import copy
import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('capture_report', Path(__file__).with_name('verify-native-capture-report.py'))
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


def complete_report():
    cases = [{'mode': mode, 'ok': True,
              'helperDiagnostics': {'captureHealth': {'magnifierSampleThreadStopped': 1}}}
             for mode in sorted(REPORT.EXPECTED_MODES)]
    case = next(case for case in cases if case['mode'] == 'magnifier-continuity-armed-and-dragging')
    case.update(generatedFinalTargetReadyBeforeHelper=True, coreOk=True, qualityOk=True, qualityDiagnostics=[],
                zeroUnderlyingInput=True, foregroundPreserved=True, postSessionSourceClickRestored=True,
                hostAliveAfterSessionClose=True, capturedPhysicalSize=[120, 40], blueHintPixelsInCapture=0)
    case['helperDiagnostics'] = {'nativeBackend': 'rust-win32-capture', 'captureHealth': {
        'magnifierSampleThreadStopped': 1, 'magnifierSampleCompleted': 30, 'magnifierFrameAgeMillisecondsMax': 80,
        'nativeCaptureBackend': 1, 'nativeHostStopped': 1, 'inputPlaneRemainingAfterCleanup': 0}}
    for phase in ('armed', 'dragging'):
        case[phase + 'MagnifierMovingPixels'] = {
            'distinctMotionPixelColors': 4, 'maximumColorRefreshMilliseconds': 100,
            'finalTargetPixelMatched': True, 'pixelObservations': 20, 'observerStopped': True, 'observerFailed': False, 'samplePixelsStored': False}
        case[phase + 'MagnifierLivePixels'] = {
            'generatedColorChanges': 3, 'maximumRefreshMilliseconds': 50,
            'livePixelRefreshVerified': True, 'visibleThroughoutLiveProbe': True, 'samplePixelsStored': False}
        case[phase + 'MagnifierContinuity'] = {
            'durationMilliseconds': 956, 'visibilitySamples': 300, 'invisibleSamples': 0,
            'hideEvents': 0, 'locationEvents': 25, 'eventObserverPositiveControl': True,
            'generatedMoves': 25, 'distinctMotionPositions': 24,
            'finalTargetSettledMilliseconds': 16, 'continuousObservation': True}
    return {'ok': True, 'productionModulesImported': True, 'userContentCaptured': False,
            'clipboardAccessed': False, 'requestedInputBackend': 'delegated-exact-production', 'cases': cases,
            'acceptancePolicy': 'core-functional-v1', 'fineQualityBlocking': False}


def continuity(report):
    return next(case for case in report['cases'] if case['mode'].startswith('magnifier-continuity'))


class CaptureReportTests(unittest.TestCase):
    def reject(self, report):
        with self.assertRaises(ValueError): REPORT.verify(json.dumps(report))

    def test_complete_report_with_bom_and_surrounding_output(self):
        report = complete_report()
        self.assertEqual(REPORT.verify('\ufefffixture output\n' + json.dumps(report) + '\ndone'), report)

    def test_old_reports_are_not_retroactively_relabelled(self):
        for field in ('acceptancePolicy', 'fineQualityBlocking'):
            report = complete_report(); del report[field]; self.reject(report)
        for field in ('coreOk', 'qualityOk', 'qualityDiagnostics'):
            report = complete_report(); del continuity(report)[field]; self.reject(report)

    def test_absent_duplicate_or_failed_report(self):
        good = json.dumps(complete_report())
        for text in ('', 'PASS', good + '\n' + good, '{"productionModulesImported":true,"ok":false}'):
            with self.subTest(text=text[:30]), self.assertRaises(ValueError): REPORT.verify(text)

    def test_missing_duplicate_failed_and_wrong_cases(self):
        for change in (lambda cases: cases.pop(), lambda cases: cases.append(copy.deepcopy(cases[0])),
                       lambda cases: cases[0].update(ok=False), lambda cases: cases[0].update(mode='wrong')):
            report = complete_report(); change(report['cases']); self.reject(report)

    def test_scope_identity_and_core_input_cleanup_cannot_be_diagnostics(self):
        for field in ('ok', 'productionModulesImported', 'userContentCaptured', 'clipboardAccessed', 'requestedInputBackend'):
            report = complete_report(); del report[field]; self.reject(report)
        for field in ('generatedFinalTargetReadyBeforeHelper', 'coreOk', 'zeroUnderlyingInput',
                      'foregroundPreserved', 'postSessionSourceClickRestored', 'hostAliveAfterSessionClose'):
            report = complete_report(); continuity(report)[field] = False; self.reject(report)
        report = complete_report(); continuity(report)['capturedPhysicalSize'] = [0, 40]; self.reject(report)
        report = complete_report(); continuity(report)['blueHintPixelsInCapture'] = 1; self.reject(report)

    def test_all_sampling_workers_must_stop_and_production_age_policy_remains(self):
        for mode in REPORT.EXPECTED_MODES:
            report = complete_report()
            next(c for c in report['cases'] if c['mode'] == mode)['helperDiagnostics']['captureHealth']['magnifierSampleThreadStopped'] = 0
            self.reject(report)
        for field, value in (('magnifierSampleCompleted', 0), ('magnifierFrameAgeMillisecondsMax', 201),
                             ('nativeCaptureBackend', 0), ('nativeHostStopped', 0), ('inputPlaneRemainingAfterCleanup', 1)):
            report = complete_report(); continuity(report)['helperDiagnostics']['captureHealth'][field] = value; self.reject(report)

    def test_fine_visual_misses_are_explicit_nonblocking_diagnostics(self):
        changes = [('MagnifierMovingPixels', 'finalTargetPixelMatched', False, 'final-pixel-deadline'),
                   ('MagnifierMovingPixels', 'distinctMotionPixelColors', 2, 'moving-color-count'),
                   ('MagnifierMovingPixels', 'maximumColorRefreshMilliseconds', 201, 'moving-color-refresh'),
                   ('MagnifierLivePixels', 'maximumRefreshMilliseconds', 201, 'stationary-refresh'),
                   ('MagnifierContinuity', 'distinctMotionPositions', 11, 'motion-follow-density'),
                   ('MagnifierContinuity', 'hideEvents', 1, 'visibility-continuity'),
                   ('MagnifierContinuity', 'eventObserverPositiveControl', False, 'event-positive-control')]
        for phase in ('armed', 'dragging'):
            for section, field, value, code in changes:
                report = complete_report(); case = continuity(report)
                case[phase + section][field] = value
                case.update(qualityOk=False, qualityDiagnostics=[phase + '-' + code])
                self.assertEqual(REPORT.verify(json.dumps(report)), report)

    def test_raw_visual_miss_cannot_be_silently_relabelled_quality_pass(self):
        report = complete_report()
        continuity(report)['armedMagnifierMovingPixels']['finalTargetPixelMatched'] = False
        self.reject(report)

    def test_diagnostic_records_must_be_bounded_honest_and_nonprivate(self):
        for diagnostics, passed in ((['unknown'], False), (['armed-final-pixel-deadline'] * 2, False),
                                    (['armed-final-pixel-deadline'], True), ([], False)):
            report = complete_report(); continuity(report).update(qualityOk=passed, qualityDiagnostics=diagnostics); self.reject(report)
        for phase in ('armed', 'dragging'):
            for section, field, value in (('MagnifierMovingPixels', 'observerStopped', False),
                                          ('MagnifierMovingPixels', 'observerFailed', None),
                                          ('MagnifierLivePixels', 'visibleThroughoutLiveProbe', None),
                                          ('MagnifierMovingPixels', 'samplePixelsStored', True),
                                          ('MagnifierLivePixels', 'samplePixelsStored', True),
                                          ('MagnifierContinuity', 'continuousObservation', False),
                                          ('MagnifierMovingPixels', 'maximumColorRefreshMilliseconds', True),
                                          ('MagnifierContinuity', 'visibilitySamples', None)):
                report = complete_report(); continuity(report)[phase + section][field] = value; self.reject(report)
            report = complete_report(); del continuity(report)[phase + 'MagnifierLivePixels']; self.reject(report)


if __name__ == '__main__': unittest.main()
