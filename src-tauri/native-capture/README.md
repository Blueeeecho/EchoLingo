# Native screenshot candidate (Windows)

This isolated Rust child is the Windows screenshot backend by default. Only the
explicit diagnostic opt-out `ECHOLINGO_RUST_CAPTURE=0` selects the legacy helper;
unset or other values use Rust. Default installation validation must remove the
environment override rather than set it to `1`. Only screenshot
selection/capture and local OCR change; selected-text extraction retains the
existing isolated UI Automation/password/clipboard helper. There is no automatic
fallback capture after a native error.

The application embeds the exact build output, extracts a SHA-256-named file into
its existing per-user native cache and verifies its bytes before every launch.
The child receives only an owned cancellation-event name, host thread ID and
random session token. Parent input delegation validates the actual child PID.
The same parent physical-task lock, cancellation, watchdog, presentation epochs,
and capture-exclusion guard remain in force. It does not access clipboard,
credentials, or a network. Existing cloud OCR selection is not changed.

The child owns one Win32 message-pump thread for all visual windows and a separate
bounded Escape-hook pump. Mouse ownership stays in the application hook thread;
child shutdown never clears the parent's owned-button mask. Escape closing and
owned-release are separate from mouse release because the parent does not own
Escape. On error, overlays are hidden before waiting for matching key release;
this wait remains bounded by child and parent watchdogs.

`--self-test` uses only an in-memory GDI bitmap: it checks x64 ABI sizes and exact
fixed-color PNG round-trip. It does not capture the desktop or install hooks.
A green self-test is **not** selection, cross-monitor, or input-lifecycle proof.

Production-mode arguments are exactly `-Mode capture-image`,
`-CaptureHostThreadId`, `-CaptureHostToken`, and `-NativeCancellationEvent`.
Unknown or duplicate options fail closed. Output is one bounded JSON reply with
`nativeBackend: rust-win32-capture`, numeric `captureHealth`, and either a PNG
`imageBase64` or an error. `nativeCaptureBackend: 1` in capture diagnostics proves
this candidate ran. The application's capture `resultOk`/`attemptStage` describe
image acquisition; the subsequent local WinRT OCR can independently fail.

Release acceptance requirements (a configuration change is not evidence of passing): actual Windows linking, fixed-pixel crop and
loupe, transparent plane/edge geometry and Z-order, nonactivation, mixed/negative
monitor geometry, hover, cross-screen drag, cancellation/restart, true display
invalidation/restart in the same app, preheld and owned input, hostile/missing
endpoint, timeout/crash, resource cleanup, local/cloud OCR routing, and same-host
interleaved shortcut-to-first-border measurements against the packaged baseline.

Numeric DPI diagnostics keep the existing policy semantics: `displayExpectedDpi`
and `displayObservedDpi` equal zero when no invalidating window-DPI value was
observed, not when a monitor has zero DPI. `displayObservedCount` and
`displayObservedAwareness` describe the most recent successful topology read;
a later failed read does not fabricate replacement values. These are diagnostic
samples, not an atomic display snapshot.
