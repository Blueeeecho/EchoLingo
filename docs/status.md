# EchoLingo status and handoff

<!-- project-presentation-license-20261028:start -->
## 2026-10-28 项目介绍、Star 邀请与许可更新

机主要求产品介绍围绕回声译自身，不将 Bob 调研作为宣传内容；README 已移除调研导航，仅文末保留一行低调致谢。项目说明入口同步收敛，README 与官网末尾均加入自然的 Star 邀请。仓库简介和官网地址已更新。[项目首页](https://github.com/Blueeeecho/EchoLingo) · [官网](https://blueeeecho.github.io/EchoLingo/)。

机主核对范围后明确选择标准 MIT + Commons Clause v1.0，而非禁止所有商业用途。已保留完整官方条件与原 MIT 全文，新增 [授权说明](../LICENSING.md)，说明定义中的 Sell、源码可见、旧版本原授权及第三方许可。Cargo/npm 元数据和未来分发的许可文件配置同步；未来离线引擎源码包包含授权说明，第三方许可原件未修改。

公开介绍/许可补丁 main bae7220c56074c2af5097c54a266f1164668cad4 仅8个必要文件，未带入其他生产改动；官网 d1aa59ad37b30f3d68e1e0bc023dd64626564a04 已 built，仅3个静态文件变化。8份公开项目文件与6份官网文件逐字节核验通过；GitHub许可识别为Other/NOASSERTION，未误标纯MIT。官方条件逐段核对、Cargo metadata、JSON依赖不变检查、脚本语法与差异检查通过。Beta1的3项资产、tag和MIT原文均保持原样。[精确记录](validation/project-presentation-license-20261028.json)。
<!-- project-presentation-license-20261028:end -->


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
