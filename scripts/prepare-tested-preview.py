#!/usr/bin/env python3
"""Prepare the one authorized 0.2.2 preview from pinned, previously tested bytes.

No compilation occurs here. The normal release gates remain unchanged; the
manifest separately discloses the failed later validation of the same source tree.
"""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import stat
import tempfile
import zipfile


VERSION = "0.2.2"
SOURCE = "4ea25907fdaf4477f3aaf92b41973668b507f528"
SOURCE_TREE = "87825bd8b1bfdb304ca9e21857d5a09769327932"
BUILD_CHECKOUT = "8b8cfcf6abee1297f5ef220154a0a28fb18cb63c"
RUN = 41053405841
RUN_URL = f"https://github.com/Blueeeecho/EchoLingo/actions/runs/{RUN}"
LATER_SOURCE = "06b4f9820e20f15fdedf8d86e875505ff95b956d"
LATER_RUN = 41056149811
ARTIFACTS = (
    {"name": "EchoLingo-Windows", "id": 12976667329, "size": 75445810,
     "sha256": "cb6405255d570fc31dec7a125921518126dbb709960bc4361f24b51622e4a3cd"},
    {"name": "EchoLingo-macOS", "id": 12975917340, "size": 4916850,
     "sha256": "8e980f9c4ccf37b72cecd551205c1d822962d789391446bb357d876572d8ec47"},
    {"name": "EchoLingo-Windows-offline-evidence", "id": 12976667318, "size": 18088658,
     "sha256": "8a77e655aa802067c080473f7715a1e075317a79b97dfb87e5862f82687aae20"},
)
MAX_ENTRIES = 10000
MAX_MEMBER_BYTES = 256 * 1024 * 1024
MAX_TOTAL_BYTES = 512 * 1024 * 1024

SPEC = importlib.util.spec_from_file_location(
    "prepare_release_assets", Path(__file__).with_name("prepare-release-assets.py"))
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_members(archive):
    """Reject unsafe paths/types, aliases, collisions and excessive expansion."""
    members = archive.infolist()
    if not members or len(members) > MAX_ENTRIES:
        raise ValueError("Unsafe ZIP entry count")
    entries = {}
    total = 0
    for member in members:
        name = member.filename
        if (member.orig_filename != name or not name or name.startswith("/") or "\\" in name or ":" in name
                or any(ord(c) < 32 for c in name)):
            raise ValueError("Unsafe ZIP path")
        parts = name[:-1].split("/") if member.is_dir() else name.split("/")
        if any(part in {"", ".", ".."} for part in parts):
            raise ValueError("Unsafe ZIP path")
        key = "/".join(parts).casefold()
        if key in entries:
            raise ValueError("Duplicate ZIP path")
        mode = stat.S_IFMT(member.external_attr >> 16)
        if mode not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise ValueError("Unsafe ZIP file type (links are forbidden)")
        if mode and (mode == stat.S_IFDIR) != member.is_dir():
            raise ValueError("ZIP directory type mismatch")
        if member.flag_bits & 1 or member.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise ValueError("Unsupported ZIP encryption or compression")
        if member.file_size < 0 or member.file_size > MAX_MEMBER_BYTES:
            raise ValueError("ZIP member exceeds size limit")
        if member.is_dir() and member.file_size:
            raise ValueError("ZIP directory has unexpected data")
        total += member.file_size
        if total > MAX_TOTAL_BYTES:
            raise ValueError("ZIP exceeds total size limit")
        entries[key] = member.is_dir()
    for key in entries:
        parts = key.split("/")
        if any(entries.get("/".join(parts[:i])) is False for i in range(1, len(parts))):
            raise ValueError("ZIP file/directory path collision")
    return members


