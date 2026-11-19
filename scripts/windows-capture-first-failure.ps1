# One bounded diagnostic experiment on an isolated CI desktop. Never clears clipboard.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath,
      [Parameter(Mandatory=$true)][string]$NativeCapturePath,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
if (-not $env:GITHUB_ACTIONS) { throw 'ISOLATED_CI_REQUIRED' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$expected='68b71145f1d77d03311133ad15161147101720c85d8c821d7e0470d976d96c8a'
if ((Get-FileHash $ApplicationPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'IMMUTABLE_APPLICATION_MISMATCH' }
if ((Get-FileHash $NativeCapturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne '8eae7f27d6bfce1522b232b3a82cd721c957a6ff72044ee420d48df06d642326') { throw 'IMMUTABLE_CAPTURE_MISMATCH' }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ClipboardBoundary {
 [DllImport("user32.dll", SetLastError=true)] static extern bool OpenClipboard(IntPtr h);
 [DllImport("user32.dll")] static extern bool CloseClipboard();
 [DllImport("user32.dll", SetLastError=true)] static extern int CountClipboardFormats();
 [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
 [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("kernel32.dll")] static extern void SetLastError(uint e);
 public static long[] Observe(uint knownPid) {
  uint before=GetClipboardSequenceNumber(),pid=0; bool opened=OpenClipboard(IntPtr.Zero); int count=-1,error=0;
  if(opened)try {SetLastError(0);count=CountClipboardFormats();if(count==0)error=Marshal.GetLastWin32Error();GetWindowThreadProcessId(GetClipboardOwner(),out pid);}finally{CloseClipboard();}
  return new long[]{before,GetClipboardSequenceNumber(),opened?1:0,count==0&&error==0?1:0,knownPid!=0&&pid==knownPid?1:0,error};
 }
}
'@
$rows=@();$previous=$null;$knownPid=0
function Observe([string]$stage) {
 $v=[ClipboardBoundary]::Observe($script:knownPid)
 $script:rows += [ordered]@{stage=$stage;opened=($v[2] -eq 1);empty=($v[3] -eq 1);sequenceChangedDuringRead=($v[0] -ne $v[1]);sequenceChangedSinceBoundary=($null -ne $script:previous -and $script:previous -ne $v[0]);ownerMatchesKnownFixture=($v[4] -eq 1);enumerationError=$v[5]}
 $script:previous=$v[1]
 $script:rows | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'clipboard-boundaries.json') -Encoding utf8
}
Observe 'before-wpf'
$ErrorActionPreference='Continue'
$wpf=@(& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-selection-wpf-smoke.ps1 -ApplicationPath $ApplicationPath -ExpectedApplicationSha256 $expected -ExpectedApplicationBytes 8237568 -IsolatedTestSession 2>&1)
$wpfExit=$LASTEXITCODE
$wpf | Out-File (Join-Path $OutputDirectory 'wpf.log') -Encoding utf8
foreach($line in $wpf){try{$r=($line.ToString()|ConvertFrom-Json);if($r.applicationProcessId){$knownPid=[uint32]$r.applicationProcessId}}catch{}}
Observe 'after-wpf'
Observe 'before-f1'
$f1=@(& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-application-smoke.ps1 -ApplicationPath $ApplicationPath -ScreenshotEditorTests -DefaultCapture -NativeCapturePath $NativeCapturePath 2>&1)
$f1Exit=$LASTEXITCODE
$f1 | Out-File (Join-Path $OutputDirectory 'f1.log') -Encoding utf8
foreach($line in $f1){try{$r=($line.ToString()|ConvertFrom-Json);if($r.applicationProcessId){$knownPid=[uint32]$r.applicationProcessId}}catch{}}
Observe 'after-f1'
[ordered]@{wpfExit=$wpfExit;f1Exit=$f1Exit;applicationSha256=$expected;diagnosticOnly=$true;releaseAcceptance=$false;retries=0} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'result.json') -Encoding utf8
if ($wpfExit -ne 0 -or $f1Exit -ne 0) { exit 1 }
