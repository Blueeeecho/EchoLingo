"""Desktop-free wiring checks, not Swift or Codex interactive acceptance."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "src-tauri/native/macos.swift").read_text()


def section(start, end):
    return SOURCE[SOURCE.index(start):SOURCE.index(end, SOURCE.index(start))]


class PassiveButtonContract(unittest.TestCase):
    def test_passivity_requires_a_known_unfocused_non_source_button(self):
        gate = section("func selectionPassiveButtonAllowed(", "func selectionBooleanQuery(")
        for required in ('role == "AXButton", subrole == nil, !isSourceTarget',
                         'case .value(false) = focus', 'windowVerified && parentVerified'):
            self.assertIn(required, gate)
        boolean = section("func selectionBooleanQuery(", "func selectionPassiveButtonContextVerified(")
        self.assertIn("status == .success", boolean)
        self.assertIn("CFGetTypeID(value) == CFBooleanGetTypeID()", boolean)
        self.assertNotIn("return .value(false)", boolean)

    def test_live_proof_checks_owner_window_parent_and_has_no_content_read(self):
        proof = section("func selectionPassiveButtonContextVerified(", "func selectionPassiveButtonChildrenMatch(")
        for required in ("!CFEqual(element, root)", "!IsSecureEventInputEnabled()",
                         "selectionElementOwnerMatches(element, applicationPID)",
                         "kAXFocusedAttribute", "selectionBooleanQuery(status:",
                         "kAXParentAttribute", "CFEqual(parent, $0)",
                         "selectionOwningWindow(element, role: roleQuery.value",
                         "CFEqual(window, $0)", "selectionQueryBudgetAvailable(deadline)"):
            self.assertIn(required, proof)
        for forbidden in ("selectionNodeExplicitlyFocused(", "accessibilitySelection(", "kAXValueAttribute",
                          "kAXTitleAttribute", "NSPasteboard", "postToPid", "activate("):
            self.assertNotIn(forbidden, proof)

    def test_new_route_is_strict_only_and_never_a_text_or_copy_candidate(self):
        recovery = section("func recoverySelection(", "struct SelectionCopyTicket:")
        for required in ('optionalPluralRootFailure && roleQuery.value == "AXButton" && !sourceTarget',
                         "guard parents.count == 1", "if !passiveButton {",
                         "!hasPositiveSelection && !deferredPluralFailure && !passiveButton",
                         "selectionRecoveryContainer(roleQuery.value) || passiveButton",
                         "passiveButtons.append((element, parent, children))"):
            self.assertIn(required, recovery)
        ordinary_gate = section("func requireSelectionCopyTarget(", "func selectionFocusClassification(")
        self.assertIn('"AXButton"', ordinary_gate)
        containers = section("func selectionRecoveryContainer(", "func optionalPluralRootReadCanRecover(")
        self.assertNotIn('"AXButton"', containers)
        for forbidden in ("NSPasteboard", "postToPid", "kAXValueAttribute", "activate("):
            self.assertNotIn(forbidden, recovery)

    def test_complete_children_and_final_passivity_are_revalidated(self):
        children = section("func selectionPassiveButtonChildrenMatch(", "// Empty input focus")
        for required in ("count == children.count", "CFArrayGetCount(values) == count",
                         "CFGetTypeID(child) == AXUIElementGetTypeID()", "CFEqual(children[index], child)",
                         "requireSelectionQueryBudget(deadline)"):
            self.assertIn(required, children)
        recovery = section("func recoverySelection(", "struct SelectionCopyTicket:")
        final = recovery[recovery.index("for button in passiveButtons {"):]
        for required in ("selectionPassiveButtonFinalProof(parent: button.parent, observedParents: parents",
                         "selectionPassiveButtonContextVerified(button.element",
                         "selectionPassiveButtonChildrenMatch(button.element",
                         'reason: "passiveButtonChanged"'):
            self.assertIn(required, final)
        proof = section("func selectionPassiveButtonFinalProof<Node>(", "// Empty input focus")
        self.assertIn("observedParents.count == 1, same(observedParents[0], parent)", proof)
        self.assertIn("contextVerified() && childrenVerified()", proof)
        self.assertLess(final.index("selectionPassiveButtonChildrenMatch("),
                        final.index("let currentText = try? accessibilitySelection("))
        self.assertIn("mixedWindowVerified = mixedWindowVerified && contextIsCurrent()", final)
        self.assertIn("optionalPluralCopyForbidden", final)

    def test_native_fixture_covers_positives_and_counterexamples(self):
        self.assertIn("try selectionPassiveButtonSelfTest()", SOURCE)
        fixture = section("func selectionPassiveButtonSelfTest()", "func selectionOptionalPluralNestedGroupSelfTest()")
        for required in ("selectionPassiveButtonAllowed(", "selectionBooleanQuery(status:",
                         "selectionProbeObserveChildren(text: passive ? nil : node.text",
                         "complete.1 == [0, 1, 2, 3, 4]", "probe(unknown).0 == .incomplete",
                         "probe(secure).0 == .incomplete", "probe(ambiguous).0 == .ambiguous",
                         "probe(missingChildren).0 == .incomplete", "wrongWindow", "wrongParent", "sourceButton",
                         "maximumNodes: 3", "maximumDepth: 2", "context: false", "strict: false",
                         "rejected != .text(whole) && rejected != .compatibility",
                         "for parents in [[], [2], [1, 1], [1, 2]]",
                         "!finalProof(focus: .unavailable)", "!finalProof(children: children)"):
            self.assertIn(required, fixture)


if __name__ == "__main__":
    unittest.main()
