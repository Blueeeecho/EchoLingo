#!/usr/bin/env python3
"""Check the static website's release links without network access or dependencies."""
import argparse
import re
from html.parser import HTMLParser
from pathlib import Path

REPO = "https://github.com/Blueeeecho/EchoLingo"


class Homepage(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = []
        self.text = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])
        if "id" in attrs:
            self.ids.append(attrs["id"])

    def handle_data(self, data):
        self.text.append(data)


def validate(source, version, previous):
    for value in (version, previous):
        if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[\w.-]+)?", value):
            raise ValueError(f"Invalid version: {value}")
    page = Homepage()
    page.feed(source)
    errors = []
    expected_downloads = {
        f"{REPO}/releases/download/{version}/{name}"
        for name in (
            f"EchoLingo_{version}_windows_x64-unpack.zip",
            f"EchoLingo_{version}_windows_x64-setup.exe",
            f"EchoLingo_{version}_macos_arm64.dmg",
            "SHA256SUMS.txt",
            "RELEASE-MANIFEST.json",
        )
    }
    actual_downloads = {url for url in page.links if "/releases/download/" in url}
    if actual_downloads != expected_downloads:
        errors.append(f"Download links differ: {sorted(actual_downloads ^ expected_downloads)}")
    expected_notes = {f"{REPO}/releases/tag/{tag}" for tag in (version, previous)}
    actual_notes = {url for url in page.links if "/releases/tag/" in url}
    if actual_notes != expected_notes:
        errors.append("Release notes must link to the current and previous previews")
    if any("/releases/latest" in url for url in page.links):
        errors.append("A prerelease must not use the stable Latest URL")
    text = " ".join(page.text)
    for required in (
        f"Windows / macOS · {version} 内测版",
        f"Windows / macOS · {version} test build",
        f"下载 {version} 内测版",
        f"Download {version} test build",
        f"{version} 更新：",
        f"New in {version}:",
        f"{previous} 安装包与版本说明",
        f"{previous} installers and release notes",
        "这是内测预发布版本，不是稳定版",
        "This is an internal prerelease, not a stable",
        "未经 Apple 公证",
        "not notarized by Apple",
        "Apple 翻译策略自检也不等于调用真实引擎",
        "Apple translation-policy checks do not call the real engine",
    ):
        if required not in text:
            errors.append(f"Missing release text: {required}")
    if set(re.findall(r"\b\d+\.\d+\.\d+\b", text)) != {version, previous}:
        errors.append("Visible version labels must name only the current and previous previews")
    if len(page.ids) != len(set(page.ids)):
        errors.append("Duplicate HTML IDs")
    for url in page.links:
        if url.startswith("#") and url[1:] not in page.ids:
            errors.append(f"Missing anchor target: {url}")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--previous", required=True)
    parser.add_argument("--html", type=Path, default=Path(__file__).resolve().parents[1] / "index.html")
    args = parser.parse_args()
    errors = validate(args.html.read_text(encoding="utf-8"), args.version, args.previous)
    if errors:
        parser.exit(1, "\n".join(errors) + "\n")
    print(f"Release {args.version} website links and bilingual prerelease labels passed")
