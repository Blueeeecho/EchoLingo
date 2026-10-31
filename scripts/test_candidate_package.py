"""Synthetic provenance/header tests; these never claim actual package acceptance."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("candidate_verifier", Path(__file__).with_name("verify-candidate-package.py"))
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)
RUN_URL = "https://github.com/Blueeeecho/EchoLingo/actions/runs/12345"


def pe(machine=0x8664):
    result = bytearray(640)
    result[:2] = b"MZ"
    struct.pack_into("<I", result, 60, 128)
    result[128:132] = b"PE\0\0"
    struct.pack_into("<HH", result, 132, machine, 1)
    optional_size = 240 if machine == 0x8664 else 224
    struct.pack_into("<HH", result, 148, optional_size, 2)
    struct.pack_into("<H", result, 152, 0x20B if machine == 0x8664 else 0x10B)
    struct.pack_into("<I", result, 168, 4096)
    section = 152 + optional_size
    struct.pack_into("<IIII", result, section + 8, 128, 4096, 128, 512)
    struct.pack_into("<I", result, section + 36, 0x60000020)
    return result


def macho(cpu=0x0100000C):
    return struct.pack("<IIIIIIII", 0xFEEDFACF, cpu, 0, 2, 1, 8, 0, 0) + bytes(8)


def dmg():
    trailer = bytearray(512)
    trailer[:4] = b"koly"
    struct.pack_into(">II", trailer, 4, 4, 512)
    return b"synthetic-not-a-real-disk-image" + trailer


class CandidatePackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.root = self.folder / "source"
        self.root.mkdir()
        files = {
            "package.json": {"version": "0.2.6"},
            "package-lock.json": {"version": "0.2.6", "packages": {"": {"version": "0.2.6"}}},
            "src-tauri/tauri.conf.json": {"version": "0.2.6"},
            "src-tauri/Cargo.toml": '[package]\nname = "echolingo"\nversion = "0.2.6"\n',
            "src-tauri/Cargo.lock": '[[package]]\nname = "echolingo"\nversion = "0.2.6"\n',
            "src-tauri/native-capture/Cargo.toml": '[package]\nname = "echolingo-native-capture"\nversion = "0.2.6"\n',
            "src-tauri/native-capture/Cargo.lock": '[[package]]\nname = "echolingo-native-capture"\nversion = "0.2.6"\n',
        }
        for name, content in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(content) if isinstance(content, dict) else content, encoding="utf-8")
        self.git("init", "--quiet")
        self.git("config", "user.email", "synthetic@example.invalid")
        self.git("config", "user.name", "Synthetic Fixture")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "synthetic source")
        self.args = self.inputs()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def inputs(self, platform="macOS"):
        installer = self.folder / ("EchoLingo_0.2.6_aarch64.dmg" if platform == "macOS" else "EchoLingo_0.2.6_x64-setup.exe")
        application = self.folder / ("echolingo" if platform == "macOS" else "echolingo.exe")
        installer.write_bytes(dmg() if platform == "macOS" else pe(0x14C))
        application.write_bytes(macho() if platform == "macOS" else pe())
        args = SimpleNamespace(platform=platform, installer=installer, application=application,
                               checks_json=self.folder / (platform + "-checks.json"),
                               output=self.folder / (platform + "-CANDIDATE-MANIFEST.json"),
                               run_url=RUN_URL, offline_staging_manifest=None, offline_source_archive=None)
        provenance = VERIFY.source_provenance(self.root)
        checks = {"schemaVersion": 1, "platform": platform, "version": "0.2.6",
                  "commit": provenance["commit"], "tree": provenance["tree"], "runUrl": RUN_URL,
                  "checks": {name: True for name in VERIFY.CHECK_NAMES},
                  "applicationMetadata": {"version": "0.2.6", "architecture": "arm64" if platform == "macOS" else "x64"},
                  "installerSha256": VERIFY.sha256(installer), "applicationSha256": VERIFY.sha256(application),
                  "extractedApplicationSha256": VERIFY.sha256(application)}
        args.checks_json.write_text(json.dumps(checks), encoding="utf-8")
        return args

    def test_synthetic_manifest_has_hashes_but_never_installed_or_release_acceptance(self):
        result = VERIFY.run(self.args, self.root)
        self.assertEqual(len(result["versionManifests"]), 7)
        self.assertEqual(result["installer"]["sha256"], VERIFY.sha256(self.args.installer))
        self.assertEqual(result["application"]["sha256"], VERIFY.sha256(self.args.application))
        self.assertTrue(result["scope"]["buildAndStaticPackageEvidenceOnly"])
        self.assertTrue(all(value is False for key, value in result["scope"].items() if key != "buildAndStaticPackageEvidenceOnly"))
        self.assertIsNone(result["offlineResourceReuse"])
        lines = Path(str(self.args.output) + ".sha256").read_text().splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(any(line.endswith("  " + self.args.installer.name) for line in lines))
        self.assertFalse(any(line.endswith("  echolingo") for line in lines))

    def test_every_version_value_must_match(self):
        for name in VERIFY.VERSION_PATHS:
            path = self.root / name
            original = path.read_text()
            with self.subTest(path=name):
                path.write_text(original.replace("0.2.6", "0.2.4", 1))
                with self.assertRaises(ValueError):
                    VERIFY.check_versions(self.root)
            path.write_text(original)

    def test_duplicate_lock_own_package_is_rejected(self):
        path = self.root / "src-tauri/Cargo.lock"
        path.write_text(path.read_text() * 2)
        with self.assertRaisesRegex(ValueError, "Exactly one"):
            VERIFY.check_versions(self.root)

    def test_dirty_tracked_source_rejected_but_untracked_build_files_allowed(self):
        (self.root / "untracked-build.bin").write_bytes(b"build")
        VERIFY.source_provenance(self.root)
        (self.root / "package.json").write_text('{"version":"0.2.4"}')
        with self.assertRaisesRegex(ValueError, "Tracked source"):
            VERIFY.source_provenance(self.root)

    def test_bad_or_noncanonical_run_url_fails(self):
        for url in [RUN_URL + "?x=1", RUN_URL.replace("https:", "http:"), "https://github.com/other/repo/actions/runs/1", RUN_URL + "/"]:
            self.args.run_url = url
            with self.assertRaisesRegex(ValueError, "canonical"):
                VERIFY.run(self.args, self.root)

    def test_inspection_is_strict_and_bound_to_exact_bytes_and_source(self):
        good = VERIFY.read_json(self.args.checks_json)
        mutations = [{**good, key: "wrong"} for key in ["version", "commit", "tree", "runUrl", "installerSha256", "applicationSha256", "extractedApplicationSha256"]]
        mutations += [{**good, "extra": True}, {**good, "schemaVersion": True},
                      {**good, "applicationMetadata": {"version": "0.2.4", "architecture": "arm64"}}]
        for name in VERIFY.CHECK_NAMES:
            for invalid in [False, 1, "true", None]:
                changed = copy.deepcopy(good)
                changed["checks"][name] = invalid
                mutations.append(changed)
        for changed in mutations:
            with self.subTest(changed=changed):
                with self.assertRaises(ValueError):
                    VERIFY.check_attestations(changed, self.args.platform, VERIFY.source_provenance(self.root), RUN_URL,
                                              VERIFY.identity(self.args.installer), VERIFY.identity(self.args.application))

    def test_changed_installer_cannot_reuse_inspection_evidence(self):
        with self.args.installer.open("r+b") as output:
            output.write(b"X")
        with self.assertRaisesRegex(ValueError, "bound"):
            VERIFY.run(self.args, self.root)

    def test_duplicate_json_key_rejected(self):
        self.args.checks_json.write_text('{"schemaVersion":1,"schemaVersion":1}')
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            VERIFY.read_json(self.args.checks_json)

    def test_no_symlink_inputs_or_parent_paths(self):
        link = self.folder / "linked-app"
        try:
            link.symlink_to(self.args.application)
        except OSError:
            self.skipTest("Synthetic symlink creation is unavailable")
        with self.assertRaisesRegex(ValueError, "Symlink"):
            VERIFY.identity(link)
        parent = self.folder / "linked-source"
        parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symlink"):
            VERIFY.identity(parent / "package.json")

    def test_output_is_never_overwritten(self):
        self.args.output.write_text("keep")
        with self.assertRaises(ValueError):
            VERIFY.run(self.args, self.root)
        self.assertEqual(self.args.output.read_text(), "keep")

    def test_macos_rejects_windows_offline_provenance(self):
        self.args.offline_staging_manifest = self.folder / "unused.json"
        with self.assertRaisesRegex(ValueError, "cannot be attributed"):
            VERIFY.run(self.args, self.root)

    def test_windows_requires_resources_and_amd64_application(self):
        args = self.inputs("Windows")
        with self.assertRaisesRegex(ValueError, "require pinned"):
            VERIFY.run(args, self.root)
        args.application.write_bytes(pe(0x14C))
        with self.assertRaisesRegex(ValueError, "architecture"):
            VERIFY.check_headers("Windows", args.installer, args.application)

    def test_headers_reject_renamed_text_old_version_and_truncation(self):
        args = self.inputs("Windows")
        self.assertEqual(VERIFY.check_pe(args.installer), "PE-x86-installer-stub")
        self.assertEqual(VERIFY.check_pe(args.application, 0x8664), "PE-x64")
        for malformed in [b"MZ", b"MZ" + bytes(100), b"not PE", pe()[:500]]:
            args.application.write_bytes(malformed)
            with self.assertRaises(ValueError):
                VERIFY.check_pe(args.application, 0x8664)
        old = self.folder / "EchoLingo_0.2.4_aarch64.dmg"
        old.write_bytes(dmg())
        with self.assertRaisesRegex(ValueError, "filename"):
            VERIFY.check_headers("macOS", old, self.args.application)
        self.args.application.write_bytes(macho(0x01000007))
        with self.assertRaisesRegex(ValueError, "arm64"):
            VERIFY.check_headers("macOS", self.args.installer, self.args.application)

    def test_mac_header_checks_are_not_full_disk_image_validation(self):
        # Explicitly synthetic bytes pass only recognition. Inspection/build
        # evidence is separately mandatory; no executable is run in this suite.
        self.assertEqual(VERIFY.check_headers("macOS", self.args.installer, self.args.application)["installer"], "UDIF-header")
        self.args.installer.write_bytes(bytes(600))
        with self.assertRaisesRegex(ValueError, "UDIF"):
            VERIFY.check_headers("macOS", self.args.installer, self.args.application)

    def test_pinned_stager_cannot_be_replaced(self):
        path = self.root / "scripts/stage-language-patch-resources.py"
        path.parent.mkdir()
        path.write_text("raise RuntimeError('must not execute')")
        with self.assertRaisesRegex(ValueError, "stager differs"):
            VERIFY.verify_offline_reuse(self.root, self.folder / "manifest", self.folder / "source")

    def test_every_pinned_reuse_field_and_runtime_inventory_is_required(self):
        fingerprint = {"size": 12, "sha256": "a" * 64}
        stage = SimpleNamespace(BASELINE_COMMIT="b" * 40, BASELINE_TREE="c" * 40,
                                BASELINE_RUN=1234, ARTIFACTS={"windows": {"id": 123, **fingerprint}},
                                INSTALLER=fingerprint, REPORT=fingerprint, SOURCE=fingerprint, ENGINE=fingerprint)
        runtime = {"models/en-zh/synthetic.bin": fingerprint}
        good = {"ok": True, "validationMode": "language-routing-patch-v1",
                "baselineCommit": stage.BASELINE_COMMIT, "baselineTree": stage.BASELINE_TREE,
                "baselineRunId": stage.BASELINE_RUN, "baselineArtifacts": stage.ARTIFACTS,
                "baselineInstaller": stage.INSTALLER, "baselineInstallerSha256": fingerprint["sha256"],
                "baselineReport": stage.REPORT, "sourceArchive": stage.SOURCE, "engine": stage.ENGINE,
                "offlineResourcesVerified": True, "oldApplicationStaged": False,
                "newInstallerAccepted": False, "installerExecuted": False, "engineExecuted": False,
                "visualTestsExecuted": False, "visualAcceptanceRepeated": False,
                "runtimeFiles": [{"path": name, **value} for name, value in runtime.items()]}
        VERIFY.validate_reuse_metadata(good, stage, runtime)
        for field in good:
            with self.subTest(field=field):
                changed = copy.deepcopy(good)
                changed.pop(field)
                with self.assertRaises(ValueError):
                    VERIFY.validate_reuse_metadata(changed, stage, runtime)
        for field in ["oldApplicationStaged", "newInstallerAccepted", "installerExecuted", "engineExecuted"]:
            changed = {**good, field: True}
            with self.assertRaises(ValueError):
                VERIFY.validate_reuse_metadata(changed, stage, runtime)
        changed = {**good, "offlineResourcesVerified": 1}
        with self.assertRaises(ValueError):
            VERIFY.validate_reuse_metadata(changed, stage, runtime)

    def test_checked_in_stager_pin_matches_reviewed_lf_content(self):
        path = Path(__file__).with_name("stage-language-patch-resources.py")
        content = path.read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(VERIFY.hashlib.sha256(content).hexdigest(), VERIFY.STAGER_SHA256)

    def test_windows_output_never_transfers_historical_acceptance(self):
        args = self.inputs("Windows")
        args.offline_staging_manifest = self.folder / "baseline-reuse.json"
        args.offline_source_archive = self.folder / "EchoLingo-offline-engine-source.zip"
        args.offline_source_archive.write_bytes(b"synthetic source only")
        offline = {"sourceArchive": VERIFY.identity(args.offline_source_archive), "currentInstallerAcceptanceTransferred": False}
        with patch.object(VERIFY, "verify_offline_reuse", return_value=offline):
            result = VERIFY.run(args, self.root)
        self.assertIs(result["scope"]["historicalInstallerAcceptanceTransferred"], False)
        self.assertEqual(len(Path(str(args.output) + ".sha256").read_text().splitlines()), 3)


if __name__ == "__main__":
    unittest.main()
