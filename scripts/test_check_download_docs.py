import copy
import importlib.util
import os
import subprocess
import textwrap
import tempfile
import unittest
from pathlib import Path

P = Path(__file__).with_name("check-download-docs.py")
spec = importlib.util.spec_from_file_location("check_download_docs", P)
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)


class ScopeTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.net")
        for path in docs.DOCS | {"src/other"}:
            file = self.root / path
            file.parent.mkdir(exist_ok=True)
            file.write_text("base\n")
        self.base = self.commit()

    def git(self, *args):
        return docs.git(*args, root=self.root).decode().strip()

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-qm", "Fixture")
        return self.git("rev-parse", "HEAD")

    def changed(self, path):
        (self.root / path).write_text("updated\n")

    def scope(self, head, base=None):
        return docs.is_docs_only(self.base if base is None else base, head, self.root)

    def test_regular_readme_change_or_version_sync_is_docs_only(self):
        self.changed("README.md")
        head = self.commit()
        self.assertTrue(self.scope(head))
        self.changed(docs.VERSION_FILE)
        self.changed("README.en.md")
        self.assertTrue(self.scope(self.commit()))

    def test_empty_missing_forged_divergent_or_wrong_checkout_never_narrows(self):
        self.assertFalse(self.scope(self.base))
        self.changed("README.md")
        head = self.commit()
        for bad in ("0" * 40, "a" * 40, "HEAD", "", "--output=/tmp/no"):
            self.assertFalse(self.scope(head, bad))
        self.assertFalse(self.scope(self.base, head))
        self.git("checkout", "--detach", self.base)
        self.assertFalse(self.scope(head))
        self.changed("README.en.md")
        self.assertFalse(self.scope(self.commit(), head))

    def test_mixed_code_and_docs_never_narrow(self):
        self.changed("README.md")
        self.changed("src/other")
        self.assertFalse(self.scope(self.commit()))

    def test_move_delete_add_and_mode_changes_never_narrow(self):
        readme = self.root / "README.md"
        readme.rename(self.root / "notes.md")
        renamed = self.commit()
        self.assertFalse(self.scope(renamed))
        (self.root / "notes.md").unlink()
        readme.write_text("new\n")
        added = self.commit()
        self.assertFalse(self.scope(added, renamed))
        readme.chmod(0o755)
        executable = self.commit()
        self.assertFalse(self.scope(executable, added))
        readme.unlink()
        readme.symlink_to("README.en.md")
        self.assertFalse(self.scope(self.commit(), executable))


    def run_workflow_selector(self, base, head, *, event="pull_request"):
        source = (P.parents[1] / ".github/workflows/ci.yml").read_text()
        selector = source.split("          # Require a complete, append-only Git history", 1)[1]
        selector = textwrap.dedent("          # Require a complete, append-only Git history" +
                                   selector.split("          # This fixed post-release documentation patch", 1)[0])
        output = self.root / "route"
        output.unlink(missing_ok=True)
        subprocess.run(["bash", "-eu", "-c", selector], cwd=self.root, check=True, env={
            **os.environ, "CI_BEFORE": base, "CI_HEAD": head, "CI_EVENT": event,
            "CI_REF": "refs/heads/main" if event == "push" else "refs/pull/1/merge",
            "PR_BASE": "main", "GITHUB_OUTPUT": str(output),
        })
        return output.read_text() if output.exists() else None

    def test_workflow_uses_only_base_policy_and_bootstrap_falls_back(self):
        missing_policy = self.base
        self.changed("README.md")
        self.assertIsNone(self.run_workflow_selector(missing_policy, self.commit()))
        (self.root / "scripts").mkdir()
        classifier = self.root / "scripts/check-download-docs.py"
        classifier.write_bytes(P.read_bytes())
        base = self.commit()
        self.changed("README.en.md")
        docs_head = self.commit()
        self.assertEqual(self.run_workflow_selector(base, docs_head), "mode=download-docs\n")
        (self.root / "route").unlink()
        self.assertEqual(self.run_workflow_selector(base, docs_head, event="push"), "mode=download-docs\n")
        (self.root / "route").unlink()
        self.assertIsNone(self.run_workflow_selector(base, docs_head, event="workflow_dispatch"))
        # A candidate classifier returning success on arbitrary changes must
        # not be invoked by the workflow before the scope has been proved.
        classifier.write_text("raise SystemExit(0)\n")
        mixed_head = self.commit()
        self.assertIsNone(self.run_workflow_selector(base, mixed_head))
        self.git("checkout", "--detach", docs_head)
        # Isolated Python must not import a stdlib shadow from the PR checkout.
        (self.root / "argparse.py").write_text("raise SystemExit(0)\n")
        self.assertIsNone(self.run_workflow_selector(base, self.commit()))


class PublishedDocsTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "docs").mkdir()
        self.version = "0.2.24"
        (self.root / docs.VERSION_FILE).write_text(self.version + "\n")
        self.tag = f"{docs.URL}/releases/tag/{self.version}"
        self.sources = f"{docs.URL}/tree/{self.version}"
        self.assets = {
            name: f"{docs.URL}/releases/download/{self.version}/{name}"
            for name in docs.asset_names(self.version)
        }
        self.release = {"tag_name": self.version, "published_at": "2026-11-21T00:00:00Z",
                        "draft": False, "prerelease": True, "html_url": self.tag,
                        "assets": [{"name": name, "browser_download_url": url,
                                    "size": 1, "state": "uploaded"} for name, url in self.assets.items()]}
        for name, marker in docs.READMES.items():
            content = "\n".join([marker, self.tag, self.sources, *self.assets.values()])
            (self.root / name).write_text(content, encoding="utf-8")

    def test_both_readmes_match_all_downloads_and_canonical_source(self):
        self.assertEqual(docs.validate_readmes(self.root), self.version)
        docs.verify_publication(self.version, self.release)

    def test_stale_missing_floating_or_extra_links_and_old_labels_fail(self):
        path = self.root / "README.en.md"
        original = path.read_text()
        for changed in (original.replace(self.version, "0.2.23"),
                        original.replace(self.sources, ""),
                        original + "\n" + f"{docs.URL}/releases/latest",
                        original + "\n" + f"{docs.URL}/releases/tag/0.2.23",
                        original + "\nDownload 0.2.23"):
            with self.subTest(text=changed):
                path.write_text(changed)
                with self.assertRaises(ValueError):
                    docs.validate_readmes(self.root)

    def test_draft_stable_wrong_or_incomplete_release_metadata_fails(self):
        for key, value in (("draft", True), ("prerelease", False), ("published_at", None),
                           ("tag_name", "0.2.23"), ("html_url", self.sources), ("assets", [])):
            with self.subTest(field=key), self.assertRaises(ValueError):
                docs.verify_publication(self.version, {**self.release, key: value})
        incomplete = copy.deepcopy(self.release)
        incomplete["assets"][0]["state"] = "starter"
        with self.assertRaises(ValueError):
            docs.verify_publication(self.version, incomplete)
        duplicate = copy.deepcopy(self.release)
        duplicate["assets"][0] = duplicate["assets"][1]
        with self.assertRaises(ValueError):
            docs.verify_publication(self.version, duplicate)

    def test_latest_prerelease_uses_numeric_order_and_ignores_drafts(self):
        older = {**self.release, "tag_name": "0.2.9"}
        future_draft = {**self.release, "tag_name": "0.2.25", "draft": True}
        future_stable = {**self.release, "tag_name": "0.2.25", "prerelease": False}
        self.assertEqual(
            docs.latest_prerelease([older, future_draft, self.release, future_stable]), self.release
        )
        with self.assertRaises(ValueError):
            docs.verify_publication(older["tag_name"], docs.latest_prerelease([older, self.release]))
