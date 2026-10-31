"""Focused immutable-artifact diagnostics never replace full acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / '.github/workflows/f1-fixture-reuse.yml').read_text()


class F1FixtureReuseWorkflowContract(unittest.TestCase):
    def test_exact_temporary_branch_and_read_only_permissions(self):
        self.assertIn('branches: [diagnostics/024-f1-fixture-reuse, diagnostics/024-macos-hover-repair]', SOURCE)
        self.assertNotIn('pull_request:', SOURCE)
        self.assertNotIn('workflow_run:', SOURCE)
        self.assertIn('contents: read', SOURCE)
        self.assertIn('actions: read', SOURCE)
        self.assertNotIn(': write', SOURCE)
        self.assertIn('persist-credentials: false', SOURCE)

    def test_quick_mac_probe_is_identical_to_strict_full_ci_job(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        expected = ci.split('  macos-screenshot-native-probe:\n', 1)[1].split('  desktop:\n', 1)[0].strip()
        actual = SOURCE.split('  macos-screenshot-native-probe:\n', 1)[1]
        condition = "    if: contains(github.event.head_commit.message, '[mac-probe]')\n"
        self.assertEqual(actual.count(condition), 1)
        actual = actual.replace(condition, '').strip()
        self.assertNotIn('[mac-probe]', ci)
        self.assertIn("if: ${{ github.ref == 'refs/heads/diagnostics/024-f1-fixture-reuse' && !contains(github.event.head_commit.message, '[mac-only]') }}", SOURCE)
        self.assertNotIn('[mac-only]', ci)
        self.assertNotIn('[mac-only]', (ROOT / '.github/workflows/release-checks.yml').read_text())
        self.assertNotIn('[mac-probe]', (ROOT / '.github/workflows/release-checks.yml').read_text())
        self.assertEqual(actual, expected)

    def test_all_production_changes_fail_and_pins_are_not_inputs(self):
        self.assertIn("git diff --name-only $base HEAD", SOURCE)
        self.assertIn("if ($path -notmatch $allowed) { throw", SOURCE)
        self.assertIn('033aa3718a0c56f05dc752c0fd729f71299b3eff', SOURCE)
        self.assertIn('41169341340', SOURCE)
        self.assertIn('13031215832', SOURCE)
        self.assertIn('13030374934', SOURCE)
        self.assertIn("crypto.createHash('sha256').update(bytes).digest('hex') !== expected.digest", SOURCE)
        self.assertIn('artifact.workflow_run?.head_sha !== source', SOURCE)
        self.assertNotIn('workflow_dispatch:', SOURCE)
        self.assertNotIn('inputs.', SOURCE)

    def test_diagnostic_executes_no_build_or_release_and_preserves_failures(self):
        self.assertIn('scripts/windows-f1-fixture-reuse.ps1', SOURCE)
        self.assertLess(SOURCE.index('Parser]::ParseFile'), SOURCE.index('name: Run original shortcut'))
        self.assertIn('if: always()', SOURCE)
        self.assertIn('It is not release acceptance.', SOURCE)
        for command in ('cargo build', 'tauri build', 'offline-engine/build.py', 'npm ci', 'createRelease', 'git push'):
            self.assertNotIn(command, SOURCE)
        self.assertNotIn('continue-on-error:', SOURCE.split('  macos-screenshot-native-probe:', 1)[0])


if __name__ == '__main__': unittest.main()
