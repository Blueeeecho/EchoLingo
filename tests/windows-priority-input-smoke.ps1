# Exact production native hook/policy, generated competing process, real Win32
# registration and synthetic OS input on an isolated GitHub-hosted desktop.
[CmdletBinding()]
param([string]$OutputDirectory,[switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$summary=Join-Path $env:RUNNER_TEMP 'echolingo-priority-input-validation.json'
$baseline=$null
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

    # This immutable pre-recovery module is a required real OS-input negative
    # control. Its later-active-hook failure must be reproduced, never skipped
    # or counted as successful product recovery. Keep both raw reports.
    $baselineRevision='f88575efc82817af78c6d273468041f3f1a9fad7'
    $repository=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    function Invoke-HistoricalGit([string]$Arguments) {
        $launch=[Diagnostics.ProcessStartInfo]::new()
        $launch.FileName='git';$launch.Arguments=$Arguments;$launch.WorkingDirectory=$repository
        $launch.UseShellExecute=$false;$launch.RedirectStandardOutput=$true;$launch.RedirectStandardError=$true
        $process=[Diagnostics.Process]::new();$process.StartInfo=$launch
        try {
            if(-not $process.Start()){throw 'HISTORICAL_GIT_START_FAILED'}
            $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            $process.WaitForExit();$null=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
            return $process.ExitCode
        }finally{$process.Dispose()}
    }
    if((Invoke-HistoricalGit ('cat-file -e '+$baselineRevision+'^{commit}')) -ne 0){
        if((Invoke-HistoricalGit ('fetch --quiet --no-tags --depth=1 origin '+$baselineRevision)) -ne 0){throw 'HISTORICAL_SOURCE_FETCH_FAILED'}
    }
    function Read-HistoricalSource([string]$Path,[string]$ExpectedSha256,[string]$Destination) {
        $launch=[Diagnostics.ProcessStartInfo]::new()
        $launch.FileName='git'
        $launch.Arguments='cat-file blob '+$baselineRevision+':'+$Path
        $launch.WorkingDirectory=$repository
        $launch.UseShellExecute=$false
        $launch.RedirectStandardOutput=$true
        $launch.RedirectStandardError=$true
        $process=[Diagnostics.Process]::new()
        $process.StartInfo=$launch
        $bytes=[IO.MemoryStream]::new()
        try {
            if(-not $process.Start()){throw 'HISTORICAL_SOURCE_READ_START_FAILED'}
            $process.StandardOutput.BaseStream.CopyTo($bytes)
            $failure=$process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if($process.ExitCode -ne 0){throw ('HISTORICAL_SOURCE_READ_FAILED:'+ $Path)}
            [IO.File]::WriteAllBytes($Destination,$bytes.ToArray())
        }finally{$bytes.Dispose();$process.Dispose()}
        $actual=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actual -cne $ExpectedSha256){throw ('HISTORICAL_SOURCE_SHA256_MISMATCH:'+ $Path)}
        return $actual
    }
    $baselineNative=Join-Path $directory 'historical-windows_mouse_shortcuts.rs'
    $baselinePolicy=Join-Path $directory 'historical-mouse_shortcuts.rs'
    $baselineNativeSha=Read-HistoricalSource 'src-tauri/src/windows_mouse_shortcuts.rs' '574b8a905d29f4c993084ff1c97620b8e2f005b3a8bcbb0718d8ae02a7ca0e4f' $baselineNative
    $baselinePolicySha=Read-HistoricalSource 'src-tauri/src/mouse_shortcuts.rs' 'b6d4765a29b8cb081f7278af2bb39d9de4a2809333d1abdbf24378a7862df0d3' $baselinePolicy
    $baselineWrapper=Join-Path $directory 'historical-native-fixture.rs'
    $wrapperText=[IO.File]::ReadAllText($native)
    foreach($entry in @(@('windows_mouse_shortcuts.rs',$baselineNative),@('mouse_shortcuts.rs',$baselinePolicy))){
        $original='#[path = "../src-tauri/src/'+$entry[0]+'"]'
        if(-not $wrapperText.Contains($original)){throw 'HISTORICAL_WRAPPER_PATH_NOT_FOUND'}
        $replacement='#[path = "'+$entry[1].Replace('\','\\').Replace('"','\"')+'"]'
        $wrapperText=$wrapperText.Replace($original,$replacement)
    }
    [IO.File]::WriteAllText($baselineWrapper,$wrapperText,[Text.UTF8Encoding]::new($false))
    $baselineLibrary=Join-Path $directory 'echolingo-priority-input-historical.dll'
    & rustc --edition 2021 --crate-type cdylib --cfg legacy_priority_fixture -C opt-level=1 $baselineWrapper -o $baselineLibrary
    if($LASTEXITCODE -ne 0){throw 'HISTORICAL_NATIVE_FIXTURE_COMPILE_FAILED'}
    $baselineReport=Join-Path $directory 'historical-report.json'
    & $executable $baselineLibrary $baselineReport --historical-control | Out-Null
    $baselineExit=$LASTEXITCODE
    if(-not (Test-Path -LiteralPath $baselineReport)){throw 'HISTORICAL_NATIVE_REPORT_MISSING'}
    $baseline=Get-Content -LiteralPath $baselineReport -Raw | ConvertFrom-Json
    $baseline | Add-Member -NotePropertyName processExitCode -NotePropertyValue $baselineExit
    $baseline | Add-Member -NotePropertyName sourceRevision -NotePropertyValue $baselineRevision
    $baseline | Add-Member -NotePropertyName nativeModuleSha256 -NotePropertyValue $baselineNativeSha
    $baseline | Add-Member -NotePropertyName pairPolicySha256 -NotePropertyValue $baselinePolicySha
    $baseline | Add-Member -NotePropertyName nativeWrapperSha256 -NotePropertyValue (Get-FileHash -LiteralPath $baselineWrapper -Algorithm SHA256).Hash.ToLowerInvariant()
    $baseline | Add-Member -NotePropertyName nativeFixtureDllSha256 -NotePropertyValue (Get-FileHash -LiteralPath $baselineLibrary -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($baselineReport,($baseline | ConvertTo-Json -Depth 16 -Compress),[Text.UTF8Encoding]::new($false))

    & $executable $library $report | Out-Null
    $exit=$LASTEXITCODE
    if(-not (Test-Path -LiteralPath $report)){throw 'NATIVE_FIXTURE_REPORT_MISSING'}
    $result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    $result | Add-Member -NotePropertyName processExitCode -NotePropertyValue $exit
    $result | Add-Member -NotePropertyName historicalControl -NotePropertyValue $baseline
    $result | Add-Member -NotePropertyName nativeModuleSha256 -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\src-tauri\src\windows_mouse_shortcuts.rs') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName pairPolicySha256 -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\src-tauri\src\mouse_shortcuts.rs') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName nativeWrapperSha256 -NotePropertyValue (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName nativeFixtureDllSha256 -NotePropertyValue (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName sourcePeerFixtureSha256 -NotePropertyValue (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | Add-Member -NotePropertyName standaloneNativeFixture -NotePropertyValue $true
    $historicalOk=$baselineExit -eq 0 -and $baseline.ok -and $baseline.executedCases -eq 9 -and $baseline.requiredCases -eq 9 -and
        $baseline.laterHookOldPriorityFailureReproduced -and $baseline.nativeHookStopped -and $baseline.ownedPeerStopped
    $result | Add-Member -NotePropertyName historicalControlPassed -NotePropertyValue ([bool]$historicalOk)
    if(-not $historicalOk){$result.ok=$false}
    $json=$result | ConvertTo-Json -Depth 16 -Compress
    [IO.File]::WriteAllText($report,$json,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($summary,$json,[Text.UTF8Encoding]::new($false))
    $json
    if($exit -ne 0 -or -not $result.ok -or $result.executedCases -ne 32 -or $result.requiredCases -ne 32 -or
       -not $result.laterHookOldPriorityFailureReproduced -or -not $historicalOk -or
       -not $result.nativeHookStopped -or -not $result.ownedPeerStopped){exit 1}
}catch{
    $json=@{ok=$false;standaloneNativeFixture=$true;stage='fixture-entry';error=$_.Exception.Message;actualApplicationTested=$false;actualWpsTested=$false;actualDoubaoTested=$false;userContentRead=$false;historicalControl=$baseline}|ConvertTo-Json -Depth 16 -Compress
    [IO.File]::WriteAllText($summary,$json,[Text.UTF8Encoding]::new($false))
    $json
    exit 1
}
