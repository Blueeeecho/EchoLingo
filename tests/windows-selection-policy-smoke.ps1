# Pure selection regression tests against the exact production policy class.
# No native helper execution, UI Automation, key injection or clipboard access.
[CmdletBinding()]
param([string]$HelperPath = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
try {
    $directory = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($directory)) { $directory = Split-Path -Parent $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($HelperPath)) { $HelperPath = Join-Path $directory '..\src-tauri\native\windows.ps1' }
    $native = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $HelperPath).Path)
    $start = $native.IndexOf('public static class SelectionCopyPolicy {', [StringComparison]::Ordinal)
    $end = $native.IndexOf('public static class EchoLingoNative {', [StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -le $start) { throw 'SELECTION_POLICY_TEST: Cannot find the production pure selection class.' }
    $policy = $native.Substring($start, $end - $start)
    $fixture = [IO.File]::ReadAllText((Join-Path $directory 'windows-selection-policy-fixture.cs'))
    $marker = 'public static class WindowsSelectionPolicyFixture {'
    if (-not $fixture.Contains($marker)) { throw 'SELECTION_POLICY_TEST: Cannot find the fixture entry point.' }
    $source = 'using System.Text;' + [Environment]::NewLine + $fixture.Replace($marker, $policy + [Environment]::NewLine + $marker)
    Add-Type -TypeDefinition $source -Language CSharp
    $result = [WindowsSelectionPolicyFixture]::Main()
    if ($result -ne 0) { throw 'SELECTION_POLICY_TEST: Production selection-policy assertions failed.' }
    exit 0
} catch {
    [Console]::Out.WriteLine((@{ ok = $false; error = $_.Exception.Message; windowsInteractiveTested = $false; clipboardAccessed = $false; inputSent = $false; screenCaptured = $false } | ConvertTo-Json -Compress))
    exit 1
}
