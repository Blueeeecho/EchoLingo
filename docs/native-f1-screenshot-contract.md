# F1 native screenshot selection

F1 uses `platform::capture_screenshot_cancelable` / `capture-screenshot`.
`capture-image` and `capture-ocr` retain their existing drag-only translation/OCR
purpose. This native endpoint returns a bounded in-memory PNG and invokes no OCR,
clipboard operation, upload, save, or editor itself. The existing PNG limit is
8 MiB; both platforms also retain their approximately 32-megapixel allocation cap.

## Gesture and visible pixels

- Hover eligible external windows with the existing blue, transparent outline.
- Button down retains the exact candidate. Small jitter is a click (four logical
  points/pixels, scaled to the press display's DPI on Windows).
- Once the pointer exceeds that threshold, drag takes precedence even if it
  returns to its starting point. Windows preserves the maximum motion separately
  from coalesced UI updates, using scalar values on the existing input host.
- A window click retains identity and original geometry and revalidates at
  release and around pixel capture. A moved, hidden, closed, protected or
  replaced candidate fails closed, rather than selecting a replacement.
- The result is **visible desktop pixels within the window's bounds**. Other
  windows overlapping those bounds stay in the image. There is no foreground
  activation, isolated/offscreen window rendering, hidden-content reconstruction,
  scrolling, or permission fallback. Offscreen parts are clipped; monitor gaps
  are blank rather than reads from an offscreen window.
- The application's own editor/selector windows are excluded. The previous
  native cleanup, screen-change, cancellation and input ownership guards remain.

Windows uses physical DWM frame bounds, visible/noniconic/uncloaked roots,
HWND/PID/thread identity and capture-affinity checks. A failed affinity query on
a layered candidate is rejected. Ordinary non-layered windows are not rejected
solely because that query fails: Microsoft only documents query success for
layered windows. Capturing still uses the existing OS desktop pixel path; it does
not bypass capture exclusion.

macOS uses public on-screen CG window metadata with ID, owner PID, layer, alpha,
sharing state and bounds; it never needs window titles. Missing sharing metadata
is not treated as permission. Quartz top-left coordinates are converted to
AppKit global points, and the existing mixed-Retina capture planner handles
output pixels. The final image remains a display-region composition, not an
isolated `SCWindow` capture. Existing permission preflight remains mandatory;
F1 does not request or change system permission.

F1's macOS cancellation token is registered before its watcher can cancel it.
Queued presentation and bounded waits observe that request's cancellation;
cleanup cannot cancel a later selector because both token and lifetime are
request-scoped. Existing OCR/selection serialization is retained.

## Verification

Cloud source/contract tests do not establish native GUI or physical-device
acceptance. Required native evidence for this change includes:

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/check-repository.py
cargo test --manifest-path src-tauri/native-capture/Cargo.toml --locked
cargo fmt --manifest-path src-tauri/Cargo.toml --check
bash tests/macos-native-self-test.sh
```

The macOS self-test now requires `screenshotWindowPolicyFixturePassed` and
`screenshotCancellationFixturePassed`. These are generated metadata/state tests,
not actual screen-capture/TCC acceptance.

On an explicitly isolated Windows test desktop, compile the unchanged-production
host harness and run the additive gate:

```powershell
powershell.exe -NoProfile -STA -File tests/windows-screenshot-window-smoke.ps1 `
  -NativeCapturePath <built-native-child.exe> -HarnessPath <built-harness.exe> `
  -IsolatedTestSession
```

All ten generated-window cases must pass: click, click jitter, rectangle drag,
coalesced out-and-back drag, changed geometry, hidden target, newly protected
target, visible overlap preservation, Escape, and next request after cancel.
The fixture checks exact PNG dimensions, excludes blue hint pixels, verifies
zero underlying mouse delivery, and does not log PNG bytes. It is **additional**
to the existing native/legacy input and magnifier gates; none are relaxed.

Actual Windows/macOS F1 shortcut-to-editor acceptance, macOS permissions and
physical multi-monitor/mixed-DPI behavior remain separate native acceptance
checks; no actual user's desktop is used by these fixtures.

The generated Windows peers stage their background below both source windows
after the initial WinForms `Shown` handler returns. Before any generated input or
native capture, a bounded read-only wait requires three consecutive exact A/B
root hit tests with unchanged frames and A foreground. It never retries input or
reorders during observation. Failure reports retain only generated-window handle
and boolean hit diagnostics; an obscured endpoint still fails the case.

## Primary API references

- [Microsoft: GetWindowRect](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect)
  distinguishes DPI-virtualized window rectangles from physical DWM extended
  frame bounds and invisible resize borders.
- [Microsoft: DWM window attributes](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute)
  documents extended frames and cloak state.
- [Microsoft: GetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowdisplayaffinity)
  documents supported query conditions and limitations; this is not a DRM bypass.
- [Microsoft: Control.BeginInvoke](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.control.begininvoke)
  documents asynchronous dispatch to the generated source's own UI thread.
- [Microsoft: SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)
  defines the explicit peer/background ordering used only by the fixture.
- [Apple: kCGWindowBounds](https://developer.apple.com/documentation/coregraphics/kcgwindowbounds?language=objc)
  defines main-display upper-left screen coordinates.
- [Apple: CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
  is the public metadata query used by the selector.
- [Apple: Advances in macOS Security, WWDC19](https://developer.apple.com/videos/play/wwdc2019/701/)
  explains that sharing state can be withheld without screen-recording approval
  and that the metadata query itself does not prompt.
- [Apple: display filter excluding windows](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:excludingwindows:))
  is the existing ScreenCaptureKit composition path, excluding this app's windows.
