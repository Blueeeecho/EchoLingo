# Real Chromium native selection matrix

Run only on an unlocked, ephemeral GitHub-hosted Windows desktop after `npm ci`
and after building the exact native .NET Framework DLL from the helper source:

```powershell
node tests/windows-browser-selection-smoke.mjs --helper src-tauri/native/windows.ps1 --native-assembly C:\owned-build\EchoLingo.Native.dll
```

Both Edge and Chrome must be installed in standard Program Files locations.
An unavailable browser is explicitly listed and fails setup; a single-browser
24-case run cannot pass this matrix. No browser is downloaded. Each browser gets three rounds,
each with a freshly launched browser, new marked profile and new bridge process.
This is a fresh-process/profile test, not an OS cold-boot benchmark.

`--browser-order edge-first|chrome-first` selects the order of the installed
browsers; the default is `edge-first`. The report records the requested order
and the actual order of attempted browser groups. CI runs both orders on two
independent `windows-latest` runners, each requiring 48 cases across both
browsers. The complete two-runner matrix requires 96 cases, with separate raw
artifacts and a failure gate for each order. This isolates the prior browser
group's influence within a job; it does not prove the OS UIA service was untouched
before the job or establish that first cold acquisition is repaired.

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
first acquisition into a pass. The previous 2000ms-per-query results remain
failures. Production now explicitly gives one SelectedText call a shared
5000ms monotonic budget from its entry, including time spent between its UIA
queries. A query receives the remaining session time; it does not reset the
budget or retain the old independent 2000ms cap. Completion returns immediately.
The isolated scalar worker fixture, which has no SelectedText session, retains
its 2000ms infrastructure timeout; that is not the product acquisition contract.
The shared deadline rejects new provider/input work and late results. It is
separate from latest-intent cancellation. Once copy input has been emitted,
its bounded completion and required clipboard restoration run before the
deadline/source is checked again; restoration warnings take precedence.
This is not a promise that helper startup or uninterruptible OLE/cleanup always
finishes within 5000ms. The contract change must pass a new real matrix and
cannot convert an old timeout, diagnostic drain or altered-DLL measurement
into a historical pass.

The helper is invoked with explicit performance diagnostics. Only the numeric
whitelist of up to 16 query durations, last stages/depths and three startup/reply
phases is retained. Stage numbers are 1 worker entered, 2 focused-element/cache
query, 3 runtime identity, 4 cached ancestor validation, 5 cached parent query,
6 TextPattern query, 7 GetSelection, 8 GetText, 9 completed focus validation,
10 GetRuntimeId returned, 11 identity mismatch, 12 missing native root,
13 ancestor belongs to another root, 14 ancestry limit, 15 ancestry ended,
16 protected ancestor, 17 missing runtime identity, 18/19 foreground changed
before/after validation, and 20 diagnostic cached-role read. Initial/fresh
ControlType IDs and identity lengths, plus identity-compared/equal flags,
distinguish provider failures from a confirmed mismatch without retaining IDs.
Root-walk reason is 0 not reached, 1 complete, 2 no root, 3 other root, 4 depth
limit, 5 ended, 6 password. Exception kind is 0 none observed, 1 unavailable
element, 2 cancellation, 3 argument, 4 COM, 5 invalid operation, 6 other. These
are numeric enums, never exception messages, runtime IDs, names or content.
Stage 21 means the single ordinary FocusedElement returned, 22 the same-element
cache update started, and 23 that cache update returned. An active-query check
between these calls prevents a late focus reply from starting another RPC.
Only an explicit diagnostic query that already failed its applicable deadline
may conditionally observe that same abandoned task for up to 3000ms.
The task is poisoned first; cancellation ends the observation immediately.
No late result is consumed and no request is retried. Original query duration,
failure stage and exception enum stay frozen at failure. Separate numeric drain
fields report observation duration, whether the worker finished, its stage and
exception category at observation end. WorkerCompletionObservedMilliseconds is
the caller's observation time (5ms polling), not a naturally completed selection
or an acceptance pass. Non-diagnostic calls receive no added observation wait.
An optional observation failure is recorded only as DrainObservationError=1;
it cannot replace the original deadline exception. Normal cancellation checks
outside this diagnostic observation retain their original behavior.
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

## Initial source-data eligibility diagnostic (after f65 candidate)

A subsequent diagnostic-only Q1 probe in immutable commit c9bc277, enabled solely by PerformanceDiagnostics,
reads from the first already validated focus ancestor chain. It never accepts a
changed focus or seeds an anchor later. It checks for the nearest existing
Document, nonempty raw selected ranges and a strictly Boolean true read-only
attribute, with at most16 ranges and strictly less than65536 UTF-16 characters.
Only nine numeric outcomes are reported; text and runtime IDs remain private to
that invocation. Extra provider calls can change timing, so a passing diagnostic
run is not evidence that the frozen f65 candidate or normal path was repaired.
No initial Document/A means no basis for a later anchor exception.

Actual diagnostic run40562621965/source c9bc277 executed both independent
orders:94/96 expectations passed, each order47/48. Both first-tested helpers
started on Pane with no Document in the original validated ancestor chain;
neither had an initial anchor and neither exhausted its budget. Of84 probes,
82 had an unsupported initial role and2 had no ancestor Document;12 password
cases were correctly rejected before probing. This rejects the proposed
initial-Document-anchor path for these observed failures. It does not prove
that the platform has no other solution, or modify the frozen f65 candidate.
After this negative prerequisite check, helper and bridge were restored exactly
to f65; the probe is not retained in the production path. The immutable diagnostic
commit and raw run preserve its source and observations.
