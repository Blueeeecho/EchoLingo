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
    static SelectionCopyPolicy.NativeContext NativeContext() {
        return new SelectionCopyPolicy.NativeContext { Foreground = 101, Root = 101, Focus = 102,
            Process = 201, ForegroundThread = 301, FocusThread = 302, Valid = true, MouseReleased = true };
    }
    static void UnreadRestartChecks() {
        SelectionCopyPolicy.ReadEvidence absent = new SelectionCopyPolicy.ReadEvidence();
        absent.CompleteUnsupportedScan();
        Assert(!absent.NoPatternComplete, "No attempted candidate query cannot qualify as a complete unsupported path");
        absent.ObservePattern(false, false); absent.ObservePattern(false, false); absent.ObservePattern(false, false);
        absent.CompleteUnsupportedScan();
        Assert(absent.NoPatternComplete && !absent.PatternSeen && !absent.RangeReadAttempted, "Only a normally completed all-unsupported candidate path can qualify");
        SelectionCopyPolicy.ReadEvidence earlyEdit = new SelectionCopyPolicy.ReadEvidence(); earlyEdit.ObservePattern(false, false);
        Assert(!earlyEdit.NoPatternComplete, "An unsupported Edit early return has not completed the candidate scan");
        SelectionCopyPolicy.ReadEvidence failedQuery = new SelectionCopyPolicy.ReadEvidence();
        Assert(!failedQuery.NoPatternComplete, "A provider query failure before normal completion cannot qualify");
        foreach (bool validPattern in new bool[] { true, false }) {
            SelectionCopyPolicy.ReadEvidence seen = new SelectionCopyPolicy.ReadEvidence(); seen.ObservePattern(true, validPattern);
            seen.CompleteUnsupportedScan();
            Assert(seen.PatternSeen && !seen.NoPatternComplete, "An available pattern is strict before GetSelection, including malformed or empty providers");
        }
        SelectionCopyPolicy.ReadEvidence inconsistent = new SelectionCopyPolicy.ReadEvidence(); inconsistent.ObservePattern(false, true); inconsistent.CompleteUnsupportedScan();
        Assert(inconsistent.PatternSeen && !inconsistent.NoPatternComplete, "A returned valid pattern never becomes no-pattern evidence even with an inconsistent available flag");
        SelectionCopyPolicy.ReadEvidence read = new SelectionCopyPolicy.ReadEvidence(); read.BeforeRangeRead(); read.CompleteUnsupportedScan();
        Assert(read.RangeReadAttempted && !read.NoPatternComplete, "Any attempted range read prevents restart eligibility");
        absent.ObservePattern(true, true);
        Assert(!absent.NoPatternComplete, "Subsequently observing a valid pattern invalidates completed unsupported evidence");
        foreach (bool emptyDocument in new bool[] { false, true }) {
            SelectionCopyPolicy.ReadEvidence empty = new SelectionCopyPolicy.ReadEvidence(); empty.ObservePattern(true, true);
            try { SelectionCopyPolicy.ReadAutomation(false, true, true,
                delegate { empty.BeforeRangeRead(); return new string[0]; }, delegate(string value) { empty.BeforeRangeRead(); return value; }, emptyDocument); }
            catch (InvalidOperationException error) { Assert(error.Message.StartsWith("NO_SELECTION:", StringComparison.Ordinal), "Valid empty Edit remains NO_SELECTION"); }
            empty.CompleteUnsupportedScan();
            Assert(empty.PatternSeen && empty.RangeReadAttempted && !empty.NoPatternComplete, "Valid empty Edit and Document providers must remain strict");
        }
        SelectionCopyPolicy.ReadEvidence stale = new SelectionCopyPolicy.ReadEvidence(); stale.ObservePattern(true, true);
        Error(delegate { SelectionCopyPolicy.ReadAutomation(false, true, true,
            delegate { stale.BeforeRangeRead(); return new string[] { "generated range" }; },
            delegate(string value) { stale.BeforeRangeRead(); throw new InvalidOperationException("SELECTION: generated stale range"); }); }, "SELECTION:");
        Assert(!stale.NoPatternComplete, "A range exception cannot reclassify a real pattern as unsupported");
        SelectionCopyPolicy.NativeContext before = NativeContext(), current = NativeContext();
        Assert(SelectionCopyPolicy.CanRestartUnreadSelection(true, null, false, before, current), "A complete unread scan permits current selection B from matching native context; it does not prove an unseen shortcut-time A");
        Assert(SelectionCopyPolicy.CanRestartUnreadSelection(true, " ", false, before, current), "Unread whitespace has no captured A to preserve");
        Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(false, null, false, before, current), "Unavailable, early-return, valid-empty or failed scans cannot restart");
        Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(true, "already captured A", false, before, current), "Previously read A must never be replaced by current B");
        Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(true, null, true, before, current), "A second context transition is never retried");
        Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(true, null, false, null, current)
            && !SelectionCopyPolicy.CanRestartUnreadSelection(true, null, false, before, null), "Unknown native context cannot authorize current capture");
        Action<SelectionCopyPolicy.NativeContext>[] changes = new Action<SelectionCopyPolicy.NativeContext>[] {
            delegate(SelectionCopyPolicy.NativeContext value) { value.Valid = false; },
            delegate(SelectionCopyPolicy.NativeContext value) { value.MouseReleased = false; },
            delegate(SelectionCopyPolicy.NativeContext value) { value.Foreground++; },
            delegate(SelectionCopyPolicy.NativeContext value) { value.Root++; },
            delegate(SelectionCopyPolicy.NativeContext value) { value.Focus++; },
            delegate(SelectionCopyPolicy.NativeContext value) { value.Process++; },
            delegate(SelectionCopyPolicy.NativeContext value) { value.ForegroundThread++; },
            delegate(SelectionCopyPolicy.NativeContext value) { value.FocusThread++; }
        };
        foreach (Action<SelectionCopyPolicy.NativeContext> change in changes) {
            current = NativeContext(); change(current);
            Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(true, null, false, before, current), "Every native context, validity and released-mouse boundary must match");
        }
        current = NativeContext(); before.MouseReleased = false;
        Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(true, null, false, before, current), "Mouse already held at Q1 entry disables restart");
        before = NativeContext(); before.Valid = false;
        Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(true, null, false, before, current), "An invalid Q1 snapshot cannot be replaced by a valid later one");
        before = NativeContext(); before.Focus = 0; current.Focus = 0;
        Assert(!SelectionCopyPolicy.CanRestartUnreadSelection(true, null, false, before, current), "Two unknown zero focus handles do not constitute matching context");
        Assert(SelectionCopyPolicy.KnownRuntimeIdChange(new int[] { 1, 2 }, new int[] { 1, 3 }), "Two real unequal RuntimeIds can use typed changed-identity control flow");
        Assert(SelectionCopyPolicy.KnownRuntimeIdChange(new int[] { 1 }, new int[] { 1, 2 }), "Different nonempty opaque RuntimeId lengths still represent a known change");
        Assert(!SelectionCopyPolicy.KnownRuntimeIdChange(new int[] { 1, 2 }, new int[] { 1, 2 }), "Equal RuntimeIds are not a transition");
        Assert(!SelectionCopyPolicy.KnownRuntimeIdChange(null, new int[] { 1 }), "Unknown initial identity cannot authorize a current capture");
        Assert(!SelectionCopyPolicy.KnownRuntimeIdChange(new int[0], new int[] { 1 }), "Empty initial identity cannot authorize a current capture");
        Assert(!SelectionCopyPolicy.KnownRuntimeIdChange(new int[] { 1 }, null), "Unavailable fresh RuntimeId stays a generic error, not restart control flow");
        Assert(!SelectionCopyPolicy.KnownRuntimeIdChange(new int[] { 1 }, new int[0]), "Empty fresh RuntimeId stays a generic error, not restart control flow");
        SelectionCopyPolicy.SelectionRuntimeIdChangedException typed = new SelectionCopyPolicy.SelectionRuntimeIdChangedException();
        Assert(typed.Message == "SELECTION: The focused control changed or is outside the source window; select text and retry.", "Typed RuntimeId failure preserves the public error text");
        Assert(!(new InvalidOperationException("PROTECTED: generated") is SelectionCopyPolicy.SelectionRuntimeIdChangedException), "Protection and generic selection errors are not restart control flow");
    }
    static void CompatibilityCopyChecks() {
        int copies = 0;
        Action<bool, bool, bool, uint, uint> capture = delegate(bool password, bool native, bool known, uint start, uint end) {
            SelectionCopyPolicy.RequireCompatibilitySelection(password, native, known, start, end);
            copies++;
        };
        foreach (bool native in new bool[] { false, true }) {
            Error(delegate { capture(true, native, false, 0, 0); }, "PROTECTED:");
            Assert(copies == 0, "Known password metadata stops explicit compatibility before copy, even when selection availability is unknown");
        }
        Error(delegate { capture(false, true, false, 0, 0); }, "SELECTION:");
        Assert(copies == 0, "A recognized native editor with unavailable selection metadata never receives blind copy");
        foreach (uint caret in new uint[] { 0, 12, 65535, 65536, UInt32.MaxValue }) {
            Error(delegate { capture(false, true, true, caret, caret); }, "NO_SELECTION:");
            Assert(copies == 0, "A native empty selection is rejected, including full 32-bit caret positions");
        }
        capture(false, true, true, 65536, 65540);
        Assert(copies == 1, "A verified native selection above the packed 16-bit range remains available");
        capture(false, true, true, 10, 5);
        Assert(copies == 2, "Selection presence uses unequal endpoints rather than truncating or assuming drag direction");
        capture(false, false, false, 0, 0);
        Assert(copies == 3, "Only the explicitly invoked compatibility policy permits unknown custom selection; this does not prove that Ctrl+C will not copy a whole line");
    }
    static void CrossProcessCopyContextChecks() {
        SelectionCopyPolicy.NativeContext before=NativeContext(),current=NativeContext();
        before.FocusProcess=current.FocusProcess=before.Process+100;
        Assert(SelectionCopyPolicy.CanCopyFromNativeContext(before,current),"An already validated same-root foreign child can be copied while both process identities remain stable");
        current.FocusProcess++;
        Assert(!SelectionCopyPolicy.CanCopyFromNativeContext(before,current),"A different focus process cannot reuse the prior child's clipboard authority even with unchanged HWND/thread/frame metadata");
        current=NativeContext();current.FocusProcess=before.FocusProcess;current.Root++;
        Assert(!SelectionCopyPolicy.CanCopyFromNativeContext(before,current),"An alternative root remains rejected; process or owner-window affinity cannot replace GA_ROOT equality");
        current=NativeContext();current.FocusProcess=before.FocusProcess;current.Valid=false;
        Assert(!SelectionCopyPolicy.CanCopyFromNativeContext(before,current),"Invalid native ancestry is not repaired by a matching focus process");
        current=NativeContext();current.FocusProcess=before.FocusProcess;current.Process++;
        Assert(!SelectionCopyPolicy.CanCopyFromNativeContext(before,current),"A changed foreground process still cancels copy even if the focused child identity remains stable");
        current=NativeContext();current.FocusProcess=0;
        Assert(!SelectionCopyPolicy.CanCopyFromNativeContext(before,current),"An unknown current focus process is not clipboard authority");
        before.FocusProcess=0;
        Assert(!SelectionCopyPolicy.CanCopyFromNativeContext(before,current),"Two zero focus process IDs cannot establish copy identity");
        Assert(!SelectionCopyPolicy.CanCopyFromNativeContext(null,current)&&!SelectionCopyPolicy.CanCopyFromNativeContext(current,null),"Missing native snapshots cannot authorize copy");
        // Strict unread/UIA policy intentionally retains its original checks.
        before=NativeContext();current=NativeContext();before.FocusProcess=1;current.FocusProcess=2;
        Assert(SelectionCopyPolicy.CanRestartUnreadSelection(true,null,false,before,current),"The legacy strict unread comparator does not inherit the new copy-only focus-process policy");
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

            int splitReads = 0, splitAfterChecks = 0, splitCopies = 0;
            List<string> splitOrder = new List<string>();
            Func<string> splitCopy = delegate { splitCopies++; splitOrder.Add("copy"); return "split fallback"; };
            Error(delegate {
                SelectionCopyPolicy.RevalidateAndCopy(
                    delegate { splitReads++; return null; },
                    delegate { throw new InvalidOperationException("CLIPBOARD_CHANGED: synthetic local precondition"); },
                    delegate { splitAfterChecks++; }, splitCopy);
            }, "CLIPBOARD_CHANGED:");
            Assert(splitReads == 0 && splitAfterChecks == 0 && splitCopies == 0,
                "A failed local before-read guard prevents provider reads, after-read checks and copy");
            foreach (string blocked in new string[] { "PROTECTED:", "SELECTION:" }) {
                splitReads = 0; splitAfterChecks = 0; splitCopies = 0; splitOrder.Clear();
                Error(delegate {
                    SelectionCopyPolicy.RevalidateAndCopy(
                        delegate { splitReads++; splitOrder.Add("validated-read"); throw new InvalidOperationException(blocked + " synthetic fresh-focus validation"); },
                        delegate { splitOrder.Add("before"); },
                        delegate { splitAfterChecks++; splitOrder.Add("after"); }, splitCopy);
                }, blocked);
                Assert(splitReads == 1 && splitAfterChecks == 0 && splitCopies == 0
                    && String.Join(",", splitOrder) == "before,validated-read",
                    "A protected or unavailable validated selection stops before after-read checks and copy");
            }
            foreach (string freshSelection in new string[] { "current direct selection", null }) {
                splitReads = 0; splitAfterChecks = 0; splitCopies = 0; splitOrder.Clear();
                Error(delegate {
                    SelectionCopyPolicy.RevalidateAndCopy(
                        delegate { splitReads++; splitOrder.Add("validated-read"); return freshSelection; },
                        delegate { splitOrder.Add("before"); },
                        delegate { splitAfterChecks++; splitOrder.Add("after"); throw new InvalidOperationException("SELECTION: synthetic focus changed during read"); }, splitCopy);
                }, "SELECTION:");
                Assert(splitReads == 1 && splitAfterChecks == 1 && splitCopies == 0
                    && String.Join(",", splitOrder) == "before,validated-read,after",
                    "A failed after-read focus guard rejects both direct text and unavailable-provider copy");
            }
            foreach (string freshSelection in new string[] { "current direct selection", null }) {
                splitReads = 0; splitAfterChecks = 0; splitCopies = 0; splitOrder.Clear();
                string splitResult = SelectionCopyPolicy.RevalidateAndCopy(
                    delegate { splitReads++; splitOrder.Add("validated-read"); return freshSelection; },
                    delegate { splitOrder.Add("before"); },
                    delegate { splitAfterChecks++; splitOrder.Add("after"); }, splitCopy);
                bool fallback = freshSelection == null;
                Assert(splitResult == (fallback ? "split fallback" : freshSelection)
                    && splitReads == 1 && splitAfterChecks == 1 && splitCopies == (fallback ? 1 : 0)
                    && String.Join(",", splitOrder) == (fallback ? "before,validated-read,after,copy" : "before,validated-read,after"),
                    "Split guards retain exactly one validated read, one post-read check and at most one copy");
            }

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
            UnreadRestartChecks();
            CompatibilityCopyChecks();
            CrossProcessCopyContextChecks();
            Console.WriteLine("{\"ok\":true,\"selectionPolicyFixturePassed\":true,\"assertions\":" + assertions + ",\"windowsInteractiveTested\":false,\"clipboardAccessed\":false,\"inputSent\":false,\"screenCaptured\":false}");
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
