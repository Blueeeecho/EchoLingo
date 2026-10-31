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
The fixture explicitly confirms its canceled save panel and owner are hidden
before starting capture. Only the generated source uses `orderFrontRegardless`
to stage itself at the front of the normal window level; no foreign window is
hidden, closed, or exempted from the occlusion guard.
The generated source
places the cursor inside itself using the public non-event-generating cursor
position API, then restores its original position on exit. All mouse-button and
Escape events go only through the fixture application's own AppKit dispatcher;
there is no system-wide key/button injection or Accessibility automation.

Five ordered cases call the production `capture-screenshot` endpoint:

1. Click the visible generated green window.
2. Drag a rectangle within that green window.
3. Cancel through an owned AppKit Escape event.
4. Cancel through the actual request-token endpoint.
5. Capture the same window after it repaints red, proving fresh pixels and reentry.

The probe verifies exact image dimensions and every PNG pixel against the
current generated color, catching blue outlines, loupe plates, old frames and
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
