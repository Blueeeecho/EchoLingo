# Same machine / same DLL, alternating fresh processes; no user's clipboard,
# source app or screen is read. self-test OCR uses only a generated local image.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,
    [string]$HelperPath = '',
    [string]$LauncherPath = ''
)
$ErrorActionPreference='Stop'
try {
    if (-not $HelperPath) { $HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1' }
    if (-not $LauncherPath) { $LauncherPath=Join-Path (Split-Path -Parent $NativeAssemblyPath) 'echolingo-windows-launcher.ps1' }
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $LauncherPath=(Resolve-Path -LiteralPath $LauncherPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $negative=@(& $shell -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $LauncherPath -Mode capture-state-self-test)
    $exit=$LASTEXITCODE
    $reply=($negative -join "`n")|ConvertFrom-Json
    if ($exit -eq 0 -or $reply.ok -or $reply.error -notlike 'NATIVE_ASSEMBLY:*') { throw 'LAUNCHER_MISSING_DLL: Packaged launcher did not fail closed.' }
    $runs=New-Object 'System.Collections.Generic.List[object]'
    foreach($mode in @('capture-state-self-test','self-test')) {
        for($iteration=0;$iteration -lt 3;$iteration++) {
            $order=if($iteration%2 -eq 0){@('source','launcher')}else{@('launcher','source')}
            foreach($variant in $order) {
                $path=if($variant -eq 'source'){$HelperPath}else{$LauncherPath}
                $watch=[Diagnostics.Stopwatch]::StartNew()
                $raw=@(& $shell -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $path -Mode $mode -NativeAssemblyPath $NativeAssemblyPath -PerformanceDiagnostics)
                $exit=$LASTEXITCODE;$watch.Stop()
                $reply=($raw -join "`n")|ConvertFrom-Json
                if($exit -ne 0 -or -not $reply.ok -or $reply.nativeBackend -ne 'precompiled-framework-dll') { throw "LAUNCHER_EQUIVALENCE: $variant $mode failed." }
                if($mode -eq 'self-test' -and -not $reply.diagnostics.ocrFixturePassed){throw 'LAUNCHER_OCR: Generated image OCR failed.'}
                if($mode -eq 'capture-state-self-test' -and -not $reply.diagnostics.captureStateFixturePassed){throw 'LAUNCHER_POLICY: Native policy tests failed.'}
                $phases=@{}
                foreach($name in @('assembliesLoadedMilliseconds','nativeTypesReadyMilliseconds','replyMilliseconds')) {
                    $value=$reply.helperPerformance.$name
                    if($null -eq $value -or [double]$value -lt 0){throw 'LAUNCHER_PHASE: Missing bounded phase.'}
                    $phases[$name]=[double]$value
                }
                $runs.Add(@{variant=$variant;mode=$mode;iteration=$iteration;elapsedMilliseconds=$watch.Elapsed.TotalMilliseconds;phases=$phases})
            }
        }
    }
    [Console]::Out.WriteLine((@{ok=$true;missingDllFailsClosed=$true;sourceBytes=(Get-Item -LiteralPath $HelperPath).Length;launcherBytes=(Get-Item -LiteralPath $LauncherPath).Length;runs=$runs.ToArray();scope='Alternating fresh PowerShell processes on one runner with identical DLL; OS caches not flushed. Generated-image OCR and pure policies only; separate app gates validate actual selection/capture/cancellation. No fixed latency promise.'}|ConvertTo-Json -Depth 7 -Compress))
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
