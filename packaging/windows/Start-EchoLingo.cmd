@echo off
setlocal DisableDelayedExpansion
rem No policy or registry changes: this command only reads runtime registration.
set "ECHOLINGO_UNPACK_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; $id='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'; $keys=@(('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\'+$id),('HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\'+$id),('HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\'+$id)); $found=$false; foreach($key in $keys){ $pv=(Get-ItemProperty -LiteralPath $key -Name pv -ErrorAction SilentlyContinue).pv; $v=$null; if([version]::TryParse([string]$pv,[ref]$v) -and $v -gt [version]'0.0.0.0'){$found=$true} }; if(-not $found){ Write-Host 'Microsoft Edge WebView2 Runtime is missing.'; Write-Host 'Install the Evergreen Runtime from the official Microsoft page:'; Write-Host 'https://developer.microsoft.com/microsoft-edge/webview2/'; Write-Host 'For an offline PC, transfer the x64 Evergreen Standalone Installer.'; Write-Host 'Then run this launcher again. See README-Windows.txt for Chinese instructions.'; exit 2 }; $app=Join-Path $env:ECHOLINGO_UNPACK_ROOT 'echolingo.exe'; if(-not (Test-Path -LiteralPath $app -PathType Leaf)){Write-Host 'Extract the entire ZIP first. echolingo.exe is missing.'; exit 3}; Start-Process -FilePath $app -WorkingDirectory $env:ECHOLINGO_UNPACK_ROOT"
if errorlevel 1 (
  echo.
  echo EchoLingo did not start. Read README-Windows.txt for help.
  pause
  exit /b 1
)
endlocal
