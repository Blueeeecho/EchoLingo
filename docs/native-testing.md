# Native selection, clipboard and offline OCR

The native adapter is `src-tauri/src/platform.rs`. Its five public functions are blocking and must run through `tauri::async_runtime::spawn_blocking`. The global-shortcut handler must capture the original application's selection **before** showing or focusing the EchoLingo window. Serialize native operations so two shortcuts cannot run overlapping clipboard transactions or screenshot pickers.

## Implementation and prerequisites

| Platform | Selection | Region capture and offline OCR | Runtime prerequisites |
| --- | --- | --- | --- |
| Windows 10/11 | UI Automation `TextPattern.GetSelection()`, followed by Ctrl+C when necessary | Per-monitor-aware WinForms selector over a desktop `BitBlt` snapshot; built-in `Windows.Media.Ocr` | Built-in Windows PowerShell 5.1, .NET Framework, and at least one installed OCR language. The desktop application also needs WebView2. |
| macOS 12+ | Accessibility selected-text attribute, followed by Cmd+C when necessary | Native `/usr/sbin/screencapture -i -x` region selection; Apple Vision | Accessibility for selection capture; Screen Recording for capture. System OCR needs no model download. |

Both helpers return one UTF-8 JSON object. Errors beginning with `CANCELLED:` are ordinary user cancellation and should not trigger alarming UI. Escape/right click cancel the Windows selector. Escape cancels the native macOS selector. Both selectors time out after 120 seconds. Windows OCR has a separate 30-second operation budget. The Rust process supervisor has a 180-second outer capture limit and a 60-second limit for other modes.

The Windows helper is embedded, extracted under `%LOCALAPPDATA%\EchoLingo\native`, and launched with the system `powershell.exe -NoProfile -NonInteractive -STA`. `-ExecutionPolicy Bypass` applies only to that child process; no persistent policy is changed. Managed computers that prohibit PowerShell may block the helper. User text is sent through UTF-8 stdin, never interpolated into PowerShell or command-line code. The script uses no third-party OCR module and performs no network requests.

The macOS helper is compiled by `build.rs` with Swift and embedded into the Rust executable. It is extracted under `~/Library/Caches/com.echolingo.app/native/echolingo-native-helper`. The directory and executable are restricted to the current user; symlink targets are rejected. The helper never activates the source application or the EchoLingo window. A stable helper path reduces repeated permission prompts, but macOS may still attribute permissions to the helper, the containing app, or the launching terminal. A signed/notarized distribution needs a separate clean-machine TCC and Gatekeeper test; an ad hoc development signature does not establish that result.

## Clipboard guarantees and limits

The direct Accessibility/UI Automation path does not write the clipboard. The copy fallback first materializes all existing clipboard formats, waits for shortcut modifiers to be released, sends copy to the foreground application, reads copied text, and restores the saved formats. Text, rich text/HTML, bitmaps, file lists, byte arrays and seekable streams are handled by the Windows adapter. macOS snapshots each pasteboard item's data representations. If any representation cannot be captured safely, fallback stops **before** changing the clipboard and returns an explicit `CLIPBOARD:` error.

Before sending copy, both platforms reject a clipboard that changed during snapshotting. After copy, if another operation changes it again, the adapter preserves the newer clipboard and returns `CLIPBOARD_CHANGED:` rather than overwriting the newer data. Failed restoration returns `CLIPBOARD_RESTORE_FAILED:`. Clipboard ownership/timestamps and third-party clipboard-manager history cannot be restored. A crash, OS termination, a late copy event or an externally busy clipboard can still interrupt a clipboard transaction; this must be included in manual acceptance testing.

Protected or elevated Windows applications can reject synthetic input; password controls are excluded. Empty selections return `NO_SELECTION:`. Screenshots are held in memory for the Windows selector and written temporarily only for the OCR decoder. Temporary images are removed in `finally`/`defer`, including ordinary cancellation and OCR failures. Forced process/OS termination can bypass cleanup, so do not describe crash cleanup as guaranteed.

Windows OCR uses the first supported user-profile language, with an installed-language fallback. This is **not automatic multilingual recognition**. Chinese/English accuracy must be tested with the appropriate Windows OCR language features installed. The diagnostics response lists available recognizer language tags and explains missing-language failures. Oversized regions exceeding `OcrEngine.MaxImageDimension` return an actionable error; they are not silently cropped or downscaled.

## Reproducible noninteractive tests

Run commands from the repository root. None of the self-tests take screenshots, inspect the current selection, or alter the clipboard.

### macOS

