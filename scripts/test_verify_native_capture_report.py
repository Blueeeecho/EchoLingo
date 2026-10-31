import copy
import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("capture_report", Path(__file__).with_name("verify-native-capture-report.py"))
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


def complete_report():
    cases = [{"mode": mode, "ok": True} for mode in sorted(REPORT.EXPECTED_MODES)]
    case = next(case for case in cases if case["mode"] == "magnifier-continuity-armed-and-dragging")
    for phase in ("armed", "dragging"):
        case[phase + "MagnifierLivePixels"] = {
            "generatedColorChanges": 3, "maximumRefreshMilliseconds": 50,
            "livePixelRefreshVerified": True, "samplePixelsStored": False,
        }
        case[phase + "MagnifierContinuity"] = {
            "durationMilliseconds": 956, "visibilitySamples": 300, "invisibleSamples": 0,
            "hideEvents": 0, "locationEvents": 25, "eventObserverPositiveControl": True,
            "generatedMoves": 25, "distinctMotionPositions": 24,
            "finalTargetSettledMilliseconds": 16, "continuousObservation": True,
        }
    return {"ok": True, "productionModulesImported": True, "userContentCaptured": False,
            "clipboardAccessed": False, "requestedInputBackend": "delegated-exact-production", "cases": cases}


class CaptureReportTests(unittest.TestCase):
    def test_complete_report_with_bom_and_surrounding_output(self):
        report = complete_report()
        self.assertEqual(REPORT.verify("\ufefffixture output\n" + json.dumps(report) + "\ndone"), report)

    def test_absent_duplicate_or_failed_report(self):
        good = json.dumps(complete_report())
        for text in ("", "PASS", good + "\n" + good, '{"productionModulesImported":true,"ok":false}'):
            with self.subTest(text=text[:30]), self.assertRaises(ValueError):
                REPORT.verify(text)

    def test_missing_duplicate_failed_and_wrong_cases(self):
        for change in (lambda cases: cases.pop(), lambda cases: cases.append(copy.deepcopy(cases[0])),
                       lambda cases: cases[0].update(ok=False), lambda cases: cases[0].update(mode="wrong")):
            report = complete_report()
            change(report["cases"])
            with self.assertRaises(ValueError):
                REPORT.verify(json.dumps(report))

    def test_missing_phase_measurement_and_failed_positive_control(self):
        for phase in ("armed", "dragging"):
            for field, value in (("eventObserverPositiveControl", False), ("continuousObservation", False),
                                 ("hideEvents", 1), ("invisibleSamples", 1), ("locationEvents", 0),
                                 ("distinctMotionPositions", 11), ("generatedMoves", 19),
                                 ("finalTargetSettledMilliseconds", -1), ("durationMilliseconds", 955),
                                 ("visibilitySamples", True), ("visibilitySamples", None)):
                report = complete_report()
                case = next(case for case in report["cases"] if case["mode"].startswith("magnifier-continuity"))
                case[phase + "MagnifierContinuity"][field] = value
                with self.subTest(phase=phase, field=field), self.assertRaises(ValueError):
                    REPORT.verify(json.dumps(report))
            report = complete_report()
            case = next(case for case in report["cases"] if case["mode"].startswith("magnifier-continuity"))
            del case[phase + "MagnifierContinuity"]
            with self.assertRaises(ValueError):
                REPORT.verify(json.dumps(report))

    def test_scope_or_production_identity_must_not_be_missing(self):
        for field in ("ok", "productionModulesImported", "userContentCaptured", "clipboardAccessed", "requestedInputBackend"):
            report = complete_report()
            del report[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                REPORT.verify(json.dumps(report))

    def test_live_pixels_are_mandatory_bounded_and_non_private(self):
        for phase in ("armed", "dragging"):
            for field, value in (("generatedColorChanges", 2), ("generatedColorChanges", True),
                                 ("maximumRefreshMilliseconds", -1), ("maximumRefreshMilliseconds", 201),
                                 ("maximumRefreshMilliseconds", True), ("maximumRefreshMilliseconds", None),
                                 ("livePixelRefreshVerified", False), ("samplePixelsStored", True)):
                report = complete_report()
                case = next(case for case in report["cases"] if case["mode"].startswith("magnifier-continuity"))
                case[phase + "MagnifierLivePixels"][field] = value
                with self.subTest(phase=phase, field=field, value=value), self.assertRaises(ValueError):
                    REPORT.verify(json.dumps(report))
            for field in (None, "generatedColorChanges", "maximumRefreshMilliseconds",
                          "livePixelRefreshVerified", "samplePixelsStored"):
                report = complete_report()
                case = next(case for case in report["cases"] if case["mode"].startswith("magnifier-continuity"))
                if field is None:
                    del case[phase + "MagnifierLivePixels"]
                else:
                    del case[phase + "MagnifierLivePixels"][field]
                with self.subTest(phase=phase, missing=field), self.assertRaises(ValueError):
                    REPORT.verify(json.dumps(report))

    def test_live_pixel_refresh_boundary_is_inclusive(self):
        for boundary in (0, 200):
            report = complete_report()
            case = next(case for case in report["cases"] if case["mode"].startswith("magnifier-continuity"))
            for phase in ("armed", "dragging"):
                case[phase + "MagnifierLivePixels"]["maximumRefreshMilliseconds"] = boundary
            self.assertEqual(REPORT.verify(json.dumps(report)), report)


if __name__ == "__main__":
    unittest.main()
