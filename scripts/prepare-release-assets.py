#!/usr/bin/env python3
"""Prepare 0.2.1 public assets from the exact successful CI run, without rebuilding."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tomllib
import zipfile


ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.2.1"


def check_version(root=ROOT):
    package = json.loads((root / "package.json").read_text())
    lock = json.loads((root / "package-lock.json").read_text())
    tauri = json.loads((root / "src-tauri/tauri.conf.json").read_text())
    cargo = tomllib.loads((root / "src-tauri/Cargo.toml").read_text())
    cargo_lock = tomllib.loads((root / "src-tauri/Cargo.lock").read_text())
    versions = [package["version"], lock["version"], lock["packages"][""]["version"],
                tauri["version"], cargo["package"]["version"]]
    versions.extend(item["version"] for item in cargo_lock["package"] if item["name"] == "echolingo")
    if len(versions) != 6 or any(version != VERSION for version in versions):
        raise ValueError("All package, Tauri and Cargo versions must be exactly 0.2.1")


def one_file(directory, pattern):
    matches = list(directory.rglob(pattern))
    if len(matches) != 1 or not matches[0].is_file() or matches[0].is_symlink() or not matches[0].stat().st_size:
        raise ValueError(f"Expected one nonempty regular {pattern} in {directory.name}")
    return matches[0]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(artifacts, output, commit, run_url):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("An exact source commit is required")
    if not re.fullmatch(r"https://github\.com/Blueeeecho/EchoLingo/actions/runs/[0-9]+", run_url):
        raise ValueError("A canonical validation run URL is required")
    if output.exists():
        raise ValueError("Output already exists; never overwrite prepared publication files")
    windows = one_file(artifacts / "EchoLingo-Windows", "*.exe")
    macos = one_file(artifacts / "EchoLingo-macOS", "*.dmg")
    evidence = artifacts / "EchoLingo-Windows-offline-evidence"
    source = one_file(evidence, "EchoLingo-offline-engine-source.zip")
    report = json.loads(one_file(evidence, "echolingo-offline-validation.json").read_text(encoding="utf-8-sig"))
    if windows.name != f"EchoLingo_{VERSION}_x64-setup.exe" or macos.name not in {
        f"EchoLingo_{VERSION}_aarch64.dmg", f"EchoLingo_{VERSION}_arm64.dmg"
    }:
        raise ValueError("Installer version or architecture does not match this release")
    for field in ("ok", "windowsRuntimeExecuted", "installerExecuted", "realModelExecuted", "rulesRemoved", "ownedInstallRemoved"):
        if report.get(field) is not True:
            raise ValueError(f"Installed Windows acceptance did not pass: {field}")
    if report.get("mockTranslationUsed") is not False:
        raise ValueError("Real-model acceptance must not use a translation mock")
    if report.get("installerSha256") != sha256(windows) or report.get("installerBytes") != windows.stat().st_size:
        raise ValueError("Windows installer differs from the actual accepted bytes")
    with zipfile.ZipFile(source) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corresponding source ZIP is corrupt")
        inventory = json.loads(archive.read("SOURCE-MANIFEST.json"))
        if inventory.get("formatVersion") != 1 or not inventory.get("files"):
            raise ValueError("Corresponding source inventory is absent")
        names = [item["path"] for item in inventory["files"]]
        if len(set(names)) != len(names) or set(archive.namelist()) != set(names) | {"SOURCE-MANIFEST.json"}:
            raise ValueError("Corresponding source inventory differs from ZIP contents")
        for item in inventory["files"]:
            data = archive.read(item["path"])
            if len(data) != item["size"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
                raise ValueError("Corresponding source file failed integrity verification")
    output.mkdir(parents=True)
    files = []
    for original, name in [(windows, f"EchoLingo_{VERSION}_windows_x64-setup.exe"),
                           (macos, f"EchoLingo_{VERSION}_macos_arm64.dmg"),
                           (source, "EchoLingo-offline-engine-source.zip")]:
        destination = output / name
        shutil.copyfile(original, destination)
        files.append({"name": name, "size": destination.stat().st_size, "sha256": sha256(destination)})
    manifest = {"version": VERSION, "commit": commit, "validationRun": run_url,
                "rebuiltAfterValidation": False, "windowsInstalledAcceptanceVerified": True, "files": files}
    (output / "RELEASE-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    checksums = [f"{sha256(path)}  {path.name}\n" for path in sorted(output.iterdir())]
    (output / "SHA256SUMS.txt").write_text("".join(checksums), encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-version", action="store_true")
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--commit")
    parser.add_argument("--run-url")
    args = parser.parse_args()
    check_version()
    if args.check_version:
        print("All release versions match 0.2.1.")
        return
    if not all((args.artifacts, args.output, args.commit, args.run_url)):
        parser.error("--artifacts, --output, --commit and --run-url are required")
    print(json.dumps(prepare(args.artifacts, args.output, args.commit, args.run_url), indent=2))


if __name__ == "__main__":
    main()
