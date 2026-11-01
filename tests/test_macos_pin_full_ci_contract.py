"""The full PR lane must execute the existing real Mac pin lifecycle too."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MacPinFullCIContract(unittest.TestCase):
    def test_full_ci_and_release_use_the_same_actual_pin_gate(self):
        for workflow in ('ci.yml', 'release-checks.yml'):
            source = (ROOT / '.github/workflows' / workflow).read_text()
            desktop = source.split('  desktop:\n', 1)[1]
            start = desktop.index('      - name: Build same-source isolated Mac debug pin host\n')
            end = desktop.index('      - name:', desktop.index('python3 scripts/verify-native-pin-release-absence.py', start))
            gate = desktop[start:end]
            self.assertIn("if: runner.os == 'macOS'", gate)
            self.assertIn('npm run tauri -- build --debug --no-bundle -- --locked', gate)
            self.assertIn('bash tests/macos-pin-native-smoke.sh "$PWD/src-tauri/target/debug/echolingo"', gate)
            self.assertIn('"$PWD/src-tauri/target/release/bundle/macos/EchoLingo.app/Contents/MacOS/echolingo"', gate)
            self.assertIn('python3 scripts/verify-native-pin-release-absence.py', gate)
            self.assertIn('set -euo pipefail', gate)
            self.assertNotIn('continue-on-error:', gate)
            self.assertNotIn('|| true', gate)
            self.assertLess(desktop.index('- name: Build desktop installer'), start)

    def test_full_ci_keeps_pin_failure_evidence(self):
        source = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn("if: always() && runner.os == 'macOS'", source)
        self.assertIn('${{ runner.temp }}/ci-native-pin-smoke', source)
        self.assertIn('${{ runner.temp }}/ci-native-pin-absence.json', source)


if __name__ == '__main__':
    unittest.main()
