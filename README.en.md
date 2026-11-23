<p align="center"><a href="README.md">中文</a> · <strong>English</strong></p>
<p align="center"><img src="https://blueeeecho.github.io/EchoLingo/assets/echolingo-icon.png" width="96" alt="EchoLingo" /></p>
<h1 align="center">EchoLingo · 回声译</h1>
<p align="center"><strong>A familiar echo for unfamiliar words.</strong></p>
<p align="center">A quiet, lightweight desktop companion for selection translation, screen OCR, and quick screenshots.</p>
<p align="center">
  <a href="https://blueeeecho.github.io/EchoLingo/">Website</a> ·
  <a href="#download">Download 0.2.25</a> ·
  <a href="https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.25">Release Notes</a> ·
  <a href="https://github.com/Blueeeecho/EchoLingo/issues">Issues</a>
</p>

## Three shortcuts

Everything centers around three defaults (on macOS, `Alt` maps to `Option`; all shortcuts can be customized or cleared in Settings):

| Shortcut | Action | What it does |
| :--- | :--- | :--- |
| **`Alt + D`** | Selection translation | Translate selected text in place; press with nothing selected to type directly |
| **`Alt + S`** | Screen OCR | Drag across any area on screen to recognize and translate on release |
| **`F1`** | Screenshot & annotate | Capture a window or region, annotate (pen, highlighter, arrows, notes, mosaic, crop), pin to desktop, or copy/save PNG |

Inside the translation popup, source text stays editable: `Enter` translates, `Shift + Enter` inserts a newline, and `Esc` cancels or hides. Click outside to dismiss, or pin the window when reading side by side.

## Highlights

- **Light and unobtrusive**: Built with Tauri 2 and the native system WebView — no bundled Chromium. Stays in your tray or menu bar until you call it.
- **Local first, extensible when you want**: Uses on-device OCR by default (plus built-in offline Chinese–English translation on Windows), and plugs into Baidu, Youdao, Microsoft, DeepL, OpenAI-compatible APIs, or local Ollama. Enable multiple translators at once to compare results.
- **Private by default**: No telemetry and no background clipboard polling. API keys live in your OS credential store, history stays local, and text/images only leave your machine if you enable a cloud provider.
- **Everyday comforts**: Copy and text-to-speech, light/dark themes, history and favorites (20 items by default, adjustable from 1 to 100), and optional update notices.

## Download

Latest prerelease: **[0.2.25](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.25)**

| Platform | Package | Requirements |
| :--- | :--- | :--- |
| **Windows (x64)** | [Portable ZIP](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.25/EchoLingo_0.2.25_windows_x64-unpack.zip) (recommended) · [Installer (.exe)](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.25/EchoLingo_0.2.25_windows_x64-setup.exe) | Windows 10 1809+ / Windows 11 (WebView2 Runtime) |
| **macOS (Apple silicon)** | [Disk Image (.dmg)](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.25/EchoLingo_0.2.25_macos_arm64.dmg) | macOS 12+ (Apple system translation needs macOS 26+) |

> Note: Prerelease builds are not commercially signed or Apple-notarized yet. Quit any previous version before upgrading; see [macOS first-launch notes](docs/macos-install.zh-CN.md) (Chinese) if Gatekeeper prompts on first run. Verification & source: [SHA256SUMS.txt](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.25/SHA256SUMS.txt) · [Release manifest](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.25/RELEASE-MANIFEST.json) · [0.2.25 source](https://github.com/Blueeeecho/EchoLingo/tree/0.2.25).

## Docs & development

- [Service configuration guide](docs/official-services.zh-CN.md) (Chinese)
- [Optional free cloud quotas guide](docs/free-setup.md)
- [Privacy note](docs/privacy.md) (Chinese)
- [Build & test from source](docs/build.md) (Chinese)

## Support & license

If EchoLingo helps your workflow, a **Star** is always appreciated. Bug reports and ideas are welcome in [Issues](https://github.com/Blueeeecho/EchoLingo/issues).

Original project code is licensed under **MIT + Commons Clause v1.0** (see [LICENSE](LICENSE) and [LICENSING.md](LICENSING.md)). Third-party dependencies and models retain their own licenses.

<sub>Thanks to Bob for the exploration and inspiration around desktop translation.</sub>

## Acknowledgments

- [Linux.do](https://linux.do/)
