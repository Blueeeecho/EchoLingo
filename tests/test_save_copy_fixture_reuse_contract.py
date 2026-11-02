"""The new diagnostic route reuses only fixed reviewed bytes and one F1 run."""
from pathlib import Path
import ast
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / '.github/workflows/f1-fixture-reuse.yml').read_text()
NEW = SOURCE.split('  windows-save-copy-fixture-reuse:\n', 1)[1].split('  macos-screenshot-native-probe:\n', 1)[0]

class SaveCopyReuseContract(unittest.TestCase):
    def test_exact_route_leaves_old_jobs_on_old_branch(self):
        self.assertIn("if: github.ref == 'refs/heads/diagnostics/screenshot-save-copy-fixture'", NEW)
        self.assertEqual(SOURCE.count("if: github.ref == 'refs/heads/diagnostics/024-f1-fixture-reuse'"), 2)
        for forbidden in ('workflow_dispatch:', 'inputs.', 'cargo build', 'tauri build', 'npm ci',
                          '-InstalledPackage', 'InstallerDirectory', 'continue-on-error:', 'macos-latest'):
            self.assertNotIn(forbidden, NEW)
        self.assertIn("$allowed = '^(tests/|\\.github/workflows/f1-fixture-reuse\\.yml$)'", NEW)
        self.assertIn('git diff --name-only $base HEAD', NEW)
        self.assertIn('if ($path -notmatch $allowed) { throw', NEW)

    def test_fixed_artifact_and_members_not_dynamic_inputs(self):
        for value in ('4941d285a06df2674bd36940da996a0f17367493', '41397150457', '13120925228',
                      '4190464', '4bce0c2ded82bb5862ee147759788284ac63d641eecf53ef9c0587050ee0cf11',
                      '8430080', 'd154e5bc9888b5859317a2bd198a2859f7e39098f6d2ac5ca5ed1781d5ea1c3f',
                      '472064', 'fee4dee2fd27e34ec7f63e3be0248625cfd04c391f466c56103b7014e3544c08'):
            self.assertIn(value, NEW)
        for guard in ('artifact.expired', 'artifact.size_in_bytes !== expected.size',
                      'artifact.workflow_run?.head_sha !== source', 'run.repository.id !== 1432139657',
                      'len(matches) != 1', 'kind not in (0, stat.S_IFREG)', 'item.flag_bits & 1',
                      'stream.read(size + 1)', 'len(data) != size', 'app.count(helper) != 1',
                      'app.find(helper) != 5983805', ".open('xb')"):
            self.assertIn(guard, NEW)
        self.assertNotIn('extractall(', NEW)
        self.assertNotIn('Expand-Archive', NEW)
        self.assertIn("if: always() && steps.save_copy_extract.outcome == 'success'", NEW)
        self.assertIn("postRunByteIdentityVerified", NEW)

    def test_once_original_fixture_and_strict_failure_propagation(self):
        self.assertEqual(NEW.count('-File tests/windows-application-smoke.ps1'), 1)
        self.assertIn('-DefaultCapture -NativeCapturePath $helper -ScreenshotEditorTests', NEW)
        self.assertIn('python scripts/verify_screenshot_editor_report.py $report --application $app', NEW)
        self.assertLess(NEW.index('$output | Out-File $report'), NEW.index('python scripts/verify_screenshot_editor_report.py'))
        self.assertIn('if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }', NEW)
        self.assertIn('if ($fixtureExit -ne 0) { exit $fixtureExit }', NEW)
        self.assertIn('Preserve the first same-byte F1 result including failures\n        if: always()', NEW)
        self.assertIn('timeout-minutes: 8', NEW)

    def test_inline_python_syntax(self):
        blocks = NEW.split('        shell: python\n        run: |\n')[1:]
        self.assertEqual(len(blocks), 2)
        for block in blocks:
            lines = []
            for line in block.splitlines():
                if line and not line.startswith('          '):
                    break
                lines.append(line[10:])
            ast.parse('\n'.join(lines))

if __name__ == '__main__': unittest.main()
