#!/usr/bin/env python3
"""Local EchoLingo preview inventory, transactional installation and process metrics.

Uses Python's standard library and built-in macOS tools. It never reads application
settings, history, credentials, clipboard contents, screenshots or process arguments.
"""

from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import uuid
from typing import Callable


BUNDLE_ID = "io.github.blueeeecho.echolingo"
REPO = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = REPO / "src-tauri/target/release/bundle/macos/EchoLingo.app"
DEFAULT_DESTINATION = Path.home() / "Applications/EchoLingo.app"


class PreviewError(RuntimeError):
    pass


def absolute(path: str | Path) -> Path:
    return Path(os.path.abspath(Path(path).expanduser()))


def require_macos() -> None:
    if sys.platform != "darwin":
        raise PreviewError("This command requires macOS. Fixture tests run on other platforms.")


def run(args: list[str], timeout: float = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, check=True, timeout=timeout)


def bundle_metadata(path: Path) -> dict:
    """Validate bundle identity before trusting its executable or replacing a copy."""
    path = absolute(path)
    if path.is_symlink() or path.suffix != ".app" or not path.is_dir():
        raise PreviewError(f"Expected a real .app directory, not a symlink: {path}")
    # Resolve ancestor aliases once; use this identity for copying, signing and
    # matching proc_pidpath (which normally returns the resolved executable).
    path = path.resolve(strict=True)
    info_path = path / "Contents/Info.plist"
    if info_path.is_symlink() or not info_path.is_file() or info_path.stat().st_size > 1024 * 1024:
        raise PreviewError(f"Missing or unsafe Info.plist: {path}")
    try:
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
    except (ValueError, plistlib.InvalidFileException) as exc:
        raise PreviewError(f"Invalid Info.plist: {path}") from exc
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise PreviewError(f"Bundle identifier is not {BUNDLE_ID}: {path}")
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or executable != "echolingo":
        raise PreviewError(f"Unexpected EchoLingo executable in bundle: {path}")
    binary = path / "Contents/MacOS" / executable
    if (binary.is_symlink() or not binary.is_file() or not os.access(binary, os.X_OK)
            or not binary.resolve().is_relative_to(path.resolve())):
        raise PreviewError(f"Missing, non-executable or unsafe app executable: {path}")
    return {
        "path": str(path),
        "bundle_id": BUNDLE_ID,
        "version": str(info.get("CFBundleShortVersionString", "unknown")),
        "executable": str(binary.resolve(strict=True)),
    }


def verify_bundle(path: Path) -> dict:
    metadata = bundle_metadata(path)
    path = Path(metadata["path"])
    try:
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(path)])
        details = run(["/usr/bin/codesign", "-d", "--verbose=4", str(path)])
    except subprocess.CalledProcessError as exc:
        raise PreviewError(f"Code signature verification failed: {path}\n{exc.stderr.strip()}") from exc
    fields = dict(line.split("=", 1) for line in (details.stdout + details.stderr).splitlines() if "=" in line)
    if fields.get("Identifier") != BUNDLE_ID:
        raise PreviewError(f"Code signing identifier does not match bundle identifier: {path}")
    metadata["signature"] = {
        "verified": True,
        "identifier": fields["Identifier"],
        "kind": fields.get("Signature", "certificate"),
        "team_identifier": fields.get("TeamIdentifier", "unknown"),
        "cdhash": fields.get("CDHash", "unknown"),
        "gatekeeper_or_notarization_verified": False,
    }
    metadata["executable_sha256"] = file_sha256(Path(metadata["executable"]))
    return metadata


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file() and not item.is_symlink())


def process_path(pid: int) -> Path | None:
    # Apple libproc.h declares proc_pidpath(pid, buffer, buffersize). No argv read.
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)
    if library.proc_pidpath(pid, buffer, len(buffer)) <= 0:
        return None
    return Path(os.fsdecode(buffer.value)).resolve()


