# Actual stage application + native pointer resizing on an ephemeral desktop.
# Reuses the visibility fixture's isolation/UIA helpers without running its cases.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath, [switch]$IsolatedTestSession)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or -not [Environment]::UserInteractive) {
        throw 'ISOLATION_REQUIRED: Unlocked ephemeral GitHub-hosted Windows desktop only.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'STA_REQUIRED: Run Windows PowerShell -NoProfile -STA.' }
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    $applicationHash = (Get-FileHash -LiteralPath $ApplicationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $applicationBytes = (Get-Item -LiteralPath $ApplicationPath).Length
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions,System.Management,UIAutomationClient,UIAutomationTypes
    $harnessText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-popup-visibility-smoke.ps1')).Replace("`r`n", "`n")
    $prefix = '$source = @' + "'`n"
    $start = $harnessText.IndexOf($prefix, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $start -ne $harnessText.LastIndexOf($prefix, [StringComparison]::Ordinal)) { throw 'HARNESS_CHANGED: Expected one C# harness source.' }
    $start += $prefix.Length
    $end = $harnessText.IndexOf("`n'@", $start, [StringComparison]::Ordinal)
    if ($end -lt 0) { throw 'HARNESS_CHANGED: C# harness terminator is missing.' }
    $harness = $harnessText.Substring($start, $end - $start)
    $declaration = 'public static class EchoLingoPopupVisibilitySmoke {'
    if (($harness.Split(@($declaration), [StringSplitOptions]::None)).Length -ne 2) { throw 'HARNESS_CHANGED: Expected the existing fixture class exactly once.' }
    $harness = $harness.Replace($declaration, 'public static partial class EchoLingoPopupVisibilitySmoke {')
    $extra = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-popup-resize-fixture.cs'))
    $references = @([Windows.Forms.Form].Assembly.Location,[Drawing.Bitmap].Assembly.Location,
        [Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[Management.ManagementObject].Assembly.Location,
        [Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition ($harness + "`n" + $extra) -ReferencedAssemblies $references -Language CSharp
    $result = [EchoLingoPopupVisibilitySmoke]::RunResize($ApplicationPath)
    $result['applicationSha256'] = $applicationHash
    $result['applicationBytes'] = $applicationBytes
    if ((Get-FileHash -LiteralPath $ApplicationPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $applicationHash -or
        (Get-Item -LiteralPath $ApplicationPath).Length -ne $applicationBytes) { $result['ok'] = $false; $result['binaryChangedDuringTest'] = $true }
    $result | ConvertTo-Json -Depth 14 -Compress
    if (-not $result['ok']) { exit 1 }
} catch {
    [ordered]@{ok=$false;stage='fixture-entry';error=$_.Exception.Message;actualWindowsResizeTested=$false;fakeIpcUsed=$false;userContentRead=$false} | ConvertTo-Json -Compress
    exit 1
}
