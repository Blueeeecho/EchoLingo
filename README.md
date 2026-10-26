<p align="center"><img src="assets/icon.svg" width="90" alt="EchoLingo icon" /></p>
<h1 align="center">EchoLingo · 回声译</h1>
<p align="center">选中文字，按下快捷键。翻译就在眼前。</p>
<p align="center">Windows 优先 · 中英离线翻译 · 系统离线 OCR · 自定义 API</p>

**0.1.0 预览版开发中。** 本项目独立实现 Bob 风格的桌面翻译工作流，非 Bob 官方产品，不使用 Bob 专有代码或素材，也不直接兼容 Bob 插件。

## 初版功能

- 在其他应用选中文字后，用全局快捷键取词并翻译。
- Alt+S 左键框选屏幕，系统离线 OCR 将文字填入浮窗并自动翻译；保留独立只识字入口。
- Windows 安装包内置 Mozilla 中英离线翻译，无需 API Key；macOS 可使用已准备的 Apple 系统语言包。
- 输入翻译、剪贴板翻译，多服务结果对照。
- 自定义 OpenAI 兼容 API、DeepL、LibreTranslate；常用供应商预设可编辑端点、模型和提示词。
- OCR 可选择本机、百度、腾讯、兼容视觉模型，或高级 HTTP JSON 网关。凭证按各自协议填写。
- 本地历史与收藏、搜索/清除、浮窗默认置顶、点击外部隐藏、托盘常驻、深浅主题。
- 原生 WebView + Rust；不捆绑 Chromium 或 OCR 大模型。

## 获取与运行

