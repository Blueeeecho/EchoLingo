# Real unpacked bytes, disposable GitHub-hosted Windows desktop only.
# Run with powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ...
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ArchivePath,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$owned = @(); $processes = [Collections.Generic.List[Diagnostics.Process]]::new()
$assertionFailure = ''
$token = [Guid]::NewGuid().ToString('N')
$report = [ordered]@{ ok = $false; version = ''; archiveSha256 = ''; windowsRuntimeExecuted = $false; interactiveCaptureTested = $false; networkIsolationTested = $false }
function Assert-Test($condition, [string]$message) { if (-not $condition) { $script:assertionFailure = $message; throw $message } }
function Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Claim([string]$path) {
    Assert-Test ([UnpackDesktop]::CreateDirectory($path, [IntPtr]::Zero)) 'Owned directory already exists or cannot be created.'
    [IO.File]::WriteAllText((Join-Path $path '.unpack-ci-owned'), $token)
    $script:owned += $path
}
function Run-Captured([string]$file, [string]$arguments, [string]$inputText = '', [int]$timeout = 120000, [int]$expectedExit = 0) {
    $info = [Diagnostics.ProcessStartInfo]::new($file, $arguments)
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.WorkingDirectory = $script:unrelated
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true; $info.RedirectStandardInput = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $p = [Diagnostics.Process]::Start($info); $processes.Add($p)
    $stdout = $p.StandardOutput.ReadToEndAsync(); $stderr = $p.StandardError.ReadToEndAsync()
    if ($inputText) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($inputText + "`n")
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.BaseStream.Flush()
    }; $p.StandardInput.Close()
    Assert-Test ($p.WaitForExit($timeout)) 'Owned subprocess timed out.'
    Assert-Test ($p.ExitCode -eq $expectedExit) 'Owned subprocess returned failure.'
    return $stdout.Result
}
function Check-Imports([string]$file) {
    $output = Run-Captured $script:dumpbin ('/nologo /dependents "' + $file + '"')
    Assert-Test ($output -match '(?i)\.dll') 'PE import inspection returned no dependencies.'
    Assert-Test ($output -notmatch '(?im)^\s*(?:vcruntime\S*|msvcp\S*|concrt\S*|WebView2Loader)\.dll\s*$') 'Undeclared redistributable or WebView2Loader DLL dependency.'
}
function Check-Payload {
    $actual = @(Get-ChildItem -LiteralPath $script:package -Recurse -File)
    Assert-Test ($actual.Count -eq $script:manifest.files.Count) 'Package gained or lost files.'
    foreach ($entry in $script:manifest.files) {
        $file = Join-Path $script:package $entry.path
        Assert-Test ((Get-Item -LiteralPath $file).Length -eq $entry.size -and (Hash $file) -eq $entry.sha256) 'Package file bytes changed.'
    }
}
try {
    Assert-Test ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and [Environment]::UserInteractive) 'Disposable GitHub-hosted interactive Windows runner required.'
    Assert-Test ([Threading.Thread]::CurrentThread.ApartmentState -eq [Threading.ApartmentState]::STA) 'Windows PowerShell STA required.'
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase, System.IO.Compression.FileSystem
    Add-Type -ReferencedAssemblies ([Windows.Automation.AutomationElement].Assembly.Location),([Windows.Automation.Condition].Assembly.Location),([Windows.DependencyObject].Assembly.Location) -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Automation;
