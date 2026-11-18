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
        fit = RUST[RUST.index('fn fit_inner('):RUST.index('fn mac_drag_operation(')]
        self.assertNotIn('mac_drag_operation(', fit)
        self.assertNotIn('drag.finish(', fit)
        self.assertIn('echolingo_cancel_stale_header_drag', fit)
        self.assertIn('current.epoch != token.epoch', fit)
        self.assertIn('popup-native-drag-ended', PANEL)
        self.assertIn('revision > self.revision', SWIFT)

    def test_first_reveal_registers_before_show_and_adopts_only_prepared_epoch(self):
        reveal = PANEL[PANEL.index('const presentPopup ='):PANEL.index('const presentManagement =')]
        self.assertLess(reveal.index("await invoke('configure_popup_header_drag'"), reveal.index("('show_popup'"))
        main = (ROOT/'src-tauri/src/main.rs').read_text()
        transaction = main[main.index('async fn show_prepared_popup('):main.index('fn start_action(')]
        self.assertLess(transaction.index('adopt_popup_header_presentation'), transaction.index('window.show()'))
        self.assertIn('guard epoch == previous, next >= previous', SWIFT)

    def test_diagnostics_default_off_fixed_and_bounded(self):
        diagnostic = (ROOT/'src-tauri/src/popup_drag_diagnostics.rs').read_text()
        self.assertIn('#[derive(Default)]', diagnostic)
        self.assertIn('if !self.enabled', diagnostic)
        self.assertIn('self.events.len() == 64', diagnostic)
        self.assertIn('min(1_000_000)', diagnostic)
        self.assertIn('Stage::FitDeferred', RUST)
        self.assertIn('Stage::FitRepositioned', RUST)
        self.assertIn('default: return .invalidOwner', SWIFT)
        self.assertIn("if (diagnosticsEnabled)", PANEL)
        for stage in ['resizeBlur', 'resizePointerCancel', 'resizeCaptureLost', 'resizeButtonsZero']:
            self.assertIn(stage, PANEL)
        self.assertIn('id="popup-drag-diagnostics-toggle"', (ROOT/'index.html').read_text())
