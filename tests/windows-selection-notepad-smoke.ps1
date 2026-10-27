# Real classic Notepad -> actual packaged Tauri Alt+D. Generated content only.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath,[switch]$IsolatedTestSession)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
        -not [Environment]::UserInteractive) { throw 'ISOLATION_REQUIRED: Unlocked ephemeral GitHub-hosted Windows desktop only.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'STA_REQUIRED: Run Windows PowerShell -NoProfile -STA.' }
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    $bytes = [IO.File]::ReadAllBytes($ApplicationPath)
    $digest = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($digest.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() } finally { $digest.Dispose() }
    if ($bytes.Length -ne 5784064 -or $hash -ne '86373b0c771b6644b66b6dc0f8a8c50295b6b7da50a8b1227953d11e78b1cf03') { throw 'EXACT_APPLICATION_REQUIRED: This fixture targets the unchanged 4cf37d8 stage executable.' }
    Add-Type -AssemblyName System.Windows.Forms,System.Web.Extensions,UIAutomationClient,UIAutomationTypes,WindowsBase
    $references = @([Windows.Forms.Form].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location,[Windows.DependencyObject].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-selection-notepad-fixture.cs'))) -ReferencedAssemblies $references
    $result = [WindowsSelectionNotepadFixture]::Run($ApplicationPath)
    $result['applicationSha256'] = $hash
    $result['powerShellVersion'] = $PSVersionTable.PSVersion.ToString()
    $result | ConvertTo-Json -Depth 16 -Compress
    if ($result['inconclusive']) { exit 2 }
    if (-not $result['ok']) { exit 1 }
} catch { [ordered]@{ok=$false;inconclusive=$false;error=$_.Exception.Message;actualApplicationTested=$false;userContentRead=$false;translationBackend='loopback-mock'} | ConvertTo-Json -Compress; exit 1 }
