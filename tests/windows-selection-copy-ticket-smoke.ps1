# Pure regression against exact production copy ticket/policy; no Windows input.
[CmdletBinding()]
param([string]$HelperPath = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
try {
    if ([string]::IsNullOrWhiteSpace($HelperPath)) { $HelperPath = Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1' }
    $native = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $HelperPath).Path)
    $ticketStart = $native.IndexOf('public sealed class SelectionCopyTicket {', [StringComparison]::Ordinal)
    $ticketEnd = $native.IndexOf('// Created only immediately before the single clipboard fallback injection.', [StringComparison]::Ordinal)
    $policyStart = $native.IndexOf('public static class SelectionCopyPolicy {', [StringComparison]::Ordinal)
    $policyEnd = $native.IndexOf('public static class EchoLingoNative {', [StringComparison]::Ordinal)
    if ($ticketStart -lt 0 -or $ticketEnd -le $ticketStart -or $policyStart -lt 0 -or $policyEnd -le $policyStart) {
        throw 'SELECTION_COPY_TICKET_TEST: Exact production classes are unavailable.'
    }
    $fixture = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-selection-copy-ticket-fixture.cs'))
    $marker = 'public static class WindowsSelectionCopyTicketFixture {'
    $classes = $native.Substring($ticketStart, $ticketEnd - $ticketStart) + [Environment]::NewLine + $native.Substring($policyStart, $policyEnd - $policyStart)
    if (-not $fixture.Contains($marker)) { throw 'SELECTION_COPY_TICKET_TEST: Fixture entry point is unavailable.' }
    Add-Type -TypeDefinition $fixture.Replace($marker, $classes + [Environment]::NewLine + $marker) -Language CSharp
    if ([WindowsSelectionCopyTicketFixture]::Main() -ne 0) { throw 'SELECTION_COPY_TICKET_TEST: Assertions failed.' }
    exit 0
} catch {
    [Console]::Out.WriteLine((@{ ok = $false; error = $_.Exception.Message; nativeHooksInstalled = $false; inputSent = $false; clipboardAccessed = $false } | ConvertTo-Json -Compress))
    exit 1
}
