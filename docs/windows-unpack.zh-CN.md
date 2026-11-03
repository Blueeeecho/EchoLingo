# Windows 免安装版

Windows 免安装版提供完整程序与中英离线翻译资源。完整解压后打开 `Start-EchoLingo.cmd`；WebView2 已就绪时也可以直接打开 `echolingo.exe`。应用驻留托盘，再次打开会显示设置。

安装版继续保留。此功能先通过独立构建验证；公开发布成功前，不把现有下载链接改为尚不存在的 ZIP。

## 系统要求与运行时

Windows 10 1809+ / Windows 11 x64。ZIP 不包含 WebView2 浏览器运行时。启动器按 [Microsoft 文档](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)检查当前用户与系统注册的 Evergreen Runtime，缺失时提供官方安装地址，不自动下载安装，不改安全策略。

[Microsoft WebView2 下载](https://developer.microsoft.com/microsoft-edge/webview2/)提供联网 Bootstrapper 与离线 Evergreen Standalone Installer。完全离线的电脑如果没有运行时，需要事先准备 x64 Standalone Installer。Edge 浏览器的存在不能代替运行时检查；“免安装”指 EchoLingo 本身，不表示缺少的系统组件也无需安装。OCR 仍依赖相应 Windows OCR 语言包。

## 数据不随程序携带

- 设置、历史仍使用 `%APPDATA%\io.github.blueeeecho.echolingo`，缓存和内嵌原生辅助程序仍使用当前用户的 AppData。
- 密钥仍保存在 Windows 凭据管理器，不写入 ZIP 或解压目录。
- 安装版和免安装版共享同一用户的数据和单实例标识。切换或更新前，从托盘完整退出旧版。
- 将整个程序文件夹拷贝到另一台电脑不会携带历史或密钥。删除程序文件夹也不会删除本机数据。
- 更新时解压到新文件夹，不混用不同版本的 exe 和资源。不要在 ZIP 预览中直接运行。

## 构建与最小验证

准备资源及对应源码的方式见[构建说明](build.md)。`windows-unpack.yml` 在 Windows 上构建真实 exe 和原有 NSIS 安装器，然后按 Tauri Windows 资源白名单生成 ZIP。模型、引擎、许可证位于 exe 同级的 `offline-translation`；不复制整个构建目录，也不读取或打包用户 AppData。

该构建为主程序和内嵌捕获子程序静态链接 MSVC CRT，避免仅在带 Visual Studio 的构建机上可运行。验收同时检查实际 PE 依赖，不能把构建机已安装的依赖误当作随包提供。

定向验证覆盖实际 ZIP 解压到含中文和空格的目录、文件哈希、异地工作目录启动与 WebView 就绪、双向真实模型、内嵌捕获程序自检，以及运行后程序目录无用户数据变化。它不替代完整截图、OCR、多屏或无 WebView2 的实体设备验收。

`EchoLingo-offline-engine-source.zip` 与二进制 ZIP 同时分发。`WINDOWS-ZIP-MANIFEST.json` 记录输入文件与归档哈希；`SHA256SUMS.txt` 提供核验。现有发布流程不会因该构建而自动覆盖或改写旧版本资产。
