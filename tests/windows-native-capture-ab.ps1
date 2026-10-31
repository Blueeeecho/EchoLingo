# Same-runner paired command-to-border measurements; never substitutes for app acceptance.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$NativeCapturePath,
    [Parameter(Mandatory=$true)][string]$NativeHarnessPath,
    [Parameter(Mandatory=$true)][string]$LegacyHarnessPath,
    [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,
    [string]$HelperPath='',
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$IsolatedTestSession
)
$ErrorActionPreference='Stop'
if(-not $IsolatedTestSession -and -not $env:GITHUB_ACTIONS){throw 'ISOLATION_REQUIRED'}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_DESKTOP_REQUIRED'}
if(-not $HelperPath){$HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1'}
$paths=@{native=$NativeCapturePath;nativeHarness=$NativeHarnessPath;legacyHarness=$LegacyHarnessPath;legacyAssembly=$NativeAssemblyPath;legacyScript=$HelperPath}
$hashes=@{}
foreach($key in @($paths.Keys)){$paths[$key]=(Resolve-Path -LiteralPath $paths[$key]).Path;$hashes[$key]=(Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$key]).Hash.ToLowerInvariant()}
# Do not overwrite an existing evidence directory or clean a caller-owned path.
if(Test-Path -LiteralPath $OutputDirectory){throw 'AB_OUTPUT_MUST_BE_NEW'}
$directory=New-Item -ItemType Directory -Path $OutputDirectory
$shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$measurements=@();$orders=@(@('legacy','native'),@('native','legacy'),@('legacy','native'))
$common=@('first-fresh-pair-immediate-release','topmost-self-raise-immediate-first-pair','foreign-thread-native-capture','cross-peer-held900ms','preheld-source-release-then-first-fresh-pair','escape-drains-owned-release','escape-held-release-after-helper-close','next-capture-after-escape','display-change-before-input','next-capture-after-display-change')
$nativeModes=$common+@('magnifier-continuity-armed-and-dragging','escape-held900ms-drains-real-key-up','next-capture-after-held-escape','own-plane-cancelmode-no-input','next-capture-after-plane-cancelmode','benign-dpi-notifications-then-capture')
function Median($Values){$sorted=@($Values|Sort-Object);$n=$sorted.Count;if($n -eq 0){throw 'AB_EMPTY_MEDIAN'};if($n % 2){return [double]$sorted[[int][Math]::Floor($n/2)]};return ([double]$sorted[$n/2-1]+[double]$sorted[$n/2])/2}
if((Median @(1,2,100)) -ne 2 -or (Median @(100,1,2)) -ne 2 -or (Median @(9,1,5,3)) -ne 4 -or (Median @(7)) -ne 7){throw 'AB_MEDIAN_SELF_TEST'}
try {
    for($round=0;$round -lt 3;$round++){
        foreach($backend in $orders[$round]){
            $script=if($backend -eq 'legacy'){'windows-delegated-capture-smoke.ps1'}else{'windows-native-capture-smoke.ps1'}
            $arguments=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $script),'-IsolatedTestSession')
            if($backend -eq 'legacy'){$arguments+=@('-HelperPath',$paths.legacyScript,'-NativeAssemblyPath',$paths.legacyAssembly,'-HarnessPath',$paths.legacyHarness)}
            else{$arguments+=@('-NativeCapturePath',$paths.native,'-HarnessPath',$paths.nativeHarness)}
            # Each complete run must pass once; no failed case is retried or omitted.
            $raw=@(& $shell @arguments);$exitCode=$LASTEXITCODE
            $evidence=Join-Path $directory.FullName ("round-{0}-{1}.json" -f ($round+1),$backend)
            $raw -join "`n" | Set-Content -LiteralPath $evidence -Encoding UTF8
            if($exitCode -ne 0){throw "AB_STRICT_FIXTURE_FAILED: round=$($round+1) backend=$backend exit=$exitCode"}
            $result=($raw -join "`n")|ConvertFrom-Json
            $expectedModes=if($backend -eq 'legacy'){$common}else{$nativeModes};$expected=$expectedModes.Count
            if(-not $result.ok -or @($result.cases).Count -ne $expected -or @($result.cases|Where-Object {-not $_.ok}).Count){throw "AB_CASE_GATE: $backend"}
            $actualModes=@($result.cases|ForEach-Object {$_.mode})
            if(@($actualModes|Select-Object -Unique).Count -ne $expected -or @(Compare-Object $expectedModes $actualModes).Count){throw "AB_EXACT_CASE_SET: $backend"}
            foreach($mode in $common){
                $cases=@($result.cases|Where-Object {$_.mode -eq $mode})
                if($cases.Count -ne 1){throw "AB_MODE_NOT_UNIQUE: $mode"};$case=$cases[0]
                if($backend -eq 'native' -and ($case.helperDiagnostics.nativeBackend -ne 'rust-win32-capture' -or $case.helperDiagnostics.captureHealth.nativeCaptureBackend -ne 1)){throw 'AB_NATIVE_BACKEND_MISMATCH'}
                if($backend -eq 'legacy' -and $case.helperDiagnostics.nativeBackend -ne 'precompiled-framework-dll'){throw 'AB_LEGACY_BACKEND_MISMATCH'}
                foreach($field in @('requestToFirstBorderObservedMilliseconds','requestToFullPickerReadyObservedMilliseconds')){
                    if(-not $case.PSObject.Properties[$field] -or [double]$case.$field -le 0 -or [double]$case.$field -gt 30000){throw "AB_INVALID_MEASUREMENT: $field"}
                }
                $measurements+=@{round=$round+1;backend=$backend;mode=$mode;firstBorderMilliseconds=[double]$case.requestToFirstBorderObservedMilliseconds;fullReadyMilliseconds=[double]$case.requestToFullPickerReadyObservedMilliseconds}
            }
        }
    }
    $summary=@()
    foreach($mode in $common){foreach($backend in @('legacy','native')){
        $values=@($measurements|Where-Object {$_.mode -eq $mode -and $_.backend -eq $backend})
        if($values.Count -ne 3){throw 'AB_PAIR_COUNT'}
        $summary+=@{backend=$backend;mode=$mode;samples=3;medianFirstBorderMilliseconds=(Median $values.firstBorderMilliseconds);medianFullReadyMilliseconds=(Median $values.fullReadyMilliseconds)}
    }}
    $report=@{ok=$true;pairedRounds=3;orders=$orders;binarySha256=$hashes;measurements=$measurements;summary=$summary;allLegacyCasesPassed=30;allNativeCasesPassed=48;scope='Same Windows runner/session, alternating complete strict runs. Each child process is new; parent hook reused only within each run. OS caches not reset. Command-to-first-observed-border polling upper bounds, not application Alt+S or OCR latency. No physical multi-monitor or DPI-switch claim.'}
    $report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $directory.FullName 'summary.json') -Encoding UTF8
    $report|ConvertTo-Json -Depth 12 -Compress
} catch {
    @{ok=$false;error=$_.Exception.Message;completedMeasurements=$measurements;binarySha256=$hashes;noRetries=$true}|ConvertTo-Json -Depth 8 -Compress|Set-Content -LiteralPath (Join-Path $directory.FullName 'failure.json') -Encoding UTF8
    throw
}
