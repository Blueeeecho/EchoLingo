EchoLingo Windows x64 免安装版 / Unpack-and-run edition

1. 完整解压 ZIP 到一个文件夹，不要在压缩包预览中运行，也不要单独移动 exe。
2. 双击 Start-EchoLingo.cmd。它只检查 WebView2 并打开 echolingo.exe，不下载或安装任何东西。
   已安装 WebView2 时，也可以直接双击 echolingo.exe。
3. 应用启动后驻留系统托盘。Alt+D 打开翻译，Alt+S 识字；再次打开 exe 可显示设置。
   使用前先从托盘退出安装版或旧版，避免两个版本共用同一配置。

运行要求
- Windows 10 1809+ / Windows 11，x64。系统 WebView2 Runtime 必须可用。
- 电脑有 Edge 浏览器并不代表一定有 WebView2 Runtime。本 ZIP 不捆绑浏览器运行时。
- 若启动器提示缺少 WebView2，请从 Microsoft 官方页面安装 Evergreen Runtime：
  https://developer.microsoft.com/microsoft-edge/webview2/
  完全离线的电脑需先在联网电脑下载 x64 Evergreen Standalone Installer，转移后安装。
  初次安装缺少的系统运行时仍是安装操作；这个版本仅免去 EchoLingo 本身的安装。
- Windows 本机 OCR 仍需要对应系统 OCR 语言包。
- 若组织策略限制脚本，可在 WebView2 已就绪后直接运行 exe；不要关闭组织安全策略。
- 此测试版未商业签名。请核对来源和 SHA-256，不要关闭杀毒软件或绕过安全策略。

数据与升级
- 本版不是“所有数据跟随 U 盘”的完整便携模式。
- 设置和历史继续保存在 %APPDATA%\io.github.blueeeecho.echolingo。
- WebView 缓存等继续位于当前 Windows 用户的 AppData；密钥留在 Windows 凭据管理器。
- 不会将密钥导出到解压目录，也不会上传设置或历史。ZIP 中不包含任何用户配置。
- 安装版和免安装版使用相同的本机配置。换电脑时不会携带密钥或历史。
- 更新时先完整退出应用，再把新 ZIP 解压到新文件夹。不要混用不同版本的资源。
- 删除解压目录只删除程序，不清除 AppData 中的设置、历史或系统凭据。

离线资源
offline-translation 文件夹包含真实中英双向模型、引擎及原始许可证，必须与 exe 同级。
应用只把你主动配置的云端服务请求发给相应服务；本机离线翻译不需要 API 密钥。
分发本 ZIP 时须同时提供 EchoLingo-offline-engine-source.zip；参见 offline-translation/licenses/SOURCE-OFFER.md。

English
Extract the whole ZIP, then run Start-EchoLingo.cmd (or echolingo.exe if WebView2 is ready).
The launcher checks the registered Microsoft Edge WebView2 Evergreen Runtime. It does not install,
download or modify system policy. Edge browser alone is not proof that the runtime exists.
For offline machines, obtain Microsoft's x64 Evergreen Standalone Installer beforehand.
Quit the installed/old copy first. EchoLingo runs in the tray; relaunch to open Settings.
Settings/history remain in the current user's AppData and secrets in Windows Credential Manager.
This is not a data-portable mode. Removing the folder does not delete user data or credentials.
Keep offline-translation next to the exe. Provide the accompanying engine source ZIP when redistributing.
