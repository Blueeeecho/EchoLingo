# Real Chromium native selection matrix

Run only on an unlocked, ephemeral GitHub-hosted Windows desktop after `npm ci`
and after building the exact native .NET Framework DLL from the helper source:

```powershell
node tests/windows-browser-selection-smoke.mjs --helper src-tauri/native/windows.ps1 --native-assembly C:\owned-build\EchoLingo.Native.dll
```

Both installed Edge and installed Chrome are tested when found in standard
Program Files locations. An unavailable browser is explicitly listed; it is not
counted as accepted. No browser is downloaded. Each browser gets three rounds,
each with a freshly launched browser, new marked profile and new bridge process.
This is a fresh-process/profile test, not an OS cold-boot benchmark.

Each round has eight predeclared cases: English body text selected with actual
`page.mouse` down/drag/up, Chinese body punctuation, selected document text while
a link is focused, selected textarea, English and Chinese contenteditable,
explicitly empty textarea, and selected generated password input. Case text is
distinct per browser/round. The mouse case derives start/end coordinates from
first/last generated text-character rectangles and requires exact DOM selection;
a failed drag is never repaired with programmatic selection. Other cases use DOM
selection to create the required focus topology and say so in their result.

The first acquisition occurs before any fixture UIA call and without
`--force-renderer-accessibility` or an accessibility warm-up. CDP verifies the
spawned root PID and exact fresh-profile command line, then Win32 verifies the
same owned executable, unique initial root HWND and actual foreground. Subsequent
cases require that same HWND/PID/thread/class/owner/root/style-kind/visible
identity; they never choose a different Chromium popup. The production helper's
own UIA identity, password and selection checks remain intact.

Every case invokes the exact production `selected-text` helper once. Its actual
exit, error prefix, explicit production UIA-deadline error, expected-result match,
clipboard and foreground outcome are retained. A separate UIA audit runs only
**after** the helper; it still has a 2000ms total deadline. It batches properties
with CacheRequest and makes one parent traversal call per level, records MTA
worker entry/FocusedElement/cache/runtime-ID stages and parent depth/start/end
measurements, and verifies source-root/password identity. The owning STA pumps
its generated OLE clipboard window during bounded waits. Acquisition failure and
post-helper-audit failure are separate fields. Audit success cannot turn a failed
first acquisition into a pass. Production still has 2000ms per SelectionQuery,
not a 2000ms limit for its complete multi-query workflow.

The helper is invoked with explicit performance diagnostics. Only the numeric
whitelist of up to 16 query durations, last stages/depths and three startup/reply
phases is retained. Stage numbers are 1 worker entered, 2 focused-element/cache
query, 3 runtime identity, 4 cached ancestor validation, 5 cached parent query,
6 TextPattern query, 7 GetSelection, 8 GetText, and 9 completed focus validation.
No accessibility warm-up or timeout/retry change accompanies these diagnostics.

A failed case keeps the overall result false. Only after generated clipboard
restoration, foreground and responsive audit are confirmed can the fixture
continue to the next predeclared distinct case; this is never a retry of the
failed helper. Unsafe cleanup, identity failure or unresponsive audit stops that
round, leaves remaining cases unexecuted, and still exits nonzero. Exact selected
text and zero copy events for empty/password controls are required. Positive
cases permit at most one DOM copy event. Unicode/HTML/RTF generated clipboard
formats must survive. An initially nonempty clipboard stops setup without
reading its data. Owner sampling reads only sequence numbers/PIDs, can miss brief
ownership, and is not proof of a clipboard fallback when direct UIA suffices.

All content is generated in an owned loopback page. Page requests outside that
origin are aborted; background networking/sync/updates/extensions are disabled
and external DNS resolution is blocked. This is not a packet-level browser/OS
network audit. Existing profiles, browser sessions, user text, credentials and
APIs are not read. Only owned process trees/profile roots are cleaned up.

Previous evidence is retained separately: run40533405895 passed one body case,
then failed root enumeration before its second helper; candidate counts were
not recorded, so zero versus multiple roots remains unknown. Run40535344819 had
a bound foreground root but timed out in the old pre-helper UIA metadata probe;
zero helpers ran. That probe both added RPC work and pre-warmed successful
subsequent helper calls. Its cause is unresolved and may be relevant to the
production two-second UIA budget; it is not dismissed as unrelated.

C#5/net48 compile, PS AST and Node syntax are host checks, not Windows acceptance.
This matrix tests direct native acquisition against installed Chromium. It does
not exercise Alt+D registration/Tauri delivery, installation, every website,
clipboard broker, WPS or physical Windows 10/11. Those require separate tests.

Microsoft UIA threading guidance:
https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-threading
