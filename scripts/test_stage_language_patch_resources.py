"""Synthetic safety tests; these do not execute an installer, engine, or 7-Zip."""
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
import warnings
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
SPEC = importlib.util.spec_from_file_location("stage_language_patch_resources", Path(__file__).with_name("stage-language-patch-resources.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def identity(data):
    return {"size": len(data), "sha256": MODULE.hashlib.sha256(data).hexdigest()}


def listing(expected, prefix="$INSTDIR/offline-translation"):
    return "\n\n".join("Path = " + prefix + "/" + name + "\nSize = " + str(value["size"])
                         + "\nAttributes = A" for name, value in expected.items())


class PatchResourceTests(unittest.TestCase):
    def test_fixed_release_provenance_and_no_fresh_acceptance_claim(self):
        self.assertEqual(MODULE.BASELINE_RUN, 41178655504)
        self.assertEqual(MODULE.BASELINE_COMMIT, "4b8c5f5ac67e07cc4005812963b2c02acdd14d5d")
        self.assertEqual(MODULE.ARTIFACTS["windows"]["id"], 13034542412)
        self.assertEqual(MODULE.ARTIFACTS["evidence"]["id"], 13034970610)
        source = Path(MODULE.__file__).read_text()
        for field in ("newInstallerAccepted", "installerExecuted", "engineExecuted", "visualTestsExecuted", "oldApplicationStaged", "visualAcceptanceRepeated"):
            self.assertIn('"' + field + '": False', source)
        self.assertIn('"validationMode": "language-routing-patch-v1"', source)
        self.assertIn('verify_installed_acceptance(report_bytes.decode("utf-8-sig"), stage_bytes)', source)
        self.assertNotIn('shell=True', source)
        self.assertNotIn('extractall(', source)
        self.assertEqual(source.count('subprocess.run('), 2)

    def test_exact_resource_root_and_windows_separators(self):
        expected = {"bin/echolingo-offline-engine.exe": identity(b"MZtest"), "models/en-zh/model.bin": identity(b"model")}
        prefix, entries = MODULE.parse_listing(listing(expected).replace("/", "\\"), expected)
        self.assertEqual(prefix, "$INSTDIR/offline-translation")
        self.assertEqual(set(entries), set(expected))
        prefix, _ = MODULE.parse_listing(listing(expected, "offline-translation"), expected)
        self.assertEqual(prefix, "offline-translation")

    def test_listing_rejects_missing_extra_alias_wrong_size_and_links(self):
        expected = {"bin/engine.exe": identity(b"MZtest")}
        valid = listing(expected)
        failures = ["", valid.replace("Size = 6", "Size = 7"), valid + "\n\n" + valid,
                    valid + "\n\n" + valid.replace("$INSTDIR", "$OTHER"),
                    valid + "\n\nPath = $INSTDIR/offline-translation/old-app.exe\nSize = 2",
                    valid + "\nSymbolic Link = outside", valid.replace("engine.exe", "ENGINE.EXE")]
        for text in failures:
            with self.subTest(text=text), self.assertRaises(ValueError):
                MODULE.parse_listing(text, expected)

    def test_unsafe_paths_are_rejected_before_extraction(self):
        for path in ("../file", "/root/file", "C:/file", "a//file", "a/./file", "a/NUL.txt",
                     "a/file:stream", "a/file.", "a/file ", "a/*", "a/line\nfile", "a\\..\\file"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                MODULE.safe_name(path)

    def test_zip_member_exact_size_digest_and_unique_name(self):
        payload = b"pinned synthetic source"
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            archive.writestr("source.zip", payload)
        with zipfile.ZipFile(stream) as archive:
            self.assertEqual(MODULE.zip_member(archive, "source.zip", identity(payload)), payload)
            for expected in (identity(b"other"), {**identity(payload), "size": len(payload) + 1}):
                with self.assertRaises(ValueError):
                    MODULE.zip_member(archive, "source.zip", expected)
            with self.assertRaises(ValueError):
                MODULE.zip_member(archive, "absent", identity(payload))
        duplicate = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(duplicate, "w") as archive:
                archive.writestr("source.zip", payload)
                archive.writestr("source.zip", payload)
        with zipfile.ZipFile(duplicate) as archive, self.assertRaises(ValueError):
            MODULE.zip_member(archive, "source.zip", identity(payload))
        redirected = io.BytesIO()
        with zipfile.ZipFile(redirected, "w") as archive:
            member = zipfile.ZipInfo("source.zip")
            member.external_attr = 0o120777 << 16
            archive.writestr(member, payload)
        with zipfile.ZipFile(redirected) as archive, self.assertRaises(ValueError):
            MODULE.zip_member(archive, "source.zip", identity(payload))

    def test_existing_output_and_mutated_inputs_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.zip"
            path.write_bytes(b"original")
            MODULE.check_file(path, identity(b"original"))
            with self.assertRaises(ValueError):
                MODULE.check_file(path, identity(b"different"))
            self.assertEqual(path.read_bytes(), b"original")
            link = Path(directory) / "link"
            try:
                link.symlink_to(path)
            except OSError:
                return  # Windows non-developer accounts may lack symlink privilege.
            with self.assertRaises(ValueError):
                MODULE.check_file(link, identity(b"original"))

    def test_stage_only_generated_resources_and_never_replace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            extracted = root / "extracted"
            extracted.mkdir()
            expected = {"bin/echolingo-offline-engine.exe": identity(b"MZtest"),
                        "models/en-zh/model.bin": identity(b"model")}
            for name, data in (("bin/echolingo-offline-engine.exe", b"MZtest"), ("models/en-zh/model.bin", b"model")):
                source = extracted / name
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_bytes(data)
            with patch.object(MODULE, "ROOT", root):
                MODULE.stage_generated(extracted, expected)
                MODULE.stage_generated(extracted, expected)
                target = root / "resources/offline-translation/bin/echolingo-offline-engine.exe"
                target.write_bytes(b"another existing build")
                with self.assertRaises(ValueError):
                    MODULE.stage_generated(extracted, expected)
                self.assertEqual(target.read_bytes(), b"another existing build")
                (extracted / "old-app.exe").write_bytes(b"MZapp")
                with self.assertRaises(ValueError):
                    MODULE.stage_generated(extracted, {"old-app.exe": identity(b"MZapp")})
                self.assertFalse((root / "resources/offline-translation/old-app.exe").exists())


if __name__ == "__main__":
    unittest.main()
