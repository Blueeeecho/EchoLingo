# EchoLingo · 回声译 — 0.1.0

User-approved name: EchoLingo. Windows first, macOS second. No HarmonyOS SDK requested.

## Architecture
- Tauri 2 + Rust backend + vanilla TypeScript/Vite frontend. Reuse system WebView rather than bundling Chromium.
- Native OS OCR: Windows.Media.Ocr / macOS Vision. No cloud screenshot upload, no bundled OCR neural model.
- Global shortcuts, tray residency, hide-on-blur with optional pinning. Selected text must be obtained before focusing EchoLingo.
- OpenAI-compatible, DeepL, LibreTranslate adapters. API credentials stored in OS Keychain / Credential Manager; endpoint/model/prompt in local JSON.
- Bounded local history, favorites and clear controls. API requests only on explicit action. No telemetry, no clipboard polling.
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
