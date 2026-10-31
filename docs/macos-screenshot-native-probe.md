# macOS F1 native runtime coverage probe

Run only on an explicitly isolated CI/test desktop:

```sh
bash tests/macos-screenshot-native-fixture.sh /absolute/probe-output --isolated-test-session
```

The shell builds a fixture linked to the exact production `macos.swift`,
`macos_capture.swift` and `macos_window.swift`, using `ECHOLINGO_LIBRARY`.
It preserves `compile.log` and `report.json`, including source and fixture binary
SHA-256 values. It does not modify the application or permission configuration.

## Evidence and boundaries

TCC-independent checks execute first:

- Generated in-memory PNG/JPEG serialization, file save/read/decode inside the
  fixture's private temporary directory.
- Actual **private named pasteboard** PNG/NSImage roundtrip; never the general
  clipboard, and **not** the Rust `arboard` backend.
- Actual native `NSSavePanel` sheet visibility and cancellation, checking that no
  target file was written; this is not the packaged Rust save-dialog flow.

The real capture probe then calls `CGPreflightScreenCaptureAccess`. If false,
it records **blocked**, captures no screen, and exits **2**. No permission request,
automatic TCC grant, accessibility grant or security-setting modification occurs.
A blocked capture is not a passed or skipped capture test. A native failure exits
**1**; only complete evidence exits **0**. CI should preserve and surface this
coverage probe's outcome, not convert a permission block into release acceptance.

If preapproved, it launches exactly one separate generated `NSWindow` process.
Before capture and after each result, it verifies that process's known PID,
window ID, frame, visibility and sharing metadata, and refuses to proceed when
an unrelated foreground window intersects its bounds. The generated source
must first satisfy that same exact public WindowServer predicate within a bounded
two-second readiness wait; AppKit `makeKeyAndOrderFront`/`displayIfNeeded` alone
are not treated as readiness. This wait performs no input or capture and is used
only before the first case. Later revalidations remain immediate fail-closed.
Failure diagnostics project only the exact generated PID/window's numeric frame,
layer, alpha, sharing and visibility fields. If a foreground window obstructs
the generated source, its numeric PID/window ID, layer/alpha and bounds are
recorded to diagnose the refusal, never titles, record descriptions or pixels.
The same single obstructing PID's public `NSRunningApplication` bundle identifier
and executable URL are recorded when available, solely to diagnose its owner.
No other processes, command-line arguments, environment or window names are read.
The fixture explicitly confirms its canceled save panel and owner are hidden
before starting capture. Only the generated source uses `orderFrontRegardless`
to stage itself at the front of the normal window level; no foreign window is
hidden, closed, or exempted from the occlusion guard.
The generated source
places the cursor inside itself using the public non-event-generating cursor
position API, then restores its original position on exit. All mouse-button and
Escape events **used for capture cases** go only through the fixture application's
own AppKit dispatcher. The earlier one-shot hosted-CI Escape did not clear the
observed Dock rectangle; it is no longer dispatched. The global-setup report
fields remain explicitly false/zero.

### Independent hosted-CI visibility diagnostic

Only with both `GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=github-hosted`, a failed
geometric visibility precondition may run a separate ScreenCaptureKit **display**
composite oracle. Existing screen-recording preflight must remain granted. It
captures exactly the generated 512×320 logical-point ROI, with its measured
backing scale and no smaller crop stretched into that size. **No windows are
excluded**, and no isolated/backing-window capture or production capture helper is
used. Every pixel must match the generated phase color and spatial fiducials.

The oracle runs before selector creation, never while own blue outlines/loupe are
visible. It verifies source PID/window/frame/sharing, display ID/frame and scale
before and after each asynchronous image, has bounded timeouts, and discards late
callbacks. Every intersecting nonzero/unknown-alpha window above the source must
have explicit sharing1/2 before and after the read; protected/unknown-sharing
covers fail rather than letting OS omission masquerade as transparency. The
successful guard and intersecting shared-overlay count are recorded numerically.
A generated normal-level magenta occluder must appear in exactly its
known 64×64 region and must fail the unobstructed-source comparison; closing it
must restore the complete original pixel pattern. No window is raised above the
Dock or security UI. Any unexpected pixel/identity or unavailable API fails.

