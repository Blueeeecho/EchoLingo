"""Wiring/safety checks only; native fixtures still require Apple Swift/macOS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SWIFT = (ROOT / "src-tauri/native/macos.swift").read_text()


def section(start, end):
    return SWIFT[SWIFT.index(start):SWIFT.index(end, SWIFT.index(start))]


class MacChatMultiSelectionContract(unittest.TestCase):
    def test_new_path_is_qq_group_only_not_wechat_or_editors(self):
        gate = section("func selectionChatGroupSupported(", "func selectionGroupIsValid")
        self.assertIn('bundleIdentifier == "com.tencent.qq" && role == "AXGroup"', gate)
        recovery = section("func recoverySelection(", "struct SelectionCopyTicket")
        self.assertIn("if selectionChatGroupSupported(bundleIdentifier: source.bundleIdentifier, role: rootRole)", recovery)
        self.assertLess(recovery.index("recoverSelectedChatChildren("), recovery.index("probeUniqueSelection("))

    def test_optional_probe_does_not_consume_original_traversal_allowance(self):
        recovery = section("func recoverySelection(", "struct SelectionCopyTicket")
        self.assertIn("let chatProbeStarted = ProcessInfo.processInfo.systemUptime", recovery)
        self.assertIn("deadline += ProcessInfo.processInfo.systemUptime - chatProbeStarted", recovery)
        self.assertIn('reason: "selectedChildrenResourceLimit"', recovery)
        self.assertLess(recovery.index("deadline += ProcessInfo.processInfo.systemUptime - chatProbeStarted"),
                        recovery.index("let (result, count) = probeUniqueSelection"))

    def test_explicit_selected_children_are_bounded_and_typed(self):
        children = section("func selectedChatChildren(", "func recoverSelectedChatChildren(")
        self.assertIn("kAXSelectedChildrenAttribute", children)
        self.assertIn("AXUIElementGetAttributeValueCount", children)
        self.assertLess(children.index("count <= 64"), children.index("AXUIElementCopyAttributeValues"))
        self.assertIn("guard count >= 2", children)
        self.assertIn("CFArrayGetCount(values) == count", children)
        self.assertIn("CFGetTypeID(value) == AXUIElementGetTypeID()", children)
        self.assertIn("if unavailableSelectionRange(status) { return nil }", children)
        self.assertIn('reason: "selectedChildrenCountInvalid"', children)

    def test_multiple_selection_is_complete_unique_and_revalidated(self):
        read = section("func readVerifiedSelectionGroup<", "func selectedChatChildren(")
        self.assertIn("selectionGroupIsValid(original, same: same)", read)
        self.assertEqual(read.count("try children()"), 3)
        self.assertEqual(read.count("try read(child)"), 2)
        self.assertIn('return texts.joined(separator: "\\n")', read)
        self.assertIn("contextIsCurrent()", read)
        self.assertIn("withinBudget()", read)
        for failure in ("selectedChildNoPositiveText", "selectedChildrenChanged", "selectedChildTextChanged"):
            self.assertIn(failure, read)
        unique = section("func selectionGroupIsValid<", "func readVerifiedSelectionGroup<")
        self.assertIn("(2...64).contains(nodes.count)", unique)
        self.assertIn("nodes[..<index].contains", unique)

    def test_each_child_has_same_owner_window_parent_and_safe_positive_text(self):
        read = section("func recoverSelectedChatChildren(", "func recoverySelection(")
        for guard in ("selectionElementOwnerMatches(child, pid)", "CFEqual(initialWindow, window)",
                      "CFEqual(root, parent)", "kAXParentAttribute", "requireNonEditableCandidate: true",
                      "requireTextTarget: true", "AXIsProcessTrusted()", "!IsSecureEventInputEnabled()",
                      "selectionCopyTicket(source: source, matching: ticket) == ticket",
                      "selectionRecoveryRole(root, applicationPID: pid, deadline: deadline)",
                      "currentRole == rootRole"):
            self.assertIn(guard, read)
        for forbidden in ("kAXValueAttribute", "kAXTitleAttribute", "NSPasteboard", ".post(", "postToPid",
                          "activate(", "AXUIElementSetAttributeValue", "SelectionCompatibilityRequired"):
            self.assertNotIn(forbidden, read)

    def test_general_ambiguity_and_invalid_metadata_still_reject_copy(self):
        probe = section("func probeUniqueSelection<", "struct SelectionCompatibilityRequired")
        self.assertIn("guard selected == nil else { return (.ambiguous", probe)
        self.assertIn("return result == .none || result == .resourceLimit", probe)
        self.assertNotIn("com.tencent.qq", probe)
        range_policy = section("func selectionDecision(", "func opaqueSelectionContainer(")
        self.assertIn("if range.length == 0 { return opaqueDocument ? .copy : .empty }", range_policy)
        opaque = section("func opaqueSelectionContainer(", "func unavailableSelectionRange(")
        self.assertNotIn("com.tencent.qq", opaque)

    def test_failed_probe_retains_metadata_without_logging_private_content(self):
        recovery = section("func recoverySelection(", "struct SelectionCopyTicket")
        self.assertIn("let nodeTrace = SelectionTrace(publish: false)", recovery)
        self.assertIn('trace.record("selection-probe-detail", fields)', recovery)
        self.assertIn('fields["probeStep"] = probeStep', recovery)
        self.assertIn('childFields["childrenStatus"] = childrenStatus.rawValue', recovery)
        trace = section("private static let allowedFields:", "private let start =")
        for forbidden in ('"selectedText"', '"probeText"', '"clipboardText"', '"windowTitle"'):
            self.assertNotIn(forbidden, trace)

    def test_native_fixture_required_without_claiming_real_app_acceptance(self):
        runner = (ROOT / "tests/macos-native-self-test.sh").read_text()
        self.assertIn("try selectionChatMultiSelectionSelfTest()", SWIFT)
        self.assertEqual(SWIFT.count('"chatMultiSelectionFixturePassed": true'), 2)
        self.assertEqual(SWIFT.count('"qqInteractiveMultiSelectionTested": false'), 2)
        self.assertIn('"chatMultiSelectionFixturePassed",', runner)
        self.assertIn('checks.get("qqInteractiveMultiSelectionTested") is False', runner)


if __name__ == "__main__":
    unittest.main()