public static class UnpackDesktop {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool CreateDirectory(string path, IntPtr security);
    [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] static extern bool SwitchDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    public static bool Unlocked() { var d=OpenInputDesktop(0,false,0x0100); if(d==IntPtr.Zero)return false; try{return SwitchDesktop(d);} finally{CloseDesktop(d);} }
    public static bool Ready(int pid) {
        var windows=AutomationElement.RootElement.FindAll(TreeScope.Children,new PropertyCondition(AutomationElement.ProcessIdProperty,pid));
        foreach(AutomationElement w in windows) {
            if(w.Current.IsOffscreen)continue;
            var button=w.FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button),new PropertyCondition(AutomationElement.NameProperty,"\u6253\u5f00\u670d\u52a1\u7ba1\u7406")));
            if(button!=null && !button.Current.IsOffscreen)return true;
        }
        return false;
    }
}
'@
    Assert-Test ([UnpackDesktop]::Unlocked()) 'Unlocked input desktop required.'
    Assert-Test (-not (Get-Process -Name echolingo -ErrorAction SilentlyContinue)) 'Preexisting application process; refusing test.'
    $dumpbin = (Get-Command dumpbin.exe -ErrorAction Stop).Source
    $archive = (Resolve-Path -LiteralPath $ArchivePath).Path
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Test ($manifest.kind -eq 'windows-unpack' -and $manifest.formatVersion -eq 1 -and $manifest.userDataPortable -eq $false) 'Unexpected package manifest.'
    $report.version = $manifest.version; $report.archiveSha256 = Hash $archive
    $identity = @($manifest.archives | Where-Object { $_.name -eq [IO.Path]::GetFileName($archive) })
    Assert-Test ($identity.Count -eq 1 -and $identity[0].sha256 -eq $report.archiveSha256 -and $identity[0].size -eq (Get-Item -LiteralPath $archive).Length) 'Archive identity mismatch.'
    $roaming = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'io.github.blueeeecho.echolingo'
    $local = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'io.github.blueeeecho.echolingo'
    $native = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'EchoLingo'
    foreach ($path in @($roaming,$local,$native)) { Assert-Test (-not (Test-Path -LiteralPath $path)) 'Preexisting app data; refusing test.' }
    Assert-Test (Test-Path -LiteralPath $env:RUNNER_TEMP -PathType Container) 'Runner temporary directory missing.'
    $root = Join-Path $env:RUNNER_TEMP ('EchoLingo unpack ' + [char]0x9a8c + [char]0x8bc1 + ' ' + $token)
    Claim $root; Claim $roaming; Claim $local; Claim $native
    $package = Join-Path $root 'Extracted app'; $unrelated = Join-Path $root 'Unrelated working directory'
    [IO.Directory]::CreateDirectory($package) | Out-Null; [IO.Directory]::CreateDirectory($unrelated) | Out-Null
    $expected = @{}
    foreach ($entry in $manifest.files) {
        Assert-Test ($entry.path -cmatch '^[^\\:]+$' -and $entry.path -notmatch '(^|/)\.{1,2}(/|$)|^/|//|[<>|?*"\x00-\x1f]' -and $entry.path -notmatch '[. ](/|$)' -and $entry.sha256 -match '^[a-f0-9]{64}$' -and $entry.size -gt 0) 'Unsafe manifest member.'
        Assert-Test (-not $expected.ContainsKey($entry.path)) 'Duplicate manifest member.'
        $expected[$entry.path] = $entry
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        Assert-Test ($zip.Entries.Count -eq $expected.Count) 'ZIP inventory mismatch.'
        $seen = @{}
        foreach ($entry in $zip.Entries) {
            Assert-Test ($expected.ContainsKey($entry.FullName) -and -not $seen.ContainsKey($entry.FullName) -and $entry.Length -eq $expected[$entry.FullName].size) 'Unexpected ZIP member.'
            $seen[$entry.FullName] = $true
            $destination = Join-Path $package $entry.FullName
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination)
        }
    } finally { $zip.Dispose() }
    Check-Payload
    # Execute the exact packaged PowerShell expression with child-only mocks.
    # No registry writes, installation, real launcher Start-Process or parent mocks.
    $launcher = Get-Content -LiteralPath (Join-Path $package 'Start-EchoLingo.cmd') -Raw -Encoding UTF8
    $commandMatches = [regex]::Matches($launcher, '(?m)^.*powershell\.exe"[^\r\n]* -Command "([^\r\n]*)"\r?$')
    Assert-Test ($commandMatches.Count -eq 1) 'Expected one packaged launcher expression.'
    $command = $commandMatches[0].Groups[1].Value
    $mockScript = Join-Path $root 'launcher-mocks.ps1'
    $mockPrefix = @'
