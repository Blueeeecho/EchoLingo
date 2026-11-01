#!/usr/bin/env python3
"""Verify the isolated debug fixture entry is absent from an actual release binary."""
import hashlib
import json
import pathlib
import sys

MARKERS = (b'--native-pin-smoke', b'SMOKE_EXTERNAL_FOREGROUND_REQUIRED', b'generated-pin-fixture')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Expected actual-release-app-executable')
    binary = pathlib.Path(sys.argv[1])
    if not binary.is_file() or binary.stat().st_size > 256 * 1024 * 1024:
        raise SystemExit('RELEASE_BINARY_REQUIRED_WITHIN_256_MIB')
    data = binary.read_bytes()
    absent = all(marker not in data for marker in MARKERS)
    print(json.dumps({'ok': absent, 'check': 'native-pin-debug-entry-absence', 'markersChecked': len(MARKERS), 'binarySha256': hashlib.sha256(data).hexdigest(), 'binaryBytes': len(data)}))
    if not absent:
        raise SystemExit('DEBUG_SMOKE_ENTRY_PRESENT_IN_RELEASE')


if __name__ == '__main__':
    main()
