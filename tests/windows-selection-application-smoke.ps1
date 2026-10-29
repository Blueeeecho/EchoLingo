# Exact packaged Tauri Alt+D, generated controls and loopback translation only.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath,[switch]$IsolatedTestSession,
    [string]$ExpectedApplicationSha256='86373b0c771b6644b66b6dc0f8a8c50295b6b7da50a8b1227953d11e78b1cf03',
    [long]$ExpectedApplicationBytes=5784064,
    [string]$ExpectedApplicationVersion='')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
        -not [Environment]::UserInteractive) { throw 'ISOLATION_REQUIRED: Unlocked ephemeral GitHub-hosted Windows desktop only.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'STA_REQUIRED: Run Windows PowerShell -NoProfile -STA.' }
    if ($ExpectedApplicationSha256 -notmatch '\A[0-9a-fA-F]{64}\z' -or $ExpectedApplicationBytes -le 0) { throw 'EXPECTED_IDENTITY_REQUIRED: Supply a 64-hex SHA256 and positive exact byte length.' }
    $expectedCustom = $PSBoundParameters.ContainsKey('ExpectedApplicationSha256') -or $PSBoundParameters.ContainsKey('ExpectedApplicationBytes')
    $ExpectedApplicationSha256 = $ExpectedApplicationSha256.ToLowerInvariant()
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    $bytes = [IO.File]::ReadAllBytes($ApplicationPath)
    $digest = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($digest.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() } finally { $digest.Dispose() }
    if ($bytes.LongLength -ne $ExpectedApplicationBytes -or $hash -ne $ExpectedApplicationSha256) { throw 'EXACT_APPLICATION_REQUIRED: Actual file differs from the expected stage identity.' }
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions,System.Management,UIAutomationClient,UIAutomationTypes,WindowsBase
    $references = @([Windows.Forms.Form].Assembly.Location,[Drawing.Bitmap].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[Management.ManagementObject].Assembly.Location,[Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location,[Windows.DependencyObject].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-selection-application-fixture.cs'))) -ReferencedAssemblies $references
    $expectedVersion = $ExpectedApplicationVersion
    if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
        # No custom identity means the pinned historical default above; current
        # builds supply their identity and use checked source metadata instead.
        $expectedVersion = if ($expectedCustom) { [string]((Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\package.json') | ConvertFrom-Json).version) } else { '0.1.0' }
    }
    if ($expectedVersion -notmatch '\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z' -or $expectedVersion.Length -gt 128) { throw 'EXPECTED_VERSION_REQUIRED: package.json must contain the checked source version.' }
    $result = [WindowsSelectionApplicationFixture]::Run($ApplicationPath, $expectedVersion)
    $result['applicationSha256'] = $hash
    $result['applicationBytes'] = $bytes.LongLength
    $result['expectedApplicationSha256'] = $ExpectedApplicationSha256
    $result['expectedApplicationBytes'] = $ExpectedApplicationBytes
    $result['expectedIdentityProvenance'] = if ($expectedCustom) { 'Caller-supplied expected source-build stage identity; invoking workflow must independently verify build/source provenance.' } else { 'Historical exact 4cf37d8 stage from run40529706953; no fixture rebuild.' }
    $result['powerShellVersion'] = $PSVersionTable.PSVersion.ToString()
    $result | ConvertTo-Json -Depth 16 -Compress
    if (-not $result['ok']) { exit 1 }
} catch { [ordered]@{ok=$false;error=$_.Exception.Message;actualApplicationTested=$false;userContentRead=$false;translationBackend='loopback-mock'} | ConvertTo-Json -Compress; exit 1 }
