#!/usr/bin/env python3
"""Fail closed unless a docs delta and the documented public assets are exact."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPO = "Blueeeecho/EchoLingo"
URL = f"https://github.com/{REPO}"
READMES = {"README.md": "预发布", "README.en.md": "prerelease"}
VERSION_FILE = "docs/desktop-download-version.txt"
DOCS = frozenset((*READMES, VERSION_FILE))
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
OID = r"[0-9a-f]{40}"


def git(*args, root=ROOT):
    return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.DEVNULL)


def is_docs_only(before, head, root=ROOT):
    if not all(re.fullmatch(OID, ref) and ref != "0" * 40 for ref in (before, head)):
        return False
    try:
        if git("rev-parse", "HEAD", root=root).decode().strip() != head:
            return False
        git("merge-base", "--is-ancestor", before, head, root=root)
        fields = git("diff", "--raw", "--no-renames", "--abbrev=40", "-z",
                     before, head, "--", root=root).decode("utf-8").split("\0")
        if fields[-1] != "" or len(fields) < 3 or len(fields) % 2 != 1:
            return False
        for i in range(0, len(fields) - 1, 2):
            if fields[i + 1] not in DOCS or not re.fullmatch(
                rf":100644 100644 {OID} {OID} M", fields[i]
            ):
                return False
        return True
    except (OSError, subprocess.CalledProcessError, UnicodeError):
        return False


def asset_names(version):
    return frozenset((f"EchoLingo_{version}_windows_x64-unpack.zip",
                      f"EchoLingo_{version}_windows_x64-setup.exe",
                      f"EchoLingo_{version}_macos_arm64.dmg",
                      "SHA256SUMS.txt", "RELEASE-MANIFEST.json"))


def validate_readmes(root=ROOT):
    raw = (root / VERSION_FILE).read_text(encoding="utf-8")
    if not re.fullmatch(VERSION + r"\n", raw):
        raise ValueError("Invalid documented desktop download version")
    version = raw.strip()
    expected_assets = {f"{URL}/releases/download/{version}/{name}" for name in asset_names(version)}
    expected_links = expected_assets | {f"{URL}/releases/tag/{version}", f"{URL}/tree/{version}"}
    for file, prerelease in READMES.items():
        text = (root / file).read_text(encoding="utf-8")
        targets = set(re.findall(re.escape(URL) + r'/[^\s"<>)]*', text))
        release_links = {link for link in targets if link.startswith(f"{URL}/releases")}
        source_tag_links = {link for link in targets if re.fullmatch(re.escape(URL) + "/tree/" + VERSION, link)}
        seen_versions = set(re.findall(r"(?<![\d.])" + VERSION + r"(?![\d.])", text))
        if (release_links | source_tag_links != expected_links or prerelease not in text
                or seen_versions != {version}):
            raise ValueError(f"{file} has missing, old, or unexpected desktop release links")
        if "/releases/latest" in text:
            raise ValueError(f"{file} links to generic latest instead of the precise prerelease")
    return version


def verify_publication(version, release):
    if (release.get("tag_name") != version or release.get("draft") is not False
            or release.get("prerelease") is not True or not release.get("published_at")
            or release.get("html_url") != f"{URL}/releases/tag/{version}"):
        raise ValueError("Documented version is not the published desktop prerelease")
    required = asset_names(version)
    matched = [asset for asset in release.get("assets", []) if asset.get("name") in required]
    if len(matched) != len(required) or {item["name"] for item in matched} != required or any(
        asset.get("state") != "uploaded" or not asset.get("size", 0) > 0
        or asset.get("browser_download_url") != f"{URL}/releases/download/{version}/{asset['name']}"
        for asset in matched
    ):
        raise ValueError("Documented prerelease is missing a verified download target")


def latest_prerelease(releases):
    eligible = [release for release in releases if release.get("draft") is False
                and release.get("prerelease") is True and release.get("published_at")
                and re.fullmatch(VERSION, release.get("tag_name", ""))]
    return max(eligible, key=lambda release: tuple(map(int, release["tag_name"].split("."))), default={})


def fetch_publication(version):
    """Resolve the highest published numeric prerelease via GitHub, not /latest."""
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "EchoLingo-Docs-CI"}
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    releases = []
    page = 1
    while True:
        request = urllib.request.Request(
            f"https://api.github.com/repos/{REPO}/releases?per_page=100&page={page}", headers=headers
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            releases.extend(json.load(response))
            if 'rel="next"' not in response.headers.get("Link", ""):
                break
        page += 1
    verify_publication(version, latest_prerelease(releases))
    try:
        package = json.loads(git("show", f"refs/tags/{version}:package.json"))
    except (subprocess.CalledProcessError, OSError) as exc:
        raise ValueError("Documented release has no locally fetched source tag") from exc
    if package.get("version") != version:
        raise ValueError("Documented version does not match its tagged source package")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", nargs=2, metavar=("BEFORE", "HEAD"))
    parser.add_argument("--published", action="store_true")
    args = parser.parse_args()
    if args.scope:
        # Scope code can be read from a trusted event-base SHA and run via stdin.
        raise SystemExit(0 if is_docs_only(*args.scope, root=Path.cwd()) else 1)
    try:
        version = validate_readmes()
        if args.published:
            fetch_publication(version)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Desktop download documentation check failed: {exc}\n")
    print(f"Desktop download document checks passed for {version}")
