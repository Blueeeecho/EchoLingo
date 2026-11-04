"""Source contracts only. Actual Swift fixtures require the macOS runner."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src-tauri/native/macos.swift").read_text()


def section(start, end):
    return SOURCE[SOURCE.index(start):SOURCE.index(end, SOURCE.index(start))]


class ClipboardTerminationContract(unittest.TestCase):
    def test_summary_is_typed_bounded_and_independent_of_events(self):
        trace = section("final class SelectionTrace", "// Taken at shortcut dispatch")
        self.assertIn("private var clipboardTermination: SelectionCopyTermination?", trace)
        self.assertIn('"clipboardTermination": clipboardTermination?.snapshot as Any? ?? NSNull()', trace)
        recorder = section("func recordClipboardStop(", "private func elapsedMilliseconds")
        self.assertIn("clipboardTermination = stop", recorder)
        self.assertNotIn("events", recorder)
        diagnostic = section("enum SelectionCopyStopReason", "// Pure production state machine")
        for reason in ("readGenerationChanged", "candidateGenerationChanged", "candidateCleared",
                       "unchangedTimeout", "unfinishedTimeout", "stableText", "stableEmpty"):
            self.assertIn(reason, diagnostic)
        self.assertIn("subtractingReportingOverflow", diagnostic)
        self.assertIn("min(64, max(-64, delta.partialValue))", diagnostic)
        for forbidden in ("NSPasteboard", "candidateText", "hash", "bundleIdentifier", "title", "format"):
            self.assertNotIn(forbidden, diagnostic)

    def test_every_production_exit_publishes_summary_without_new_copy_or_restore(self):
        loop = section("func copiedSelection(", "func selection(requestSource:")
        self.assertIn("trace: SelectionTrace? = nil", loop)
        self.assertIn("defer { if let stop = completion.termination { trace?.recordClipboardStop(stop) } }", loop)
        self.assertIn("systemUptime + 1.2", loop)
        self.assertIn("Thread.sleep(forTimeInterval: 0.005)", loop)
        self.assertIn("copied = try copiedSelection(pasteboard, initialCount: initialCount, trace: trace)", SOURCE)
        for forbidden in ("clearContents", "restore(", "writeObjects", "postToPid"):
            self.assertNotIn(forbidden, loop)

    def test_original_safety_decisions_remain_and_reasons_are_observational(self):
        state = section("struct SelectionCopyCompletion", "func requireSelectionFocus(")
        self.assertIn("static let settleInterval: TimeInterval = 0.02", state)
        self.assertIn("let result = evaluate(", state)
        self.assertIn("case .waiting: return result", state)
        for guard in ("guard countBefore == countAfter else { return .superseded }",
                      "if let candidateCount, candidateCount != countAfter { return .superseded }",
                      "guard countAfter != initialCount else { return expired ? .unchangedTimeout : .waiting }",
                      "} else if candidateCount != nil {", "return .unfinishedTimeout"):
            self.assertIn(guard, state)

    def test_native_fixture_covers_all_outcomes_and_privacy_on_required_path(self):
        fixture = section("func selectionCopyPolicySelfTest()", "// Exercise the same snapshot/restore")
        self.assertIn("try selectionCopyPolicySelfTest()", SOURCE)
        for marker in ("(newer, .candidateGenerationChanged)", "(duringRead, .readGenerationChanged)",
                       "(clearedCandidate, .candidateCleared)", "(unchanged, .unchangedTimeout)",
                       "(late, .unfinishedTimeout)", "(lateClear, .unfinishedTimeout)",
                       "(deferred, .stableText)", "(empty, .stableEmpty)", "(lazy, .stableText)",
                       "0..<96", "Set(summary.keys) == expectedKeys", 'snapshot["clipboardTermination"]',
                       '!encoded.contains("private-clipboard-sentinel")', '!encoded.contains("98765432")',
                       "relativeCount(Int.max, initial: Int.min)", "relativeCount(Int.min, initial: Int.max)"):
            self.assertIn(marker, fixture)
        runner = (ROOT / "tests/macos-native-self-test.sh").read_text()
        self.assertIn("--selection-policy-self-test", runner)


if __name__ == "__main__":
    unittest.main()
