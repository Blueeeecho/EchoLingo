#!/usr/bin/env python3
"""Statically inspect a fresh 0.2.6 installer; never run, install or re-sign it.

The two --*-passed flags are explicit workflow attestations, not substitutes
for running a locked build and focused tests first. --output-dir must be new.
On macOS pass the freshly signed bundle executable (or its .app directory),
not the unsigned pre-bundling executable. Only successful inspection writes
checks.json. Native commands require their matching OS; tests use generated
metadata/bytes and do not claim installer or interactive acceptance.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import threading
import tempfile
import tomllib

VERSION = "0.2.6"
ROOT = Path(__file__).resolve().parents[1]
MAX_MEMBERS = 20000
MAX_LISTING = 16 * 1024 * 1024
MAX_EXECUTABLE = 512 * 1024 * 1024
RUN_URL = re.compile(r"https://github\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+/actions/runs/[1-9][0-9]*")


class InspectionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InspectionError(message)


def command_failure(result):
    args = [str(item) for item in result.args]
    name = Path(args[0]).name
    label = name
    detail = ""
    if name == "hdiutil" and len(args) > 1 and args[1] in {"verify", "attach", "detach"}:
        label += " " + args[1]
        # Only this system tool's error stream is surfaced, never attachment
        # stdout (which may contain a license), plist contents or archive data.
        # Bound output and redact absolute paths/URLs/control characters first.
        text = (result.stderr or b"")[:2048].decode("utf-8", errors="replace")
        for argument in sorted(args[2:], key=len, reverse=True):
            if Path(argument).is_absolute():
                text = text.replace(argument, "<path>")
        text = re.sub(r"https?://\S+", "<url>", text)
        text = re.sub(r"(?:[A-Za-z]:[\\/]|/)[^\s\"'<>]+", "<path>", text)
        text = " ".join("".join(c if c.isprintable() else " " for c in text).split())[:512]
        detail = "; stderr: " + (text or "<empty>")
    return f"{label} failed (exit {result.returncode}){detail}"


def checked_command(command, *, env=None, check=True, maximum_bytes=MAX_LISTING):
    # Bound stdout while reading (not after capture_output has allocated it).
    # stderr is a private temporary stream, never a candidate-content log.
    args = [str(item) for item in command]
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=errors, env=env)
        timer = threading.Timer(180, process.kill)
        timer.start()
        try:
            chunks, total = [], 0
            for chunk in iter(lambda: process.stdout.read(1024 * 1024), b""):
                total += len(chunk)
                require(total <= maximum_bytes, "Inspection command output exceeds limit")
                chunks.append(chunk)
            code = process.wait(timeout=5)
            require(errors.tell() <= maximum_bytes, "Inspection command error output exceeds limit")
            errors.seek(0)
            result = subprocess.CompletedProcess(args, code, b"".join(chunks), errors.read(maximum_bytes))
            if check:
                require(code == 0, command_failure(result))
            return result
        finally:
            timer.cancel()
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
            process.stdout.close()


def tool(name):
    result = shutil.which(name)
    require(result is not None, f"Required inspection tool is unavailable: {name}")
    return result


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def regular_file(path):
    path = Path(path)
    require(not path.is_symlink() and path.is_file(), "Expected a regular non-symlink file")
    require(not getattr(path.lstat(), "st_file_attributes", 0) & 0x400, "Reparse-point input is forbidden")
    require(stat.S_ISREG(path.stat().st_mode), "Expected a regular file")
    return path.resolve(strict=True)


def source_identity(root=ROOT):
    root = Path(root)
    def git(*args):
        return checked_command(["git", "-C", root, *args]).stdout.decode("utf-8").strip()
    require(Path(git("rev-parse", "--show-toplevel")).resolve() == root.resolve(), "Expected the worktree root")
    require(not git("status", "--porcelain=v1", "--untracked-files=no"), "Tracked checkout is not clean")
    commit, tree = git("rev-parse", "HEAD", "HEAD^{tree}").splitlines()
    require(all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (commit, tree)), "Invalid source identity")
    versions = [json.loads((root / "package.json").read_text(encoding="utf-8"))["version"],
                json.loads((root / "src-tauri/tauri.conf.json").read_text(encoding="utf-8"))["version"],
                tomllib.loads((root / "src-tauri/Cargo.toml").read_text(encoding="utf-8"))["package"]["version"]]
    require(versions == [VERSION] * 3, "Only the exact 0.2.6 candidate may be inspected")
    return commit, tree


def member_path(value):
    require(isinstance(value, str) and value, "Empty archive member path")
    require(not value.startswith(("/", "\\", "@")) and not any(ord(c) < 32 or ord(c) == 127 for c in value),
            "Unsafe archive member path")
    require(not any(c in value for c in ':*?<>"|'), "Unsafe archive member path")
    parts = value.replace("\\", "/").split("/")
    require(all(part not in ("", ".", "..") and part == part.rstrip(" .") for part in parts),
            "Traversal or aliased archive member path")
    return "/".join(parts)


def parse_7z_listing(text, expected_application_size=None):
    """Parse 7z l -slt, retaining exact member names for literal extraction."""
    require(len(text.encode("utf-8")) <= MAX_LISTING, "Archive listing exceeds limit")
    text = text.replace("\r\n", "\n")
    require(text.count("\n----------\n") == 1, "Missing or ambiguous 7-Zip member boundary")
    header, body = text.split("\n----------\n", 1)
    require(re.findall(r"^Type = (.+)$", header, re.M) == ["Nsis"], "Expected a single NSIS installer")
    records, seen = [], set()
    for block in re.split(r"\n\s*\n", body.strip()):
        record = {}
        for line in block.splitlines():
            require(" = " in line, "Malformed archive listing record")
            key, value = line.split(" = ", 1)
            require(key and key not in record, "Duplicate archive listing field")
            record[key] = value
        path = member_path(record.get("Path"))
        key = path.casefold()
        require(key not in seen, "Duplicate or case-aliased archive member")
        seen.add(key)
        for field in ("Symbolic Link", "Hard Link", "Link", "Copy Link", "Reparse"):
            require(not record.get(field), "Archive links are forbidden")
        require(record.get("Links", "1") in ("", "0", "1"), "Archive hard links are forbidden")
        attributes = record.get("Attributes", "")
        require("L" not in attributes and not re.search(r"(^|\s)l[rwx-]{9}", attributes), "Archive links are forbidden")
        mode = record.get("Mode", "")
        require(not mode.startswith("l"), "Archive links are forbidden")
        require(record.get("Encrypted", "-") in ("", "-"), "Encrypted archive member")
        require(record.get("Anti", "-") in ("", "-"), "Deleted archive member")
        require(record.get("Alternate Stream", "-") in ("", "-"), "Alternate data stream")
        size_text = record.get("Size", "")
        # The official NSIS handler can leave kpidSize unset when unknown.
        # Ignored members are never extracted; only the selected app needs a
        # numeric size to bound and verify its stdout-only extraction.
        # https://github.com/ip7z/7zip/blob/main/CPP/7zip/Archive/Nsis/NsisHandler.cpp
        require(not size_text or re.fullmatch(r"[0-9]+", size_text) is not None, "Invalid archive member size")
        record["normalizedPath"] = path
        record["size"] = int(size_text) if size_text else None
        record["directory"] = record.get("Folder") == "+" or "D" in attributes
        records.append(record)
        require(len(records) <= MAX_MEMBERS, "Too many archive members")
    require(records, "Installer has no members")
    files = {r["normalizedPath"].casefold() for r in records if not r["directory"]}
    for record in records:
        parts = record["normalizedPath"].casefold().split("/")
        require(not any("/".join(parts[:i]) in files for i in range(1, len(parts))), "Archive file/directory collision")
    candidates = [r for r in records if r["normalizedPath"].split("/")[-1].casefold() == "echolingo.exe"]
    require(len(candidates) == 1 and not candidates[0]["directory"], "Expected exactly one echolingo.exe member")
    selected = candidates[0]
    if expected_application_size is not None:
        require(type(expected_application_size) is int and 0 < expected_application_size <= MAX_EXECUTABLE,
                "Fresh application size exceeds limit")
        require(selected["size"] is None or selected["size"] == expected_application_size,
                "Application listing size differs from fresh application")
        selected["size"] = expected_application_size
    require(type(selected["size"]) is int and 0 < selected["size"] <= MAX_EXECUTABLE,
            "Application member size is missing or exceeds limit")
    return selected


def extract_windows_member(seven_zip, installer, member, target):
    # -so means the archive tool writes no archive-chosen filesystem path.
    # -spd disables wildcard matching; -- terminates switch interpretation.
    command = [seven_zip, "e", "-so", "-spd", "--", str(installer), member["Path"]]
    with target.open("xb") as output, (target.parent / "7z-extract.stderr").open("xb") as errors:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=errors)
        timer = threading.Timer(180, process.kill)
        timer.start()
        try:
            total = 0
            # At most one byte past the exact known application length is read
            # to detect an oversized stream. No archive-controlled allocation.
            for chunk in iter(lambda: process.stdout.read(min(1024 * 1024, member["size"] - total + 1)), b""):
                total += len(chunk)
                require(total <= member["size"] and total <= MAX_EXECUTABLE, "Extracted application exceeds expected size")
                output.write(chunk)
            require(process.wait(timeout=5) == 0, "7-Zip extraction failed")
            require(total == member["size"], "Extracted application size differs from fresh application")
        finally:
            timer.cancel()
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
            process.stdout.close()


def verify_pe(path):
    with regular_file(path).open("rb") as stream:
        header = stream.read(64)
        require(len(header) == 64 and header[:2] == b"MZ", "Application is not PE")
        offset = struct.unpack_from("<I", header, 60)[0]
        require(64 <= offset <= path.stat().st_size - 26, "Invalid PE header offset")
        stream.seek(offset)
        header = stream.read(26)
        require(len(header) == 26 and header[:4] == b"PE\0\0", "Invalid PE signature")
        machine, sections, _, _, _, optional_size, flags, magic = struct.unpack_from("<HHIIIHHH", header, 4)
        require(machine == 0x8664 and magic == 0x20B, "Application is not PE x64")
        require(0 < sections <= 96 and optional_size >= 112 and flags & 2 and not flags & 0x2000,
                "PE is not an executable image")
        require(offset + 24 + optional_size + sections * 40 <= path.stat().st_size, "Truncated PE headers")


def verify_windows_version(value):
    require(isinstance(value, dict) and set(value) == {"fileVersion", "productVersion", "fileParts", "productParts"},
            "Invalid Windows version metadata")
    for key in ("fileVersion", "productVersion"):
        require(value[key] in (VERSION, VERSION + ".0"), "Windows file/product version is not 0.2.6")
    for key in ("fileParts", "productParts"):
        require(isinstance(value[key], list) and all(type(n) is int for n in value[key])
                and value[key] == [0, 2, 6, 0], "Windows numeric file/product version is not 0.2.6")


def inspect_windows(installer, output, expected_application_size):
    seven_zip = tool("7z")
    listing = checked_command([seven_zip, "l", "-slt", "-sccUTF-8", "--", installer]).stdout.decode("utf-8")
    (output / "7z-listing.txt").write_text(listing, encoding="utf-8")
    member = parse_7z_listing(listing, expected_application_size)
    target = output / "echolingo.exe"
    extract_windows_member(seven_zip, installer, member, target)
    verify_pe(target)
    command = '''$ErrorActionPreference = 'Stop';
$v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($env:ECHOLINGO_INSPECT_APPLICATION);
[ordered]@{fileVersion=$v.FileVersion;productVersion=$v.ProductVersion;
fileParts=@($v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart,$v.FilePrivatePart);
productParts=@($v.ProductMajorPart,$v.ProductMinorPart,$v.ProductBuildPart,$v.ProductPrivatePart)} | ConvertTo-Json -Compress'''
    env = dict(os.environ, ECHOLINGO_INSPECT_APPLICATION=str(target))
    result = checked_command([tool("powershell"), "-NoProfile", "-NonInteractive", "-Command", command], env=env)
    verify_windows_version(json.loads(result.stdout.decode("utf-8-sig")))
    return target


def verify_macho(path):
    with regular_file(path).open("rb") as stream:
        header = stream.read(32)
    require(len(header) == 32 and header[:4] == b"\xcf\xfa\xed\xfe", "Expected a thin 64-bit Mach-O")
    cpu, _, filetype = struct.unpack_from("<III", header, 4)
    require(cpu == 0x0100000C and filetype == 2, "Application is not an arm64 Mach-O executable")


def owned_bundle_file(bundle, relative):
    bundle = Path(bundle)
    require(bundle.is_dir() and not bundle.is_symlink(), "Application bundle cannot be a symlink")
    current = bundle
    for part in Path(relative).parts:
        require(part not in ("", ".", "..") and not Path(part).is_absolute(), "Unsafe bundle member")
        current = current / part
        require(not current.is_symlink(), "Bundle metadata/executable path cannot contain a symlink")
    result = regular_file(current)
    require(result.is_relative_to(bundle.resolve(strict=True)), "Bundle member escapes application")
    return result


def attachment_entities(data):
    value = plistlib.loads(data)
    require(isinstance(value, dict) and isinstance(value.get("system-entities"), list), "Malformed disk-image attachment metadata")
    entities = value["system-entities"]
    require(all(isinstance(entity, dict) for entity in entities), "Malformed attachment entity")
    return entities


def attachment_device(data):
    devices = [entity.get("dev-entry") for entity in attachment_entities(data) if entity.get("dev-entry")]
    require(devices and all(isinstance(device, str) and re.fullmatch(r"/dev/disk[0-9]+(?:s[0-9]+)*", device) for device in devices),
            "Invalid disk-image device metadata")
    roots = [device for device in devices if re.fullmatch(r"/dev/disk[0-9]+", device)]
    require(len(roots) == 1, "Expected exactly one attached image device")
    require(all(device == roots[0] or device.startswith(roots[0] + "s") for device in devices), "Unrelated attached image devices")
    return roots[0]


def validate_attach_result(data, mountpoint):
    device = attachment_device(data)
    mounts = [entity["mount-point"] for entity in attachment_entities(data) if "mount-point" in entity]
    require(mounts == [str(mountpoint)], "Disk image did not mount only at the owned mountpoint")
    return device


@contextmanager
def readonly_dmg(installer, mountpoint):
    hdiutil = tool("hdiutil")
    checked_command([hdiutil, "verify", installer])
    mountpoint.mkdir()
    detach_target = str(mountpoint)
    primary_error = None
    # Even an attach failure may leave a mount behind. Always attempt cleanup
    # of only the freshly owned mountpoint/device, never a pre-existing volume.
    try:
        result = checked_command([hdiutil, "attach", "-readonly", "-nobrowse", "-noautoopen", "-plist",
                                  "-mountpoint", mountpoint, installer], check=False)
        # A failed attach can still report an allocated but unmounted device.
        # Retain that exact operation's device before checking mount/exit state.
        if result.stdout:
            try:
                detach_target = attachment_device(result.stdout)
            except (ValueError, TypeError, plistlib.InvalidFileException):
                # Nonzero attach may emit a human-readable prompt rather than
                # plist. Preserve its real error; do not parse a device from text.
                if result.returncode == 0:
                    raise InspectionError("hdiutil attach returned invalid device metadata")
        require(result.returncode == 0, command_failure(result))
        validate_attach_result(result.stdout, mountpoint)
        yield mountpoint
    except BaseException as error:
        primary_error = error
        raise
    finally:
        try:
            checked_command([hdiutil, "detach", detach_target])
        except Exception as cleanup_error:
            if primary_error is None:
                raise
            # A failed attach commonly has nothing to detach. Cleanup remains
            # required and scoped, but must not replace the actionable failure.
            raise InspectionError(f"{primary_error}; cleanup also failed: {cleanup_error}") from primary_error


def inspect_macos(installer, output):
    with readonly_dmg(installer, output / "mount") as volume:
        applications = [path for path in volume.iterdir() if path.name.casefold().endswith(".app")]
        require(len(applications) == 1 and applications[0].name == "EchoLingo.app", "Expected exactly one EchoLingo.app at image root")
        bundle = applications[0]
        info = owned_bundle_file(bundle, "Contents/Info.plist")
        plutil = tool("plutil")
        version = checked_command([plutil, "-extract", "CFBundleShortVersionString", "raw", "-o", "-", info]).stdout.decode("utf-8").strip()
        executable = checked_command([plutil, "-extract", "CFBundleExecutable", "raw", "-o", "-", info]).stdout.decode("utf-8").strip()
        build_version = checked_command([plutil, "-extract", "CFBundleVersion", "raw", "-o", "-", info]).stdout.decode("utf-8").strip()
        identifier = checked_command([plutil, "-extract", "CFBundleIdentifier", "raw", "-o", "-", info]).stdout.decode("utf-8").strip()
        require(version == VERSION and build_version == VERSION and executable == "echolingo"
                and identifier == "io.github.blueeeecho.echolingo", "Unexpected macOS bundle identity, version or executable")
        application = owned_bundle_file(bundle, "Contents/MacOS/" + executable)
        verify_macho(application)
        codesign = tool("codesign")
        checked_command([codesign, "--verify", "--deep", "--strict", "--verbose=2", bundle])
        signature = checked_command([codesign, "-d", "--verbose=4", bundle])
        details = (signature.stdout + signature.stderr).decode("utf-8")
        require(re.search(r"^Signature=adhoc$", details, re.M) is not None, "Expected the existing ad-hoc signature")
        target = output / "echolingo"
        # Copy bytes only, not permissions/xattrs; this file is never executed.
        with application.open("rb") as source, target.open("xb") as destination:
            shutil.copyfileobj(source, destination, length=1024 * 1024)
        require(sha256(target) == sha256(application), "Packaged application changed during inspection")
    return target


def inspect(platform, installer, built_application, output, run_url, *, locked_build_passed=False,
            focused_tests_passed=False, root=ROOT):
    require(locked_build_passed is True and focused_tests_passed is True, "Locked build and focused-test attestations are required")
    require(platform in ("Windows", "macOS"), "Unsupported candidate platform")
    require((platform == "Windows" and sys.platform == "win32") or (platform == "macOS" and sys.platform == "darwin"),
            "Native installer inspection requires the matching operating system")
    require(RUN_URL.fullmatch(run_url) is not None, "Expected a canonical GitHub Actions run URL")
    commit, tree = source_identity(root)
    installer = regular_file(installer)
    allowed = {"Windows": {f"echolingo_{VERSION}_x64-setup.exe"},
               "macOS": {f"echolingo_{VERSION}_aarch64.dmg", f"echolingo_{VERSION}_arm64.dmg"}}
    require(installer.name.casefold() in allowed[platform], "Unexpected candidate installer name")
    built_application = Path(built_application)
    if platform == "macOS" and built_application.name == "EchoLingo.app":
        built_application = owned_bundle_file(built_application, "Contents/MacOS/echolingo")
    built_application = regular_file(built_application)
    require(built_application.name.casefold() == ("echolingo.exe" if platform == "Windows" else "echolingo"),
            "Unexpected built application name")
    installer_hash, built_hash = sha256(installer), sha256(built_application)
    output = Path(output)
    require(not output.exists() and not output.is_symlink(), "Inspection output must be a new directory")
    output.mkdir(parents=True)
    output = output.resolve(strict=True)
    application = inspect_windows(installer, output, built_application.stat().st_size) if platform == "Windows" else inspect_macos(installer, output)
    extracted_hash = sha256(regular_file(application))
    require(extracted_hash == built_hash, "Installer application does not match freshly built application")
    require(sha256(installer) == installer_hash and sha256(built_application) == built_hash, "Build inputs changed during inspection")
    require(source_identity(root) == (commit, tree), "Source identity changed during inspection")
    report = {"schemaVersion": 1, "platform": platform, "version": VERSION,
              "commit": commit, "tree": tree, "runUrl": run_url,
              "checks": {"lockedBuild": True, "focusedTestsPassed": True,
                         "installerStructureVerified": True, "applicationMetadataVerified": True,
                         "installerApplicationMatches": True},
              "applicationMetadata": {"version": VERSION, "architecture": "x64" if platform == "Windows" else "arm64"},
              "installerSha256": installer_hash, "applicationSha256": extracted_hash,
              "extractedApplicationSha256": extracted_hash}
    with (output / "checks.json").open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("Windows", "macOS"), required=True)
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--built-application", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--locked-build-passed", action="store_true")
    parser.add_argument("--focused-tests-passed", action="store_true")
    args = parser.parse_args()
    try:
        report = inspect(args.platform, args.installer, args.built_application, args.output_dir, args.run_url,
                         locked_build_passed=args.locked_build_passed, focused_tests_passed=args.focused_tests_passed)
    except (InspectionError, OSError, subprocess.SubprocessError, UnicodeError, json.JSONDecodeError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Candidate inspection failed: {error}\n")
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
