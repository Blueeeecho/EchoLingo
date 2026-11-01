"""Borderless pin IPC guards; native runtime remains a separate gate."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class BorderlessPinContract(unittest.TestCase):
    def test_borderless_pin_commands_are_registry_guarded_on_ui_thread(self):
        source = (ROOT / 'src-tauri/src/screenshot_pins.rs').read_text()
        self.assertIn('.decorations(false)', source)
        self.assertNotIn('42.0 * units', source)
        guard = source.split('fn ready_pin(', 1)[1].split('#[tauri::command]', 1)[0]
        for token in ('!is_pin(window.label())', '.get(window.label())', 'entry.delivered && entry.ready.is_none() && entry.image.is_none()'):
            self.assertIn(token, guard)
        drag = source.split('pub async fn start_pinned_screenshot_drag(', 1)[1].split('#[tauri::command]', 1)[0]
        resize = source.split('pub async fn resize_pinned_screenshot(', 1)[1].split('#[tauri::command]', 1)[0]
        for command in (drag, resize):
            self.assertIn('super::screenshot::dialog(&app, move ||', command)
            self.assertIn('ready_pin(&handle, &window)?', command)
        self.assertIn('.start_dragging()', drag)
        self.assertIn('.start_resize_dragging(direction)', resize)
        self.assertIn('#[serde(rename_all = "lowercase")]', source)
        self.assertIn('"SMOKE_PIN_NOT_BORDERLESS"', (ROOT / 'src-tauri/src/native_pin_smoke.rs').read_text())
        fixture = (ROOT / 'tests/windows-screenshot-editor-fixture.cs').read_text()
        self.assertNotRegex(fixture, r'0x00C00000L\)\s*==\s*0(?![0-9A-Za-z_])')
        self.assertIn('&0x00C00000L)==0x00C00000L', fixture)
        for token in ('ScreenshotVerifyPinClientFrame(form,app,pin,result)', 'GetClientRect(pin,out client)', 'ClientToScreen(pin,ref first)', 'ClientToScreen(pin,ref last)', 'RtlGetVersion(ref version)==0', 'GetSystemMetricsForDpi(32,dpi)+GetSystemMetricsForDpi(92,dpi)', 'insets[1]==top', 'nativePinStyle'):
            self.assertIn(token, fixture)


if __name__ == "__main__":
    unittest.main()
