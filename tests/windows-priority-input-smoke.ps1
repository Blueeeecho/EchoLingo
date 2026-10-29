# Exact production native hook/policy, generated competing process, real Win32
# registration and synthetic OS input on an isolated GitHub-hosted desktop.
[CmdletBinding()]
param([string]$OutputDirectory,[switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$summary=Join-Path $env:RUNNER_TEMP 'echolingo-priority-input-validation.json'
try {
    if(-not $IsolatedTestSession -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
       [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive){throw 'ISOLATED_INTERACTIVE_GITHUB_WINDOWS_REQUIRED'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'STA_REQUIRED'}
    if(-not $OutputDirectory){$OutputDirectory=Join-Path $env:RUNNER_TEMP ('echolingo-priority-input-'+[Guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $OutputDirectory){throw 'NEW_OUTPUT_DIRECTORY_REQUIRED'}
    $directory=[IO.Directory]::CreateDirectory($OutputDirectory).FullName
    $library=Join-Path $directory 'echolingo-priority-input-native-fixture.dll'
    $executable=Join-Path $directory 'echolingo-priority-input-peer.exe'
    $report=Join-Path $directory 'report.json'
    $native=Join-Path $PSScriptRoot 'windows-priority-input-native-fixture.rs'
    & rustc --edition 2021 --crate-type cdylib -C opt-level=1 $native -o $library
    if($LASTEXITCODE -ne 0){throw 'EXACT_NATIVE_FIXTURE_COMPILE_FAILED'}
    $compiler=Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if(-not (Test-Path -LiteralPath $compiler)){throw 'NET_FRAMEWORK_CSC_REQUIRED'}
    $fixture=Join-Path $PSScriptRoot 'windows-priority-input-fixture.cs'
    & $compiler /nologo /target:exe /platform:x64 /warnaserror+ /out:$executable /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll $fixture
    if($LASTEXITCODE -ne 0){throw 'OWNED_PEER_FIXTURE_COMPILE_FAILED'}
    & $executable $library $report | Out-Null
    $exit=$LASTEXITCODE
    if(-not (Test-Path -LiteralPath $report)){throw 'NATIVE_FIXTURE_REPORT_MISSING'}
    $result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    $result | Add-Member -NotePropertyName nativeModuleSha256 -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\src-tauri\src\windows_mouse_shortcuts.rs') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName pairPolicySha256 -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\src-tauri\src\mouse_shortcuts.rs') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName nativeWrapperSha256 -NotePropertyValue (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName nativeFixtureDllSha256 -NotePropertyValue (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName sourcePeerFixtureSha256 -NotePropertyValue (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName standaloneNativeFixture -NotePropertyValue $true
    $json=$result | ConvertTo-Json -Depth 12 -Compress
    [IO.File]::WriteAllText($summary,$json,[Text.UTF8Encoding]::new($false))
    $json
    if($exit -ne 0 -or -not $result.ok -or $result.executedCases -ne 17 -or -not $result.nativeHookStopped -or -not $result.ownedPeerStopped){exit 1}
}catch{
    $json=@{ok=$false;standaloneNativeFixture=$true;stage='fixture-entry';error=$_.Exception.Message;actualApplicationTested=$false;actualWpsTested=$false;userContentRead=$false}|ConvertTo-Json -Compress
    [IO.File]::WriteAllText($summary,$json,[Text.UTF8Encoding]::new($false))
    $json
    exit 1
}
