# Preview completion

## Goal
Finish actionable remaining preview work and test it, preserving explicit manual/platform/credential boundaries. No stable release until acceptance is complete.

## Phases

### Phase 1: Scope and delegation
**Status:** complete
Read durable project evidence, identified actionable defects, delegated separate implementation/review tasks.

### Phase 2: Implementation and regression repairs
**Status:** complete
Cancellation/presentation lifecycle, Chinese script fidelity, safe installer, storage and native fixtures implemented; independent findings repaired.

### Phase 3: Validation and review
**Status:** complete
Local 50 Rust / 45 frontend / full UI / 22 installer fixtures passed. Current CI passed all three jobs: Windows49Rust including exclusive file locking, Mac50Rust, native fixtures, Python and UI. PR1/run40172215129 tested the identical source tree.

### Phase 4: Packaging and evidence
**Status:** complete
Verified local app/DMG installed at canonical path; silent startup and constrained performance measured. Current Windows installer downloaded, artifact ZIP digest matched GitHub and PE header verified. Draft preview release now contains both installer assets and checksums; interactive/TCC/live-account limits remain explicit.

### Phase 5: Final handoff
**Status:** complete
CI outcome and exact source tree are recorded. Both packages and draft-release digests verified; durable handoff finalized with external acceptance explicitly left open.

## Decisions
- Root owns request lifecycle (Rust main + frontend main + UI regression).
- Delegate language protocol fidelity and installation/verification tooling separately.
- Real cloud account tests require credentials configured inside EchoLingo. Do not inspect Bob secrets.
- No Windows interactive pass without Windows execution. Existing remote CI can validate native builds and controlled fixtures.
- Preserve old builds as development artifacts; expose one canonical installed app rather than deleting arbitrary copies.

## Errors
- Initial planning directory did not exist; created it after successful empty catchup. No source changes predated this task.
- Native background test initially warned about AppKit promise fulfillment; native fixture was restricted to CLI main thread, with an explicit worker skip marker. Scoped Rust retest passed without warning.
- Git HTTPS push failed with HTTP2 framing; synced the exact tree through GitHub API, verified identical tree hash and aligned local/remote commit metadata. Artifact connector failed and gh download timed out; HTTP1 download resumed the partial ZIP and its digest matched GitHub.
- First final install attempt safely refused because Tauri's dmg-only build cleans its intermediate .app. DMG succeeded and verified; generated the app bundle separately and clarified the documented build command to retain both.
- One patch context failed after rustfmt; reread the formatted function and applied an adapted patch. No source mutation occurred on the failed patch.

## External acceptance left open
Real supplier credentials, installed-app IME/TCC/selection/capture, Windows multi-screen/target-app/install/uninstall and cold OCR outlier need their stated environments. Completion of this actionable hardening task must not mark those tests passed or permit a stable release.
