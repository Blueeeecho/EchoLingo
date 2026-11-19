# Bounded Windows first-failure investigation

Base: `15dd281bb8379f9bb6e211770ce123833b6252f9`. Public 0.2.21 stays blocked.
This is diagnostic instrumentation, not an established root-cause fix.

`ECHOLINGO_CAPTURE_DIAGNOSTICS=1` enables fixed scalar observations for a native
capture session; default is off. No file logging, clipboard content, coordinates,
application names, IDs or global hooks are added. The existing isolated fixture
retains its existing generated-window reports. No timeout or input retry changes.

Child first-failure/cleanup reason: 0 none, 1 PostThreadMessage failed (immediate
Win32 error), 2 READY deadline, 3 ACK deadline, 4 negative STOP_ACK, 5 FAILURE,
6 negative PING_ACK, 7 STOP unconfirmed during cleanup. First error and cleanup
error are independent, and later failures cannot overwrite either first record.
Wire-event bits: READY sent 1, ARM sent 2, STOP sent 4, READY_ACK 8, ARM_ACK 16,
STOP_ACK 32, FAILURE 64, PING_ACK 128. These are observations, not proof of cause.
Parent READY bits: received 1, closing 2, refresh incomplete 4, child unbound 8,
window query failed 16, endpoint mismatch 32, ACK sent 64, ACK send failed 128.
Only ACK send failure currently has a Win32 code. No unknown IDs are exported.

One branch-triggered Windows run performs the unchanged ten-case native F1
fixture once on the freshly built diagnostic child and exact-source host. This
is not a packaged application or physical-device acceptance. A separate phase
uses the immutable *failed normal CI* app and embedded child, verified by full
hash, for the original WPF fixture followed by original F1 fixture once. It does
not substitute the different passing release-workflow package. Boundary
observations read emptiness, sequence changes, and known fixture ownership only;
unknown content is never read or cleared. Existing fixture failures remain
failures; subsequent observation does not authorize publication.

The immutable experiment omits the earlier full-CI workload. A pass cannot prove
that workload, CPU, linking, clipboard ownership or timing caused the old failure.
No automatic merge, release or website mutation is part of this workflow.
