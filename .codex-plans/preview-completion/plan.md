# Preview completion

## Goal
Finish actionable remaining preview work and test it, preserving explicit manual/platform/credential boundaries. No stable release until acceptance is complete.

## Phases
- [x] 1. Scope remaining defects and delegate independent changes.
- [x] 2. Implement cancellation, language fidelity and repeatable packaging/verification.
- [ ] 3. Run frontend, Rust, native and installed-app checks; independent review and repairs.
- [ ] 4. Build current packages, consolidate the local app entry, record performance/evidence and update docs.
- [ ] 5. Verify final changes and report achieved work plus externally blocked acceptance.

## Decisions
- Root owns request lifecycle (Rust main + frontend main + UI regression).
- Delegate language protocol fidelity and installation/verification tooling separately.
- Real cloud account tests require credentials configured inside EchoLingo. Do not inspect Bob secrets.
- No Windows interactive pass without Windows execution. Existing remote CI can validate native builds and controlled fixtures.
- Preserve old builds as development artifacts; expose one canonical installed app rather than deleting arbitrary copies.

## Errors
- Initial planning directory did not exist; created it after successful empty catchup. No source changes predated this task.
- Native background test initially warned about AppKit promise fulfillment; native fixture was restricted to CLI main thread, with an explicit worker skip marker. Scoped Rust retest passed without warning.
- First final install attempt safely refused because Tauri's dmg-only build cleans its intermediate .app. DMG succeeded and verified; generated the app bundle separately and clarified the documented build command to retain both.
- One patch context failed after rustfmt; reread the formatted function and applied an adapted patch. No source mutation occurred on the failed patch.
