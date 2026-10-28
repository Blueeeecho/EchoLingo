// Exact production ticket/policy classes are injected by the smoke script.
// Synthetic input phases and clipboard delegates; no native hooks or input.
using System;
using System.Threading;
using System.Text;

public static class WindowsSelectionCopyTicketFixture {
    static int assertions;
    const ulong Marker = 17023;
    static void Assert(bool value, string message) {
        assertions++;
        if (!value) throw new InvalidOperationException("SELF_TEST: " + message);
    }
    static void OwnCopy(SelectionCopyTicket ticket) {
        ticket.Observe(0xA2, true, false, Marker);
        ticket.Observe(0x43, true, false, Marker);
        ticket.Observe(0x43, false, true, Marker);
        ticket.Observe(0x11, false, true, Marker);
    }
    static void OtherCopy(SelectionCopyTicket ticket, int key) {
        ticket.Observe(0xA3, true, false, 0);
        ticket.Observe(key, true, false, 0);
    }
    static void Require(SelectionCopyTicket ticket) {
        if (ticket.Superseded) throw new InvalidOperationException("CANCELLED: synthetic newer copy");
    }
    static void InvalidatedAt(int stage) {
        SelectionCopyTicket ticket = new SelectionCopyTicket(Marker); OwnCopy(ticket);
        int reads = 0, restores = 0, owners = 0, gates = 0;
        try {
            SelectionCopyPolicy.CompleteCopy(10, 4, delegate { return 11; },
                delegate { reads++; if (stage == 2) OtherCopy(ticket, 0x43); return "generated requested selection"; },
                delegate(uint expected) { restores++; }, delegate { return 0; },
                delegate { throw new Exception("Unexpected wait"); }, null, null,
                delegate { if (++owners == 2 && stage == 3) OtherCopy(ticket, 0x2D); },
                delegate { if (++gates == 1 && stage == 1) OtherCopy(ticket, 0x43); Require(ticket); });
            throw new Exception("A superseded copy must not return a source");
        } catch (InvalidOperationException error) {
            Assert(error.Message.StartsWith("CANCELLED:", StringComparison.Ordinal), "New copy quietly cancels old result");
        }
        Assert(reads == (stage == 1 ? 0 : 1), "No clipboard read after prior invalidation");
        Assert(restores == 0, "A new copy before read/after read/before restore cannot be overwritten");
    }
    public static int Main() {
        try {
            SelectionCopyTicket own = new SelectionCopyTicket(Marker); OwnCopy(own);
            Assert(own.OwnInputObserved && !own.Superseded, "All tagged phases acknowledge exactly one own copy");
            own.Observe(0x43, true, false, 0);
            Assert(!own.Superseded, "An ordinary C after own Ctrl release is not a copy");
            foreach (int key in new int[] { 0x43, 0x2D }) {
                SelectionCopyTicket external = new SelectionCopyTicket(Marker); OwnCopy(external); OtherCopy(external, key);
                Assert(external.Superseded, "A distinct Ctrl+C or Ctrl+Insert supersedes the old ticket");
                external.Observe(key, false, true, 0); external.Observe(0xA3, false, true, 0);
                Assert(external.Superseded, "Releasing keys does not revive an obsolete copy");
            }
            SelectionCopyTicket overlap = new SelectionCopyTicket(Marker);
            overlap.Observe(0x11, true, false, Marker);
            overlap.Observe(0xA2, true, false, 0);
            overlap.Observe(0x11, false, true, Marker);
            overlap.Observe(0x43, true, false, 0);
            Assert(overlap.Superseded, "Own Ctrl release cannot erase a separately held user Ctrl");
            SelectionCopyTicket partial = new SelectionCopyTicket(Marker);
            partial.Observe(0x11, true, false, Marker); partial.Observe(0x43, true, false, Marker);
            Assert(!partial.OwnInputObserved, "Partial injection is not a complete acknowledgement");
            partial.Observe(0x43, false, true, Marker); partial.Observe(0x11, false, true, Marker);
            Assert(partial.OwnInputObserved, "Tagged compensating releases can acknowledge a partial copy");
            SelectionCopyTicket foreign = new SelectionCopyTicket(Marker);
            foreign.Observe(0x11, true, false, Marker + 1); foreign.Observe(0x43, true, false, Marker + 1);
            Assert(foreign.Superseded && !foreign.OwnInputObserved, "A different transaction marker is external input");
            SelectionCopyTicket paste = new SelectionCopyTicket(Marker);
            paste.Observe(0x10, true, false, 0); paste.Observe(0x2D, true, false, 0);
            Assert(!paste.Superseded, "Shift+Insert paste is not misclassified as copy");
            for (int stage = 1; stage <= 3; stage++) InvalidatedAt(stage);
            int restores = 0;
            try {
                SelectionCopyPolicy.CompleteCopy(10, 4, delegate { return 11; }, delegate { return "generated requested selection"; },
                    delegate(uint expected) { restores++; }, delegate { return 0; }, delegate { throw new Exception("Unexpected wait"); },
                    null, delegate { throw new OperationCanceledException("ordinary native cancellation"); }, null, delegate { Require(own); });
                throw new Exception("Ordinary cancellation must be surfaced");
            } catch (OperationCanceledException) { Assert(restores == 1, "Ordinary cancellation still restores the completed copy first"); }
            Console.WriteLine("{\"ok\":true,\"selectionCopyTicketPassed\":true,\"assertions\":" + assertions + ",\"nativeHooksInstalled\":false,\"inputSent\":false,\"clipboardAccessed\":false}");
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
