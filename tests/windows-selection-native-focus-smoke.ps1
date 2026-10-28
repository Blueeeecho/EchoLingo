[CmdletBinding()]
param([string]$HelperPath='', [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,[switch]$ExpectCrossProcessSuccess,[switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if(-not $IsolatedTestSession -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
       [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive){throw 'ISOLATED_INTERACTIVE_GITHUB_WINDOWS_REQUIRED'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'STA_REQUIRED'}
    if(-not $HelperPath){$HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1'}
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    if(Test-Path -LiteralPath $OutputDirectory){throw 'NEW_OUTPUT_DIRECTORY_REQUIRED'}
    $directory=[IO.Directory]::CreateDirectory($OutputDirectory).FullName
    $child=Join-Path $directory 'echolingo-generated-focus-child.exe'
    $childSource=Join-Path $PSScriptRoot 'windows-selection-native-focus-child.cs'
    $compiler=Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    & $compiler /nologo /target:exe /out:$child /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $childSource
    if($LASTEXITCODE -ne 0){throw 'CHILD_FIXTURE_COMPILE_FAILED'}
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions
    Add-Type -Path @($childSource,(Join-Path $PSScriptRoot 'windows-selection-native-focus-fixture.cs')) -ReferencedAssemblies @([Windows.Forms.Form].Assembly.Location,[Drawing.Bitmap].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    $result=[WindowsSelectionNativeFocusFixture]::Run($HelperPath,$NativeAssemblyPath,$child,$ExpectCrossProcessSuccess.IsPresent)
    $result['nativeAssemblySha256']=(Get-FileHash -LiteralPath $NativeAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $result['helperSha256']=(Get-FileHash -LiteralPath $HelperPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $result | ConvertTo-Json -Depth 12 -Compress
    if(-not $result.ok){exit 1}
}catch{@{ok=$false;nativeFocusFixture=$true;error=$_.Exception.Message;actualWpsTested=$false;userContentRead=$false}|ConvertTo-Json -Compress;exit 1}
