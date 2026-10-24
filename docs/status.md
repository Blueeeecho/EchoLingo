# EchoLingo status and handoff

Updated: 2026-10-24, Asia/Shanghai. Stage: v0.1.0 preview validation.

## Confirmed product behavior
- Independent installable Windows-first desktop app, also macOS. Not a browser product.
- EchoLingo / Chinese name: Hui Sheng Yi. No HarmonyOS/DevEco SDK requested.
- Silent tray/menu-bar startup; no window until a user action.
- Alt+D translates selected text. No selection opens an empty floating view WITHOUT activating the app, focusing its textarea, moving the pointer, or calling an API.
- Alt+S selects a screen region, OCRs it, then translates directly. No intermediate OCR result window.
- Floating window is above other ordinary apps by default. Clicking outside hides it; no default timeout. Pin means retain on outside click, not a different z-order.
- Original text, language bar, then multiple provider results; original EchoLingo styling inspired only by the reference information order.
- Custom translation AND OCR APIs; local system OCR remains the default. Cloud OCR uploads only after explicit provider selection.

## Implemented and verified so far
- Public GitHub repo and matching local Codex project folder.
- Detailed Bob research, requirements, review notes, Windows manual test plan.
- Translation: OpenAI-compatible, DeepL, LibreTranslate, with official supplier presets for DeepSeek, Zhipu, SiliconFlow and Qwen (region/workspace aware).
- OCR: native Windows.Media.Ocr / macOS Vision, Baidu OAuth/form, Tencent TC3, compatible Vision API and advanced JSON gateway. Supplier-specific credential fields; new cloud entries do not change the active local engine.
- OS credentials bound to protocol and normalized endpoint origin, preventing old keys crossing suppliers; bounded history/favorites, themes, provider and hotkey settings.
- Native clipboard-preserving selection, screenshot capture, inactive floating windows and outside-click handling.
- 28 Rust tests and 20 frontend tests passed locally; isolated frontend/IPC regressions passed, including dual credentials, partial-field rejection, protocol/origin changes and no secrets in Settings.
- macOS OCR fixture + PNG base64 roundtrip passed.
- GitHub Actions run 40097996277 on commit 3c8d0f8 passed all three jobs: Windows/macOS builds and tests plus frontend interactions. Actual NSIS and DMG packages include supplier adapters and origin-bound credentials. Local optimized Apple Silicon app: 4.78 MiB, ad-hoc signature verified.

## In progress
- Local preview acceptance using generated installers; real supplier account testing requires the owner to configure credentials inside EchoLingo.
- Public release publication after the applicable manual acceptance gates. Source is already public; do not call automated checks a completed end-to-end user test.

## Verification boundaries
- User confirmed the independent Mac window is visible. Native automation screenshots returned white even for its normal main view; do not treat that as a proven application rendering failure.
- The owner stopped Bob credential inspection. Current research uses official configuration and supplier API documentation only. Live third-party API calls are NOT claimed as tested; protocol fixtures are clearly labelled. Do not resume inspecting another app's secrets.
- macOS Accessibility permission for this app/helper is still not granted. Actual selected-text permission workflow remains to be accepted on the user's desktop.
- Interactive region selection, mixed DPI/multiple displays, real Windows ARM VM/x64 machines and installation/uninstallation need the manual plan.
- No commercial signing, Apple notarization or store submission. Stable release gates are not yet complete.
