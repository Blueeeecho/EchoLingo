import pathlib
import subprocess
import sys
import tempfile
import unittest


CHECK = pathlib.Path(__file__).resolve().parents[1] / "scripts/check-repository.py"


class RepositoryHygiene(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = pathlib.Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)

    def write(self, path, text, stage=True):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        if stage:
            subprocess.run(["git", "add", "--", path], cwd=self.repo, check=True)

    def check(self):
        return subprocess.run(
            [sys.executable, str(CHECK), "--repo", str(self.repo)],
            capture_output=True, text=True, check=False,
        )

    def test_local_notes_are_not_scanned(self):
        self.write("README.md", "Public instructions")
        self.write(".codex-plans/local/plan.md", "Local notes", stage=False)
        self.write("AGENTS.md", "Local handoff", stage=False)
        self.assertEqual(self.check().returncode, 0)

    def test_staged_internal_files_are_rejected(self):
        for path in [".codex-plans/plan.md", "AGENTS.md", "docs/validation/run.json"]:
            self.write(path, "Internal")
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn(".codex-plans/plan.md", result.stdout)
        self.assertIn("AGENTS.md", result.stdout)
        self.assertIn("docs/validation/run.json", result.stdout)

    def test_staged_data_cannot_be_hidden_by_working_edit(self):
        secret = "sk-" + "A" * 48
        user_path = "/" + "Users/fixture-owner/private/"
        self.write("src/example.txt", secret + "\n" + user_path)
        self.write("src/example.txt", "Clean working copy", stage=False)
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("credential-like value", result.stdout)
        self.assertIn("local user path", result.stdout)
        self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertNotIn(user_path, result.stdout + result.stderr)

    def test_public_docs_and_licenses_remain_allowed(self):
        for path in ["README.md", "docs/build.md", "docs/privacy.md", "LICENSE",
                     "LICENSING.md", "resources/offline-translation/licenses/MPL-2.0.txt"]:
            self.write(path, "Public material")
        self.assertEqual(self.check().returncode, 0)


if __name__ == "__main__":
    unittest.main()
