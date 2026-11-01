"""Wiring guardrails; actual waiter/handler/trace fixtures run in native macOS CI."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text()

class MacOCRCancellationContract(unittest.TestCase):
    def test_all_capture_modes_share_registered_cancel_lifetime(self):
        source = read("src-tauri/src/platform.rs")
        self.assertIn('matches!(mode, "capture-ocr" | "capture-image" | "capture-screenshot")', source)
        body = source.split("fn run_macos_capture_cancelable", 1)[1].split("\nfn ", 1)[0]
        self.assertIn('run(mode, Some(&operation))', body)
        self.assertIn('"cancel-native-capture"', body)
        self.assertIn('"end-native-capture"', body)
        self.assertLess(body.index('"begin-native-capture"'), body.index('std::thread::Builder::new()'))
    def test_swift_token_reaches_vision_without_new_timeout(self):
        source = read("src-tauri/native/macos.swift")
        self.assertIn('try captureOCR(cancellation: captureInputOperation(input))', source)
        self.assertIn('try captureImage(cancellation: captureInputOperation(input))', source)
        body = source.split("func recognize(", 1)[1].split("let maximumPNGBytes", 1)[0]
        self.assertIn('installCancellationHandler { request.cancel() }', body)
        self.assertIn('removeCancellationHandler(cancellationHandler)', body)
        self.assertIn('cancellation: cancellation)', body)
        self.assertIn('deadline.schedule(deadline: .now() + 30)', body)
    def test_timings_are_bounded_static_metadata(self):
        source = read("src-tauri/native/macos_capture.swift")
        body = source.split("final class NativeCaptureTrace:", 1)[1].split("final class CaptureScreenshotOperation", 1)[0]
        self.assertIn('Self.events.count == 24', body)
        self.assertIn('!Self.terminal', body)
        self.assertNotIn('localizedDescription', body)
        self.assertNotIn('CGImage', body)
        for phase in ("selectorShown", "selectionCompleted", "captureCompleted", "ocrStarted", "ocrCompleted"):
            self.assertIn(phase, source + read("src-tauri/native/macos.swift"))
        main = read("src-tauri/src/main.rs")
        for phase in ("nativeWorkerWaiting", "nativeWorkerEntered", "nativeCallStarted", "nativeCallCompleted", "nativeCallCancelled", "sourcePublished", "presentationCancelled"):
            self.assertIn(phase, main)
    def test_native_regression_is_invoked_by_existing_ci(self):
        source = read("src-tauri/native/macos_capture.swift")
        self.assertIn('try captureOCRCancellationSelfTest()', source)
        self.assertIn('waiter.finish(.success(42))', source)
        self.assertIn('operation.removeCancellationHandler(old)', source)
        self.assertIn('"ocrCancellationTimingFixturePassed"', read("tests/macos-native-self-test.sh"))
if __name__ == "__main__": unittest.main()
