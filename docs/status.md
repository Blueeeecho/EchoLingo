# EchoLingo status and handoff

Updated: 2026-10-25, Asia/Shanghai. Stage: v0.1.0 preview hardening and acceptance.

## 2026-10-27 Windows11 interaction investigation — candidate under review, not installed/accepted

The owner reports blue OCR frames but left clicks still reach ordinary non-fullscreen application buttons, plus slow Alt+S readiness/dragging and unwanted OCR spaces/wraps. Earlier Server2025 generated-window passes do not override this physical Windows11 failure. The mouse-interception cause remains unproved; a visible frame is not proof of a working mouse hook.

Candidate changes remove the fixed Windows180ms delay, embed a build-time Framework DLL instead of recompiling C# on every operation, coalesce MOVE-triggered UI wakes with the16ms heartbeat retained, reduce redundant edge HWND updates, and preserve bounded no-content capture-health metadata. A750ms sustained input mismatch cancels visibly without a screenshot; this is a fail-safe, not proof the owner bug is fixed. OCR-only Han spacing repair and native paragraph-pitch inference preserve raw restore, explicit paragraphs, code/Latin/Korean/numbers and manually typed input.

Two core shortcuts now have recording/manual editing and transactional immediate registration/persistence. An early installed-exe CLI checks actual temporary RegisterHotKey availability without a WebView/credential read/settings write; installation warns on conflicts and offers shortcut settings. Silent/passive installation never launches settings or displays this prompt. Unknown checks are distinct from occupied/reserved keys. Independent review identified that WM_HOTKEY combinations need a lease-bound event bridge to be recorded, and found delayed-ACK/Esc and DLL cache identity boundaries; fixes and actual Windows verification are in progress.

Initial host checks:193Rust pass/1resource-runtime ignored,71TS unit pass and complete isolated fake-IPC UI pass. These precede the final independent-review fixes and are not final candidate or Windows-native acceptance. Expanded ordinary-peer drag, exact-DLL load/failure, same-runner A/B and actual packaged WebView+SendInput shortcut fixtures are prepared for a new full CI. No Mac signing/install/permissions, user credentials or stopped local Win10VM were touched.

Size audit of the previous delivered archive:94,674,254B outer ZIP includes75,210,904B NSIS and19,456,259B corresponding engine source.104,470,603B unpacked bilingual offline models dominate runtime resources. New runtime allowlist excludes195,072B development metadata while retaining every model and original license/source notice; compressed savings must be measured after the new build. The source attachment remains separately available; it must not be confused with installed application code.

## 2026-10-27 Windows OCR hover-window guidance: controlled runtime and preview complete

Alt+S keeps the current-display screen border and adds a thin blue frame around the actual hovered application root. Desktop/taskbar, unknown, known-own/known-affinity-excluded or occlusion-mismatched targets keep only the screen border. Starting left-drag clears the window hint and keeps the arbitrary-region OCR→source fill→automatic translation flow. Metadata only,80ms UI-thread queries,12 allocated thin HWNDs/display; no whole-display surface, window title/text/pixels, focus or extra permission for hints. The disabled-window ambiguity found in independent review was repaired before runtime verification.

