#!/usr/bin/env python3
"""Create the corresponding inference-source release asset (no models/binaries).

Run only after preparing the exact pinned dependency tree used for the build.
The supplied source tree includes any compatibility changes made by the builder.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
MOZILLA_COMMIT = "69455acaecbe8650cdba988dbcf7c10ca20e7c48"
SKIP_NAMES = {".git", ".DS_Store", "__pycache__", "CMakeFiles", "Testing", "build", "_build", "_deps"}
UNUSED_MOZILLA = (
    "inference/3rd_party/emsdk", "inference/3rd_party/ssplit-cpp/nonbreaking_prefixes",
    "inference/marian-fork/src/3rd_party/nccl", "inference/marian-fork/src/3rd_party/fbgemm",
    "inference/marian-fork/src/3rd_party/simple-websocket-server",
    "inference/marian-fork/src/3rd_party/onnxjs",
    "inference/marian-fork/src/3rd_party/sentencepiece/python/test",
)
SKIP_SUFFIXES = {".o", ".obj", ".a", ".lib", ".dll", ".exe", ".dylib", ".so", ".pyc", ".pdb", ".ninja", ".log"}
NOTICE = """# EchoLingo offline inference corresponding source

This archive accompanies the EchoLingo preview installer. Mozilla covered files
remain under MPL 2.0; Marian and each dependency retain their original licenses.
Original notices are in the source tree and resources/offline-translation/licenses/.
See that directory's SOURCE-OFFER.md and SOURCE-MANIFEST.json for provenance.

The application does not load or distribute ssplit nonbreaking-prefix data;
those unused LGPL data, SentencePiece Python test fixtures/models, and disabled
GPU/server/WASM dependencies are omitted.
No model weights, user text, credentials, build outputs or toolchain are included.
Model source URLs/hashes are in resources/offline-translation/manifest.json; weights accompany the
installer. This source archive does not include private application data.

Build with a C++17 compiler, CMake and Ninja (or a platform CMake generator):

    cmake -S scripts/offline-engine -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DECHOLINGO_MOZILLA_SOURCE=<absolute path to translations-69455acaecbe8650cdba988dbcf7c10ca20e7c48> -DECHOLINGO_PCRE2_SOURCE=<absolute path to pcre2-10.46> -DECHOLINGO_JSON_SOURCE=<absolute path to nlohmann-json>
    cmake --build build --config Release --target echolingo-offline-engine

