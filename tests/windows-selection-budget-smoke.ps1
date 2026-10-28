# Exact private production budget/query regression with synthetic delegates.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$NativeAssemblyPath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'WINDOWS_QUERY_THREAD_REQUIRED' }
    $native = (Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    $assembly = [Reflection.Assembly]::LoadFrom($native)
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-selection-budget-fixture.cs'))
    Add-Type -TypeDefinition $source -Language CSharp
    $result = [WindowsSelectionBudgetFixture]::Run($assembly)
    $result['nativeAssemblySha256'] = (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToLowerInvariant()
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 10 -Compress))
    if (-not $result.ok -or -not $result.selectionBudgetFixturePassed) { exit 1 }
    exit 0
} catch {
    [Console]::Out.WriteLine((@{ ok = $false; selectionBudgetFixturePassed = $false; error = $_.Exception.GetBaseException().Message; inputSent = $false; clipboardAccessed = $false; nativeHooksInstalled = $false; actualUIAProviderTested = $false } | ConvertTo-Json -Compress))
    exit 1
}
