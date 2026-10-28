#!/usr/bin/env python3
"""Run only the independent Tauri fixture; never start the installed app.

Example: python3 tests/macos-tauri-activation-fixture.py --output-dir /abs/evidence
Build the Cargo example first. Default cases are unbundled/bundled, setup/
before-run, and no-window/hidden-window. A floating window requires an explicit
--window floating argument and should be coordinated with the root's own host.
"""

import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    parser.add_argument(
        "--binary", type=pathlib.Path,
        default=root / "src-tauri/target/debug/examples/macos-activation-policy",
    )
    parser.add_argument("--mode", action="append", choices=("setup", "before-run"))
    parser.add_argument("--window", action="append", choices=("none", "hidden", "floating"))
    parser.add_argument("--bundle-only", action="store_true")
    parser.add_argument("--hold-ms", type=int, default=250)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This fixture requires macOS; no other host will be contacted.")
    if not args.output_dir.is_absolute() or not args.binary.is_absolute():
        parser.error("Output directory and binary must be absolute paths.")
    if not 250 <= args.hold_ms <= 30_000:
        parser.error("hold-ms must be between 250 and 30000.")
    binary = args.binary.resolve(strict=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    source_plist = root / "src-tauri/Info.plist"
    with source_plist.open("rb") as stream:
        app_plist = plistlib.load(stream)
    if app_plist.get("LSUIElement") is not True:
        parser.error("Production Info.plist must explicitly contain LSUIElement=true.")
    inputs = {
        "binary": binary,
        "fixture": root / "src-tauri/examples/macos-activation-policy.rs",
        "startupHelper": root / "src-tauri/src/macos_startup.rs",
        "nativeWindowHelper": root / "src-tauri/native/macos_window.swift",
        "productionInfoPlist": source_plist,
    }
    source_hashes = {name: digest(path) for name, path in inputs.items()}
    modes = args.mode or ["setup", "before-run"]
    windows = args.window or ["none", "hidden"]
    contexts = ["bundle"] if args.bundle_only else ["unbundled", "bundle"]
    summary = []
    # No Launch Services registration, installation, signing or user app path.
    # The entire independent .app is removed when this scope ends.
    with tempfile.TemporaryDirectory(
        prefix="tauri-activation-", suffix=".noindex", dir=args.output_dir
    ) as temporary:
        app = pathlib.Path(temporary) / "EchoLingoActivationFixture.app"
        executable = app / "Contents/MacOS/activation-policy-fixture"
        executable.parent.mkdir(parents=True)
        shutil.copy2(binary, executable)
        app_plist.update({
            "CFBundleIdentifier": "io.github.blueeeecho.echolingo.activation-policy-fixture",
            "CFBundleExecutable": executable.name,
            "CFBundleName": "EchoLingoActivationFixture",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "0.0.0",
            "CFBundleShortVersionString": "0.0.0",
            "NSHighResolutionCapable": True,
        })
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(app_plist, stream)
        for context in contexts:
            target = executable if context == "bundle" else binary
            for mode in modes:
                for window in windows:
                    command = [str(target), "--mode=" + mode, "--window=" + window,
                               "--hold-ms=" + str(args.hold_ms)]
                    record = {
                        "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        "context": context, "mode": mode, "window": window,
                        "sourceSha256": source_hashes,
                        "productionInfoPlistCopied": context == "bundle",
                        "independentBundleIdentifier": app_plist["CFBundleIdentifier"],
                        "appSignedOrRegistered": False,
                    }
                    try:
                        run = subprocess.run(command, capture_output=True, text=True,
                                             timeout=(args.hold_ms + 7_000) / 1000)
                        record["processExitCode"] = run.returncode
                        record["stderr"] = run.stderr.strip()
                        try:
                            report = json.loads(run.stdout)
                            record["report"] = report
                            record["ok"] = run.returncode == 0 and report.get("ok") is True
                            if context == "bundle":
                                record["ok"] = record["ok"] and report.get("bundledContext") is True
                                record["ok"] = record["ok"] and all(
                                    row.get("lsUiElement") is True
                                    for row in report.get("observations", [])
                                )
                        except json.JSONDecodeError:
                            record["ok"] = False
                            record["error"] = "Fixture did not emit one JSON result."
                            record["stdout"] = run.stdout
                    except subprocess.TimeoutExpired:
                        record["ok"] = False
                        record["error"] = "Independent fixture exceeded bounded process deadline."
                    path = args.output_dir / f"tauri-{context}-{mode}-{window}.json"
                    path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
                    summary.append({"evidence": str(path), "ok": record["ok"],
                                    "context": context, "mode": mode, "window": window})
                    print(json.dumps(summary[-1]), flush=True)
    report = {"ok": all(row["ok"] for row in summary), "cases": summary,
              "temporaryBundleRemoved": True, "productionAppTouched": False,
              "physicalFullScreenVisualTested": False, "windowsPlatformTested": False}
    (args.output_dir / "tauri-matrix-summary.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    )
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
