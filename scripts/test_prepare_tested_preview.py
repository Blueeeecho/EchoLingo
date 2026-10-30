import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "tested_preview", Path(__file__).with_name("prepare-tested-preview.py"))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


def archive_bytes(entries):
    out = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in entries:
                archive.writestr(name, data)
    return out.getvalue()


class TestedPreviewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archives = self.root / "archives"
        self.archives.mkdir()
        self.output = self.root / "output"
        self.windows = b"accepted Windows 0.2.2 installer"
        self.mac = b"tested macOS 0.2.2 installer"
        source_data = b"corresponding offline source"
        inventory = {"formatVersion": 1, "files": [{
            "path": "main.cpp", "size": len(source_data),
            "sha256": hashlib.sha256(source_data).hexdigest()}]}
        self.source = archive_bytes([
            ("main.cpp", source_data), ("SOURCE-MANIFEST.json", json.dumps(inventory))])
        self.report = {field: True for field in (
            "ok", "windowsRuntimeExecuted", "installerExecuted", "realModelExecuted",
            "rulesRemoved", "ownedInstallRemoved")}
        self.report.update(mockTranslationUsed=False,
                           installerSha256=hashlib.sha256(self.windows).hexdigest(),
                           installerBytes=len(self.windows))
        self.write_archives()

    def write_archives(self):
        contents = [
            [("nsis/EchoLingo_0.2.2_x64-setup.exe", self.windows)],
            [("dmg/EchoLingo_0.2.2_aarch64.dmg", self.mac)],
            [("temp/echolingo-offline-validation.json", json.dumps(self.report)),
             ("temp/EchoLingo-offline-engine-source.zip", self.source)],
        ]
        self.pins = []
        for artifact, entries in zip(M.ARTIFACTS, contents):
            data = archive_bytes(entries)
            (self.archives / (artifact["name"] + ".zip")).write_bytes(data)
            self.pins.append({**artifact, "size": len(data),
                              "sha256": hashlib.sha256(data).hexdigest()})

    def prepare(self):
        with patch.object(M, "ARTIFACTS", self.pins):
            return M.prepare(self.archives, self.output, "a" * 40)

    def extract(self, entries):
        data = archive_bytes(entries)
        source = self.root / "fixture.zip"
        source.write_bytes(data)
        expected = {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        return M.extract_pinned(source, self.root / "extracted", expected)

    def test_production_pins_are_exact(self):
        self.assertEqual(M.VERSION, "0.2.2")
        self.assertEqual(M.SOURCE, "4ea25907fdaf4477f3aaf92b41973668b507f528")
        self.assertEqual(M.SOURCE_TREE, "87825bd8b1bfdb304ca9e21857d5a09769327932")
        self.assertEqual(M.BUILD_CHECKOUT, "8b8cfcf6abee1297f5ef220154a0a28fb18cb63c")
        self.assertEqual(M.RUN, 41053405841)
        self.assertEqual([(a["id"], a["size"], a["sha256"]) for a in M.ARTIFACTS], [
            (12976667329, 75445810, "cb6405255d570fc31dec7a125921518126dbb709960bc4361f24b51622e4a3cd"),
            (12975917340, 4916850, "8e980f9c4ccf37b72cecd551205c1d822962d789391446bb357d876572d8ec47"),
            (12976667318, 18088658, "8a77e655aa802067c080473f7715a1e075317a79b97dfb87e5862f82687aae20"),
        ])

    def test_exact_bytes_provenance_failure_disclosure_and_checksums(self):
        manifest = self.prepare()
        self.assertEqual(manifest["commit"], M.SOURCE)
        self.assertEqual(manifest["sourceCommit"], M.SOURCE)
        self.assertEqual(manifest["sourceTree"], M.SOURCE_TREE)
        self.assertEqual(manifest["buildCheckoutCommit"], M.BUILD_CHECKOUT)
        self.assertEqual(manifest["publisherCommit"], "a" * 40)
        self.assertFalse(manifest["rebuiltAfterValidation"])
        self.assertTrue(manifest["windowsInstalledAcceptanceVerified"])
        verification = manifest["verification"]
        self.assertEqual(verification["runId"], M.RUN)
        self.assertEqual(verification["overallRunConclusion"], "success")
        self.assertEqual(verification["windowsJobId"], 124054804159)
        self.assertEqual(verification["macosJobId"], 124054803658)
        self.assertEqual(verification["frontendJobId"], 124054803992)
        self.assertEqual(len(verification["artifacts"]), 3)
        later = manifest["laterValidation"]
        self.assertEqual(later["sourceCommit"], M.LATER_SOURCE)
        self.assertEqual(later["runId"], 41056149811)
        self.assertEqual(later["conclusion"], "failure")
        self.assertEqual(later["gate"], "rigorousSelection")
        self.assertEqual(later["error"], "MOCK_CONTROLLED_REPLY_NOT_RELEASED")
        self.assertFalse(later["fixed"])
        self.assertTrue(later["userRetestingRequired"])
        self.assertEqual((self.output / "EchoLingo_0.2.2_windows_x64-setup.exe").read_bytes(), self.windows)
        self.assertEqual((self.output / "EchoLingo_0.2.2_macos_arm64.dmg").read_bytes(), self.mac)
        self.assertEqual((self.output / "EchoLingo-offline-engine-source.zip").read_bytes(), self.source)
        self.assertEqual(len(list(self.output.iterdir())), 5)
        lines = (self.output / "SHA256SUMS.txt").read_text().splitlines()
        self.assertEqual(len(lines), 4)
        self.assertTrue(any(line.endswith("  RELEASE-MANIFEST.json") for line in lines))
        for line in lines:
            digest, name = line.split("  ", 1)
            self.assertEqual(digest, M.sha256(self.output / name))

    def test_invalid_publisher_and_existing_output_fail(self):
        for publisher in ("main", "A" * 40, "a" * 39):
            with self.assertRaisesRegex(ValueError, "publisher"):
                M.prepare(self.archives, self.output, publisher)
        self.output.mkdir()
        sentinel = self.output / "keep"; sentinel.write_text("unchanged")
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.prepare()
        self.assertEqual(sentinel.read_text(), "unchanged")

    def test_archive_digest_and_size_checked_before_extraction(self):
        path = self.archives / (self.pins[0]["name"] + ".zip")
        original = path.read_bytes()
        for changed in (b"x" * len(original), original + b"x"):
            path.write_bytes(changed)
            with self.assertRaisesRegex(ValueError, "Pinned artifact"):
                self.prepare()
            self.assertFalse(self.output.exists())

    def test_archive_symlink_rejected(self):
        source = self.archives / (self.pins[0]["name"] + ".zip")
        link = self.root / "link.zip"; link.symlink_to(source)
        with self.assertRaisesRegex(ValueError, "regular"):
            M.extract_pinned(link, self.root / "extracted", self.pins[0])

    def test_path_traversal_and_ambiguous_paths_rejected(self):
        for name in ("../escape", "/absolute", "a/../escape", "a/./file", "a//file",
                     "C:/drive", "a\\file", "a\nfile"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unsafe ZIP path"):
                self.extract([(name, b"x")])
            self.assertFalse((self.root / "extracted").exists())

    def test_symlink_and_special_member_rejected(self):
        for kind in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFSOCK):
            member = zipfile.ZipInfo("link"); member.create_system = 3
            member.external_attr = (kind | 0o777) << 16
            with self.assertRaisesRegex(ValueError, "file type"):
                self.extract([(member, b"target")])
            self.assertFalse((self.root / "extracted").exists())

    def test_duplicate_paths_and_file_directory_collisions_rejected(self):
        for entries in [ [("file", b"a"), ("file", b"b")],
                         [("File", b"a"), ("file", b"b")],
                         [("a", b"a"), ("a/file", b"b")],
                         [("a/file", b"b"), ("A", b"a")] ]:
            with self.assertRaisesRegex(ValueError, "Duplicate|collision"):
                self.extract(entries)
            self.assertFalse((self.root / "extracted").exists())

    def test_size_bomb_and_entry_count_limits(self):
        for name, value, entries in [
            ("MAX_MEMBER_BYTES", 3, [("large", b"1234")]),
            ("MAX_TOTAL_BYTES", 5, [("one", b"123"), ("two", b"456")]),
            ("MAX_ENTRIES", 1, [("one", b"a"), ("two", b"b")]),
        ]:
            with patch.object(M, name, value), self.assertRaisesRegex(ValueError, "size limit|entry count"):
                self.extract(entries)
            self.assertFalse((self.root / "extracted").exists())

    def test_encryption_and_unsupported_compression_rejected(self):
        for flags, compression in ((1, zipfile.ZIP_STORED), (0, zipfile.ZIP_BZIP2)):
            member = zipfile.ZipInfo("file"); member.flag_bits = flags; member.compress_type = compression
            class Archive:
                def infolist(self): return [member]
            with self.assertRaisesRegex(ValueError, "encryption or compression"):
                M.validate_members(Archive())

    def test_nul_truncated_name_rejected(self):
        member = zipfile.ZipInfo("safe\x00hidden")
        class Archive:
            def infolist(self): return [member]
        with self.assertRaisesRegex(ValueError, "Unsafe ZIP path"):
            M.validate_members(Archive())

    def test_installed_acceptance_and_source_inventory_are_not_bypassed(self):
        self.report["mockTranslationUsed"] = True; self.write_archives()
        with self.assertRaisesRegex(ValueError, "mock"):
            self.prepare()
        self.assertFalse(self.output.exists())
        self.report["mockTranslationUsed"] = False
        self.report["installerSha256"] = "0" * 64; self.write_archives()
        with self.assertRaisesRegex(ValueError, "accepted bytes"):
            self.prepare()
        self.assertFalse(self.output.exists())
        self.report["installerSha256"] = hashlib.sha256(self.windows).hexdigest()
        self.source = archive_bytes([("SOURCE-MANIFEST.json", '{"formatVersion":1,"files":[]}')])
        self.write_archives()
        with self.assertRaisesRegex(ValueError, "inventory"):
            self.prepare()
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
