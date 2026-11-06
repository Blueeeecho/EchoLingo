#!/bin/bash
# Standalone development checks only; production links Swift into the app.
# This uses a private fixture pasteboard and never captures a screen, requests
# TCC access, reads a source selection or touches the user's general clipboard.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'macOS with the Apple Swift toolchain is required.' >&2
  exit 1
fi

case "$(uname -m)" in
  arm64|x86_64) native_arch="$(uname -m)" ;;
  *) printf '%s\n' 'Unsupported macOS architecture.' >&2; exit 1 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/echolingo-native-self-test.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT

# Exercise actual bounded coordinator with blocked work AND blocked cancellation.
# No Apple engine or private pixels are used by this fixture.
swiftc "$repo_root/src-tauri/native/macos_ocr.swift" "$repo_root/tests/macos-ocr-domain-fixture.swift" \
  -parse-as-library -O -target "${native_arch}-apple-macosx12.0" -o "$fixture_dir/ocr-domain-fixture"
"$fixture_dir/ocr-domain-fixture"

swiftc "$repo_root/src-tauri/native/macos.swift" "$repo_root/src-tauri/native/macos_capture.swift" "$repo_root/src-tauri/native/macos_ocr.swift" "$repo_root/src-tauri/native/macos_window.swift" -parse-as-library -O \
  -target "${native_arch}-apple-macosx12.0" \
  -framework AppKit -framework Vision -framework ApplicationServices -framework CoreText \
  -o "$fixture_dir/echolingo-native-helper"
"$fixture_dir/echolingo-native-helper" --selection-policy-self-test | tee "$fixture_dir/selection-policy.json"
python3 - "$fixture_dir/selection-policy.json" <<'PY_SELECTION'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
assert report.get("ok") is True
assert report.get("diagnostics", {}).get("selectionPolicyFixturePassed") is True
PY_SELECTION
"$fixture_dir/echolingo-native-helper" --self-test | tee "$fixture_dir/report.json"
python3 - "$fixture_dir/report.json" <<'PY_CHECK'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as report_file:
    report = json.load(report_file)
assert report.get("ok") is True, "Native self-test did not report success"
checks = report.get("diagnostics", {})
for required in (
    "screenshotWindowPolicyFixturePassed",
    "screenshotCancellationFixturePassed",
    "ocrCancellationTimingFixturePassed",
    "mixedSelectionRecoveryFixturePassed",
    "chatMultiSelectionFixturePassed",
    "selectionFocusRecoveryFixturePassed",
    "selectionSourceAnchorFixturePassed",
    "selectionTraceRetentionFixturePassed",
    "selectionAXWindowTicketFixturePassed",
    "selectionWindowAnchorFixturePassed",
    "selectionRecoveryFixturePassed",
    "controlledSelectionCopyFixturePassed",
    "protectedSelectionFixturePassed",
    "selectionTracePrivacyFixturePassed",
):
    assert checks.get(required) is True, f"Missing or failed native fixture: {required}"
assert checks.get("generalClipboardTouched") is False, "Self-test touched the general clipboard"
assert checks.get("codexInteractiveSelectionTested") is False, "Fixtures must not claim Codex interactive acceptance"
assert checks.get("qqInteractiveMultiSelectionTested") is False, "Fixtures must not claim QQ interactive acceptance"
PY_CHECK

# Reuse the same compiled helper. These are synthetic policy/state tests, not
# an Apple engine request, a language download, or physical-device acceptance.
"$fixture_dir/echolingo-native-helper" --system-translation-self-test | tee "$fixture_dir/system-translation.json"
swiftc --version > "$fixture_dir/swift-version.txt"
sw_vers -productVersion > "$fixture_dir/macos-version.txt"
python3 - "$fixture_dir/system-translation.json" "$fixture_dir/swift-version.txt" "$fixture_dir/macos-version.txt" <<'PY_SYSTEM'
import json
import os
import re
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
assert report.get("ok") is True, "System translation synthetic self-test failed"
checks = report.get("diagnostics", {})
for required in (
    "systemTranslationPolicyFixturePassed",
    "systemTranslationTraceRecoveryFixturePassed",
    "systemTranslationOutputFixturePassed",
):
    assert checks.get(required) is True, f"Missing system translation policy check: {required}"
assert checks.get("translationEngineCalled") is False, "Policy checks invoked Apple translation"
assert checks.get("languageDownloadRequested") is False, "Policy checks requested language downloads"
version = re.search(r"Swift version (\d+)\.(\d+)", Path(sys.argv[2]).read_text())
assert version, "Cannot establish Swift compiler capability"
compiler = tuple(map(int, version.groups()))
macos_major = int(Path(sys.argv[3]).read_text().strip().split(".")[0])
capable = compiler >= (6, 2) and macos_major >= 26
if os.environ.get("ECHOLINGO_REQUIRE_SYSTEM_TRANSLATION_RECOVERY") == "1":
    assert capable, "Release acceptance requires macOS 26 and Swift 6.2 installed-only recovery coverage"
    assert checks.get("systemTranslationInstalledRetryFixturePassed") is True, "Release acceptance requires executed installed-only retry tests"
    assert checks.get("systemTranslationInstalledRetryFixtureSkipped") is False, "Release acceptance cannot use skipped installed-only retry tests"
if capable:
    assert checks.get("systemTranslationInstalledOnlyFixturePassed") is True, "Capable runner skipped installed-only/recovery policy tests"
    assert checks.get("systemTranslationInstalledRetryFixturePassed") is True, "Capable runner skipped bounded installed-only retry tests"
    assert checks.get("systemTranslationInstalledRetryFixtureSkipped") is False, "Capable runner reported retry tests skipped"
    assert checks.get("systemTranslationCancellationFixturePassed") is True, "Capable runner skipped cancellation policy tests"
else:
    assert checks.get("systemTranslationInstalledOnlyFixturePassed") is False, "Unsupported runner claimed macOS 26 policy coverage"
    assert checks.get("systemTranslationInstalledRetryFixturePassed") is False, "Unsupported runner claimed installed-only retry coverage"
    assert checks.get("systemTranslationInstalledRetryFixtureSkipped") is True, "Unsupported runner did not report retry coverage skipped"
    print("Installed-only/recovery Translation API policy checks skipped: macOS 26 and Swift 6.2 required.")
print("Synthetic system translation policy/recovery checks passed; no engine/download or real-device acceptance claimed.")
PY_SYSTEM
