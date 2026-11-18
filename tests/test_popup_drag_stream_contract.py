"""Production ownership boundaries; native behavior runs in the AppKit fixture."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
PANEL=(ROOT/'src/panel-layout.ts').read_text()
SWIFT=(ROOT/'src-tauri/native/macos_window.swift').read_text()
RUST=(ROOT/'src-tauri/src/window_layout.rs').read_text()
class PopupDragStreamContract(unittest.TestCase):
    def test_webview_only_configures_header_and_never_samples(self):
        self.assertIn("invoke('configure_popup_header_drag'", PANEL)
        for command in ['begin_popup_drag', 'move_popup_drag', 'end_popup_drag']:
            self.assertNotIn(command, PANEL)
            self.assertNotIn('pub async fn '+command, RUST)
        self.assertNotIn("window.addEventListener('blur', cancelPopupDrag)", PANEL)
    def test_native_ownership_and_release_are_local(self):
        self.assertIn('NSEvent.addLocalMonitorForEvents', SWIFT)
        self.assertNotIn('addGlobalMonitorForEvents', SWIFT)
        self.assertIn('RunLoop.main.add(timer, forMode: .common)', SWIFT)
        self.assertIn('event.window === window', SWIFT)
        self.assertIn('guard region.contains(anchor)', SWIFT)
    def test_old_completion_cannot_retire_new_token_or_fit_during_drag(self):
        self.assertIn('token.id == id', RUST)
        self.assertIn('current.epoch == token.epoch', RUST)
        self.assertIn('popup-native-drag-ended', PANEL)
        self.assertIn('revision > self.revision', SWIFT)
