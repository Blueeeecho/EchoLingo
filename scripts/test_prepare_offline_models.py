#!/usr/bin/env python3
"""Integrity checks for build-time model staging; no network or real model load."""

import gzip
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("prepare-offline-models.py")
SPEC = importlib.util.spec_from_file_location("prepare_offline_models", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PinnedModelIntegrity(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.payload = b"synthetic model fixture\x00\xff"
        self.packed = gzip.compress(self.payload, mtime=0)
        self.item = {"path": "models/en-zh/model.fixture.bin", "size": len(self.payload),
                     "sha256": hashlib.sha256(self.payload).hexdigest(),
                     "compressedSize": len(self.packed),
                     "compressedSha256": hashlib.sha256(self.packed).hexdigest(),
                     "sourceUrl": "https://storage.googleapis.com/moz-fx-translations-data--303e-prod-translations-data/models/fixture.gz"}

    def response(self, payload):
        response = io.BytesIO(payload)
        response.geturl = lambda: self.item["sourceUrl"]
        return response

    def test_checked_download_then_offline_cache(self):
        with mock.patch.object(MODULE.urllib.request, "urlopen", return_value=self.response(self.packed)) as fetch:
            cached = MODULE.ensure_cached(self.item, self.root, False)
            self.assertEqual(cached.read_bytes(), self.payload)
            self.assertEqual(MODULE.ensure_cached(self.item, self.root, True), cached)
            self.assertEqual(fetch.call_count, 1)

    def test_tampered_download_is_not_installed(self):
        with mock.patch.object(MODULE.urllib.request, "urlopen", return_value=self.response(b"x" * len(self.packed))):
            with self.assertRaisesRegex(ValueError, "integrity mismatch"):
                MODULE.ensure_cached(self.item, self.root, False)
        self.assertFalse((self.root / self.item["sha256"]).exists())

    def test_gzip_expansion_is_bounded(self):
        self.item["size"] -= 1
        with mock.patch.object(MODULE.urllib.request, "urlopen", return_value=self.response(self.packed)):
            with self.assertRaisesRegex(ValueError, "unpacked model exceeds"):
                MODULE.ensure_cached(self.item, self.root, False)

    def test_corrupt_cache_is_rejected_without_network(self):
        (self.root / self.item["sha256"]).write_bytes(b"broken")
        with mock.patch.object(MODULE.urllib.request, "urlopen") as fetch:
            with self.assertRaisesRegex(ValueError, "integrity mismatch"):
                MODULE.ensure_cached(self.item, self.root, False)
            fetch.assert_not_called()

    def test_missing_offline_cache_does_not_use_network(self):
        with mock.patch.object(MODULE.urllib.request, "urlopen") as fetch:
            with self.assertRaisesRegex(ValueError, "cache unavailable"):
                MODULE.ensure_cached(self.item, self.root, True)
            fetch.assert_not_called()

    def test_real_manifest_has_only_pinned_directions_and_sizes(self):
        manifest = MODULE.read_manifest()
        self.assertEqual({f["path"].split("/")[1] for f in manifest["files"]}, {"en-zh", "zh-en"})
        self.assertEqual(sum(f["size"] for f in manifest["files"]), 104470603)


if __name__ == "__main__":
    unittest.main()
