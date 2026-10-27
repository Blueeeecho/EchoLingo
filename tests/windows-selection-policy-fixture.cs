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
    // The host fixture cannot load Windows UIAutomationTypes. This represents
    // a provider disappearance, which is not a documented unsupported-selection
    // InvalidOperationException. The real adapter catches ElementNotAvailable.
    sealed class UnavailableElementFixtureException : Exception { }
    sealed class CopyFixture {
        public readonly List<Frame> Frames = new List<Frame>();
        public int Index, RestoreCount, ReadCount, SequenceReadCount;
        public bool ReplaceBeforeRestore;
        public bool FailRestore;
        public bool FailRead;
        public bool BusyFirstRead, ForeignOwner;
        public int OwnerChecks;
        public bool LoseContextWhileReading, CancelAfterCopy;
        public int PostContextChecks;
        public readonly List<string> Order = new List<string>();
        public string Clipboard = "original-rich-fixture";
        public uint CurrentSequence { get { return Frames[Math.Min(Index, Frames.Count - 1)].Sequence; } }
        public string Run(uint inserted) {
            return SelectionCopyPolicy.CompleteCopy(10, inserted,
                delegate { SequenceReadCount++; return CurrentSequence; },
                delegate { ReadCount++; Order.Add("read"); if (FailRead) throw new InvalidOperationException("synthetic read failure"); if(BusyFirstRead&&ReadCount==1)throw new System.Runtime.InteropServices.ExternalException("synthetic publication lock",unchecked((int)0x800401D0)); Clipboard = Frames[Math.Min(Index, Frames.Count - 1)].Text; return Clipboard; },
                delegate(uint expected) {
                    if (ReplaceBeforeRestore) SelectionCopyPolicy.RequireCurrentSequence(expected, expected + 1);
                    if (FailRestore) throw new InvalidOperationException("CLIPBOARD_RESTORE_FAILED: synthetic failure");
                    SelectionCopyPolicy.RequireCurrentSequence(expected, CurrentSequence);
                    RestoreCount++; Order.Add("restore"); Clipboard = "original-rich-fixture";
                },
                delegate { return Frames[Math.Min(Index, Frames.Count - 1)].Time; },
                delegate { if (++Index >= Frames.Count) throw new Exception("Unbounded copy wait"); }, null,
                delegate {
                    PostContextChecks++; Order.Add("post-context");
                    if (CancelAfterCopy) throw new OperationCanceledException("CANCELLED: synthetic newer task");
                    if (LoseContextWhileReading && ReadCount > 0)
                        throw new InvalidOperationException("SELECTION: synthetic source context changed while copy waited");
                }, delegate {OwnerChecks++;if(ForeignOwner)throw new InvalidOperationException("CLIPBOARD_CHANGED: synthetic non-source owner");});
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
            Error(delegate { SelectionCopyPolicy.AutomationText(new string[] { null }, delegate(string text) { throw new Exception("must not read a null range"); }); }, "SELECTION:");

            int unavailableCopies = 0, rangeReads = 0;
            Func<string> unavailableCopy = delegate { unavailableCopies++; return "synthetic fallback selection"; };
            Action currentContext = delegate { };
            Func<string[], string> currentRanges = delegate(string[] ranges) {
                return SelectionCopyPolicy.ReadAutomation(false, true, true, delegate { return ranges; },
                    delegate(string range) { rangeReads++; return range; });
            };
            Error(delegate {
                SelectionCopyPolicy.RevalidateAndCopy(delegate {
                    SelectionCopyPolicy.RequireFocus<string>(null);
                    return currentRanges(null);
                }, currentContext, unavailableCopy);
            }, "SELECTION:");
            Assert(unavailableCopies == 0 && rangeReads == 0, "Missing focus stops before querying text or sending copy");
            Error(delegate { SelectionCopyPolicy.RevalidateAndCopy(delegate { return currentRanges(new string[] { null }); }, currentContext, unavailableCopy); }, "SELECTION:");
            Assert(unavailableCopies == 0 && rangeReads == 0, "Malformed range element never becomes unsupported-provider fallback");
            bool providerFailed = false;
            try {
                SelectionCopyPolicy.RevalidateAndCopy(delegate {
                    return SelectionCopyPolicy.ReadAutomation<string>(false, true, true,
                        delegate { throw new UnavailableElementFixtureException(); }, delegate(string range) { return range; });
                }, currentContext, unavailableCopy);
            } catch (UnavailableElementFixtureException) { providerFailed = true; }
            Assert(providerFailed && unavailableCopies == 0, "A disappeared provider propagates failure before copy instead of becoming unsupported");
            Error(delegate {
                SelectionCopyPolicy.RevalidateAndCopy(delegate {
                    return SelectionCopyPolicy.ReadAutomation<string>(false, true, true,
                        delegate { return new string[] { "range" }; }, delegate(string range) { throw new InvalidOperationException("SELECTION: stale range read"); });
                }, currentContext, unavailableCopy);
            }, "SELECTION:");
            Assert(unavailableCopies == 0, "Invalid range read is not caught as GetSelection unsupported");
            foreach (string allowed in new string[] { "ControlType.Edit", "ControlType.Document", "ControlType.Text", "ControlType.Custom", "ControlType.Pane" }) {
                bool fallback = SelectionCopyPolicy.CopyFallbackAllowed(allowed);
                int beforeCopy = unavailableCopies;
                Assert(SelectionCopyPolicy.RevalidateAndCopy(delegate {
                    return SelectionCopyPolicy.ReadAutomation<string>(false, fallback, true, delegate { return null; }, delegate(string range) { return range; });
                }, currentContext, unavailableCopy) == "synthetic fallback selection" && unavailableCopies == beforeCopy + 1,
                    "GetSelection whole-array null retains one copy for a verified text/document/custom focus: " + allowed);
                Assert(SelectionCopyPolicy.RevalidateAndCopy(delegate {
                    return SelectionCopyPolicy.ReadAutomation<string>(false, fallback, true,
                        delegate { throw new InvalidOperationException("selection unsupported"); }, delegate(string range) { return range; });
                }, currentContext, unavailableCopy) == "synthetic fallback selection" && unavailableCopies == beforeCopy + 2,
                    "Documented GetSelection unsupported exception retains one copy: " + allowed);
            }
            foreach (string blockedRole in new string[] { "ControlType.Window", "ControlType.Button", "ControlType.Menu", "ControlType.MenuItem", "ControlType.ToolBar", "ControlType.TitleBar", "", null }) {
                bool fallback = SelectionCopyPolicy.CopyFallbackAllowed(blockedRole);
                int beforeCopy = unavailableCopies;
                Error(delegate {
                    SelectionCopyPolicy.RevalidateAndCopy(delegate {
                        return SelectionCopyPolicy.ReadAutomation<string>(false, fallback, false,
                            delegate { throw new Exception("No TextPattern must not query selection"); }, delegate(string range) { return range; });
                    }, currentContext, unavailableCopy);
                }, "NO_SELECTION:");
                Assert(unavailableCopies == beforeCopy, "Known non-text/unknown focus never receives blind copy: " + blockedRole);
            }
            foreach (bool password in new bool[] { false, true }) {
                int beforeCopy = unavailableCopies;
                Error(delegate {
                    SelectionCopyPolicy.RevalidateAndCopy(delegate {
                        return SelectionCopyPolicy.ReadAutomation<string>(password, true, true,
                            delegate { return new string[] { "" }; }, delegate(string range) { return range; });
                    }, currentContext, unavailableCopy);
                }, password ? "PROTECTED:" : "NO_SELECTION:");
                Assert(unavailableCopies == beforeCopy, "Known empty and password controls stop without copy");
            }
            int unsupportedQueries = 0, beforeUnsupported = unavailableCopies;
            Assert(SelectionCopyPolicy.RevalidateAndCopy(delegate {
                return SelectionCopyPolicy.ReadAutomation<string>(false, SelectionCopyPolicy.CopyFallbackAllowed("ControlType.Custom"), false,
                    delegate { unsupportedQueries++; return null; }, delegate(string range) { return range; });
            }, currentContext, unavailableCopy) == "synthetic fallback selection" && unsupportedQueries == 0 && unavailableCopies == beforeUnsupported + 1,
                "A valid custom control without TextPattern keeps exactly one fallback without querying that absent pattern");

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
            Assert(normal.Run(4) == "synthetic selected text 中文" && normal.Index == 2, "Clear then first coherent source-owned Unicode publication completes without a fixed stability sleep");
            Assert(normal.RestoreCount == 1 && normal.Clipboard == "original-rich-fixture", "Completed copy restores original data once");
            Assert(normal.PostContextChecks == 1 && normal.Order.IndexOf("restore") < normal.Order.IndexOf("post-context"), "Source context is checked after restoration before a normal result returns");
            foreach (string changed in new string[] { "foreground", "focused control" }) {
                CopyFixture supersededSource = Stable(); supersededSource.LoseContextWhileReading = true;
                Error(delegate { supersededSource.Run(4); }, "SELECTION:");
                Assert(supersededSource.ReadCount > 0 && supersededSource.RestoreCount == 1
                    && supersededSource.Clipboard == "original-rich-fixture", "Copy already issued still restores before rejecting changed " + changed);
                Assert(supersededSource.PostContextChecks == 1
                    && supersededSource.Order.IndexOf("restore") < supersededSource.Order.IndexOf("post-context"), "Changed " + changed + " cannot return old text and cannot skip necessary restoration");
            }
            CopyFixture cancelled = Stable(); cancelled.CancelAfterCopy = true;
            bool cancellationReported = false;
            try { cancelled.Run(4); } catch (OperationCanceledException) { cancellationReported = true; }
            Assert(cancellationReported && cancelled.RestoreCount == 1 && cancelled.Clipboard == "original-rich-fixture", "A superseded task restores its already-issued copy before reporting cancellation");
            Assert(cancelled.Order.IndexOf("restore") < cancelled.Order.IndexOf("post-context"), "Cancellation cannot skip required clipboard restoration");
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
            late.Frames.Add(new Frame(1200, 12, "late text"));
            Error(delegate { late.Run(4); }, "CLIPBOARD_RESTORE_SKIPPED:");
            Assert(late.RestoreCount == 0, "A first Unicode publication at the deadline does not extend the bounded observation");
            CopyFixture foreign = Stable(); foreign.ForeignOwner=true;
            Error(delegate {foreign.Run(4);}, "CLIPBOARD_CHANGED:");
            Assert(foreign.RestoreCount==0&&foreign.OwnerChecks==1,"First coherent text from a non-source clipboard owner is never returned or overwritten");
            CopyFixture busy = new CopyFixture();busy.BusyFirstRead=true;
            busy.Frames.Add(new Frame(0,12,"selected after lock"));busy.Frames.Add(new Frame(5,12,"selected after lock"));
            Assert(busy.Run(4)=="selected after lock"&&busy.ReadCount==2&&busy.RestoreCount==1,"Known temporary clipboard-open failure is condition-retried then restored once");
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
            Assert(torn.Observe(12, "coherent text", 12, 5) == SelectionCopyPolicy.Observation.Completed, "The first coherent snapshot can complete once ownership is checked by the caller");
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
            Assert(rendered == "coherent text" && renderRestores == 1 && renderStep == 1, "First read render race is reread coherently and restored exactly once without stability delay");
            Assert(metadataTrace[0].Contains("before=11 after=12 candidateBefore=none candidateAfter=none")
                && metadataTrace[0].Contains("observation=Waiting"), "Numeric trace proves the torn first snapshot was discarded");
            Assert(metadataTrace.TrueForAll(delegate(string trace) { return !trace.Contains("discarded torn text") && !trace.Contains("coherent text"); }), "Diagnostic trace contains no copied content");
            Assert(SelectionCopyPolicy.ReadAutomation(false,true,true,delegate{return new string[0];},delegate(string x){return x;},true)==null,"Document-scoped empty provider may seek a verified parent selection or single-copy fallback");
            Error(delegate {SelectionCopyPolicy.ReadAutomation(false,true,true,delegate{return new string[]{(string)null};},delegate(string x){return x;},true);},"SELECTION:");
            Error(delegate {SelectionCopyPolicy.ReadAutomation(false,true,true,delegate{return new string[]{"range"};},delegate(string x){throw new InvalidOperationException("SELECTION: stale range");},true);},"SELECTION:");
            Assert(normal.OwnerChecks==2,"Owner validated after coherent read and again immediately before restore");
            Console.WriteLine("{\"ok\":true,\"selectionPolicyFixturePassed\":true,\"assertions\":" + assertions + ",\"windowsInteractiveTested\":false,\"clipboardAccessed\":false,\"inputSent\":false,\"screenCaptured\":false}");
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
