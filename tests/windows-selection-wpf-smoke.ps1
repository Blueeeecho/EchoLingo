# Real WPF FlowDocument source -> one OS-registered Alt+D -> exact Tauri popup.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath,[switch]$IsolatedTestSession,
    [string]$ExpectedApplicationSha256='8490a973c9e4f4568b851f61524a4ef8f554d8b3a506b12dd19ba34f0dd22a4b',
    [long]$ExpectedApplicationBytes=5825536)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or -not [Environment]::UserInteractive) {throw 'EPHEMERAL_INTERACTIVE_WINDOWS_REQUIRED'}
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {throw 'STA_REQUIRED'}
    if ($ExpectedApplicationSha256 -notmatch '\A[0-9a-fA-F]{64}\z' -or $ExpectedApplicationBytes -le 0) {throw 'EXPECTED_APPLICATION_IDENTITY_REQUIRED'}
    $ApplicationPath=(Resolve-Path -LiteralPath $ApplicationPath).Path
    $bytes=[IO.File]::ReadAllBytes($ApplicationPath);$sha=[Security.Cryptography.SHA256]::Create()
    try {$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
    if ($bytes.LongLength -ne $ExpectedApplicationBytes -or $hash -ne $ExpectedApplicationSha256.ToLowerInvariant()) {throw 'EXACT_APPLICATION_IDENTITY_MISMATCH'}
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Drawing,System.Windows.Forms,System.Web.Extensions,UIAutomationClient,UIAutomationTypes
    $refs=@([Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.DependencyObject].Assembly.Location,[System.Xaml.XamlServices].Assembly.Location,[Drawing.Rectangle].Assembly.Location,[Windows.Forms.Form].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-selection-wpf-fixture.cs'))) -ReferencedAssemblies $refs
    $result=[WindowsSelectionWpfFixture]::Run($ApplicationPath)
    $result['applicationSha256']=$hash;$result['applicationBytes']=$bytes.LongLength
    $result['powerShellVersion']=$PSVersionTable.PSVersion.ToString()
    $result | ConvertTo-Json -Depth 18 -Compress
    if (-not $result['ok']) {exit 1}
} catch { [ordered]@{ok=$false;error=$_.Exception.Message;actualApplicationTested=$false;generatedWpfSource=true;thirdPartyApplicationTested=$false;userContentRead=$false} | ConvertTo-Json -Compress;exit 1 }
