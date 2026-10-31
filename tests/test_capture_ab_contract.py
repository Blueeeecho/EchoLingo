"""Keep same-runner comparison coverage aligned with its strict native fixture."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
AB = (ROOT / "tests/windows-native-capture-ab.ps1").read_text()
NATIVE = (ROOT / "tests/windows-native-capture-smoke.ps1").read_text()
COMMON = [
    "first-fresh-pair-immediate-release", "topmost-self-raise-immediate-first-pair",
    "foreign-thread-native-capture", "cross-peer-held900ms",
    "preheld-source-release-then-first-fresh-pair", "escape-drains-owned-release",
    "escape-held-release-after-helper-close", "next-capture-after-escape",
    "display-change-before-input", "next-capture-after-display-change",
]


def quoted_values(pattern, text, quote):
    match = re.search(pattern, text)
    if match is None:
        raise AssertionError("Required fixture mode declaration is missing")
    return re.findall(quote + r"([^" + quote + r"]+)" + quote, match.group(1))


class CaptureABContract(unittest.TestCase):
    def test_preserves_all_ten_common_comparisons_in_order(self):
        common = quoted_values(r"\$common=@\(([^\n]+)\)", AB, "'")
        self.assertEqual(common, COMMON)
        self.assertIn("foreach($mode in $common)", AB)
        self.assertIn("if($values.Count -ne 3){throw 'AB_PAIR_COUNT'}", AB)

    def test_native_modes_match_complete_fixture_without_duplicates(self):
        extra = quoted_values(r"\$nativeModes=\$common\+@\(([^\n]+)\)", AB, "'")
        modes = quoted_values(r'foreach\(string kind in new string\[\]\{([^}]+)\}\)', NATIVE, '"')
        declared = COMMON + extra
        self.assertEqual(len(declared), 16)
        self.assertEqual(len(set(declared)), 16)
        self.assertEqual(set(declared), set(modes))
        self.assertEqual(len(modes), 16)
        self.assertIn("magnifier-continuity-armed-and-dragging", extra)

    def test_three_round_totals_and_strict_case_checks_remain_required(self):
        self.assertIn("$round -lt 3", AB)
        self.assertIn("allLegacyCasesPassed=30;allNativeCasesPassed=48", AB)
        self.assertIn("if($exitCode -ne 0){throw", AB)
        self.assertIn("@($result.cases).Count -ne $expected", AB)
        self.assertIn("@($result.cases|Where-Object {-not $_.ok}).Count", AB)
        self.assertIn("@(Compare-Object $expectedModes $actualModes).Count", AB)
        self.assertIn("noRetries=$true", AB)


if __name__ == "__main__":
    unittest.main()
