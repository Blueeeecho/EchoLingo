import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from test_verify_screenshot_editor_report import complete as screenshot_report


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
        self.windows = self.artifacts / f"EchoLingo-Windows/nsis/EchoLingo_{RELEASE.VERSION}_x64-setup.exe"
        self.macos = self.artifacts / f"EchoLingo-macOS/dmg/EchoLingo_{RELEASE.VERSION}_aarch64.dmg"
        self.report_path = self.artifacts / "EchoLingo-Windows-offline-evidence/temp/echolingo-offline-validation.json"
        for path, data in [(self.windows, b"accepted Windows installer"), (self.macos, b"tested Mac installer")]:
            path.parent.mkdir(parents=True)
            path.write_bytes(data)
        self.report = {field: True for field in ("ok", "windowsRuntimeExecuted", "installerExecuted", "realModelExecuted", "rulesRemoved", "ownedInstallRemoved")}
        self.report.update(mockTranslationUsed=False, installerSha256=RELEASE.sha256(self.windows), installerBytes=self.windows.stat().st_size)
        self.report.update(applicationSha256="a"*64, installedScreenshotEditorVerified=True, installedScreenshotEditor=screenshot_report(installed=True))
        self.report_path.parent.mkdir(parents=True)
        self.write_report()
        self.source = self.report_path.with_name("EchoLingo-offline-engine-source.zip")
        data = b"corresponding source fixture"
        inventory = {"formatVersion": 1, "files": [{"path": "main.cpp", "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}]}
        with zipfile.ZipFile(self.source, "w") as archive:
            archive.writestr("main.cpp", data)
            archive.writestr("SOURCE-MANIFEST.json", json.dumps(inventory))

        if RELEASE.VERSION == "0.2.12":
            # Exercise the retired publisher with synthetic historical evidence.
            # Its imported verifier now targets 0.2.13; do not retarget either
            # production publisher just to make these old fixture bytes pass.
            self.current_verifier_version = RELEASE.package_verifier.VERSION
            version = patch.object(RELEASE.package_verifier, "VERSION", RELEASE.VERSION)
            version.start(); self.addCleanup(version.stop)
            provenance = {"commit": "a" * 40, "tree": "b" * 40, "trackedWorktreeClean": True}
            mock = patch.object(RELEASE.package_verifier, "source_provenance", return_value=provenance)
            mock.start(); self.addCleanup(mock.stop)
            self.inspections = {}
            for platform, installer, executable in [("Windows", self.windows, "echolingo.exe"), ("macOS", self.macos, "echolingo")]:
                folder = self.artifacts / f"EchoLingo-package-inspection-{platform}"
                folder.mkdir()
                application = folder / executable
                application.write_bytes(f"generated {platform} app".encode())
                digest = RELEASE.sha256(application)
                checks = {"schemaVersion": 1, "platform": platform, "version": RELEASE.VERSION,
                          "commit": provenance["commit"], "tree": provenance["tree"],
                          "runUrl": "https://github.com/Blueeeecho/EchoLingo/actions/runs/123",
                          "checks": {name: True for name in RELEASE.package_verifier.CHECK_NAMES},
                          "applicationMetadata": {"version": RELEASE.VERSION, "architecture": "x64" if platform == "Windows" else "arm64"},
                          "installerSha256": RELEASE.sha256(installer), "applicationSha256": digest,
                          "extractedApplicationSha256": digest}
                self.inspections[platform] = folder / "checks.json"
                self.inspections[platform].write_text(json.dumps(checks))
                if platform == "Windows":
                    self.report["applicationSha256"] = digest
                    self.report["installedScreenshotEditor"]["applicationSha256"] = digest
            self.write_report()

    def write_report(self):
        self.report_path.write_text(json.dumps(self.report), encoding="utf-8-sig")

    def prepare(self):
        return RELEASE.prepare(self.artifacts, self.output, "a" * 40, "https://github.com/Blueeeecho/EchoLingo/actions/runs/123")

    def test_fresh_release_requires_every_package_inspection_identity_and_gate(self):
        for platform, path in self.inspections.items():
            original = json.loads(path.read_text())
            for field, value in [('version', '0.2.6'), ('commit', 'c' * 40), ('tree', 'c' * 40),
                                 ('runUrl', 'https://github.com/Blueeeecho/EchoLingo/actions/runs/999'),
                                 ('platform', 'wrong'), ('installerSha256', 'c' * 64),
                                 ('applicationSha256', 'c' * 64), ('extractedApplicationSha256', 'c' * 64),
                                 ('applicationMetadata', {}), ('schemaVersion', True)]:
                with self.subTest(platform=platform, field=field):
                    path.write_text(json.dumps({**original, field: value}))
                    with self.assertRaises(ValueError): self.prepare()
                    self.assertFalse(self.output.exists())
            for gate in original['checks']:
                with self.subTest(platform=platform, gate=gate):
                    path.write_text(json.dumps({**original, 'checks': {**original['checks'], gate: False}}))
                    with self.assertRaises(ValueError): self.prepare()
            path.write_text(json.dumps(original))

    def test_rejects_mismatched_checkout_or_installed_application(self):
        with patch.object(RELEASE.package_verifier, 'source_provenance', return_value={'commit': 'c' * 40, 'tree': 'b' * 40}):
            with self.assertRaisesRegex(ValueError, 'checked-out source'): self.prepare()
        self.report['applicationSha256'] = 'c' * 64
        self.report['installedScreenshotEditor']['applicationSha256'] = 'c' * 64
        self.write_report()
        with self.assertRaisesRegex(ValueError, 'inspected package'): self.prepare()

    def test_missing_package_inspection_is_not_installed_acceptance(self):
        self.inspections['macOS'].unlink()
        with self.assertRaisesRegex(ValueError, 'checks.json'): self.prepare()

    def test_new_release_cannot_use_historical_language_patch_mode(self):
        with self.assertRaisesRegex(ValueError, 'only authorized for 0.2.4'):
            RELEASE.prepare(self.artifacts, self.output, 'a' * 40,
                            'https://github.com/Blueeeecho/EchoLingo/actions/runs/123', language_patch=True)

    def test_retired_release_is_manual_and_never_reuses_old_package_diagnosis(self):
        root = Path(__file__).resolve().parents[1]
        workflow = (root / '.github/workflows/release.yml').read_text()
        trigger = workflow.split('permissions:', 1)[0]
        self.assertIn('  workflow_dispatch:', trigger)
        self.assertNotIn('  push:', trigger)
        self.assertNotIn('  pull_request:', trigger)
        checks = (root / '.github/workflows/release-checks.yml').read_text()
        self.assertIn("docs/releases/0.2.12.zh-CN.md", workflow)
        self.assertTrue((root / 'docs/releases/0.2.12.zh-CN.md').is_file())
        for historical in ('41271318023', '13069451922', 'release-10-diagnostic', '0.2.7'):
            self.assertNotIn(historical, checks)
        self.assertIn('name: Inspect exact fresh installer and packaged application bytes', checks)

    def test_release_inspects_app_and_dmg_and_preserves_failed_package_evidence(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / '.github/workflows/release-checks.yml').read_text()
        self.assertIn("'nsis' || 'app,dmg'", source)
        self.assertIn('python3 scripts/verify-native-pin-release-absence.py src-tauri/target/release/bundle/macos/EchoLingo.app/Contents/MacOS/echolingo', source)
        self.assertIn('release-native-pin-absence.json', source)
        self.assertIn('npm run tauri -- build --debug --no-bundle -- --locked', source)
        self.assertIn('bash tests/macos-pin-native-smoke.sh', source)
        self.assertIn('release-native-pin-smoke', source)
        inspection = source.split('      - name: Inspect exact fresh installer', 1)[1].split('      - name: Identify the actual embedded', 1)[0]
        self.assertIn('bundle/macos/EchoLingo.app/Contents/MacOS/echolingo', inspection)
        self.assertIn('scripts/inspect-candidate-package.py', inspection)
        self.assertIn('set -euo pipefail', inspection)
        self.assertNotIn('continue-on-error:', inspection)
        self.assertIn('if: always()', inspection)
        self.assertIn('release-package-inspection/checks.json', inspection)
        self.assertIn('release-package-inspection/7z-listing.txt', inspection)
        self.assertIn('EchoLingo.app.tar.gz', inspection)
        self.assertIn('src-tauri/target/release/bundle/dmg/*.dmg', source)
        workflow = (root / '.github/workflows/release.yml').read_text()
        self.assertNotIn('language-patch-checks.yml', workflow)
        self.assertNotIn('--language-patch', workflow)
        self.assertIn('pattern: EchoLingo-package-inspection-*', workflow)

    def test_installed_screenshot_evidence_is_required_and_bound_to_installed_bytes(self):
        for field in ("installedScreenshotEditorVerified", "installedScreenshotEditor"):
            original = self.report.pop(field)
            self.write_report()
            with self.assertRaises(ValueError): self.prepare()
            self.report[field] = original
        original = self.report.pop("applicationSha256")
        self.write_report()
        with self.assertRaises(ValueError): self.prepare()
        self.report["applicationSha256"] = original
        self.report["installedScreenshotEditor"]["applicationSha256"] = "b"*64
        self.write_report()
        with self.assertRaises(ValueError): self.prepare()

    def test_release_keeps_every_full_ci_gate_and_existing_priority_input_gate(self):
        root = Path(__file__).resolve().parents[1]
        ci = (root / ".github/workflows/ci.yml").read_text()
        start = ci.index("  macos-screenshot-native-probe:\n")
        end = ci.index("\n  windows-popup-diagnostics:", start)
        expected = ci[start:end]
        expected = "\n".join(line for line in expected.split("\n") if not line.startswith("    if: github.event.inputs.mode") and line != "    needs: validation-mode" and not line.startswith("    if: needs.validation-mode.outputs.mode"))
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
        # Only release-specific strengthening may differ: fresh app+DMG,
        # package inspection/evidence, native-capture formatting and version.
        normalized = release.split("jobs:\n", 1)[1]
        # Native pin execution is now common to full CI and release. Compare
        # every command, normalizing only the evidence directory/title.
        normalized = normalized.replace('against this release source', 'against this exact source')
        normalized = normalized.replace('release-native-pin', 'ci-native-pin')
        start = normalized.index('      - name: Inspect exact fresh installer')
        end = normalized.index('      - name: Identify the actual embedded', start)
        normalized = normalized[:start] + normalized[end:]
        # CI uploads pin evidence separately; release includes the same files
        # in its always-preserved package-inspection artifact above.
        start = expected.index('      - name: Preserve actual Mac pin lifecycle evidence')
        end = expected.index('      - name: Identify the actual embedded', start)
        expected = expected[:start] + expected[end:]
        normalized = normalized.replace('        id: package_build\n', '')
        normalized = normalized.replace('        run: |\n          cargo fmt --manifest-path src-tauri/Cargo.toml --check\n          cargo fmt --manifest-path src-tauri/native-capture/Cargo.toml --check', '        run: cargo fmt --manifest-path src-tauri/Cargo.toml --check')
        # Current frontend regression tests read immutable release history. The
        # historical 0.2.12 snapshot has no such dependency; normalize only this
        # exact stronger checkout setting, never test commands or job guards.
        checkout = '  frontend-interactions:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n'
        complete_history = checkout + '        with:\n          fetch-depth: 0\n'
        self.assertEqual(expected.count(complete_history), 1)
        expected = expected.replace(complete_history, checkout)
        self.assertEqual(normalized.strip(), expected.strip())
        self.assertNotIn("actions: read", release)

    def test_upper_window_acceptance_selects_exact_current_installer_in_both_workflows(self):
        root = Path(__file__).resolve().parents[1]
        for name in ('ci.yml', 'release-checks.yml'):
            source = (root / '.github/workflows' / name).read_text()
            step = source.split('        id: windows_capture_upper_windows', 1)[1].split('      - name:', 1)[0]
            self.assertIn('$version = (Get-Content package.json -Raw | ConvertFrom-Json).version', step)
            self.assertIn('$tauriVersion = (Get-Content src-tauri/tauri.conf.json -Raw | ConvertFrom-Json).version', step)
            self.assertIn("if ($version -notmatch '^\\d+\\.\\d+\\.\\d+$' -or $version -cne $tauriVersion) { throw", step)
            self.assertIn("$expectedInstaller = 'EchoLingo_{0}_x64-setup.exe' -f $version", step)
            self.assertIn('-Filter $expectedInstaller', step)
            self.assertIn("if ($installers.Count -ne 1) { throw", step)
            self.assertIn('-InstallerPath $installers[0].FullName -IsolatedTestSession', step)
            self.assertNotIn("-Filter '*", step)

    def test_publication_is_main_or_version_tag_only_and_keeps_prerelease_gate(self):
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github/workflows/release.yml").read_text()
        self.assertNotIn("pull_request:", workflow)
        self.assertIn('  workflow_dispatch:', workflow)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        self.assertIn(f"refs/tags/{RELEASE.VERSION}", workflow)
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
        files = ("package.json", "package-lock.json", "src-tauri/tauri.conf.json",
                 "src-tauri/Cargo.toml", "src-tauri/Cargo.lock",
                 "src-tauri/native-capture/Cargo.toml", "src-tauri/native-capture/Cargo.lock")
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory)
            # Test the historical version contract independently of the live
            # checkout, which correctly belongs to a different release now.
            fixtures = (
                json.dumps({'version': RELEASE.VERSION}),
                json.dumps({'version': RELEASE.VERSION, 'packages': {'': {'version': RELEASE.VERSION}}}),
                json.dumps({'version': RELEASE.VERSION}),
                f'[package]\nname = "echolingo"\nversion = "{RELEASE.VERSION}"\n',
                f'[[package]]\nname = "echolingo"\nversion = "{RELEASE.VERSION}"\n',
                f'[package]\nname = "echolingo-native-capture"\nversion = "{RELEASE.VERSION}"\n',
                f'[[package]]\nname = "echolingo-native-capture"\nversion = "{RELEASE.VERSION}"\n',
            )
            for name, content in zip(files, fixtures):
                destination = copy / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(content, encoding='utf-8')
            RELEASE.check_version(copy)
            for name in files[-2:]:
                path = copy / name
                original = path.read_text()
                path.write_text(original.replace('version = "0.2.12"', 'version = "0.2.3"'))
                with self.subTest(name=name), self.assertRaises(ValueError):
                    RELEASE.check_version(copy)
                path.write_text(original)

    def test_current_checkout_versions_are_consistent(self):
        root = Path(__file__).resolve().parents[1]
        current = json.loads((root / 'package.json').read_text(encoding='utf-8'))['version']
        with patch.object(RELEASE.package_verifier, 'VERSION', current):
            RELEASE.package_verifier.check_versions(root)

    def test_retired_release_rejects_current_checkout(self):
        root = Path(__file__).resolve().parents[1]
        current = json.loads((root / 'package.json').read_text(encoding='utf-8'))['version']
        self.assertNotEqual(current, RELEASE.VERSION)
        with self.assertRaisesRegex(ValueError, 'must be exactly 0.2.12'):
            RELEASE.check_version()

    def test_mismatched_verifier_version_still_rejects_historical_evidence(self):
        with patch.object(RELEASE.package_verifier, 'VERSION', '0.0.0'):
            with self.assertRaisesRegex(ValueError, 'source/run/package'):
                self.prepare()
        self.assertFalse(self.output.exists())

    def test_new_release_does_not_retarget_historical_macos_only_publication(self):
        root = Path(__file__).resolve().parents[1]
        historical = (root / ".github/workflows/release-macos-first.yml").read_text()
        self.assertIn("paths: [.github/workflows/release-macos-first.yml]", historical)
        self.assertNotIn("package.json", historical)
        publisher = (root / "scripts/publish-macos-first-release.cjs").read_text()
        self.assertIn("tag: '0.2.1'", publisher)
        self.assertIn("Release exists; no overwrite", publisher)
        self.assertEqual(RELEASE.VERSION, "0.2.12")

    def test_refuses_previous_version_installer_filename(self):
        self.windows.rename(self.windows.with_name("EchoLingo_0.2.3_x64-setup.exe"))
        with self.assertRaisesRegex(ValueError, "version or architecture"):
            self.prepare()

    def test_copies_exact_bytes_with_public_provenance_and_checksums(self):
        manifest = self.prepare()
        self.assertFalse(manifest["rebuiltAfterValidation"])
        self.assertEqual(len(manifest["files"]), 3)
        self.assertEqual(len(list(self.output.iterdir())), 5)
        self.assertEqual((self.output / "EchoLingo_0.2.12_windows_x64-setup.exe").read_bytes(), self.windows.read_bytes())
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
