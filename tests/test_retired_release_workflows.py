"""Retired desktop releases must not rebuild on an ordinary package.json push."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "retired_release_workflows", ROOT / "scripts" / "retired_release_workflows.py"
)
retired = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(retired)


class RetiredReleaseWorkflows(unittest.TestCase):
    def test_shipped_workflows_are_manual_and_current_release_still_pushes(self):
        for name in retired.RETIRED:
            with self.subTest(name=name):
                retired.assert_manual_only(self, name)
        current = (ROOT / retired.CURRENT).read_text()
        self.assertIn("\n  workflow_dispatch:\n", current)
        self.assertIn("\n  push:\n", current)
        self.assertIn("package.json", current)
        self.assertIn("contents: write", current)
