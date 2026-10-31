"""Focused native diagnostics retain the normal isolated runtime gates exactly."""
import hashlib
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / '.github/workflows/capture-timing-native.yml').read_text()


class CaptureTimingWorkflowContract(unittest.TestCase):
    def test_fixed_branch_and_read_only_scope(self):
        self.assertIn('branches: [diagnostics/024-capture-timing-native]', WORKFLOW)
        self.assertIn('contents: read', WORKFLOW)
        self.assertIn('persist-credentials: false', WORKFLOW)
        self.assertIn("head == os.environ['GITHUB_SHA']", WORKFLOW)
        for forbidden in ('pull_request:', 'workflow_dispatch:', ': write', 'continue-on-error:',
                          'npm ci', 'tauri build', 'offline-engine/build.py', 'git push', 'createRelease'):
            self.assertNotIn(forbidden, WORKFLOW)

    def test_every_original_runtime_step_is_byte_identical(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        expected = ci.split('  windows-rust-capture-candidate:\n', 1)[1].split('  macos-native-frame-probe:\n', 1)[0]
        actual = WORKFLOW.split('  windows-rust-capture-candidate:\n', 1)[1]
        start = actual.index('      - name: Verify the reviewed native diagnostic source inputs\n')
        end = actual.index('      - uses: dtolnay/rust-toolchain@stable\n', start)
        actual = actual[:start] + actual[end:]
        actual = actual.split('      - name: Preserve exact source provenance\n', 1)[0]
        self.assertEqual(actual, expected)

    def test_pins_cover_all_native_and_windows_fixture_inputs(self):
        pins = json.loads((ROOT / 'tests/fixtures/capture-timing-source-pins.json').read_text())
        globs = ['src-tauri/src/windows*.rs', 'src-tauri/src/platform.rs', 'src-tauri/native/windows.ps1',
                 'src-tauri/windows_launcher.rs', 'src-tauri/native-capture/*',
                 'tests/windows*.rs', 'tests/windows*.ps1', 'scripts/build-windows-native-helper.ps1',
                 'scripts/verify-native-capture-report.py', 'scripts/verify-screenshot-window-report.py']
        names = subprocess.check_output(['git', 'ls-files', *globs], cwd=ROOT, text=True).splitlines()
        self.assertEqual(set(pins['files']), set(names))
        self.assertEqual(pins['formatVersion'], 1)
        for name, expected in pins['files'].items():
            self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), expected, name)

    def test_strict_same_runner_and_failure_evidence_remain(self):
        self.assertIn('windows-native-capture-smoke.ps1', WORKFLOW)
        self.assertIn('windows-native-capture-ab.ps1', WORKFLOW)
        self.assertIn('verify-screenshot-window-report.py', WORKFLOW)
        self.assertIn('native-capture-paired-evidence', WORKFLOW)
        self.assertIn('cargo build --manifest-path src-tauri/native-capture/Cargo.toml --release --locked', WORKFLOW)
        self.assertIn('if: always()', WORKFLOW)
        self.assertIn('not full application, installer, or release acceptance', WORKFLOW)


if __name__ == '__main__':
    unittest.main()
