"""Desktop-free wiring checks; native behavior is tested by the Swift fixtures.

These checks do not pretend to execute macOS AX/AppKit or an installed app.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SWIFT = (ROOT / "src-tauri/native/macos.swift").read_text()
MAIN = (ROOT / "src-tauri/src/main.rs").read_text()
PLATFORM = (ROOT / "src-tauri/src/platform.rs").read_text()


def section(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]


class MacSelectionRecoveryContract(unittest.TestCase):
    def test_request_identity_is_captured_before_async_dispatch(self):
        action = section(MAIN, "fn start_action(", "fn fit_window_with_visibility(")
        self.assertLess(action.index("platform::macos_selection_source()"),
                        action.index("tauri::async_runtime::spawn(async move"))
        self.assertIn("let expected_macos_source = macos_selection_source?;", action)
        self.assertIn("platform::selected_text_from_source_cancelable(", action)
        self.assertIn('expected_macos_source.as_ref().ok_or("缺少原取词窗口")?', action)

    def test_selection_cfg_branches_are_blocks_and_return_result(self):
        selection = section(MAIN, 'let text = match worker_action.as_str() {', '"clipboard" => platform::clipboard_text(),')
        # Rust must parse the complete token stream before cfg filtering. Two
        # adjacent attributed bare call expressions are not separate statements.
        # Explicit blocks are valid on every target and keep each Result as the
        # block's tail value; adding a semicolon would instead discard it.
        self.assertRegex(selection, r'#\[cfg\(target_os = "windows"\)\]\s*\{')
        self.assertRegex(selection, r'#\[cfg\(target_os = "macos"\)\]\s*\{')
        self.assertRegex(selection, r'#\[cfg\(not\(any\(target_os = "windows", target_os = "macos"\)\)\)\]\s*\{')
        self.assertRegex(selection, r'platform::selected_text_with_strategy_cancelable\(cancel, strategy, attempt\)\s*\}')
        self.assertRegex(selection, r'platform::selected_text_from_source_cancelable\([\s\S]*?\n\s*\)\s*\}')
        self.assertRegex(selection, r'platform::selected_text_cancelable\(cancel\)\s*\}')

    def test_basic_workspace_snapshot_has_no_ax_or_content_read(self):
        snapshot = section(SWIFT, "func selectionRequestSourceSnapshot()", "func selectionRequestSourceForShortcut()")
        for forbidden in ("AXUIElementCopy", "AXValue", "activate(", "NSPasteboard", "windowTitle"):
            self.assertNotIn(forbidden, snapshot)
        self.assertIn("NSWorkspace.shared.frontmostApplication", snapshot)
        self.assertIn("application.launchDate", snapshot)
        self.assertIn("selectionCGCopyTicket(source: source)?.windowID", snapshot)

    def test_exceptional_shortcut_anchor_has_no_text_and_checks_window_twice(self):
        snapshot = section(SWIFT, "func selectionRequestSourceForShortcut()", "func selectionRequestSourceMatches(")
        self.assertEqual(snapshot.count("focusedSelectionWindow(applicationPID:"), 2)
        self.assertIn("CFEqual(window, confirmed)", snapshot)
        self.assertIn("selectionRequestSourceMatches(source, current)", snapshot)
        for forbidden in ("accessibilitySelection(", "NSPasteboard", "activate(", "kAXValueAttribute", "kAXTitleAttribute"):
            self.assertNotIn(forbidden, snapshot)

    def test_ax_request_token_is_checked_before_read_and_released_at_exit(self):
        check = section(SWIFT, "func requireSelectionRequestSource(", "struct SelectionApplicationSnapshot")
        self.assertIn("SelectionRequestWindowStore.window(for: expected)", check)
        self.assertIn("selectionAnchoredWindowMatches(window, current, same: { CFEqual($0, $1) })", check)
        self.assertIn("} else { matches = false }", check)
        self.assertIn("defer { SelectionRequestWindowStore.remove(requestSource?.axWindowToken) }", SWIFT)

    def test_snapshot_endpoint_does_not_wait_for_clipboard_lock(self):
        bridge = section(PLATFORM, 'fn run(mode: &str, input: Option<&str>) -> Result<Value, String> {\n    use std::ffi',
                         "// Cached paths are an optimization")
        lock = section(bridge, "let _capture", 'unsafe extern "C"')
        self.assertNotIn('"selection-source"', lock)

    def test_selection_skip_delay_does_not_remove_copy_modifier_guards(self):
        self.assertIn('if worker_action != "selection" {', MAIN)
        self.assertGreaterEqual(SWIFT.count("try requireSelectionModifiersReleased()"), 2)
        self.assertIn('trace.record("modifier-release")', SWIFT)

    def test_source_passes_through_bridge_without_new_text_capture(self):
        bridge = section(PLATFORM, "pub fn selected_text_from_source_cancelable(", '#[cfg(target_os = "windows")]')
        self.assertIn('run("selected-text", Some(&source.to_string()))', bridge)
        self.assertEqual(bridge.count("cancelled(Some(&cancel))"), 2)
        self.assertIn("selection(requestSource: source)", SWIFT)

    def test_request_anchor_is_rechecked_before_ax_and_copy(self):
        capture = section(SWIFT, "func captureSelectedText(trace:", "func captureSelectedTextInSource(")
        self.assertLess(capture.index("try requireSelectionRequestSource(requestSource"),
                        capture.index("selectionApplicationSnapshot("))
        recheck = section(SWIFT, "func recheckSelectionApplication(", "func requireUnprotectedSelection(")
        self.assertIn("try requireSelectionRequestSource(expected.requestSource", recheck)

    def test_recovery_is_only_for_initial_unavailability_before_copy(self):
        capture = section(SWIFT, "func captureSelectedText(trace:", "func captureSelectedTextInSource(")
        self.assertIn('selectionFocusRecoveryAllowed(initialFocusState: originalFocusQuery.state, copyIssued: trace.hasIssuedCopy)', capture)
        gate = section(SWIFT, "func selectionFocusRecoveryAllowed(", "func requireSelectionTextTarget(")
        self.assertIn('initialFocusState == "unavailable" && !copyIssued', gate)
        self.assertEqual(capture.count("recoverSelectionAfterFocusAppeared("), 1)
        self.assertNotIn("catch let error as NativeError", capture)

    def test_recovery_never_copies_activates_or_reads_document_value(self):
        recovery = section(SWIFT, "func recoverSelectionAfterFocusAppeared(", "func unavailableSelectionError(")
        for forbidden in ("NSPasteboard", "postToPid", ".post(", "activate(", "kAXValueAttribute",
                          "SelectionCopyDispatch", "AXUIElementSetAttributeValue"):
            self.assertNotIn(forbidden, recovery)
        self.assertIn("!IsSecureEventInputEnabled()", recovery)
        self.assertIn("AXIsProcessTrusted()", recovery)
        self.assertIn("selectionCopyTicket(source: source, matching: ticket) == ticket", recovery)
        self.assertIn("+ 0.18", recovery)
        self.assertIn("try requireSelectionTextTarget(element, deadline: deadline)", recovery)
        self.assertIn("requireTextTarget: true", recovery)

    def test_direct_ax_results_recheck_control_not_just_app(self):
        capture = section(SWIFT, "func captureSelectedTextInSource(", "struct OCRLayoutLine")
        self.assertIn("try requireSelectionReadFocus(originalFocus", capture)
        self.assertIn("try requireSelectionReadFocus(currentFocus", capture)

    def test_focus_fixture_pins_generic_identity_to_int(self):
        fixture = section(SWIFT, "func selectionFocusRecoverySelfTest()", "func selectionSourceAnchorSelfTest()")
        # Bare `==` plus an unconstrained integer-literal focus gives Swift
        # several legal generic Focus types. Keep all seven fixture scenarios,
        # but pin the comparator's intended generated identity type explicitly.
        self.assertNotIn("same: ==", fixture)
        self.assertEqual(fixture.count("same: { (left: Int, right: Int) in left == right }"), 7)
        self.assertEqual(fixture.count("try readNewlyAvailableSelection("), 7)

    def test_ax_window_fallback_uses_public_focused_window_not_search(self):
        fallback = section(SWIFT, "func selectionAXCopyTicket(", "func selectionCopyTicket(")
        self.assertIn("focusedSelectionWindow(applicationPID: pid", fallback)
        self.assertIn("selectionRecoveryRole(window, applicationPID: pid", fallback)
        self.assertIn("!IsSecureEventInputEnabled()", fallback)
        self.assertIn("AXIsProcessTrusted()", fallback)
        for forbidden in ("kAXWindowsAttribute", "kAXTitleAttribute", "_AXUIElementGetWindow", "NSPasteboard", ".post("):
            self.assertNotIn(forbidden, fallback)

    def test_ticket_revalidation_cannot_switch_authority(self):
        dispatch = section(SWIFT, "func selectionCopyTicket(", "func selectionCompatibilityRejectionReason(")
        matched = section(dispatch, "if let ticket {", "    return selectionCGCopyTicket")
        self.assertIn("ticket.focusedWindow == nil ?", matched)
        self.assertNotIn("??", matched)
        self.assertIn("case (let left?, let right?): return CFEqual(left, right)", SWIFT)

    def test_failure_slot_is_bounded_and_not_recursive(self):
        retention = section(SWIFT, "struct SelectionTraceRetention {", "final class SelectionTrace {")
        self.assertIn("if failed { lastFailure = snapshot }", retention)
        self.assertNotIn("append", retention)
        self.assertIn('Self.retained.store(value, failed: state == "failed")', SWIFT)
        self.assertIn('retained?["lastFailure"] == nil', SWIFT)

    def test_new_native_fixtures_are_required_not_merely_advertised(self):
        fixtures = (ROOT / "tests/macos-native-self-test.sh").read_text()
        for fixture, result in (
            ("selectionFocusRecoverySelfTest", "selectionFocusRecoveryFixturePassed"),
            ("selectionSourceAnchorSelfTest", "selectionSourceAnchorFixturePassed"),
            ("selectionTraceRetentionSelfTest", "selectionTraceRetentionFixturePassed"),
            ("selectionAXWindowTicketSelfTest", "selectionAXWindowTicketFixturePassed"),
            ("selectionWindowAnchorSelfTest", "selectionWindowAnchorFixturePassed"),
        ):
            self.assertIn(f"try {fixture}()", SWIFT)
            self.assertIn(f'"{result}": true', SWIFT)
            self.assertIn(f'"{result}"', fixtures)
        self.assertIn('codexInteractiveSelectionTested") is False', fixtures)


if __name__ == "__main__":
    unittest.main()
