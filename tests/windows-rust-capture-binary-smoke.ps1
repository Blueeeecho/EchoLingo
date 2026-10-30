param([Parameter(Mandatory=$true)][string]$ExecutablePath)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $ExecutablePath).Path
$cases = [Collections.Generic.List[object]]::new()
foreach ($case in @(
    @{ name = 'missing-arguments'; arguments = @() },
    @{ name = 'duplicate-mode'; arguments = @('-Mode','capture-image','-CaptureHostThreadId','1','-CaptureHostToken','1','-NativeCancellationEvent','Local\EchoLingoParserOnly-NoEventCreated','-Mode','capture-image') },
    @{ name = 'unknown-flag'; arguments = @('-Unknown','value') },
    @{ name = 'selection-not-supported'; arguments = @('-Mode','selected-text') }
)) {
    $arguments = $case.arguments
    $raw = @(& $exe @arguments)
    $code = $LASTEXITCODE
    $reply = ($raw -join "`n") | ConvertFrom-Json
    if ($code -eq 0 -or $reply.ok -ne $false -or $reply.error -notlike 'CAPTURE_ARGUMENT*' -or $null -ne $reply.imageBase64) { throw "NATIVE_ARGUMENT_GATE: $($case.name) did not fail closed before native UI." }
    $cases.Add(@{ name = $case.name; passed = $true; exitCode = $code })
}
$raw = @(& $exe --self-test)
$code = $LASTEXITCODE
$reply = ($raw -join "`n") | ConvertFrom-Json
if ($code -ne 0 -or $reply.ok -ne $true -or $reply.memoryPixelSelfTest -ne $true -or $reply.nativeBackend -ne 'rust-win32-capture') { throw 'NATIVE_MEMORY_GATE: Real linked child failed its memory GDI pixel/PNG self-test.' }
[Console]::Out.WriteLine((@{ ok = $true; executableSha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant(); nativeBackend = $reply.nativeBackend; argumentCases = $cases.ToArray(); memoryPixelSelfTest = $true; realSelectorTested = $false } | ConvertTo-Json -Depth 5 -Compress))
