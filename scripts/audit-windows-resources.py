#!/usr/bin/env python3
"""Check the Windows installer resource allowlist without downloading anything.

Default: validate the checked-in allowlist and original notices. --staged also
verifies every generated model and the engine before packaging. --installed-root
checks the resulting offline-translation directory, including unexpected files.
This is a package inventory check, not translation or Windows interaction proof.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys


ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "resources/offline-translation"
EXCLUDED_METADATA = (
    ".gitignore", "README.md", "engine-sources.lock.json",
    "mozilla-model-registry-20261026.json", "selected-models.json",
)
REQUIRED_NOTICES = {"MPL-2.0.txt", "SOURCE-OFFER.md", "THIRD_PARTY_NOTICES.md"}


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def regular(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("missing regular resource: " + path.name)
    return path


def inventory(staged=False, installed_root=None):
    manifest = json.loads((RESOURCES / "manifest.json").read_text(encoding="utf-8"))
    notices = json.loads((RESOURCES / "license-files.json").read_text(encoding="utf-8"))
    if manifest.get("formatVersion") != 1 or len(manifest.get("files", [])) != 7:
        raise ValueError("unexpected model manifest")
    model_names = set()
    directions = set()
    for entry in manifest["files"]:
        relative = PurePosixPath(entry["path"])
        if (len(relative.parts) != 3 or relative.parts[0] != "models"
                or relative.parts[1] not in ("en-zh", "zh-en")
                or any(part in (".", "..") for part in relative.parts)
                or not isinstance(entry["size"], int) or entry["size"] <= 0
                or len(entry["sha256"]) != 64):
            raise ValueError("invalid model resource inventory")
        model_names.add(relative.as_posix())
        directions.add(relative.parts[1])
    if len(model_names) != 7 or directions != {"en-zh", "zh-en"}:
        raise ValueError("both complete offline translation directions are required")

    file_names = {"manifest.json", "license-files.json", "bin/echolingo-offline-engine.exe"} | model_names
    expected_mapping = {
        "../resources/offline-translation/" + name: "offline-translation/" + name
        for name in file_names | {"licenses/"}
    }
    config = json.loads((ROOT / "src-tauri/tauri.windows.conf.json").read_text(encoding="utf-8"))
    if config.get("bundle", {}).get("resources") != expected_mapping:
        raise ValueError("Windows resource mapping is not the exact runtime allowlist")
    # A base-config directory mapping would merge with the platform allowlist.
    base = json.loads((ROOT / "src-tauri/tauri.conf.json").read_text(encoding="utf-8"))
    if base.get("bundle", {}).get("resources"):
        raise ValueError("base configuration adds resources outside the Windows allowlist")

    license_paths = set()
    if notices.get("formatVersion") != 1 or len(notices.get("files", [])) < 33:
        raise ValueError("original license inventory is incomplete")
    for entry in notices["files"]:
        relative = PurePosixPath(entry["path"])
        if len(relative.parts) != 2 or relative.parts[0] != "licenses" or ".." in relative.parts:
            raise ValueError("unsafe license inventory")
        path = regular(RESOURCES / relative.as_posix())
        if digest(path) != entry["sha256"]:
            raise ValueError("original license digest mismatch: " + path.name)
        license_paths.add(relative.as_posix())
    for path in (RESOURCES / "licenses").iterdir():
        regular(path)
        license_paths.add("licenses/" + path.name)
    if not {"licenses/" + name for name in REQUIRED_NOTICES} <= license_paths:
        raise ValueError("license or corresponding-source notice was excluded")

    payload_root = installed_root or RESOURCES
    if staged or installed_root:
        engine = regular(payload_root / "bin/echolingo-offline-engine.exe")
        with engine.open("rb") as stream:
            engine_header = stream.read(2)
        if engine_header != b"MZ":
            raise ValueError("staged offline engine is not a Windows executable")
        for entry in manifest["files"]:
            path = regular(payload_root / entry["path"])
            if path.stat().st_size != entry["size"] or digest(path) != entry["sha256"]:
                raise ValueError("model digest or size mismatch: " + entry["path"])
    if installed_root:
        expected_files = file_names | license_paths
        actual_files = set()
        for path in installed_root.rglob("*"):
            if path.is_symlink():
                raise ValueError("installed resource contains a symlink")
            if path.is_file():
                actual_files.add(path.relative_to(installed_root).as_posix())
        if actual_files != expected_files:
            raise ValueError("installed resource inventory differs from the allowlist")
        for name in {"manifest.json", "license-files.json"} | license_paths:
            if digest(regular(installed_root / name)) != digest(regular(RESOURCES / name)):
                raise ValueError("installed metadata or original license changed: " + name)

    excluded = [{"path": name, "bytes": regular(RESOURCES / name).stat().st_size}
                for name in EXCLUDED_METADATA]
    return {"ok": True, "stagedPayloadChecked": staged or bool(installed_root),
            "installedInventoryChecked": bool(installed_root), "modelFiles": len(model_names),
            "modelBytes": sum(entry["size"] for entry in manifest["files"]),
            "originalNotices": len(notices["files"]), "allLicenseFiles": len(license_paths),
            "expectedRuntimeFiles": len(file_names | license_paths),
            "excludedBuildMetadata": excluded,
            "excludedUncompressedBytes": sum(entry["bytes"] for entry in excluded),
            "sourceArchiveRequiredSeparately": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true")
    parser.add_argument("--installed-root", type=Path,
                        help="installed offline-translation resource directory")
    args = parser.parse_args()
    print(json.dumps(inventory(args.staged, args.installed_root), sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Windows resource audit failed: " + str(error), file=sys.stderr)
        sys.exit(1)
