; Probe through the installed application's early CLI path: no WebView,
; credential reads, settings writes, or resident process. RegisterHotKey is a
; point-in-time check; normal startup/save still handles later conflicts.
!macro NSIS_HOOK_POSTINSTALL
  Push $R0
  Push $R1
  nsExec::ExecToStack /TIMEOUT=15000 '"$INSTDIR\${MAINBINARYNAME}.exe" --check-shortcuts-on-install'
  Pop $R0
  Pop $R1
  DetailPrint "EchoLingo shortcut check: $R0 $R1"
  ; Never launch the app or show dialogs in unattended/passive installation.
  ${IfNot} ${Silent}
  ${AndIf} $PassiveMode != 1
    ${If} $R0 == "2"
      ${If} $LANGUAGE == 2052
        MessageBox MB_ICONEXCLAMATION|MB_YESNO "以下快捷键已被占用或被系统保留：$\r$\n$R1$\r$\n$\r$\n是否现在打开设置，更改快捷键？" /SD IDNO IDNO +2
        ExecShell "open" "$INSTDIR\${MAINBINARYNAME}.exe" "--configure-shortcuts"
      ${Else}
        MessageBox MB_ICONEXCLAMATION|MB_YESNO "These shortcuts are unavailable (in use or reserved by Windows):$\r$\n$R1$\r$\n$\r$\nOpen settings to change them now?" /SD IDNO IDNO +2
        ExecShell "open" "$INSTDIR\${MAINBINARYNAME}.exe" "--configure-shortcuts"
      ${EndIf}
    ${ElseIf} $R0 != "0"
      ${If} $LANGUAGE == 2052
        MessageBox MB_ICONEXCLAMATION|MB_YESNO "本次无法完成快捷键检查。请先关闭正在运行的 EchoLingo；设置损坏或系统拒绝检查也会导致此情况。$\r$\n$\r$\n是否现在打开快捷键设置？" /SD IDNO IDNO +2
        ExecShell "open" "$INSTDIR\${MAINBINARYNAME}.exe" "--configure-shortcuts"
      ${Else}
        MessageBox MB_ICONEXCLAMATION|MB_YESNO "Shortcut availability could not be checked. Close any running EchoLingo first; invalid settings or denied system access can also prevent a check.$\r$\n$\r$\nOpen shortcut settings now?" /SD IDNO IDNO +2
        ExecShell "open" "$INSTDIR\${MAINBINARYNAME}.exe" "--configure-shortcuts"
      ${EndIf}
    ${EndIf}
  ${EndIf}
  Pop $R1
  Pop $R0
!macroend