def echolingo_processes() -> list[dict]:
    processes = []
    # Deliberately omit command line arguments and environment from process data.
    rows = run(["/bin/ps", "-axo", "pid=,uid="]).stdout.splitlines()
    for row in rows:
        fields = row.split()
        if len(fields) != 2 or not all(field.isdigit() for field in fields):
            continue
        pid, uid = map(int, fields)
        if uid != os.getuid():
            continue
        binary = process_path(pid)
        if binary is None or binary.name.lower() != "echolingo":
            continue
        item = {"pid": pid, "uid": uid, "executable": str(binary), "verified": False}
        try:
            if binary.parent.name == "MacOS" and binary.parent.parent.name == "Contents":
                metadata = verify_bundle(binary.parent.parent.parent)
                if Path(metadata["executable"]).resolve() == binary.resolve():
                    item["verified"] = True
                    item["kind"] = "app_bundle"
            elif binary.resolve() in {
                (REPO / "src-tauri/target/debug/echolingo").resolve(),
                (REPO / "src-tauri/target/release/echolingo").resolve(),
            }:
                # Exact build output of this checkout; never match by name alone.
                item["verified"] = True
                item["kind"] = "this_checkout_build"
        except (PreviewError, OSError, subprocess.SubprocessError):
            pass
        processes.append(item)
    return processes


def stop_verified(processes: list[dict], timeout: float = 5) -> None:
    if any(not item["verified"] for item in processes):
        raise PreviewError("An unverifiable echolingo process exists. Quit it manually before installing; no processes stopped.")
    for item in processes:
        pid, executable = item["pid"], Path(item["executable"]).resolve()
        if process_path(pid) != executable:
            continue  # Exited or PID was reused since the inventory.
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not any(process_path(item["pid"]) == Path(item["executable"]).resolve() for item in processes):
            return
        time.sleep(0.05)
    raise PreviewError("EchoLingo did not exit after SIGTERM. Installation aborted; no forced kill was attempted.")


def install_paths(source: Path, destination: Path) -> tuple[Path, Path]:
    source, destination = absolute(source), absolute(destination)
    if destination.name != "EchoLingo.app" or destination.is_symlink():
        raise PreviewError("Destination must be a real path named EchoLingo.app, not a symlink.")
    if source.is_symlink():
        raise PreviewError("Source app must not be a symlink.")
    src, dst = source.resolve(), destination.resolve()
    if src == dst or src.is_relative_to(dst) or dst.is_relative_to(src):
        raise PreviewError("Source and destination must be separate, non-nested app paths.")
    return src, dst


def copy_bundle(source: Path, destination: Path) -> None:
    # ditto preserves bundle metadata/resource forks; staged signature is rechecked.
    run(["/usr/bin/ditto", "--rsrc", "--extattr", str(source), str(destination)])


