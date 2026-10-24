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
- Translation: OpenAI-compatible, DeepL, LibreTranslate.
- OCR: native Windows.Media.Ocr / macOS Vision, custom Vision-compatible API and JSON gateway.
- Separate OS credential entries for translation/OCR, bounded history/favorites, themes, provider and hotkey settings.
- Native clipboard-preserving selection, screenshot capture, inactive floating windows and outside-click handling.
- 21 Rust tests and 9 frontend model tests passed locally; isolated frontend/IPC regressions passed.
- macOS OCR fixture + PNG base64 roundtrip passed.
- Earlier source revision built actual Windows NSIS and macOS DMG successfully in GitHub Actions run 40093670591. New behavior requires another final CI run.

## In progress
- Latest native Windows OCR/selection/empty-selection/clipboard smoke and frontend CI.
- Final optimized desktop bundles after recent feature changes.
- Review and preview release publication after required automated gates.

## Verification boundaries
- User confirmed the independent Mac window is visible. Native automation screenshots returned white even for its normal main view; do not treat that as a proven application rendering failure.
- Bob preferences were inspected read-only under explicit user authorization. No transferable personal provider key was identified. Live third-party API calls are NOT claimed as tested; protocol fixtures are clearly labelled.
- macOS Accessibility permission for this app/helper is still not granted. Actual selected-text permission workflow remains to be accepted on the user's desktop.
- Interactive region selection, mixed DPI/multiple displays, real Windows ARM VM/x64 machines and installation/uninstallation need the manual plan.
- No commercial signing, Apple notarization or store submission. Stable release gates are not yet complete.
