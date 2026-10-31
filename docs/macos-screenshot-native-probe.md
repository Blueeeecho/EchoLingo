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
