#!/bin/bash
# Generated external fullscreen + WKWebView host metadata, not physical IME proof.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then echo 'MACOS_RUNTIME_REQUIRED' >&2; exit 2; fi
if [[ "${GITHUB_ACTIONS:-}" != true && "${1:-}" != --isolated-test-session ]]; then
  echo 'ISOLATION_REQUIRED' >&2; exit 2
fi
private="$(mktemp -d "${TMPDIR:-/tmp}/echolingo-overlay-host.XXXXXX")"
trap 'rm -rf "$private"' EXIT
swiftc "$root/src-tauri/native/macos.swift" "$root/src-tauri/native/macos_capture.swift" \
  "$root/src-tauri/native/macos_window.swift" "$root/tests/macos-screenshot-overlay-host-fixture.swift" \
  -D ECHOLINGO_LIBRARY -parse-as-library -O -target "$(uname -m)-apple-macosx12.0" \
  -framework AppKit -framework WebKit -framework Vision -framework ApplicationServices -framework CoreText \
  -o "$private/overlay-host"
"$private/overlay-host" --isolated-test-session
