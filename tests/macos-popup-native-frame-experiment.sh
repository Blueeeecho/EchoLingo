#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
binary="$(mktemp -d)/native-frame-experiment"
trap 'rm -rf "$(dirname "$binary")"' EXIT
swiftc -g src-tauri/native/macos_window.swift tests/macos-popup-native-frame-experiment.swift -o "$binary"
"$binary"
