<p align="center"><strong>中文</strong> · <a href="README.en.md">English</a></p>
<p align="center"><img src="https://blueeeecho.github.io/EchoLingo/assets/echolingo-icon.png" width="96" alt="EchoLingo · 回声译" /></p>
<h1 align="center">EchoLingo · 回声译</h1>
<p align="center"><strong>让陌生的语言，有熟悉的回声。</strong></p>
<p align="center">轻量的桌面选词翻译与无感 OCR 工具，让理解跟上思路。</p>
<p align="center"><a href="https://blueeeecho.github.io/EchoLingo/">官方网站</a> · <a href="https://github.com/Blueeeecho/EchoLingo/releases/tag/0.1.0-beta.2.2">下载 Beta 2.2</a> · <a href="https://github.com/Blueeeecho/EchoLingo/issues">反馈与建议</a></p>

## 下载与安装

**[下载 Windows Beta 2.2（x64）](https://github.com/Blueeeecho/EchoLingo/releases/download/0.1.0-beta.2.2/EchoLingo_0.1.0-beta.2.2_windows_x64-setup.exe)** · **[下载 macOS Beta 2.2（Apple 芯片）](https://github.com/Blueeeecho/EchoLingo/releases/download/0.1.0-beta.2.2/EchoLingo_0.1.0-beta.2.2_macos_arm64.dmg)**

Windows 适用于 Windows 10 1809+ / Windows 11；macOS 安装包适用于 Apple 芯片 Mac、macOS 12+，Apple 系统翻译需要 macOS 26+。安装后打开回声译，应用会驻留托盘或菜单栏；升级前先完整退出旧版。

[Windows 版本与校验](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.1.0-beta.2.2) · [macOS 版本与校验](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.1.0-beta.2.2) · [macOS 首次安装说明](docs/macos-install.zh-CN.md) · [源码构建](docs/build.md)

## 两个快捷动作

- **选词翻译**：在原应用中选中文字，按 `Alt+D`，原文自动填入浮窗并翻译。
- **无感 OCR**：按 `Alt+S`，用鼠标左键拖动框选，松开后自动识字、填入原文并翻译。

空按 `Alt+D` 可以直接输入。原文随时可编辑，`Enter` 翻译，`Shift+Enter` 换行，`Esc` 取消框选。快捷键可在设置中修改；Mac 上 Alt 对应 Option。

## 按你的习惯使用

- **安静轻量**：托盘常驻，按需唤起；点击外部隐藏，钉住后保留。使用系统 WebView，无需捆绑 Chromium。
- **自由选择服务**：Windows 内置中英离线翻译，OCR 默认本机识别；也能配置自己的翻译与 OCR 服务。
- **顺手的小功能**：原文与译文支持复制、朗读，保留主题切换、历史与收藏。历史默认最近 20 条，可调整为 1–100 条。

在托盘菜单打开设置，即可配置服务、管理密钥或调整快捷键。详见[服务配置说明](docs/official-services.zh-CN.md)。想用免费云端额度提高质量、同时保留本机默认，看[免费配置指南](docs/free-setup.zh-CN.md)。额度会变，不是永久免费。

## 免费更新提示

设置中可点「检查更新」和「打开下载页」。自动检查默认关闭；开启后每天最多一次，仅向 GitHub 请求公开版本信息，不上传文字或密钥。0.2.0 内测版默认包含内测更新，可切换为仅正式版。不会自动下载或安装，也不需要购买签名或更新服务。

## 隐私与数据

本机 OCR 和离线翻译在电脑上处理；选择云端服务后，文字或图片才会发送给你指定的服务。密钥存于系统凭据库，历史保存在本机。应用无遥测，不在后台持续轮询剪贴板。[阅读隐私说明](docs/privacy.md)。

## 支持回声译

如果回声译对你有帮助，欢迎点亮右上角的 **⭐ Star**。让更多人发现这个小工具，也支持我们持续打磨。

遇到问题或有新的想法，欢迎提交 [Issue](https://github.com/Blueeeecho/EchoLingo/issues)。源码构建与测试方式见[开发说明](docs/build.md)。

## 许可与商业授权

当前项目自有代码采用 **MIT + Commons Clause v1.0**，源码可查看、学习、修改和按条款分发。详见 [LICENSE](LICENSE) 和[授权说明](LICENSING.md)。

第三方组件与模型保留各自许可。已按 MIT 发布的旧版本继续适用其原有授权。

<sub>感谢 Bob 在桌面翻译体验上的探索与启发。</sub>
