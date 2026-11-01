#!/bin/bash
# Actual Tauri pin lifecycle, generated pixels only. Debug entry absent in release.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then echo MACOS_RUNTIME_REQUIRED >&2; exit 2; fi
if [[ "${GITHUB_ACTIONS:-}" != true && "${4:-}" != --isolated-test-session ]]; then
  echo ISOLATION_REQUIRED >&2; exit 2
fi
if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo 'Expected debug-binary release-binary new-evidence-directory [--isolated-test-session]' >&2; exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$1" "$2" "$3" "$root" <<'PY'
import hashlib, json, pathlib, subprocess, sys

debug, release, output = (pathlib.Path(value).resolve(strict=False) for value in sys.argv[1:4])
if not debug.is_file() or not release.is_file() or debug == release:
    raise SystemExit('DISTINCT_DEBUG_AND_RELEASE_BINARIES_REQUIRED')
output.mkdir(parents=True, exist_ok=False)
if release.stat().st_size > 256 * 1024 * 1024:
    raise SystemExit('RELEASE_BINARY_SIZE_BOUND')
release_bytes = release.read_bytes()
if debug.stat().st_size > 256 * 1024 * 1024:
    raise SystemExit('DEBUG_BINARY_SIZE_BOUND')
provenance = {
    'sourceCommit': subprocess.check_output(['git', '-C', sys.argv[4], 'rev-parse', 'HEAD'], text=True).strip(),
    'debugSha256': hashlib.sha256(debug.read_bytes()).hexdigest(),
    'releaseSha256': hashlib.sha256(release_bytes).hexdigest(),
    'commitBinding': 'workflow-build-provenance-required; hashes identify tested bytes',
}
(output / 'inputs.json').write_text(json.dumps(provenance, indent=2))
markers = (b'--native-pin-smoke', b'SMOKE_EXTERNAL_FOREGROUND_REQUIRED', b'generated-pin-fixture')
absent = all(marker not in release_bytes for marker in markers)
(output / 'release-entry-absence.json').write_text(json.dumps({'ok': absent, 'markersChecked': len(markers)}))
if not absent:
    raise SystemExit('DEBUG_SMOKE_ENTRY_PRESENT_IN_RELEASE')
try:
    result = subprocess.run([str(debug), '--native-pin-smoke', '--isolated-test-session'],
                            capture_output=True, timeout=70, check=False)
except subprocess.TimeoutExpired as error:
    (output / 'stdout.log').write_bytes((error.stdout or b'')[:1024 * 1024])
    (output / 'stderr.log').write_bytes((error.stderr or b'')[:1024 * 1024])
    raise SystemExit('NATIVE_PIN_SMOKE_TIMEOUT')
(output / 'stdout.log').write_bytes(result.stdout[:1024 * 1024])
(output / 'stderr.log').write_bytes(result.stderr[:1024 * 1024])
if len(result.stdout) > 1024 * 1024 or len(result.stderr) > 1024 * 1024:
    raise SystemExit('NATIVE_PIN_SMOKE_OUTPUT_BOUND')
records = []
for line in result.stdout.decode('utf-8', errors='replace').splitlines():
    try:
        value = json.loads(line)
    except ValueError:
        continue
    if isinstance(value, dict) and value.get('fixture') == 'native-pin-smoke':
        records.append(value)
if result.returncode != 0 or len(records) != 1 or records[0].get('ok') is not True:
    raise SystemExit('NATIVE_PIN_SMOKE_FAILED_SEE_PRESERVED_LOGS')
report = records[0]
for key in ('productionPinCommand', 'productionPageAndReadyIpc', 'generatedPixelsVerified',
            'passiveShowVerified', 'nativeToggleResizeCloseVerified',
            'registryAndEncodedPayloadReleased', 'ownedDirectoryRemoved', 'noExportFiles', 'debugOnly'):
    if report.get(key) is not True:
        raise SystemExit('NATIVE_PIN_SMOKE_MISSING_EVIDENCE_' + key)
if report.get('cycles') != 2:
    raise SystemExit('NATIVE_PIN_SMOKE_REUSE_NOT_VERIFIED')
(output / 'report.json').write_text(json.dumps(report, indent=2))
print('Native production pin lifecycle passed; release debug-entry absence verified.')
PY
