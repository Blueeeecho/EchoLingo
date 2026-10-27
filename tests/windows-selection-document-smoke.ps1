# Fresh disposable Windows account only; clipboard contents are generated here.
[CmdletBinding()]
param([string]$HelperPath='', [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,[switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if(-not $IsolatedTestSession -and -not $env:GITHUB_ACTIONS){throw 'ISOLATION_REQUIRED'}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive){throw 'INTERACTIVE_WINDOWS_REQUIRED'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'STA_REQUIRED'}
    if(-not $HelperPath){$HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1'}
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions,UIAutomationClient,UIAutomationTypes,UIAutomationProvider,WindowsBase
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-selection-document-fixture.cs'))
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([System.Windows.Forms.Form].Assembly.Location,[System.Drawing.Bitmap].Assembly.Location,[System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[System.Windows.Automation.AutomationElement].Assembly.Location,[System.Windows.Automation.ControlType].Assembly.Location,[System.Windows.Automation.Provider.IRawElementProviderSimple].Assembly.Location,[System.Windows.Rect].Assembly.Location)
    $result=[WindowsSelectionDocumentFixture]::Run($HelperPath,$NativeAssemblyPath)
    [Console]::Out.WriteLine(($result|ConvertTo-Json -Depth 12 -Compress))
    if(-not $result.ok){exit 1}
}catch{[Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message;realBrowserTested=$false;userContentRead=$false}|ConvertTo-Json -Compress));exit 1}
