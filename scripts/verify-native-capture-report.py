#!/usr/bin/env python3
"""Require a complete generated-window native-capture report, not just exit zero."""
import json
from pathlib import Path
import sys

EXPECTED_MODES = {
    "first-fresh-pair-immediate-release", "magnifier-continuity-armed-and-dragging",
    "topmost-self-raise-immediate-first-pair", "foreign-thread-native-capture",
    "cross-peer-held900ms", "preheld-source-release-then-first-fresh-pair",
    "escape-drains-owned-release", "escape-held-release-after-helper-close",
    "next-capture-after-escape", "display-change-before-input",
    "next-capture-after-display-change", "escape-held900ms-drains-real-key-up",
    "next-capture-after-held-escape", "own-plane-cancelmode-no-input",
    "next-capture-after-plane-cancelmode", "benign-dpi-notifications-then-capture",
}


def verify(text):
    reports = []
    for line in text.lstrip("\ufeff").splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict) and "productionModulesImported" in value:
            reports.append(value)
    if len(reports) != 1:
        raise ValueError("Exactly one native-capture report is required")
    report = reports[0]
    if (report.get("ok") is not True or report.get("productionModulesImported") is not True
            or report.get("userContentCaptured") is not False or report.get("clipboardAccessed") is not False
            or report.get("requestedInputBackend") != "delegated-exact-production"):
        raise ValueError("Native-capture success/scope is absent or invalid")
    cases = report.get("cases")
    if (not isinstance(cases, list) or len(cases) != len(EXPECTED_MODES)
            or any(not isinstance(case, dict) or case.get("ok") is not True for case in cases)
            or {case.get("mode") for case in cases} != EXPECTED_MODES):
        raise ValueError("All 16 distinct native-capture cases must pass")
    for case in cases:
        diagnostics = case.get("helperDiagnostics")
        health = diagnostics.get("captureHealth") if isinstance(diagnostics, dict) else None
        if (not isinstance(health, dict) or type(health.get("magnifierSampleThreadStopped")) is not int
                or health["magnifierSampleThreadStopped"] != 1):
            raise ValueError("Every native case must stop its sampling worker")
    continuity = next(case for case in cases if case["mode"] == "magnifier-continuity-armed-and-dragging")
    health = continuity["helperDiagnostics"]["captureHealth"]
    if (type(health.get("magnifierSampleThreadStopped")) is not int
            or health["magnifierSampleThreadStopped"] != 1
            or type(health.get("magnifierSampleCompleted")) is not int
            or health["magnifierSampleCompleted"] < 1
            or type(health.get("magnifierFrameAgeMillisecondsMax")) is not int
            or not 0 <= health["magnifierFrameAgeMillisecondsMax"] <= 200):
        raise ValueError("Magnifier sampling must be fresh and its worker must stop")
    for phase in ("armed", "dragging"):
        moving = continuity.get(phase + "MagnifierMovingPixels")
        if (not isinstance(moving, dict) or moving.get("finalTargetPixelMatched") is not True
                or moving.get("observerStopped") is not True or moving.get("samplePixelsStored") is not False
                or type(moving.get("distinctMotionPixelColors")) is not int or moving["distinctMotionPixelColors"] < 3
                or type(moving.get("pixelObservations")) is not int or moving["pixelObservations"] < 1
                or type(moving.get("maximumColorRefreshMilliseconds")) is not int
                or not 0 <= moving["maximumColorRefreshMilliseconds"] <= 200):
            raise ValueError("Magnifier pixels must change during motion and match the final target")
        pixels = continuity.get(phase + "MagnifierLivePixels")
        if (not isinstance(pixels, dict) or pixels.get("livePixelRefreshVerified") is not True
                or pixels.get("samplePixelsStored") is not False
                or type(pixels.get("generatedColorChanges")) is not int
                or pixels["generatedColorChanges"] != 3
                or type(pixels.get("maximumRefreshMilliseconds")) is not int
                or not 0 <= pixels["maximumRefreshMilliseconds"] <= 200):
            raise ValueError("Both magnifier phases require fresh generated pixels within 200 ms")
        evidence = continuity.get(phase + "MagnifierContinuity")
        if not isinstance(evidence, dict):
            raise ValueError("Both magnifier phases require continuous evidence")
        if evidence.get("continuousObservation") is not True or evidence.get("eventObserverPositiveControl") is not True:
            raise ValueError("Magnifier observer positive control is required")
        for field, minimum in (("durationMilliseconds", 956), ("visibilitySamples", 1),
                               ("locationEvents", 1), ("generatedMoves", 20),
                               ("distinctMotionPositions", 12), ("finalTargetSettledMilliseconds", 0)):
            value = evidence.get(field)
            if type(value) is not int or value < minimum:
                raise ValueError("Missing or incomplete magnifier measurement: " + field)
        for field in ("invisibleSamples", "hideEvents"):
            if type(evidence.get(field)) is not int or evidence[field] != 0:
                raise ValueError("Magnifier visibility was interrupted")
    return report


if __name__ == "__main__":
    verify(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    print("PASS: all 16 native-capture cases, live pixels and both continuous magnifier phases verified.")
