import importlib.util
import json
import re
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('language_patch', ROOT/'scripts/verify-language-patch.py')
MODULE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(MODULE)

FULL_JOBS = {
    'rust-input-preparation', 'windows-rust-capture-candidate',
    'macos-native-frame-probe', 'macos-screenshot-native-probe',
    'desktop', 'frontend-interactions',
}


def assert_language_job_gates(test, source):
    parts = re.split(r'^  ([\w-]+):\n', source.split('jobs:\n', 1)[1], flags=re.MULTILINE)
    jobs = dict(zip(parts[1::2], parts[2::2]))
    exclusion = "needs.validation-mode.outputs.mode != 'language-routing-patch-v1'"
    scoped_jobs = {
        name for name, body in jobs.items()
        if any(exclusion in gate for gate in re.findall(r'^    if: (.+)$', body, re.MULTILINE))
    }
    test.assertEqual(scoped_jobs, FULL_JOBS)
    options = re.search(r'^        options: \[(.+)\]$', source, re.MULTILINE).group(1).split(', ')
    diagnostic_clauses = {f"github.event.inputs.mode != '{mode}'" for mode in options
                          if mode not in {'full', 'macos-preview', 'windows-preview'}}
    base_modes = {'desktop-recovery', 'windows-unpack', 'language-routing-patch-v1', 'automatic-direction', 'routing-release'}
    for name in FULL_JOBS:
        with test.subTest(job=name):
            body = jobs[name]
            test.assertEqual(re.findall(r'^    needs: (.+)$', body, re.MULTILINE), ['validation-mode'])
            gates = re.findall(r'^    if: (.+)$', body, re.MULTILINE)
            test.assertEqual(len(gates), 1)
            clauses = gates[0].split(' && ')
            expected_modes = base_modes.copy()
            if name != 'rust-input-preparation':
                expected_modes.add('screenshot-pins')
            if name not in {'rust-input-preparation', 'frontend-interactions'}:
                expected_modes.add('macos-followup')
            expected = {f"needs.validation-mode.outputs.mode != '{mode}'" for mode in expected_modes}
            if name == 'rust-input-preparation':
                expected.add("github.event_name == 'pull_request'")
            if name in {'desktop', 'frontend-interactions'}:
                expected |= diagnostic_clauses
            # Exact conjuncts, regardless of order. Missing/inverted guards,
            # unknown scope exclusions, OR/always()/false and duplicates fail.
            test.assertEqual(set(clauses), expected)
            test.assertEqual(len(clauses), len(expected))


