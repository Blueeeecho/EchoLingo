# Real bundled-model and installed-NSIS acceptance, CI disposable Windows only.
# Program-specific firewall rules are temporary; no adapter/profile/default
# policy is changed. This script never uses a translation HTTP mock or API key.
[CmdletBinding()]
param([string]$InstallerPath = '', [string]$ApplicationSmokePath = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$report = [ordered]@{ ok = $false; windowsRuntimeExecuted = $false; installerExecuted = $false; realModelExecuted = $false; mockTranslationUsed = $false; rulesRemoved = $false; ownedInstallRemoved = $false }
$rules = @()
$installRoot = $null
$token = [Guid]::NewGuid().ToString('N')
$markerName = '.echolingo-offline-ci-owned'
$engine = $null
$app = $null
$cli = $null
$install = $null
$smoke = $null

function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "OFFLINE_ACCEPTANCE: $Message" }
}
function Quote-Argument([string]$Value) {
    Assert-Fixture ($Value -notmatch '["\r\n]') 'Unsafe fixture argument rejected.'
    return '"' + $Value + '"'
}
function Start-Captured([string]$Path, [string]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new($Path, $Arguments)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    return [Diagnostics.Process]::Start($start)
}
function Assert-OfflinePolicy {
    Assert-Fixture ((Get-Service -Name MpsSvc).Status -eq 'Running') 'Windows Defender Firewall is not running; offline proof unavailable.'
    $active = @(Get-NetConnectionProfile | ForEach-Object {
        if ($_.NetworkCategory -eq 'DomainAuthenticated') { 'Domain' } else { [string]$_.NetworkCategory }
    } | Select-Object -Unique)
    Assert-Fixture ($active.Count -gt 0) 'No active network profile can be verified.'
    foreach ($firewallProfile in @(Get-NetFirewallProfile -PolicyStore ActiveStore -Name $active)) {
        Assert-Fixture ([string]$firewallProfile.Enabled -eq 'True') ('Active firewall profile is disabled: ' + $firewallProfile.Name)
    }
    foreach ($entry in $script:rules) {
        $rule = Get-NetFirewallRule -PolicyStore ActiveStore -Name $entry.name
        Assert-Fixture ([string]$rule.Enabled -eq 'True' -and [string]$rule.Direction -eq 'Outbound' -and [string]$rule.Action -eq 'Block' -and [string]$rule.Profile -eq 'Any') 'Effective outbound rule does not block all profiles.'
        $filter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule
        Assert-Fixture ([string]::Equals([string]$filter.Program, $entry.program, [StringComparison]::OrdinalIgnoreCase)) 'Effective firewall program path differs from the owned executable.'
    }
    return $active
}
function Verify-Resources([string]$ResourceRoot) {
    $manifestPath = Join-Path $ResourceRoot 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fixture ($manifest.formatVersion -eq 1 -and @($manifest.files).Count -ge 6) 'Installed model manifest is missing or has an unsupported format.'
    $checked = @()
    $directions = @{}
    $prefix = [IO.Path]::GetFullPath($ResourceRoot).TrimEnd('\') + '\'
    foreach ($file in @($manifest.files)) {
        Assert-Fixture ($file.path -match '^models/(en-zh|zh-en)/[^/\\]+$' -and $file.sha256 -match '^[a-fA-F0-9]{64}$') 'Installed model manifest has an unexpected file path/hash.'
        $path = [IO.Path]::GetFullPath((Join-Path $ResourceRoot ([string]$file.path)))
        Assert-Fixture ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) 'Resource escaped the owned installation.'
        $item = Get-Item -LiteralPath $path
        Assert-Fixture (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Installed model must be a regular local file.'
        Assert-Fixture ($item.Length -eq [long]$file.size) ('Installed model size mismatch: ' + $file.path)
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Fixture ($hash -eq ([string]$file.sha256).ToLowerInvariant()) ('Installed model hash mismatch: ' + $file.path)
        $direction = ([string]$file.path).Split('/')[1]
        $directions[$direction] = 1 + [int]$directions[$direction]
        $checked += [ordered]@{ path = $file.path; size = $item.Length; sha256 = $hash }
    }
    Assert-Fixture ($directions['en-zh'] -ge 3 -and $directions['zh-en'] -ge 3) 'Both installed model directions need original model, lexical and vocabulary files.'
    foreach ($license in @('licenses/THIRD_PARTY_NOTICES.md', 'licenses/MPL-2.0.txt', 'licenses/SOURCE-OFFER.md')) {
        Assert-Fixture ((Test-Path -LiteralPath (Join-Path $ResourceRoot $license) -PathType Leaf)) ('Installed license is absent: ' + $license)
    }
    $licenseManifestPath = Join-Path $ResourceRoot 'license-files.json'
    $licenseManifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $licenseManifestPath).Hash.ToLowerInvariant()
    $sourceLicenseManifest = Join-Path $PSScriptRoot '..\resources\offline-translation\license-files.json'
    Assert-Fixture ($licenseManifestHash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLicenseManifest).Hash.ToLowerInvariant()) 'Installed license inventory differs from this source.'
    $licenseManifest = Get-Content -LiteralPath $licenseManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fixture ($licenseManifest.formatVersion -eq 1 -and @($licenseManifest.files).Count -ge 33) 'Installed original license inventory is incomplete.'
    $checkedLicenses = @()
    foreach ($license in @($licenseManifest.files)) {
        Assert-Fixture ($license.path -match '^licenses/[^/\\]+$' -and $license.sha256 -match '^[a-fA-F0-9]{64}$') 'Unexpected license inventory path/hash.'
        $licensePath = Join-Path $ResourceRoot ([string]$license.path)
        Assert-Fixture (((Get-Item -LiteralPath $licensePath).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Installed license must be a regular local file.'
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $licensePath).Hash.ToLowerInvariant()
        Assert-Fixture ($hash -eq ([string]$license.sha256).ToLowerInvariant()) ('Installed original license hash mismatch: ' + $license.path)
        $checkedLicenses += [ordered]@{ path = $license.path; sha256 = $hash }
    }
    return [ordered]@{ manifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant(); files = $checked; totalModelBytes = ($checked | Measure-Object -Property size -Sum).Sum; licenseManifestSha256 = $licenseManifestHash; checkedOriginalLicenses = $checkedLicenses }
}
function Invoke-RealCase($Process, $Case) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $request = [ordered]@{ id = [string]$Case.id; source = $Case.source; target = $Case.target; text = $Case.text }
    $Process.StandardInput.WriteLine(($request | ConvertTo-Json -Compress))
    $Process.StandardInput.Flush()
    $read = $Process.StandardOutput.ReadLineAsync()
    Assert-Fixture ($read.Wait(120000)) ('Real model response timed out: ' + $Case.id)
    $line = $read.Result
    Assert-Fixture ($null -ne $line -and $line.Length -le 1000000) ('Real engine closed stdout or exceeded response limit: ' + $Case.id)
    $reply = $line | ConvertFrom-Json
    $watch.Stop()
    Assert-Fixture ([string]$reply.id -eq [string]$Case.id) 'Real engine response ID differs from request.'
    Assert-Fixture (-not $reply.error -and -not [string]::IsNullOrWhiteSpace([string]$reply.text)) ('Real engine failed: ' + [string]$Case.id + ': ' + [string]$reply.error)
    $text = [string]$reply.text
    if ($Case.expectation -eq 'zh-sentence') {
        Assert-Fixture ($text -match '[\u3400-\u9fff]' -and $text -match '\u4e16\u754c|\u4f60\u597d' -and $text -match '\u6d4b\u8bd5|\u8bd5\u9a8c') ('Real en-zh semantic check failed: ' + $text)
    } elseif ($Case.expectation -eq 'en-sentence') {
        Assert-Fixture ($text -match '(?i)world' -and $text -match '(?i)test') ('Real zh-en semantic check failed: ' + $text)
    } elseif ($Case.expectation -eq 'zh-technical') {
        Assert-Fixture ($text -match '[\u3400-\u9fff]' -and $text.Contains('42')) ('Real technical translation lost its numeric value or target script: ' + $text)
    }
    if ($Case.paragraphs) {
        Assert-Fixture ($text -match '\r?\n[ \t]*\r?\n') ('Real model did not preserve an explicit paragraph: ' + $Case.id)
    }
    return [ordered]@{ id = $Case.id; source = $Case.source; target = $Case.target; input = $Case.text; output = $text; explicitParagraphPreserved = [bool]$Case.paragraphs; elapsedMs = $watch.ElapsedMilliseconds; qualityScope = 'Basic direction/semantic/format acceptance only; short identifiers require nonempty output and are not rated as high quality' }
}