param([string]$Mode,[string]$Root)
$ErrorActionPreference = 'Stop'
$env:ECHOLINGO_UNPACK_ROOT = $Root
$script:launched = $false
$script:reads = 0
function Get-ItemProperty {
    param($LiteralPath,$Name,$ErrorAction)
    if ($Name -ne 'pv' -or $LiteralPath -notmatch '^HK(LM|CU):\\SOFTWARE\\(WOW6432Node\\)?Microsoft\\EdgeUpdate\\Clients\\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5\}$') { throw 'Unexpected runtime registry query' }
    $script:reads++
    if ($Mode -eq 'missing') { return $null }
    if ($Mode -eq 'zero') { return [pscustomobject]@{pv='0.0.0.0'} }
    if ($Mode -eq 'present' -and $LiteralPath.StartsWith('HKCU:')) { return [pscustomobject]@{pv='130.0.0.0'} }
    return $null
}
function Start-Process {
    param($FilePath,$WorkingDirectory)
    if ($Mode -ne 'present' -or $FilePath -ne (Join-Path $Root 'echolingo.exe') -or $WorkingDirectory -ne $Root -or $script:launched) { throw 'Unexpected launcher process request' }
    $script:launched = $true
}
'@
    $mockSuffix = @'
if ($Mode -ne 'present' -or -not $script:launched -or $script:reads -ne 3) { throw 'Launcher failed to use mocked runtime and app path' }
Write-Output 'MOCK_LAUNCH_VALIDATED'
'@
    [IO.File]::WriteAllText($mockScript, $mockPrefix + "`r`n" + $command + "`r`n" + $mockSuffix, [Text.UTF8Encoding]::new($true))
    $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    foreach ($mode in @('missing','zero','present')) {
        $expectedExit = if ($mode -eq 'present') { 0 } else { 2 }
        $mockOutput = Run-Captured $powershell ('-NoProfile -ExecutionPolicy Bypass -File "' + $mockScript + '" -Mode ' + $mode + ' -Root "' + $package + '"') '' 30000 $expectedExit
        if ($mode -eq 'present') { Assert-Test ($mockOutput -match 'MOCK_LAUNCH_VALIDATED') 'Present runtime mock did not validate launch.' }
        else { Assert-Test ($mockOutput -match 'Microsoft Edge WebView2 Runtime is missing') 'Missing runtime mock did not explain prerequisite.' }
    }
    $report.launcherMissingZeroPresentMocks = $true
    $resources = Join-Path $package 'offline-translation'
    $audit = & python (Join-Path $PSScriptRoot '../scripts/audit-windows-resources.py') --installed-root $resources
    Assert-Test ($LASTEXITCODE -eq 0 -and (($audit -join "`n") | ConvertFrom-Json).ok) 'Extracted resource audit failed.'
    $app = Join-Path $package 'echolingo.exe'; $engine = Join-Path $resources 'bin/echolingo-offline-engine.exe'
    Check-Imports $app; Check-Imports $engine
    $report.applicationSha256 = Hash $app; $report.engineSha256 = Hash $engine
    # Use only a build candidate whose complete bytes occur in the packaged app.
    # This avoids exercising an arbitrary/stale helper and needs no screenshot input.
    $capture = Join-Path $root 'embedded-capture.exe'
    @'
