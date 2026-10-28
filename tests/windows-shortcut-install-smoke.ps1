# Disposable Windows account only. Owns temporary settings and hotkeys; never
# reads existing user settings, starts the WebView, or sends user input.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath, [switch]$IsolatedTestSession)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$owned = $false
$held = $false
$root = $null
$cases = [Collections.Generic.List[object]]::new()
function Require([bool]$Value, [string]$Message) { if (-not $Value) { throw "SHORTCUT_INSTALL: $Message" } }
function Probe([int]$Expected, [string]$ExpectedOutput, [string]$Name) {
    $start = [Diagnostics.ProcessStartInfo]::new($script:ApplicationPath, '--check-shortcuts-on-install')
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $before = if (Test-Path -LiteralPath $script:settings) { (Get-FileHash -LiteralPath $script:settings -Algorithm SHA256).Hash } else { '' }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync(); $errorTask = $process.StandardError.ReadToEndAsync()
        Require ($process.WaitForExit(15000)) 'Early probe did not exit without becoming a resident app.'
        $stdout = $outputTask.GetAwaiter().GetResult().Replace("`r`n", "`n")
        $stderr = $errorTask.GetAwaiter().GetResult()
        Require ($process.ExitCode -eq $Expected) "$Name returned unexpected exit code $($process.ExitCode)."
        Require ($stdout -eq $ExpectedOutput -and $stdout.Length -le 480 -and $stdout -notmatch '[^\x00-\x7f]') "$Name returned an invalid bounded ASCII protocol."
        Require ([string]::IsNullOrEmpty($stderr)) "$Name unexpectedly printed an error or private data."
        $after = if (Test-Path -LiteralPath $script:settings) { (Get-FileHash -LiteralPath $script:settings -Algorithm SHA256).Hash } else { '' }
        Require ($before -eq $after) "$Name modified settings."
        Require (@(Get-ChildItem -LiteralPath $script:root -File).Count -eq $(if ($after) { 2 } else { 1 })) "$Name created history or other files."
        $script:cases.Add(@{ name=$Name; exit=$process.ExitCode; protocol=$stdout; settingsUnchanged=$true; exited=$true })
    } finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}
