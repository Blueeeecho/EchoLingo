"""Wiring guardrails; actual waiter/handler/trace fixtures run in native macOS CI."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text()

class MacOCRCancellationContract(unittest.TestCase):
    def test_all_capture_modes_share_registered_cancel_lifetime(self):
        source = read("src-tauri/src/platform.rs")
        self.assertIn('matches!(mode, "capture-ocr" | "capture-image" | "capture-screenshot" | "select-screenshot" | "capture-selected-region")', source)
        body = source.split("fn run_macos_capture_cancelable_input", 1)[1].split("\nfn ", 1)[0]
        self.assertIn('run(mode, Some(&operation))', body)
        self.assertIn('"cancel-native-capture"', body)
        self.assertIn('"end-native-capture"', body)
        self.assertLess(body.index('"begin-native-capture"'), body.index('std::thread::Builder::new()'))
    def test_swift_token_reaches_bounded_domain_without_changing_accuracy(self):
        source = read("src-tauri/native/macos.swift")
        self.assertIn('try captureOCR(cancellation: captureInputOperation(input))', source)
        self.assertIn('try captureImage(cancellation: captureInputOperation(input))', source)
        body = source.split("func recognize(", 1)[1].split("let maximumPNGBytes", 1)[0]
        self.assertIn('installCancellationHandler { job.cancel() }', body)
        self.assertIn('removeCancellationHandler(cancellationHandler)', body)
        self.assertIn('job.bindCancellation { request.cancel() }', body)
        self.assertIn('defer { job.clearCancellation() }', body)
        self.assertLess(body.index('NativeOCRDomain.shared.reserve {'), body.index('try withCapturedRegion(cancellation:'))
        self.assertIn('try job.start { job in try autoreleasepool { try recognize(image, job: job) } }', body)
        self.assertIn('let result = try job.wait()', body)
        self.assertIn('request.recognitionLevel = .accurate', body)
        self.assertIn('request.usesLanguageCorrection = true', body)
        self.assertIn('["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]', body)
        domain = read("src-tauri/native/macos_ocr.swift")
        self.assertIn('start(timeout: TimeInterval = 30', domain)
        self.assertIn('wake.wait(timeout: .now() + remaining)', domain)
        self.assertNotIn('Date().addingTimeInterval', domain)
        self.assertIn('guard active == nil', domain)
        self.assertIn('(!cancelScheduled || cancelReturned)', domain)
        self.assertIn('if stop == nil { result = outcome }', domain)
    def test_timings_are_bounded_static_metadata(self):
        source = read("src-tauri/native/macos_capture.swift")
        body = source.split("final class NativeCaptureTrace:", 1)[1].split("final class CaptureScreenshotOperation", 1)[0]
        self.assertIn('Self.events.count == 48', body)
        self.assertIn('!Self.terminal', body)
        self.assertNotIn('localizedDescription', body)
        self.assertNotIn('CGImage', body)
        for phase in ("selectorShown", "selectionCompleted", "captureCompleted", "ocrStarted", "ocrCompleted"):
            self.assertIn(phase, source + read("src-tauri/native/macos.swift"))
        main = read("src-tauri/src/main.rs")
        for phase in ("nativeWorkerWaiting", "nativeWorkerEntered", "nativeCallStarted", "nativeCallCompleted", "nativeCallCancelled", "sourcePublished", "nativeWorkerReleased"):
            self.assertIn(phase, main)
    def test_native_regression_is_invoked_by_existing_ci(self):
        source = read("src-tauri/native/macos_capture.swift")
        self.assertIn('try captureOCRCancellationSelfTest()', source)
        self.assertIn('waiter.finish(.success(42))', source)
        self.assertIn('operation.removeCancellationHandler(old)', source)
        runner = read("tests/macos-native-self-test.sh")
        self.assertIn('"ocrCancellationTimingFixturePassed"', runner)
        self.assertIn('macos-ocr-domain-fixture.swift', runner)
        fixture = read("tests/macos-ocr-domain-fixture.swift")
        for injection in ('releaseWork.wait()', 'releaseCancel.wait()', 'allowBinding.wait()',
                          'finishQuery.wait()', 'try busy(domain)', 'imageProbe == nil'):
            self.assertIn(injection, fixture)

    def test_diagnostics_does_not_query_vision_again(self):
        source = read("src-tauri/native/macos.swift")
        body = source.split("func diagnostics(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('NativeOCRCapabilities.shared.snapshot()', body)
        self.assertIn('NativeOCRDomain.shared.snapshot()', body)
        self.assertNotIn('VNRecognizeTextRequest', body)
        self.assertNotIn('supportedRecognitionLanguages()', body)
        self.assertIn('ocrLanguagesObservation', body)

    def test_cancellation_reasons_are_fixed_metadata(self):
        source = read("src-tauri/src/popup_health.rs")
        self.assertIn('cancel_reason: Option<CancellationReason>', source)
        self.assertIn('enum CancellationReason', source)
        main = read("src-tauri/src/main.rs")
        for reason in ('SettingsAction', 'NewNativeAction', 'ScreenshotAction', 'InputAction',
                       'OutsideClick', 'ExternalFocus', 'HideRequested', 'WindowClose'):
            self.assertIn('CancellationReason::' + reason, main)
        self.assertIn('busy_ocr_uses_normal_error_presentation_but_selection_stays_quiet', main)
if __name__ == "__main__": unittest.main()
