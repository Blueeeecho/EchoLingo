<p align="center"><strong>中文</strong> · <a href="README.en.md">English</a></p>
<p align="center"><img src="https://blueeeecho.github.io/EchoLingo/assets/echolingo-icon.png" width="96" alt="EchoLingo · 回声译" /></p>
<h1 align="center">EchoLingo · 回声译</h1>
<p align="center"><strong>让陌生的语言，有熟悉的回声。</strong></p>
<p align="center">一款安静轻量的桌面划词翻译、框选 OCR 与截图工具。</p>
<p align="center">
  <a href="https://blueeeecho.github.io/EchoLingo/">官网</a> ·
  <a href="#下载与安装">下载 0.2.26</a> ·
  <a href="https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.26">更新日志</a> ·
  <a href="https://github.com/Blueeeecho/EchoLingo/issues">反馈与建议</a>
</p>

## 核心用法

只需要记住三个快捷键（macOS 上 `Alt` 对应 `Option`，均可在设置中自定义或清空）：

| 快捷键 | 功能 | 说明 |
| :--- | :--- | :--- |
| **`Alt + D`** | 划词翻译 | 选中文字后按下，浮窗自动填入原文并翻译；未选中时直接打开输入框 |
| **`Alt + S`** | 框选 OCR | 拖选屏幕任意区域，松手即识别文字并翻译 |
| **`F1`** | 截图与标注 | 点击窗口或拖选范围，支持画笔、高亮、箭头、文字便签、马赛克、裁剪和贴图，一键复制或保存 PNG |

在翻译浮窗中，原文随时可二次编辑：`Enter` 翻译，`Shift + Enter` 换行，`Esc` 取消框选或收起窗口。点击浮窗外部自动隐藏，需要对照阅读时点一下图钉即可常驻置顶。

## 为什么做 EchoLingo

- **安静、轻量**：基于 Tauri 2 与系统原生 WebView，不捆绑 Chromium；平时常驻托盘或菜单栏，用完即走。
- **离线可用，也支持多引擎对照**：默认本机 OCR（Windows 还内置了中英离线翻译），同时支持接入百度、有道、微软、DeepL、OpenAI 兼容接口或本地 Ollama，可同时开启多个服务对照译文。
- **隐私留在本地**：无遥测、不后台轮询剪贴板；API 密钥存入系统凭据库，历史记录只保存在本机。只有在你主动启用云端服务时，文字或图片才会发给你指定的服务商。
- **顺手的小功能**：支持原文/译文复制与朗读、深浅主题切换、历史记录与收藏（默认 20 条，可调 1–100 条），以及可选的更新提醒。

## 下载与安装

当前最新内测版为 **[0.2.26](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.26)**：

| 平台 | 下载 | 系统要求 |
| :--- | :--- | :--- |
| **Windows (x64)** | [免安装压缩包 (.zip)](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.26/EchoLingo_0.2.26_windows_x64-unpack.zip)（推荐） · [安装版 (.exe)](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.26/EchoLingo_0.2.26_windows_x64-setup.exe) | Windows 10 1809+ / Windows 11（需 WebView2） |
| **macOS (Apple 芯片)** | [安装包 (.dmg)](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.26/EchoLingo_0.2.26_macos_arm64.dmg) | macOS 12+（Apple 系统翻译需 macOS 26+） |

> 提示：当前为内测预发布版，暂未购买商业签名与 Apple 公证。升级前请先完全退出旧版；如果 macOS 首次打开提示无法验证开发者，请参考 [macOS 首次安装说明](docs/macos-install.zh-CN.md)。校验与归档：[SHA256SUMS.txt](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.26/SHA256SUMS.txt) · [发布清单](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.26/RELEASE-MANIFEST.json) · [0.2.26 源码](https://github.com/Blueeeecho/EchoLingo/tree/0.2.26)。

## 文档与开发

- [翻译与 OCR 服务配置说明](docs/official-services.zh-CN.md)
- [免费云端额度配置指南](docs/free-setup.zh-CN.md)
- [隐私说明](docs/privacy.md)
- [从源码构建与本地测试](docs/build.md)

## 支持与许可

如果 EchoLingo 帮到了你，欢迎点个 **⭐ Star**，有问题或想法直接提 [Issue](https://github.com/Blueeeecho/EchoLingo/issues) 即可。

本项目自有代码采用 **MIT + Commons Clause v1.0** 协议（详见 [LICENSE](LICENSE) 与 [LICENSING.md](LICENSING.md)），第三方组件与模型遵循各自原许可。

<sub>感谢 Bob 在桌面翻译体验上的探索与启发。</sub>

## Acknowledgments

- [Linux.do](https://linux.do/)
