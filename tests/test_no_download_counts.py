"""Keep download links independent of public download-count requests."""
import unittest
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class PageResources(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scripts = []
        self.policy = ""

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "script" and "src" in attrs:
            self.scripts.append(attrs["src"])
        if tag == "meta" and attrs.get("http-equiv") == "Content-Security-Policy":
            self.policy = attrs["content"]


class NoDownloadCountsTest(unittest.TestCase):
    def test_counter_markup_removed_in_both_languages(self):
        source = (ROOT / "index.html").read_text(encoding="utf-8")
        for marker in ("download-stats", "data-download-count", "data-download-status",
                       "累计应用包下载", "下载量", "Total app downloads",
                       "Every download means a little more support"):
            with self.subTest(marker=marker):
                self.assertNotIn(marker, source)

    def test_only_existing_local_ui_scripts_are_loaded(self):
        page = PageResources()
        page.feed((ROOT / "index.html").read_text(encoding="utf-8"))
        self.assertEqual(page.scripts, ["./lang.js", "./app.js"])
        for script in page.scripts:
            self.assertTrue((ROOT / script).is_file())
        self.assertIn("default-src 'none'", page.policy)
        self.assertNotIn("api.github.com", page.policy)
        self.assertFalse((ROOT / "downloads.js").exists())

    def test_no_counter_css_or_stale_api_privacy_claim(self):
        self.assertNotIn("download-stats", (ROOT / "styles.css").read_text(encoding="utf-8"))
        privacy = (ROOT / "privacy.html").read_text(encoding="utf-8")
        for marker in ("下载次数", "汇总下载量", "GitHub 公开 API"):
            with self.subTest(marker=marker):
                self.assertNotIn(marker, privacy)
        self.assertIn("GitHub Pages 数据收集说明", privacy)


if __name__ == "__main__":
    unittest.main()
