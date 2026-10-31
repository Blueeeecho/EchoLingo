"""Focused candidate checks never weaken release or private-evidence boundaries."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / '.github/workflows/macos-selection-recovery-checks.yml').read_text()


class MacRecoveryWorkflowContract(unittest.TestCase):
    def test_only_exact_candidate_branch_with_read_only_permissions(self):
        self.assertIn('branches: [fix/025-macos-recovery-integration]', SOURCE)
        self.assertNotIn('pull_request:', SOURCE)
        self.assertNotIn('workflow_dispatch:', SOURCE)
        self.assertNotIn(': write', SOURCE)
        self.assertIn('contents: read', SOURCE)
        self.assertIn('persist-credentials: false', SOURCE)
        self.assertIn('git merge-base --is-ancestor "$base" HEAD', SOURCE)
        self.assertIn("if changed - allowed:", SOURCE)

    def test_real_bridge_must_execute_exactly_one_test(self):
        self.assertIn('mac_selection_source_identity_survives_real_swift_rust_swift_json_bridge -- --nocapture', SOURCE)
        self.assertIn('source_identity_failure_is_actionable_but_superseded_selection_stays_quiet -- --nocapture', SOURCE)
        self.assertEqual(SOURCE.count("grep -q 'test result: ok. 1 passed'"), 2)
        self.assertIn("grep -q 'legacyNumericMismatchCount='", SOURCE)

    def test_formatter_cannot_change_code_under_test(self):
        self.assertIn('git restore --worktree -- src-tauri', SOURCE)
        self.assertLess(SOURCE.index('git restore --worktree -- src-tauri'),
                        SOURCE.index('name: Compile Swift'))
        self.assertIn('if ! git diff --quiet -- src-tauri; then status=1; fi', SOURCE)

    def test_artifact_is_explicit_synthetic_evidence_not_private_state(self):
        artifact = SOURCE.split('name: macos-selection-recovery-evidence', 1)[1].split('      - name:', 1)[0]
        self.assertNotIn('*', artifact)
        self.assertNotIn('test-results', artifact)
        self.assertNotIn('diagnostics.json', artifact)
        self.assertEqual(artifact.count('${{ runner.temp }}/macos-selection-recovery/'), 10)

    def test_failure_is_not_a_skipped_or_implicit_pass(self):
        final = SOURCE.split('name: Require every executed candidate gate', 1)[1]
        for gate in ['guard', 'contracts', 'frontend', 'typography', 'formatting', 'swift', 'bridge', 'failure']:
            self.assertIn(f'steps.{gate}.outcome', final)
        self.assertIn('for outcome in $GATES; do test "$outcome" = success; done', final)
        for forbidden in ['tauri build', 'createRelease', 'git push', 'verify-language-patch.py']:
            self.assertNotIn(forbidden, SOURCE)


if __name__ == '__main__':
    unittest.main()
