# Private native bridge for one fresh-browser, real local-OCR visibility case.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BrowserExecutable,
    [Parameter(Mandatory=$true)][string]$ApplicationPath,
    [Parameter(Mandatory=$true)][string]$MockBaseUrl,
    [Parameter(Mandatory=$true)][string]$ProviderId,
    [string]$ExpectedApplicationSha256='8490a973c9e4f4568b851f61524a4ef8f554d8b3a506b12dd19ba34f0dd22a4b',
    [long]$ExpectedApplicationBytes=5825536, [string]$NativeCapturePath='', [switch]$LegacyCapture)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive){throw 'EPHEMERAL_INTERACTIVE_WINDOWS_REQUIRED'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'STA_REQUIRED'}
    if($ExpectedApplicationSha256 -notmatch '\A[0-9a-f]{64}\z' -or $ExpectedApplicationBytes -le 0){throw 'EXPECTED_APPLICATION_IDENTITY_REQUIRED'}
    $ApplicationPath=(Resolve-Path -LiteralPath $ApplicationPath).Path
    if((Get-Item -LiteralPath $ApplicationPath).Length -ne $ExpectedApplicationBytes -or (Get-FileHash -LiteralPath $ApplicationPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedApplicationSha256){throw 'EXACT_APPLICATION_IDENTITY_MISMATCH'}
    if(-not $LegacyCapture){$NativeCapturePath=(Resolve-Path -LiteralPath $NativeCapturePath).Path}
    $BrowserExecutable=(Resolve-Path -LiteralPath $BrowserExecutable).Path
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions,UIAutomationClient,UIAutomationTypes,WindowsBase
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-browser-ocr-visibility-bridge.cs'))
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([Drawing.Bitmap].Assembly.Location,[Windows.Forms.Form].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location,[Windows.DependencyObject].Assembly.Location)
    [WindowsBrowserOcrVisibilityBridge]::Run($BrowserExecutable,$ApplicationPath,$MockBaseUrl,$ProviderId,$ExpectedApplicationSha256,$ExpectedApplicationBytes,$NativeCapturePath,[bool]$LegacyCapture)
}catch{
    $reason=$_.Exception;while($null -ne $reason.InnerException){$reason=$reason.InnerException}
    [Console]::Out.WriteLine((@{ok=$false;bridgeStartupFailure=$true;setupInconclusive=$true;failureClassification='roi-preparation-inconclusive';error=$reason.Message;errorType=$reason.GetType().Name}|ConvertTo-Json -Compress));exit 1
}