def extract_pinned(archive_path, destination, expected):
    archive_path, destination = Path(archive_path), Path(destination)
    if archive_path.is_symlink() or not archive_path.is_file():
        raise ValueError("Expected a regular pinned artifact archive")
    if archive_path.stat().st_size != expected["size"] or sha256(archive_path) != expected["sha256"]:
        raise ValueError("Pinned artifact size or digest mismatch")
    if destination.exists() or destination.is_symlink():
        raise ValueError("Extraction destination already exists")
    with zipfile.ZipFile(archive_path) as archive:
        members = validate_members(archive)
        destination.mkdir(parents=True)
        for member in members:
            target = destination.joinpath(*member.filename.rstrip("/").split("/"))
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            written = 0
            with archive.open(member) as source, target.open("xb") as output:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    written += len(chunk)
                    if written > member.file_size or written > MAX_MEMBER_BYTES:
                        raise ValueError("ZIP expanded data exceeds declared size")
                    output.write(chunk)
            if written != member.file_size:
                raise ValueError("ZIP expanded data size mismatch")


def prepare(archive_directory, output, publisher):
    if not re.fullmatch(r"[0-9a-f]{40}", publisher):
        raise ValueError("An exact publisher commit is required")
    archive_directory, output = Path(archive_directory), Path(output)
    if output.exists() or output.is_symlink():
        raise ValueError("Output already exists; never overwrite publication inputs")
    RELEASE.check_version()
    if RELEASE.VERSION != VERSION:
        raise ValueError("Only the authorized 0.2.2 release is allowed")
    with tempfile.TemporaryDirectory(prefix="echolingo-tested-preview-") as temporary:
        root = Path(temporary)
        artifacts, staged = root / "artifacts", root / "prepared"
        for artifact in ARTIFACTS:
            extract_pinned(archive_directory / (artifact["name"] + ".zip"),
                           artifacts / artifact["name"], artifact)
        manifest = RELEASE.prepare(artifacts, staged, SOURCE, RUN_URL)
        manifest.update({
            "releaseScope": "windows-macos-tested-preview",
            "sourceCommit": SOURCE,
            "publisherCommit": publisher,
            "sourceTree": SOURCE_TREE,
            "buildCheckoutCommit": BUILD_CHECKOUT,
            "verification": {
                "runId": RUN, "runUrl": RUN_URL, "sourceCommit": SOURCE,
                "buildCheckoutCommit": BUILD_CHECKOUT,
                "overallRunConclusion": "success",
                "windowsJobId": 124054804159, "macosJobId": 124054803658,
                "frontendJobId": 124054803992,
                "windowsJobConclusion": "success", "macosJobConclusion": "success",
                "frontendJobConclusion": "success",
                "artifacts": [{"id": a["id"], "name": a["name"],
                               "archiveBytes": a["size"], "archiveSha256": a["sha256"]}
                              for a in ARTIFACTS],
            },
            "laterValidation": {
                "sourceCommit": LATER_SOURCE, "sourceTree": SOURCE_TREE,
                "runId": LATER_RUN,
                "runUrl": f"https://github.com/Blueeeecho/EchoLingo/actions/runs/{LATER_RUN}",
                "conclusion": "failure", "gate": "rigorousSelection",
                "error": "MOCK_CONTROLLED_REPLY_NOT_RELEASED",
                "fixed": False, "userRetestingRequired": True,
            },
            "knownLimitations": [
                "The later same-tree Windows rigorousSelection gate failed with "
                "MOCK_CONTROLLED_REPLY_NOT_RELEASED; this preview does not claim that failure is fixed.",
                "Real-machine interaction feel and intermittent clipboard behavior require user testing.",
            ],
        })
        (staged / "RELEASE-MANIFEST.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (staged / "SHA256SUMS.txt").write_text("".join(
            f"{sha256(path)}  {path.name}\n" for path in sorted(staged.iterdir())
            if path.name != "SHA256SUMS.txt"), encoding="utf-8")
        shutil.copytree(staged, output)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive_directory", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("publisher")
    args = parser.parse_args()
    prepare(args.archive_directory, args.output, args.publisher)
