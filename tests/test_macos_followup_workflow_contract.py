"""Exact candidate routing; all other refs retain their previous selection."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MacFollowupRouting(unittest.TestCase):
    def route(self, head, base):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        scope = workflow.split('        run: |\n', 1)[1].split('\n  language-patch-targeted:', 1)[0]
        script = '\n'.join(line[10:] for line in scope.splitlines())
        with tempfile.NamedTemporaryFile() as output:
            env = dict(os.environ, PR_HEAD=head, PR_BASE=base, GITHUB_OUTPUT=output.name)
            subprocess.run(['bash', '-eu', '-c', script], cwd=ROOT, env=env, check=True, capture_output=True)
            return Path(output.name).read_text().strip()

    def test_only_exact_candidate_uses_mac_followup(self):
        self.assertEqual(self.route('fix/macos-screenshot-followup', 'main'), 'mode=macos-followup')
        for head, base in [('fix/macos-screenshot-followup', 'other'), ('other', 'main'), ('', '')]:
            self.assertEqual(self.route(head, base), 'mode=full')

    def test_original_pin_route_retained(self):
        self.assertEqual(self.route('feat/screenshot-pins', 'fix/025-macos-recovery-integration'), 'mode=screenshot-pins')

    def test_native_and_frontend_execution_retained(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn("fromJSON(needs.validation-mode.outputs.mode == 'macos-followup'", workflow)
        for command in ['bash tests/macos-native-self-test.sh', 'bash tests/macos-screenshot-overlay-host-fixture.sh', 'npm run check && npm test && npm run build', 'npm run test:ui']:
            self.assertIn(command, workflow)
        self.assertIn('--selection-policy-self-test', (ROOT / 'tests/macos-native-self-test.sh').read_text())
