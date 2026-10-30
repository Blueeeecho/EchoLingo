param([Parameter(Mandatory=$true)][string]$ExecutablePath)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $ExecutablePath).Path
# A GUI-subsystem child must be explicitly awaited with redirected handles;
# PowerShell's call operator can detach it and close its output pipe early.
function Invoke-OwnedChild([string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $exe
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) {
            $process.Kill()
            if (-not $process.WaitForExit(3000)) { throw 'NATIVE_BINARY_GATE: Timed-out owned child did not confirm exit after termination.' }
            throw 'NATIVE_BINARY_GATE: Owned child exceeded its bounded no-input smoke-test timeout.'
        }
        $text = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($text.Length -gt 65536 -or $errors.Length -gt 65536) { throw 'NATIVE_BINARY_GATE: Unexpectedly large child reply.' }
        return @{ exitCode = $process.ExitCode; reply = ($text | ConvertFrom-Json) }
    } finally { $process.Dispose() }
}
$cases = [Collections.Generic.List[object]]::new()
foreach ($case in @(
    @{ name = 'missing-arguments'; arguments = @() },
    @{ name = 'duplicate-mode'; arguments = @('-Mode','capture-image','-CaptureHostThreadId','1','-CaptureHostToken','1','-NativeCancellationEvent','Local\EchoLingoParserOnly-NoEventCreated','-Mode','capture-image') },
    @{ name = 'unknown-flag'; arguments = @('-Unknown','value') },
    @{ name = 'selection-not-supported'; arguments = @('-Mode','selected-text') }
)) {
    $arguments = $case.arguments
    $result = Invoke-OwnedChild $arguments
    $code = $result.exitCode
    $reply = $result.reply
    if ($code -eq 0 -or $reply.ok -ne $false -or $reply.error -notlike 'CAPTURE_ARGUMENT*' -or $null -ne $reply.imageBase64) { throw "NATIVE_ARGUMENT_GATE: $($case.name) did not fail closed before native UI." }
    $cases.Add(@{ name = $case.name; passed = $true; exitCode = $code })
}
$result = Invoke-OwnedChild @('--self-test')
$code = $result.exitCode
$reply = $result.reply
if ($code -ne 0 -or $reply.ok -ne $true -or $reply.memoryPixelSelfTest -ne $true -or $reply.nativeBackend -ne 'rust-win32-capture') { throw 'NATIVE_MEMORY_GATE: Real linked child failed its memory GDI pixel/PNG self-test.' }
[Console]::Out.WriteLine((@{ ok = $true; executableSha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant(); nativeBackend = $reply.nativeBackend; argumentCases = $cases.ToArray(); memoryPixelSelfTest = $true; realSelectorTested = $false } | ConvertTo-Json -Depth 5 -Compress))
