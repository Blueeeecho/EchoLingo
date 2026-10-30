#!/bin/bash
# Optional diagnostic, not a release or physical-edge acceptance gate.
set -euo pipefail
cd "$(dirname "$0")/.."
binary="$(mktemp -d)/native-edge-experiment"
trap 'rm -rf "$(dirname "$binary")"' EXIT
swiftc -parse-as-library -g src-tauri/native/macos_window.swift tests/macos-popup-native-edge-experiment.swift -o "$binary"
"$binary"
