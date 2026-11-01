#!/usr/bin/env python3
"""Hash a 0.2.6 candidate and bind explicit build checks to its exact source.

This is not a release/installed-application acceptance gate. It never executes
an installer, application or engine, downloads files, changes Git, or republishes
historical installer acceptance. Native package inspection is supplied by the
separate workflow inspector and is explicitly identified as an input assertion.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.2.6"
MODE = "candidate-package-provenance-v1"
STAGER_SHA256 = "da1928dd2c699bc27d7d6ff7d6c66c975fc72018fea14b153a34bc5fdd9f05fa"
VERSION_PATHS = (
    "package.json", "package-lock.json", "src-tauri/tauri.conf.json",
    "src-tauri/Cargo.toml", "src-tauri/Cargo.lock",
    "src-tauri/native-capture/Cargo.toml", "src-tauri/native-capture/Cargo.lock",
)
CHECK_NAMES = {
    "lockedBuild", "focusedTestsPassed", "installerStructureVerified",
    "applicationMetadataVerified", "installerApplicationMatches",
}
CHECK_FIELDS = {
    "schemaVersion", "platform", "version", "commit", "tree", "runUrl", "checks",
    "applicationMetadata", "installerSha256", "applicationSha256", "extractedApplicationSha256",
}


def no_links(path):
    path = Path(os.path.abspath(path))
    for part in [*reversed(path.parents), path]:
        if not part.exists() and not part.is_symlink():
            continue
        info = part.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError("Symlink/reparse paths are not allowed: " + str(part))
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def identity(path):
    path = no_links(path)
    if not path.is_file() or path.stat().st_size <= 0:
        raise ValueError("A nonempty regular file is required: " + path.name)
    if any(ord(character) < 32 for character in path.name):
        raise ValueError("Control characters are not permitted in artifact filenames")
    return {"name": path.name, "size": path.stat().st_size, "sha256": sha256(path)}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON field: " + key)
        result[key] = value
    return result


def read_json(path):
    path = no_links(path)
    if not path.is_file() or path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError("Missing or oversized metadata file")
    value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)
    if not isinstance(value, dict):
        raise ValueError("Metadata must be a JSON object")
    return value


def git(root, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=root, text=True).strip()


def source_provenance(root):
    if Path(git(root, "rev-parse", "--show-toplevel")).resolve() != root.resolve():
        raise ValueError("Source root must be the Git worktree root")
    # Git handles its configured CRLF conversion. Never normalize installer bytes.
    if git(root, "status", "--porcelain=v1", "--untracked-files=no"):
        raise ValueError("Tracked source differs from committed HEAD")
    commit, tree = git(root, "rev-parse", "HEAD"), git(root, "rev-parse", "HEAD^{tree}")
    if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (commit, tree)):
        raise ValueError("Exact Git commit/tree identities are required")
    return {"commit": commit, "tree": tree, "trackedWorktreeClean": True}


def check_versions(root):
    package, lock, tauri = [read_json(root / name) for name in VERSION_PATHS[:3]]
    cargo, cargo_lock, capture, capture_lock = [
        tomllib.loads(no_links(root / name).read_text(encoding="utf-8")) for name in VERSION_PATHS[3:]
    ]
    versions = [package["version"], lock["version"], lock["packages"][""]["version"],
                tauri["version"], cargo["package"]["version"], capture["package"]["version"]]
    for manifest, name in ((cargo_lock, "echolingo"), (capture_lock, "echolingo-native-capture")):
        entries = [entry for entry in manifest["package"] if entry["name"] == name]
        if len(entries) != 1:
            raise ValueError("Exactly one own-package lock entry is required: " + name)
        versions.append(entries[0]["version"])
    if len(versions) != 8 or any(version != VERSION for version in versions):
        raise ValueError("All eight version values in seven manifests must equal 0.2.6")
    return [{"path": name, "sha256": sha256(root / name)} for name in VERSION_PATHS]


def check_pe(path, expected_machine=None):
    size = path.stat().st_size
    with path.open("rb") as source:
        dos = source.read(64)
        if len(dos) != 64 or dos[:2] != b"MZ":
            raise ValueError("Missing PE DOS header")
        offset = struct.unpack_from("<I", dos, 60)[0]
        if offset < 64 or offset + 24 > size:
            raise ValueError("Invalid PE header offset")
        source.seek(offset)
        header = source.read(24)
        if header[:4] != b"PE\0\0":
            raise ValueError("Missing PE signature")
        machine, sections = struct.unpack_from("<HH", header, 4)
        optional_size, flags = struct.unpack_from("<HH", header, 20)
        if (machine not in (0x14C, 0x8664) or expected_machine not in (None, machine)
                or not 1 <= sections <= 96 or not flags & 2 or flags & 0x2000
                or optional_size < 64 or offset + 24 + optional_size + sections * 40 > size):
            raise ValueError("Unexpected PE architecture or executable structure")
        optional = source.read(optional_size)
        if struct.unpack_from("<H", optional)[0] != (0x20B if machine == 0x8664 else 0x10B):
            raise ValueError("PE optional-header architecture mismatch")
        entry = struct.unpack_from("<I", optional, 16)[0]
        executable_entry = False
        for _ in range(sections):
            section = source.read(40)
            virtual_size, address, raw_size, raw_offset = struct.unpack_from("<IIII", section, 8)
            characteristics = struct.unpack_from("<I", section, 36)[0]
            if raw_size and (raw_offset == 0 or raw_offset + raw_size > size):
                raise ValueError("PE section extends outside the file")
            if characteristics & 0x20000000 and raw_size and address <= entry < address + max(virtual_size, raw_size):
                executable_entry = True
        if not executable_entry:
            raise ValueError("PE has no bounded executable entry section")
    return "PE-x64" if machine == 0x8664 else "PE-x86-installer-stub"


def check_headers(platform, installer, application):
    if platform == "Windows":
        if installer.name != "EchoLingo_0.2.6_x64-setup.exe" or application.name.lower() != "echolingo.exe":
            raise ValueError("Unexpected Windows candidate filename/version/architecture")
        return {"installer": check_pe(installer), "application": check_pe(application, 0x8664)}
    if installer.name not in {"EchoLingo_0.2.6_aarch64.dmg", "EchoLingo_0.2.6_arm64.dmg"} or application.name != "echolingo":
        raise ValueError("Unexpected macOS candidate filename/version/architecture")
    if installer.stat().st_size <= 512:
        raise ValueError("Truncated UDIF disk image")
    with installer.open("rb") as source:
        source.seek(-512, 2)
        trailer = source.read(512)
    if trailer[:4] != b"koly" or struct.unpack_from(">II", trailer, 4) != (4, 512):
        raise ValueError("Missing standard UDIF trailer")
    with application.open("rb") as source:
        header = source.read(32)
    if (len(header) != 32 or header[:4] != b"\xcf\xfa\xed\xfe"
            or struct.unpack_from("<I", header, 4)[0] != 0x0100000C
            or struct.unpack_from("<I", header, 12)[0] != 2):
        raise ValueError("Expected a thin arm64 Mach-O executable")
    commands, command_size = struct.unpack_from("<II", header, 16)
    if commands == 0 or command_size < commands * 8 or 32 + command_size > application.stat().st_size:
        raise ValueError("Invalid Mach-O load-command bounds")
    return {"installer": "UDIF-header", "application": "Mach-O-arm64-header"}


def check_attestations(data, platform, provenance, run_url, installer, application):
    if set(data) != CHECK_FIELDS or type(data["schemaVersion"]) is not int or data["schemaVersion"] != 1:
        raise ValueError("Unexpected package-inspection schema")
    expected = {"platform": platform, "version": VERSION, "commit": provenance["commit"],
                "tree": provenance["tree"], "runUrl": run_url,
                "installerSha256": installer["sha256"], "applicationSha256": application["sha256"],
                "extractedApplicationSha256": application["sha256"]}
    if any(data[key] != value for key, value in expected.items()):
        raise ValueError("Inspection evidence is not bound to this source/run/package")
    if not isinstance(data["checks"], dict) or set(data["checks"]) != CHECK_NAMES or any(
            value is not True for value in data["checks"].values()):
        raise ValueError("Every explicit workflow build/inspection check must pass")
    if data["applicationMetadata"] != {"version": VERSION, "architecture": "x64" if platform == "Windows" else "arm64"}:
        raise ValueError("Packaged application metadata version/architecture mismatch")


def validate_reuse_metadata(data, stage, runtime):
    expected = {
        "ok": True, "validationMode": "language-routing-patch-v1",
        "baselineCommit": stage.BASELINE_COMMIT, "baselineTree": stage.BASELINE_TREE,
        "baselineRunId": stage.BASELINE_RUN, "baselineArtifacts": stage.ARTIFACTS,
        "baselineInstaller": stage.INSTALLER, "baselineInstallerSha256": stage.INSTALLER["sha256"],
        "baselineReport": stage.REPORT, "sourceArchive": stage.SOURCE, "engine": stage.ENGINE,
        "offlineResourcesVerified": True, "oldApplicationStaged": False,
        "newInstallerAccepted": False, "installerExecuted": False, "engineExecuted": False,
        "visualTestsExecuted": False, "visualAcceptanceRepeated": False,
        "runtimeFiles": [{"path": name, **value} for name, value in sorted(runtime.items())],
    }
    for key, value in expected.items():
        if data.get(key) != value or (isinstance(value, bool) and data.get(key) is not value):
            raise ValueError("Pinned offline-resource provenance differs: " + key)


def verify_offline_reuse(root, manifest, source):
    stager_path = no_links(root / "scripts/stage-language-patch-resources.py")
    if hashlib.sha256(stager_path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != STAGER_SHA256:
        raise ValueError("Offline-resource stager differs from the reviewed pinned implementation")
    spec = importlib.util.spec_from_file_location("candidate_pinned_resource_stager", stager_path)
    stage = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stage)
    stage.check_file(source, stage.SOURCE)
    stage.check_source(source)
    report = stage.check_file(manifest.parent / "baseline-offline-validation.json", stage.REPORT)
    auditor = stage.load_auditor()
    runtime = stage.expected_runtime(read_json(report), auditor)
    validate_reuse_metadata(read_json(manifest), stage, runtime)
    for name, expected in runtime.items():
        stage.check_file(root / "resources/offline-translation" / name, expected)
    auditor.inventory(staged=True)
    stage.check_file(source, stage.SOURCE)
    stage.check_file(report, stage.REPORT)
    return {"scope": "unchanged offline engine/models/notices/corresponding-source only",
            "baselineCommit": stage.BASELINE_COMMIT, "baselineTree": stage.BASELINE_TREE,
            "baselineRunId": stage.BASELINE_RUN, "stagingManifest": identity(manifest),
            "sourceArchive": identity(source), "engine": stage.ENGINE,
            "runtimeFilesVerified": len(runtime), "historicalReportBytesPinned": True,
            "currentInstallerAcceptanceTransferred": False, "currentEngineRuntimeExecuted": False}


def run(args, root=ROOT):
    if args.platform not in {"Windows", "macOS"}:
        raise ValueError("Unsupported candidate platform")
    if not re.fullmatch(r"https://github\.com/Blueeeecho/EchoLingo/actions/runs/[1-9][0-9]*", args.run_url):
        raise ValueError("A canonical candidate build run URL is required")
    output = no_links(args.output)
    checksum_output = no_links(Path(str(output) + ".sha256"))
    if output.suffix.lower() != ".json" or output.exists() or checksum_output.exists() or not output.parent.is_dir():
        raise ValueError("Manifest/checksum outputs must be new files in an existing directory")
    if any(ord(character) < 32 for character in output.name):
        raise ValueError("Invalid output filename")
    provenance = source_provenance(root)
    versions = check_versions(root)
    installer, application = no_links(args.installer), no_links(args.application)
    installer_id, application_id = identity(installer), identity(application)
    headers = check_headers(args.platform, installer, application)
    checks_id = identity(args.checks_json)
    inspection = read_json(args.checks_json)
    check_attestations(inspection, args.platform, provenance, args.run_url, installer_id, application_id)
    offline = None
    if args.platform == "Windows":
        if args.offline_staging_manifest is None or args.offline_source_archive is None:
            raise ValueError("Windows candidates require pinned offline staging and corresponding source")
        offline = verify_offline_reuse(root, no_links(args.offline_staging_manifest), no_links(args.offline_source_archive))
    elif args.offline_staging_manifest is not None or args.offline_source_archive is not None:
        raise ValueError("Windows offline reuse cannot be attributed to a macOS candidate")
    if (source_provenance(root) != provenance or identity(installer) != installer_id
            or identity(application) != application_id or identity(args.checks_json) != checks_id):
        raise ValueError("Source or package bytes changed during verification")
    result = {"schemaVersion": 1, "validationMode": MODE, "version": VERSION,
              "platform": args.platform, "architecture": "x64" if args.platform == "Windows" else "arm64",
              "source": provenance, "runUrl": args.run_url, "versionManifests": versions,
              "installer": installer_id, "application": application_id, "formatHeaders": headers,
              "workflowInspection": {"evidence": checks_id, "assertions": inspection},
              "offlineResourceReuse": offline,
              "scope": {"buildAndStaticPackageEvidenceOnly": True, "installerExecuted": False,
                        "installedApplicationAcceptance": False, "interactiveSelectionAcceptance": False,
                        "visualAcceptance": False, "performanceAcceptance": False,
                        "releaseAcceptance": False, "historicalInstallerAcceptanceTransferred": False}}
    with output.open("x", encoding="utf-8", newline="\n") as destination:
        destination.write(json.dumps(result, indent=2, sort_keys=True) + "\n")
    # The bare extracted executable is evidence, not a delivered installer asset.
    # Its hash remains in the manifest; checksums list delivered basenames only.
    entries = [installer_id, identity(output)]
    if offline:
        entries.append(offline["sourceArchive"])
    with checksum_output.open("x", encoding="utf-8", newline="\n") as destination:
        for entry in entries:
            destination.write(f'{entry["sha256"]}  {entry["name"]}\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["Windows", "macOS"], required=True)
    for name in ("installer", "application", "checks-json", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--offline-staging-manifest", type=Path)
    parser.add_argument("--offline-source-archive", type=Path)
    print(json.dumps(run(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, struct.error, subprocess.SubprocessError) as error:
        print("Candidate provenance failed: " + str(error), file=sys.stderr)
        sys.exit(1)
