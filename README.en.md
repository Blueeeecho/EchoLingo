<p align="center"><a href="README.md">中文</a> · <strong>English</strong></p>
<p align="center"><img src="https://blueeeecho.github.io/EchoLingo/assets/echolingo-icon.png" width="96" alt="EchoLingo" /></p>
<h1 align="center">EchoLingo · 回声译</h1>
<p align="center"><strong>A familiar echo for unfamiliar words.</strong></p>
<p align="center">A lightweight desktop app for selection translation and seamless OCR, so understanding can keep up with your reading.</p>
<p align="center"><a href="https://blueeeecho.github.io/EchoLingo/">Website</a> · <a href="https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.13">Windows 0.2.13 test prerelease</a> · <a href="https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.13">macOS 0.2.13 test prerelease</a> · <a href="https://github.com/Blueeeecho/EchoLingo/issues">Feedback</a></p>

## Download and install

**[Download Windows 0.2.13 test prerelease (x64)](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.13/EchoLingo_0.2.13_windows_x64-setup.exe)** · **[Download macOS 0.2.13 test prerelease (Apple silicon)](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.13/EchoLingo_0.2.13_macos_arm64.dmg)**

Windows supports Windows 10 1809+ and Windows 11. The macOS package is for Apple silicon Macs on macOS 12 or later. Apple system translation needs macOS 26 or later. After installation, EchoLingo stays in the tray or menu bar. Quit the previous version completely before you upgrade.

Windows and macOS now both offer the 0.2.13 test prerelease. Translation and OCR services are managed separately, with collapsible free-service recommendations. The defaults are `Alt+D`, `Alt+S`, and a separate `F1` screenshot and local editor action; shortcuts can be changed, cleared, or customized.

This version simplifies automatic translation direction: EchoLingo’s own content checks no longer block requests early because of filenames, mixed languages, short text or uncertain detection. A manually selected target uses a concrete fallback source when detection is unresolved. Apple system translation no longer bypasses the service by returning the original text directly. Service refusals or failures are still reported.

Validation covers focused routing and request tests on both platforms, fresh installer builds and static package inspection. Full regression, installed runtime, screenshot, OCR and visual acceptance were not repeated. Other selection, screenshot and multi-display issues are outside this fix. Real applications, services, Chinese IME candidate windows, physical multi-monitor setups and mixed DPI still need hands-on acceptance. See the release notes for limitations.

This is an internal prerelease, not a stable release. Windows has no commercial code signature; macOS uses ad hoc signing and is not notarized by Apple. Your system may show warnings or request permissions again. Install only files from this repository’s release page with matching checksums.

- **Windows 0.2.13**: [Release notes](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.13) · [SHA-256 checksums](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.13/SHA256SUMS.txt) · [Release manifest](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.13/RELEASE-MANIFEST.json)
- **macOS 0.2.13**: [Release notes](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.13) · [SHA-256 checksums](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.13/SHA256SUMS.txt) · [Release manifest](https://github.com/Blueeeecho/EchoLingo/releases/download/0.2.13/RELEASE-MANIFEST.json)

0.2.13 is a test prerelease, not a stable GitHub `Latest` release. See [all releases](https://github.com/Blueeeecho/EchoLingo/releases) for earlier versions. The installers correspond to the [0.2.13 source tag](https://github.com/Blueeeecho/EchoLingo/tree/0.2.13), not the default branch; See the release manifest for the relationship between source and installer bytes. The previous [0.2.12 preview](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.12) remains available.

[First-launch notes for macOS](docs/macos-install.zh-CN.md) (Chinese) · [Build from source](docs/build.md) (Chinese)

## Three shortcuts

- **Selection translation**: select text in the app you are using, then press `Alt+D`. The popup fills in the text and translates it.
- **Seamless OCR**: press `Alt+S` and drag with the left mouse button. When you release, EchoLingo reads the text, fills it in, and translates it.

- **Screenshot and in-place editing**: press `F1`, then click a window or drag a region. Readjust the capture bounds in the same editor; type text or notes on the canvas and annotate with a pen, highlighter, ellipses or numbered arrows. Move or re-edit annotations, erase parts of strokes, pin a reference image, or copy/save a PNG. Capture and editing stay local, without OCR or translation services.

Press `Alt+D` with nothing selected to type directly. The source stays editable. `Enter` translates, `Shift+Enter` inserts a line break, and `Esc` cancels a region selection. Shortcuts can be changed in Settings. On a Mac, Alt is Option.

## Use it your way

- **Quiet and light**: it lives in the tray and appears when you call it. Click outside to hide the translation popup, or pin it to keep it. It uses the system web view and does not bundle Chromium.
- **Your choice of service**: Windows includes offline Chinese–English translation, and OCR stays on the device by default. You can also configure your own translation and OCR services, with multiple translation services enabled together to compare results.
- **Small things close at hand**: copy or speak the source and the translation, switch themes, and keep history and favorites. History keeps the latest 20 items by default, adjustable from 1 to 100.

Open Settings from the tray menu to configure services, manage keys, or change shortcuts. See the [service setup notes](docs/official-services.zh-CN.md) (Chinese). For optional free cloud quotas while keeping the local default, see the [free setup guide](docs/free-setup.md). Quotas change and are not permanently free.

## Free update notices

Use **Check for updates** and **Open download page** in Settings. Automatic checks are off by default; opt in for at most one public GitHub metadata request per day. No text or keys are sent. The current internal preview builds include prereleases by default; you can select stable releases only. Downloads and installation remain manual, with no paid updater or signing purchase required.

## Privacy and data

Local OCR and offline translation run on your computer. Text or images are sent out only after you choose a cloud service. Keys stay in the system credential store, and history stays on the device. The app has no telemetry and does not keep polling the clipboard. [Read the privacy note](docs/privacy.md) (Chinese).

## Support EchoLingo

If EchoLingo is useful, a **Star** helps more people find it and supports the work. Questions and ideas are welcome as [issues](https://github.com/Blueeeecho/EchoLingo/issues). Building and testing from source is described in the [development notes](docs/build.md) (Chinese).

## License

The project’s own code uses **MIT + Commons Clause v1.0**. You can read, study, modify, and distribute it under those terms. See [LICENSE](LICENSE) and the [licensing notes](LICENSING.md).

Third-party components and models keep their own licenses. Older versions already released under MIT stay under that original license.

<sub>Thanks to Bob for the exploration and inspiration around desktop translation.</sub>

## Acknowledgments

- [Linux.do](https://linux.do/)
