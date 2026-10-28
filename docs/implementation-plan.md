# EchoLingo · 回声译 — 0.1.0

User-approved name: EchoLingo. Windows first, macOS second. No HarmonyOS SDK requested.

## Architecture
- Tauri 2 + Rust backend + vanilla TypeScript/Vite frontend. Reuse system WebView rather than bundling Chromium.
- Native OS OCR by default: Windows.Media.Ocr / macOS Vision, no bundled OCR neural model. Explicitly selected cloud OCR is an alternative, with its own credentials and visible upload status; no automatic cloud fallback.
- Global shortcuts, tray residency, always-on-top floating view and hide-on-outside-click with optional pinning. Selected text must be obtained before showing EchoLingo without activation. Empty selection opens a blank view without focusing the textarea.
- OpenAI-compatible, DeepL, LibreTranslate adapters. API credentials stored in OS Keychain / Credential Manager; endpoint/model/prompt in local JSON.
- Supplier-specific OCR adapters for Baidu and Tencent, compatible vision models, and an advanced JSON gateway. Authentication protocol and supplier labels remain separate; Ali machine translation is not Qwen.
- Bounded local history, favorites and clear controls. API requests only on explicit action. No telemetry, no clipboard polling.
- Windows idle OCR additionally outlines the actual application root beneath the pointer using DWM frame metadata, while retaining the current-display screen border. Desktop/shell, unknown, known-own/known-affinity-excluded or occlusion-mismatched targets show only the screen border. Four more thin HWNDs per display and80ms UI-thread queries keep the hint out of input hooks; left-drag clears it and retains the arbitrary ROI. Mac parity is deferred.
- Bob is a behavior reference only. No Bob proprietary code, names, icons, or plugin compatibility claimed.

## First release gates
1. Frontend typecheck/build and model tests.
2. Rust settings, endpoint, protocol, history and actual local HTTP integration tests.
3. Native OCR fixture self-test on macOS and Windows.
4. GitHub Actions builds actual Windows NSIS and macOS DMG bundles.
5. Security review: no credentials in settings/history/source, bounded response bodies, TLS, local-only IPC, no remote script/HTML rendering.
6. Explicitly distinguish automation results from interactive multi-screen/permission checks still requiring manual validation.

## Deferred
Translated-image overlays, arbitrary Bob JavaScript plugin execution, continuous OCR, QR codes, full dictionary pronunciation/word forms, signed store releases and auto-update infrastructure.

## Toolchain
Node and Xcode Command Line Tools already available on the user's Apple Silicon Mac. Install Rust stable minimally; Tauri CLI is project-local npm dependency. Native Windows builds run on Windows GitHub Actions with MSVC + WebView2, not emulated as a Mac compile.
