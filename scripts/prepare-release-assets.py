#!/usr/bin/env python3
"""Prepare 0.2.4 public assets from the exact successful CI run, without rebuilding."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tomllib
import zipfile

from verify_screenshot_editor_report import verify_report as verify_screenshot_editor_report


ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.2.4"


def check_version(root=ROOT):
    package = json.loads((root / "package.json").read_text())
    lock = json.loads((root / "package-lock.json").read_text())
    tauri = json.loads((root / "src-tauri/tauri.conf.json").read_text())
    cargo = tomllib.loads((root / "src-tauri/Cargo.toml").read_text())
    cargo_lock = tomllib.loads((root / "src-tauri/Cargo.lock").read_text())
    versions = [package["version"], lock["version"], lock["packages"][""]["version"],
                tauri["version"], cargo["package"]["version"]]
    versions.extend(item["version"] for item in cargo_lock["package"] if item["name"] == "echolingo")
    capture = tomllib.loads((root / "src-tauri/native-capture/Cargo.toml").read_text())
    capture_lock = tomllib.loads((root / "src-tauri/native-capture/Cargo.lock").read_text())
    versions.append(capture["package"]["version"])
    versions.extend(item["version"] for item in capture_lock["package"] if item["name"] == "echolingo-native-capture")
    if len(versions) != 8 or any(version != VERSION for version in versions):
        raise ValueError("All package, Tauri and Cargo versions must be exactly 0.2.4")


def one_file(directory, pattern):
    matches = list(directory.rglob(pattern))
    if len(matches) != 1 or not matches[0].is_file() or matches[0].is_symlink() or not matches[0].stat().st_size:
        raise ValueError(f"Expected one nonempty regular {pattern} in {directory.name}")
    return matches[0]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _prepare_full(artifacts, output, commit, run_url):
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
    # Historical 0.2.1/0.2.2 helpers import this preparer but remain version-pinned.
    # F1 is mandatory from 0.2.4 onward; do not retroactively assert it for old bytes.
    requires_screenshot_editor = tuple(map(int, VERSION.split("."))) >= (0, 2, 4)
    if requires_screenshot_editor:
        if report.get("installedScreenshotEditorVerified") is not True:
            raise ValueError("Installed F1 editor acceptance did not pass")
        installed_sha = report.get("applicationSha256")
        if not isinstance(installed_sha, str) or re.fullmatch(r"[0-9a-f]{64}", installed_sha) is None:
            raise ValueError("Installed application identity is absent for F1 acceptance")
        verify_screenshot_editor_report(report.get("installedScreenshotEditor"), installed_sha, installed=True)
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
    if requires_screenshot_editor:
        manifest["windowsInstalledScreenshotEditorVerified"] = True
    (output / "RELEASE-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    checksums = [f"{sha256(path)}  {path.name}\n" for path in sorted(output.iterdir())]
    (output / "SHA256SUMS.txt").write_text("".join(checksums), encoding="utf-8")
    return manifest



LANGUAGE_PATCH_MODE = "language-routing-patch-v1"
LANGUAGE_PATCH_BASELINE = {
    "commit": "4b8c5f5ac67e07cc4005812963b2c02acdd14d5d",
    "runId": 41178655504,
    "tree": "dbb9690106c0abec0c55f2bc665d7b60aedf0697",
}


LANGUAGE_PATCH_ARTIFACTS = {
    "windows": {"id": 13034542412, "size": 75913568,
                "sha256": "da42d05739744f5eafa71f9758d6a045b42020403d4228f3007d9bbda92fbb25"},
    "evidence": {"id": 13034970610, "size": 18894885,
                 "sha256": "2520b83f54d3774b75c0cc1c6fc3f3105f0c9fb380800d94ac73001e36295285"},
}
LANGUAGE_PATCH_INSTALLER = {"size": 75911379, "sha256": "55f3b9c239df8509dcd739ee690cbfcb6d5ac59ed396dc1a0cda342ca8ad11b5"}
LANGUAGE_PATCH_SOURCE = {"size": 19274493, "sha256": "52ce8e690c977e409670c1c32081e9ff354e1b9a0c701e2115c23ca985e9daea"}
LANGUAGE_PATCH_REPORT = {"size": 44030, "sha256": "a630618e1cabd469163535e9bdf9f5d26c9528c693bdbf07e03e96118229016b"}


def _prepare_language_patch(artifacts, output, commit, run_url):
    if VERSION != "0.2.4":
        raise ValueError("Language patch mode is only authorized for 0.2.4")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("An exact source commit is required")
    if not re.fullmatch(r"https://github\.com/Blueeeecho/EchoLingo/actions/runs/[0-9]+", run_url):
        raise ValueError("A canonical validation run URL is required")
    if output.exists():
        raise ValueError("Output already exists; never overwrite prepared publication files")
    windows = one_file(artifacts / "EchoLingo-Windows", "*.exe")
    macos = one_file(artifacts / "EchoLingo-macOS", "*.dmg")
    if windows.name != "EchoLingo_0.2.4_x64-setup.exe" or macos.name not in {
        "EchoLingo_0.2.4_aarch64.dmg", "EchoLingo_0.2.4_arm64.dmg"
    }:
        raise ValueError("Installer version or architecture does not match this release")
    evidence = artifacts / "EchoLingo-language-patch-evidence"
    reports = {}
    for platform, filename, installer in [
        ("Windows", "windows-build.json", windows), ("macOS", "macos-build.json", macos)
    ]:
        report = json.loads(one_file(evidence, filename).read_text(encoding="utf-8-sig"))
        if not isinstance(report, dict) or set(report) != {
            "validationMode", "commit", "platform", "baseline", "installer",
            "targetedLanguageTestsPassed", "sourceGuardPassed", "versionVerified", "lockedBuild",
            "visualAcceptanceRepeated"
        }:
            raise ValueError("Language patch build report has an unexpected schema")
        if (report.get("validationMode") != LANGUAGE_PATCH_MODE or report.get("commit") != commit
                or report.get("platform") != platform or report.get("baseline") != LANGUAGE_PATCH_BASELINE
                or report.get("visualAcceptanceRepeated") is not False):
            raise ValueError("Language patch build provenance does not match the fixed scope")
        for field in ("targetedLanguageTestsPassed", "sourceGuardPassed", "versionVerified", "lockedBuild"):
            if report.get(field) is not True:
                raise ValueError(f"Language patch build gate did not pass: {field}")
        identity = {"name": installer.name, "size": installer.stat().st_size, "sha256": sha256(installer)}
        if report.get("installer") != identity:
            raise ValueError("Language patch installer differs from the validated build bytes")
        reports[platform] = report
    source = one_file(evidence, "EchoLingo-offline-engine-source.zip")
    baseline = json.loads(one_file(evidence, "baseline-reuse.json").read_text(encoding="utf-8-sig"))
    if (baseline.get("baselineCommit") != LANGUAGE_PATCH_BASELINE["commit"]
            or baseline.get("baselineRunId") != LANGUAGE_PATCH_BASELINE["runId"]
            or baseline.get("baselineTree") != LANGUAGE_PATCH_BASELINE["tree"]):
        raise ValueError("Baseline reuse does not match the authorized immutable baseline")
    for field in ("baselineInstalledAcceptanceVerified", "baselineInstalledScreenshotEditorVerified", "offlineResourcesVerified"):
        if baseline.get(field) is not True:
            raise ValueError(f"Baseline reuse verification is absent: {field}")
    if (baseline.get("validationMode") != LANGUAGE_PATCH_MODE or baseline.get("ok") is not True
            or baseline.get("baselineArtifacts") != LANGUAGE_PATCH_ARTIFACTS
            or baseline.get("baselineInstaller") != LANGUAGE_PATCH_INSTALLER
            or baseline.get("baselineInstallerSha256") != LANGUAGE_PATCH_INSTALLER["sha256"]
            or baseline.get("baselineReport") != LANGUAGE_PATCH_REPORT):
        raise ValueError("Baseline reuse identity does not match the fixed accepted artifacts")
    for field in ("visualAcceptanceRepeated", "oldApplicationStaged", "newInstallerAccepted",
                  "installerExecuted", "engineExecuted", "visualTestsExecuted"):
        if baseline.get(field) is not False:
            raise ValueError(f"Baseline reuse must not claim new execution: {field}")
    audits = baseline.get("resourceAudit", {})
    if not isinstance(audits, dict) or any(
        not isinstance(audits.get(stage), dict) or audits[stage].get("ok") is not True
        or audits[stage].get("stagedPayloadChecked") is not True for stage in ("extracted", "staged")
    ):
        raise ValueError("Both extracted and staged offline resources must be verified")
    if (baseline.get("sourceArchive") != LANGUAGE_PATCH_SOURCE
            or LANGUAGE_PATCH_SOURCE != {"size": source.stat().st_size, "sha256": sha256(source)}):
        raise ValueError("Corresponding source does not match the verified baseline archive")
    raw_report = one_file(evidence, "baseline-offline-validation.json")
    if LANGUAGE_PATCH_REPORT != {"size": raw_report.stat().st_size, "sha256": sha256(raw_report)}:
        raise ValueError("Baseline raw report differs from the pinned accepted evidence")
    historical = json.loads(raw_report.read_text(encoding="utf-8-sig"))
    for field in ("ok", "windowsRuntimeExecuted", "installerExecuted", "realModelExecuted",
                  "rulesRemoved", "ownedInstallRemoved", "installedScreenshotEditorVerified"):
        if historical.get(field) is not True:
            raise ValueError(f"Historical installed acceptance did not pass: {field}")
    if (historical.get("mockTranslationUsed") is not False
            or historical.get("installerSha256") != LANGUAGE_PATCH_INSTALLER["sha256"]
            or historical.get("installerBytes") != LANGUAGE_PATCH_INSTALLER["size"]):
        raise ValueError("Historical acceptance is not bound to the fixed baseline installer")
    installed_sha = historical.get("applicationSha256")
    if not isinstance(installed_sha, str) or re.fullmatch(r"[0-9a-f]{64}", installed_sha) is None:
        raise ValueError("Historical installed application identity is absent")
    verify_screenshot_editor_report(historical.get("installedScreenshotEditor"), installed_sha, installed=True)

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
    for original, name in [(windows, "EchoLingo_0.2.4_windows_x64-setup.exe"),
                           (macos, "EchoLingo_0.2.4_macos_arm64.dmg"),
                           (source, "EchoLingo-offline-engine-source.zip")]:
        destination = output / name
        shutil.copyfile(original, destination)
        files.append({"name": name, "size": destination.stat().st_size, "sha256": sha256(destination)})
    manifest = {"version": VERSION, "commit": commit, "validationRun": run_url,
                "validationMode": LANGUAGE_PATCH_MODE, "rebuiltAfterValidation": False,
                "windowsInstalledAcceptanceVerified": False,
                "windowsInstalledScreenshotEditorVerified": False,
                "visualAcceptanceRepeated": False, "targetedValidation": reports,
                "reusedBaseline": {**LANGUAGE_PATCH_BASELINE,
                    "artifacts": LANGUAGE_PATCH_ARTIFACTS,
                    "installer": LANGUAGE_PATCH_INSTALLER,
                    "sourceArchive": LANGUAGE_PATCH_SOURCE,
                    "windowsInstalledAcceptanceVerified": True,
                    "windowsInstalledScreenshotEditorVerified": True,
                    "offlineResourcesVerified": True,
                    "scope": "Prior baseline only; not installed acceptance of these new installers"},
                "files": files}
    (output / "RELEASE-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    checksums = [f"{sha256(path)}  {path.name}\n" for path in sorted(output.iterdir())]
    (output / "SHA256SUMS.txt").write_text("".join(checksums), encoding="utf-8")
    return manifest


def prepare(artifacts, output, commit, run_url, language_patch=False):
    if language_patch:
        return _prepare_language_patch(artifacts, output, commit, run_url)
    return _prepare_full(artifacts, output, commit, run_url)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-version", action="store_true")
    parser.add_argument("--language-patch", action="store_true")
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--commit")
    parser.add_argument("--run-url")
    args = parser.parse_args()
    check_version()
    if args.check_version:
        print("All release versions match 0.2.4.")
        return
    if not all((args.artifacts, args.output, args.commit, args.run_url)):
        parser.error("--artifacts, --output, --commit and --run-url are required")
    print(json.dumps(prepare(args.artifacts, args.output, args.commit, args.run_url, language_patch=args.language_patch), indent=2))


if __name__ == "__main__":
    main()
