#!/usr/bin/env python3
"""Require native capture/input/cleanup; retain fine visual timing as diagnostics."""
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
    if report.get("acceptancePolicy") != "core-functional-v1" or report.get("fineQualityBlocking") is not False:
        raise ValueError("Explicit core-functional policy is required; historical reports are not relabeled")
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
    if continuity.get("generatedFinalTargetReadyBeforeHelper") is not True:
        raise ValueError("The generated final spatial target must be verified before helper launch")
    health = continuity["helperDiagnostics"]["captureHealth"]
    if (type(health.get("magnifierSampleThreadStopped")) is not int
            or health["magnifierSampleThreadStopped"] != 1
            or type(health.get("magnifierSampleCompleted")) is not int
            or health["magnifierSampleCompleted"] < 1
            or type(health.get("magnifierFrameAgeMillisecondsMax")) is not int
            or not 0 <= health["magnifierFrameAgeMillisecondsMax"] <= 200):
        raise ValueError("Magnifier sampling must be fresh and its worker must stop")
    if continuity.get("coreOk") is not True or type(continuity.get("qualityOk")) is not bool:
        raise ValueError("Core and quality results must be explicitly separated")
    quality = continuity.get("qualityDiagnostics")
    suffixes = {"stationary-refresh", "motion-observer-failed", "moving-color-count", "moving-color-refresh",
                "final-pixel-deadline", "event-positive-control", "visibility-continuity", "motion-follow-density"}
    allowed = {phase + "-" + suffix for phase in ("armed", "dragging") for suffix in suffixes}
    if (not isinstance(quality, list) or len(quality) > 16
            or any(not isinstance(code, str) or code not in allowed for code in quality)
            or len(set(quality)) != len(quality) or continuity["qualityOk"] != (len(quality) == 0)):
        raise ValueError("Quality diagnostics must be bounded known codes, not silently discarded failures")
    for field in ("zeroUnderlyingInput", "foregroundPreserved", "postSessionSourceClickRestored", "hostAliveAfterSessionClose"):
        if continuity.get(field) is not True:
            raise ValueError("Native functional input/cleanup proof is required: " + field)
    size = continuity.get("capturedPhysicalSize")
    if (not isinstance(size, list) or len(size) != 2
            or any(type(value) is not int or not 0 < value <= 16384 for value in size)
            or type(continuity.get("blueHintPixelsInCapture")) is not int
            or continuity["blueHintPixelsInCapture"] != 0):
        raise ValueError("A valid native PNG without overlay contamination remains mandatory")
    if continuity["helperDiagnostics"].get("nativeBackend") != "rust-win32-capture":
        raise ValueError("Exact native backend is required")
    for field, expected in (("nativeCaptureBackend", 1), ("nativeHostStopped", 1), ("inputPlaneRemainingAfterCleanup", 0)):
        if type(health.get(field)) is not int or health[field] != expected:
            raise ValueError("Native functional cleanup is incomplete: " + field)
    for phase in ("armed", "dragging"):
        moving = continuity.get(phase + "MagnifierMovingPixels")
        pixels = continuity.get(phase + "MagnifierLivePixels")
        evidence = continuity.get(phase + "MagnifierContinuity")
        if not all(isinstance(value, dict) for value in (moving, pixels, evidence)):
            raise ValueError("Both phases must retain their raw diagnostic observations")
        if (moving.get("observerStopped") is not True or moving.get("samplePixelsStored") is not False
                or pixels.get("samplePixelsStored") is not False or evidence.get("continuousObservation") is not True):
            raise ValueError("Diagnostic observers must stop without retaining screen pixels")
        for value, names in ((moving, ("distinctMotionPixelColors", "maximumColorRefreshMilliseconds", "pixelObservations")),
                             (pixels, ("generatedColorChanges", "maximumRefreshMilliseconds")),
                             (evidence, ("durationMilliseconds", "visibilitySamples", "invisibleSamples", "hideEvents",
                                         "locationEvents", "generatedMoves", "distinctMotionPositions"))):
            for field in names:
                if type(value.get(field)) is not int or not 0 <= value[field] <= 30000:
                    raise ValueError("Missing or invalid bounded quality observation: " + field)
        if pixels["generatedColorChanges"] > 3:
            raise ValueError("Generated color observations exceed the fixture's three colors")
        if (type(evidence.get("finalTargetSettledMilliseconds")) is not int
                or not -1 <= evidence["finalTargetSettledMilliseconds"] <= 30000):
            raise ValueError("Final geometry observation must remain explicit")
        for value, field in ((moving, "finalTargetPixelMatched"), (moving, "observerFailed"),
                             (pixels, "visibleThroughoutLiveProbe"), (pixels, "livePixelRefreshVerified"),
                             (evidence, "eventObserverPositiveControl")):
            if type(value.get(field)) is not bool:
                raise ValueError("Quality observation must remain a boolean: " + field)
        failures = {
            "stationary-refresh": pixels["generatedColorChanges"] != 3 or not pixels["livePixelRefreshVerified"]
                                  or pixels["maximumRefreshMilliseconds"] > 200,
            "motion-observer-failed": moving.get("observerFailed") is True,
            "moving-color-count": moving["distinctMotionPixelColors"] < 3,
            "moving-color-refresh": moving["maximumColorRefreshMilliseconds"] > 200,
            "final-pixel-deadline": not moving["finalTargetPixelMatched"],
            "event-positive-control": not evidence["eventObserverPositiveControl"],
            "visibility-continuity": evidence["invisibleSamples"] > 0 or evidence["hideEvents"] > 0
                                     or pixels.get("visibleThroughoutLiveProbe") is False,
            "motion-follow-density": evidence["generatedMoves"] < 20 or evidence["distinctMotionPositions"] < 12
                                     or evidence["finalTargetSettledMilliseconds"] < 0,
        }
        if any(failed and phase + "-" + code not in quality for code, failed in failures.items()):
            raise ValueError("Raw fine-quality misses must remain explicitly reported, not relabeled passed")
    return report


if __name__ == "__main__":
    report = verify(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    continuity = next(case for case in report["cases"] if case["mode"] == "magnifier-continuity-armed-and-dragging")
    print(json.dumps({"corePassed": True, "acceptancePolicy": "core-functional-v1",
                      "qualityBlocking": False, "qualityOk": continuity["qualityOk"],
                      "qualityDiagnostics": continuity["qualityDiagnostics"]}))