class LanguagePatchContract(unittest.TestCase):
    def test_exact_reviewed_source_and_no_existing_dependency_upgrade(self):
        # The current release must never qualify for historical language-only reuse.
        with patch.object(MODULE.subprocess, 'check_output', side_effect=AssertionError('Ineligible release must not query Git')) as git:
            with self.assertRaisesRegex(ValueError, 'only authorized for the exact 0.2.4'): MODULE.verify()
            git.assert_not_called()
        self.assertEqual(MODULE.BASE, '4b8c5f5ac67e07cc4005812963b2c02acdd14d5d')
        self.assertEqual(len(MODULE.PINS), 3)
    def test_retained_language_test_command_does_not_select_old_release_scope(self):
        for version in ['0.2.6', '0.2.7', '0.2.8', '0.2.9', '0.2.12', '0.2.4-beta.1', None]:
            with self.subTest(version=version), patch.object(MODULE, 'verify') as verify:
                self.assertEqual(MODULE.select_mode({'version': version, 'scripts': {'test:language-routing': MODULE.COMMAND}}), 'full')
                verify.assert_not_called()
        package = {'version': '0.2.4', 'scripts': {'test:language-routing': MODULE.COMMAND}}
        with patch.object(MODULE, 'verify') as verify:
            self.assertEqual(MODULE.select_mode(package), MODULE.MODE)
            verify.assert_called_once_with()
        with patch.object(MODULE, 'verify', side_effect=ValueError('changed historical source')):
            with self.assertRaises(ValueError): MODULE.select_mode(package)
        package['scripts']['test:language-routing'] = 'different command'
        with patch.object(MODULE, 'verify') as verify:
            self.assertEqual(MODULE.select_mode(package), 'full')
            verify.assert_not_called()

    def test_unapproved_source_or_wrong_pin_fails_closed(self):
        # Exercise the actual path/pin guards with an eligible generated package,
        # independently of the current release version or checkout history depth.
        with tempfile.TemporaryDirectory() as directory, patch.object(MODULE, 'ROOT', Path(directory)):
            (Path(directory)/'package.json').write_text(json.dumps({
                'version': '0.2.4', 'scripts': {'test:language-routing': MODULE.COMMAND}}), encoding='utf-8')
            with patch.object(MODULE, 'git', side_effect=[MODULE.TREE, 'src-tauri/src/screenshot.rs']) as git:
                with self.assertRaisesRegex(ValueError, 'unapproved file'): MODULE.verify()
                self.assertEqual(git.call_count, 2)
            with patch.object(MODULE, 'git', side_effect=[MODULE.TREE, '']), \
                    patch.object(MODULE.subprocess, 'check_output', return_value=b'unapproved canonical source') as canonical:
                with self.assertRaisesRegex(ValueError, 'Exact reviewed language input changed'): MODULE.verify()
                canonical.assert_called_once()

    def test_direct_verification_rejects_other_versions_and_commands_without_git(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(MODULE, 'ROOT', Path(directory)), \
                patch.object(MODULE.subprocess, 'check_output', side_effect=AssertionError('No historical Git access')) as git:
            for version, command in [('0.2.6', MODULE.COMMAND), ('0.2.7', MODULE.COMMAND), ('0.2.8', MODULE.COMMAND), ('0.2.9', MODULE.COMMAND), ('0.2.12', MODULE.COMMAND), ('0.2.4', 'different command')]:
                with self.subTest(version=version, command=command):
                    (Path(directory)/'package.json').write_text(json.dumps({
                        'version': version, 'scripts': {'test:language-routing': command}}), encoding='utf-8')
                    with self.assertRaisesRegex(ValueError, 'only authorized for the exact 0.2.4'): MODULE.verify()
            git.assert_not_called()

    def test_fixed_mode_does_not_make_gui_claims(self):
        source = (ROOT/'.github/workflows/language-patch-checks.yml').read_text()
        self.assertIn('npm run test:language-routing',source)
        self.assertIn('npm run tauri build -- --bundles',source)
        self.assertIn('-- --locked',source)
        self.assertIn('scripts/verify-language-patch.py',source)
        for forbidden in ['windows-application-smoke','test:ui','macos-screenshot-native-fixture','git push','contents: write']:
            self.assertNotIn(forbidden,source)
        self.assertIn('13034542412',source)
        self.assertIn('13034970610',source)
        self.assertIn("run.conclusion !== 'success'",source)
    def test_normal_release_path_and_no_overwrite_are_retained(self):
        source = (ROOT/'.github/workflows/release.yml').read_text()
        self.assertIn('uses: ./.github/workflows/release-checks.yml',source)
        self.assertNotIn("needs.language-patch.result",source)
        self.assertIn("needs.verify.result == 'success'",source)
        self.assertIn('Only the exact main release commit',source)
        self.assertIn('Release already exists; no files were overwritten.',source)
        self.assertIn('release remains a draft.',source)
    def test_ci_only_skips_full_jobs_after_successful_source_guard(self):
        source=(ROOT/'.github/workflows/ci.yml').read_text()
        assert_language_job_gates(self, source)
        self.assertIn('cargo test --manifest-path tests/language-routing-patch/Cargo.toml --locked',source)
        self.assertIn("ref: ${{ github.event.pull_request.head.sha || github.sha }}",source)

    def test_ci_job_gate_contract_rejects_weakened_or_unreviewed_conditions(self):
        source = (ROOT/'.github/workflows/ci.yml').read_text()
        exclusion = "needs.validation-mode.outputs.mode != 'language-routing-patch-v1'"
        for replacement in ['', exclusion.replace('!=', '=='), exclusion + ' || true',
                            exclusion + ' && false', exclusion + ' && ' + exclusion,
                            exclusion + " && needs.validation-mode.outputs.mode != 'unreviewed-mode'"]:
            with self.subTest(replacement=replacement), self.assertRaises(AssertionError):
                # A plain TestCase keeps expected failures out of this test's
                # own subtest outcome bookkeeping.
                assert_language_job_gates(unittest.TestCase(), source.replace(exclusion, replacement, 1))
        with self.assertRaises(AssertionError):
            assert_language_job_gates(unittest.TestCase(), source.replace('  desktop:\n', '  renamed-desktop:\n', 1))

if __name__ == '__main__': unittest.main()
