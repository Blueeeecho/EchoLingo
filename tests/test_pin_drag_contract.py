"""Source guards only; actual AppKit dragging remains a native runtime gate."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class PinDragContract(unittest.TestCase):
    def test_mac_drag_uses_owned_window_local_point_and_live_button(self):
        source = (ROOT / 'src-tauri/native/macos_window.swift').read_text().split('public func echoLingoDragPinnedWindow(', 1)[1]
        for required in ['Thread.isMainThread', 'NSApp.windows.contains', 'window.isVisible',
                         'popupDragPressMatches(pressIdentity, popupDragPressIdentity(), NSEvent.pressedMouseButtons & 1 != 0)', 'window.frame.contains(screenPoint)',
                         'window.convertPoint(fromScreen: screenPoint)', 'location: localPoint',
                         'windowNumber: window.windowNumber', 'window.performDrag(with: event)']:
            self.assertIn(required, source)
        self.assertNotIn('setFrame(', source)
        self.assertNotIn('backingScaleFactor', source)
        self.assertNotIn('NSApp.currentEvent()', source)
    def test_registry_guard_precedes_native_bridge_and_windows_keeps_system_drag(self):
        source = (ROOT / 'src-tauri/src/screenshot_pins.rs').read_text().split('pub async fn start_pinned_screenshot_drag(', 1)[1].split('#[tauri::command]', 1)[0]
        self.assertLess(source.index('ready_pin(&handle, &window)?'), source.index('echolingo_drag_pinned_window(pointer, press)'))
        self.assertIn('window.ns_window()', source)
        self.assertIn('#[cfg(not(target_os = "macos"))]', source)
        self.assertIn('.start_dragging()', source)
if __name__ == '__main__': unittest.main()
