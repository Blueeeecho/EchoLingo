# Generated-data same-process clipboard race; only a fresh hosted desktop.
[CmdletBinding()]
param([string]$HelperPath='', [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,[switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted'){throw 'FRESH_GITHUB_HOSTED_DESKTOP_REQUIRED'}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive){throw 'INTERACTIVE_WINDOWS_REQUIRED'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'STA_REQUIRED'}
    if(-not $HelperPath){$HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1'}
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions,UIAutomationClient,UIAutomationTypes,UIAutomationProvider,WindowsBase
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-selection-clipboard-race.cs'))
    $references=@([System.Windows.Forms.Form].Assembly.Location,[System.Drawing.Bitmap].Assembly.Location,[System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[System.Windows.Automation.AutomationElement].Assembly.Location,[System.Windows.Automation.ControlType].Assembly.Location,[System.Windows.Automation.Provider.IRawElementProviderSimple].Assembly.Location,[System.Windows.Automation.Provider.IRawElementProviderFragmentRoot].Assembly.Location,[System.Windows.Rect].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    $result=[WindowsSelectionClipboardRace]::Run($HelperPath,$NativeAssemblyPath)
    $result['helperSha256']=(Get-FileHash -LiteralPath $HelperPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $result['nativeAssemblySha256']=(Get-FileHash -LiteralPath $NativeAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [Console]::Out.WriteLine(($result|ConvertTo-Json -Depth 12 -Compress))
    if(-not $result.ok){exit 1}
}catch{[Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message;actualApplicationTested=$false;generatedDataOnly=$true}|ConvertTo-Json -Compress));exit 1}
