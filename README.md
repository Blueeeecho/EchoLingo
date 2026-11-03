<p align="center"><strong>中文</strong> · <a href="README.en.md">English</a></p>
<p align="center"><img src="https://blueeeecho.github.io/EchoLingo/assets/echolingo-icon.png" width="96" alt="EchoLingo · 回声译" /></p>
<h1 align="center">EchoLingo · 回声译</h1>
<p align="center"><strong>让陌生的语言，有熟悉的回声。</strong></p>
<p align="center">轻量的桌面选词翻译与无感 OCR 工具，让理解跟上思路。</p>
<p align="center"><a href="https://blueeeecho.github.io/EchoLingo/">官方网站</a> · <a href="https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.14">Windows 0.2.14 测试版</a> · <a href="https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.14">macOS 0.2.14 测试版</a> · <a href="https://github.com/Blueeeecho/EchoLingo/issues">反馈与建议</a></p>

## 下载与安装

**[推荐：Windows 0.2.14 免安装 ZIP（x64）](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.14/EchoLingo_0.2.14_windows_x64-unpack.zip)** · **[下载 macOS 0.2.14 测试版（Apple 芯片）](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.14/EchoLingo_0.2.14_macos_arm64.dmg)**

Windows ZIP 请完整解压后打开 `Start-EchoLingo.cmd`。也可选择 [Windows NSIS 安装版](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.14/EchoLingo_0.2.14_windows_x64-setup.exe)。仍需 Microsoft Edge WebView2 Runtime，启动器不自动下载或安装运行环境。免安装仅指程序文件无需安装向导，配置、历史与 WebView 数据仍保存在当前用户的 AppData，密钥仍在 Windows 凭据库中，不会随 ZIP 搬走。

Windows 适用于 Windows 10 1809+ / Windows 11；macOS 安装包适用于 Apple 芯片 Mac、macOS 12+，Apple 系统翻译需要 macOS 26+。打开回声译后，应用会驻留托盘或菜单栏；升级前先完整退出旧版。

Windows 与 macOS 现统一提供 0.2.14 测试版。翻译与 OCR 服务独立管理，免费推荐列表可折叠；默认启用 `Alt+D`、`Alt+S`，另提供独立的 `F1` 截图与本地编辑；快捷键可修改、清空或自定义。

0.2.14 改善设置页与服务管理的文字、链接和窄窗口排版，保持快捷键录制反馈可见；修复历史翻译的语言选择影响后续捕获或清空的问题，并区分请求语言与解析语言的无内容诊断。Windows 增加包含离线引擎、双向模型和许可的完整 ZIP，并修复冷启动时第二次启动请求的状态访问。

发布前执行同一提交的完整 CI 门槛、双端新构建与包结构检查；Windows 最终 ZIP 还验证解压启动、设置 WebView、第二次启动转发、双向离线翻译、内嵌捕获自检和实际设置快捷键。安装包静态检查不等同于安装后完整运行；真实应用与服务、缺少 WebView2 的机器、中文输入法、物理多屏、混合 DPI 和断网场景仍需现场验收。用户报告的现场翻译问题仍按具体复现结果判断，详见版本说明。

这是内测预发布版本，不是稳定版。Windows 未商业签名；macOS 使用 ad hoc 签名，未经 Apple 公证。系统可能提示风险或要求重新授权，请仅安装来自本仓库发布页且校验值相符的文件。

- **Windows 0.2.14**：[版本说明](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.14) · [SHA-256 校验值](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.14/SHA256SUMS.txt) · [发布清单](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.14/RELEASE-MANIFEST.json)
- **macOS 0.2.14**：[版本说明](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.14) · [SHA-256 校验值](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.14/SHA256SUMS.txt) · [发布清单](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.14/RELEASE-MANIFEST.json)

0.2.14 是测试预发布版，不使用 GitHub 的稳定版 `Latest` 标记。历史版本见[全部发布](https://github.com/Blueeeecho/EchoLingo/releases)。程序包对应 [0.2.14 标签源码](https://github.com/Blueeeecho/EchoLingo/tree/0.2.14)，不等同于默认分支源码；程序包源码与实际文件对应关系请查看发布清单。上一内测版 [0.2.13](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.13) 仍可下载。

[macOS 首次安装说明](docs/macos-install.zh-CN.md) · [源码构建](docs/build.md)

## 三个快捷动作

- **选词翻译**：在原应用中选中文字，按 `Alt+D`，原文自动填入浮窗并翻译。
- **无感 OCR**：按 `Alt+S`，用鼠标左键拖动框选，松开后自动识字、填入原文并翻译。

- **截图与原位编辑**：按 `F1`，点击选择窗口或拖动框选；在同一编辑界面再次调整范围，直接在画布上输入文字或便签；支持画笔、高亮、椭圆、编号箭头、标注移动与再编辑、局部笔画擦除，也可固定贴图对照，再复制或保存 PNG。全程本机处理，不调用 OCR 或翻译服务。

空按 `Alt+D` 可以直接输入。原文随时可编辑，`Enter` 翻译，`Shift+Enter` 换行，`Esc` 取消框选。快捷键可在设置中修改；Mac 上 Alt 对应 Option。

## 按你的习惯使用

- **安静轻量**：托盘常驻，按需唤起；翻译浮窗点击外部隐藏，钉住后保留。使用系统 WebView，无需捆绑 Chromium。
- **自由选择服务**：Windows 内置中英离线翻译，OCR 默认本机识别；也能配置自己的翻译与 OCR 服务，同时启用多个翻译服务对照结果。
- **顺手的小功能**：原文与译文支持复制、朗读，保留主题切换、历史与收藏。历史默认最近 20 条，可调整为 1–100 条。

在托盘菜单打开设置，即可配置服务、管理密钥或调整快捷键。详见[服务配置说明](docs/official-services.zh-CN.md)。想用免费云端额度提高质量、同时保留本机默认，看[免费配置指南](docs/free-setup.zh-CN.md)。额度会变，不是永久免费。

## 免费更新提示

设置中可点「检查更新」和「打开下载页」。自动检查默认关闭；开启后每天最多一次，仅向 GitHub 请求公开版本信息，不上传文字或密钥。当前内测版默认包含内测更新，可切换为仅正式版。不会自动下载或安装，也不需要购买签名或更新服务。

## 隐私与数据

本机 OCR 和离线翻译在电脑上处理；选择云端服务后，文字或图片才会发送给你指定的服务。密钥存于系统凭据库，历史保存在本机。应用无遥测，不在后台持续轮询剪贴板。[阅读隐私说明](docs/privacy.md)。

## 支持回声译

如果回声译对你有帮助，欢迎点亮右上角的 **⭐ Star**。让更多人发现这个小工具，也支持我们持续打磨。

遇到问题或有新的想法，欢迎提交 [Issue](https://github.com/Blueeeecho/EchoLingo/issues)。源码构建与测试方式见[开发说明](docs/build.md)。

## 许可与商业授权

当前项目自有代码采用 **MIT + Commons Clause v1.0**，源码可查看、学习、修改和按条款分发。详见 [LICENSE](LICENSE) 和[授权说明](LICENSING.md)。

第三方组件与模型保留各自许可。已按 MIT 发布的旧版本继续适用其原有授权。

<sub>感谢 Bob 在桌面翻译体验上的探索与启发。</sub>

## Acknowledgments

- [Linux.do](https://linux.do/)
