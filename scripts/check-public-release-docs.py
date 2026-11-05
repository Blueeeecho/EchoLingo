#!/usr/bin/env python3
"""Check current README download links without changing release assets."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/Blueeeecho/EchoLingo"


def current_version():
    return json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]


def validate_document(text, version):
    prefix = f"{REPOSITORY}/releases/download/{version}/"
    expected = {prefix + name for name in (
        f"EchoLingo_{version}_windows_x64-unpack.zip",
        f"EchoLingo_{version}_windows_x64-setup.exe",
        f"EchoLingo_{version}_macos_arm64.dmg",
        "SHA256SUMS.txt", "RELEASE-MANIFEST.json",
    )}
    expected |= {f"{REPOSITORY}/releases/tag/{version}", f"{REPOSITORY}/tree/{version}"}
    urls = set(re.findall(r"https://github\.com/Blueeeecho/EchoLingo/[^\s\"'<>)]*", text))
    missing = expected - urls
    if missing:
        raise ValueError("Missing current release links: " + ", ".join(sorted(missing)))
    stale = {url for url in urls if "/releases/download/" in url and not url.startswith(prefix)}
    if stale:
        raise ValueError("Outdated download links: " + ", ".join(sorted(stale)))
    if any("/releases/latest" in url for url in urls):
        raise ValueError("Prerelease downloads must not use the stable Latest endpoint")
    if not any(word in text.lower() for word in ("预发布", "prerelease", "pre-release")):
        raise ValueError("The public download documentation must disclose prerelease status")


def main():
    version = current_version()
    for name in ("README.md", "README.en.md"):
        validate_document((ROOT / name).read_text(encoding="utf-8"), version)
    print(json.dumps({"version": version, "documents": ["README.md", "README.en.md"], "ok": True}))


if __name__ == "__main__":
    main()
