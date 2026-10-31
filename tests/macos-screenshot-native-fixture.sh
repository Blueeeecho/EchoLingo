#!/bin/bash
# Coverage probe, not a silently-skipped release gate. A denied screen-capture
# preflight exits 2 with a blocked report; no permission request or grant occurs.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:?Usage: macos-screenshot-native-fixture.sh /absolute/output-directory [--isolated-test-session]}"
case "$output" in /*) ;; *) echo 'An absolute output directory is required.' >&2; exit 2;; esac
if [[ "${GITHUB_ACTIONS:-}" != "true" && "${2:-}" != "--isolated-test-session" ]]; then
  echo 'ISOLATION_REQUIRED: Run only in an explicitly isolated generated-window session.' >&2; exit 2
fi
mkdir -p "$output"
report="$output/report.json"
if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' '{"schema":"echolingo-macos-screenshot-native-v1","ok":false,"status":"blocked","reason":"macos-runtime-unavailable","permissionRequested":false,"securitySettingsChanged":false,"physicalF1Tested":false,"packagedEditorTested":false}' > "$report"
  cat "$report"; exit 2
fi
private="$(mktemp -d "${TMPDIR:-/tmp}/echolingo-screenshot-native.XXXXXX")"
trap 'rm -rf "$private"' EXIT
binary="$private/screenshot-fixture"
if ! swiftc "$repo_root/src-tauri/native/macos.swift" "$repo_root/src-tauri/native/macos_capture.swift" \
    "$repo_root/src-tauri/native/macos_window.swift" "$repo_root/tests/macos-screenshot-native-fixture.swift" \
    -D ECHOLINGO_LIBRARY -parse-as-library -O -target "$(uname -m)-apple-macosx12.0" \
    -framework AppKit -framework Vision -framework ApplicationServices -framework CoreText \
    -o "$binary" > "$output/compile.log" 2>&1; then
  printf '%s\n' '{"schema":"echolingo-macos-screenshot-native-v1","ok":false,"status":"failed","reason":"native-fixture-compile-failed","permissionRequested":false,"securitySettingsChanged":false,"physicalF1Tested":false,"packagedEditorTested":false}' > "$report"
  cat "$output/compile.log" >&2; cat "$report"; exit 1
fi
mkdir "$private/images"
if "$binary" --isolated-test-session "$report" "$private/images"; then code=0; else code=$?; fi
python3 - "$report" "$binary" "$repo_root" "$code" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
report_path, binary, root, code = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4])
if not report_path.is_file():
    report = {'schema':'echolingo-macos-screenshot-native-v1','ok':False,'status':'failed',
              'reason':'native-probe-ended-without-report','permissionRequested':False,'securitySettingsChanged':False}
else:
    report = json.loads(report_path.read_text())
report['nativeProcessExitCode'] = code
report['fixtureBinarySha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
report['productionSourceSha256'] = {
    str(path): hashlib.sha256((root/path).read_bytes()).hexdigest()
    for path in map(Path, ['src-tauri/native/macos.swift','src-tauri/native/macos_capture.swift','src-tauri/native/macos_window.swift'])
}
report_path.write_text(json.dumps(report, sort_keys=True) + '\n')
PY
# The validator deliberately returns 2 for permission blocked, not a green skip.
python3 "$repo_root/scripts/verify-macos-screenshot-probe.py" "$report"
exit "$code"
