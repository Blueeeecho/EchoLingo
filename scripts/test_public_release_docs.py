"""Keep current public downloads aligned with the project release version."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("public_docs", Path(__file__).with_name("check-public-release-docs.py"))
docs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(docs)


class PublicReleaseDocs(unittest.TestCase):
    def document(self):
        version = "0.2.16"
        base = docs.REPOSITORY
        return "Prerelease\n" + "\n".join([
            f"{base}/releases/tag/{version}", f"{base}/tree/{version}",
            *(f"{base}/releases/download/{version}/{name}" for name in (
                f"EchoLingo_{version}_windows_x64-unpack.zip",
                f"EchoLingo_{version}_windows_x64-setup.exe",
                f"EchoLingo_{version}_macos_arm64.dmg",
                "SHA256SUMS.txt", "RELEASE-MANIFEST.json")),
        ])

    def test_current_readmes_match_project_version(self):
        for name in ("README.md", "README.en.md"):
            with self.subTest(name=name):
                docs.validate_document((docs.ROOT / name).read_text(encoding="utf-8"), docs.current_version())

    def test_current_links_and_previous_release_notes_are_valid(self):
        docs.validate_document(self.document() + f"\n{docs.REPOSITORY}/releases/tag/0.2.15", "0.2.16")

    def test_a_version_bump_requires_download_documentation_update(self):
        with self.assertRaisesRegex(ValueError, "Missing current release links"):
            docs.validate_document(self.document(), "0.2.17")

    def test_stale_download_is_rejected_even_if_current_download_is_present(self):
        with self.assertRaisesRegex(ValueError, "Outdated download links"):
            docs.validate_document(self.document() + f"\n{docs.REPOSITORY}/releases/download/0.2.15/old.zip", "0.2.16")

    def test_stable_latest_link_cannot_hide_the_prerelease(self):
        with self.assertRaisesRegex(ValueError, "stable Latest"):
            docs.validate_document(self.document() + f"\n{docs.REPOSITORY}/releases/latest", "0.2.16")

    def test_prerelease_label_is_required(self):
        with self.assertRaisesRegex(ValueError, "disclose prerelease"):
            docs.validate_document(self.document().replace("Prerelease", ""), "0.2.16")

if __name__ == "__main__":
    unittest.main()
