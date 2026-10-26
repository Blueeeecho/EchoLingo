#!/usr/bin/env python3
"""Reproduce original offline dependency notices from the prepared source tree.

The tracked license-files.json lists the selected original files and digest.
Most notices are copied verbatim. Named header-notice entries retain the
unchanged leading copyright/license block rather than copying executable code.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys


ROOT = Path(__file__).resolve().parent.parent
RESOURCE = ROOT / "resources/offline-translation"
INDEX = RESOURCE / "license-files.json"
LOCK = ROOT / "scripts/offline-engine/sources.lock.json"


def notice_bytes(item, work, mozilla):
    relative = PurePosixPath(item["sourcePath"])
    if relative.is_absolute() or any(part in ("..", ".") for part in relative.parts):
        raise ValueError("unsafe notice source path")
    if relative.parts[0] in ("pcre2-10.46", "nlohmann-json"):
        source = work.joinpath(*relative.parts)
    elif relative.parts[0] == "inference" or relative.as_posix() in ("LICENSE", "README.md"):
        source = mozilla.joinpath(*relative.parts)
    else:
        raise ValueError("unexpected notice source tree")
    if source.is_symlink() or not source.is_file():
        raise ValueError("missing regular notice source")
    data = source.read_bytes()
    name = PurePosixPath(item["path"]).name
    if name.startswith("marian-header-notice__"):
        lines = data.splitlines(keepends=True)
        stop = next((i for i, line in enumerate(lines)
                     if line.startswith((b"#include", b"#pragma", b"#ifndef"))), None)
        if stop is None:
            raise ValueError("missing header notice boundary")
        data = b"".join(lines[:stop])
    elif name.startswith("simd-utils-header-notice__"):
        marker = b"/* Tunable configurations */" if "sse2neon" in name else b"#include"
        end = data.find(marker)
        if end < 0:
            raise ValueError("missing SIMD header notice boundary")
        data = data[:end]
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine-work-dir", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true", help="compare original bytes and tracked hashes without writes")
    args = parser.parse_args()
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    work = args.engine_work_dir.resolve()
    mozilla = work / ("translations-" + lock["mozillaCommit"])
    if index.get("formatVersion") != 1 or index.get("mozillaCommit") != lock["mozillaCommit"]:
        raise ValueError("notice/source revision mismatch")
    for item in index["files"]:
        target = PurePosixPath(item["path"])
        if len(target.parts) != 2 or target.parts[0] != "licenses" or ".." in target.parts:
            raise ValueError("unsafe notice destination")
        data = notice_bytes(item, work, mozilla)
        if hashlib.sha256(data).hexdigest() != item["sha256"]:
            raise ValueError("original notice digest mismatch: " + item["path"])
        destination = RESOURCE.joinpath(*target.parts)
        if args.verify_only:
            if destination.is_symlink() or destination.read_bytes() != data:
                raise ValueError("staged notice differs: " + item["path"])
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.is_symlink():
                raise ValueError("refusing notice symlink destination")
            destination.write_bytes(data)
    locked_bytes = LOCK.read_bytes()
    locked_copy = RESOURCE / "engine-sources.lock.json"
    if args.verify_only:
        if locked_copy.read_bytes() != locked_bytes:
            raise ValueError("staged source lock differs")
    else:
        locked_copy.write_bytes(locked_bytes)
    print(json.dumps({"ok": True, "originalNotices": len(index["files"]),
                      "mozillaCommit": lock["mozillaCommit"], "verifyOnly": args.verify_only}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print("offline notice preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
