# Actual generated-window A/B fixture on one isolated Windows desktop. Neither
# implementation may inspect a user's desktop content or credentials.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaselineHelperPath,
    [Parameter(Mandatory = $true)][string]$NativeAssemblyPath,
    [string]$HelperPath = '',
    [ValidateRange(1, 3)][int]$Iterations = 1
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
function Get-CanonicalHash([string]$Path) {
    $text = [IO.File]::ReadAllText($Path).TrimStart([char]0xfeff).Replace("`r`n", "`n")
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($text)))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}
function Get-Summary([object[]]$Runs) {
    $ready = @($Runs | ForEach-Object { $_.report.trials } | ForEach-Object { [double]$_.helperStartupToReadyMilliseconds } | Sort-Object)
    $bursts = @($Runs | ForEach-Object { $_.report.trials } | Where-Object { $_.mode -eq 'capture-burst' })
    return @{
        freshProcessReadinessSamples = $ready
        freshProcessReadinessP50Milliseconds = $ready[[int][Math]::Ceiling($ready.Count * 0.5) - 1]
        freshProcessReadinessP95Milliseconds = $ready[[int][Math]::Ceiling($ready.Count * 0.95) - 1]
        dragSamples = @($bursts | ForEach-Object { @{ p50Milliseconds = $_.dragToObservedBorderP50Milliseconds; p95Milliseconds = $_.dragToObservedBorderP95Milliseconds; cpuMilliseconds = $_.helperCpuMillisecondsDuringDrag; wallMilliseconds = $_.dragWallMilliseconds; workingSetBytes = $_.helperWorkingSetBytesDuringDrag } })
    }
}
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) { throw 'DESKTOP_UNAVAILABLE: Use an unlocked isolated Windows desktop.' }
    if ([string]::IsNullOrWhiteSpace($HelperPath)) { $HelperPath = Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1' }
    $HelperPath = (Resolve-Path -LiteralPath $HelperPath).Path
    $BaselineHelperPath = (Resolve-Path -LiteralPath $BaselineHelperPath).Path
    $NativeAssemblyPath = (Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    $baselineHash = Get-CanonicalHash $BaselineHelperPath
    if ($baselineHash -ne '4a3674ff1b7da09b664fe807ead116d45b5689adcfc2bc2a47eea77ee6d7b1b7') { throw 'BASELINE_IDENTITY: Expected the exact ab4405c hover helper, not a rewritten comparison.' }
    $live = Join-Path $PSScriptRoot 'windows-live-capture-smoke.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $runs = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Iterations; $i++) {
        # Alternate order between repetitions to expose warm-cache/order effects.
        $order = if (($i % 2) -eq 0) { @('baseline', 'candidate', 'candidate-planeOnly') } else { @('candidate-planeOnly', 'candidate', 'baseline') }
        foreach ($variant in $order) {
            $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $live, '-HelperPath')
            if ($variant -ne 'baseline') {
                $arguments += @($HelperPath, '-NativeAssemblyPath', $NativeAssemblyPath, '-PerformanceDiagnostics')
                if ($variant -eq 'candidate-planeOnly') { $arguments += @('-InputBackend', 'planeOnly') }
            } else { $arguments += @($BaselineHelperPath, '-LegacyBaseline') }
            $raw = @(& $powershell @arguments)
            $exit = $LASTEXITCODE
            $result = ($raw -join "`n") | ConvertFrom-Json
            $runs.Add(@{ variant = $variant; iteration = $i; report = $result })
            $expectedModes = if ($variant -eq 'baseline') {
                'capture,capture-burst,topmost-capture,escape-short,escape,right,capture,hover-window-follow'
            } else {
                'capture,capture-burst,topmost-capture,escape-short,escape,right,capture,dpi-notification,display-change,capture,hover-window-follow'
            }
            $actualModes = (@($result.trials | ForEach-Object { $_.mode }) -join ',')
            if ($exit -ne 0 -or -not $result.ok -or $actualModes -ne $expectedModes -or @($result.trials | Where-Object { -not $_.passed }).Count -ne 0 -or -not $result.crossPeerCapturePassed -or -not $result.crossPeerCapture.passed) { throw "PERFORMANCE_FIXTURE: $variant did not pass every required live/input/cancel/next-capture case in order plus independent ordinary-peer long drag." }
            if ($variant -ne 'baseline' -and (-not $result.benignDpiNotificationsPassed -or -not $result.displayChangeCancelledAndNextCapturePassed)) { throw 'DISPLAY_GATE: Candidate did not prove benign DPI continuation and display-change cancellation followed by fresh capture.' }
            if ($variant -ne 'baseline') {
                $planeOnly = $variant -eq 'candidate-planeOnly'
                $expectedBackend = if ($planeOnly) { 2 } else { 1 }
                $expectedMouseHook = if ($planeOnly) { 0 } else { 1 }
                if (-not $result.requiredInputPlanes -or $result.requestedInputBackend -ne $(if ($planeOnly) { 'planeOnly' } else { 'hybrid' })) { throw 'PLANE_GATE: Candidate did not require the exact requested input plane implementation.' }
                foreach ($trial in @($result.trials) + @($result.crossPeerCapture)) {
                    if ($trial.nativeBackend -ne 'precompiled-framework-dll' -or $null -eq $trial.helperPerformance -or $null -eq $trial.captureHealth) { throw 'PRECOMPILED_GATE: A candidate session did not use the exact explicit native DLL or provide safe timing/input metadata.' }
                    if ($trial.captureHealth.inputBackend -ne $expectedBackend -or $trial.captureHealth.mouseHookInstalled -ne $expectedMouseHook -or $trial.captureHealth.inputPlaneCount -le 0 -or $trial.captureHealth.inputPlaneRemainingAfterCleanup -ne 0) { throw 'PLANE_GATE: Real helper backend/allocation/cleanup metadata did not match the requested mode.' }
                    if ($planeOnly -and $trial.mode -notin @('escape-short','escape','right','display-change') -and ($trial.captureHealth.inputPlaneDowns -le 0 -or $trial.captureHealth.inputPlaneUps -le 0 -or $trial.captureHealth.inputPlaneFallbackUsed -ne 1)) { throw 'FALLBACK_GATE: Forced no-hook capture did not prove actual input plane down/up delivery.' }
                }
                $displayCancelled = @($result.trials | Where-Object { $_.mode -eq 'display-change' })[0]
                if ($displayCancelled.captureHealth.inputPlaneDowns -ne 0 -or $displayCancelled.captureHealth.inputPlaneUps -ne 0 -or $displayCancelled.captureHealth.hookMouseDowns -ne 0 -or $displayCancelled.captureHealth.hookMouseUps -ne 0) { throw 'DISPLAY_GATE: The no-input display-cancellation case unexpectedly consumed mouse input.' }
                $burst = @($result.trials | Where-Object { $_.mode -eq 'capture-burst' })[0]
                if ($burst.capturePerformance.moveFrameCount -le 0) { throw 'INPUT_GATE: Candidate did not prove actual coalesced UI move frames.' }
                if (-not $planeOnly -and ($burst.captureHealth.hookMouseMoves -le 0 -or $burst.captureHealth.hookMouseDowns -le 0 -or $burst.captureHealth.hookMouseUps -le 0)) { throw 'INPUT_GATE: Hybrid candidate did not prove actual hook movement/down/up.' }
                if ($planeOnly -and ($burst.captureHealth.inputPlaneMoves -le 0 -or $burst.captureHealth.hookMouseMoves -ne 0 -or $burst.captureHealth.hookMouseDowns -ne 0 -or $burst.captureHealth.hookMouseUps -ne 0)) { throw 'FALLBACK_GATE: No-hook burst did not prove actual input plane moves.' }
            }
        }
    }
    $baseline = Get-Summary @($runs | Where-Object { $_.variant -eq 'baseline' })
    $candidate = Get-Summary @($runs | Where-Object { $_.variant -eq 'candidate' })
    $planeOnly = Get-Summary @($runs | Where-Object { $_.variant -eq 'candidate-planeOnly' })
    [Console]::Out.WriteLine((@{
        ok = $true; baselineCanonicalSha256 = $baselineHash; candidateCanonicalSha256 = (Get-CanonicalHash $HelperPath)
        nativeAssemblySha256 = (Get-FileHash -LiteralPath $NativeAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
        baseline = $baseline; candidate = $candidate; candidatePlaneOnly = $planeOnly; runs = $runs.ToArray()
        scope = 'Same runner generated sources; baseline exact legacy source has no input planes; candidate hybrid and forced-no-mouse-hook planeOnly share the exact source/DLL. Fresh helper processes; OS cache not flushed. Descriptive A/B measurements, not physical Windows11 acceptance or a guaranteed speed-up.'
        userContentCaptured = $false; clipboardAccessed = $false; credentialsAccessed = $false
    } | ConvertTo-Json -Depth 18 -Compress))
} catch {
    [Console]::Out.WriteLine((@{ ok = $false; error = $_.Exception.Message; runs = $runs; userContentCaptured = $false; clipboardAccessed = $false; credentialsAccessed = $false } | ConvertTo-Json -Depth 18 -Compress))
    exit 1
}
