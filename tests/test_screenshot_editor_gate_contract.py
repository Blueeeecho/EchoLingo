"""Native F1 editor results must remain independent of mock browser coverage."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ScreenshotEditorGateContract(unittest.TestCase):
    def test_built_app_raw_gate_is_mandatory_in_both_workflows(self):
        for name in ['ci.yml', 'release-checks.yml']:
            source = (ROOT / '.github/workflows' / name).read_text()
            self.assertIn('id: windows_screenshot_editor', source)
            self.assertIn('-ScreenshotEditorTests -DefaultCapture', source)
            self.assertIn("screenshotEditor = '${{ steps.windows_screenshot_editor.outcome }}'", source)
            self.assertIn('scripts/verify_screenshot_editor_report.py "$env:RUNNER_TEMP/echolingo-screenshot-editor.log" --application src-tauri/target/release/echolingo.exe', source)
            self.assertIn('Actual F1 editor acceptance report is missing, incomplete or failed.', source)
            self.assertIn('echolingo-installed-screenshot-editor.log', source)
            self.assertIn("nativeCaptureContinuity = '${{ steps.windows_native_capture_continuity.outcome }}'", source)

    def test_mac_probe_requires_pass_and_preserves_blocked_evidence(self):
        jobs = []
        for name in ['ci.yml', 'release-checks.yml']:
            source = (ROOT / '.github/workflows' / name).read_text()
            job = source.split('  macos-screenshot-native-probe:\n', 1)[1].split('  desktop:\n', 1)[0]
            jobs.append(job)
            self.assertIn('continue-on-error: true', job)
            self.assertIn('macos-screenshot-native-fixture.sh', job)
            final = job.split('name: Require actual native capture pass, not blocked permissions', 1)[1]
            self.assertIn('if: always()', final)
            self.assertIn('set -euo pipefail', final)
            self.assertIn('scripts/verify-macos-screenshot-probe.py', final)
            self.assertNotIn('continue-on-error', final)
            self.assertNotIn('|| true', job)
            self.assertIn('This is not physical F1 or packaged editor acceptance.', job)
        self.assertEqual(jobs[0], jobs[1])

    def test_installed_executable_is_retested_without_replacing_real_offline_flows(self):
        source = (ROOT / 'scripts/windows-offline-translation-test.ps1').read_text()
        self.assertIn('-OfflineTranslation -InstalledPackage -DefaultCapture', source)
        self.assertIn('-ScreenshotEditorTests -InstalledPackage -DefaultCapture', source)
        self.assertIn('verify_screenshot_editor_report.py', source)
        self.assertIn('$screenshotLog --application $app --installed', source)
        self.assertIn('$report.installedScreenshotEditorVerified = $true', source)
        self.assertIn('foreach ($ownedProcess in @($smoke, $screenshotSmoke, $install))', source)
        self.assertIn('Verify-NsisApplicationIdentity $expectedApp $app', source)
        self.assertIn("'Installed executable changed during the real-model test.'", source)

    def test_publication_requires_installed_screenshot_report_for_new_versions(self):
        source = (ROOT / 'scripts/prepare-release-assets.py').read_text()
        self.assertIn('tuple(map(int, VERSION.split("."))) >= (0, 2, 4)', source)
        self.assertIn('verify_screenshot_editor_report(report.get("installedScreenshotEditor"), installed_sha, installed=True)', source)
        self.assertIn('manifest["windowsInstalledScreenshotEditorVerified"] = True', source)


if __name__ == '__main__': unittest.main()
