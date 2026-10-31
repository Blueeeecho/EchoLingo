import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile


SPEC = importlib.util.spec_from_file_location("prepare_release_assets", Path(__file__).with_name("prepare-release-assets.py"))
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class ReleaseAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.artifacts = self.root / "artifacts"
        self.output = self.root / "public"
        self.windows = self.artifacts / "EchoLingo-Windows/nsis/EchoLingo_0.2.4_x64-setup.exe"
        self.macos = self.artifacts / "EchoLingo-macOS/dmg/EchoLingo_0.2.4_aarch64.dmg"
        self.report_path = self.artifacts / "EchoLingo-Windows-offline-evidence/temp/echolingo-offline-validation.json"
        for path, data in [(self.windows, b"accepted Windows installer"), (self.macos, b"tested Mac installer")]:
            path.parent.mkdir(parents=True)
            path.write_bytes(data)
        self.report = {field: True for field in ("ok", "windowsRuntimeExecuted", "installerExecuted", "realModelExecuted", "rulesRemoved", "ownedInstallRemoved")}
        self.report.update(mockTranslationUsed=False, installerSha256=RELEASE.sha256(self.windows), installerBytes=self.windows.stat().st_size)
        self.report_path.parent.mkdir(parents=True)
        self.write_report()
        self.source = self.report_path.with_name("EchoLingo-offline-engine-source.zip")
        data = b"corresponding source fixture"
        inventory = {"formatVersion": 1, "files": [{"path": "main.cpp", "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}]}
        with zipfile.ZipFile(self.source, "w") as archive:
            archive.writestr("main.cpp", data)
            archive.writestr("SOURCE-MANIFEST.json", json.dumps(inventory))

    def write_report(self):
        self.report_path.write_text(json.dumps(self.report), encoding="utf-8-sig")

    def prepare(self):
        return RELEASE.prepare(self.artifacts, self.output, "a" * 40, "https://github.com/Blueeeecho/EchoLingo/actions/runs/123")

    def test_release_keeps_every_full_ci_gate_and_existing_priority_input_gate(self):
        root = Path(__file__).resolve().parents[1]
        ci = (root / ".github/workflows/ci.yml").read_text()
        start = ci.index("  desktop:\n")
        end = ci.index("\n  windows-popup-diagnostics:", start)
        expected = ci[start:end]
        expected = "\n".join(line for line in expected.split("\n") if not line.startswith("    if: github.event.inputs.mode"))
        old_matrix = "os: ${{ fromJSON(github.event.inputs.mode == 'macos-preview' && '[\"macos-latest\"]' || github.event.inputs.mode == 'windows-preview' && '[\"windows-latest\"]' || '[\"windows-latest\",\"macos-latest\"]') }}"
        self.assertIn(old_matrix, expected)
        expected = expected.replace(old_matrix, "os: [windows-latest, macos-latest]")
        priority = '''      - name: Windows exact priority keyboard and optional side-button input
        if: runner.os == 'Windows'
        timeout-minutes: 8
        shell: powershell
        run: powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-priority-input-smoke.ps1 -OutputDirectory "$env:RUNNER_TEMP/echolingo-release-priority-input" -IsolatedTestSession
'''
        marker = "      - name: Windows selected-text and clipboard desktop smoke\n"
        self.assertEqual(expected.count(marker), 1)
        expected = expected.replace(marker, priority + marker)
        release = (root / ".github/workflows/release-checks.yml").read_text()
        self.assertEqual(release.split("jobs:\n", 1)[1].strip(), expected.strip())
        self.assertNotIn("actions: read", release)

    def test_publication_is_main_or_version_tag_only_and_keeps_prerelease_gate(self):
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github/workflows/release.yml").read_text()
        self.assertNotIn("pull_request:", workflow)
        self.assertIn(f"tags: ['{RELEASE.VERSION}']", workflow)
        self.assertIn(f"refs/tags/{RELEASE.VERSION}", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn("needs: [release-inputs, verify]", workflow)
        self.assertIn("draft: true, prerelease: true", workflow)
        self.assertIn("main.object.sha !== context.sha", workflow)
        self.assertIn("already exists; inspect it instead of overwriting", workflow)
        self.assertIn(f"docs/releases/{RELEASE.VERSION}.zh-CN.md", workflow)
        self.assertTrue((root / f"docs/releases/{RELEASE.VERSION}.zh-CN.md").is_file())

    def test_native_capture_continuity_requires_embedded_bytes_and_raw_report(self):
        root = Path(__file__).resolve().parents[1]
        for name in ("ci.yml", "release-checks.yml"):
            workflow = (root / ".github/workflows" / name).read_text()
            desktop = workflow.split("  desktop:\n", 1)[1].split("\n  frontend-interactions:", 1)[0]
            gate = desktop.split("      - name: Windows embedded capture child continuous magnifier and input ownership", 1)[1].split("      - name:", 1)[0]
            self.assertIn("id: windows_native_capture_continuity", gate)
            self.assertIn("-NativeCapturePath '${{ steps.windows_native_candidate.outputs.capturePath }}'", gate)
            self.assertIn("tests/windows-native-capture-smoke.ps1", gate)
            self.assertIn("exit $fixtureExit", gate)
            self.assertIn("nativeCaptureContinuity = '${{ steps.windows_native_capture_continuity.outcome }}'", desktop)
            self.assertIn('python scripts/verify-native-capture-report.py "$env:RUNNER_TEMP/echolingo-native-capture-continuity.log"', desktop)
            self.assertIn("Embedded native capture acceptance report is missing, incomplete or failed.", desktop)
            self.assertLess(desktop.index("completeNativeCaptureEmbedded = $true"), desktop.index("id: windows_native_capture_continuity"))

    def test_version_guard_includes_native_capture_package_and_lock(self):
        root = Path(__file__).resolve().parents[1]
        import shutil
        files = ("package.json", "package-lock.json", "src-tauri/tauri.conf.json",
                 "src-tauri/Cargo.toml", "src-tauri/Cargo.lock",
                 "src-tauri/native-capture/Cargo.toml", "src-tauri/native-capture/Cargo.lock")
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory)
            for name in files:
                destination = copy / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / name, destination)
            RELEASE.check_version(copy)
            for name in files[-2:]:
                path = copy / name
                original = path.read_text()
                path.write_text(original.replace('version = "0.2.4"', 'version = "0.2.3"'))
                with self.subTest(name=name), self.assertRaises(ValueError):
                    RELEASE.check_version(copy)
                path.write_text(original)

    def test_versions_are_consistent(self):
        RELEASE.check_version()

    def test_new_release_does_not_retarget_historical_macos_only_publication(self):
        root = Path(__file__).resolve().parents[1]
        historical = (root / ".github/workflows/release-macos-first.yml").read_text()
        self.assertIn("paths: [.github/workflows/release-macos-first.yml]", historical)
        self.assertNotIn("package.json", historical)
        publisher = (root / "scripts/publish-macos-first-release.cjs").read_text()
        self.assertIn("tag: '0.2.1'", publisher)
        self.assertIn("Release exists; no overwrite", publisher)
        self.assertEqual(RELEASE.VERSION, "0.2.4")

    def test_refuses_previous_version_installer_filename(self):
        self.windows.rename(self.windows.with_name("EchoLingo_0.2.3_x64-setup.exe"))
        with self.assertRaisesRegex(ValueError, "version or architecture"):
            self.prepare()

    def test_copies_exact_bytes_with_public_provenance_and_checksums(self):
        manifest = self.prepare()
        self.assertFalse(manifest["rebuiltAfterValidation"])
        self.assertEqual(len(manifest["files"]), 3)
        self.assertEqual(len(list(self.output.iterdir())), 5)
        self.assertEqual((self.output / "EchoLingo_0.2.4_windows_x64-setup.exe").read_bytes(), self.windows.read_bytes())
        self.assertNotIn(str(self.root), (self.output / "RELEASE-MANIFEST.json").read_text())
        for line in (self.output / "SHA256SUMS.txt").read_text().splitlines():
            digest, name = line.split("  ", 1)
            self.assertEqual(digest, RELEASE.sha256(self.output / name))

    def test_refuses_every_missing_acceptance_gate(self):
        for field in ("ok", "windowsRuntimeExecuted", "installerExecuted", "realModelExecuted", "rulesRemoved", "ownedInstallRemoved"):
            with self.subTest(field=field):
                self.report[field] = False
                self.write_report()
                with self.assertRaises(ValueError):
                    self.prepare()
                self.report[field] = True
                self.assertFalse(self.output.exists())

    def test_refuses_mocked_acceptance(self):
        self.report["mockTranslationUsed"] = True
        self.write_report()
        with self.assertRaisesRegex(ValueError, "mock"):
            self.prepare()

    def test_refuses_installer_hash_or_size_mismatch(self):
        for field, value in [("installerSha256", "0" * 64), ("installerBytes", 1)]:
            original = self.report[field]
            self.report[field] = value
            self.write_report()
            with self.assertRaisesRegex(ValueError, "accepted bytes"):
                self.prepare()
            self.report[field] = original

    def test_refuses_ambiguous_and_wrong_version_installers(self):
        extra = self.windows.with_name("extra.exe")
        extra.write_bytes(b"extra")
        with self.assertRaisesRegex(ValueError, "Expected one"):
            self.prepare()
        extra.unlink()
        self.windows.rename(self.windows.with_name("EchoLingo_0.1.0_x64-setup.exe"))
        with self.assertRaisesRegex(ValueError, "version or architecture"):
            self.prepare()

    def test_refuses_missing_or_modified_corresponding_source(self):
        with zipfile.ZipFile(self.source, "w") as archive:
            archive.writestr("SOURCE-MANIFEST.json", json.dumps({"formatVersion": 1, "files": [{"path": "main.cpp", "size": 5, "sha256": "0" * 64}]}))
            archive.writestr("main.cpp", b"wrong")
        with self.assertRaisesRegex(ValueError, "integrity"):
            self.prepare()

    def test_never_overwrites_prepared_output(self):
        self.prepare()
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.prepare()

    def test_refuses_untrusted_provenance(self):
        with self.assertRaisesRegex(ValueError, "commit"):
            RELEASE.prepare(self.artifacts, self.output, "main", "https://github.com/Blueeeecho/EchoLingo/actions/runs/123")
        with self.assertRaisesRegex(ValueError, "run URL"):
            RELEASE.prepare(self.artifacts, self.output, "a" * 40, "https://example.com/run/123")


if __name__ == "__main__":
    unittest.main()