On Windows, use the Visual Studio x64 Native Tools environment for these commands.
The preparation script records exact upstream revisions and archive SHA-256.
The archive's translations-<commit>/, pcre2-10.46/ and nlohmann-json/ contain prepared source and any
compatibility changes used for this build, so the CMake commands need no download.
Alternatively use scripts/offline-engine/build.py --prepared-source <archive root>
with --work-dir <build directory> and --output-dir <binary directory>.
Refer to scripts/offline-engine/build.py for the full pinned preparation path.
"""


def source_files(source, prefix, mozilla=False):
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if any(part in SKIP_NAMES for part in relative.parts):
            continue
        posix = relative.as_posix()
        if mozilla and (not (posix.startswith("inference/") or posix in {"README.md", "LICENSE", ".gitmodules"})
                        or any(posix == x or posix.startswith(x + "/") for x in UNUSED_MOZILLA)):
            continue
        if path.is_symlink():
            raise ValueError("source symlink requires explicit review: " + posix)
        if not path.is_file() or path.suffix.lower() in SKIP_SUFFIXES:
            continue
        if path.name in {"CMakeCache.txt", "compile_commands.json", "build.ninja", "cmake_install.cmake"}:
            continue
        if path.stat().st_size > 32 * 1024 * 1024:
            raise ValueError("unexpected large source file: " + posix)
        yield prefix + "/" + posix, path.read_bytes()


def source_modifications(entries, work):
    """Compare supplied files to their hash-verified original source archives."""
    lock = json.loads((ROOT / "scripts/offline-engine/sources.lock.json").read_text(encoding="utf-8"))
    changes = []
    for item in lock["archives"]:
        filename = item["repository"].replace("/", "-") + "-" + item["commit"] + ".tar.gz"
        path = work / "archives" / filename
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("original source archive missing or hash mismatch: " + item["repository"])
        with tarfile.open(path, "r:gz") as archive:
            for member in archive:
                if not member.isfile():
                    continue
                relative = "/".join(member.name.split("/")[1:])
                name = item["destination"] + "/" + relative
                if name not in entries:
                    continue
                original = archive.extractfile(member).read()
                original_hash = hashlib.sha256(original).hexdigest()
                supplied_hash = hashlib.sha256(entries[name]).hexdigest()
                if original_hash != supplied_hash:
                    changes.append({"path": name, "repository": item["repository"],
                                    "commit": item["commit"], "upstreamSha256": original_hash,
                                    "suppliedSha256": supplied_hash})
    for item in lock.get("files", []):
        name = item["destination"]
        if name not in entries or hashlib.sha256(entries[name]).hexdigest() != item["sha256"]:
            raise ValueError("pinned source file missing or hash mismatch: " + name)
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine-work-dir", type=Path, help="work directory used by scripts/offline-engine/build.py")
    parser.add_argument("--source-root", type=Path, help="prepared pinned Mozilla source used for this build")
    parser.add_argument("--pcre2-source", type=Path, help="prepared pinned PCRE2 source used for this build")
    parser.add_argument("--output", required=True, type=Path, help="release zip path, outside the repository")
    args = parser.parse_args()
    if args.engine_work_dir:
        if args.source_root or args.pcre2_source:
            parser.error("choose --engine-work-dir or explicit source paths")
        source = args.engine_work_dir.resolve() / ("translations-" + MOZILLA_COMMIT)
        pcre2 = args.engine_work_dir.resolve() / "pcre2-10.46"
        work = args.engine_work_dir.resolve()
    elif args.source_root and args.pcre2_source:
        source, pcre2 = args.source_root.resolve(), args.pcre2_source.resolve()
        work = source.parent
    else:
        parser.error("provide --engine-work-dir or both source paths")
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        raise ValueError("corresponding source asset belongs outside the Git working tree")
    if not (source / "inference/CMakeLists.txt").is_file() or not (source / "LICENSE").is_file():
        raise ValueError("prepared Mozilla inference source is incomplete")
    if not (pcre2 / "CMakeLists.txt").is_file() or not (pcre2 / "LICENCE.md").is_file():
        raise ValueError("prepared PCRE2 source is incomplete")
    entries = dict(source_files(source, "translations-" + MOZILLA_COMMIT, mozilla=True))
    entries.update(source_files(pcre2, "pcre2-10.46"))
    entries.update(source_files(work / "nlohmann-json", "nlohmann-json"))
    entries.update(source_files(ROOT / "scripts/offline-engine", "scripts/offline-engine"))
    required = [ROOT / "scripts/offline-engine/main.cpp", ROOT / "scripts/offline-engine/CMakeLists.txt",
                ROOT / "scripts/offline-engine/build.py", ROOT / "scripts/offline-engine/sources.lock.json",
                ROOT / "scripts/prepare-offline-models.py", ROOT / "scripts/test_prepare_offline_models.py",
                ROOT / "scripts/prepare-offline-notices.py",
                Path(__file__).resolve(), ROOT / "LICENSE"]
    for path in required:
        if not path.is_file():
            raise ValueError("missing EchoLingo build source: " + path.name)
        entries[path.relative_to(ROOT).as_posix()] = path.read_bytes()
    for path in sorted((ROOT / "resources/offline-translation/licenses").glob("*")):
        if path.is_file():
            entries["resources/offline-translation/licenses/" + path.name] = path.read_bytes()
    for name in ("manifest.json", "license-files.json", "engine-sources.lock.json", "selected-models.json", "mozilla-model-registry-20261026.json"):
        entries["resources/offline-translation/" + name] = (ROOT / "resources/offline-translation" / name).read_bytes()
    entries["README.md"] = NOTICE.encode("utf-8")
    inventory = {"formatVersion": 1, "mozillaCommit": MOZILLA_COMMIT,
                 "excludedUnusedSourcePaths": list(UNUSED_MOZILLA),
                 "upstreamFileModifications": source_modifications(entries, work),
                 "files": [{"path": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                           for name, data in sorted(entries.items())]}
    entries["SOURCE-MANIFEST.json"] = (json.dumps(inventory, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="offline-source-", suffix=".zip", dir=output.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name, data in sorted(entries.items()):
                member = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                member.compress_type = zipfile.ZIP_DEFLATED
                member.external_attr = 0o100644 << 16
                archive.writestr(member, data, compresslevel=9)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError("source archive CRC verification failed")
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(json.dumps({"ok": True, "files": len(entries), "size": output.stat().st_size,
                      "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "archive": str(output)}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print("offline source packaging failed: " + str(error), file=sys.stderr)
        sys.exit(1)
