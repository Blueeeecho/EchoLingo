# Private stdin/stdout bridge for the fresh-profile Chromium selection fixture.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$HelperPath,[Parameter(Mandatory=$true)][string]$NativeAssemblyPath,[Parameter(Mandatory=$true)][string]$BrowserExecutable)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive){throw 'EPHEMERAL_INTERACTIVE_WINDOWS_REQUIRED'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'STA_REQUIRED'}
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    $BrowserExecutable=(Resolve-Path -LiteralPath $BrowserExecutable).Path
    Add-Type -AssemblyName System.Windows.Forms,System.Web.Extensions,UIAutomationClient,UIAutomationTypes,WindowsBase
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-browser-selection-bridge.cs'))
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([Windows.Forms.Form].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location,[Windows.DependencyObject].Assembly.Location)
    [WindowsBrowserSelectionBridge]::Run($HelperPath,$NativeAssemblyPath,$BrowserExecutable)
}catch{$reason=$_.Exception;while($null -ne $reason.InnerException){$reason=$reason.InnerException};[Console]::Out.WriteLine((@{ok=$false;bridgeStartupFailure=$true;error=$reason.Message;errorType=$reason.GetType().Name}|ConvertTo-Json -Compress));exit 1}
