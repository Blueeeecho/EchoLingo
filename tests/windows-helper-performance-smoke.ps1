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
        $order = if (($i % 2) -eq 0) { @('baseline', 'candidate') } else { @('candidate', 'baseline') }
        foreach ($variant in $order) {
            $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $live, '-HelperPath')
            if ($variant -eq 'candidate') { $arguments += @($HelperPath, '-NativeAssemblyPath', $NativeAssemblyPath, '-PerformanceDiagnostics') }
            else { $arguments += $BaselineHelperPath }
            $raw = @(& $powershell @arguments)
            $exit = $LASTEXITCODE
            $result = ($raw -join "`n") | ConvertFrom-Json
            $runs.Add(@{ variant = $variant; iteration = $i; report = $result })
            if ($exit -ne 0 -or -not $result.ok -or @($result.trials).Count -ne 8) { throw "PERFORMANCE_FIXTURE: $variant did not pass all eight actual live/input/cancel/next-capture cases." }
            if ($variant -eq 'candidate') {
                foreach ($trial in $result.trials) {
                    if ($trial.nativeBackend -ne 'precompiled-framework-dll' -or $null -eq $trial.helperPerformance -or $null -eq $trial.captureHealth) { throw 'PRECOMPILED_GATE: A candidate session did not use the exact explicit native DLL or provide safe timing/input metadata.' }
                }
                $burst = @($result.trials | Where-Object { $_.mode -eq 'capture-burst' })[0]
                if ($burst.captureHealth.hookMouseMoves -le 0 -or $burst.captureHealth.hookMouseDowns -le 0 -or $burst.captureHealth.hookMouseUps -le 0 -or $burst.capturePerformance.moveFrameCount -le 0) { throw 'INPUT_GATE: Candidate blue borders did not prove actual movement/down/up plus coalesced UI frame delivery.' }
            }
        }
    }
    $baseline = Get-Summary @($runs | Where-Object { $_.variant -eq 'baseline' })
    $candidate = Get-Summary @($runs | Where-Object { $_.variant -eq 'candidate' })
    [Console]::Out.WriteLine((@{
        ok = $true; baselineCanonicalSha256 = $baselineHash; candidateCanonicalSha256 = (Get-CanonicalHash $HelperPath)
        nativeAssemblySha256 = (Get-FileHash -LiteralPath $NativeAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
        baseline = $baseline; candidate = $candidate; runs = $runs.ToArray()
        scope = 'Same runner generated sources, fresh helper processes; OS cache not flushed. Descriptive A/B measurements, not physical Windows11 acceptance or a guaranteed speed-up.'
        userContentCaptured = $false; clipboardAccessed = $false; credentialsAccessed = $false
    } | ConvertTo-Json -Depth 18 -Compress))
} catch {
    [Console]::Out.WriteLine((@{ ok = $false; error = $_.Exception.Message; runs = $runs; userContentCaptured = $false; clipboardAccessed = $false; credentialsAccessed = $false } | ConvertTo-Json -Depth 18 -Compress))
    exit 1
}
