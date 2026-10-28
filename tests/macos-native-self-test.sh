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

swiftc "$repo_root/src-tauri/native/macos.swift" "$repo_root/src-tauri/native/macos_capture.swift" "$repo_root/src-tauri/native/macos_window.swift" -parse-as-library -O \
  -target "${native_arch}-apple-macosx12.0" \
  -framework AppKit -framework Vision -framework ApplicationServices -framework CoreText \
  -o "$fixture_dir/echolingo-native-helper"
"$fixture_dir/echolingo-native-helper" --self-test
