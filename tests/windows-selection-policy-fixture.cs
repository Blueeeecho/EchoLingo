// Compile with the exact SelectionCopyPolicy class extracted from windows.ps1.
// Synthetic delegates only: no Windows UI, input, clipboard, or native calls.
using System;
using System.Collections.Generic;

public static class WindowsSelectionPolicyFixture {
    static int assertions;
    static void Assert(bool value, string message) {
        assertions++;
        if (!value) throw new InvalidOperationException("SELF_TEST: " + message);
    }
    static void Error(Action action, string prefix) {
        try { action(); throw new Exception("Expected " + prefix); }
        catch (InvalidOperationException error) { Assert(error.Message.StartsWith(prefix, StringComparison.Ordinal), "Wrong error: " + error.Message); }
    }
    sealed class Frame {
        public long Time;
        public uint Sequence;
        public string Text;
        public Frame(long time, uint sequence, string text) { Time = time; Sequence = sequence; Text = text; }
    }
    sealed class CopyFixture {
        public readonly List<Frame> Frames = new List<Frame>();
        public int Index, RestoreCount, ReadCount, SequenceReadCount;
        public bool ReplaceBeforeRestore;
        public bool FailRestore;
        public bool FailRead;
        public string Clipboard = "original-rich-fixture";
        public uint CurrentSequence { get { return Frames[Math.Min(Index, Frames.Count - 1)].Sequence; } }
        public string Run(uint inserted) {
            return SelectionCopyPolicy.CompleteCopy(10, inserted,
                delegate { SequenceReadCount++; return CurrentSequence; },
                delegate { ReadCount++; if (FailRead) throw new InvalidOperationException("synthetic clipboard busy"); Clipboard = Frames[Math.Min(Index, Frames.Count - 1)].Text; return Clipboard; },
                delegate(uint expected) {
                    if (ReplaceBeforeRestore) SelectionCopyPolicy.RequireCurrentSequence(expected, expected + 1);
                    if (FailRestore) throw new InvalidOperationException("CLIPBOARD_RESTORE_FAILED: synthetic failure");
                    SelectionCopyPolicy.RequireCurrentSequence(expected, CurrentSequence);
                    RestoreCount++; Clipboard = "original-rich-fixture";
                },
                delegate { return Frames[Math.Min(Index, Frames.Count - 1)].Time; },
                delegate { if (++Index >= Frames.Count) throw new Exception("Unbounded copy wait"); });
        }
    }
    static CopyFixture Stable() {
        CopyFixture fixture = new CopyFixture();
        fixture.Frames.Add(new Frame(0, 10, null));
        fixture.Frames.Add(new Frame(5, 11, null)); // EmptyClipboard is not completion.
        fixture.Frames.Add(new Frame(10, 12, "synthetic selected text 中文"));
        fixture.Frames.Add(new Frame(29, 12, "synthetic selected text 中文"));
        fixture.Frames.Add(new Frame(30, 12, "synthetic selected text 中文"));
        return fixture;
    }
    public static int Main() {
        try {
            Assert(SelectionCopyPolicy.AutomationText<string>(null, delegate(string text) { return text; }) == null,
                   "UIA null means unavailable and allows exactly the existing copy fallback");
            Error(delegate { SelectionCopyPolicy.AutomationText(new string[0], delegate(string text) { return text; }); }, "NO_SELECTION:");
            Error(delegate { SelectionCopyPolicy.AutomationText(new string[] { "", "  " }, delegate(string text) { return text; }); }, "NO_SELECTION:");
            Assert(SelectionCopyPolicy.AutomationText(new string[] { "first", "second" }, delegate(string text) { return text; }) == "first" + Environment.NewLine + "second", "Nonempty disjoint ranges preserved");
            Assert(SelectionCopyPolicy.AutomationText(new string[] { null }, delegate(string text) { throw new Exception("must not read a null range"); }) == null, "Malformed null range is unavailable without dereference");

            int copyCalls = 0, contextChecks = 0;
            Func<string> copy = delegate { copyCalls++; return "fallback"; };
            Action context = delegate { contextChecks++; };
            foreach (string blocked in new string[] { "PROTECTED:", "NO_SELECTION:" }) {
                Error(delegate { SelectionCopyPolicy.RevalidateAndCopy(delegate { throw new InvalidOperationException(blocked + " synthetic newly focused control"); }, context, copy); }, blocked);
                Assert(copyCalls == 0, "A newly protected/empty control cannot inherit the old copy fallback");
            }
            Assert(SelectionCopyPolicy.RevalidateAndCopy(delegate { return "current direct selection"; }, context, copy) == "current direct selection" && copyCalls == 0, "A newly available direct selection avoids injected copy");
            Assert(SelectionCopyPolicy.RevalidateAndCopy(delegate { return null; }, context, copy) == "fallback" && copyCalls == 1, "Only a still-unavailable provider reaches one copy");
            Assert(contextChecks == 6, "Context is checked before and after each successful revalidation");
            int changedContextChecks = 0;
            Error(delegate { SelectionCopyPolicy.RevalidateAndCopy(delegate { return null; }, delegate { if (++changedContextChecks == 2) throw new InvalidOperationException("CLIPBOARD_CHANGED: synthetic race"); }, copy); }, "CLIPBOARD_CHANGED:");
            Assert(copyCalls == 1, "A context change during UIA revalidation blocks input");

            CopyFixture normal = Stable();
            Assert(normal.Run(4) == "synthetic selected text 中文" && normal.Index == 4, "Clear then delayed stable text waits and succeeds");
            Assert(normal.RestoreCount == 1 && normal.Clipboard == "original-rich-fixture", "Completed copy restores original data once");
            foreach (uint partial in new uint[] { 2, 3 }) {
                CopyFixture fixture = Stable();
                Error(delegate { fixture.Run(partial); }, "SELECTION:");
                Assert(fixture.RestoreCount == 1 && fixture.Clipboard == "original-rich-fixture", "Partial Ctrl+C is observed/restored before input failure");
            }
            foreach (uint notCopied in new uint[] { 0, 1 }) {
                CopyFixture fixture = Stable();
                Error(delegate { fixture.Run(notCopied); }, "SELECTION:");
                Assert(fixture.RestoreCount == 0 && fixture.SequenceReadCount == 0 && fixture.ReadCount == 0, "No C-down means no ownership of any clipboard update");
            }
            CopyFixture clearOnly = new CopyFixture();
            clearOnly.Frames.Add(new Frame(0, 11, null)); clearOnly.Frames.Add(new Frame(1200, 11, null));
            Error(delegate { clearOnly.Run(4); }, "CLIPBOARD_RESTORE_SKIPPED:");
            Assert(clearOnly.RestoreCount == 0, "An incomplete clear cannot be restored over a later publish");
            CopyFixture late = new CopyFixture();
            late.Frames.Add(new Frame(1195, 12, "late text")); late.Frames.Add(new Frame(1200, 12, "late text"));
            Error(delegate { late.Run(4); }, "CLIPBOARD_RESTORE_SKIPPED:");
            Assert(late.RestoreCount == 0, "Deadline does not bypass 20ms stability");
            CopyFixture newer = new CopyFixture();
            newer.Frames.Add(new Frame(0, 12, "copy candidate")); newer.Frames.Add(new Frame(10, 13, "new user copy"));
            Error(delegate { newer.Run(4); }, "CLIPBOARD_CHANGED:");
            Assert(newer.RestoreCount == 0 && newer.Clipboard == "new user copy", "A newer generation after a candidate wins");
            CopyFixture restoreRace = Stable(); restoreRace.ReplaceBeforeRestore = true;
            Error(delegate { restoreRace.Run(4); }, "CLIPBOARD_CHANGED:");
            Assert(restoreRace.RestoreCount == 0, "Final restoration callback rechecks clipboard generation");
            CopyFixture restoreFailure = Stable(); restoreFailure.FailRestore = true;
            Error(delegate { restoreFailure.Run(4); }, "CLIPBOARD_RESTORE_FAILED:");
            CopyFixture readFailure = Stable(); readFailure.FailRead = true;
            Error(delegate { readFailure.Run(4); }, "CLIPBOARD_RESTORE_SKIPPED:");
            Assert(readFailure.RestoreCount == 0, "Unreadable clipboard data never causes an unsafe restoration");
            CopyFixture unchanged = new CopyFixture(); unchanged.Frames.Add(new Frame(1200, 10, null));
            Error(delegate { unchanged.Run(4); }, "NO_SELECTION:");
            Assert(unchanged.RestoreCount == 0 && unchanged.ReadCount == 0, "No clipboard change means no restoration");

            SelectionCopyPolicy.Completion torn = new SelectionCopyPolicy.Completion(10);
            Assert(torn.Observe(11, "discarded torn text", 12, 0) == SelectionCopyPolicy.Observation.Waiting, "First materialization race is discarded and reread");
            Assert(!torn.CandidateSequence.HasValue, "A torn first read cannot establish clipboard ownership");
            Assert(torn.Observe(12, "coherent text", 12, 5) == SelectionCopyPolicy.Observation.Waiting, "Only a coherent snapshot establishes the first candidate");
            Assert(torn.Observe(12, "newer text", 13, 10) == SelectionCopyPolicy.Observation.Superseded, "A torn read after a candidate still preserves the newer generation");
            SelectionCopyPolicy.Completion expiredTorn = new SelectionCopyPolicy.Completion(10);
            Assert(expiredTorn.Observe(11, "late torn text", 12, 1200) == SelectionCopyPolicy.Observation.UnfinishedTimeout, "An initial materialization race cannot extend the deadline");
            uint renderSequence = 11;
            int renderStep = 0, renderRestores = 0;
            List<string> metadataTrace = new List<string>();
            string rendered = SelectionCopyPolicy.CompleteCopy(10, 4, delegate { return renderSequence; },
                delegate { if (renderStep == 0) { renderSequence = 12; return "discarded torn text"; } return "coherent text"; },
                delegate(uint expected) { SelectionCopyPolicy.RequireCurrentSequence(expected, renderSequence); renderRestores++; },
                delegate { return renderStep * 10; }, delegate { if (++renderStep > 4) throw new Exception("Unbounded materialization retry"); },
                delegate(string trace) { metadataTrace.Add(trace); });
            Assert(rendered == "coherent text" && renderRestores == 1 && renderStep == 3, "First read render race is reread, stabilized, then restored exactly once");
            Assert(metadataTrace[0].Contains("before=11 after=12 candidateBefore=none candidateAfter=none")
                && metadataTrace[0].Contains("observation=Waiting"), "Numeric trace proves the torn first snapshot was discarded");
            Assert(metadataTrace.TrueForAll(delegate(string trace) { return !trace.Contains("discarded torn text") && !trace.Contains("coherent text"); }), "Diagnostic trace contains no copied content");
            SelectionCopyPolicy.Completion changedText = new SelectionCopyPolicy.Completion(10);
            Assert(changedText.Observe(11, "part", 11, 0) == SelectionCopyPolicy.Observation.Waiting, "First candidate waits");
            Assert(changedText.Observe(11, "whole", 11, 10) == SelectionCopyPolicy.Observation.Waiting, "Same-generation materialization resets stability");
            Assert(changedText.Observe(11, "whole", 11, 29) == SelectionCopyPolicy.Observation.Waiting, "Changed candidate cannot complete early");
            Assert(changedText.Observe(11, "whole", 11, 30) == SelectionCopyPolicy.Observation.Completed, "Changed candidate completes after stable interval");
            Console.WriteLine("{\"ok\":true,\"selectionPolicyFixturePassed\":true,\"assertions\":" + assertions + ",\"windowsInteractiveTested\":false,\"clipboardAccessed\":false,\"inputSent\":false,\"screenCaptured\":false}");
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