安装包通过 [GitHub Actions](https://github.com/Blueeeecho/EchoLingo/actions) 构建，验证后的预览版位于 [Releases](https://github.com/Blueeeecho/EchoLingo/releases)。没有附件时说明尚未完成验证，请勿把源代码 ZIP 当安装包。

- Windows：Windows 10 1809+ / Windows 11 x64，内置翻译需要支持 SSE4.1 的 x64 CPU，支持中英互译，其他语言可配置 API；OCR 仍需系统语言包与 WebView2。安装包可安装缺失的 WebView2（需要联网）。
- macOS：macOS 12+，当前优先 Apple Silicon。取词可能需要辅助功能权限，截图需要屏幕录制权限。原生代码运行在应用自身进程中；快捷键只检查权限，在设置中明确授权。预览版的临时签名仍可能在重建后使授权失效，见 [原生说明](docs/native-testing.md)。
- 初版安装包尚无商业代码签名/Apple 公证，会出现系统来源提示；不包含商店上架或自动更新。

## 首次配置

1. Windows 默认启用“本机离线翻译”，可以直接尝试中英句子；模型随安装包提供，不在翻译时下载。macOS 可在设置中检查并显式准备 Apple 系统语言包。
2. 在其他应用选中文字，按 Alt+D；图片文字按 Alt+S 后左键拖动框选，识别后自动填入并翻译。
3. 需要更多语言或其他翻译质量时，在“设置”添加供应商预设，填写自己的 API 地址、模型和密钥。密钥仅存系统凭据库。
4. 本机服务的“测试翻译”不发送云端请求；API 的“测试连接”会发送 `Hello`，可能消耗供应商额度。

DeepL 可使用 `https://api-free.deepl.com/v2` 或 Pro 的 `https://api.deepl.com/v2`；LibreTranslate 填你自己的实例地址。本地服务可用 `http://127.0.0.1:端口`，远程服务要求 HTTPS。

OCR 默认不需要密钥。需要云端识别时，在“OCR 服务”中添加供应商：百度填写 API Key 与 Secret Key；腾讯填写 SecretId 与 SecretKey，临时凭证另填 Token。保存配置后可用生成的测试图检查连接，再选择它作为当前 OCR。测试会上传该测试图，启用云端 OCR 后会上传你主动框选的截图。通用 JSON 网关供已有自建接口使用，不能代替厂商原生签名协议。详见 [服务配置设计](docs/api-configuration-design.zh-CN.md)。

## 默认快捷键

| 功能 | Windows | macOS |
|---|---|---|
| 划词翻译 | Alt+D | Option+D |
| 无感 OCR → 自动翻译 | Alt+S | Option+S |
| 截图 OCR | Alt+Shift+S | Option+Shift+S |
| 输入翻译 | Alt+A | Option+A |

设置中可修改或留空禁用。快捷键冲突会报告错误；若同时运行 Bob 等工具，需为其中一个更换快捷键。没有选中文字时按 Alt+D，会打开空白浮窗并聚焦输入框，可直接键入，Enter 翻译、Shift+Enter 换行；输入法确认不提交。翻译按钮在请求期间变为停止按钮；编辑、清空或隐藏浮窗也会取消当前翻译，取消的任务不会再写入历史。已经发送到供应商的请求可能仍计费，停止本机等待不表示供应商退款。Esc 取消截图/隐藏窗口。

启动默认只出现在托盘/菜单栏，不主动弹窗口。浮窗默认位于其他普通窗口之上；点击外部立即隐藏，不使用倒计时。“钉住窗口”可让它在点击外部后保留。关闭窗口后应用仍在托盘运行，从托盘菜单退出。

## 隐私与数据

本机 OCR 在系统内离线执行；只有明确选择云端 OCR 后，截图才会发送到选定服务。截图临时文件在处理结束后删除。内置离线翻译在本机执行；启用 API 服务后，翻译文字才会发送给你选定的供应商。无遥测、无常驻剪贴板监听。

历史默认保存在本机，保留最近20条，可调1–100条或关闭、清除。密钥位于系统凭据库；其他设置和历史保存在应用数据目录（可在“权限与诊断”查看）。首次配置前请先阅读 [隐私说明](docs/privacy.md)。

## 本地开发

需要 Node.js 24 LTS、Rust stable（1.90+）和平台编译工具。macOS 仅桌面开发使用 Xcode Command Line Tools 即可；Windows 需要 MSVC C++ Build Tools 和 WebView2，详见 [Tauri 官方环境要求](https://v2.tauri.app/start/prerequisites/)。

```sh
npm ci
npm test
npm run test:ui # 另一个终端先启动 npm run dev；需 Playwright Chromium
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri dev
# 当前平台安装包
npm run tauri build
```

Windows 离线翻译构建需先准备固定资源与原生引擎（CMake3.31、MSVC x64、Ninja；仅构建时下载）：

```powershell
python scripts/prepare-offline-models.py
python scripts/offline-engine/build.py --work-dir "$env:TEMP/echolingo-offline-build" --output-dir resources/offline-translation/bin --jobs 4
npm run tauri build -- --bundles nsis
```

模型资源增加约104.47MB安装占用，引擎/应用和安装器压缩体积另计。真实执行结果与限制以验证报告为准。

Windows 原生 OCR 非交互自测（不修改剪贴板）：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File src-tauri/native/windows.ps1 -Mode self-test
```

## 项目文档

- [项目要求与入口](PROJECT.md)
- [Bob 详细研究与可复现交互](docs/bob-research.zh-CN.md)
- [开发进度](docs/status.md) · [验证报告](docs/test-report.md)
- [个性化需求与路线图](docs/roadmap.zh-CN.md)
- [原生平台说明](docs/native-testing.md)
- [macOS 固定预览入口、安装回滚与性能采样](docs/local-preview.zh-CN.md)

原图覆盖翻译、连续 OCR、任意插件执行和完整词典功能尚未实现。Windows 多屏、混合 DPI、特定应用选文等必须按报告补真实桌面验收，不能用构建成功替代。

EchoLingo 自有代码为 MIT；内置模型与推理组件分别遵守 MPL-2.0 等第三方许可，见[分发说明](docs/offline-translation-licenses.zh-CN.md)。Bob、Windows、macOS 及各翻译服务商标归各自所有者。
