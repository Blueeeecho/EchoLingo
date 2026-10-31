# Only a fresh, isolated GitHub-hosted Windows desktop with an empty clipboard.
# The fixture never reads, overwrites, or restores a pre-existing clipboard.
[CmdletBinding()]
param([string]$HelperPath='', [switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$temporary=''
try {
    if(-not $IsolatedTestSession -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
       [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive -or
       $PSVersionTable.PSVersion.Major -ne 5 -or [Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'ISOLATED_FRAMEWORK_HOST_REQUIRED'}
    if(-not $HelperPath){$HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1'}
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('echolingo-clipboard-marker-'+[Guid]::NewGuid().ToString('N'))
    if(Test-Path -LiteralPath $temporary){throw 'NEW_TEMPORARY_DIRECTORY_REQUIRED'}
    $null=[IO.Directory]::CreateDirectory($temporary)
    $assembly=Join-Path $temporary 'EchoLingo.MarkerFixture.Native.dll'
    $builder=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\scripts\build-windows-native-helper.ps1')).Path
    $buildOutput=@(& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $builder -HelperPath $HelperPath -OutputPath $assembly 2>&1)
    if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($assembly)){throw 'EXACT_NATIVE_BUILD_FAILED'}
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes,WindowsBase
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-clipboard-marker-fixture.cs'))
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([Windows.Forms.Form].Assembly.Location,[Drawing.Bitmap].Assembly.Location) -ErrorAction Stop
    $result=[WindowsClipboardMarkerFixture]::Run($assembly)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $result['nativeAssemblySha256']=[BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($assembly))).Replace('-','').ToLowerInvariant()
        $result['helperSha256']=[BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($HelperPath))).Replace('-','').ToLowerInvariant()
    } finally {$sha.Dispose()}
    [Console]::Out.WriteLine(($result|ConvertTo-Json -Depth 8 -Compress))
    if(-not $result.ok){exit 1}
} catch {
    # No exception messages, arbitrary format names, payloads, or local paths.
    [Console]::Out.WriteLine('{"ok":false,"clipboardMarkerFixture":true,"startupOrBoundaryFailure":true,"generatedDataOnly":true}')
    exit 1
} finally {
    if($temporary -and [IO.Directory]::Exists($temporary)){Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue}
}
