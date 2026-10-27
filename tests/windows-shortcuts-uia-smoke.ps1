# Actual settings UIA + native shortcut registration. Generated ephemeral data only.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ApplicationPath,
    [switch]$IsolatedTestSession,
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedApplicationSha256 = '3e767c7046adcf8ef6b137f5811b0966efc8613f671f1f3d575f185b3c074539',
    [ValidateRange(1,2147483647)][long]$ExpectedApplicationBytes = 5825536
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
        -not [Environment]::UserInteractive) { throw 'ISOLATION_REQUIRED: Unlocked ephemeral GitHub-hosted Windows desktop only.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'STA_REQUIRED: Run Windows PowerShell -NoProfile -STA.' }
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    $file = Get-Item -LiteralPath $ApplicationPath
    $hash = (Get-FileHash -LiteralPath $ApplicationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $ExpectedApplicationBytes -or $hash -ne $ExpectedApplicationSha256.ToLowerInvariant()) { throw 'EXACT_APPLICATION_REQUIRED: Caller-proven candidate size/hash mismatch.' }
    Add-Type -AssemblyName System.Web.Extensions,UIAutomationClient,UIAutomationTypes,WindowsBase
    $references = @([Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,
        [Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location,
        [Windows.DependencyObject].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-shortcuts-uia-fixture.cs'))) -ReferencedAssemblies $references
    $result = [EchoLingoShortcutsUiaFixture]::Run($ApplicationPath)
    $result['applicationSha256'] = $hash
    $result['applicationBytes'] = $file.Length
    $result['powerShellVersion'] = $PSVersionTable.PSVersion.ToString()
    $result | ConvertTo-Json -Depth 16 -Compress
    if (-not $result['ok']) { exit 1 }
} catch {
    [ordered]@{ok=$false;stage='fixture-entry';error=$_.Exception.Message;actualSettingsUiTested=$false;fakeIpcUsed=$false;userContentRead=$false} | ConvertTo-Json -Compress
    exit 1
}
