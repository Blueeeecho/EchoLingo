"""Generated static fixtures only: no installers, native apps or permission APIs."""
import importlib.util
import hashlib
import io
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
    def license_fixture(self, path, mutate=None):
        controls = {"LPic": [{"ID": "5000", "Data": b"synthetic reviewed mapping"}],
                    "STR#": [{"ID": "5000", "Data": b"synthetic reviewed buttons"}]}
        resources = {**controls, "TEXT": [{"ID": "5000", "Data": (MODULE.ROOT / "LICENSE").read_bytes()}]}
        if mutate: mutate(resources)
        data = plistlib.dumps({"resource-fork": resources})
        trailer = bytearray(512); trailer[:4] = b"koly"
        struct.pack_into(">II", trailer, 4, 4, 512)
        struct.pack_into(">QQ", trailer, 216, 8, len(data))
        path.write_bytes(b"fixture!" + data + trailer)
        return {key: sorted((item["ID"], hashlib.sha256(item["Data"]).hexdigest()) for item in value)
                for key, value in controls.items()}

    def test_only_exact_own_license_and_reviewed_mapping_can_supply_one_response(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.dmg"
            pins = self.license_fixture(path)
            with mock.patch.object(MODULE, "OWN_EULA_CONTROLS", pins):
                self.assertEqual(MODULE.verified_own_dmg_license(path), b"y\n")
                for mutate in (lambda r: r["TEXT"][0].update(Data=b"unknown terms"),
                               lambda r: r["TEXT"].append(dict(r["TEXT"][0])),
                               lambda r: r.update({"RTF ": [{"ID": "5000", "Data": b"other terms"}]}),
                               lambda r: r["LPic"][0].update(Data=b"changed mapping"),
                               lambda r: r.pop("TEXT")):
                    self.license_fixture(path, mutate)
                    with self.subTest(mutate=mutate), self.assertRaises(MODULE.InspectionError):
                        MODULE.verified_own_dmg_license(path)

    def test_license_parser_rejects_bad_bounds_and_duplicate_keys(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.dmg"
            self.license_fixture(path)
            data = bytearray(path.read_bytes())
            struct.pack_into(">QQ", data, len(data) - 512 + 216, len(data), 100)
            path.write_bytes(data)
            with self.assertRaisesRegex(MODULE.InspectionError, "Unbounded"):
                MODULE.verified_own_dmg_license(path)
            self.license_fixture(path)
            data = path.read_bytes(); metadata = data[8:-512]
            metadata = metadata.replace(b"<dict>", b"<dict><key>resource-fork</key><dict/>", 1)
            trailer = bytearray(data[-512:]); struct.pack_into(">QQ", trailer, 216, 8, len(metadata))
            path.write_bytes(b"fixture!" + metadata + trailer)
            with self.assertRaisesRegex(MODULE.InspectionError, "Duplicate"):
                MODULE.verified_own_dmg_license(path)

    def test_verified_license_prompt_prefix_does_not_replace_attachment_metadata(self):
        data = plistlib.dumps({"system-entities": [{"dev-entry": "/dev/disk9"}]})
        self.assertEqual(MODULE.own_license_attachment_plist(b"generated own-license prompt\n" + data), data)
        for invalid in (data + data, b"prompt without metadata", b"x" * 32769 + data):
            with self.assertRaises(MODULE.InspectionError): MODULE.own_license_attachment_plist(invalid)

    def test_unknown_license_fails_before_attach_and_generic_input_is_forbidden(self):
        with tempfile.TemporaryDirectory() as folder:
            with mock.patch.object(MODULE, "tool", return_value="hdiutil"), mock.patch.object(MODULE, "checked_command") as command, \
                    mock.patch.object(MODULE, "verified_own_dmg_license", side_effect=MODULE.InspectionError("unknown terms")):
                with self.assertRaisesRegex(MODULE.InspectionError, "unknown terms"):
                    with MODULE.readonly_dmg(Path(folder) / "fixture.dmg", Path(folder) / "mount"): pass
                self.assertEqual(command.call_count, 1)
                self.assertEqual(command.call_args.args[0][1], "verify")
        with self.assertRaises(MODULE.InspectionError):
            MODULE.checked_command([sys.executable, "-c", "print('never run')"], stdin_bytes=b"y\n")

    def test_exact_nsis_member_and_windows_separators(self):
        selected = MODULE.parse_7z_listing(listing(entry("$_OUTDIR\\echolingo.exe"), entry("resources/model.bin")))
        self.assertEqual(selected["Path"], "$_OUTDIR\\echolingo.exe")
        self.assertEqual(selected["normalizedPath"], "$_OUTDIR/echolingo.exe")
        self.assertEqual(selected["size"], 512)

    def test_unknown_ignored_nsis_sizes_do_not_weaken_selected_application_bounds(self):
        for ignored in ({"Path": "uninstall.exe", "Attributes": "A"},
                        entry("resources/model.bin", Size=""),
                        {"Path": "resources", "Attributes": "D"}):
            with self.subTest(ignored=ignored):
                selected = MODULE.parse_7z_listing(listing(entry(), ignored))
                self.assertEqual(selected["normalizedPath"], "echolingo.exe")
                self.assertEqual(selected["size"], 512)
        for selected in ({"Path": "echolingo.exe", "Attributes": "A"}, entry(Size="")):
            with self.subTest(selected=selected), self.assertRaisesRegex(MODULE.InspectionError, "Application member size"):
                MODULE.parse_7z_listing(listing(selected, entry("resources/model.bin")))

    def test_selected_missing_nsis_size_is_bounded_by_fresh_binary_not_archive_metadata(self):
        unknown = listing({"Path": "echolingo.exe", "Attributes": "A"})
        self.assertEqual(MODULE.parse_7z_listing(unknown, 512)["size"], 512)
        self.assertEqual(MODULE.parse_7z_listing(listing(entry(Size="")), 512)["size"], 512)
        with self.assertRaisesRegex(MODULE.InspectionError, "differs from fresh"):
            MODULE.parse_7z_listing(listing(entry(Size="513")), 512)
        for size in (0, -1, True, MODULE.MAX_EXECUTABLE + 1):
            with self.subTest(size=size), self.assertRaises(MODULE.InspectionError):
                MODULE.parse_7z_listing(unknown, size)

    def test_extraction_reads_at_most_one_byte_past_known_size_and_requires_exact_length(self):
        class Stream(io.BytesIO):
            def read(self, size):
                self.requests.append(size)
                return super().read(size)
        for payload in (b"ab", b"abc", b"abcdef"):
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as folder:
                stream = Stream(payload)
                stream.requests = []
                process = mock.Mock(stdout=stream)
                process.wait.return_value = 0
                process.poll.return_value = 0
                with mock.patch.object(MODULE.subprocess, "Popen", return_value=process):
                    args = ("7z", "generated.exe", {"Path": "echolingo.exe", "size": 3}, Path(folder) / "app.exe")
                    if len(payload) == 3:
                        MODULE.extract_windows_member(*args)
                        self.assertEqual(args[-1].read_bytes(), payload)
                    else:
                        with self.assertRaises(MODULE.InspectionError): MODULE.extract_windows_member(*args)
                self.assertTrue(stream.requests and all(0 < size <= 4 for size in stream.requests))

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
                with mock.patch.object(MODULE, "verified_own_dmg_license", return_value=b"y\n"), mock.patch.object(MODULE, "tool", return_value="hdiutil"), mock.patch.object(MODULE, "checked_command", side_effect=execute):
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

    def test_hdiutil_errors_name_verb_and_bound_redact_stderr_not_stdout(self):
        result = subprocess.CompletedProcess(["/usr/bin/hdiutil", "attach", "/generated-owned/build/own.dmg"], 1,
                    b"license text must not be logged", b"hdiutil: attach failed: /generated-owned/build/own.dmg permission denied\n" + b"x" * 4096)
        message = MODULE.command_failure(result)
        self.assertIn("hdiutil attach failed (exit 1)", message)
        self.assertIn("permission denied", message)
        self.assertNotIn("/generated-owned", message)
        self.assertNotIn("license text", message)
        self.assertLess(len(message), 600)

    def test_failed_attach_prompt_and_cleanup_keep_primary_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            mount = Path(folder) / "mount"
            calls = []
            def execute(command, **_):
                calls.append(command)
                if command[1] == "attach":
                    return subprocess.CompletedProcess(command, 1, b"generated prompt, not a plist",
                                                       b"hdiutil: attach failed - permission denied")
                if command[1] == "detach":
                    raise MODULE.InspectionError("hdiutil detach failed (exit 1); stderr: not mounted")
                return subprocess.CompletedProcess(command, 0, b"", b"")
            with mock.patch.object(MODULE, "verified_own_dmg_license", return_value=b"y\n"), mock.patch.object(MODULE, "tool", return_value="hdiutil"), mock.patch.object(MODULE, "checked_command", side_effect=execute):
                with self.assertRaisesRegex(MODULE.InspectionError, "hdiutil attach failed.*permission denied.*cleanup also failed.*hdiutil detach"):
                    with MODULE.readonly_dmg(Path(folder) / "fixture.dmg", mount):
                        self.fail("Failed attach must not yield")
            self.assertEqual(calls[-1], ["hdiutil", "detach", str(mount)])

    def test_cleanup_failure_without_primary_still_fails_inspection(self):
        with tempfile.TemporaryDirectory() as folder:
            mount = Path(folder) / "mount"
            def execute(command, **_):
                if command[1] == "attach":
                    data = {"system-entities": [{"dev-entry": "/dev/disk9"}, {"dev-entry": "/dev/disk9s1", "mount-point": str(mount)}]}
                    return subprocess.CompletedProcess(command, 0, plistlib.dumps(data), b"")
                if command[1] == "detach": raise MODULE.InspectionError("generated detach failure")
                return subprocess.CompletedProcess(command, 0, b"", b"")
            with mock.patch.object(MODULE, "verified_own_dmg_license", return_value=b"y\n"), mock.patch.object(MODULE, "tool", return_value="hdiutil"), mock.patch.object(MODULE, "checked_command", side_effect=execute):
                with self.assertRaisesRegex(MODULE.InspectionError, "generated detach failure"):
                    with MODULE.readonly_dmg(Path(folder) / "fixture.dmg", mount): pass

    def test_failed_attach_detaches_its_reported_unmounted_device(self):
        with tempfile.TemporaryDirectory() as folder:
            calls = []
            def execute(command, **_):
                calls.append(command)
                if command[1] == "attach":
                    data = plistlib.dumps({"system-entities": [{"dev-entry": "/dev/disk9"}]})
                    return subprocess.CompletedProcess(command, 1, data, b"generated mount failure")
                return subprocess.CompletedProcess(command, 0, b"", b"")
            with mock.patch.object(MODULE, "verified_own_dmg_license", return_value=b"y\n"), mock.patch.object(MODULE, "tool", return_value="hdiutil"), mock.patch.object(MODULE, "checked_command", side_effect=execute):
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
            def extract(_, output, expected_size):
                self.assertEqual(expected_size, built.stat().st_size)
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
            def mismatch(_, output, expected_size):
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
