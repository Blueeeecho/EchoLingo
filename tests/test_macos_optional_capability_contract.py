"""Wiring checks only; native metadata/safety fixtures execute on macOS CI.

AX failure is not unsupported. Apple's CopyAttributeNames API reports supported
attributes; only a successful, validated list can omit the optional plural read.
No private diagnostics or selected text are fixtures here.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'src-tauri/native/macos.swift').read_text()


def section(start, end):
    return SOURCE[SOURCE.index(start):SOURCE.index(end, SOURCE.index(start))]


class OptionalCapabilityContract(unittest.TestCase):
    def test_exact_predicate_and_strict_capabilities(self):
        policy = section('func optionalPluralCapabilityRequired(', 'func accessibilitySelection(')
        for check in ('selectionRecoveryContainer(role)',
                      '&& bounded', 'textStatus == .noValue', 'selectedRange?.length == 0',
                      'status == .success', 'names.count <= 128', 'Set(names).count == names.count',
                      'names.contains(kAXSelectedTextRangeAttribute as String)', 'return .invalid'):
            self.assertIn(check, policy)
        self.assertNotIn('bundleIdentifier', policy)
        self.assertNotIn('.copy', policy)
        self.assertNotIn('.unavailable', policy)

    def test_bundle_independent_capability_does_not_expand_chat_copy_policy(self):
        policy = section('func optionalPluralCapabilityRequired(', 'func accessibilitySelection(')
        # The query-decision API has no app identity input at all: Codex, QQ,
        # Feishu and unknown apps follow the same capability/role predicate.
        for bundle in ('com.openai.codex', 'com.tencent.qq', 'com.electron.lark', 'unknown.application'):
            self.assertNotIn(bundle, policy)
        chat = SOURCE[SOURCE.index('func selectionChatGroupSupported('):SOURCE.index('}', SOURCE.index('func selectionChatGroupSupported('))]
        self.assertIn('bundleIdentifier == "com.tencent.qq" && role == "AXGroup"', chat)
        opaque = SOURCE[SOURCE.index('func opaqueSelectionContainer('):SOURCE.index('}', SOURCE.index('func opaqueSelectionContainer('))]
        self.assertIn('com.kingsoft.wpsoffice.mac', opaque)

    def test_optional_query_is_skipped_before_call_not_after_failure(self):
        selection = section('func accessibilitySelection(', 'func selectionRecoveryContainer(')
        self.assertLess(selection.index('selectionFocusClassification('), selection.index('AXUIElementCopyAttributeNames('))
        self.assertLess(selection.index('AXUIElementCopyAttributeNames('), selection.index('kAXSelectedTextRangesAttribute as CFString'))
        self.assertIn('try requireUsableSelectionQuery(capability)\n        queryPlural = capability.value != false', selection)
        self.assertIn('if queryPlural {', selection)
        self.assertIn('try requireUsableSelectionQuery(query)', selection)
        # Discovery diagnostics never serialize capability names or any text.
        self.assertIn('"pluralCapabilityDeclared": capability.value', selection)
        self.assertNotIn('"pluralCapabilityNames"', SOURCE)

    def test_native_regression_and_existing_safety_fixtures_remain_invoked(self):
        for fixture in ('selectionMetadataPolicySelfTest', 'selectionCompatibilitySelfTest',
                        'selectionClassificationPolicySelfTest', 'selectionCopyPolicySelfTest'):
            self.assertIn('try ' + fixture + '()', SOURCE)
        metadata = section('func selectionMetadataPolicySelfTest()', 'func selectionClassificationPolicySelfTest()')
        for marker in ('value: declaredNames).value == true', 'value: absentNames).value == false',
                       'Failed capability discovery', 'Malformed capability discovery',
                       '"AXTextField"', '"AXTextArea"', 'kAXSecureTextFieldSubrole'):
            self.assertIn(marker, metadata)
        compatibility = section('func selectionCompatibilityRejectionReason(', 'func selectionCompatibilityContextAllowed(')
        for marker in ('secureInputEnabled', 'current == ticket', 'sameFocus', 'focusQueryInvalid'):
            self.assertIn(marker, compatibility)
        completion = SOURCE[SOURCE.index('func selectionCopyPolicySelfTest()'):]
        self.assertIn('text: "old clipboard text"', completion)
        self.assertIn('== .unchangedTimeout', completion)


if __name__ == '__main__':
    unittest.main()
