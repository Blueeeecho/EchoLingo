#!/usr/bin/env python3
"""Reuse only hash-pinned, already accepted offline resources for the OCR patch.

No download, installer/app/engine execution, or fresh acceptance is performed.
7-Zip lists and extracts only the exact runtime allowlist from the old NSIS.
The old application is read in memory only to verify its historical evidence.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

from verify_screenshot_editor_report import verify_installed_acceptance

ROOT = Path(__file__).resolve().parent.parent
BASELINE_COMMIT = "4b8c5f5ac67e07cc4005812963b2c02acdd14d5d"
BASELINE_TREE = "dbb9690106c0abec0c55f2bc665d7b60aedf0697"
BASELINE_RUN = 41178655504
ARTIFACTS = {
    "windows": {"id": 13034542412, "size": 75913568,
                "sha256": "da42d05739744f5eafa71f9758d6a045b42020403d4228f3007d9bbda92fbb25"},
    "evidence": {"id": 13034970610, "size": 18894885,
                 "sha256": "2520b83f54d3774b75c0cc1c6fc3f3105f0c9fb380800d94ac73001e36295285"},
}
INSTALLER = {"size": 75911379, "sha256": "55f3b9c239df8509dcd739ee690cbfcb6d5ac59ed396dc1a0cda342ca8ad11b5"}
ENGINE = {"size": 6479872, "sha256": "957b54ce135a8ef7ffb0b19c4b46d2fbcf56449831fc2ef9f767d634b8dd5310"}
SOURCE = {"size": 19274493, "sha256": "52ce8e690c977e409670c1c32081e9ff354e1b9a0c701e2115c23ca985e9daea"}
REPORT = {"size": 44030, "sha256": "a630618e1cabd469163535e9bdf9f5d26c9528c693bdbf07e03e96118229016b"}
STAGE_APP = {"size": 7944192, "sha256": "cdee16da380d9746c5e1ea212b27bad615605ec543f57a29bfc8a1b6e6e53c25"}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def no_links(path):
    """Reject symlinks/junctions before resolving or touching their contents."""
    path = Path(os.path.abspath(path))
    for item in [*reversed(path.parents), path]:
        if not item.exists() and not item.is_symlink():
            continue
        info = item.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError("link/reparse point is not permitted: " + str(item))
    return path


def check_file(path, expected):
    path = no_links(path)
    if (not path.is_file() or path.stat().st_size != expected["size"]
            or sha256(path) != expected["sha256"]):
        raise ValueError("pinned file identity mismatch: " + path.name)
    return path


def safe_name(name):
    name = name.replace("\\", "/")
    parts = name.split("/")
    if (not name or any(not p or p in (".", "..") or p[-1:] in (" ", ".")
                        or any(ord(c) < 32 or c in ':*?<>|"' for c in p)
                        or p.split(".")[0].upper() in {"CON", "PRN", "AUX", "NUL", *("COM" + str(i) for i in range(1, 10)), *("LPT" + str(i) for i in range(1, 10))}
                        for p in parts)):
        raise ValueError("unsafe archive member name")
    return name


def zip_member(archive, name, expected):
    matches = [item for item in archive.infolist() if item.filename == name]
    if len(matches) != 1 or matches[0].is_dir() or matches[0].file_size != expected["size"]:
        raise ValueError("missing/duplicate/unbounded pinned ZIP member: " + name)
    item = matches[0]
    if stat.S_ISLNK(item.external_attr >> 16):
        raise ValueError("ZIP member is a symlink")
    data = archive.read(item)
    if hashlib.sha256(data).hexdigest() != expected["sha256"]:
        raise ValueError("ZIP member hash mismatch: " + name)
    return data


def load_auditor():
    spec = importlib.util.spec_from_file_location("patch_resource_audit", ROOT / "scripts/audit-windows-resources.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expected_runtime(report, auditor):
    auditor.inventory()  # Validate checked-in exact config, notices, and manifest first.
    resources = ROOT / "resources/offline-translation"
    manifest = json.loads((resources / "manifest.json").read_text(encoding="utf-8"))
    if (report["resources"]["manifestSha256"] != sha256(resources / "manifest.json")
            or report["resources"]["licenseManifestSha256"] != sha256(resources / "license-files.json")
            or report["resources"]["files"] != [{key: entry[key] for key in ("path", "size", "sha256")} for entry in manifest["files"]]):
        raise ValueError("baseline model/license inventory differs from current source")
    expected = {entry["path"]: {"size": entry["size"], "sha256": entry["sha256"]}
                for entry in manifest["files"]}
    expected["bin/echolingo-offline-engine.exe"] = ENGINE
    for path in [resources / "manifest.json", resources / "license-files.json", *sorted((resources / "licenses").iterdir())]:
        no_links(path)
        expected[path.relative_to(resources).as_posix()] = {"size": path.stat().st_size, "sha256": sha256(path)}
    return expected


def parse_listing(text, expected):
    """Choose exactly one safe resource root; no wildcard or whole-NSIS extraction."""
    records = []
    for block in text.replace("\r\n", "\n").strip().split("\n\n"):
        row = {}
        for line in block.splitlines():
            if " = " in line:
                key, value = line.split(" = ", 1)
                if key in row:
                    raise ValueError("duplicate 7-Zip listing field")
                row[key] = value
        if "Path" in row:
            records.append(row)
    if not records or len(records) > 4096:
        raise ValueError("missing/unbounded NSIS listing")
    roots, found, folded = set(), {}, set()
    for row in records:
        name = safe_name(row["Path"])
        if name.casefold() in folded:
            raise ValueError("duplicate/case-aliased NSIS path")
        folded.add(name.casefold())
        parts = name.split("/")
        if "offline-translation" not in parts:
            continue
        if parts.count("offline-translation") != 1:
            raise ValueError("ambiguous NSIS resource root")
        index = parts.index("offline-translation")
        root = "/".join(parts[:index + 1])
        roots.add(root)
        if row.get("Folder") == "+" or row.get("Attributes", "").startswith("D"):
            continue
        relative = "/".join(parts[index + 1:])
        if (relative not in expected or relative in found
                or any("link" in key.lower() for key in row)
                or row.get("Size") != str(expected[relative]["size"])):
            raise ValueError("NSIS resource allowlist/size mismatch: " + relative)
        found[relative] = row["Path"]
    if len(roots) != 1 or set(found) != set(expected):
        raise ValueError("NSIS must contain exactly one complete offline runtime allowlist")
    return roots.pop(), found


def check_source(source):
    """The accepted corresponding-source asset must match our unchanged engine inputs."""
    paths = [*(ROOT / "scripts/offline-engine" / name for name in
               ("CMakeLists.txt", "README.md", "build.py", "main.cpp", "sources.lock.json")),
             *(ROOT / p for p in ("scripts/prepare-offline-models.py", "scripts/test_prepare_offline_models.py",
                                  "scripts/prepare-offline-notices.py", "scripts/package-offline-source.py", "LICENSE", "LICENSING.md")),
             *sorted((ROOT / "resources/offline-translation").glob("*.json")),
             *sorted((ROOT / "resources/offline-translation/licenses").iterdir())]
    with zipfile.ZipFile(source) as archive:
        for path in paths:
            no_links(path)
            if not path.is_file():
                raise ValueError("unexpected engine input directory")
            name = path.relative_to(ROOT).as_posix()
            members = [item for item in archive.infolist() if item.filename == name]
            if len(members) != 1 or members[0].is_dir() or members[0].file_size > 32 * 1024 * 1024:
                raise ValueError("missing/ambiguous source input: " + name)
            # Git's Windows checkout used CRLF for text source. The immutable
            # archive itself remains byte-pinned; compare source content only.
            if archive.read(members[0]).replace(b"\r\n", b"\n") != path.read_bytes().replace(b"\r\n", b"\n"):
                raise ValueError("baseline engine source input changed: " + name)


def stage_generated(extracted, expected):
    resources = ROOT / "resources/offline-translation"
    for name, identity in sorted(expected.items()):
        source = check_file(extracted / name, identity)
        target = no_links(resources / name)
        if target.exists():
            check_file(target, identity)  # Never replace existing different bytes.
            continue
        if not (name.startswith("models/") or name == "bin/echolingo-offline-engine.exe"):
            raise ValueError("checked-in resource is missing: " + name)
        target.parent.mkdir(parents=True, exist_ok=True)
        no_links(target.parent)
        with source.open("rb") as reader, target.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
        check_file(target, identity)


def run(args):
    windows = check_file(args.windows_zip, ARTIFACTS["windows"])
    evidence = check_file(args.evidence_zip, ARTIFACTS["evidence"])
    output = no_links(args.output_dir)
    output.mkdir(exist_ok=False)  # Caller owns parent; never overwrite an earlier run.
    with zipfile.ZipFile(evidence) as archive:
        report_bytes = zip_member(archive, "_temp/echolingo-offline-validation.json", REPORT)
        source_bytes = zip_member(archive, "_temp/EchoLingo-offline-engine-source.zip", SOURCE)
        stage_bytes = zip_member(archive, "EchoLingo/EchoLingo/src-tauri/target/release/echolingo.exe", STAGE_APP)
    report = json.loads(report_bytes.decode("utf-8-sig"))
    verify_installed_acceptance(report_bytes.decode("utf-8-sig"), stage_bytes)
    del stage_bytes  # Historical application never written, staged, or launched.
    if (report.get("installerSha256") != INSTALLER["sha256"] or report.get("installerBytes") != INSTALLER["size"]
            or report.get("engineSha256") != ENGINE["sha256"] or report.get("engineBytes") != ENGINE["size"]
            or report.get("resourceAllowlist", {}).get("ok") is not True):
        raise ValueError("accepted baseline installer/engine identity differs")
    (output / "baseline-offline-validation.json").write_bytes(report_bytes)
    source = output / "EchoLingo-offline-engine-source.zip"
    source.write_bytes(source_bytes)
    del source_bytes
    check_source(source)
    auditor = load_auditor()
    expected = expected_runtime(report, auditor)
    with tempfile.TemporaryDirectory(prefix="baseline-resource-extract-", dir=output) as temporary:
        work = Path(temporary)
        installer = work / "baseline.exe"
        with zipfile.ZipFile(windows) as archive:
            installer.write_bytes(zip_member(archive, "nsis/EchoLingo_0.2.4_x64-setup.exe", INSTALLER))
        listing = subprocess.run([args.seven_zip, "l", "-slt", "-ba", "-sccUTF-8", str(installer)],
                                 check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        (output / "nsis-listing.txt").write_bytes(listing.stdout)
        (output / "nsis-listing.stderr.txt").write_bytes(listing.stderr)
        prefix, members = parse_listing(listing.stdout.decode("utf-8-sig"), expected)
        destination = work / "payload"
        destination.mkdir()
        with (output / "nsis-extraction.log").open("wb") as log:
            subprocess.run([args.seven_zip, "x", "-y", "-spd", "-sccUTF-8", "-o" + str(destination),
                            str(installer), *[members[name] for name in sorted(members)]],
                           check=True, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        actual = set()
        for path in destination.rglob("*"):
            no_links(path)
            if path.is_file():
                actual.add(path.relative_to(destination).as_posix())
        if actual != {safe_name(name) for name in members.values()}:
            raise ValueError("7-Zip extracted files beyond the exact runtime allowlist")
        extracted = destination / prefix
        for name, identity in expected.items():
            check_file(extracted / name, identity)
        extracted_audit = auditor.inventory(installed_root=extracted)
        stage_generated(extracted, expected)
        staged_audit = auditor.inventory(staged=True)
    # Recheck pins after extraction/staging and preserve only source/report/logs, never old app/installer.
    check_file(windows, ARTIFACTS["windows"])
    check_file(evidence, ARTIFACTS["evidence"])
    check_file(source, SOURCE)
    result = {
        "ok": True, "validationMode": "language-routing-patch-v1", "visualAcceptanceRepeated": False,
        "baselineCommit": BASELINE_COMMIT, "baselineTree": BASELINE_TREE,
        "baselineRunId": BASELINE_RUN, "baselineArtifacts": ARTIFACTS,
        "baselineInstallerSha256": INSTALLER["sha256"], "baselineInstaller": INSTALLER,
        "baselineReport": REPORT, "sourceArchive": SOURCE, "engine": ENGINE,
        "baselineInstalledAcceptanceVerified": True, "baselineInstalledScreenshotEditorVerified": True,
        "offlineResourcesVerified": True, "runtimeFiles": [{"path": name, **identity} for name, identity in sorted(expected.items())],
        "resourceAudit": {"extracted": extracted_audit, "staged": staged_audit},
        "sourceContentComparison": "CRLF/LF-normalized text; preserved source ZIP remains byte-identical",
        "nsisResourcePrefix": prefix, "oldApplicationStaged": False, "newInstallerAccepted": False,
        "installerExecuted": False, "engineExecuted": False, "visualTestsExecuted": False,
        "reuseScope": "Unchanged baseline offline engine/models/notices/source and historical accepted evidence only; not fresh installer acceptance",
    }
    (output / "baseline-reuse.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windows-zip", type=Path, required=True)
    parser.add_argument("--evidence-zip", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seven-zip", default="7z")
    print(json.dumps(run(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        print("baseline resource reuse failed: " + str(error), file=sys.stderr)
        sys.exit(1)
