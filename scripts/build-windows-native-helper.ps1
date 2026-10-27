# Build-time only. The application embeds this exact DLL; normal shortcuts
# load it and never invoke a C# compiler. Use Windows PowerShell 5.1 / Framework.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HelperPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'NATIVE_BUILD_HOST: Use Windows PowerShell 5.1 and the built-in .NET Framework compiler on Windows.'
    }
    $helper = (Resolve-Path -LiteralPath $HelperPath).Path
    $native = [IO.File]::ReadAllText($helper)
    $match = [regex]::Match($native, '(?ms)^    \$source = @''\r?\n(.*?)^''@\r?$')
    if (-not $match.Success) { throw 'NATIVE_BUILD_SOURCE: Cannot locate the exact native C# source.' }
    $destination = [IO.Path]::GetFullPath($OutputPath)
    $directory = [IO.Path]::GetDirectoryName($destination)
    $null = [IO.Directory]::CreateDirectory($directory)
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes, WindowsBase
    $references = @(
        [System.Windows.Forms.Form].Assembly.Location
        [System.Drawing.Bitmap].Assembly.Location
        [System.Windows.Automation.AutomationElement].Assembly.Location
        [System.Windows.Automation.AutomationPattern].Assembly.Location
        [System.Windows.DependencyObject].Assembly.Location
    ) | Select-Object -Unique
    Add-Type -TypeDefinition $match.Groups[1].Value -ReferencedAssemblies $references -OutputAssembly $destination -OutputType Library
    if (-not [IO.File]::Exists($destination) -or ([IO.FileInfo]$destination).Length -eq 0) {
        throw 'NATIVE_BUILD_OUTPUT: The compiler produced no native DLL.'
    }
    [Console]::Out.WriteLine((@{ ok = $true; backend = 'precompiled-framework-dll'; bytes = ([IO.FileInfo]$destination).Length; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() } | ConvertTo-Json -Compress))
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
