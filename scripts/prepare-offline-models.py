#!/usr/bin/env python3
"""Stage the pinned Mozilla models; no inference or user data is accessed.

All downloads are build-time actions. The application never calls this script.
The tracked manifest pins both compressed and unpacked lengths and SHA-256.
"""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tempfile
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
RESOURCE_ROOT = ROOT / "resources" / "offline-translation"
MANIFEST = RESOURCE_ROOT / "manifest.json"
ALLOWED_HOST = "storage.googleapis.com"
ALLOWED_PREFIX = "/moz-fx-translations-data--303e-prod-translations-data/models/"


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def verify(path, size, sha256):
    if path.is_symlink() or not path.is_file():
        raise ValueError("missing regular model file: " + str(path))
    if path.stat().st_size != size or digest(path) != sha256:
        raise ValueError("model integrity mismatch: " + str(path))


def read_manifest():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("formatVersion") != 1 or len(manifest.get("files", [])) != 7:
        raise ValueError("unsupported pinned model manifest")
    seen = set()
    for item in manifest["files"]:
        path = PurePosixPath(item["path"])
        if (len(path.parts) != 3 or path.parts[0] != "models"
                or path.parts[1] not in ("en-zh", "zh-en")
                or path.is_absolute() or ".." in path.parts
                or item["path"] in seen):
            raise ValueError("unsafe or duplicate model path")
        seen.add(item["path"])
        url = urllib.parse.urlsplit(item["sourceUrl"])
        if (url.scheme != "https" or url.netloc != ALLOWED_HOST
                or not url.path.startswith(ALLOWED_PREFIX)
                or not url.path.endswith(".gz") or url.query or url.fragment):
            raise ValueError("unexpected model download origin")
        for key in ("sha256", "compressedSha256"):
            value = item[key]
            if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
                raise ValueError("invalid pinned SHA-256")
        for key in ("size", "compressedSize"):
            if type(item[key]) is not int or not 0 < item[key] < 64 * 1024 * 1024:
                raise ValueError("invalid pinned model size")
    return manifest


def atomic_copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise ValueError("refusing model symlink destination")
    fd, temporary = tempfile.mkstemp(prefix=".model-", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as output, source.open("rb") as data:
            shutil.copyfileobj(data, output, 1024 * 1024)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def ensure_cached(item, cache, offline):
    cached = cache / item["sha256"]
    if cached.exists():
        verify(cached, item["size"], item["sha256"])
        return cached
    if offline:
        raise ValueError("verified model cache unavailable: " + item["path"])
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="model-download-", dir=cache) as temporary:
        packed = Path(temporary) / "model.gz"
        unpacked = Path(temporary) / "model"
        request = urllib.request.Request(item["sourceUrl"], headers={"User-Agent": "EchoLingo-build-model-preparer/1"})
        with urllib.request.urlopen(request, timeout=120) as response, packed.open("wb") as target:
            if response.geturl() != item["sourceUrl"]:
                raise ValueError("model redirect is not part of the pinned source")
            count = 0
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                count += len(chunk)
                if count > item["compressedSize"]:
                    raise ValueError("compressed model exceeds pinned size")
                target.write(chunk)
        verify(packed, item["compressedSize"], item["compressedSha256"])
        with gzip.open(packed, "rb") as source, unpacked.open("wb") as target:
            count = 0
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                count += len(chunk)
                if count > item["size"]:
                    raise ValueError("unpacked model exceeds pinned size")
                target.write(chunk)
        verify(unpacked, item["size"], item["sha256"])
        atomic_copy(unpacked, cached)
    return cached


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=RESOURCE_ROOT / "models", help="destination models directory")
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "EchoLingo" / "offline-models")
    parser.add_argument("--verify-only", action="store_true", help="check staged files without downloading or writing")
    parser.add_argument("--offline", action="store_true", help="stage only from a previously verified cache")
    args = parser.parse_args()
    manifest = read_manifest()
    files = manifest["files"]
    output = args.output.expanduser().resolve()
    cache = args.cache.expanduser().resolve()
    for item in files:
        destination = output.joinpath(*PurePosixPath(item["path"]).parts[1:])
        if args.verify_only or destination.exists():
            # A corrupt existing output is rejected rather than silently repaired.
            verify(destination, item["size"], item["sha256"])
        else:
            atomic_copy(ensure_cached(item, cache, args.offline), destination)
            verify(destination, item["size"], item["sha256"])
        print("verified " + item["path"])
    print(json.dumps({"ok": True, "files": len(files), "unpackedBytes": sum(f["size"] for f in files),
                      "downloadBytes": sum(f["compressedSize"] for f in files)}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print("offline model preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
