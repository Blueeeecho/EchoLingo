"""Structural checks only; Windows PowerShell/native execution is a CI stage."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'scripts/windows-f1-fixture-reuse.ps1').read_text()


class FixtureReuseContract(unittest.TestCase):
    def test_only_exact_artifact_identities_and_embedded_child_are_accepted(self):
        for value in ['033aa3718a0c56f05dc752c0fd729f71299b3eff', '41169341340',
                      'ca32cefbb9ce44193cf37e29458a2745bc6526c40f1b827ecf43b29a5784d95d',
                      '884b8abbd0c724481a9e5d006bc010f98747e32a2811ea91d204cc9eab514c5f',
                      '2aa598c3f5f932f69dd85af7f384cf343a9c629ad804d4ec6d513351a3252fed',
                      '2a5795c26b695a6a9c9f7de7094f85c77d455fa6e987406917bccd08fe5d4e1b',
                      '7944192', '75877892', '5772421', '412160', '7315789']:
            self.assertIn(value, SOURCE)
        self.assertIn('$files.Count -eq 1', SOURCE)
        self.assertIn('Check-File $capture $CaptureBytes $CaptureSha', SOURCE)
        self.assertIn('[Buffer]::BlockCopy($bytes,$CaptureOffset,$slice,0,$CaptureBytes)', SOURCE)
        self.assertIn('[IO.FileMode]::CreateNew', SOURCE)

    def test_original_strict_fixtures_run_once_in_order_for_bare_and_installed(self):
        body = SOURCE.split('function Run-Fixtures(', 1)[1].split('function Verify-NsisIdentity', 1)[0]
        self.assertLess(body.index("'-shortcuts-uia'"), body.index("'-f1-editor'"))
        self.assertIn('$ui.casesExpected -eq 6 -and $ui.casesExecuted -eq 6', body)
        self.assertIn('-ScreenshotEditorTests -DefaultCapture -NativeCapturePath', body)
        self.assertIn("if ($IsInstalled) { $args += ' -InstalledPackage' }", body)
        self.assertIn("if ($IsInstalled) { $verifyArgs += ' --installed' }", body)
        self.assertIn('verify_screenshot_editor_report.py', SOURCE)
        self.assertEqual(SOURCE.count("Run-Fixtures 'bare'"), 1)
        self.assertEqual(SOURCE.count("Run-Fixtures 'installed'"), 1)
        for forbidden in ['cargo ', 'npm ', 'windows-offline-translation-test.ps1',
                          '-OfflineTranslation', 'New-NetFirewallRule', 'Set-Net', 'Start-Sleep',
                          'Invoke-WebRequest', 'curl ', 'git push', 'continue-on-error']:
            self.assertNotIn(forbidden, SOURCE)

    def test_ownership_cleanup_raw_logs_and_three_byte_nsis_identity_are_preserved(self):
        for text in ['github-hosted', 'UserInteractive', 'ApartmentState]::STA', 'RUNNER_TEMP',
                     '[IO.FileAttributes]::ReparsePoint', 'Check-Owned $installRoot',
                     'Existing EchoLingo installation refused', 'actualExecutablesModified=$false',
                     '__TAURI_BUNDLE_TYPE_VAR_UNK', '__TAURI_BUNDLE_TYPE_VAR_NSS',
                     'changedBytes=3', '$derived -eq $InstalledSha', 'unchangedArtifactsAfterTests',
                     "'.stdout.log'", "'.stderr.log'", 'diagnosticOnly=$true', 'releaseAcceptance=$false',
                     "'nsis-uninstall'", "'/S _?='", 'diagnostic-summary.json']:
            self.assertIn(text, SOURCE)
        owned = SOURCE.split('function Check-Owned(', 1)[1].split('function Run-Captured(', 1)[0]
        self.assertLess(owned.index('Check-Path $marker'), owned.index('[IO.File]::ReadAllText($marker)'))
        self.assertIn('Require (-not $timedOut -and $process.ExitCode -eq 0)', SOURCE)
        self.assertIn('$report.ok=$false; $report.installCleanupError', SOURCE)
        self.assertRegex(SOURCE, r'if \(-not \$report\.ok\) \{ exit 1 \}')

    def test_process_launch_uses_one_concrete_path_and_preserves_phase_evidence(self):
        self.assertIn('$pythonCommands=@(Get-Command python.exe -CommandType Application', SOURCE)
        self.assertIn('$python=$pythonCommands[0].Path', SOURCE)
        self.assertNotIn('Get-Command python -CommandType Application -ErrorAction Stop).Source', SOURCE)
        self.assertIn('$start.FileName=$Executable; $start.Arguments=$Arguments; $start.WorkingDirectory=$workingDirectory', SOURCE)
        self.assertIn('executableFileExists=[IO.File]::Exists($Executable)', SOURCE)
        self.assertIn('$script:report.processLaunches.Count -lt 10', SOURCE)
        self.assertLess(SOURCE.index("Run-Captured 'python-runtime-preflight'"), SOURCE.index("Run-Fixtures 'bare'"))
        self.assertEqual(SOURCE.count("Run-Captured 'python-runtime-preflight'"), 1)
        self.assertIn("Run-Captured ($Name + '-strict-f1-verifier') $python", SOURCE)
        self.assertIn('$start.UseShellExecute=$false', SOURCE)

    def test_powershell_here_string_and_basic_delimiters_are_balanced(self):
        # Not a PowerShell parser: actual AST parse is mandatory in Windows CI.
        self.assertEqual(SOURCE.count("@'"), 1)
        self.assertEqual(SOURCE.count("\n'@"), 1)
        stripped = re.sub(r"@'\n.*?\n'@", '', SOURCE, flags=re.S)
        stripped = re.sub(r"'(?:[^']|'')*'|\"(?:[^\"`]|`.)*\"|#.*", '', stripped)
        for left, right in [('(', ')'), ('[', ']'), ('{', '}')]:
            self.assertEqual(stripped.count(left), stripped.count(right), (left, right))


if __name__ == '__main__':
    unittest.main()