try {
    Assert-Fixture ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and [Environment]::UserInteractive) 'Only an unlocked disposable GitHub-hosted Windows desktop is allowed.'
    $report.windowsRuntimeExecuted = $true
    $machine = Get-CimInstance Win32_ComputerSystem
    $report.machine = [ordered]@{ model = $machine.Model; manufacturer = $machine.Manufacturer; totalPhysicalMemoryBytes = $machine.TotalPhysicalMemory; processors = @(Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors); architecture = $env:PROCESSOR_ARCHITECTURE }
    Assert-Fixture ([Threading.Thread]::CurrentThread.ApartmentState -eq [Threading.ApartmentState]::STA) 'Run powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File scripts/windows-offline-translation-test.ps1.'
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    Assert-Fixture ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'The CI runner lacks permission for scoped firewall rules; do not elevate or claim offline acceptance.'
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        $installers = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\src-tauri\target\release\bundle\nsis') -Filter '*.exe' -File)
        Assert-Fixture ($installers.Count -eq 1) 'Pass the exact single NSIS installer with -InstallerPath.'
        $InstallerPath = $installers[0].FullName
    }
    $InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
    if ([string]::IsNullOrWhiteSpace($ApplicationSmokePath)) { $ApplicationSmokePath = Join-Path $PSScriptRoot '..\tests\windows-application-smoke.ps1' }
    $ApplicationSmokePath = (Resolve-Path -LiteralPath $ApplicationSmokePath).Path
    Assert-Fixture (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) 'A disposable runner temp directory is required.'
    foreach ($registryRoot in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')) {
        $existing = @(Get-ChildItem -Path $registryRoot -ErrorAction SilentlyContinue | Get-ItemProperty | Where-Object { $_.DisplayName -like 'EchoLingo*' })
        Assert-Fixture ($existing.Count -eq 0) 'An existing EchoLingo install is registered; never replace or uninstall it.'
    }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EchoLingoOwnedDirectory {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool CreateDirectory(string path, IntPtr security);
}
'@
    # ASCII-only source remains correctly decoded by Windows PowerShell5.1;
    # the actual installation/model/engine paths deliberately contain Chinese.
    $unicodeName = ('{"name":"\u79bb\u7ebf\u9a8c\u8bc1"}' | ConvertFrom-Json).name
    $installRoot = Join-Path $env:RUNNER_TEMP ('echolingo-' + $unicodeName + '-' + $token)
    Assert-Fixture ([EchoLingoOwnedDirectory]::CreateDirectory($installRoot, [IntPtr]::Zero)) 'Owned install directory already exists; no file was read or overwritten.'
    [IO.File]::WriteAllText((Join-Path $installRoot $markerName), $token, [Text.UTF8Encoding]::new($false))
    $report.windowsRuntimeExecuted = $true
    $report.installerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $InstallerPath).Hash.ToLowerInvariant()
    $report.installerBytes = (Get-Item -LiteralPath $InstallerPath).Length
    $install = [Diagnostics.Process]::Start([Diagnostics.ProcessStartInfo]@{ FileName = $InstallerPath; Arguments = '/S /D=' + $installRoot; UseShellExecute = $false })
    Assert-Fixture ($install.WaitForExit(120000) -and $install.ExitCode -eq 0) 'NSIS silent installation failed or timed out.'
    $report.installerExecuted = $true
    $app = Join-Path $installRoot 'echolingo.exe'
    $resourceRoot = Join-Path $installRoot 'offline-translation'
    $engine = Join-Path $resourceRoot 'bin\echolingo-offline-engine.exe'
    Assert-Fixture ((Test-Path -LiteralPath $app -PathType Leaf) -and (Test-Path -LiteralPath $engine -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $installRoot 'uninstall.exe') -PathType Leaf)) 'NSIS did not install the app, uninstaller and offline engine at fixed resource paths.'
    $report.resources = Verify-Resources $resourceRoot
    $report.applicationSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $app).Hash.ToLowerInvariant()
    $report.engineSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $engine).Hash.ToLowerInvariant()
    $report.engineBytes = (Get-Item -LiteralPath $engine).Length
    $report.installedBytesBeforeFirstRun = (Get-ChildItem -LiteralPath $installRoot -Recurse -File | Where-Object { $_.Name -ne $markerName } | Measure-Object -Property Length -Sum).Sum
    $expectedApp = Join-Path $PSScriptRoot '..\src-tauri\target\release\echolingo.exe'
    $expectedEngine = Join-Path $PSScriptRoot '..\resources\offline-translation\bin\echolingo-offline-engine.exe'
    $expectedManifest = Join-Path $PSScriptRoot '..\resources\offline-translation\manifest.json'
    Assert-Fixture ($report.applicationSha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $expectedApp).Hash.ToLowerInvariant()) 'NSIS installed a different app from this build.'
    Assert-Fixture ($report.engineSha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $expectedEngine).Hash.ToLowerInvariant()) 'NSIS installed a different engine from staging.'
    Assert-Fixture ($report.resources.manifestSha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $expectedManifest).Hash.ToLowerInvariant()) 'NSIS installed a different model manifest from this source.'
    $report.chineseInstallationPath = $true
    foreach ($program in @($app, $engine)) {
        $name = 'EchoLingo-offline-ci-' + $token + '-' + $rules.Count
        Assert-Fixture (-not (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue)) 'A firewall rule with this ownership marker already exists.'
        New-NetFirewallRule -Name $name -DisplayName $name -Direction Outbound -Action Block -Program $program -Profile Any -Enabled True -PolicyStore PersistentStore | Out-Null
        $rules += [ordered]@{ name = $name; program = $program }
    }
    $report.blockedActiveNetworkProfiles = @(Assert-OfflinePolicy)
    $report.offlineIsolation = 'Effective Windows Defender outbound Block, exact installed app/engine program paths only; adapters, profile states and default policy unchanged'
    $cases = @'
