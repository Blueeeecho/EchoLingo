# EchoLingo project handoff

## Product
EchoLingo · 回声译 is a lightweight Windows-first desktop translation tool, with macOS support. The owner explicitly authorized multi-agent implementation, local desktop toolchain installation, public GitHub repository creation, and an initial preview release. Do not install HarmonyOS/DevEco Studio: the owner clarified Windows/macOS desktop tooling only.

## Start here
Read `PROJECT.md`, `docs/status.md`, `docs/implementation-plan.md`, and `docs/test-report.md` (when present). The repository and these files are the durable source of project state; do not rely on one chat's history.

## Working rules
- Use skills only when necessary or explicitly requested by the owner.
- Default to silent tray/menu-bar startup. Only user-triggered actions show the window; hide on outside click, with NO automatic timeout by default (explicit owner preference).
- The translation view is a transient minimal popup, not the app home: tiny pin/more/close toolbar, source, languages and results only. Management screens are an explicit separate presentation; resize never activates/focuses/shows a window.
- Normalize soft wraps only for captured selection/OCR. Preserve clear paragraphs, code/lists, and raw capture in memory for an unobtrusive restore action. Typed/pasted text and history must not be automatically flattened. Plain text cannot perfectly distinguish every paragraph.
- Keep software lightweight: system WebView, native offline OCR, vanilla TypeScript. Avoid Chromium/Electron and bundled OCR models without a demonstrated need.
- Native selected-text acquisition must happen before focusing EchoLingo. Never silently replace text in the source app.
- Empty/unavailable Alt+D selection opens a quiet blank popup, including missing Accessibility permission. Permission requests belong to explicit Settings actions; hotkeys and status refreshes only check. Keep clipboard-restoration failures visible.
- Source Enter submits translation; Shift+Enter inserts a newline. Never submit Enter while an IME composition is being confirmed. Empty input is a no-op.
- macOS native code runs as a statically linked library in the app process, not a separately extracted helper. Ad hoc signing still cannot guarantee retained TCC authorization across rebuilds.
- No API keys in files, Git commits, logs, history, screenshots, or fixtures. Store keys in OS credentials. Fixtures use dummy values and local mock HTTP only.
- OCR credentials are scoped by service ID and protocol. Baidu/Tencent use dedicated multi-field credentials and native authentication, not a generic Bearer header. Provider presets must use official docs and distinguish Ali machine translation from Qwen.
- Screenshots are local temporary files, deleted after OCR. Local OCR is default; cloud upload requires explicit OCR service selection, never silent fallback. No telemetry or background clipboard polling.
- The owner stopped local Bob/keychain verification and asked for official configuration-document research instead. Do not resume inspecting another app's secrets without a new explicit request.
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
- `src-tauri/src/ocr.rs` / `ocr_native.rs`: compatible Vision/JSON and native Baidu/Tencent OCR protocols.
- `src-tauri/src/platform.rs`: native helper process boundary.
- `src/panel-layout.ts` / `src-tauri/src/window_layout.rs`: intrinsic popup height and native geometry; content must be prepared before inactive presentation.
- `src/text-normalization.ts`: conservative captured-text wrap cleanup.
- `src-tauri/native/`: macOS Swift + Windows PowerShell/C# helpers.
- `.github/workflows/`: native Windows/macOS CI and preview release builds.
- `docs/`: research, architecture, status, tests and future requirements.
