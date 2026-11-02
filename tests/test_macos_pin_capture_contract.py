"""Ready-pin capture exceptions remain object-registered and fail closed."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
SWIFT = (ROOT / 'src-tauri/native/macos_capture.swift').read_text()
RUST = (ROOT / 'src-tauri/src/screenshot_pins.rs').read_text()

class PinCaptureContract(unittest.TestCase):
    def test_only_decoded_guarded_native_pin_registers(self):
        ready = RUST.split('pub async fn pinned_screenshot_ready(', 1)[1].split('#[tauri::command]', 1)[0]
        for guard in ('entry.delivered && entry.ready.is_some()', 'with_pin_source(source', 'show_without_activation(&window)?'):
            self.assertLess(ready.index(guard), ready.index('if unsafe { echolingo_register_capture_pin(pointer) }'))
        self.assertIn('window.ns_window()', ready)
        registry = SWIFT.split('private final class CaptureReadyPin {', 1)[1].split('@available(macOS 12.3, *)', 1)[0]
        for guard in ('weak var window: NSWindow?', 'Thread.isMainThread', '$0 === window',
                      'window.isVisible', '!window.isMiniaturized', 'window.sharingType = .readOnly',
                      'NSWindow.willCloseNotification', 'captureReadyPins.removeValue',
                      'captureReadyPinGeneration < UInt64.max', 'captureReadyPinGeneration += 1'):
            self.assertIn(guard, registry)
        self.assertIn('let windows: [(UInt64, CGWindowID)]', registry)
        self.assertNotIn('let windows: [(NSWindow', registry)
        self.assertNotIn('.title', registry)
        self.assertNotIn('window.label', registry)

    def test_both_capture_paths_validate_pin_generation_before_and_after_pixels(self):
        modern = SWIFT.split('func captureScreenKitImage(', 1)[1].split('func captureLegacyWindowIds(', 1)[0]
        legacy = SWIFT.split('func captureNativePlannedImage(', 1)[1].split('// Public response coordinates', 1)[0]
        self.assertLess(modern.index('let pins = captureReadyPinSnapshot()'), modern.index('SCShareableContent.getExcludingDesktopWindows'))
        self.assertLess(legacy.index('let pins = captureReadyPinSnapshot()'), legacy.index('CGWindowListCopyWindowInfo'))
        self.assertIn('captureExcludesOwnWindow(', modern)
        self.assertIn('ownPID: ProcessInfo.processInfo.processIdentifier, readyPins: pins.ids', modern)
        self.assertIn('$0.windowID == id && $0.owningApplication?.processID', modern)
        self.assertIn('pins.ids.isSubset(of: Set(ids))', legacy)
        for body in (modern, legacy):
            self.assertGreaterEqual(body.count('captureValidateReadyPins(pins)'), 3)
        policy = SWIFT.split('func captureLegacyWindowIds(', 1)[1].split('func captureLegacyWindowArray', 1)[0]
        self.assertIn('captureExcludesOwnWindow(pid: Int32(pid)', policy)
        self.assertIn('readyPins: Set<CGWindowID> = []', policy)

    def test_existing_actual_fixture_adds_pin_ocr_without_replacing_original_cases(self):
        fixture = (ROOT / 'tests/macos-screenshot-native-fixture.swift').read_text()
        self.assertIn('if index == modes.count { verifyReadyPinCapture() }', fixture)
        for evidence in ('captureNativePlannedImage(plan, purpose: .region)', 'recognizeFixture(image)',
                         'echoLingoRegisterCapturePin(pointer)', 'captureValidateReadyPins(snapshot)',
                         'pin.orderOut(nil)', 'pin.close(); helper.close()'):
            self.assertIn(evidence, fixture)
        verifier = (ROOT / 'scripts/verify-macos-screenshot-probe.py').read_text()
        for field in ('readyPinCaptureOCRPassed', 'unregisteredOwnWindowExcludedPassed', 'readyPinLifecycleCleanupPassed'):
            self.assertIn(field, verifier)
            self.assertIn(field, fixture)

    def test_pin_failure_observation_is_fixed_and_does_not_change_verdict(self):
        fixture = (ROOT / 'tests/macos-screenshot-native-fixture.swift').read_text()
        proof = fixture.split('func verifyReadyPinCapture()', 1)[1].split('func verifyPixels(', 1)[0]
        for stage in ('"stage": "capture"', 'observation["stage"] = "recognize"', 'observation["stage"] = "expected-text"'):
            self.assertIn(stage, proof)
        self.assertIn('try fixtureNeed(normalized == "EchoLingo pin 97531"', proof)
        self.assertIn('reason: "pin-proof-capture-ocr-failed"', proof)
        self.assertNotIn('observation["text"]', proof)
        self.assertNotIn('String(describing: error)', proof)
        self.assertNotIn('sleep(', proof)
        self.assertIn('image.width <= 4096, image.height <= 4096', fixture)
        self.assertIn('["white": 0, "magenta": 0, "red": 0, "dark": 0, "other": 0]', fixture)

if __name__ == '__main__': unittest.main()
