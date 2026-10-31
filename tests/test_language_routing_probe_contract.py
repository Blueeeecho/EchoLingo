"""The language dependency probe is synthetic and cannot publish or alter the app."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ProbeContract(unittest.TestCase):
    def test_fixed_scope_and_no_write_permissions(self):
        source = (ROOT/'.github/workflows/language-routing-probe.yml').read_text()
        self.assertIn('branches: [diagnostics/024-language-routing-probe]', source)
        self.assertIn('contents: read', source)
        self.assertIn('persist-credentials: false', source)
        self.assertIn('cargo run --manifest-path tests/language-routing-probe/Cargo.toml --locked', source)
        self.assertIn('set -euo pipefail', source)
        for forbidden in ('pull_request:', 'workflow_dispatch:', ': write', 'git push', 'tauri build', 'createRelease'):
            self.assertNotIn(forbidden, source)
    def test_official_dependency_exactly_pinned_and_corpus_is_static(self):
        self.assertIn('whatlang = "=0.18.0"', (ROOT/'tests/language-routing-probe/Cargo.toml').read_text())
        source = (ROOT/'tests/language-routing-probe/src/main.rs').read_text()
        for forbidden in ('std::env', 'std::fs', 'std::net', 'include_str!', 'stdin'):
            self.assertNotIn(forbidden, source)
        self.assertIn('i.confidence(), i.is_reliable()', source)
    def test_actual_module_and_app_lock_are_not_simulations(self):
        workflow = (ROOT/'.github/workflows/language-routing-probe.yml').read_text()
        self.assertIn('cargo update --manifest-path src-tauri/Cargo.toml --workspace', workflow)
        self.assertNotIn('cargo update --manifest-path src-tauri/Cargo.toml\n', workflow)
        self.assertIn('cargo metadata --manifest-path src-tauri/Cargo.toml --locked', workflow)
        self.assertIn('cargo test --manifest-path tests/language-routing-probe/Cargo.toml --locked', workflow)
        self.assertIn('app-baseline.Cargo.lock', workflow)
        self.assertIn('app-lock.patch', workflow)
        harness = (ROOT/'tests/language-routing-probe/src/main.rs').read_text()
        for module in ('bilingual_input', 'language_detection'):
            self.assertIn(f'#[path = "../../../src-tauri/src/{module}.rs"]', harness)
        self.assertIn('tokio = { version = "=1.54.1"', (ROOT/'tests/language-routing-probe/Cargo.toml').read_text())
if __name__ == '__main__': unittest.main()
