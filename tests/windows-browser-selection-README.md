# Real Chromium selected-text fixture

Run only on an unlocked, ephemeral GitHub-hosted Windows desktop after `npm ci`
and after building the exact native .NET Framework DLL from the helper source:

```powershell
node tests/windows-browser-selection-smoke.mjs --helper src-tauri/native/windows.ps1 --native-assembly C:\owned-build\EchoLingo.Native.dll
```

The fixture uses the runner's installed Edge, or installed Chrome if Edge is
absent. It downloads no browser. It creates a new marked temporary profile,
launches its own browser process and connects only to that profile's
`DevToolsActivePort`. CDP independently verifies the browser root PID and exact
fresh-profile command line before any page operation. It does not discover or
connect to existing browser profiles or debugging sessions.

Four generated local-page cases invoke the real native `selected-text` helper
once each: body document selection, link focus with a separate document
selection, explicitly empty textarea, and selected textarea. UIA metadata
records actual focused/ancestor PIDs and control types. The helper must preserve
browser foreground and generated Unicode/HTML/RTF clipboard formats. DOM copy
events must be at most one; empty textarea must never copy. Clipboard owner
sampling reads only sequence numbers and owner PIDs; it can miss brief ownership
and does not establish an unobserved copy path. If UIA provides text directly,
`nativeClipboardCopyExercised` is false. No application-specific provider branch
or fake helper response is used.

The page contains only generated fixture text and inline styling/script. Page
requests outside its exact loopback origin are aborted; browser background
networking, sync, updates and extensions are disabled and external DNS resolution
is blocked. This is not a packet-level audit of the browser/OS. No external page,
API, user account, existing clipboard content or existing profile is read.
An initially nonempty clipboard stops setup without reading its data.

Failure/inconclusive always exits nonzero. Missing installed browser, unavailable
foreground/UIA setup or a missing owned debugging endpoint is not acceptance.
Each result says whether setup failed, whether the real browser was reached, and
how many cases executed/passed. Host C# compilation, PS AST and Node syntax checks
are not Windows runtime results. This fixture tests native acquisition against a
fresh Chromium page, not Tauri hotkey dispatch, an installed app, all websites,
all clipboard brokers, physical Windows 10/11 or performance guarantees.

Cleanup requests helper cancellation before bounded hard cleanup of its own
synthetic-data process, closes/kills only fixture-started process trees, and
removes only its marked profile root. Existing browser processes are untouched.
