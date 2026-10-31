# Independent ephemeral Windows serialization diagnosis. No browser or key input.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$NativeAssemblyPath,
      [Parameter(Mandatory=$true)][string]$ExpectedNativeSha256,
      [string]$OutputPath='', [switch]$Child)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
       [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive -or
       $PSVersionTable.PSVersion.Major -ne 5 -or [Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw 'FIXTURE_HOST'}
    if($ExpectedNativeSha256 -notmatch '\A[0-9a-f]{64}\z'){throw 'FIXTURE_IDENTITY'}
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions,UIAutomationClient,UIAutomationTypes,WindowsBase
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-clipboard-snapshot-smoke.cs'))
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([Windows.Forms.Form].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    if($Child){$result=[ClipboardSnapshotSmoke]::Child($NativeAssemblyPath,$ExpectedNativeSha256)}
    else{$result=[ClipboardSnapshotSmoke]::Parent($PSCommandPath,$NativeAssemblyPath,$ExpectedNativeSha256)}
    $json=$result|ConvertTo-Json -Depth 12 -Compress
    if(-not $Child -and $OutputPath){
        # CreateNew: do not overwrite an unrelated artifact or follow an existing file.
        $destination=[IO.Path]::GetFullPath($OutputPath)
        $directory=[IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($destination))
        while($null -ne $directory){if(-not $directory.Exists -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'FIXTURE_OUTPUT_BOUNDARY'};$directory=$directory.Parent}
        $stream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($json);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }
    [Console]::Out.WriteLine($json)
    if($result.ok -ne 1){exit 1}
}catch{
    # Never emit exception messages, paths, fixture text, or nonce values.
    [Console]::Out.WriteLine('{"ok":0,"startupOrProtocolFailure":1}')
    exit 1
}
