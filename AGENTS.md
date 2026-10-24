# EchoLingo project handoff

## Product
EchoLingo · 回声译 is a lightweight Windows-first desktop translation tool, with macOS support. The owner explicitly authorized multi-agent implementation, local desktop toolchain installation, public GitHub repository creation, and an initial preview release. Do not install HarmonyOS/DevEco Studio: the owner clarified Windows/macOS desktop tooling only.

## Start here
Read `PROJECT.md`, `docs/status.md`, `docs/implementation-plan.md`, and `docs/test-report.md` (when present). The repository and these files are the durable source of project state; do not rely on one chat's history.

## Working rules
- Use skills only when necessary or explicitly requested by the owner.
- Keep software lightweight: system WebView, native offline OCR, vanilla TypeScript. Avoid Chromium/Electron and bundled OCR models without a demonstrated need.
- Native selected-text acquisition must happen before focusing EchoLingo. Never silently replace text in the source app.
- No API keys in files, Git commits, logs, history, screenshots, or fixtures. Store keys in OS credentials. Fixtures use dummy values and local mock HTTP only.
- Screenshots are local temporary files, deleted after OCR. No telemetry or background clipboard polling.
- Bob is proprietary. Reproduce public behavior independently; do not copy source, UI assets or imply Bob plugin compatibility.
- Keep exact verification evidence. A Windows build is not an interactive Windows test. Mark unsigned previews and manual tests honestly.
- Never publish a stable release until the platform acceptance checklist is complete. Preview releases must list limitations.
- Update `docs/status.md` and `docs/test-report.md` after substantive changes.

## Commands
`npm ci`, `npm run check`, `npm test`, `npm run build`, `cargo test --manifest-path src-tauri/Cargo.toml`, `cargo fmt --manifest-path src-tauri/Cargo.toml`, `npm run tauri dev`, `npm run tauri build`.

## Code map
- `src/`: interface, frontend models and styling.
- `src-tauri/src/main.rs`: IPC commands, tray, hotkeys and state.
- `src-tauri/src/model.rs`: settings/types/validation.
- `src-tauri/src/translation.rs`: OpenAI-compatible/DeepL/LibreTranslate protocols.
- `src-tauri/src/platform.rs`: native helper process boundary.
- `src-tauri/native/`: macOS Swift + Windows PowerShell/C# helpers.
- `.github/workflows/`: native Windows/macOS CI and preview release builds.
- `docs/`: research, architecture, status, tests and future requirements.
