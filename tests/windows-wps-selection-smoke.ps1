# Installs a fixed, vendor-hosted WPS only on a disposable hosted Windows runner.
# Never run this on a developer's desktop. WPS binaries are not build artifacts.
# Manifest: microsoft/winget-pkgs@b0fe77c399ea82726dba194fe427fab45d3dd230,
# manifests/k/Kingsoft/WPSOffice/CN/12.1.0.29161/Kingsoft.WPSOffice.CN.installer.yaml.
# NSIS /S: microsoft/winget-cli@5d302e449b63ca1534bf4b7c871f048ad07d5dca,
# src/AppInstallerCommonCore/Manifest/ManifestCommon.cpp, GetDefaultKnownSwitches.
[CmdletBinding()]
param([string]$HelperPath='', [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory, [switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$stage='isolation'
$temporary=$null
$result=[ordered]@{ok=$false;actualWpsTested=$false;registeredShortcutTested=$false;physicalOwnerWindowsTested=$false;
    generatedDocumentOnly=$true;userContentRead=$false;vendorInstallerVersion='12.1.0.29161';
    installerExpectedSha256='d5a7d632411c73962a2e1ee8d5545fe125f414ad845f8de7f5dc393c4e10f391';
    manifestCommit='b0fe77c399ea82726dba194fe427fab45d3dd230'}
try {
    if(-not $IsolatedTestSession -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
       [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive){throw 'ISOLATED_INTERACTIVE_GITHUB_WINDOWS_REQUIRED'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'STA_REQUIRED'}
    if(-not $HelperPath){$HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1'}
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    if(Test-Path -LiteralPath $OutputDirectory){throw 'NEW_OUTPUT_DIRECTORY_REQUIRED'}
    $directory=[IO.Directory]::CreateDirectory($OutputDirectory).FullName
    $result['helperSha256']=(Get-FileHash -LiteralPath $HelperPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $result['nativeAssemblySha256']=(Get-FileHash -LiteralPath $NativeAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    # Refuse an existing office session/install rather than borrowing its files.
    if(@(Get-Process -Name wps,et,wpp,wpspdf,wpsoffice -ErrorAction SilentlyContinue).Count -ne 0){throw 'EXISTING_WPS_SESSION_REFUSED'}
    $roots=@((Join-Path $env:LOCALAPPDATA 'Kingsoft\WPS Office'),(Join-Path $env:ProgramFiles 'Kingsoft\WPS Office'))
    if(${env:ProgramFiles(x86)}){$roots+=Join-Path ${env:ProgramFiles(x86)} 'Kingsoft\WPS Office'}
    $roots=@($roots|Select-Object -Unique)
    foreach($root in $roots){if(Test-Path -LiteralPath $root){throw 'EXISTING_WPS_INSTALL_REFUSED'}}
    $temporary=[IO.Directory]::CreateDirectory((Join-Path $env:RUNNER_TEMP ('echolingo-wps-'+[Guid]::NewGuid().ToString('N')))).FullName
    $installer=Join-Path $temporary 'WPS_Setup_29161.exe'
    $stage='vendor-download'
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri 'https://official-package.wpscdn.cn/wps/download/WPS_Setup_29161.exe' -OutFile $installer -TimeoutSec 180
    $actual=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    $result['installerActualSha256']=$actual
    if($actual -ne $result.installerExpectedSha256){throw 'VENDOR_INSTALLER_HASH_MISMATCH'}
    $result['installerHashVerified']=$true
    $stage='vendor-install'
    $started=[DateTime]::UtcNow
    # /S is winget-cli's NSIS silent switch; -agreelicense is the fixed manifest's
    # explicit custom switch. Do not treat manifest success-code 1223 as success.
    $start=[Diagnostics.ProcessStartInfo]::new($installer,'/S -agreelicense')
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $install=[Diagnostics.Process]::Start($start)
    # Drain vendor output without serializing its text or environment paths.
    $discardOutput=$install.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
    $discardError=$install.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
    try {
        if(-not $install.WaitForExit(180000)){
            $install.Kill()
            [void]$install.WaitForExit(5000)
            throw 'VENDOR_INSTALLER_DEADLINE'
        }
        $result['installerExitCode']=$install.ExitCode
        if($install.ExitCode -ne 0){throw 'VENDOR_INSTALLER_NONZERO_EXIT'}
    } finally {$install.Dispose()}
    $stage='installed-binary'
    # Search only the fresh known product roots. Never read registry command
    # strings, document history, user profiles or unrelated process titles.
    $executables=@(foreach($root in $roots){if(Test-Path -LiteralPath $root){Get-ChildItem -LiteralPath $root -Filter wps.exe -File -Recurse -ErrorAction Stop}})
    if($executables.Count -ne 1){throw 'UNIQUE_INSTALLED_WPS_BINARY_REQUIRED'}
    $wps=$executables[0].FullName
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($wps)
    $numericVersion='{0}.{1}.{2}.{3}' -f $version.FileMajorPart,$version.FileMinorPart,$version.FileBuildPart,$version.FilePrivatePart
    $result['wpsFileVersion']=$numericVersion
    if($numericVersion -ne '12.1.0.29161'){throw 'INSTALLED_WPS_VERSION_MISMATCH'}
    $result['wpsExecutableSha256']=(Get-FileHash -LiteralPath $wps -Algorithm SHA256).Hash.ToLowerInvariant()
    $stage='compile-fixture'
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions
    Add-Type -Path (Join-Path $PSScriptRoot 'windows-wps-selection-fixture.cs') -ReferencedAssemblies @(
        [Windows.Forms.Form].Assembly.Location,[Drawing.Bitmap].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    $stage='actual-wps-document'
    $native=[WindowsWpsSelectionFixture]::Run($wps,$HelperPath,$NativeAssemblyPath,$temporary,$started.Ticks)
    foreach($entry in $native.GetEnumerator()){$result[$entry.Key]=$entry.Value}
    if((Get-FileHash -LiteralPath $HelperPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $result.helperSha256 -or
       (Get-FileHash -LiteralPath $NativeAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $result.nativeAssemblySha256 -or
       (Get-FileHash -LiteralPath $wps -Algorithm SHA256).Hash.ToLowerInvariant() -ne $result.wpsExecutableSha256){
        $result['ok']=$false
        $result['failureCategory']='PINNED_INPUT_CHANGED_DURING_TEST'
    }
} catch {
    $result['ok']=$false
    $result['failedStage']=$stage
    $message=$_.Exception.Message
    $result['failureCategory']=if($message -cmatch '^[A-Z][A-Z0-9_]{0,95}$'){$message}else{'FIXTURE_OR_VENDOR_SETUP_EXCEPTION'}
    $result['exceptionType']=$_.Exception.GetType().Name
} finally {
    if($temporary -and (Test-Path -LiteralPath $temporary)){
        try{Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction Stop;$result['ownedTemporaryFilesRemoved']=$true}
        catch{$result['ownedTemporaryFilesRemoved']=$false;$result['ok']=$false}
    }
}
if($directory){[IO.File]::WriteAllText((Join-Path $directory 'wps-selection-report.json'),($result|ConvertTo-Json -Depth 12 -Compress),[Text.UTF8Encoding]::new($false))}
$result|ConvertTo-Json -Depth 12 -Compress
if(-not $result.ok){exit 1}