```sh
mkdir -p work/native-check
swiftc src-tauri/native/macos.swift -O -target arm64-apple-macosx12.0 \
  -framework AppKit -framework Vision -framework ApplicationServices -framework CoreText \
  -o work/native-check/echolingo-native-helper
work/native-check/echolingo-native-helper --diagnostics
work/native-check/echolingo-native-helper --self-test
```

Use `x86_64-apple-macosx12.0` on Intel. `build.rs` chooses the Rust target architecture automatically, so CI can build Intel and Apple Silicon independently. The self-test draws `EchoLingo translation 2468` into an in-memory CoreText image, runs the real Vision recognizer, and requires the app name and digits to be recognized. `ocrFixturePassed: true` confirms the OCR path, not interactive selection, permissions, or shortcut registration.

### Windows PowerShell 5.1

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File src-tauri/native/windows.ps1 -Mode diagnostics
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File src-tauri/native/windows.ps1 -Mode self-test
```

`diagnostics` compiles the actual C# helper against the system WinForms/UI Automation assemblies and enumerates installed OCR languages. `self-test` additionally renders an English PNG fixture, decodes it through WinRT, runs the installed real OCR engine and verifies `2468`. The temporary fixture is removed afterward. These commands can run in Windows CI without an interactive desktop; if the runner has no OCR language installed, self-test returns `OCR_LANGUAGE_MISSING:` and should not be reported as an OCR pass.

The Rust protocol test is included in `cargo test --manifest-path src-tauri/Cargo.toml`. It checks Unicode JSON, the cancellation prefix, unsuccessful exit status, and malformed helper responses. Full Rust/Tauri build results are recorded by the main application validation workflow.

## Evidence from the development machine

On 2026-10-24, this module was compiled locally with Apple Swift 6.4, targeting **arm64 macOS 12.0**, and `--self-test` passed. The real Vision output was exactly `EchoLingo translation 2468`. `--diagnostics` enumerated English, Simplified/Traditional Chinese, Japanese and other supported OCR languages; it reported one Retina display (1710 × 1107 points at scale 2), Screen Recording available, and Accessibility not granted to that test helper. No interactive capture or clipboard operation was performed while building this module.

Windows code was initially authored and reviewed on macOS, which has no Windows PowerShell/.NET Framework/WinRT execution environment. Treat Windows runtime, packaged application behavior, UI Automation coverage and DPI behavior as unverified until the Windows CI and manual cases below have actually passed. Do not infer those passes from the macOS OCR test.

## Required interactive acceptance before a stable release

Record OS build, application version, permissions, installed OCR languages, display scale and the result for each case.

| Case | Expected result |
| --- | --- |
| Global selection shortcut in browser, Notepad/TextEdit, VS Code, Word and a PDF viewer | Captures the source selection before app activation; no unexpected keystrokes |
| UI Automation/Accessibility unavailable, protected app, no selected text | Actionable error or deliberate clipboard fallback; source window is not focused by our code |
| Preexisting rich HTML/RTF, image, file list, empty clipboard and unsupported custom format | Existing formats restore, or fallback aborts before changing the clipboard |
| A separate application copies while capture is running | Newer clipboard preserved and a clear retry error returned |
| English, Chinese, mixed-language, small-font and dark-background OCR | Readable output with installed-language limitations documented |
| Windows 100%, 125%, 150%, 200%; monitors at mixed scale; monitor left/above primary | Rectangle and recognized crop match selected physical pixels |
| macOS Retina and non-Retina, two displays, display to left of primary | Native selector and OCR match the selected area |
| Escape, right click, sub-3-pixel crop, 120-second timeout | Clean cancellation; no blank result or leftover temporary image |
| Denied/revoked macOS Accessibility or Screen Recording | Clear permission guidance, recoverable after OS permission changes |
| Repeated shortcuts, text copy containing Unicode, quotes, backticks, dollar signs and newlines | One operation at a time; text preserved exactly and never executed |
| Windows app/PowerShell restrictions, Secure Desktop, remote desktop, elevated app | Unsupported/protected cases fail clearly; normal desktop operation remains usable |
| Signed installer on a clean Windows machine; signed/notarized macOS app outside the dev terminal | OCR and selection work with documented first-launch setup |

## Platform references

- [Microsoft: OCR recognition accepts a SoftwareBitmap](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine.recognizeasync)
- [Microsoft: OCR engine and installed recognizer languages](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine)
- [Microsoft: Windows Runtime async bridge](https://learn.microsoft.com/en-us/dotnet/api/system.windowsruntimesystemextensions)
- [Microsoft: Clipboard data formats and multiple representations](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/advanced/how-to-retrieve-data-from-the-clipboard)
- [Apple: Accessibility selected-text attribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute)
- [Apple: Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
