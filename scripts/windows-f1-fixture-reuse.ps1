# Diagnostic-only reuse of immutable CI artifacts. No build, retry, model run,
# security-policy change or replacement of the full exact-head release gates.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [Parameter(Mandatory=$true)][string]$InstallerDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$utf8 = [Text.UTF8Encoding]::new($false)
$SourceCommit = '033aa3718a0c56f05dc752c0fd729f71299b3eff'
$SourceRun = '41169341340'
$BareSha = 'ca32cefbb9ce44193cf37e29458a2745bc6526c40f1b827ecf43b29a5784d95d'
$AppBytes = 7944192
$InstalledSha = '884b8abbd0c724481a9e5d006bc010f98747e32a2811ea91d204cc9eab514c5f'
$InstallerSha = '2aa598c3f5f932f69dd85af7f384cf343a9c629ad804d4ec6d513351a3252fed'
$InstallerBytes = 75877892
$BundleMarkerOffset = 7315789
$CaptureOffset = 5772421
$CaptureBytes = 412160
$CaptureSha = '2a5795c26b695a6a9c9f7de7094f85c77d455fa6e987406917bccd08fe5d4e1b'
$token = [Guid]::NewGuid().ToString('N')
$markerName = '.echolingo-f1-reuse-owned'
$work = $null; $installRoot = $null; $bare = $null; $installer = $null; $capture = $null; $installed = $null
$outputOwned = $false
$report = [ordered]@{
    ok=$false; diagnosticOnly=$true; releaseAcceptance=$false; rebuilt=$false; retries=0
    immutableSourceCommit=$SourceCommit; immutableRunId=$SourceRun
    evidenceArtifactId='13031215832'; installerArtifactId='13030374934'
    fixtures=@(); ownedWorkRemoved=$false; ownedInstallRemoved=$false; unchangedArtifactsAfterTests=$false
    securitySettingsChanged=$false; offlineEngineExecuted=$false
}
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw ('F1_REUSE: ' + $Message) } }
function Quote([string]$Value) { Require ($Value -notmatch '["\r\n]') 'Unsafe argument rejected.'; return '"' + $Value + '"' }
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Check-File([string]$Path, [long]$Bytes, [string]$Sha) {
    $item = Get-Item -LiteralPath $Path -Force
    Require (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Artifact is not a regular non-redirected file.'
    Require ($item.Length -eq $Bytes -and (Hash $Path) -eq $Sha) 'Immutable artifact size/hash mismatch.'
}
function Check-Path([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force
        Require (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Reparse-point path refused.'
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}
function Tree-Files([string]$Root) {
    Check-Path $Root
    $pending = [Collections.Generic.Queue[string]]::new(); $pending.Enqueue($Root)
    $files = [Collections.Generic.List[string]]::new(); $count = 0
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $count++; Require ($count -le 10000) 'Artifact/owned tree exceeds its fixed entry bound.'
            Require (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Redirected descendant refused.'
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) } else { $files.Add($item.FullName) }
        }
    }
    return $files.ToArray()
}
function Single-File([string]$Root, [string]$Name) {
    $files = @(Tree-Files $Root | Where-Object { [IO.Path]::GetFileName($_) -ceq $Name })
    Require ($files.Count -eq 1) ('Exactly one pinned ' + $Name + ' must be present.')
    return $files[0]
}
function Claim([string]$Path) {
    Require ([EchoLingoF1ReuseDirectory]::CreateDirectory($Path, [IntPtr]::Zero)) 'Owned directory already exists or cannot be created.'
    [IO.File]::WriteAllText((Join-Path $Path $markerName), $token, $utf8)
}
function Check-Owned([string]$Path) {
    Check-Path $Path
    $marker = Join-Path $Path $markerName
    Check-Path $marker
    Require ((Test-Path -LiteralPath $marker -PathType Leaf) -and [IO.File]::ReadAllText($marker) -eq $token) 'Ownership marker missing; preserve directory.'
    $null = @(Tree-Files $Path)
}
function Run-Captured([string]$Name, [string]$Executable, [string]$Arguments, [int]$TimeoutMs) {
    $process = $null; $timedOut = $false
    $stdoutPath = Join-Path $OutputDirectory ($Name + '.stdout.log')
    $stderrPath = Join-Path $OutputDirectory ($Name + '.stderr.log')
    try {
        $start = [Diagnostics.ProcessStartInfo]::new($Executable, $Arguments)
        $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        $start.StandardOutputEncoding=$utf8; $start.StandardErrorEncoding=$utf8
        $process = [Diagnostics.Process]::Start($start)
        $out = $process.StandardOutput.ReadToEndAsync(); $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) {
            $timedOut=$true
            & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
            $null = $process.WaitForExit(5000)
        }
        Require ($out.Wait(5000) -and $err.Wait(5000)) 'Owned process output did not finish after its bounded deadline.'
        [IO.File]::WriteAllText($stdoutPath, $out.Result, $utf8)
        [IO.File]::WriteAllText($stderrPath, $err.Result, $utf8)
        $entry = [ordered]@{name=$Name; exitCode=$process.ExitCode; timedOut=$timedOut; stdout=[IO.Path]::GetFileName($stdoutPath); stderr=[IO.Path]::GetFileName($stderrPath)}
        $script:report.fixtures += $entry
        Require (-not $timedOut -and $process.ExitCode -eq 0) ($Name + ' failed; unchanged raw stdout/stderr retained.')
        return $out.Result
    } finally {
        if ($null -ne $process) {
            if (-not $process.HasExited) { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null; $null=$process.WaitForExit(5000) }
            $process.Dispose()
        }
    }
}
function Run-Fixtures([string]$Name, [string]$Application, [string]$ExpectedSha, [bool]$IsInstalled) {
    Check-File $Application $AppBytes $ExpectedSha
    # The repaired actual Settings UI fixture always runs before F1; no retry.
    $args = '-NoProfile -STA -ExecutionPolicy Bypass -File ' + (Quote $shortcutScript) + ' -ApplicationPath ' + (Quote $Application) + ' -IsolatedTestSession -ExpectedApplicationSha256 ' + $ExpectedSha + ' -ExpectedApplicationBytes ' + $AppBytes
    $ui = (Run-Captured ($Name + '-shortcuts-uia') $powershell $args 240000) | ConvertFrom-Json
    Require ($ui.ok -eq $true -and $ui.actualSettingsUiTested -eq $true -and $ui.fakeIpcUsed -eq $false -and $ui.cdpUsed -eq $false -and $ui.ownedDataRemoved -eq $true -and @($ui.cleanupErrors).Count -eq 0) 'Real Settings UI or owned cleanup was not proved.'
    Require ($ui.casesExpected -eq 6 -and $ui.casesExecuted -eq 6 -and @($ui.cases).Count -eq 6 -and @($ui.cases | Where-Object { $_.passed -ne $true }).Count -eq 0) 'All six original Settings workflows must pass.'
    Check-File $Application $AppBytes $ExpectedSha
    $args = '-NoProfile -STA -ExecutionPolicy Bypass -File ' + (Quote $applicationScript) + ' -ApplicationPath ' + (Quote $Application) + ' -ScreenshotEditorTests -DefaultCapture -NativeCapturePath ' + (Quote $capture)
    if ($IsInstalled) { $args += ' -InstalledPackage' }
    $null = Run-Captured ($Name + '-f1-editor') $powershell $args 300000
    $raw = Join-Path $OutputDirectory ($Name + '-f1-editor.stdout.log')
    $verifyArgs = (Quote $verifier) + ' ' + (Quote $raw) + ' --application ' + (Quote $Application)
    if ($IsInstalled) { $verifyArgs += ' --installed' }
    $null = Run-Captured ($Name + '-strict-f1-verifier') $python $verifyArgs 60000
    Check-File $Application $AppBytes $ExpectedSha
    Check-File $capture $CaptureBytes $CaptureSha
}
function Verify-NsisIdentity([string]$Stage, [string]$Installed) {
    Check-File $Stage $AppBytes $BareSha; Check-File $Installed $AppBytes $InstalledSha
    $bytes=[IO.File]::ReadAllBytes($Stage); $text=[Text.Encoding]::ASCII.GetString($bytes)
    $old='__TAURI_BUNDLE_TYPE_VAR_UNK'; $new='__TAURI_BUNDLE_TYPE_VAR_NSS'
    $offset=$text.IndexOf($old,[StringComparison]::Ordinal)
    Require ($offset -eq $BundleMarkerOffset -and $text.IndexOf($old,$offset+1,[StringComparison]::Ordinal) -eq -1) 'Expected exactly one Tauri unknown bundle marker.'
    $replacement=[Text.Encoding]::ASCII.GetBytes($new); [Buffer]::BlockCopy($replacement,0,$bytes,$offset,$replacement.Length)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $derived=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    Require ($derived -eq $InstalledSha) 'Installed NSIS bytes differ beyond the exact three-byte bundle marker.'
    return [ordered]@{stageSha256=$BareSha; installedSha256=$InstalledSha; expectedNsisSha256=$derived; markerOffset=$offset; changedBytes=3; comparedBytes=$AppBytes; actualExecutablesModified=$false}
}
try {
    Require ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and [Environment]::UserInteractive) 'Unlocked ephemeral GitHub-hosted Windows desktop required.'
    Require ([Threading.Thread]::CurrentThread.ApartmentState -eq [Threading.ApartmentState]::STA) 'Windows PowerShell -NoProfile -STA required.'
    Require (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) 'RUNNER_TEMP is required.'
    $temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
    foreach ($path in @($EvidenceDirectory,$InstallerDirectory,$OutputDirectory)) { Require ([IO.Path]::GetFullPath($path).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) 'Inputs/results must stay under the disposable runner temp directory.' }
    $OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
    Check-Path ([IO.Path]::GetDirectoryName($OutputDirectory))
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EchoLingoF1ReuseDirectory {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool CreateDirectory(string path, IntPtr security);
}
'@
    Claim $OutputDirectory; $outputOwned=$true
    $work=Join-Path $env:RUNNER_TEMP ('echolingo-f1-reuse-'+$token); Claim $work
    $bare=Single-File $EvidenceDirectory 'echolingo.exe'
    $installer=Single-File $InstallerDirectory 'EchoLingo_0.2.4_x64-setup.exe'
    Check-File $bare $AppBytes $BareSha; Check-File $installer $InstallerBytes $InstallerSha
    $report.bareApplicationSha256=$BareSha; $report.installerSha256=$InstallerSha
    # Extract only the pinned embedded executable slice; never compile a helper.
    $bytes=[IO.File]::ReadAllBytes($bare)
    Require ($CaptureOffset -ge 0 -and $CaptureOffset+$CaptureBytes -le $bytes.Length) 'Capture slice is outside the pinned application.'
    $slice=[byte[]]::new($CaptureBytes); [Buffer]::BlockCopy($bytes,$CaptureOffset,$slice,0,$CaptureBytes)
    $capture=Join-Path $work 'echolingo-capture.exe'
    $file=[IO.File]::Open($capture,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $file.Write($slice,0,$slice.Length); $file.Flush() } finally { $file.Dispose() }
    Check-File $capture $CaptureBytes $CaptureSha
    $report.captureSlice=[ordered]@{offset=$CaptureOffset; bytes=$CaptureBytes; sha256=$CaptureSha; extractedWithoutRebuild=$true}
    $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $python=(Get-Command python -CommandType Application -ErrorAction Stop).Source
    $shortcutScript=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tests\windows-shortcuts-uia-smoke.ps1')).Path
    $applicationScript=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tests\windows-application-smoke.ps1')).Path
    $verifier=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'verify_screenshot_editor_report.py')).Path
    $report.fixtureSourceSha256=[ordered]@{shortcuts=(Hash $shortcutScript); shortcutImplementation=(Hash (Join-Path $PSScriptRoot '..\tests\windows-shortcuts-uia-fixture.cs')); application=(Hash $applicationScript); editorImplementation=(Hash (Join-Path $PSScriptRoot '..\tests\windows-screenshot-editor-fixture.cs')); verifier=(Hash $verifier)}
    Run-Fixtures 'bare' $bare $BareSha $false
    foreach ($registry in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')) {
        $existing=@(Get-ChildItem -Path $registry -ErrorAction SilentlyContinue | Get-ItemProperty | Where-Object { $_.DisplayName -like 'EchoLingo*' })
        Require ($existing.Count -eq 0) 'Existing EchoLingo installation refused.'
    }
    $installRoot=Join-Path $work 'installed'; Claim $installRoot
    # NSIS /D must be the final, unquoted argument; the complete path is checked.
    $null=Quote $installRoot
    $null=Run-Captured 'nsis-install' $installer ('/S /D='+$installRoot) 120000
    Check-Owned $installRoot
    $installed=Join-Path $installRoot 'echolingo.exe'
    $report.nsisIdentity=Verify-NsisIdentity $bare $installed
    Run-Fixtures 'installed' $installed $InstalledSha $true
    $report.installedPackageDiagnosticTested=$true
    $report.ok=$true
} catch {
    $report.error=$_.Exception.Message; $report.errorLine=$_.InvocationInfo.ScriptLineNumber
} finally {
    try {
        if ($bare) { Check-File $bare $AppBytes $BareSha }
        if ($installer) { Check-File $installer $InstallerBytes $InstallerSha }
        if ($capture) { Check-File $capture $CaptureBytes $CaptureSha }
        if ($installed) { Check-File $installed $AppBytes $InstalledSha }
        $report.unchangedArtifactsAfterTests=($null -ne $bare -and $null -ne $installer -and $null -ne $capture)
    } catch { $report.ok=$false; $report.identityRecheckError=$_.Exception.Message }
    if ($installRoot -and (Test-Path -LiteralPath $installRoot)) {
        try {
            Check-Owned $installRoot
            $uninstaller=Join-Path $installRoot 'uninstall.exe'
            Require (Test-Path -LiteralPath $uninstaller -PathType Leaf) 'Owned installer produced no uninstaller; preserve installation for diagnosis.'
            $null=Run-Captured 'nsis-uninstall' $uninstaller ('/S _?='+$installRoot) 60000
            if (Test-Path -LiteralPath $installRoot) {
                # The trusted uninstaller may remove its child marker while
                # retaining its own locked EXE. Parent ownership and the full
                # non-reparse descendant walk still constrain this cleanup.
                Check-Owned $work
                Remove-Item -LiteralPath $installRoot -Recurse -Force
            }
            $report.ownedInstallRemoved=(-not (Test-Path -LiteralPath $installRoot))
        } catch { $report.ok=$false; $report.installCleanupError=$_.Exception.Message }
    } else { $report.ownedInstallRemoved=$true }
    if ($work -and (Test-Path -LiteralPath $work) -and $report.ownedInstallRemoved) {
        try { Check-Owned $work; Remove-Item -LiteralPath $work -Recurse -Force; $report.ownedWorkRemoved=(-not (Test-Path -LiteralPath $work)) }
        catch { $report.ok=$false; $report.workCleanupError=$_.Exception.Message }
    }
    if (-not $report.ownedInstallRemoved -or -not $report.ownedWorkRemoved -or -not $report.unchangedArtifactsAfterTests) { $report.ok=$false }
    $json=$report | ConvertTo-Json -Depth 16 -Compress
    if ($outputOwned) { [IO.File]::WriteAllText((Join-Path $OutputDirectory 'diagnostic-summary.json'),$json,$utf8) }
    [Console]::Out.WriteLine($json)
}
if (-not $report.ok) { exit 1 }
