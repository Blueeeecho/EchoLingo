# In-process Windows OCR tests

Run on an interactive Windows 10/11 worker with an installed English OCR language:

```powershell
cargo test --manifest-path tests/windows-ocr-native/Cargo.toml --locked -- --test-threads=1
```

These execute the production Rust module directly, without Tauri, PowerShell,
WebView, cloud APIs, a screenshot overlay, or an external OCR process. Missing
OCR languages are a failure, not a silently skipped test. The checked-in PNG is
synthetically generated text (`ECHO NATIVE OCR 12345`) on white, not user content.
Checks cover repeated and concurrent real recognition, white-image `NO_TEXT`,
malformed PNG, decoder dimensions before bitmap allocation, byte/pixel caps,
pre-cancel, cancellation during pending async work, deadline, and owned-input
cleanup after a canceled wait. The latter two use synthetic WinRT operations to
make races reproducible. They do not substitute for capture/UI cancellation.

On Linux the same command runs only five pure geometry suites ported from the
existing PowerShell helper. Cross-target `cargo check --tests --target
x86_64-pc-windows-msvc` validates API/type compatibility but does not execute
WinRT and must not be reported as Windows runtime acceptance.

Integration retains the existing latest-intent/epoch delivery gate and service
choice. This module never switches to cloud OCR, captures pixels, or launches a
process. Call `recognize_png` only on a blocking worker. Auto-language selection
keeps the old profile-language then first installed-language order. Runtime
errors contain only a fixed description plus numeric HRESULT. No OCR text,
PNG bytes, filesystem paths, or language list enters a diagnostic log here.

The implementation is independently written against Microsoft Windows APIs;
no Pot source is copied. Pot was inspected solely to confirm its architectural
use of Windows.Media.Ocr rather than subprocess OCR. Official references:

- https://learn.microsoft.com/uwp/api/windows.media.ocr.ocrengine
- https://learn.microsoft.com/uwp/api/windows.graphics.imaging.bitmapdecoder.getsoftwarebitmapasync
- https://learn.microsoft.com/windows/win32/api/combaseapi/nf-combaseapi-coincrementmtausage
- https://github.com/microsoft/windows-rs (pinned windows 0.62.2 / windows-future 0.3.2)

Cancellation requests `IAsyncOperation.Cancel` and returns without closing
active inputs. The completion callback owns input COM references and an MTA
usage cookie until terminal completion, even if the caller has already left.
MTA decrement is valid across threads per the Microsoft contract. UI speedup
must be established separately; OCR-only timing is not hotkey-to-border timing.
