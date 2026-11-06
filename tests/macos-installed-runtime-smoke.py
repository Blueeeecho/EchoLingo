#!/usr/bin/env python3
"""Real packaged WKWebView smoke, restricted to a fresh macOS Actions runner.

No fake IPC, UI automation, permission grants, signing, quarantine changes,
clipboard reads or screenshots. The two native flags attest to earlier tests
in the same job; they are not performed by this script. Linux contract tests
exercise guards and metadata only, and are not runtime acceptance.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "io.github.blueeeecho.echolingo"
VERSION = "0.2.17"
RUN_URL = re.compile(r"https://github\.com/Blueeeecho/EchoLingo/actions/runs/[1-9][0-9]*")
MAX_DIAGNOSTIC_BYTES = 128 * 1024


class SmokeError(Exception):
    """Only fixed error codes are written to evidence, never application logs."""


def require(condition, code):
    if not condition:
        raise SmokeError(code)


def command(args, timeout=30):
    # Every invoked tool here emits bounded metadata, never user content.
    result = subprocess.run([str(a) for a in args], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            timeout=timeout, check=False)
    require(result.returncode == 0, "metadata_command_failed")
    require(len(result.stdout) <= 1024 * 1024, "metadata_output_too_large")
    return result.stdout


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_manifest(bundle):
    """Identity includes every file, symlink target and POSIX mode, not mtimes.

    Never follows symlinks while walking; external links are rejected. Xattrs
    are preserved by ditto and the unchanged signed bundle is verified again.
    """
    bundle = Path(bundle)
    require(bundle.is_dir() and not bundle.is_symlink(), "invalid_bundle")
    manifest = {}
    for directory, dirs, files in os.walk(bundle, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(directory) / name
            relative = path.relative_to(bundle).as_posix()
            metadata = path.lstat()
            mode = stat.S_IMODE(metadata.st_mode)
            if path.is_symlink():
                target = os.readlink(path)
                require(path.resolve().is_relative_to(bundle.resolve()), "external_bundle_symlink")
                manifest[relative] = ["symlink", mode, target]
            elif stat.S_ISREG(metadata.st_mode):
                manifest[relative] = ["file", mode, sha256(path)]
            elif stat.S_ISDIR(metadata.st_mode):
                manifest[relative] = ["directory", mode]
            else:
                raise SmokeError("unsupported_bundle_member")
            require(len(manifest) <= 20000, "bundle_too_large")
    return manifest


def manifest_digest(manifest):
    return hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def validate_bundle(bundle):
    with (bundle / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("CFBundleIdentifier") == BUNDLE_ID
            and info.get("CFBundleExecutable") == "echolingo"
            and info.get("CFBundleShortVersionString") == VERSION
            and info.get("CFBundleVersion") == VERSION,
            "bundle_identity_mismatch")
    binary = bundle / "Contents/MacOS/echolingo"
    require(binary.is_file() and not binary.is_symlink(), "invalid_executable")
    return binary


def require_runner():
    require(sys.platform == "darwin" and os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_OS") == "macOS", "fresh_macos_actions_runner_required")
    home = Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()
    require(Path.home().resolve() == home, "real_runner_home_required")
    return home


def state_paths(home):
    # Only these exact app-owned paths may be removed, and only after all were
    # proved absent before launch. Never enumerate/read existing user files.
    library = home / "Library"
    return [library / suffix for suffix in (
        f"Application Support/{BUNDLE_ID}", f"Caches/{BUNDLE_ID}",
        f"WebKit/{BUNDLE_ID}", f"HTTPStorages/{BUNDLE_ID}",
        f"HTTPStorages/{BUNDLE_ID}.binarycookies", f"Preferences/{BUNDLE_ID}.plist",
        f"Saved Application State/{BUNDLE_ID}.savedState", f"Logs/{BUNDLE_ID}",
        f"Containers/{BUNDLE_ID}", "Application Support/EchoLingo", "Caches/EchoLingo",
        "WebKit/EchoLingo", "Logs/EchoLingo",
    )]


def require_absent_state(paths):
    for path in paths:
        require(not os.path.lexists(path), "preexisting_app_state")
        require(not any(parent.is_symlink() for parent in path.parents), "symlink_state_parent")


def app_pids():
    result = subprocess.run(["pgrep", "-ix", "echolingo"], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
    require(result.returncode in (0, 1), "process_inventory_failed")
    return {int(value) for value in result.stdout.split()}


def frontend_ready(path, pid):
    # This is the sole generated app file read. It contains only opt-in input
    # event metadata. A stale first-launch file cannot satisfy restart readiness.
    if not path.is_file() or path.is_symlink():
        return False
    try:
        with path.open("rb") as stream:
            raw = stream.read(MAX_DIAGNOSTIC_BYTES + 1)
        require(len(raw) <= MAX_DIAGNOSTIC_BYTES, "diagnostic_too_large")
        value = json.loads(raw)
    except (OSError, ValueError):
        return False  # The production writer may be between truncate and write.
    return (isinstance(value, dict) and type(value.get("processId")) is int
            and value["processId"] == pid and isinstance(value.get("entries"), list)
            and any(isinstance(row, dict) and row.get("stage") == "ready"
                    for row in value["entries"]))


def window_shown(probe, pid):
    value = json.loads(command([probe, str(pid)], timeout=10))
    return (value.get("bundleIdentifier") == BUNDLE_ID and value.get("processId") == pid
            and type(value.get("onscreenAppWindowCount")) is int
            and value["onscreenAppWindowCount"] >= 1
            and value.get("applicationActivationPolicy") == 1
            and value.get("applicationIsHidden") is False
            and value.get("screenshotsTaken") is False
            and value.get("permissionRequestsMade") is False)


def await_ready(process, diagnostic, probe, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        require(process.poll() is None, "release_process_exited_early")
        if frontend_ready(diagnostic, process.pid) and window_shown(probe, process.pid):
            return
        time.sleep(0.25)
    raise SmokeError("webview_or_settings_deadline")


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)


def remove_owned_state(paths):
    for path in paths:
        require(not any(parent.is_symlink() for parent in path.parents), "cleanup_symlink_parent")
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.exists():
            shutil.rmtree(path)
    return all(not os.path.lexists(path) for path in paths)


def run(args):
    report = dict(version=VERSION, commit=None, tree=None, runUrl=args.run_url,
                  installerSha256=None, applicationSha256=None, ok=False,
                  extractedBundleLaunched=False, frontendWebViewReady=False,
                  settingsWindowShown=False, nativeSelfTestsPassed=args.native_self_tests_passed,
                  nativeWindowResizeFixturePassed=args.native_window_resize_fixture_passed,
                  packageUnchangedAfterRun=False, cleanupComplete=False,
                  fakeIpcUsed=False, userContentRead=False, codexInteractiveSelectionTested=False,
                  restartPassed=False, secondInstancePassed=False)
    owned_paths, children, temporary = [], [], None
    mount_clean = True
    stage = "runner_preflight"
    try:
        home = require_runner()
        require(RUN_URL.fullmatch(args.run_url) is not None, "invalid_run_url")
        require(args.native_self_tests_passed and args.native_window_resize_fixture_passed,
                "native_prerequisites_missing")
        require(not app_pids(), "preexisting_app_process")
        paths = state_paths(home)
        require_absent_state(paths)
        # No cleanup authority is acquired until every preflight guard passes.
        owned_paths = paths
        stage = "source_identity"
        report["commit"], report["tree"] = command(
            ["git", "-C", ROOT, "rev-parse", "HEAD", "HEAD^{tree}"]).decode().splitlines()
        require(all(re.fullmatch(r"[0-9a-f]{40}", report[key]) for key in ("commit", "tree")),
                "invalid_source_identity")
        require(not command(["git", "-C", ROOT, "status", "--porcelain=v1", "--untracked-files=no"]),
                "tracked_source_not_clean")
        stage = "built_bundle_identity"
        installer = args.installer.resolve(strict=True)
        built = args.built_application.resolve(strict=True)
        require(installer.is_file() and installer.suffix.lower() == ".dmg", "invalid_installer")
        validate_bundle(built)
        built_manifest = bundle_manifest(built)
        report["installerSha256"] = sha256(installer)
        stage = "temporary_directory"
        temporary = Path(tempfile.mkdtemp(prefix="echolingo-runtime-", suffix=".noindex"))
        # hdiutil reports canonical /private/var paths on macOS even when
        # tempfile used /var. Keep strict mount identity checks unchanged.
        temporary = temporary.resolve(strict=True)
        stage = "window_probe_build"
        probe = temporary / "window-probe"
        command(["xcrun", "swiftc", ROOT / "tests/macos-window-probe.swift", "-o", probe], timeout=120)
        stage = "package_inspector_load"
        spec = importlib.util.spec_from_file_location("candidate_inspection", ROOT / "scripts/inspect-candidate-package.py")
        inspection = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(inspection)
        installed = temporary / "EchoLingo.app"
        mount_clean = False
        stage = "dmg_mount"
        with inspection.readonly_dmg(installer, temporary / "mount") as volume:
            stage = "packaged_bundle_identity"
            applications = [p for p in volume.iterdir() if p.name.casefold().endswith(".app")]
            require(len(applications) == 1 and applications[0].name == "EchoLingo.app", "unexpected_dmg_apps")
            packaged = applications[0]
            validate_bundle(packaged)
            require(bundle_manifest(packaged) == built_manifest, "package_differs_from_fresh_build")
            stage = "packaged_bundle_copy"
            command(["ditto", "--rsrc", "--extattr", packaged, installed], timeout=120)
            stage = "dmg_detach"
        mount_clean = True
        stage = "installed_bundle_verification"
        require(bundle_manifest(installed) == built_manifest, "copied_bundle_changed")
        binary = validate_bundle(installed)
        report["applicationSha256"] = sha256(binary)
        report["bundleManifestSha256"] = manifest_digest(built_manifest)
        command(["codesign", "--verify", "--deep", "--strict", installed])
        # Preserve the actual runner HOME: Cocoa may ignore a synthetic HOME.
        env = os.environ.copy()
        for name in list(env):
            if name.startswith("ECHOLINGO_"):
                del env[name]
        env["ECHOLINGO_INPUT_DIAGNOSTICS"] = "1"
        diagnostic = paths[0] / "frontend-input-diagnostics.json"
        def launch():
            child = subprocess.Popen([str(binary), "--configure-shortcuts"], env=env,
                                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, cwd=temporary)
            children.append(child)
            return child
        stage = "first_launch"
        first = launch()
        stage = "first_webview_and_window"
        await_ready(first, diagnostic, probe)
        report.update(extractedBundleLaunched=True, frontendWebViewReady=True, settingsWindowShown=True)
        stage = "second_instance"
        second = launch()
        require(second.wait(timeout=20) == 0, "second_instance_failed")
        require(first.poll() is None and app_pids() == {first.pid}, "single_instance_invariant_failed")
        require(window_shown(probe, first.pid), "second_instance_window_missing")
        report["secondInstancePassed"] = True
        stage = "first_termination"
        stop(first)
        require(not app_pids(), "first_process_did_not_stop")
        stage = "restart_launch"
        restarted = launch()
        stage = "restart_webview_and_window"
        await_ready(restarted, diagnostic, probe)
        require(restarted.pid != first.pid, "restart_pid_reused")
        report["restartPassed"] = True
        stage = "restart_termination"
        stop(restarted)
        stage = "post_run_package_verification"
        report["packageUnchangedAfterRun"] = (
            sha256(installer) == report["installerSha256"]
            and bundle_manifest(installed) == built_manifest
            and bundle_manifest(built) == built_manifest)
        require(report["packageUnchangedAfterRun"], "package_changed_after_run")
        command(["codesign", "--verify", "--deep", "--strict", installed])
        report["ok"] = True
    except Exception as error:
        report["failureStage"] = stage
        report["failureCode"] = str(error) if isinstance(error, SmokeError) else type(error).__name__
    finally:
        cleanup_ok = mount_clean
        for child in reversed(children):
            try:
                stop(child)
            except Exception:
                cleanup_ok = False
        try:
            # Never remove an attached volume or delete app state under a live app.
            if owned_paths:
                require(not app_pids(), "live_process_blocks_cleanup")
                cleanup_ok = remove_owned_state(owned_paths) and cleanup_ok
            if temporary is not None and mount_clean:
                shutil.rmtree(temporary)
                cleanup_ok = not temporary.exists() and cleanup_ok
        except Exception:
            cleanup_ok = False
        if not cleanup_ok and "failureStage" not in report:
            report["failureStage"] = "cleanup"
            report["failureCode"] = "cleanup_incomplete"
        report["cleanupComplete"] = cleanup_ok
        report["ok"] = report["ok"] and cleanup_ok
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installer", required=True, type=Path)
    parser.add_argument("--built-application", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--native-self-tests-passed", action="store_true")
    parser.add_argument("--native-window-resize-fixture-passed", action="store_true")
    args = parser.parse_args()
    report = run(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("ok", "cleanupComplete", "failureCode", "failureStage") if key in report}))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
