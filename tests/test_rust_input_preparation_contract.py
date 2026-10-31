"""Generated CI inputs are review artifacts, never a substitute for exact-head tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RustInputPreparationContract(unittest.TestCase):
    def test_preparation_is_read_only_conservative_and_requires_committed_inputs(self):
        source = (ROOT / '.github/workflows/ci.yml').read_text()
        job = source.split('  rust-input-preparation:\n', 1)[1].split('  windows-rust-capture-candidate:\n', 1)[0]
        self.assertIn("if: github.event_name == 'pull_request'", job)
        self.assertIn('ref: ${{ github.event.pull_request.head.sha }}', job)
        self.assertIn('persist-credentials: false', job)
        self.assertIn('cargo update --manifest-path src-tauri/Cargo.toml --workspace', job)
        self.assertIn('cargo metadata --manifest-path src-tauri/Cargo.toml --locked', job)
        self.assertIn('git diff --exit-code -- src-tauri', job)
        self.assertIn('name: Rust-input-preparation', job)
        for forbidden in ['contents: write', 'git push', 'git commit ', 'generate-lockfile', '--recursive', 'continue-on-error: true']:
            self.assertNotIn(forbidden, job)
        for evidence in ['source.txt', 'toolchain.txt', 'manifests.sha256', 'generated.patch', 'generated.sha256']:
            self.assertIn(evidence, job)

    def test_normal_and_release_workflows_include_all_source_contracts(self):
        for name in ['ci.yml', 'release-checks.yml']:
            source = (ROOT / '.github/workflows' / name).read_text()
            self.assertIn("python3 -m unittest discover -s tests -p 'test_*.py' -v", source)


if __name__ == '__main__':
    unittest.main()