A failed bounded visibility read may transiently contain non-generated pixels
from that ROI on this disposable CI desktop. Images and normalized pixels stay
in memory only, are discarded immediately, and are never written, logged,
returned or retained in artifacts. Only scalar match outcomes survive.

The source-point OS mouse-down hit ID and unmodified production hover-candidate
ID are then reported separately. A positive visibility oracle only starts the
**real unmodified native picker**; it never injects a candidate or satisfies any
of the five capture cases. If production hover still rejects the source, the
probe remains failed. This diagnostic is not a Dock whitelist or a product-policy
change and does not claim all five cases have executed.

When the independent pixel route is used, every native case gets a new complete
current-phase display-composite proof immediately before selector creation and
again after its cleanup, including cancellation cases. While the selector is
visible, the fixture checks the exact live source identity, authoritative hit,
and all intersecting foreign sharing metadata; only exact owned selector panels
are exempt from that metadata guard. It does not run the no-exclusion pixel
oracle through its own blue outline/loupe. Final native PNG pixel checks are
unchanged, and phase2 must independently show the newly generated red pixels.
The production hit-policy negative vectors run before any native capture probe.

Five ordered cases call the production `capture-screenshot` endpoint:

1. Click the visible generated green window.
2. Drag a rectangle within that green window.
3. Cancel through an owned AppKit Escape event.
4. Cancel through the actual request-token endpoint.
5. Capture the same window after it repaints red, proving fresh pixels and reentry.

The probe verifies exact image dimensions and every PNG pixel against the
current generated color and fiducials, catching blue outlines, loupe plates, old frames and
unexpected desktop pixels. Cancel cases must return no image. Every case requires
no remaining visible capture panels and exact source revalidation. Reports contain
only scalar metadata, never PNG/base64/pixel content. The owned source must exit
cleanly, including restoring its cursor position.

**Not established:** physical/global F1 registration, packaged Tauri editor,
Rust `arboard`, packaged save-dialog behavior, physical multi-display/mixed-DPI
or runtime monitor-gap composition. Those remain separately required acceptance
evidence. The existing memory metadata/geometry tests still cover synthetic
negative coordinates, Retina planning and invalid targets; this runtime probe
does not re-label those as physical-display tests.

## Primary API references

- [Apple: local event monitors](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:))
  documents dispatch through the application's `sendEvent` path.
- [Apple: controlling the mouse cursor](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/MouseCursor.html)
  states that cursor positioning does not generate a mouse event; the generated
  source performs it while it owns foreground.
- [Apple: screen-capture preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())
  is the permission check; missing window metadata is not used to infer consent.
- [Apple: native bitmap serialization](https://developer.apple.com/documentation/appkit/nsbitmapimagerep/representation(using:properties:))
  describes image representations suitable for file/decode roundtrips.
- [Apple: deferred window display](https://developer.apple.com/documentation/appkit/nswindow/displayifneeded())
  describes AppKit's event-loop display behavior; source readiness is established
  by fresh public window metadata rather than a fixed rendering delay.
- [Apple: window sharing metadata](https://developer.apple.com/documentation/coregraphics/kcgwindowsharingstate)
  specifies its numeric representation; diagnostics retain the strict production
  parser and expose numeric/Boolean type mismatches without accepting them.
- [Apple: save-panel completion](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:))
  notes that the sheet may remain onscreen in its completion callback and must
  be explicitly ordered out before showing another window.
- [Apple: ordering cooperating windows](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless())
  documents front ordering for cooperating processes without changing the window
  level; this is fixture staging, not production capture behavior.
- [Apple: running-application identity](https://developer.apple.com/documentation/appkit/nsrunningapplication)
  provides the exact-PID bundle and executable metadata for obstruction diagnostics;
  identifying a system owner never exempts its window from the capture guard.
- [Apple: ScreenCaptureKit display filters](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:excludingwindows:))
  defines the independent composite oracle; its exclusion array is empty.
- [Apple: actual window hit-testing](https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:))
  skips point transparency and mouse-ignoring windows. Hit testing is reported
  independently, never used alone as proof of visible pixel contents.
