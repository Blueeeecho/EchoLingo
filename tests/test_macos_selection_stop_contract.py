"""Source wiring only; native fixtures must also run on macOS."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "src-tauri/native/macos.swift").read_text()


def section(start, end):
    return SOURCE[SOURCE.index(start):SOURCE.index(end, SOURCE.index(start))]


class SelectionStopContract(unittest.TestCase):
    def test_summary_is_independent_of_event_truncation_and_fixed_classifications(self):
        trace = section("final class SelectionTrace", "// Taken at shortcut dispatch")
        self.assertIn("private var probeTermination: [String: Any]?", trace)
        self.assertIn('"probeTermination": probeTermination as Any? ?? NSNull()', trace)
        recorder = section("func recordProbeStop(", "private func elapsedMilliseconds()")
        self.assertIn("probeTermination = fields", recorder)
        self.assertIn('roles.contains($0) ? $0 : "unknown"', recorder)
        self.assertIn('steps.contains($0) ? $0 : "unknown"', recorder)
        for forbidden in ("AXUIElementCopy", '"selectedText"', '"windowTitle"', "NSPasteboard"):
            self.assertNotIn(forbidden, recorder)

    def test_all_walker_terminations_have_one_typed_callback(self):
        walker = section("func probeUniqueSelection<Node>(", "func selectionProbeAllowsCompatibility(")
        self.assertEqual(walker.count("onStop(SelectionProbeStop("), 1)
        self.assertEqual(walker.count("return ("), 1)  # Only the common finish function.
        for reason in ("invalidConfiguration", "timeLimit", "nodeLimit", "depthLimit", "childrenLimit",
                       "contextChanged", "observerInvalid", "observerResourceLimit", "protectedNode",
                       "ambiguousSelection", "noPositiveSelection", "positiveSelection"):
            self.assertIn("." + reason, walker)
        self.assertIn("maximumNodes: Int = 64, maximumDepth: Int = 6", walker)
        self.assertIn("if requireCompleteSubtree() { return finish(.incomplete, .protectedNode) }", walker)
        self.assertIn("if !requireCompleteSubtree() { continue }", walker)

    def test_bfs_parent_depth_and_duplicates_are_not_conflated(self):
        walker = section("func probeUniqueSelection<Node>(", "func selectionProbeAllowsCompatibility(")
        self.assertIn("let (node, depth, parentIndex) = pending.removeFirst()", walker)
        self.assertIn("parentIndex: parentIndex, depth: depth", walker)
        self.assertIn("value.children.map { ($0, depth + 1, visited.count) }", walker)
        self.assertIn("duplicateNodes += 1; continue", walker)
        self.assertIn("positiveNodes += 1", walker)

    def test_production_protected_exit_is_observable_without_changing_admission(self):
        recovery = section("func recoverySelection(", "struct SelectionCopyTicket:")
        self.assertIn("trace.recordProbeStop(stop, role: probeRole, subrole: probeSubrole", recovery)
        self.assertIn("sourceTarget: probeSourceTarget, documentNodes: probeDocumentNodes, observerStep: probeStep", recovery)
        self.assertIn("if readonlySelectionContainer(probeRole) { probeDocumentNodes += 1 }", recovery)
        self.assertIn('probeStep = "copyTarget"', recovery)
        self.assertIn("if optionalPluralRootFailure && sensitive { return invalid() }", recovery)
        self.assertIn("return SelectionProbeObservation(text: nil, children: [], protected: true)", recovery)
        self.assertIn("ProcessInfo.processInfo.systemUptime + 0.18", recovery)

    def test_native_matrix_and_generated_six_node_failure_are_on_required_path(self):
        self.assertIn("try selectionProbeTerminationSelfTest()", SOURCE)
        fixture = section("func selectionProbeTerminationSelfTest()", "func selectionOptionalPluralNestedGroupSelfTest()")
        for marker in ("requireSelectionCopyTarget(role: role, subrole: nil)",
                       "reproduced.1 == 6 && deferredGroups == 4", "stop.visit.depth == 1",
                       "stop.visit.parentIndex == 1", "stop.visit.remaining == 58",
                       'trace.snapshot()["probeTermination"]', 'summary?["probeRoleClass"] as? String == "AXButton"',
                       "0..<96", '!encoded.contains("private-termination-sentinel")',
                       "cycleResult.1.duplicateNodes == 1", "strict: false).0 == .none"):
            self.assertIn(marker, fixture)
        for reason in ("invalidConfiguration", "timeLimit", "nodeLimit", "depthLimit", "childrenLimit",
                       "contextChanged", "observerInvalid", "observerResourceLimit", "protectedNode",
                       "ambiguousSelection", "noPositiveSelection", "positiveSelection"):
            self.assertIn("." + reason, fixture)


if __name__ == "__main__":
    unittest.main()
