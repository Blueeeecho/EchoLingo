import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_release", ROOT / "scripts/check-release.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseLinksTest(unittest.TestCase):
    source = (ROOT / "index.html").read_text(encoding="utf-8")

    def check(self, source):
        return module.validate(source, "0.2.21")

    def test_current_page(self):
        self.assertEqual(self.check(self.source), [])

    def test_stale_package_rejected(self):
        self.assertTrue(self.check(self.source.replace(
            "/download/0.2.21/EchoLingo_0.2.21_windows_x64-setup.exe",
            "/download/0.2.18/EchoLingo_0.2.18_windows_x64-setup.exe")))

    def test_stale_label_rejected(self):
        self.assertTrue(self.check(self.source.replace(
            "Download 0.2.21 test build", "Download 0.2.14 test build")))

    def test_stable_latest_rejected(self):
        self.assertTrue(self.check(self.source.replace(
            "/releases/tag/0.2.21", "/releases/latest")))

    def test_missing_prerelease_warning_rejected(self):
        self.assertTrue(self.check(self.source.replace(
            "This is an internal prerelease, not a stable", "This is a stable")))

    def test_missing_verification_limits_rejected(self):
        self.assertTrue(self.check(self.source.replace(
            "Apple translation-policy checks do not call the real engine", "")))

    def test_stale_previous_release_rejected(self):
        self.assertTrue(self.check(self.source.replace(
            "/releases/tag/0.2.21", "/releases/tag/0.2.18")))

    def test_archive_link_rejected(self):
        self.assertTrue(self.check(self.source + f'<a href="{module.REPO}/releases">Archive</a>'))

    def test_missing_checksum_rejected(self):
        self.assertTrue(self.check(self.source.replace("SHA256SUMS.txt", "checksums.txt")))


if __name__ == "__main__":
    unittest.main()
