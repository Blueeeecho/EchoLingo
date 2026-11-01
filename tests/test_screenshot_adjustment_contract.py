"""Native selection/source contracts; native Swift/Rust fixtures remain the runtime gate."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]

class ScreenshotAdjustmentContract(unittest.TestCase):
    def test_native_action_allowlist_is_typed_and_bound_only_to_new_capture(self):
        platform = (ROOT / 'src-tauri/src/platform.rs').read_text()
        screenshot = (ROOT / 'src-tauri/src/screenshot.rs').read_text()
        actions = platform.split('pub enum ScreenshotInitialAction {', 1)[1].split('}', 1)[0]
        self.assertEqual(re.findall(r'\b([A-Z][a-z]+),', actions), ['Select', 'Rectangle', 'Arrow', 'Text', 'Number', 'Pen', 'Highlight', 'Mosaic', 'Solid', 'Crop', 'Copy', 'Save', 'Pin'])
        self.assertIn('response.get("initialAction").cloned()', re.sub(r"\s+", "", platform))
        self.assertIn('initial_action: None', screenshot)
        start = screenshot.split('pub fn start_capture(', 1)[1].split('#[cfg(test)]', 1)[0]
        self.assertIn('session.initial_action = Some(action)', start)
        self.assertIn('worker_request.cancelled()', start)

    def test_claim_removes_action_under_current_session_lock(self):
        source = (ROOT / 'src-tauri/src/screenshot.rs').read_text()
        claim = source.split('fn take_initial_action(', 1)[1].split('fn cancel_pending(', 1)[0]
        for value in ['locked(&self.state)', 'state.intent != Some(id)', 'image.public.id == id', 'image.public.initial_action.take()']:
            self.assertIn(value, claim)
        command = source.split('pub fn consume_screenshot_initial_action(', 1)[1].split('pub async fn screenshot_editor_ready(', 1)[0]
        self.assertIn('ensure_editor(&window)?', command)
        self.assertIn('take_initial_action(session_id)', command)

    def test_restart_is_new_f1_not_old_bitmap_reuse_or_source_activation(self):
        source = (ROOT / 'src-tauri/src/screenshot.rs').read_text()
        restart = source.split('pub async fn restart_screenshot_capture(', 1)[1].split('#[derive(Serialize)]', 1)[0]
        for value in ['ensure_editor(&window)?', '.try_acquire()', 'dialog_active.load', 'dismiss_current(Some(session_id)', 'emit_cleared(&handle, Some(session_id))', 'start_capture(handle.clone())']:
            self.assertIn(value, restart)
        self.assertLess(restart.index('dismiss_current('), restart.index('start_capture('))
        for value in ['set_focus(', 'SetForegroundWindow(', 'set_image(', 'capture_screenshot_with_geometry_cancelable(']:
            self.assertNotIn(value, restart)

    def test_mac_adjusting_defers_capture_and_keeps_original_window_guard(self):
        source = (ROOT / 'src-tauri/native/macos_capture.swift').read_text()
        state = source.split('struct CaptureSelectorState {', 1)[1].split('final class CaptureScreenshotOperation', 1)[0]
        self.assertIn('if purpose == .screenshot { adjusting = true; self.anchor = nil }', state)
        self.assertIn('else { outcome = .selected(rectangle) }', state)
        self.assertIn('adjustment == nil', state)
        self.assertIn('selectedWindow = window', state)
        self.assertIn('captureValidateWindow(state.selectedWindow)', source)
        self.assertIn('plan.window = state.selectedWindow', source)
        self.assertIn('plan.initialAction = state.initialAction', source)
        self.assertIn('event.type == .keyUp && self.ownsEnter', source)
        self.assertIn('self.receive(.action(.copy))', source)
        self.assertIn('self.pressedAction = nil', source)

    def test_mac_toolbar_geometry_and_native_fixtures_cover_adjustment(self):
        source = (ROOT / 'src-tauri/native/macos_capture.swift').read_text()
        for value in ['captureAdjustmentHandles', 'captureAdjustedRectangle', 'captureActionButtons', 'height <= usable.height - 16', '.visibleFrame', 'actionDisplayID', 'desktop.contains(adjusted)', 'adjusting.initialAction == .pen', 'buttons.allSatisfy { usable.contains($0.1) }']:
            self.assertIn(value, source)
        for removed in ['captureActionHintFrame', 'pressedHint', '选工具后固定范围']:
            self.assertNotIn(removed, source)
        self.assertNotIn('NSApp.activate', source.split('final class CaptureSelectionSession {', 1)[1].split('func selectNativeCaptureRegion(', 1)[0])

if __name__ == '__main__': unittest.main()
