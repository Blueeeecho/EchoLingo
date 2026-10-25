# EchoLingo status and handoff

Updated: 2026-10-25, Asia/Shanghai. Stage: v0.1.0 preview validation.

## Latest refinement: quiet empty popup, Enter submission and app-owned permissions
- Alt+D with no obtainable selection, including missing Accessibility permission, presents only the blank popup. It does not autofocus, request access, call a translation API or show a selection-error toast. Clipboard-restoration failures remain visible.
- Source Enter submits once; Shift+Enter inserts a line break. Composition lifecycle, isComposing, legacy keyCode 229 and key repeat are guarded. Empty input is a no-op; other settings fields keep their own Enter behavior.
- Blank layout uses a soft input surface, a distinct language strip and a single collapsible service row; secondary operations remain in More. Translation/OCR errors are not silently swallowed.
- macOS Swift is now a static library inside the app process, removing the former cached helper's separate TCC identity. Hotkeys and status refresh only preflight; explicit Settings actions request access or open one of two fixed privacy panes.
- Local native verification: 34 Rust tests, including the actual Swift static entry, real Vision OCR/PNG/paragraph fixture, Unicode/NUL ABI roundtrip, host PID identity and permission-kind rejection. The Intel macOS 12 static library also cross-compiles; it was not executed on Intel.
- Code was independently reviewed. Installed-app TCC/real IME acceptance and final native installer CI are recorded after packaging. Ad hoc signing can still invalidate authorization after a rebuild; a stable installation path alone does not replace Developer ID signing.

## Latest user refinement: minimal popup and wrapped text
- Translation is a transient popup: tiny pin/more/close toolbar, auto-sized source editor, language strip and provider text. No brand block, counters, instructional/empty cards, timings or footer. Secondary controls are in More or appear on hover/keyboard focus.
- Popup starts at 480 px wide, adapts height to intrinsic content with a work-area cap and no OS title bar. Settings/history use a normal management presentation. Fit operations never show or focus the app; captured content is prepared before inactive display. Only actual outside clicks hide an unpinned popup, not general focus changes; management stays open.
- Captured selection/OCR soft wraps are cleaned once before display/API submission. Blank paragraphs, indentation and recognizable code/lists remain. Raw capture is kept in memory for More > restore original line breaks. Typed/pasted text and historical records are untouched.
- Native OCR uses relative line geometry to mark obvious paragraph gaps; it preserves original line order and handles rotation/structured text conservatively. Plain-text or OCR paragraph reconstruction remains heuristic.
- Input/capture shortcuts received during a credentials editor are deferred without shrinking the editor or discarding its fields.
- Verification: 45 frontend tests and 30 Rust tests, integrated IPC regressions, 420/520 px short/medium/long layout samples; Mac real OCR and paragraph geometry fixtures passed. GitHub Actions run 40102326336 on e15deaa passed frontend interactions, both native builds, Windows OCR geometry and selection/clipboard smoke checks. NSIS and DMG artifacts were generated successfully.
- Latest optimized app is running silently from outputs/EchoLingo-installers/EchoLingo.app. The owner pressed Alt+D and explicitly confirmed the simplified popup is visible on their desktop. Local minimal DMG is generated and its checksum verified.

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
- 30 Rust tests and 45 frontend tests passed locally; isolated frontend/IPC regressions passed, including dual credentials, partial-field rejection, protocol/origin changes, no secrets in Settings and the minimal-popup/captured-text behavior above.
- macOS OCR fixture + PNG base64 roundtrip passed.
- GitHub Actions run 40102326336 on commit e15deaa passed all three jobs: Windows/macOS builds and tests plus frontend interactions. Actual NSIS and DMG packages include the minimal popup, wrapped-text handling, supplier adapters and origin-bound credentials. Local optimized Apple Silicon executable: 4.82 MiB, ad-hoc signature verified.

## In progress
- Local preview acceptance using generated installers; real supplier account testing requires the owner to configure credentials inside EchoLingo.
- Public release publication after the applicable manual acceptance gates. Source is already public; do not call automated checks a completed end-to-end user test.

## Verification boundaries
- User confirmed the independent Mac window is visible. Native automation screenshots returned white even for its normal main view; do not treat that as a proven application rendering failure.
- The owner stopped Bob credential inspection. Current research uses official configuration and supplier API documentation only. Live third-party API calls are NOT claimed as tested; protocol fixtures are clearly labelled. Do not resume inspecting another app's secrets.
- macOS Accessibility permission for this app/helper is still not granted. Actual selected-text permission workflow remains to be accepted on the user's desktop.
- Interactive region selection, mixed DPI/multiple displays, real Windows ARM VM/x64 machines and installation/uninstallation need the manual plan.
- No commercial signing, Apple notarization or store submission. Stable release gates are not yet complete.