import pathlib, sys
app, build, output = map(pathlib.Path, sys.argv[1:])
blob = app.read_bytes()
matches = {p.read_bytes() for p in build.rglob('echolingo-native-capture.exe') if p.is_file()}
matches = [b for b in matches if b and b in blob]
if len(matches) != 1: raise SystemExit('Exact embedded capture candidate not uniquely identified')
output.write_bytes(matches[0])
'@ | & python - $app (Join-Path $PSScriptRoot '../src-tauri/target/release/build') $capture
    Assert-Test ($LASTEXITCODE -eq 0) 'Embedded capture extraction failed.'
    Check-Imports $capture
    $captureResult = (Run-Captured $capture '--self-test') | ConvertFrom-Json
    Assert-Test ($captureResult.ok -and $captureResult.memoryPixelSelfTest -and $captureResult.nativeBackend -eq 'rust-win32-capture') 'Embedded capture memory self-test failed.'
    $report.captureSha256 = Hash $capture; $report.embeddedCaptureMemorySelfTest = $true; $report.peDependencyChecks = $true
    $cases = '[{"id":"en-zh","source":"en","target":"zh","text":"Hello world. This is a translation test."},{"id":"zh-en","source":"zh","target":"en","text":"\u4f60\u597d\uff0c\u4e16\u754c\u3002\u8fd9\u662f\u4e00\u6b21\u7ffb\u8bd1\u6d4b\u8bd5\u3002"}]' | ConvertFrom-Json
    foreach ($case in $cases) {
        $result = (Run-Captured $engine ('--once --model-root "' + (Join-Path $resources 'models') + '"') ($case | ConvertTo-Json -Compress)) | ConvertFrom-Json
        Assert-Test ($result.id -eq $case.id -and -not [string]::IsNullOrWhiteSpace($result.text) -and $result.text -ne $case.text) 'Translation protocol or useful output failed.'
        if ($case.target -eq 'zh') { Assert-Test ($result.text -match '[\u4e00-\u9fff]') 'Chinese translation missing.' }
        else { Assert-Test ($result.text -match '[A-Za-z]{3}' -and $result.text -notmatch '[\u4e00-\u9fff]') 'English translation missing.' }
    }
    $report.realTranslationBothDirections = $true
    $info = [Diagnostics.ProcessStartInfo]::new($app)
    $info.UseShellExecute = $false; $info.WorkingDirectory = $unrelated
    $application = [Diagnostics.Process]::Start($info); $processes.Add($application)
    Start-Sleep -Seconds 4
    Assert-Test (-not $application.HasExited) 'Extracted app exited before second launch.'
    $second = [Diagnostics.Process]::Start($info); $processes.Add($second)
    Assert-Test ($second.WaitForExit(30000) -and $second.ExitCode -eq 0) 'Second launch did not forward to existing app.'
    $ready = $false; $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        Assert-Test (-not $application.HasExited) 'App exited during UI readiness.'
        try { $ready = [UnpackDesktop]::Ready($application.Id) } catch { $ready = $false }
        if (-not $ready) { Start-Sleep -Milliseconds 500 }
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    Assert-Test $ready 'Settings WebView UI did not become ready.'
    Assert-Test (Test-Path -LiteralPath (Join-Path $local 'EBWebView')) 'Expected local WebView profile missing.'
    Assert-Test (Test-Path -LiteralPath $roaming -PathType Container) 'Expected roaming data directory missing.'
    $report.windowsRuntimeExecuted = $true; $report.settingsWebViewReady = $true; $report.expectedLocalWebViewProfileCreated = $true; $report.roamingDirectoryAvailable = $true
    Check-Payload; $report.packageUnchangedAfterRun = $true; $report.ok = $true
} catch {
    # Do not upload raw exceptions, user paths, app data, outputs or logs.
    $report.failure = if ($assertionFailure) { $assertionFailure } else { 'Windows unpack smoke operation failed.' }
    $report.failureLine = $_.InvocationInfo.ScriptLineNumber
    Write-Warning ('Unpack smoke failed at script line ' + $_.InvocationInfo.ScriptLineNumber)
} finally {
    foreach ($p in $processes) { try { if (-not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null; $null = $p.WaitForExit(10000) } } catch {} }
    if ($report.ok) {
        try { Check-Payload } catch { $report.ok = $false; $report.packageUnchangedAfterRun = $false }
    }
    foreach ($path in @($owned | Sort-Object Length -Descending)) {
        $marker = Join-Path $path '.unpack-ci-owned'
        if ((Test-Path -LiteralPath $marker) -and [IO.File]::ReadAllText($marker) -eq $token) {
            for ($attempt=0; $attempt -lt 10; $attempt++) {
                try { Remove-Item -LiteralPath $path -Recurse -Force; break } catch { Start-Sleep -Milliseconds 500 }
            }
            if (Test-Path -LiteralPath $path) { $report.ok = $false; $report.cleanupComplete = $false }
        }
    }
    $json = $report | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), $json, [Text.UTF8Encoding]::new($false))
    Write-Output $json
}
if (-not $report.ok) { exit 1 }
