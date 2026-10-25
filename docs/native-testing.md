# Native selection, clipboard and offline OCR

The native adapter is `src-tauri/src/platform.rs`. Its capture and clipboard functions are blocking and must run through `tauri::async_runtime::spawn_blocking`. `show_without_activation` is an exception and must run on the application main thread. The global-shortcut handler must capture the original application's selection **before** showing or focusing the EchoLingo window. Serialize native operations so two shortcuts cannot run overlapping clipboard transactions or screenshot pickers.

## Implementation and prerequisites

| Platform | Selection | Region capture and offline OCR | Runtime prerequisites |
| --- | --- | --- | --- |
| Windows 10/11 | UI Automation `TextPattern.GetSelection()`, followed by Ctrl+C when necessary | Per-monitor-aware WinForms selector over a desktop `BitBlt` snapshot; built-in `Windows.Media.Ocr` | Built-in Windows PowerShell 5.1, .NET Framework, and at least one installed OCR language. The desktop application also needs WebView2. |
| macOS 12+ | Accessibility selected-text attribute, followed by Cmd+C when necessary | Native `/usr/sbin/screencapture -i -x` region selection; Apple Vision | Accessibility for selection capture; Screen Recording for capture. System OCR needs no model download. |

Both adapters use one UTF-8 JSON object per operation. Windows uses a supervised helper process; macOS links the Swift adapter into the EchoLingo application process. Errors beginning with `CANCELLED:` are ordinary user cancellation and should not trigger alarming UI. Escape/right click cancel the Windows selector. Escape cancels the native macOS selector. Both selectors time out after 120 seconds. Windows OCR has a separate 30-second operation budget. The Windows process supervisor has a 180-second outer capture limit and a 60-second limit for other modes.

Local system OCR remains the default: `capture_ocr()` returns recognized text and sends no image to a server. Third-party OCR requires explicitly selecting/configuring an OCR API in the application. For that route, `capture_image()` uses the same native region picker and returns a **plain PNG base64 string without a `data:` prefix**. The helper protocol is `{ "ok": true, "imageBase64": "..." }`. The native helper only captures and encodes; the application handles any explicitly configured OCR upload afterward. Image capture does not require an installed Windows OCR language because it never initializes the recognizer.

Captured PNG data is limited to **8 MiB before base64 encoding**. Larger images return `CAPTURE_TOO_LARGE:` with guidance to select a smaller region. `capture-image` gets the same 180-second outer limit as local OCR capture; its stdout budget is 12 MiB to accommodate base64 expansion, while other modes retain a 4 MiB stdout limit. Temporary image files are removed after encoding or errors in the same `finally`/`defer` scope as local OCR. Neither helper uploads screenshots, logs base64 image data, or writes images into application history.

The Windows helper is embedded, extracted under `%LOCALAPPDATA%\EchoLingo\native`, and launched with the system `powershell.exe -NoProfile -NonInteractive -STA`. `-ExecutionPolicy Bypass` applies only to that child process; no persistent policy is changed. Managed computers that prohibit PowerShell may block the helper. User text is sent through UTF-8 stdin, never interpolated into PowerShell or command-line code. The script uses no third-party OCR module and performs no network requests.

The macOS adapter is compiled by `build.rs` as a Swift static library and linked into the Rust executable. It no longer extracts or launches a cached `echolingo-native-helper`. Accessibility and Screen Recording checks therefore execute in the application process, eliminating the former separate helper identity. The adapter never activates the source application or the EchoLingo window. Use the installed `/Applications/EchoLingo.app` consistently rather than alternating between debug builds and output copies.

Shortcut operations only preflight permissions. Settings exposes read-only `permission_status`, explicit `request_permission` and fixed-pane `open_permission_settings` commands, with only `accessibility` / `screenCapture` accepted. A status refresh never requests access. Empty or unavailable selection opens a blank, nonactivating popup without an error toast; failed clipboard restoration remains an actionable warning. macOS still controls permission grants, and a new application identity may require the owner to authorize it once.

