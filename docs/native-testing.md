# 原生功能与测试

## 平台依赖

| 平台 | 取词 | OCR | 依赖 |
|---|---|---|---|
| Windows | UI Automation 选区或复制兼容模式 | Windows.Media.Ocr | Windows PowerShell 5.1、.NET Framework、系统 OCR 语言包与 WebView2 |
| macOS | Accessibility 选区或复制回退 | Apple Vision | 应用的辅助功能和屏幕录制授权 |

macOS 原生适配静态链接到应用进程；Windows 使用 PowerShell/C# 桥接。先取得原应用选文，再显示翻译浮窗。复制回退会保存并尝试恢复原剪贴板；来源变化或无法安全恢复时应停止并提示。

截图默认在本机识别；明确选择云 OCR 后才上传选区。权限刷新和快捷键只检查权限，授权操作由用户在设置中发起。

## 可复现检查

在目标平台运行：

```sh
# macOS 原生 OCR 与私有剪贴板检查
bash tests/macos-native-self-test.sh
```

```powershell
# Windows 原生 OCR 与临时测试窗口的取词检查
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File src-tauri/native/windows.ps1 -Mode self-test
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-native-smoke.ps1
```

`tests/` 中还保留选区、复制来源、OCR 输入层、浮窗和快捷键的回归夹具。它们使用生成的测试文本，不需要真实 API 密钥。全部构建入口见[源码构建](build.md)。

## 桌面交互检查

- 在浏览器、编辑器和文档应用选中文字，按一次已配置的取词快捷键，核对原文和译文。
- 空选区时打开空白输入框，确认可以立即输入；编辑原文后重新翻译。
- OCR 左键拖选、松开识字、Esc 取消；检查普通窗口、全屏和多屏场景。
- 点击外部隐藏；固定后连续取词或 OCR，用新内容更新现有浮窗。
- 修改快捷键后核对新键生效、旧键释放及冲突提示；重启后配置应保留。
- 核对剪贴板恢复、权限提示、取消操作和窗口宽度调整。

自动构建或隔离界面测试不能证明所有目标应用、输入法和显示配置均已通过这些交互检查。
