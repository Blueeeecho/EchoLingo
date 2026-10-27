// Reflect exact production budget/session/query and copy policy. Generated
// delegates only: no UIA provider, input, clipboard, or native hook is accessed.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Threading;

public static class WindowsSelectionBudgetFixture {
    const BindingFlags PrivateStatic = BindingFlags.NonPublic | BindingFlags.Static;
    static Type Native, BudgetType, SessionType, PolicyType;
    static FieldInfo CurrentSession, Worker;
    static int assertions;
    static readonly List<Dictionary<string, object>> cases = new List<Dictionary<string, object>>();
    static object Call(MethodBase method, object target, params object[] arguments) {
        try { return ((MethodInfo)method).Invoke(target, arguments); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    static object Construct(ConstructorInfo constructor, params object[] arguments) {
        try { return constructor.Invoke(arguments); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    static object Budget(long milliseconds) {
        return Construct(BudgetType.GetConstructor(new Type[] { typeof(long) }), milliseconds);
    }
    static object Session(object budget) {
        return Construct(SessionType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic, null, new Type[] { BudgetType }, null), budget);
    }
    static long Remaining(object budget) { return Convert.ToInt64(BudgetType.GetProperty("RemainingMilliseconds").GetValue(budget, null)); }
    static void Require() { Call(Native.GetMethod("RequireSelectionBudget", PrivateStatic), null); }
    static string Query(Func<string> action) { return (string)Call(Native.GetMethod("SelectionQuery", PrivateStatic).MakeGenericMethod(typeof(string)), null, action); }
    static void ActiveQuery() { Call(Native.GetMethod("RequireSelectionQueryActive", PrivateStatic), null); }
    static void Assert(bool value, string message) {
        assertions++; if (!value) throw new InvalidOperationException("SELF_TEST: " + message);
    }
    static Exception Error(Action action, string prefix) {
        try { action(); } catch (Exception error) {
            Assert(error.Message.StartsWith(prefix, StringComparison.Ordinal), "Expected " + prefix + "; got " + error.GetType().Name);
            return error;
        }
        throw new InvalidOperationException("SELF_TEST: Expected " + prefix);
    }
    static void Expire(object budget) {
        Stopwatch limit = Stopwatch.StartNew();
        while (Remaining(budget) > 0 && limit.ElapsedMilliseconds < 2000) Thread.Sleep(1);
        Assert(Remaining(budget) == 0, "Short synthetic preparation reaches the actual monotonic deadline");
    }
    static void ResetWorker() {
        object worker = Worker.GetValue(null);
        if (worker == null) return;
        Call(worker.GetType().GetMethod("Abandon"), worker);
        Thread thread = (Thread)worker.GetType().GetField("thread", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(worker);
        Assert(thread.Join(2500), "Owned synthetic worker exits after its blocked delegate is released");
        Worker.SetValue(null, null);
    }
    static void Case(string name, Action<Dictionary<string, object>> body) {
        Dictionary<string, object> row = new Dictionary<string, object> { { "name", name }, { "ok", false } };
        cases.Add(row);
        try { body(row); row["ok"] = true; }
        catch (Exception error) { row["error"] = error.GetType().Name + ": " + error.Message; }
        finally {
            if (CurrentSession.GetValue(null) != null) {
                ((IDisposable)CurrentSession.GetValue(null)).Dispose();
                row["ok"] = false; row["scopeLeaked"] = true;
            }
        }
    }
    static void DefaultAndPreparationCases() {
        Case("production-default-5000-and-dispose-ends-scope", delegate(Dictionary<string, object> row) {
            object session = Construct(SessionType.GetConstructor(Type.EmptyTypes));
            object budget = SessionType.GetField("Budget").GetValue(session);
            try {
                Assert(Convert.ToInt64(BudgetType.GetProperty("LimitMilliseconds").GetValue(budget, null)) == 5000, "Production default is exactly5000ms");
                Assert(Object.ReferenceEquals(CurrentSession.GetValue(null), session), "Caller owns current session");
                Require(); row["defaultLimitMilliseconds"] = 5000;
            } finally { ((IDisposable)session).Dispose(); }
            Assert(CurrentSession.GetValue(null) == null && Remaining(budget) == 0, "Dispose clears current scope and ends its budget");
        });
        Case("non-uia-preparation-expires-before-input-guard", delegate(Dictionary<string, object> row) {
            object budget = Budget(25), session = Session(budget); int simulatedInputs = 0;
            try { Expire(budget); Exception error = Error(delegate { Require(); simulatedInputs++; }, "SELECTION:"); Assert(error.GetType().Name == "SelectionBudgetExceededException", "Preparation fails specifically at its shared budget guard"); Assert(simulatedInputs == 0, "Expired pre-input guard sends no input"); }
            finally { ((IDisposable)session).Dispose(); }
            row["inputGuardPassed"] = false; row["simulatedInputs"] = simulatedInputs;
        });
    }
    static void CopyCase(string name, bool failRestore, bool newCopy) {
        Case(name, delegate(Dictionary<string, object> row) {
            uint generation = 10;
            int restores = 0, reads = 0; bool published = false;
            Dictionary<string, object> original = new Dictionary<string, object> { { "UnicodeText", "generated original" }, { "HTML Format", "<b>generated original</b>" }, { "fixture/custom", new byte[] { 7, 31, 9 } } };
            Dictionary<string, object> restored = null;
            Type ticketType = Native.Assembly.GetType("SelectionCopyTicket", true);
            object ticket = Construct(ticketType.GetConstructor(new Type[] { typeof(ulong) }), (ulong)17023);
            MethodInfo observe = ticketType.GetMethod("Observe");
            foreach (object[] phase in new object[][] {
                new object[] { 0x11, true, false, (ulong)17023 }, new object[] { 0x43, true, false, (ulong)17023 },
                new object[] { 0x43, false, true, (ulong)17023 }, new object[] { 0x11, false, true, (ulong)17023 } }) Call(observe, ticket, phase);
            Action ticketGuard = delegate {
                if ((bool)ticketType.GetProperty("Superseded").GetValue(ticket, null)) throw new InvalidOperationException("CANCELLED: generated newer copy");
            };
            MethodInfo completeCopy = PolicyType.GetMethod("CompleteCopy");
            object budget = Budget(100), session = Session(budget);
            Stopwatch clock = new Stopwatch();
            try {
                Require(); long remainingAtIssue = Remaining(budget);
                Assert(remainingAtIssue > 0, "Synthetic copy is issued while the shared budget is still active");
                row["budgetRemainingAtSyntheticCopyIssuedMilliseconds"] = remainingAtIssue;
                clock.Start();
                Exception outcome = Error(delegate {
                    Call(completeCopy, null, (uint)10, (uint)4,
                        (Func<uint>)delegate { return generation; },
                        (Func<string>)delegate { reads++; return newCopy ? "generated independent copy" : "generated selected source"; },
                        (Action<uint>)delegate(uint expected) {
                            Assert(Remaining(budget) == 0, "The issued synthetic copy completes after the session expires"); restores++;
                            if (failRestore) throw new InvalidOperationException("CLIPBOARD_RESTORE_FAILED: generated restore failure");
                            restored = new Dictionary<string, object>(original);
                        }, (Func<long>)delegate { return clock.ElapsedMilliseconds; },
                        (Action)delegate {
                            if (Remaining(budget) == 0 && !published) {
                                published = true; generation = 11;
                                if (newCopy) { Call(observe, ticket, 0xA2, true, false, (ulong)0); Call(observe, ticket, 0x43, true, false, (ulong)0); }
                            } else Thread.Sleep(1);
                        }, null, (Action)Require, null, ticketGuard);
                }, newCopy ? "CANCELLED:" : failRestore ? "CLIPBOARD_RESTORE_FAILED:" : "SELECTION:");
                if (!newCopy && !failRestore) Assert(outcome.GetType().Name == "SelectionBudgetExceededException", "Post-restore rejection is specifically the expired shared budget");
                Assert(published, "Deadline expired only after the synthetic copy was issued");
                Assert(restores == (newCopy ? 0 : 1), "Only a newer copy skips restoration; budget expiration alone does not");
                if (!newCopy && !failRestore) {
                    Assert(restored != null && (string)restored["HTML Format"] == (string)original["HTML Format"]
                        && (string)restored["UnicodeText"] == (string)original["UnicodeText"]
                        && ((byte[])restored["fixture/custom"])[1] == 31, "Synthetic rich formats restore before budget rejection");
                }
            } finally { ((IDisposable)session).Dispose(); }
            row["syntheticCopyIssued"] = true; row["restoreCalls"] = restores; row["readCalls"] = reads;
            row["newCopySuperseded"] = newCopy; row["syntheticFormatsRestored"] = restored != null;
        });
    }
    static void WindowsQueryCases() {
        Case("scoped-query-can-exceed-old-two-second-limit", delegate(Dictionary<string, object> row) {
            ResetWorker(); object budget = Budget(4000), session = Session(budget); Stopwatch elapsed = Stopwatch.StartNew();
            try {
                string result = Query(delegate { using (ManualResetEvent delay = new ManualResetEvent(false)) delay.WaitOne(2200); return "generated query result"; });
                Assert(result == "generated query result" && elapsed.ElapsedMilliseconds >= 2000, "Scoped query uses remaining shared budget, not min(2s,remaining)");
                row["queryElapsedMilliseconds"] = elapsed.Elapsed.TotalMilliseconds;
            } finally { ((IDisposable)session).Dispose(); ResetWorker(); }
        });
        Case("cumulative-expiry-no-new-query-and-late-work-rejected", delegate(Dictionary<string, object> row) {
            ResetWorker(); Stopwatch total = Stopwatch.StartNew(); object budget = Budget(700), session = Session(budget);
            using (ManualResetEvent release = new ManualResetEvent(false)) using (ManualResetEvent finished = new ManualResetEvent(false)) {
                int secondStarted = 0, thirdStarted = 0, lateRpc = 0; bool sharedOnWorker = false;
                try {
                    Assert(Query(delegate { using (ManualResetEvent delay = new ManualResetEvent(false)) delay.WaitOne(300); return "first"; }) == "first", "First query completes within shared budget");
                    Error(delegate { Query(delegate {
                        Interlocked.Increment(ref secondStarted);
                        object trace = Native.GetField("selectionTrace", PrivateStatic).GetValue(null);
                        sharedOnWorker = Object.ReferenceEquals(trace.GetType().GetField("Budget").GetValue(trace), budget);
                        try { release.WaitOne(); ActiveQuery(); Interlocked.Increment(ref lateRpc); return "must not publish"; }
                        finally { finished.Set(); }
                    }); }, "SELECTION:");
                    row["cumulativeQueryElapsedMilliseconds"] = total.Elapsed.TotalMilliseconds;
                    Assert(total.ElapsedMilliseconds < 1500, "Second query consumes only the remaining shared700ms, not another independent2s or5s");
                    Exception afterExpiry = Error(delegate { Query(delegate { Interlocked.Increment(ref thirdStarted); return "must not queue"; }); }, "SELECTION:");
                    Assert(afterExpiry.GetType().Name == "SelectionBudgetExceededException", "New query is rejected by budget before consulting the poisoned worker");
                    Assert(secondStarted == 1 && thirdStarted == 0 && sharedOnWorker, "Cumulative expiry shares the same budget and prevents a new query");
                } finally {
                    release.Set(); if (secondStarted != 0) Assert(finished.WaitOne(2000), "Released late delegate exits");
                    ((IDisposable)session).Dispose(); ResetWorker();
                }
                Assert(lateRpc == 0, "A late abandoned delegate cannot start the next synthetic RPC");
                row["secondQueryStarted"] = secondStarted; row["queryAfterExpiryStarted"] = thirdStarted; row["lateRpcCalls"] = lateRpc;
            }
        });
        Case("unscoped-query-retains-two-second-deadline", delegate(Dictionary<string, object> row) {
            ResetWorker(); Assert(CurrentSession.GetValue(null) == null, "Standalone scalar query has no selection session");
            using (ManualResetEvent release = new ManualResetEvent(false)) using (ManualResetEvent finished = new ManualResetEvent(false)) {
                int started = 0; Stopwatch elapsed = Stopwatch.StartNew();
                try {
                    Error(delegate { Query(delegate { Interlocked.Increment(ref started); try { release.WaitOne(); ActiveQuery(); return "must not publish"; } finally { finished.Set(); } }); }, "SELECTION:");
                    Assert(started == 1 && elapsed.ElapsedMilliseconds >= 1800 && elapsed.ElapsedMilliseconds < 4500, "Unscoped timeout remains2s without diagnostic drain");
                    row["queryElapsedMilliseconds"] = elapsed.Elapsed.TotalMilliseconds;
                } finally { release.Set(); if (started != 0) Assert(finished.WaitOne(2000), "Released standalone delegate exits"); ResetWorker(); }
            }
        });
    }
    static Dictionary<string, object> RunCore(Assembly assembly, bool windowsQueries) {
        assertions = 0; cases.Clear(); Native = assembly.GetType("EchoLingoNative", true);
        BudgetType = Native.GetNestedType("SelectionBudget", BindingFlags.NonPublic); SessionType = Native.GetNestedType("SelectionSession", BindingFlags.NonPublic);
        PolicyType = assembly.GetType("SelectionCopyPolicy", true);
        CurrentSession = Native.GetField("currentSelectionSession", PrivateStatic); Worker = Native.GetField("selectionWorker", PrivateStatic);
        Assert(BudgetType != null && SessionType != null && CurrentSession != null && Worker != null, "Exact private production budget API exists");
        Assert(CurrentSession.GetValue(null) == null, "Fresh fixture has no preexisting session");
        Assert(!(bool)assembly.GetType("CapturePerformance", true).GetProperty("Enabled").GetValue(null, null), "Isolated fixture has no diagnostic drain enabled");
        DefaultAndPreparationCases();
        CopyCase("expired-after-copy-restores-before-budget-rejection", false, false);
        CopyCase("restore-failure-takes-precedence-over-expired-budget", true, false);
        CopyCase("new-copy-still-supersedes-expired-session", false, true);
        if (windowsQueries) WindowsQueryCases();
        int passed = 0, purePassed = 0; for (int i = 0; i < cases.Count; i++) if ((bool)cases[i]["ok"]) { passed++; if (i < 5) purePassed++; }
        int required = windowsQueries ? 8 : 5;
        return new Dictionary<string, object> {
            { "ok", cases.Count == required && passed == required }, { "selectionBudgetFixturePassed", windowsQueries && cases.Count == required && passed == required },
            { "pureBudgetPolicyPassed", purePassed == 5 }, { "requiredCases", required }, { "executedCases", cases.Count }, { "passedCases", passed }, { "assertions", assertions },
            { "cases", new List<Dictionary<string, object>>(cases) }, { "windowsQueryThreadTested", windowsQueries }, { "actualUIAProviderTested", false },
            { "inputSent", false }, { "clipboardAccessed", false }, { "nativeHooksInstalled", false }, { "generatedDataOnly", true }
        };
    }
    public static Dictionary<string, object> Run(Assembly assembly) { return RunCore(assembly, true); }
    // Host evidence only; never reports the Windows query fixture as passed.
    public static Dictionary<string, object> RunPureBudget(Assembly assembly) { return RunCore(assembly, false); }
}
