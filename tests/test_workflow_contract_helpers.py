"""Routing normalization must never hide changes to acceptance steps."""
import unittest
from workflow_contract_helpers import executable_job, assert_pull_request_gate


class WorkflowContractHelpers(unittest.TestCase):
    def test_only_known_conservative_top_level_routes_are_ignored(self):
        body = "    name: Probe\n    steps:\n      - if: always()\n        run: verify\n"
        routing = "    needs: validation-mode\n    if: needs.validation-mode.outputs.mode != 'language-routing-patch-v1' && needs.validation-mode.outputs.mode != 'screenshot-pins'\n"
        self.assertEqual(executable_job(routing + body), executable_job(body))
        for mode in ['automatic-direction', 'routing-release', 'windows-unpack']:
            self.assertEqual(executable_job(f"    if: needs.validation-mode.outputs.mode != '{mode}'\n" + body), executable_job(body))
        self.assertNotEqual(executable_job(body), executable_job(body.replace('always()', 'false')))
        self.assertNotEqual(executable_job(body), executable_job(body.replace('run: verify', 'continue-on-error: true\n        run: verify')))
        for condition in ['false', 'always()', "needs.validation-mode.outputs.mode != 'full'", "needs.validation-mode.outputs.mode != 'screenshot-pins' || true", "needs.validation-mode.outputs.mode == 'windows-unpack'", "needs.validation-mode.outputs.mode != 'windows-unpack' || true", "needs.validation-mode.outputs.mode != 'unreviewed-mode'"]:
            with self.assertRaises(AssertionError):
                executable_job(f'    if: {condition}\n' + body)

    def test_preparation_is_pr_only_even_with_scope_exclusions(self):
        assert_pull_request_gate(self, "    if: github.event_name == 'pull_request'\n")
        assert_pull_request_gate(self, "    if: needs.validation-mode.outputs.mode != 'language-routing-patch-v1' && github.event_name == 'pull_request'\n")
        for mode in ['automatic-direction', 'routing-release', 'windows-unpack']:
            assert_pull_request_gate(self, f"    if: needs.validation-mode.outputs.mode != '{mode}' && github.event_name == 'pull_request'\n")
        for condition in ["github.event_name == 'push'", "github.event_name == 'pull_request' || true", "false && github.event_name == 'pull_request'", "needs.validation-mode.outputs.mode != 'windows-unpack' || github.event_name == 'pull_request'", "needs.validation-mode.outputs.mode == 'windows-unpack' && github.event_name == 'pull_request'", "needs.validation-mode.outputs.mode != 'unreviewed-mode' && github.event_name == 'pull_request'"]:
            with self.assertRaises(AssertionError):
                assert_pull_request_gate(self, f'    if: {condition}\n')
