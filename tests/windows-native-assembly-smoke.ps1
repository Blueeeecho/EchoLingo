# Native build/load boundary only: no screenshots, input, public clipboard or
# user data. Pass the exact DLL emitted by Cargo's Windows build script.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$NativeAssemblyPath, [string]$HelperPath = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'NATIVE_ASSEMBLY_TEST: Windows is required.' }
    if ([string]::IsNullOrWhiteSpace($HelperPath)) { $HelperPath = Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1' }
    $HelperPath = (Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath = (Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $common = @('-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $HelperPath, '-Mode', 'capture-state-self-test', '-NativeAssemblyPath')
    $good = @(& $powershell @common $NativeAssemblyPath)
    $goodExit = $LASTEXITCODE; $goodResult = ($good -join "`n") | ConvertFrom-Json
    if ($goodExit -ne 0 -or -not $goodResult.ok -or $goodResult.nativeBackend -ne 'precompiled-framework-dll' -or
        $goodResult.diagnostics.fixtureAssertions -lt 99 -or $goodResult.diagnostics.screenCaptured -or $goodResult.diagnostics.clipboardChanged) { throw 'NATIVE_ASSEMBLY_TEST: The exact precompiled DLL did not pass the real production pure policies.' }
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('echolingo-assembly-fixture-' + [Guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($directory)
    $bad = Join-Path $directory 'corrupt.dll'; [IO.File]::WriteAllBytes($bad, [byte[]]@(0, 1, 2, 3))
    $cases = [Collections.Generic.List[object]]::new()
    try {
        foreach ($path in @((Join-Path $directory 'missing.dll'), $bad, [string].Assembly.Location)) {
            $raw = @(& $powershell @common $path)
            $code = $LASTEXITCODE; $result = ($raw -join "`n") | ConvertFrom-Json
            if ($code -eq 0 -or $result.ok -or $result.nativeBackend -ne 'precompiled-framework-dll' -or -not $result.error.StartsWith('NATIVE_ASSEMBLY:', [StringComparison]::Ordinal)) { throw 'NATIVE_ASSEMBLY_TEST: A missing, corrupt, or unrelated assembly silently fell back to runtime compilation.' }
            $cases.Add(@{ passed = $true; backend = $result.nativeBackend; errorCategory = 'NATIVE_ASSEMBLY'; sourceCompilationFallback = $false })
        }
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force }
    [Console]::Out.WriteLine((@{ ok = $true; nativeAssemblySha256 = (Get-FileHash -LiteralPath $NativeAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant(); pure = $goodResult.diagnostics; invalidAssemblyCases = $cases.ToArray(); screenCaptured = $false; inputSent = $false; clipboardAccessed = $false; userDataRead = $false } | ConvertTo-Json -Depth 8 -Compress))
} catch {
    [Console]::Out.WriteLine((@{ ok = $false; error = $_.Exception.Message; screenCaptured = $false; inputSent = $false; clipboardAccessed = $false; userDataRead = $false } | ConvertTo-Json -Compress))
    exit 1
}