[
 {"id":"en-zh-sentence","source":"en","target":"zh","text":"Hello world. This is a translation test.","expectation":"zh-sentence"},
 {"id":"zh-en-sentence","source":"zh","target":"en","text":"\u4f60\u597d\uff0c\u4e16\u754c\u3002\u8fd9\u662f\u4e00\u6b21\u7ffb\u8bd1\u6d4b\u8bd5\u3002","expectation":"en-sentence"},
 {"id":"technical-short","source":"en","target":"zh","text":"- quiet-pin:","expectation":"nonempty"},
 {"id":"technical-underlines","source":"en","target":"zh","text":"Translate the option - quiet-pin: and quiet_pin (value 42) at /tmp/example_file.txt.","expectation":"zh-technical"},
 {"id":"en-zh-paragraphs","source":"en","target":"zh","text":"Hello world.\n\nThis is a translation test.","expectation":"zh-sentence","paragraphs":true},
 {"id":"zh-en-paragraphs","source":"zh","target":"en","text":"\u4f60\u597d\uff0c\u4e16\u754c\u3002\n\n\u8fd9\u662f\u4e00\u6b21\u7ffb\u8bd1\u6d4b\u8bd5\u3002","expectation":"en-sentence","paragraphs":true}
]
'@ | ConvertFrom-Json
    $cli = Start-Captured $engine ('--model-root ' + (Quote-Argument (Join-Path $resourceRoot 'models')))
    $stderr = $cli.StandardError.ReadToEndAsync()
    $results = @()
    $seenPairs = @{}
    foreach ($case in $cases) {
        $result = Invoke-RealCase $cli $case
        $pair = $case.source + '-' + $case.target
        $result.firstUseForDirection = -not $seenPairs.ContainsKey($pair)
        $result.cacheScope = if ($result.firstUseForDirection) { 'First in-process model load for this direction; OS file cache was not flushed' } else { 'Same-process cached directional model' }
        $seenPairs[$pair] = $true
        $results += $result
    }
    $cli.Refresh()
    $report.engineMemory = [ordered]@{ workingSetBytesAfterBothDirections = $cli.WorkingSet64; peakWorkingSetBytes = $cli.PeakWorkingSet64; scope = 'Real engine process holding both directional model caches after all JSONL cases' }
    $cli.StandardInput.Close()
    Assert-Fixture ($cli.WaitForExit(10000) -and $cli.ExitCode -eq 0) 'Real engine did not stop normally on stdin EOF.'
    $report.realModelExecuted = $true
    $report.realModelCases = $results
    $report.engineStderrBytes = [Text.Encoding]::UTF8.GetByteCount($stderr.Result)
    $arguments = '-NoProfile -STA -ExecutionPolicy Bypass -File ' + (Quote-Argument $ApplicationSmokePath) + ' -ApplicationPath ' + (Quote-Argument $app) + ' -OfflineTranslation -InstalledPackage'
    $smoke = Start-Captured (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') $arguments
    $smoke.StandardInput.Close()
    $smokeOut = $smoke.StandardOutput.ReadToEndAsync()
    $smokeErr = $smoke.StandardError.ReadToEndAsync()
    Assert-Fixture ($smoke.WaitForExit(300000)) 'Installed app single-hotkey smoke exceeded its bounded deadline.'
    $report.installedApplication = $smokeOut.Result.Trim() | ConvertFrom-Json
    Assert-Fixture ($smoke.ExitCode -eq 0 -and $report.installedApplication.ok -and $report.installedApplication.translationBackend -eq 'real-bundled-offline-model' -and @($report.installedApplication.mockRequests).Count -eq 0) ('Installed app did not pass real offline core flows: ' + $smokeErr.Result)
    $report.installedPackageTested = $true
    $report.policyStillEffective = @(Assert-OfflinePolicy)
    Assert-Fixture ((Get-FileHash -Algorithm SHA256 -LiteralPath $engine).Hash.ToLowerInvariant() -eq $report.engineSha256 -and (Get-FileHash -Algorithm SHA256 -LiteralPath $app).Hash.ToLowerInvariant() -eq $report.applicationSha256) 'Installed executable changed during the real-model test.'
    $report.ok = $true
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    $report.error = $message
} finally {
    if ($null -ne $cli) { try { if (-not $cli.HasExited) { $cli.Kill(); $cli.WaitForExit(5000) | Out-Null } } catch { $report.ok = $false; $report.engineCleanupError = $_.Exception.Message }; $cli.Dispose() }
    foreach ($ownedProcess in @($smoke, $install)) {
        if ($null -ne $ownedProcess) {
            try { if (-not $ownedProcess.HasExited) { & taskkill.exe /PID $ownedProcess.Id /T /F 2>&1 | Out-Null; $ownedProcess.WaitForExit(5000) | Out-Null } }
            catch { $report.ok = $false; $report.processCleanupError = $_.Exception.Message }
            $ownedProcess.Dispose()
        }
    }
    if ($app) {
        try { Get-CimInstance Win32_Process -Filter "Name='echolingo.exe'" | Where-Object { $_.ExecutablePath -eq $app } | ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>&1 | Out-Null } }
        catch { $report.ok = $false; $report.processCleanupError = $_.Exception.Message }
    }
    foreach ($entry in $rules) { try { Remove-NetFirewallRule -Name $entry.name -ErrorAction Stop } catch { $report.ok = $false; $report.firewallCleanupError = $_.Exception.Message } }
    try { $report.rulesRemoved = (@($rules | Where-Object { Get-NetFirewallRule -Name $_.name -ErrorAction SilentlyContinue }).Count -eq 0) }
    catch { $report.ok = $false; $report.firewallCleanupError = $_.Exception.Message }
    if ($installRoot -and (Test-Path -LiteralPath $installRoot)) {
        try {
            $marker = Join-Path $installRoot $markerName
            Assert-Fixture ((Test-Path -LiteralPath $marker -PathType Leaf) -and [IO.File]::ReadAllText($marker) -eq $token) 'Install ownership marker missing; installation directory preserved.'
            $uninstaller = Join-Path $installRoot 'uninstall.exe'
            if (Test-Path -LiteralPath $uninstaller -PathType Leaf) {
                $uninstall = [Diagnostics.Process]::Start([Diagnostics.ProcessStartInfo]@{ FileName = $uninstaller; Arguments = '/S _?=' + $installRoot; UseShellExecute = $false })
                Assert-Fixture ($uninstall.WaitForExit(60000) -and $uninstall.ExitCode -eq 0) 'Owned NSIS uninstall failed.'
            }
            if (Test-Path -LiteralPath $installRoot) { Remove-Item -LiteralPath $installRoot -Recurse -Force }
            $report.ownedInstallRemoved = -not (Test-Path -LiteralPath $installRoot)
        } catch { $report.ok = $false; $report.installCleanupError = $_.Exception.Message }
    }
}
$jsonReport = $report | ConvertTo-Json -Depth 16 -Compress
if ($report.windowsRuntimeExecuted -and $env:RUNNER_TEMP) {
    try { [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP 'echolingo-offline-validation.json'), $jsonReport, [Text.UTF8Encoding]::new($false)) }
    catch { $report.ok = $false; $report.evidenceWriteError = $_.Exception.Message; $jsonReport = $report | ConvertTo-Json -Depth 16 -Compress }
}
[Console]::Out.WriteLine($jsonReport)
if (-not $report.ok -or -not $report.rulesRemoved -or -not $report.ownedInstallRemoved) { exit 1 }