def transactional_install(
    source: Path,
    destination: Path,
    *,
    verifier: Callable[[Path], dict] = verify_bundle,
    copier: Callable[[Path, Path], None] = copy_bundle,
    stop: Callable[[], None] = lambda: stop_verified(echolingo_processes()),
) -> dict:
    """Stage and verify before stopping app; keep previous app for easy recovery.

    Each rename is atomic on the destination filesystem. The pair of renames is
    not one atomic operation: interrupted installation may leave the old app at
    the reported backup path. It never deletes source or unrelated app copies.
    """
    source, destination = install_paths(source, destination)
    source_metadata = verifier(source)
    if destination.exists():
        verifier(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    lock = destination.parent / ".EchoLingo.preview-install.lock"
    try:
        lock.mkdir()
    except FileExistsError as exc:
        raise PreviewError(f"Another install or interrupted install holds {lock}. Inspect its transaction.json and app paths before removing the lock directory.") from exc
    stage: Path | None = None
    backup: Path | None = None
    moved_old = False
    moved_new = False
    rollback_failed = False
    journal = lock / "transaction.json"

    def checkpoint(phase: str) -> None:
        with journal.open("w", encoding="utf-8") as stream:
            json.dump({"installer_pid": os.getpid(), "source": str(source),
                       "destination": str(destination), "stage": str(stage) if stage else None,
                       "backup": str(backup) if backup else None, "phase": phase}, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())

    try:
        stage = Path(tempfile.mkdtemp(prefix=".echolingo-stage-", dir=destination.parent))
        checkpoint("staging")
        staged_app = stage / "EchoLingo.app"
        copier(source, staged_app)
        staged_metadata = verifier(staged_app)
        if staged_metadata.get("executable_sha256") != source_metadata.get("executable_sha256"):
            raise PreviewError("Staged executable differs from the verified source.")
        checkpoint("stopping_verified_instances")
        stop()
        # Revalidate target after staging, in case it changed while copying.
        if destination.exists() or destination.is_symlink():
            verifier(destination)
            suffix = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            backup = destination.parent / f".EchoLingo.backup-{suffix}-{uuid.uuid4().hex[:8]}.app"
            checkpoint("backing_up_old_app")
            destination.rename(backup)
            moved_old = True
        checkpoint("installing_new_app")
        staged_app.rename(destination)
        moved_new = True
        checkpoint("verifying_installed_app")
        installed = verifier(destination)
        if installed.get("executable_sha256") != source_metadata.get("executable_sha256"):
            raise PreviewError("Installed executable differs from the verified source.")
        return {"installed": installed, "backup": str(backup) if backup else None, "other_copies_deleted": False}
    except BaseException as exc:
        try:
            if moved_new and stage is not None:
                destination.rename(stage / "failed-install.app")
            if moved_old and backup is not None:
                backup.rename(destination)
        except OSError as rollback_error:
            rollback_failed = True
            raise PreviewError(f"Installation failed ({exc}); automatic rollback failed ({rollback_error}). Preserve stage {stage} and backup {backup} for recovery.") from exc
        raise
    finally:
        if stage is not None and not rollback_failed:
            shutil.rmtree(stage)
        if not rollback_failed:
            journal.unlink(missing_ok=True)
            lock.rmdir()


def find_bundles(roots: list[Path], max_depth: int) -> list[Path]:
    found: set[Path] = set()
    for root in roots:
        root = absolute(root)
        if root.suffix == ".app":
            found.add(root)
            continue
        if not root.is_dir():
            continue
        for current, dirs, _files in os.walk(root, followlinks=False):
            current_path = Path(current)
            depth = len(current_path.relative_to(root).parts)
            kept = []
            for name in sorted(dirs):
                path = current_path / name
                if path.suffix == ".app":
                    # Only inspect Info.plist for candidates; no app user data.
                    try:
                        bundle_metadata(path)
                        found.add(path)
                    except (PreviewError, OSError):
                        if "echolingo" in name.lower():
                            found.add(path)
                elif depth < max_depth and not name.startswith(".") and name not in {"node_modules", "target", "dist"}:
                    kept.append(name)
            dirs[:] = kept
    return sorted(found)


def inventory(extra_roots: list[str], max_depth: int) -> dict:
    roots = [Path.home() / "Applications", Path("/Applications"), REPO.parent,
             REPO / "src-tauri/target/release/bundle/macos",
             REPO / "src-tauri/target/debug/bundle/macos"]
    roots.extend(Path(path) for path in extra_roots)
    bundles = []
    for path in find_bundles(roots, max_depth):
        try:
            item = verify_bundle(path)
            item["bundle_bytes"] = bundle_size(path)
            item["canonical_installation"] = Path(item["path"]) == DEFAULT_DESTINATION.resolve()
            bundles.append(item)
        except (PreviewError, OSError, subprocess.SubprocessError) as exc:
            bundles.append({"path": str(path), "verified": False, "error": str(exc)})
    return {"read_only": True, "canonical_path": str(DEFAULT_DESTINATION),
            "bundles": bundles, "processes": echolingo_processes(),
            "note": "Build outputs and backups remain untouched. Inventory includes only configured roots, not every disk or Spotlight entry."}


def parse_cpu_time(value: str) -> float:
    days = 0
    if "-" in value:
        day_string, value = value.split("-", 1)
        days = int(day_string)
    pieces = value.split(":")
    if len(pieces) not in (2, 3):
        raise PreviewError("Unexpected ps CPU time format.")
    seconds = float(pieces[-1]) + 60 * int(pieces[-2])
    return days * 86400 + seconds + (3600 * int(pieces[0]) if len(pieces) == 3 else 0)


def process_sample(pid: int, executable: Path) -> dict:
    executable = executable.resolve()
    if process_path(pid) != executable:
        raise PreviewError("Measured EchoLingo process exited or changed identity.")
    try:
        row = run(["/bin/ps", "-p", str(pid), "-o", "rss=,time="]).stdout.split()
        if len(row) != 2:
            raise PreviewError("Measured EchoLingo process is unavailable.")
        sample = {"rss_kib": int(row[0]), "cpu_seconds": parse_cpu_time(row[1]), "monotonic": time.monotonic()}
    except subprocess.CalledProcessError as exc:
        raise PreviewError("Measured EchoLingo process exited.") from exc
    if process_path(pid) != executable:
        raise PreviewError("Measured EchoLingo process changed identity during sampling.")
    return sample


def silent_launch(metadata: dict, timeout: float = 10) -> tuple[int, float]:
    if echolingo_processes():
        raise PreviewError("EchoLingo is already running. Refusing a second launch because its single-instance handler can show the popup.")
    executable = Path(metadata["executable"]).resolve()
    bundle = Path(metadata["path"]).resolve()
    start = time.monotonic()
    # Launch the bundle through normal Launch Services, preserving its app launch
    # context. -g requests no foreground activation; -j requests hidden launch.
    # Never execute Contents/MacOS directly for installed-app TCC acceptance.
    try:
        run(["/usr/bin/open", "-g", "-j", str(bundle)], timeout=timeout)
    except subprocess.CalledProcessError as exc:
        raise PreviewError(f"macOS app-bundle launch failed: {exc.stderr.strip()}") from exc
    deadline = start + timeout
    while time.monotonic() < deadline:
        matching = [item for item in echolingo_processes()
                    if item["verified"] and Path(item["executable"]).resolve() == executable]
        if len(matching) == 1:
            pid = matching[0]["pid"]
            observed = process_sample(pid, executable)
            if observed["rss_kib"] > 0:
                return pid, (time.monotonic() - start) * 1000
        time.sleep(0.02)
    raise PreviewError("EchoLingo process observation timed out; inspect the app manually. No popup was requested.")


def benchmark(args: argparse.Namespace) -> dict:
    metadata = verify_bundle(absolute(args.app))
    executable = Path(metadata["executable"]).resolve()
    report = {
        "measured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "macos": platform.mac_ver()[0], "architecture": platform.machine(),
        "app": metadata, "bundle_bytes": bundle_size(Path(metadata["path"])),
        "executable_bytes": executable.stat().st_size,
        "scope": "Main EchoLingo process only; excludes separate WebKit/system helper processes.",
        "cpu_method": "Delta of ps accumulated CPU time / elapsed interval; 100% equals one CPU core; CPU time has 0.01 s display resolution.",
        "limitations": ["Process observation does not measure tray, WebView, first paint, OCR or API latency.",
                        "App launch uses Launch Services; this script does not verify TCC responsible-code attribution or retained privacy authorization.",
                        "Idle is the operator's condition: leave the popup hidden and do not use hotkeys during samples.",
                        "No application content, credentials, clipboard, screenshots, process arguments or environment are inspected."],
    }
    processes = echolingo_processes()
    if args.dry_run:
        report.update({"dry_run": True, "launch_requested": args.launch,
                       "samples_planned": args.samples, "interval_seconds": args.interval,
                       "settle_seconds": args.settle, "processes": processes})
        return report
    if args.launch:
        pid, elapsed_ms = silent_launch(metadata)
        report["launched"] = True
        report["launch_method"] = "Launch Services via /usr/bin/open -g -j and the verified bundle path"
        report["launch_to_process_observation_ms"] = round(elapsed_ms, 2)
        report["launch_metric_definition"] = "Elapsed from background bundle launch request to OS reporting the expected executable path and nonzero RSS; not application readiness or render latency."
    else:
        matching = [item for item in processes if Path(item["executable"]).resolve() == executable and item["verified"]]
        if len(matching) != 1:
            raise PreviewError("Exactly one running instance of --app is required. Use install first, then benchmark --launch when no EchoLingo instance is running.")
        pid = matching[0]["pid"]
        report["launched"] = False
    report["pid"] = pid
    time.sleep(args.settle)
    previous = process_sample(pid, executable)
    samples = []
    for _ in range(args.samples):
        time.sleep(args.interval)
        current = process_sample(pid, executable)
        elapsed = current["monotonic"] - previous["monotonic"]
        samples.append({"rss_kib": current["rss_kib"],
                        "cpu_percent_one_core": round(max(0, current["cpu_seconds"] - previous["cpu_seconds"]) / elapsed * 100, 3),
                        "interval_seconds": round(elapsed, 3)})
        previous = current
    report["samples"] = samples
    report["summary"] = {"rss_kib_median": statistics.median(item["rss_kib"] for item in samples),
                         "rss_kib_max": max(item["rss_kib"] for item in samples),
                         "cpu_percent_one_core_mean": round(statistics.mean(item["cpu_percent_one_core"] for item in samples), 3)}
    report["left_running"] = True
    return report


def bounded_number(converter: Callable, minimum: float, maximum: float) -> Callable:
    def parse(value: str):
        converted = converter(value)
        if not minimum <= converted <= maximum:
            raise argparse.ArgumentTypeError(f"Expected {minimum} through {maximum}.")
        return converted
    return parse


def parser() -> argparse.ArgumentParser:
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inventory", help="Read-only duplicate bundle/process inventory; never deletes copies.")
    inspect.add_argument("--search-root", action="append", default=[], help="Additional bounded directory to search (repeatable).")
    inspect.add_argument("--max-depth", type=bounded_number(int, 0, 8), default=2)
    install = commands.add_parser("install", help="Explicitly install a verified app; stop only verified EchoLingo processes and retain old app backup.")
    install.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    install.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    install.add_argument("--dry-run", action="store_true", help="Validate and print the plan; no copies, stopping or launch.")
    install.add_argument("--launch", action="store_true", help="After install, launch silently; no popup or focus request.")
    measure = commands.add_parser("benchmark", help="Sample main-process size, RSS and interval CPU; optional silent launch observation.")
    measure.add_argument("--app", type=Path, default=DEFAULT_DESTINATION)
    measure.add_argument("--launch", action="store_true", help="Launch only when no EchoLingo is running; leave it running afterwards.")
    measure.add_argument("--dry-run", action="store_true", help="Print planned measurements without launching or sampling.")
    measure.add_argument("--samples", type=bounded_number(int, 1, 60), default=5)
    measure.add_argument("--interval", type=bounded_number(float, 0.1, 10), default=1)
    measure.add_argument("--settle", type=bounded_number(float, 0, 30), default=3)
    return cli


def main() -> int:
    args = parser().parse_args()
    try:
        require_macos()
        if args.command == "inventory":
            result = inventory(args.search_root, args.max_depth)
        elif args.command == "benchmark":
            result = benchmark(args)
        else:
            source, destination = install_paths(args.source, args.destination)
            source_metadata = verify_bundle(source)
            if destination.exists():
                verify_bundle(destination)
            processes = echolingo_processes()
            if args.dry_run:
                result = {"dry_run": True, "source": source_metadata, "destination": str(destination),
                          "would_backup_existing": destination.exists(), "processes_to_stop": processes,
                          "would_launch_silently": args.launch, "other_copies_deleted": False}
            else:
                result = transactional_install(source, destination)
                if args.launch:
                    pid, elapsed = silent_launch(result["installed"])
                    result["silent_launch"] = {"pid": pid, "launch_to_process_observation_ms": round(elapsed, 2),
                                               "method": "Launch Services via /usr/bin/open -g -j",
                                               "render_or_tray_readiness_verified": False}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (PreviewError, OSError, subprocess.SubprocessError, ValueError) as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