Applicationab4405cc15e2ca204459b2fd40389924aa994695: full [40481264703](https://github.com/Blueeeecho/EchoLingo/actions/runs/40481264703) retains **failure** because the old application fixture required4edges. Its actual live8/8 (A→B/disabled/shell/heldfreeROI/7pixel probes), popup cases, real NSIS installation and6offline models+3installed appflows passed. The failing old readiness probe did not log its actual edge count. Fixture-onlyef27367 [40483707524](https://github.com/Blueeeecho/EchoLingo/actions/runs/40483707524) then passed all3actual appflows with exact controlled source/pointer/DWM/uniquehelper/screen4+hover4 geometry. Source-unchanged and exact stageSHA199d3f29… gates passed; no rebuild. Combined evidence is for one application, not a rewritten full-CI success or physicalWin10 acceptance.

[New unsigned Windows x64 preview with corresponding engine source](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261027-hover-window/EchoLingo_0.1.0_preview_20261027_hover-window_windows_x64_with-source.zip):94,674,254B/SHA256a6c99dbdc1908b108731e481c87ff554b84371868c272cde3937bfaa9d06328b. NSIS75,210,904B/293a2648…; engine source19,456,259B/b82a524a…. API ZIP digests/size/CRC, embedded complete frozen helper, exact3byte NSIS bundle-marker identity and final archive members verified. Previous previews remain recoverable archives; no stable/public release published.

Host C#5/net48/PS7 AST and76capture-policy assertions (30hover) passed; actual Windows native checks and142WindowsRust/146MacRust (1ignored each),61frontend and isolatedUI passed within their scope. Mac hover parity is deferred; canonical7eafe813 was only hash-read and unchanged. Local known-failing Win10VM remains stopped and was not used for this feature. PhysicalWin10 responsiveness/IME/consumer setup, WPS/Edge, physicalmulti-display/mixedDPI, elevatedinstaller/securitydesktop and pinned own-window exclusion remain open. [Exact evidence](validation/windows-ocr-hover-20261027.json).

## Latest work: cancellation, language fidelity and repeatable verification
- Translation requests now have backend tickets and a presentation epoch. Edit, clear, Stop, Escape, close, outside-click hide and a new capture abort the old HTTP future. A hide before ticket allocation also invalidates the request; stale hide/source events or delayed layout cannot resurrect an abandoned popup.
- Cancelled/superseded translations cannot commit history. Completion uses current privacy settings; clearing all history invalidates pending begins. Byte accounting includes JSON array delimiters, and a single oversized result is discarded before it can evict other healthy records.
- DeepL preserves Simplified/Traditional targets with ZH-HANS/ZH-HANT; LibreTranslate uses zh/zt. A missing model or rejected target remains an explicit error; there is no silent Simplified fallback.
- Native macOS checks now cover a unique private pasteboard's multiple Unicode/HTML/RTF/binary representations, empty restoration, PNG size boundaries and additional OCR geometry. They never touch the general clipboard or request access. The private AppKit fixture runs in the standalone CLI main thread; background Rust tests report that fixture skipped and still exercise the production static OCR/ABI entry.
- New local preview tooling verifies bundle/signature identity, stages installation, preserves a rollback backup, refuses unsafe paths/processes, supports ancestor path aliases and uses Launch Services for a background hidden launch. Development outputs are retained; one canonical daily entry is ~/Applications/EchoLingo.app.
- Independent review found and repaired pending-ticket native-hide and stale-result races plus aliased install-path identity. Storage fault tests cover replacement failures and Windows sharing locks.

## Confirmed product behavior
- Independent lightweight Windows-first desktop app, also macOS; Tauri 2, vanilla TypeScript and system WebView. No HarmonyOS/DevEco SDK, bundled Chromium or OCR models.
- Default startup is silent tray/menu-bar residency. Translation is a transient minimal popup: tiny pin/more/close toolbar, source, language strip and multiple provider results. Settings/history are a separate management presentation.
- Alt+D acquires selection before presenting inactive content. Unavailable/empty selection opens a quiet blank popup without autofocus, permission prompts or an API request. Clipboard-restoration failures remain visible.
- Alt+S region OCR translates directly. Local system OCR is default; cloud uploads require an explicitly selected OCR provider. No silent fallback, telemetry or background clipboard polling.
- Popup is above ordinary windows; an outside click hides unless pinned. No default timeout. Fit/resize never shows or focuses a window.
- Enter submits, Shift+Enter inserts a line break; IME confirmation and key repeat do not submit.
- Only captured selection/OCR soft wraps are normalized; paragraphs/code/lists and raw restore are preserved. Typed/pasted text and history are untouched. Paragraph inference remains heuristic.
- Translation: OpenAI-compatible, DeepL, LibreTranslate plus official DeepSeek/Zhipu/SiliconFlow/Qwen presets. OCR: macOS Vision/Windows.Media.Ocr, Baidu, Tencent, compatible vision and JSON gateway. Credentials stay in OS storage, bound to protocol and endpoint origin.
- macOS native Swift is statically linked in the app process. Permission refresh/hotkeys only check; explicit Settings actions request/open access. Ad hoc signing can still invalidate TCC authorization across rebuilds.

## Verification evidence
- Current local checks: 50 Rust tests, 45 frontend unit tests, complete isolated UI/IPC regression, 22 installer safety/rollback fixtures; typecheck, production build, formatting and npm audit passed.
- Current branch CI run 40172215129 on 3ec4f81 passed all three jobs. Windows ran 49 Rust tests including the real exclusive-file-lock failure/retry, native OCR and selection/clipboard desktop smoke; macOS ran 50 Rust tests and the standalone private-pasteboard/OCR suite. Both NSIS and DMG artifacts were generated. See https://github.com/Blueeeecho/EchoLingo/actions/runs/40172215129 and draft PR https://github.com/Blueeeecho/EchoLingo/pull/1.
- Optimized macOS app/DMG, ad hoc signature integrity and hdiutil checksum verification passed. The canonical ~/Applications app is installed and running; a read-only probe found zero onscreen regular windows and no foreground activation. Main-process metrics and the retained OCR timing outlier are in docs/test-report.md and docs/validation/macos-preview-20261025.json.
- Baseline main CI run 40167604502 on 856e1a7 also passed Windows/macOS native builds and frontend interactions; current branch evidence above supersedes that baseline for this work.
- Prior user confirmation of the minimal popup belongs to the older e15deaa installation. It is not acceptance of the latest permission/cancellation changes.

## Preview distribution
- Draft prerelease v0.1.0-preview.1 contains the Apple Silicon DMG, Windows x64 NSIS and SHA-256 checksums. It remains unpublished: https://github.com/Blueeeecho/EchoLingo/releases/tag/untagged-c8da17a22fa76e07d45f. Local packages are in sibling EchoLingo-installers; the Windows ZIP digest matched GitHub artifact metadata and its PE header was checked. This is not a real Windows install/uninstall pass.

## Remaining external acceptance
- Installed-app real IME; actual selection and region capture/cancel; same-version restart and cross-version TCC behavior on the owner's Mac.
- Windows actual target apps, global shortcuts, region selector, mixed DPI/multiple displays, installation/upgrade/uninstall on a real Windows desktop. Controlled CI fixtures do not establish all of these.
- Live supplier-account translation/OCR. Tests use dummy credentials and local HTTP; do not inspect Bob credentials. The owner stopped that inspection and requested official-document research instead.
- Full WebView process-group memory, end-to-end cold startup/capture latency, commercial signing/Apple notarization, auto-update/store distribution.
- No stable release until the platform acceptance checklist is complete. A preview must retain explicit limitations. Candidate features in roadmap.zh-CN.md are not all promised for v0.1.

## Local entry and sources
- Use the canonical app after installation: ~/Applications/EchoLingo.app. Other .app outputs are build/recovery artifacts, not separate products to run simultaneously.
- See [local preview tooling](local-preview.zh-CN.md), [test report](test-report.md), [Windows acceptance plan](windows-test-plan.zh-CN.md), and [native verification](native-testing.md).
- The main source checkout remains this repository. Previous development chat is titled “查询 GitHub 多账号连接”, associated with the parent ni-ne directory; project files and Codex chat history are stored separately.