This fixes the separate-helper and repeated-request paths; it does not make an ad hoc signature stable across rebuilds. Apple explains that ad hoc designated requirements are tied to a specific code version, so upgrades can invalidate recorded authorization. A distribution needs a consistent Apple signing identity and separate clean-machine TCC/Gatekeeper acceptance. See [Apple TN3127: code identity and designated requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## Clipboard guarantees and limits

The direct Accessibility/UI Automation path does not write the clipboard. The copy fallback first materializes all existing clipboard formats, waits for shortcut modifiers to be released, sends copy to the foreground application, reads copied text, and restores the saved formats. Text, rich text/HTML, bitmaps, file lists, byte arrays and seekable streams are handled by the Windows adapter. macOS snapshots each pasteboard item's data representations. If any representation cannot be captured safely, fallback stops **before** changing the clipboard and returns an explicit `CLIPBOARD:` error.

Before sending copy, both platforms reject a clipboard that changed during snapshotting. After copy, if another operation changes it again, the adapter preserves the newer clipboard and returns `CLIPBOARD_CHANGED:` rather than overwriting the newer data. Failed restoration returns `CLIPBOARD_RESTORE_FAILED:`. Clipboard ownership/timestamps and third-party clipboard-manager history cannot be restored. A crash, OS termination, a late copy event or an externally busy clipboard can still interrupt a clipboard transaction; this must be included in manual acceptance testing.

Protected or elevated Windows applications can reject synthetic input; password controls are excluded. Empty selections return `NO_SELECTION:`. Screenshots are held in memory for the Windows selector and written temporarily only for the OCR decoder. Temporary images are removed in `finally`/`defer`, including ordinary cancellation and OCR failures. Forced process/OS termination can bypass cleanup, so do not describe crash cleanup as guaranteed.

An explicitly supported but empty/whitespace Accessibility selected-text attribute or UI Automation `TextPattern` selection returns `NO_SELECTION:` immediately. It does **not** invoke Cmd+C/Ctrl+C, because some editors interpret copy with no selection as copying the whole current line. Only an unavailable/unsupported selection interface uses the clipboard fallback. Such applications can still have app-specific copy behavior, which requires separate compatibility testing.

Windows OCR uses the first supported user-profile language, with an installed-language fallback. This is **not automatic multilingual recognition**. Chinese/English accuracy must be tested with the appropriate Windows OCR language features installed. The diagnostics response lists available recognizer language tags and explains missing-language failures. Oversized regions exceeding `OcrEngine.MaxImageDimension` return an actionable error; they are not silently cropped or downscaled.

## Nonactivating floating window and outside clicks

`show_without_activation(&WebviewWindow)` must be called inside the application's main-thread dispatch. On macOS it sends the existing NSWindow `orderFrontRegardless` without calling `makeKeyAndOrderFront`, `NSApplication.activate`, or Tauri `show()` first. The macOS adapter rejects calls from a non-main thread. On Windows it uses the owned HWND with `ShowWindow(SW_SHOWNOACTIVATE)` and `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOMOVE | SWP_NOSIZE)`. These operations show the floating window while retaining source-app focus. macOS window level is set separately by the application; ordering alone does not change it.

`pointer_state()` reads only the current/recent left/right mouse button activity and current global pointer position. Windows uses `GetAsyncKeyState(VK_LBUTTON/VK_RBUTTON)` (current-state high bit plus a best-effort recent-press low bit) and `GetCursorPos`. macOS uses `CGEventSourceButtonState`, left/right press counters from `CGEventSourceCounterForEventType`, and a temporary `CGEventCreate(NULL)` snapshot with `CGEventGetLocation` and matching `CFRelease`. Atomic previous counts allow it to notice a quick press/release between samples. Only two aggregate press counts are retained in process memory; no coordinates or content are retained. It installs no event tap or hook, posts no input, moves no cursor, requests no Input Monitoring permission, and records no pointer history or content.

**Coordinate contract:** Windows returns physical screen pixels (in the application's DPI-aware context). macOS returns upper-left-origin, global **logical points**, including negative coordinates for displays left/above the primary display. When comparing the macOS pointer to a Tauri window's physical `outer_position`/`outer_size`, multiply **both pointer coordinates by that same window's current `scale_factor()`**. This matches the bundled Tao 0.37.2 macOS implementation, whose `outer_position()` flips the NSWindow frame into top-left logical coordinates then calls `to_physical(window.scale_factor())`. Do not use the primary monitor's scale for a window on another monitor.

The application polls this state only while its floating window is visible and compares against its bounds to hide on an outside press. It must discard the first sample on **each hidden-to-visible transition** to establish a fresh baseline, ignoring counters or Windows recent-press bits from activity while hidden. The return boolean means "currently down or a recent press was observed", rather than strictly "currently held". Windows documents that another application can consume the recent-press low bit, so polling should remain frequent and cannot promise event-hook reliability. Aggregate counters report activity, not the original click location; the coordinates are the current pointer snapshot. Nonactivation, focus retention, quick outside clicks, and mixed-scale/negative-coordinate displays still require real desktop acceptance; the clipboard smoke fixture does not establish those UI behaviors.

## Reproducible noninteractive tests

Run commands from the repository root. None of the self-tests take screenshots, inspect the current selection, request system permissions, or alter the user's general clipboard. The macOS self-test writes only a uniquely named private fixture pasteboard, which is released after testing.

### macOS

The repeatable runner compiles for the current Mac architecture in a temporary directory, runs the fixture suite, and removes the standalone executable afterward:

```sh
bash tests/macos-native-self-test.sh
```

To keep a CLI for additional local diagnostics, compile it explicitly:

```sh
mkdir -p work/native-check
swiftc src-tauri/native/macos.swift -parse-as-library -O -target arm64-apple-macosx12.0 \
  -framework AppKit -framework Vision -framework ApplicationServices -framework CoreText \
  -o work/native-check/echolingo-native-helper
work/native-check/echolingo-native-helper --diagnostics
work/native-check/echolingo-native-helper --self-test
```

Use `x86_64-apple-macosx12.0` on Intel. This optional CLI is only a standalone development self-test; the installed app does not execute it. `build.rs` chooses the Rust target architecture automatically, so CI can build Intel and Apple Silicon independently. The self-test draws `EchoLingo translation 2468` into an in-memory CoreText image, runs the real Vision recognizer, and requires the app name and digits to be recognized. It also checks the generated PNG's base64 roundtrip (`pngBase64RoundtripPassed`), rejects empty/over-8-MiB encoder input, and accepts the inclusive 8-MiB boundary (`pngSizeGuardsPassed`). The exact boundary case tests the byte limit and encoding, not image decoding.

`privatePasteboardFixturePassed` runs the production `SavedPasteboard` snapshot/restore against a unique private pasteboard. It verifies multiple items and every materialized representation byte-for-byte: Unicode with NUL, UTF-8/UTF-16, HTML, RTF, custom binary and zero-length data. It also checks restoration of an originally empty private pasteboard. This fixture requires the standalone CLI's actual main thread: AppKit may synchronously fulfill a synthesized clipboard-format promise and warns when asked to do so on a background thread. A Rust unit-test worker has no active main event loop, so its static-entry self-test deliberately reports `privatePasteboardFixturePassed: false` / `privatePasteboardFixtureSkipped: true` and still runs OCR, geometry, PNG and ABI checks. Use the shell runner to obtain the private pasteboard pass; no synchronous main-thread dispatch is attempted from a worker.

`generalClipboardTouched: false` and `interactiveCaptureTested: false` explicitly mark the boundary: this is no evidence of real Cmd+C injection, source-app compatibility, clipboard races or TCC grants. Paragraph fixtures verify spacing/column reset, scale invariance, original ordering, lists, fenced code, invalid/zero geometry and empty input.

Rust tests additionally call the same statically linked entry point used by the app, verify the process identity and read-only permission status, and reject unknown permission kinds. These tests never invoke the grant/request path. `ocrFixturePassed: true` confirms the OCR path, not interactive selection, permissions, or shortcut registration.

### Windows PowerShell 5.1

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File src-tauri/native/windows.ps1 -Mode diagnostics
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File src-tauri/native/windows.ps1 -Mode self-test
```

`diagnostics` compiles the actual C# helper against the system WinForms/UI Automation assemblies and enumerates installed OCR languages. `self-test` additionally renders an English PNG fixture, decodes it through WinRT, runs the installed real OCR engine and verifies `2468`. It also checks a PNG base64 roundtrip using the same encoder as `capture-image`. The temporary fixture is removed afterward. These commands can run in Windows CI without an interactive desktop; if the runner has no OCR language installed, self-test returns `OCR_LANGUAGE_MISSING:` and should not be reported as an OCR pass.

The Rust protocol and pointer-query tests are included in `cargo test --manifest-path src-tauri/Cargo.toml`. They check Unicode JSON, the cancellation prefix, unsuccessful exit status, malformed helper responses, and a real read-only native pointer query with finite coordinates. The pointer test logs no coordinates and synthesizes no input. Full Rust/Tauri build results are recorded by the main application validation workflow.

### Windows desktop integration smoke test

Run this separately on an **unlocked, dedicated Windows test desktop**. It creates its own temporary WinForms fixture and temporarily seeds that desktop's clipboard. It is suitable for a CI runner with an interactive session, rather than a session-0 Windows service. Avoid running it while someone is using that desktop's clipboard.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-native-smoke.ps1
```

The default helper path is resolved inside the script body for Windows PowerShell 5.1 compatibility. It uses the smoke script's own directory, so it does not depend on the current working directory; `-HelperPath C:\absolute\path\windows.ps1` can override it explicitly. A missing/unresolvable script location is a failing diagnostic, not a skipped test.

The script keeps a live WinForms message loop while a separate STA test thread invokes the actual native helper in child processes. It checks:

- Exact Unicode copy/read roundtrip through UTF-8 stdin and JSON, including Chinese, Japanese, newlines, quotes, backticks, dollar signs and shell metacharacters.
- Capture of a known selection in its own foreground TextBox, retaining seeded Unicode text, HTML and RTF clipboard formats.
- An empty selection in that TextBox must return `NO_SELECTION:` and retain all seeded clipboard formats.
- A dedicated selectable control without a text-selection provider that handles Ctrl+C. A counter must observe exactly one real injected copy, and all three seeded clipboard representations must be restored afterward. This checks the actual fallback, rather than inferring fallback coverage from the normal TextBox case.
- A selected password TextBox must return `PROTECTED:` and leave the seeded clipboard unchanged.

Before any clipboard mutation the test snapshots all original formats it can materialize. Unsupported original formats cause a failure before the clipboard is changed. Normal success, assertion failure and child-process timeout all run cleanup that restores the original clipboard, disposes saved resources, and closes the fixture window. Each child has a 60-second timeout; the fixture has a 180-second overall watchdog. Forced termination of the test process or OS can still bypass `finally`.

The output is one JSON object with `ok`, the individual `passed` checks, `inputDesktop`, `sessionId` and `clipboardRestored`. A locked/noninteractive desktop, denied foreground focus, helper compilation failure or failed assertion returns a diagnostic and a nonzero process exit; there is **no silent skip**. Foreground is checked both before and after each helper selection operation. A passing result establishes native helper behavior against this controlled WinForms fixture only. The report explicitly sets `screenshotsTested`, `multiMonitorTested` and `globalShortcutRegistrationTested` to `false`.

This smoke test does not press the application's registered global shortcuts, drive the screenshot selector, test cancellation/Escape, emulate mixed DPI or establish compatibility with browsers/Office/PDF viewers. Those cases remain in the manual acceptance matrix. The script was authored on macOS and requires a successful Windows execution before any integration pass is claimed.

## Evidence from the development machine

On 2026-10-24, this module was compiled locally with Apple Swift 6.4, targeting **arm64 macOS 12.0**, and `--self-test` passed. The real Vision output was exactly `EchoLingo translation 2468`. `--diagnostics` enumerated English, Simplified/Traditional Chinese, Japanese and other supported OCR languages; it reported one Retina display (1710 × 1107 points at scale 2), Screen Recording available, and Accessibility not granted to that test helper. No interactive capture or clipboard operation was performed while building this module.

The complete macOS Rust/Tauri `cargo check --manifest-path src-tauri/Cargo.toml` also passed with Rust 1.99.1, including `build.rs`, the embedded Swift executable and the native adapter. A temporary command-line crates registry mirror was used because the default crates.io connection timed out; this did not modify the user's global Cargo configuration or change package checksums. `cargo check` confirms compilation, not runtime shortcuts or screenshot interactions.

Windows code was initially authored and reviewed on macOS, which has no Windows PowerShell/.NET Framework/WinRT execution environment. Treat Windows runtime, packaged application behavior, UI Automation coverage and DPI behavior as unverified until the Windows CI and manual cases below have actually passed. Do not infer those passes from the macOS OCR test.

## Required interactive acceptance before a stable release

Record OS build, application version, permissions, installed OCR languages, display scale and the result for each case.

| Case | Expected result |
| --- | --- |
| Global selection shortcut in browser, Notepad/TextEdit, VS Code, Word and a PDF viewer | Captures the source selection before app activation; no unexpected keystrokes |
| UI Automation/Accessibility unavailable, protected app, no selected text | Blank popup without an error toast or autofocus; permission status remains available in Settings; a clipboard restoration failure still warns |
| Preexisting rich HTML/RTF, image, file list, empty clipboard and unsupported custom format | Existing formats restore, or fallback aborts before changing the clipboard |
| A separate application copies while capture is running | Newer clipboard preserved and a clear retry error returned |
| English, Chinese, mixed-language, small-font and dark-background OCR | Readable output with installed-language limitations documented |
| Windows 100%, 125%, 150%, 200%; monitors at mixed scale; monitor left/above primary | Rectangle and recognized crop match selected physical pixels |
| macOS Retina and non-Retina, two displays, display to left of primary | Native selector and OCR match the selected area |
| Escape, right click, sub-3-pixel crop, 120-second timeout | Clean cancellation; no blank result or leftover temporary image |
| Denied/revoked macOS Accessibility or Screen Recording | Shortcut never requests system permission; Settings provides explicit grant/open/refresh actions and remains recoverable after OS changes |
| Empty-selection shortcut, inactive always-on-top float, typing in source, outside click, pinned retention | Empty source remains empty; showing float preserves source focus; outside press hides unless retention is enabled |
| Explicit third-party OCR provider selected; local provider selected; oversized image | Only the selected API receives a screenshot; local OCR sends none; PNGs over 8 MiB fail before upload |
| Repeated shortcuts, text copy containing Unicode, quotes, backticks, dollar signs and newlines | One operation at a time; text preserved exactly and never executed |
| Windows app/PowerShell restrictions, Secure Desktop, remote desktop, elevated app | Unsupported/protected cases fail clearly; normal desktop operation remains usable |
| Signed installer on a clean Windows machine; signed/notarized macOS app outside the dev terminal | OCR and selection work with documented first-launch setup |

## Platform references

- [Microsoft: OCR recognition accepts a SoftwareBitmap](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine.recognizeasync)
- [Microsoft: OCR engine and installed recognizer languages](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine)
- [Microsoft: Windows Runtime async bridge](https://learn.microsoft.com/en-us/dotnet/api/system.windowsruntimesystemextensions)
- [Microsoft: Clipboard data formats and multiple representations](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/advanced/how-to-retrieve-data-from-the-clipboard)
- [Microsoft: Asynchronous mouse-button state](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getasynckeystate)
- [Microsoft: Showing a window without activation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showwindow)
- [Apple: Accessibility selected-text attribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute)
- [Apple: Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- [Apple: CGEvent location](https://developer.apple.com/documentation/coregraphics/cgevent/location)
- [Apple: Aggregate event counters](https://developer.apple.com/documentation/coregraphics/cgeventsource/counterforeventtype%28_%3Aeventtype%3A%29)
- [Apple: Ordering a window without making it key](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless%28%29)
