"""Wiring/privacy checks; not a macOS or real Codex acceptance test."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'src-tauri/native/macos.swift').read_text()


def section(start, end):
    return SOURCE[SOURCE.index(start):SOURCE.index(end, SOURCE.index(start))]


class OptionalPluralRecoveryContract(unittest.TestCase):
    def test_only_exact_root_failure_is_deferred_not_reclassified(self):
        gate = section('func optionalPluralRootReadCanRecover(', 'func shouldQueryPluralSelectionRanges(')
        for condition in ('allowed && role == "AXGroup" && bounded', 'textStatus == .noValue',
                          'validSelectionRange($0) && $0.length == 0',
                          'capabilityDeclared == true && pluralStatus == .failure'):
            self.assertIn(condition, gate)
        parser = section('func selectionRangesQuery(', 'func requireUsableSelectionQuery')
        self.assertIn('unavailableSelectionRange(status) ? .unavailable : .invalid', parser)
        selection = section('func accessibilitySelection(', 'func selectionRecoveryContainer(')
        self.assertIn('allowOptionalPluralRootRecovery: Bool = false', selection)
        self.assertIn('throw SelectionOptionalPluralRootFailure()', selection)
        self.assertIn('"pluralStatus": status.rawValue, "pluralState": query.state', selection)
        self.assertIn('try requireUsableSelectionQuery(query)', selection)

    def test_deferred_recovery_is_root_only_and_requires_an_initial_window(self):
        recovery = section('func recoverySelection(', 'struct SelectionCopyTicket:')
        self.assertIn('allowOptionalPluralRootRecovery: originalFocus != nil && CFEqual(element, root) &&', recovery)
        self.assertIn('sourceWindowTicket != nil && initialWindow.value != nil', recovery)
        self.assertIn('catch is SelectionOptionalPluralRootFailure', recovery)
        self.assertIn('trace.record("selection-probe-ax", event)', recovery)
        self.assertIn('!knownEmptyEditor && !optionalPluralRootFailure', recovery)
        self.assertIn('if optionalPluralRootFailure && sensitive { return invalid() }', recovery)

    def test_unknown_siblings_or_unenumerated_containers_cannot_look_complete(self):
        recovery = section('func recoverySelection(', 'struct SelectionCopyTicket:')
        self.assertIn('optionalPluralRootFailure && !CFEqual(element, root) && !confirmedEmpty', recovery)
        self.assertIn('probeStep = "optionalPluralUnknownSelection"', recovery)
        self.assertIn('probeStep = "optionalPluralUnknownLeaf"', recovery)
        children = recovery[recovery.index('if unavailableSelectionRange(countStatus)'):]
        self.assertIn('if optionalPluralRootFailure { return invalid() }', children)
        self.assertIn('guard childCount <= remaining else { return limited() }', children)

    def test_strict_recovery_enumerates_positive_candidates_in_observer_and_walker(self):
        helper = section('func selectionProbeObserveChildren<Node>(', 'enum SelectionProbeResult:')
        self.assertIn('if let positiveText, !requireCompleteSubtree', helper)
        self.assertIn('guard let observation = try children()', helper)
        self.assertIn('text: positiveText, children: observation.children', helper)
        walker = section('func probeUniqueSelection<Node>(', 'func selectionProbeAllowsCompatibility(')
        self.assertIn('requireCompleteSubtree: () -> Bool = { false }', walker)
        self.assertIn('if !requireCompleteSubtree() { continue }', walker)
        self.assertIn('if requireCompleteSubtree() { return (.incomplete, visited.count) }', walker)
        self.assertLess(walker.index('if !requireCompleteSubtree() { continue }'),
                        walker.index('pending.append(contentsOf: value.children'))
        recovery = section('func recoverySelection(', 'struct SelectionCopyTicket:')
        self.assertIn('requireCompleteSubtree: { optionalPluralRootFailure }', recovery)
        start = recovery.index('if hasPositiveSelection {')
        end = recovery.index('return try selectionProbeObserveChildren(', start)
        self.assertNotIn('return ', recovery[start:end])
        self.assertNotIn('children: []', recovery[start:end])
        children = recovery[end:recovery.index('} catch is SelectionProbeBudgetExpired', end)]
        self.assertIn('requireCompleteSubtree: optionalPluralRootFailure)', children)
        self.assertIn('!confirmedEmpty && !hasPositiveSelection', children)
        self.assertIn('AXUIElementGetAttributeValueCount(', children)
        self.assertIn('AXUIElementCopyAttributeValues(', children)
        self.assertIn('text: nil, children: children, protected: false', children)

    def test_success_requires_document_selection_revalidation_not_fragment_joining(self):
        gate = section('func selectionOptionalPluralRecoveryDisposition(', 'func selectionOwningWindow(')
        self.assertIn('guard case .text(let text) = result', gate)
        self.assertIn('guard readonlySelectionContainer(candidateRole)', gate)
        self.assertIn('guard windowAndSelectionVerified', gate)
        self.assertNotIn('.compatibility', gate)
        self.assertNotIn('joined(', gate)
        recovery = section('func recoverySelection(', 'struct SelectionCopyTicket:')
        for proof in ('selectionRecoveryRole(root, applicationPID: pid, deadline: deadline)) == rootRole',
                      'selectionRecoveryRole(candidate, applicationPID: pid, deadline: deadline)) == selectedCandidateRole',
                      'selectionMixedTextStillSelected(selectedText, current: currentText)',
                      'selectionMixedWindowMatches(', 'selectionCopyTicket(source: source, matching: ticket) == ticket'):
            self.assertIn(proof, recovery)
        terminal = recovery[recovery.index('if optionalPluralRootFailure {\n        // This separate terminal branch'):]
        self.assertLess(terminal.index('selectionOptionalPluralRecoveryDisposition('), terminal.index('switch selectionRecoveryDisposition('))
        self.assertIn('case .compatibility: throw unavailableSelectionError', terminal)
        for forbidden in ('NSPasteboard', 'postToPid', '.post(', 'kAXValueAttribute', 'activate('):
            self.assertNotIn(forbidden, recovery)

    def test_native_exact_shape_and_negative_fixtures_remain_on_required_path(self):
        self.assertIn('try selectionOptionalPluralRecoverySelfTest()', SOURCE)
        fixture = section('func selectionOptionalPluralRecoverySelfTest()', 'func selectionMixedRecoverySelfTest()')
        for marker in ('first synthetic message\\nsecond synthetic message', 'selectionRangesQuery(status: .failure, value: nil).state == "invalid"',
                       'probe(fragments) == .ambiguous', 'probe(unknown) == .incomplete', 'rejected != .compatibility',
                       'context: false', 'blocked: true', 'selectionMixedTextStillSelected(whole, current: nil)',
                       'snapshot["optionalPluralRootFailure"] as? Bool == true', 'snapshot["copyIssued"] as? Bool == false'):
            self.assertIn(marker, fixture)
        for forbidden in ('AXUIElementCopy', 'NSPasteboard', 'postToPid', 'activate('):
            self.assertNotIn(forbidden, fixture)

    def test_native_nested_counterexamples_use_the_production_observer_helper(self):
        parent = section('func selectionOptionalPluralRecoverySelfTest()', 'func selectionOptionalPluralSubtreeSelfTest()')
        self.assertIn('try selectionOptionalPluralSubtreeSelfTest()', parent)
        fixture = section('func selectionOptionalPluralSubtreeSelfTest()', 'func selectionMixedRecoverySelfTest()')
        for marker in ('optionalPluralRootReadCanRecover(allowed: true',
                       'textStatus: .noValue, selectedRange: CFRange(location: 0, length: 0)',
                       'capabilityDeclared: true, pluralStatus: .failure',
                       'requireCompleteSubtree: { strict }',
                       'selectionProbeObserveChildren(text: node.text, requireCompleteSubtree: strict)',
                       'childrenRead.append(id)', 'complete.childrenRead == [0, 1, 2]',
                       'FixtureNode(role: "AXWebArea", text: whole, children: [2])',
                       'nestedPositive[2] = FixtureNode(role: "AXDocument", text:',
                       'nestedUnknown[2] = FixtureNode(role: "AXDocument", confirmedEmpty: false)',
                       'nestedSecure[2] = FixtureNode(role: "AXTextField", secure: true)',
                       'ambiguous.result == .ambiguous', 'unknown.result == .incomplete',
                       'secure.result == .incomplete', 'probe(unavailableChildren).result == .incomplete',
                       'maximumNodes: 2).result == .resourceLimit', 'maximumDepth: 1).result == .resourceLimit',
                       'disposition != .compatibility', 'ordinary.childrenRead == [0]',
                       'ordinary.observed == [0, 1]', 'ordinaryWalker.1 == 1'):
            self.assertIn(marker, fixture)


if __name__ == '__main__':
    unittest.main()
