"""Generated static fixtures only: no installers, native apps or permission APIs."""
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("inspect_candidate", Path(__file__).with_name("inspect-candidate-package.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def listing(*records):
    header = "7-Zip fixture\n\n--\nPath = fixture.exe\nType = Nsis\n\n----------\n"
    return header + "\n\n".join("\n".join(f"{k} = {v}" for k, v in record.items()) for record in records) + "\n"


def entry(path="echolingo.exe", **extra):
    return {"Path": path, "Size": "512", "Attributes": "A", **extra}


def pe(machine=0x8664, magic=0x20B, flags=2):
    value = bytearray(512)
    value[:2] = b"MZ"
    struct.pack_into("<I", value, 60, 64)
    value[64:68] = b"PE\0\0"
    struct.pack_into("<HHIIIHHH", value, 68, machine, 1, 0, 0, 0, 112, flags, magic)
    return value


def macho(cpu=0x0100000C, filetype=2):
    return struct.pack("<IIIIIIII", 0xFEEDFACF, cpu, 0, filetype, 0, 0, 0, 0)


class CandidateInspectionTests(unittest.TestCase):
    def test_exact_nsis_member_and_windows_separators(self):
        selected = MODULE.parse_7z_listing(listing(entry("$_OUTDIR\\echolingo.exe"), entry("resources/model.bin")))
        self.assertEqual(selected["Path"], "$_OUTDIR\\echolingo.exe")
        self.assertEqual(selected["normalizedPath"], "$_OUTDIR/echolingo.exe")
        self.assertEqual(selected["size"], 512)

    def test_unsafe_paths_rejected_before_extraction(self):
        for path in ("../echolingo.exe", "folder/../echolingo.exe", "/echolingo.exe", "\\echolingo.exe",
                     "C:\\echolingo.exe", "@folder/echolingo.exe", "folder//echolingo.exe", "./echolingo.exe", "folder./echolingo.exe",
                     "folder /echolingo.exe", "folder/echolingo.exe:stream", "folder/echo*.exe", "folder/echo?.exe",
                     "folder/echo\nlingo.exe", "folder/echo\x00lingo.exe"):
            with self.subTest(path=path), self.assertRaises(MODULE.InspectionError):
                MODULE.parse_7z_listing(listing(entry(path)))

    def test_duplicate_alias_or_multiple_application_rejected(self):
        for records in ((entry(), entry()), (entry(), entry("ECHOLINGO.EXE")),
                        (entry("first/echolingo.exe"), entry("second/echolingo.exe")),
                        (entry("dir\\echolingo.exe"), entry("dir/echolingo.exe")),
                        (entry(), entry("folder"), entry("folder/data.bin"))):
            with self.subTest(records=records), self.assertRaises(MODULE.InspectionError):
                MODULE.parse_7z_listing(listing(*records))

    def test_links_streams_encryption_and_directory_rejected(self):
        for extra in ({"Symbolic Link": "other.exe"}, {"Hard Link": "other.exe"}, {"Link": "other.exe"},
                      {"Copy Link": "other.exe"}, {"Reparse": "fixture"}, {"Links": "2"},
                      {"Attributes": "AL"}, {"Attributes": "A lrwxrwxrwx"}, {"Mode": "lrwxrwxrwx"},
                      {"Encrypted": "+"}, {"Anti": "+"}, {"Alternate Stream": "+"},
                      {"Folder": "+"}, {"Attributes": "D"}):
            with self.subTest(extra=extra), self.assertRaises(MODULE.InspectionError):
                MODULE.parse_7z_listing(listing(entry(**extra)))

    def test_listing_ambiguity_size_and_wrong_format_rejected(self):
        samples = [listing(entry()).replace("Type = Nsis", "Type = zip"),
                   listing(entry()).replace("----------", "--------"),
                   listing(entry()).replace("Size = 512", "Size = 512\nSize = 1"),
                   listing(entry(Size="")), listing(entry(Size="-1")), listing(entry(Size="0")),
                   listing(entry(Size=str(MODULE.MAX_EXECUTABLE + 1))), listing(entry("other.exe")),
                   listing(entry()) + "\n----------\n"]
        for value in samples:
            with self.subTest(value=value), self.assertRaises(MODULE.InspectionError):
                MODULE.parse_7z_listing(value)

    def test_pe_x64_executable_only(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "echolingo.exe"
            path.write_bytes(pe())
            MODULE.verify_pe(path)
            for value in (pe(machine=0x14C), pe(magic=0x10B), pe(flags=0x2002), pe(flags=0), b"MZ", b"not PE"):
                path.write_bytes(value)
                with self.assertRaises(MODULE.InspectionError):
                    MODULE.verify_pe(path)

    def test_windows_versions_require_both_numeric_and_display_match(self):
        valid = {"fileVersion": "0.2.6.0", "productVersion": "0.2.6", "fileParts": [0, 2, 6, 0], "productParts": [0, 2, 6, 0]}
        MODULE.verify_windows_version(valid)
        for key, value in (("fileVersion", "0.2.5"), ("fileVersion", "0.2.6.1"), ("productVersion", "0.2.6-preview"),
                           ("fileParts", [0, 2, 6, 1]), ("productParts", [0, 2, 5, 0]), ("fileParts", [False, 2, 6, 0])):
            with self.subTest(key=key, value=value), self.assertRaises(MODULE.InspectionError):
                MODULE.verify_windows_version({**valid, key: value})

    def test_macho_arm64_executable_only(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "echolingo"
            path.write_bytes(macho())
            MODULE.verify_macho(path)
            for value in (macho(cpu=0x01000007), macho(filetype=6), macho()[:16], b"\xca\xfe\xba\xbe" + bytes(28)):
                path.write_bytes(value)
                with self.assertRaises(MODULE.InspectionError):
                    MODULE.verify_macho(path)

    def test_bundle_member_cannot_escape_or_follow_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle = root / "EchoLingo.app"
            binary = bundle / "Contents/MacOS/echolingo"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(macho())
            self.assertEqual(MODULE.owned_bundle_file(bundle, "Contents/MacOS/echolingo"), binary.resolve())
            with self.assertRaises(MODULE.InspectionError):
                MODULE.owned_bundle_file(bundle, "../other")
            other = root / "other"
            other.write_bytes(macho())
            binary.unlink()
            binary.symlink_to(other)
            with self.assertRaises(MODULE.InspectionError):
                MODULE.owned_bundle_file(bundle, "Contents/MacOS/echolingo")

    def test_attachment_requires_one_owned_mount_and_device(self):
        mount = Path("/tmp/generated-owned-mount")
        valid = {"system-entities": [{"dev-entry": "/dev/disk9"}, {"dev-entry": "/dev/disk9s1", "mount-point": str(mount)}]}
        self.assertEqual(MODULE.validate_attach_result(plistlib.dumps(valid), mount), "/dev/disk9")
        for entities in ([{"dev-entry": "/dev/disk9", "mount-point": "/tmp/other"}],
                         [{"dev-entry": "/dev/disk9", "mount-point": str(mount)}, {"dev-entry": "/dev/disk2"}],
                         [{"dev-entry": "/dev/disk9s1", "mount-point": str(mount)}],
                         [{"dev-entry": "not-device", "mount-point": str(mount)}], []):
            with self.subTest(entities=entities), self.assertRaises(MODULE.InspectionError):
                MODULE.validate_attach_result(plistlib.dumps({"system-entities": entities}), mount)

    def test_detach_finally_on_inspection_error_and_attach_failure(self):
        for failed_attach in (False, True):
            with tempfile.TemporaryDirectory() as folder:
                mount = Path(folder) / "mount"
                calls = []
                def execute(command, **_):
                    calls.append(command)
                    if command[1] == "attach":
                        if failed_attach:
                            raise MODULE.InspectionError("generated attach failure")
                        data = {"system-entities": [{"dev-entry": "/dev/disk9"},
                                                    {"dev-entry": "/dev/disk9s1", "mount-point": str(mount)}]}
                        return subprocess.CompletedProcess(command, 0, plistlib.dumps(data), b"")
                    return subprocess.CompletedProcess(command, 0, b"", b"")
                with mock.patch.object(MODULE, "tool", return_value="hdiutil"), mock.patch.object(MODULE, "checked_command", side_effect=execute):
                    with self.assertRaises(MODULE.InspectionError):
                        with MODULE.readonly_dmg(Path(folder) / "fixture.dmg", mount):
                            raise MODULE.InspectionError("generated inspection failure")
                self.assertEqual([command[1] for command in calls], ["verify", "attach", "detach"])
                self.assertEqual(calls[-1][2], str(mount) if failed_attach else "/dev/disk9")
                self.assertIn("-readonly", calls[1])
                self.assertIn("-nobrowse", calls[1])
                self.assertIn("-noautoopen", calls[1])

    def test_bounded_capture_rejects_stdout_before_unbounded_allocation(self):
        result = MODULE.checked_command([sys.executable, "-c", "print('generated')"], maximum_bytes=32)
        self.assertEqual(result.stdout, b"generated\n")
        with self.assertRaisesRegex(MODULE.InspectionError, "output exceeds limit"):
            MODULE.checked_command([sys.executable, "-c", "print('x' * 2048)"], maximum_bytes=32)

    def test_failed_attach_detaches_its_reported_unmounted_device(self):
        with tempfile.TemporaryDirectory() as folder:
            calls = []
            def execute(command, **_):
                calls.append(command)
                if command[1] == "attach":
                    data = plistlib.dumps({"system-entities": [{"dev-entry": "/dev/disk9"}]})
                    return subprocess.CompletedProcess(command, 1, data, b"generated mount failure")
                return subprocess.CompletedProcess(command, 0, b"", b"")
            with mock.patch.object(MODULE, "tool", return_value="hdiutil"), mock.patch.object(MODULE, "checked_command", side_effect=execute):
                with self.assertRaises(MODULE.InspectionError):
                    with MODULE.readonly_dmg(Path(folder) / "fixture.dmg", Path(folder) / "mount"):
                        self.fail("Failed attachment must not inspect a bundle")
            self.assertEqual(calls[-1], ["hdiutil", "detach", "/dev/disk9"])

    def test_static_command_contract_has_no_launch_sign_or_permission_mutation(self):
        source = Path(MODULE.__file__).read_text()
        self.assertIn('[seven_zip, "e", "-so", "-spd", "--"', source)
        self.assertIn('"--verify", "--deep", "--strict"', source)
        self.assertIn('"CFBundleVersion"', source)
        self.assertIn('"CFBundleIdentifier"', source)
        self.assertIn('Signature=adhoc', source)
        for forbidden in ('"--sign"', '"--force"', '"chmod"', '"xattr"', '"spctl"', '"open"', 'Start-Process', 'os.chmod('):
            self.assertNotIn(forbidden, source)

    def test_attestations_and_native_platform_are_not_synthesized(self):
        with mock.patch.object(MODULE, "source_identity") as identity:
            with self.assertRaises(MODULE.InspectionError):
                MODULE.inspect("Windows", "missing", "missing", "missing", "https://github.com/a/b/actions/runs/1")
            with mock.patch.object(MODULE.sys, "platform", "linux"), self.assertRaises(MODULE.InspectionError):
                MODULE.inspect("Windows", "missing", "missing", "missing", "https://github.com/a/b/actions/runs/1",
                               locked_build_passed=True, focused_tests_passed=True)
            identity.assert_not_called()

    def test_report_only_after_matching_static_application_and_stable_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            installer = root / "EchoLingo_0.2.6_x64-setup.exe"
            built = root / "echolingo.exe"
            installer.write_bytes(b"generated installer container")
            built.write_bytes(pe())
            identity = ("a" * 40, "b" * 40)
            def extract(_, output):
                path = output / "echolingo.exe"
                path.write_bytes(built.read_bytes())
                return path
            with mock.patch.object(MODULE.sys, "platform", "win32"), mock.patch.object(MODULE, "source_identity", return_value=identity), mock.patch.object(MODULE, "inspect_windows", side_effect=extract):
                report = MODULE.inspect("Windows", installer, built, root / "inspection", "https://github.com/a/b/actions/runs/1",
                                        locked_build_passed=True, focused_tests_passed=True)
                self.assertEqual(report["version"], "0.2.6")
                self.assertEqual(report["applicationMetadata"], {"version": "0.2.6", "architecture": "x64"})
                self.assertEqual(report["applicationSha256"], report["extractedApplicationSha256"])
                self.assertTrue(all(value is True for value in report["checks"].values()))
                self.assertEqual(json.loads((root / "inspection/checks.json").read_text()), report)
                with self.assertRaises(MODULE.InspectionError):
                    MODULE.inspect("Windows", installer, built, root / "inspection", "https://github.com/a/b/actions/runs/1",
                                   locked_build_passed=True, focused_tests_passed=True)
            def mismatch(_, output):
                target = output / "echolingo.exe"
                target.write_bytes(b"different bytes")
                return target
            with mock.patch.object(MODULE.sys, "platform", "win32"), mock.patch.object(MODULE, "source_identity", return_value=identity), mock.patch.object(MODULE, "inspect_windows", side_effect=mismatch):
                with self.assertRaises(MODULE.InspectionError):
                    MODULE.inspect("Windows", installer, built, root / "mismatch", "https://github.com/a/b/actions/runs/1",
                                   locked_build_passed=True, focused_tests_passed=True)
                self.assertFalse((root / "mismatch/checks.json").exists())

    def test_source_gate_uses_clean_tracked_exact_commit_tree_and_version(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "src-tauri").mkdir()
            (root / "package.json").write_text('{"version":"0.2.6"}')
            (root / "src-tauri/tauri.conf.json").write_text('{"version":"0.2.6"}')
            (root / "src-tauri/Cargo.toml").write_text('[package]\nversion="0.2.6"\n')
            def git(*args):
                subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)
            git("init", "-q")
            git("add", ".")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "generated")
            commit, tree = MODULE.source_identity(root)
            self.assertRegex(commit, r"^[0-9a-f]{40}$")
            self.assertRegex(tree, r"^[0-9a-f]{40}$")
            (root / "untracked.log").write_text("generated output")
            self.assertEqual(MODULE.source_identity(root), (commit, tree))
            (root / "package.json").write_text('{"version":"0.2.5"}')
            with self.assertRaises(MODULE.InspectionError):
                MODULE.source_identity(root)
            git("add", ".")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "wrong-version")
            with self.assertRaises(MODULE.InspectionError):
                MODULE.source_identity(root)

    def test_source_manifests_use_utf8_even_with_cp1252_default(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "src-tauri").mkdir()
            manifests = {
                "package.json": '{"version":"0.2.6","description":"描述"}',
                "src-tauri/tauri.conf.json": '{"version":"0.2.6","productName":"描述"}',
                "src-tauri/Cargo.toml": '[package]\nversion="0.2.6"\ndescription="描述"\n',
            }
            for name, content in manifests.items():
                (root / name).write_text(content, encoding="utf-8")
            identity = ("a" * 40, "b" * 40)
            outputs = [str(root), "", "\n".join(identity)]
            git_results = [subprocess.CompletedProcess([], 0, value.encode("utf-8"), b"") for value in outputs]
            original_read_text = Path.read_text
            reads = []

            def cp1252_default(path, encoding=None, errors=None):
                reads.append((path.relative_to(root).as_posix(), encoding))
                return original_read_text(path, encoding="cp1252" if encoding is None else encoding, errors=errors)

            with mock.patch.object(Path, "read_text", cp1252_default):
                # These real UTF-8 bytes cannot be decoded using Windows' default
                # code page; explicit per-file encoding must bypass that default.
                for name in manifests:
                    with self.subTest(name=name), self.assertRaises(UnicodeDecodeError):
                        (root / name).read_text()
                reads.clear()
                with mock.patch.object(MODULE, "checked_command", side_effect=git_results):
                    self.assertEqual(MODULE.source_identity(root), identity)
            self.assertEqual(reads, [(name, "utf-8") for name in manifests])


if __name__ == "__main__":
    unittest.main()