function Set-Bindings([string]$Selection, [string]$Ocr) {
    @{ shortcutDefaultsVersion=1; shortcuts=@{ selection=$Selection; silentOcr=$Ocr; capture=''; ocr=''; input='' } } |
        ConvertTo-Json -Depth 4 -Compress | ForEach-Object { [IO.File]::WriteAllText($script:settings, $_, [Text.UTF8Encoding]::new($false)) }
}
try {
    Require ($IsolatedTestSession -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) 'Use an explicitly isolated Windows test account.'
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    Require (@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ApplicationPath)) -ErrorAction SilentlyContinue).Count -eq 0) 'EchoLingo already runs; no interference allowed.'
    $root = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'io.github.blueeeecho.echolingo'
    Require (-not (Test-Path -LiteralPath $root)) 'Existing application data; refuse to inspect or overwrite.'
    $null = [IO.Directory]::CreateDirectory($root); $owned = $true
    $token = [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText((Join-Path $root '.shortcut-fixture-owned'), $token)
    $settings = Join-Path $root 'settings.json'
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EchoLingoShortcutOwner {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool UnregisterHotKey(IntPtr window, int id);
}
'@
    Probe 0 "selection=Alt+D`nsilentOcr=Alt+S`n" 'fresh-install-defaults'
    Require ([EchoLingoShortcutOwner]::RegisterHotKey([IntPtr]::Zero, 17031, 1, 0x53)) 'Cannot own the fixture Alt+S conflict.'
    $held = $true
    Probe 2 "silentOcr=Alt+S`n" 'default-conflict-real-registration'
    Probe 2 "silentOcr=Alt+S`n" 'conflict-owner-not-unregistered'
    Require ([EchoLingoShortcutOwner]::UnregisterHotKey([IntPtr]::Zero, 17031)) 'Cannot release fixture Alt+S.'
    $held = $false
    Probe 0 "selection=Alt+D`nsilentOcr=Alt+S`n" 'available-after-owner-release'
    Require ([EchoLingoShortcutOwner]::RegisterHotKey([IntPtr]::Zero, 17031, 1, 0x41)) 'Cannot own the fixture compatible-input conflict.'
    $held = $true
    Probe 2 "input=Alt+A`n" 'compatible-enabled-binding-conflict-not-missed'
    Require ([EchoLingoShortcutOwner]::UnregisterHotKey([IntPtr]::Zero, 17031)) 'Cannot release compatible fixture hotkey.'
    $held = $false
    Set-Bindings 'Ctrl+Alt+Shift+F9' 'Ctrl+Alt+Shift+F10'
    Probe 0 "selection=Ctrl+Alt+Shift+F9`nsilentOcr=Ctrl+Alt+Shift+F10`n" 'existing-custom-settings'
    Require ([EchoLingoShortcutOwner]::RegisterHotKey([IntPtr]::Zero, 17031, 7, 0x79)) 'Cannot own the fixture custom OCR conflict.'
    $held = $true
    Probe 2 "silentOcr=Ctrl+Alt+Shift+F10`n" 'custom-conflict-real-registration'
    Require ([EchoLingoShortcutOwner]::UnregisterHotKey([IntPtr]::Zero, 17031)) 'Cannot release custom fixture hotkey.'
    $held = $false
    Set-Bindings '' ''
    Probe 0 "selection=`nsilentOcr=`n" 'explicitly-disabled-core-shortcuts'
    # Real early CLI validation only: not Settings UI recording or physical
    # key acceptance. The pinned Windows mapping must not turn keypad = into E.
    foreach ($action in @('selection', 'silentOcr', 'capture', 'ocr', 'input')) {
        Set-Bindings '' ''
        $unsupported = [IO.File]::ReadAllText($settings) | ConvertFrom-Json
        $unsupported.shortcuts.PSObject.Properties[$action].Value = 'Ctrl+Alt+Shift+NumpadEqual'
        [IO.File]::WriteAllText($settings, ($unsupported | ConvertTo-Json -Depth 4 -Compress), [Text.UTF8Encoding]::new($false))
        Probe 3 '' "windows-numpad-equal-$action-rejected-before-registration"
    }
    Set-Bindings 'Ctrl+Alt+Shift+E' ''
    Probe 0 "selection=Ctrl+Alt+Shift+E`nsilentOcr=`n" 'ordinary-e-supported-after-keypad-equal-rejection'
    Set-Bindings 'F12' ''
    Probe 2 "selection=F12`n" 'windows-reserved-key'
    Set-Bindings '' ''
    $legacy = [IO.File]::ReadAllText($settings) | ConvertFrom-Json
    $legacy.shortcuts.input = 'F12'
    [IO.File]::WriteAllText($settings, ($legacy | ConvertTo-Json -Depth 4 -Compress), [Text.UTF8Encoding]::new($false))
    Probe 2 "input=F12`n" 'compatible-enabled-reserved-key'
    Set-Bindings '' ''
    $invalid = [IO.File]::ReadAllText($settings) | ConvertFrom-Json
    $invalid | Add-Member -NotePropertyName providers -NotePropertyValue @(@{ id=''; name='Fixture local service'; kind='offline'; baseUrl=''; model=''; prompt=''; enabled=$true })
    [IO.File]::WriteAllText($settings, ($invalid | ConvertTo-Json -Depth 6 -Compress), [Text.UTF8Encoding]::new($false))
    Probe 3 '' 'startup-invalid-provider-cannot-report-disabled-keys-available'
    Set-Bindings 'Ctrl+Alt+Shift+F9' 'Ctrl+Alt+Shift+F10'
    $migrated = [IO.File]::ReadAllText($settings) | ConvertFrom-Json
    $migrated | Add-Member -NotePropertyName maxHistory -NotePropertyValue 200
    $migrated | Add-Member -NotePropertyName autoHideSeconds -NotePropertyValue 15
    [IO.File]::WriteAllText($settings, ($migrated | ConvertTo-Json -Depth 6 -Compress), [Text.UTF8Encoding]::new($false))
    Probe 0 "selection=Ctrl+Alt+Shift+F9`nsilentOcr=Ctrl+Alt+Shift+F10`n" 'valid-legacy-preferences-migrate-readonly-before-validation'
    [IO.File]::WriteAllText($settings, '{broken')
    Probe 3 '' 'invalid-settings-unknown-not-conflict'
    [IO.File]::WriteAllText($settings, (' ' * (2MB + 1)))
    Probe 3 '' 'oversized-settings-bounded-unknown'
    [Console]::Out.WriteLine((@{ok=$true; cases=$cases.ToArray(); actualWindowsRegistration=$true; webviewStarted=$false; credentialsAccessed=$false; scope='Isolated account real CLI/RegisterHotKey probe. Not Settings UI recording, physical keyboard, installer dialog, consumer app or Windows11 acceptance.'} | ConvertTo-Json -Depth 7 -Compress))
} catch {
    [Console]::Out.WriteLine((@{ok=$false; error=$_.Exception.Message; cases=$cases.ToArray()} | ConvertTo-Json -Depth 7 -Compress))
    exit 1
} finally {
    if ($held) { $null = [EchoLingoShortcutOwner]::UnregisterHotKey([IntPtr]::Zero, 17031) }
    if ($owned -and [IO.File]::ReadAllText((Join-Path $root '.shortcut-fixture-owned')) -eq $token) { Remove-Item -LiteralPath $root -Recurse -Force }
}
