import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('language_patch', ROOT/'scripts/verify-language-patch.py')
MODULE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(MODULE)

class LanguagePatchContract(unittest.TestCase):
    def test_exact_reviewed_source_and_no_existing_dependency_upgrade(self):
        self.assertEqual(MODULE.verify()['runId'], 41178655504)
        self.assertEqual(len(MODULE.PINS), 3)
    def test_unapproved_source_or_wrong_pin_fails_closed(self):
        original = MODULE.git
        def injected(*args):
            if args[:2] == ('diff','--name-only'): return 'src-tauri/src/screenshot.rs'
            return original(*args)
        with patch.object(MODULE,'git',side_effect=injected):
            with self.assertRaises(ValueError): MODULE.verify()
        with patch.dict(MODULE.PINS, {'src-tauri/src/bilingual_input.rs':'0'*64}):
            with self.assertRaises(ValueError): MODULE.verify()
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
        self.assertIn("needs.language-patch.result == 'success'",source)
        self.assertIn('Only the exact main release commit',source)
        self.assertIn('Release already exists; no files were overwritten.',source)
        self.assertIn('release remains a draft.',source)
    def test_ci_only_skips_full_jobs_after_successful_source_guard(self):
        source=(ROOT/'.github/workflows/ci.yml').read_text()
        self.assertEqual(source.count("if: needs.validation-mode.outputs.mode != 'language-routing-patch-v1'"),6)
        self.assertIn('cargo test --manifest-path tests/language-routing-patch/Cargo.toml --locked',source)
        self.assertIn("ref: ${{ github.event.pull_request.head.sha || github.sha }}",source)

if __name__ == '__main__': unittest.main()
