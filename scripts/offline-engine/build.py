#!/usr/bin/env python3
"""Build a pinned CPU-only offline engine; downloads build sources, never user text/models."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / "sources.lock.json").read_text(encoding="utf-8"))


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def download(archive, cache):
    name = archive["repository"].replace("/", "-") + "-" + archive["commit"] + ".tar.gz"
    path = cache / name
    if path.exists() and digest(path) == archive["sha256"]:
        return path
    url = "https://codeload.github.com/" + archive["repository"] + "/tar.gz/" + archive["commit"]
    temporary = path.with_suffix(".download")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=90) as response, temporary.open("wb") as stream:
                shutil.copyfileobj(response, stream, length=1024 * 1024)
            if digest(temporary) != archive["sha256"]:
                raise RuntimeError("Archive hash mismatch: " + archive["repository"])
            temporary.replace(path)
            return path
        except Exception:
            temporary.unlink(missing_ok=True)
            if attempt == 2:
                raise


def extract(archive_path, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive:
            parts = PurePosixPath(member.name).parts[1:]
            if not parts:
                continue
            if any(part in ("..", "") or ":" in part or "\\" in part for part in parts):
                raise RuntimeError("Unsafe source archive path")
            target = destination.joinpath(*parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
            elif member.issym() and member.name.endswith("python/test/botchan.txt"):
                # An unused SentencePiece Python test fixture, unavailable on Windows without symlink privileges.
                continue
            else:
                raise RuntimeError("Unexpected source archive entry")


def patch_archive_revision(source):
    path = source / "inference/marian-fork/src/CMakeLists.txt"
    text = path.read_text(encoding="utf-8")
    marker = "# EchoLingo: reproducible archive revision; no Git checkout required."
    if marker in text:
        return
    start = text.index("set(MARIAN_GIT_DIR ")
    end = text.index("# make sure all local dependencies", start)
    revision = "mozilla-" + LOCK["mozillaCommit"]
    replacement = marker + "\nfile(WRITE ${CMAKE_CURRENT_SOURCE_DIR}/common/git_revision.h "
    replacement += '"#define GIT_REVISION \\\"' + revision + '\\\"\\n")\n'
    replacement += "add_custom_target(marian_version)\nadd_dependencies(marian marian_version)\n"
    path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


def patch_sentencepiece_enum(source):
    # The pinned 2020 tokenizer uses an out-of-enum sentinel. New Clang rejects
    # that conversion in constexpr evaluation; runtime const retains its value.
    path = source / "inference/marian-fork/src/3rd_party/sentencepiece/src/trainer_interface.cc"
    text = path.read_text(encoding="utf-8")
    old = "constexpr unicode_script::ScriptType kAnyType ="
    new = "const unicode_script::ScriptType kAnyType =  // EchoLingo: modern Clang build compatibility."
    if new not in text:
        if text.count(old) != 1:
            raise RuntimeError("Unexpected SentencePiece source revision")
        path.write_text(text.replace(old, new), encoding="utf-8")
    path = source / "inference/marian-fork/src/3rd_party/simd_utils/simd_utils.h"
    text = path.read_text(encoding="utf-8")
    marker = "#include <fenv.h> // EchoLingo: explicit floating-point environment declarations."
    if marker not in text:
        path.write_text(text.replace("#include <math.h>", "#include <math.h>\n" + marker), encoding="utf-8")


def prepare(work):
    cache = work / "archives"
    cache.mkdir(parents=True, exist_ok=True)
    for archive in LOCK["archives"]:
        path = download(archive, cache)
        destination = work / archive["destination"]
        marker = destination / ".echolingo-source.json"
        if not marker.exists() or json.loads(marker.read_text())["sha256"] != archive["sha256"]:
            extract(path, destination)
            marker.write_text(json.dumps(archive, indent=2) + "\n", encoding="utf-8")
    for entry in LOCK["files"]:
        destination = work / entry["destination"]
        if not destination.exists() or digest(destination) != entry["sha256"]:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(entry["sourceUrl"], timeout=90) as response:
                data = response.read(2 * 1024 * 1024)
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise RuntimeError("Source file hash mismatch")
            destination.write_bytes(data)
    source = work / ("translations-" + LOCK["mozillaCommit"])
    patch_archive_revision(source)
    patch_sentencepiece_enum(source)
    return source, work / "pcre2-10.46"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--generator", default="Ninja" if os.name == "nt" else "Unix Makefiles")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--prepared-source", type=Path, help="Use the source-offer tree without network downloads")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 32:
        parser.error("--jobs must be 1..32")
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    if args.prepared_source:
        prepared = args.prepared_source.resolve()
        source, pcre = prepared / ("translations-" + LOCK["mozillaCommit"]), prepared / "pcre2-10.46"
        if not (source / "inference/CMakeLists.txt").is_file() or not (pcre / "CMakeLists.txt").is_file():
            raise RuntimeError("Incomplete prepared source-offer tree")
        patch_archive_revision(source)
        patch_sentencepiece_enum(source)
        json_source = prepared / "nlohmann-json"
    else:
        source, pcre = prepare(work)
        json_source = work / "nlohmann-json"
    for entry in LOCK["files"]:
        if digest(json_source / Path(entry["destination"]).name) != entry["sha256"]:
            raise RuntimeError("Prepared JSON source hash mismatch")
    if args.prepare_only:
        print(json.dumps({"source": str(source), "pcre2": str(pcre), "mozillaCommit": LOCK["mozillaCommit"]}))
        return
    build = work / ("build-windows" if os.name == "nt" else "build-macos")
    command = [args.cmake, "-S", str(HERE), "-B", str(build), "-G", args.generator,
               "-DCMAKE_BUILD_TYPE=Release", "-DECHOLINGO_MOZILLA_SOURCE=" + str(source),
               "-DECHOLINGO_PCRE2_SOURCE=" + str(pcre), "-DECHOLINGO_JSON_SOURCE=" + str(json_source)]
    if os.name == "nt" and args.generator.startswith("Visual Studio"):
        command.extend(["-A", "x64"])
    subprocess.run(command, check=True)
    subprocess.run([args.cmake, "--build", str(build), "--target", "echolingo-offline-engine",
                    "--config", "Release", "--parallel", str(args.jobs)], check=True)
    filename = "echolingo-offline-engine.exe" if os.name == "nt" else "echolingo-offline-engine"
    binary = next((p for p in (build / "Release" / filename, build / filename) if p.is_file()), None)
    if binary is None:
        raise RuntimeError("Engine binary was not produced")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, output / filename)
    print(json.dumps({"binary": str(output / filename), "sha256": digest(output / filename),
                      "mozillaCommit": LOCK["mozillaCommit"]}))


if __name__ == "__main__":
    main()
