"""Source guardrails only; the pure Swift fixture still needs a macOS runner."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MacOSOCRHoverContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'src-tauri/native/macos_capture.swift').read_text()
        cls.state = cls.source.split('struct CaptureSelectorState {', 1)[1].split('final class CaptureScreenshotOperation', 1)[0]
        cls.session = cls.source.split('final class CaptureSelectionSession {', 1)[1].split('func selectNativeCaptureRegion(', 1)[0]

    def test_both_modes_use_the_same_bounded_actual_hit_lookup(self):
        self.assertIn('var canQueryWindowHint: Bool { outcome == nil && anchor == nil }', self.state)
        query = self.session.split('if state.canQueryWindowHint {', 1)[1].split('state.receive(event)', 1)[0]
        self.assertIn('now.timeIntervalSince(lastWindowQuery) >= 0.08', query)
        self.assertIn('state.candidate = captureCurrentWindows().flatMap {', query)
        self.assertIn('captureHoverWindow($0, at: pointer', query)
        self.assertIn('excludingPID: ProcessInfo.processInfo.processIdentifier', query)
        self.assertIn('state.candidate?.frame.contains(pointer) != true { state.candidate = nil }', query)
        self.assertNotIn('purpose', query)
        self.assertNotIn('throw', query)
        for forbidden in ['AXIsProcessTrusted', 'CGRequestScreenCaptureAccess', 'CGWindowListCreateImage', 'captureLoupeImage']:
            self.assertNotIn(forbidden, query)

    def test_hint_does_not_enable_ocr_window_clicks(self):
        hint = self.state.split('var windowHint:', 1)[1].split('mutating func receive(', 1)[0]
        self.assertIn('guard outcome == nil else { return nil }', hint)
        self.assertIn('if anchor == nil { return candidate }', hint)
        self.assertIn('purpose == .screenshot && !dragExceeded ? pressedWindow : nil', hint)
        self.assertIn('pressedWindow = purpose == .screenshot ? candidate.flatMap', self.state)
        self.assertIn('if purpose == .screenshot && !dragExceeded {', self.state)
        self.assertIn('} else if rectangle.width >= 2 && rectangle.height >= 2 {', self.state)
        self.assertIn('let hovered = state.windowHint?.frame.intersection(geometry.frame)', self.session)

    def test_hint_only_redraw_cannot_resample_pixels(self):
        self.assertIn('let loupeChanged = view.selection != local || pointerMoved', self.session)
        self.assertIn('view.hoveredWindow != localHovered || loupeChanged', self.session)
        self.assertIn('if loupeChanged, let localPointer = localPointer {', self.session)
        self.assertEqual(self.session.count('captureLoupeImage(at:'), 1)
        self.assertNotIn('activate(', self.session)

    def test_pure_mode_fixture_is_on_the_existing_native_self_test_path(self):
        selection = self.source.split('func captureSelectionSelfTest() throws {', 1)[1].split('func captureOverlayBehaviorSelfTest()', 1)[0]
        self.assertIn('try captureWindowHintSelfTest()', selection)
        fixture = self.source.split('func captureWindowHintSelfTest() throws {', 1)[1].split('func captureScreenshotSelfTest()', 1)[0]
        for case in ['[CapturePurpose.region, .screenshot]', 'state.outcome == nil', '.windowSelected(target)',
                     'drag.windowHint == nil', 'cancelled.windowHint == nil',
                     'unavailable.outcome == .selected(rectangle)', 'width: 3, height: 3']:
            self.assertIn(case, fixture)
        for forbidden in ['captureCurrentWindows(', 'captureLoupeImage(', 'NSPasteboard', 'CGRequest', 'NSEvent']:
            self.assertNotIn(forbidden, fixture)

    def test_existing_windows_hover_remains_purpose_independent(self):
        native = (ROOT / 'src-tauri/src/windows_capture_native.rs').read_text()
        hover = native.split('let hovered = if !self.selection.dragging', 1)[1].split('if let Err(e) = self.render', 1)[0]
        self.assertIn('hover_target(p, &self.own, self.owner_process)', hover)
        self.assertNotIn('CapturePurpose', hover)
        legacy = (ROOT / 'src-tauri/native/windows.ps1').read_text()
        hover = legacy.split('Rectangle hovered = Rectangle.Empty;', 1)[1].split('lock (selectionGate)', 1)[0]
        self.assertIn('hoverResolver.Resolve(pointer)', hover)
        self.assertIn('catch { hoverPolicy.Clear(); }', hover)


if __name__ == '__main__':
    unittest.main()
