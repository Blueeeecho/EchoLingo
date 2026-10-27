# Windows PowerShell 5.1, built-in .NET Framework, UI Automation and Windows OCR.
# No download, OCR package, PowerShell module or network access is required.
[CmdletBinding()]
param(
    [ValidateSet('selected-text', 'capture-ocr', 'capture-image', 'clipboard', 'copy', 'diagnostics', 'self-test', 'capture-state-self-test')]
    [string]$Mode = $env:ECHOLINGO_NATIVE_MODE,
    # Production always supplies its embedded, content-addressed DLL. Omission
    # is the standalone source-development/fixture path, never a load fallback.
    [string]$NativeAssemblyPath = '',
    [switch]$PerformanceDiagnostics,
    # Explicit standalone capture-image diagnostics only. Packaged Rust calls
    # never select this switch; it exercises the same HWND fallback without a
    # global mouse hook, while retaining Escape cancellation.
    [ValidateSet('hybrid', 'planeOnly')]
    [string]$InputBackend = 'hybrid',
    # Explicit packaged native session. No source/window content is transferred.
    [uint32]$CaptureHostThreadId = 0,
    [long]$CaptureHostToken = 0,
    [string]$NativeCancellationEvent = '',
    [uint32]$ExcludedSourceProcessId = 0
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
$script:NativeBackend = 'uninitialized'
$script:HelperWatch = [Diagnostics.Stopwatch]::StartNew()
$script:HelperPhases = @{}

function Write-Result($Value) {
    $Value['nativeBackend'] = $script:NativeBackend
    if ('CaptureHealth' -as [type]) {
        [CaptureHealth]::Mark('replyAtMilliseconds')
        [CaptureHealth]::Duration('releaseToReplyMilliseconds','releaseAtMilliseconds')
        if ($script:HelperPhases.ContainsKey('ocrRecognizedMilliseconds')) {
            [CaptureHealth]::Set('ocrDurationMilliseconds',[long]($script:HelperPhases['ocrRecognizedMilliseconds']-$script:HelperPhases['ocrStartMilliseconds']))
        }
        $Value['captureHealth'] = [CaptureHealth]::Snapshot()
    }
    if ($PerformanceDiagnostics) {
        $script:HelperPhases['replyMilliseconds'] = $script:HelperWatch.Elapsed.TotalMilliseconds
        $Value['helperPerformance'] = $script:HelperPhases
        if ('CapturePerformance' -as [type]) { $Value['capturePerformance'] = [CapturePerformance]::Snapshot() }
    }
    [Console]::Out.WriteLine(($Value | ConvertTo-Json -Depth 12 -Compress))
}

try {
    if (($CaptureHostThreadId -eq 0) -ne ($CaptureHostToken -eq 0) -or $CaptureHostToken -lt 0 -or
        ($CaptureHostThreadId -ne 0 -and ($Mode -notin 'capture-ocr','capture-image' -or $InputBackend -ne 'hybrid'))) {
        throw 'CAPTURE_ARGUMENT: Native input session parameters are invalid.'
    }
    if ($InputBackend -eq 'planeOnly' -and $Mode -ne 'capture-image') {
        throw 'CAPTURE_ARGUMENT: planeOnly is available only for explicit capture-image diagnostics.'
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName WindowsBase
    $script:HelperPhases['assembliesLoadedMilliseconds'] = $script:HelperWatch.Elapsed.TotalMilliseconds
    if (-not [string]::IsNullOrWhiteSpace($NativeAssemblyPath)) {
        $script:NativeBackend = 'precompiled-framework-dll'
        if (-not [IO.Path]::IsPathRooted($NativeAssemblyPath) -or -not [IO.File]::Exists($NativeAssemblyPath) -or
            [IO.Path]::GetExtension($NativeAssemblyPath) -ne '.dll') {
            throw 'NATIVE_ASSEMBLY: The packaged Windows native DLL is missing or invalid.'
        }
        try {
            Add-Type -Path $NativeAssemblyPath
            if (-not ('EchoLingoNative' -as [type]) -or -not ('CapturePerformance' -as [type]) -or
                -not [string]::Equals([IO.Path]::GetFullPath([EchoLingoNative].Assembly.Location), [IO.Path]::GetFullPath($NativeAssemblyPath), [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Native types do not belong to the packaged DLL.'
            }
        }
        catch { throw 'NATIVE_ASSEMBLY: The packaged Windows native DLL could not be loaded. Reinstall the application.' }
    } else {
    $script:NativeBackend = 'source-compiled-cli'
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using System.Windows.Forms;

// Pure policies shared by the real UIA/copy path and synthetic tests. A null
// UIA result is unavailable, while a supported empty range remains an explicit
// empty selection. A clipboard clear alone is not a completed copy operation.
// Numeric, opt-in in-process timings only. No source/window/clipboard content.
public static class CapturePerformance {
    static readonly Stopwatch clock = new Stopwatch();
    static readonly Dictionary<string, double> values = new Dictionary<string, double>();
    public static bool Enabled { get; private set; }
    public static void Enable() { values.Clear(); clock.Restart(); Enabled = true; }
    public static long Begin() { return Enabled ? Stopwatch.GetTimestamp() : 0; }
    public static void Mark(string stage) { if (Enabled && !values.ContainsKey(stage)) values[stage] = clock.Elapsed.TotalMilliseconds; }
    public static void Set(string name, double value) { if (Enabled) values[name] = value; }
    public static void End(string name, long started) {
        if (!Enabled || started == 0) return;
        double elapsed = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency, count, total, maximum;
        values.TryGetValue(name + "Count", out count); values.TryGetValue(name + "TotalMilliseconds", out total); values.TryGetValue(name + "MaxMilliseconds", out maximum);
        values[name + "Count"] = count + 1; values[name + "TotalMilliseconds"] = total + elapsed;
        values[name + "MaxMilliseconds"] = Math.Max(maximum, elapsed);
    }
    public static Dictionary<string, double> Snapshot() { return new Dictionary<string, double>(values); }
}

public static class CaptureHealth {
    static readonly Dictionary<string, long> values = new Dictionary<string, long>();
    static readonly Stopwatch clock=Stopwatch.StartNew();
    public static void Mark(string name){if(!values.ContainsKey(name))values[name]=clock.ElapsedMilliseconds;}
    public static void Duration(string name,string start){long began;if(values.TryGetValue(start,out began))values[name]=Math.Max(0,clock.ElapsedMilliseconds-began);}
    public static void Set(string name, long value) { values[name] = value; }
    public static void Increment(string name) { long value;values.TryGetValue(name,out value);values[name]=value+1; }
    public static Dictionary<string, long> Snapshot() { return new Dictionary<string, long>(values); }
}

// A clipboard owner/sequence cannot identify a copy transaction. This ticket
// only detects a distinct keyboard copy intent; background writes by the same
// process remain outside that guarantee. No text or general key history is kept.
public sealed class SelectionCopyTicket {
    readonly ulong marker;
    int controls, ownControls, ownPhases, superseded;
    public SelectionCopyTicket(ulong value) { if (value == 0) throw new ArgumentException("A copy input marker is required."); marker = value; }
    public void Observe(int key, bool down, bool up, ulong extra) {
        int control = key == 0x11 ? 1 : key == 0xA2 ? 2 : key == 0xA3 ? 4 : 0;
        if (extra == marker) {
            if (control != 0) { if (down) ownControls = 1; if (up) ownControls = 0; }
            int phase = control != 0 ? (down ? 1 : up ? 8 : 0) : key == 0x43 ? (down ? 2 : up ? 4 : 0) : 0;
            Interlocked.Exchange(ref ownPhases, ownPhases | phase);
            return;
        }
        if (control != 0) { if (down) controls |= control; if (up) controls &= ~control; }
        if (down && (controls | ownControls) != 0 && (key == 0x43 || key == 0x2D)) Interlocked.Exchange(ref superseded, 1);
    }
    public bool Superseded { get { return Interlocked.CompareExchange(ref superseded, 0, 0) != 0; } }
    public bool OwnInputObserved { get { return Interlocked.CompareExchange(ref ownPhases, 0, 0) == 15; } }
}

// Created only immediately before the single clipboard fallback injection.
// The direct UIA path never starts this thread or installs a hook. The callback
// forwards every key and only updates bounded scalar ticket state.
sealed class SelectionCopyObserver : IDisposable {
    delegate IntPtr KeyboardHook(int code, IntPtr message, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] struct KeyboardData { public uint key, scan, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct NativeMessage { public IntPtr window; public uint message; public UIntPtr word; public IntPtr parameter; public uint time; public int x, y; public uint privateData; }
    [DllImport("user32.dll", EntryPoint="SetWindowsHookExW", SetLastError=true)] static extern IntPtr SetHook(int id, KeyboardHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll", SetLastError=true)] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] static extern bool PeekMessage(out NativeMessage message, IntPtr window, uint min, uint max, uint remove);
    [DllImport("user32.dll", SetLastError=true)] static extern int GetMessage(out NativeMessage message, IntPtr window, uint min, uint max);
    [DllImport("user32.dll", EntryPoint="PostThreadMessageW", SetLastError=true)] static extern bool PostThreadMessage(uint thread, uint message, UIntPtr word, IntPtr parameter);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string module);
    readonly SelectionCopyTicket ticket;
    readonly KeyboardHook callback;
    readonly ManualResetEvent ready;
    readonly Thread thread;
    IntPtr hook;
    volatile uint threadId;
    volatile bool running, inputIssued;
    volatile string failure;
    int stopRequested, disposed;
    public UIntPtr Marker { get; private set; }
    public SelectionCopyObserver() {
        byte[] bytes = new byte[IntPtr.Size];
        using (System.Security.Cryptography.RandomNumberGenerator random = System.Security.Cryptography.RandomNumberGenerator.Create()) random.GetBytes(bytes);
        ulong value = IntPtr.Size == 8 ? BitConverter.ToUInt64(bytes, 0) : BitConverter.ToUInt32(bytes, 0);
        if (value == 0) throw new InvalidOperationException("SELECTION: Windows could not initialize copy observation; no copy input was sent.");
        Marker = IntPtr.Size == 8 ? new UIntPtr(value) : new UIntPtr((uint)value);
        ticket = new SelectionCopyTicket(value); callback = OnKeyboard;
        ready = new ManualResetEvent(false);
        thread = new Thread(Run);
        try { thread.IsBackground = true; thread.Name = "EchoLingo copy input"; thread.SetApartmentState(ApartmentState.MTA); thread.Start(); if (!ready.WaitOne(1000)) throw new InvalidOperationException("SELECTION: Copy observation did not start in time; no copy input was sent."); RequireCurrent(); }
        catch { Dispose(); throw; }
    }
    void Run() {
        try {
            threadId = GetCurrentThreadId(); NativeMessage message;
            PeekMessage(out message, IntPtr.Zero, 0, 0, 0);
            hook = SetHook(13, callback, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero) { failure = "install"; return; }
            running = true; ready.Set();
            while (Interlocked.CompareExchange(ref stopRequested, 0, 0) == 0) {
                int result = GetMessage(out message, IntPtr.Zero, 0, 0);
                if (result == 0) break;
                if (result < 0) { failure = "message"; break; }
            }
        } catch { failure = "listener"; }
        finally {
            if (hook != IntPtr.Zero && !UnhookWindowsHookEx(hook)) failure = "unhook";
            hook = IntPtr.Zero; running = false; ready.Set(); GC.KeepAlive(callback);
        }
    }
    IntPtr OnKeyboard(int code, IntPtr message, IntPtr data) {
        if (code == 0) {
            try {
                int kind = message.ToInt32(); bool down = kind == 0x100 || kind == 0x104, up = kind == 0x101 || kind == 0x105;
                if (down || up) { KeyboardData key = (KeyboardData)Marshal.PtrToStructure(data, typeof(KeyboardData)); ticket.Observe((int)key.key, down, up, key.extra.ToUInt64()); }
            } catch { failure = "callback"; }
        }
        return CallNextHookEx(hook, code, message, data);
    }
    public void Issued() { RequireCurrent(); inputIssued = true; }
    public void RequireCurrent() {
        if (ticket.Superseded) throw new InvalidOperationException("CANCELLED: A new copy shortcut superseded selection capture; the newer clipboard was preserved.");
        if (failure != null || !running) throw new InvalidOperationException(inputIssued
            ? "CLIPBOARD_RESTORE_SKIPPED: Copy input observation was lost; current clipboard contents were preserved."
            : "SELECTION: Copy observation is unavailable; no copy input was sent.");
    }
    public void AwaitOwnInput(Func<long> elapsedMilliseconds) {
        while (!ticket.OwnInputObserved) {
            RequireCurrent();
            if (elapsedMilliseconds() >= 1200) throw new InvalidOperationException("CLIPBOARD_RESTORE_SKIPPED: Windows did not confirm the copy input; current clipboard contents were preserved.");
            Thread.Sleep(1); // Await actual input acknowledgement, not a settling delay.
        }
        RequireCurrent();
    }
    public void Finish() {
        RequireCurrent(); Dispose();
        if (ticket.Superseded) throw new InvalidOperationException("CANCELLED: A new copy shortcut superseded selection capture; the newer clipboard was preserved.");
        if (failure != null) throw new InvalidOperationException("SELECTION: Windows could not finish copy observation.");
    }
    public void Dispose() {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        Interlocked.Exchange(ref stopRequested, 1);
        if (threadId != 0 && running && !PostThreadMessage(threadId, 0x12, UIntPtr.Zero, IntPtr.Zero)) failure = "stop";
        if (thread.IsAlive && !thread.Join(1000)) { failure = "join"; return; }
        ready.Dispose(); GC.KeepAlive(callback);
    }
}

public static class SelectionCopyPolicy {
    public const string InputBlocked = "SELECTION: Windows blocked copy input. Elevated or protected apps may not allow selection capture; try screenshot OCR.";
    public static T RequireFocus<T>(T focused) where T : class {
        if (focused == null) throw new InvalidOperationException("SELECTION: The focused control is unavailable; select text and retry.");
        return focused;
    }
    public static bool CopyFallbackAllowed(string controlType) {
        // Known non-text windows, dialogs, buttons and menus must not receive a
        // blind copy. Pane/Custom retain the dedicated unsupported-provider
        // path, after native focus identity and top-level context validation.
        return controlType == "ControlType.Edit" || controlType == "ControlType.Document"
            || controlType == "ControlType.Text" || controlType == "ControlType.Custom"
            || controlType == "ControlType.Pane";
    }
    static string UnavailableSelection(bool fallbackAllowed) {
        if (!fallbackAllowed) throw new InvalidOperationException("NO_SELECTION: The focused control does not provide a text selection.");
        return null;
    }
    public static string ReadAutomation<T>(bool password, bool fallbackAllowed, bool hasTextPattern,
                                           Func<T[]> getSelection, Func<T, string> read, bool emptyIsUnavailable = false) where T : class {
        if (password) throw new InvalidOperationException("PROTECTED: Selected text is inside a password control.");
        if (!hasTextPattern) return UnavailableSelection(fallbackAllowed);
        T[] ranges;
        try { ranges = getSelection(); }
        // GetSelection documents this exception for unsupported selection.
        // Do not catch range-reading failures here: a stale/invalid provider
        // must not be converted into permission to send keyboard input.
        catch (InvalidOperationException) { return UnavailableSelection(fallbackAllowed); }
        string text = AutomationText(ranges, read, emptyIsUnavailable);
        return text ?? UnavailableSelection(fallbackAllowed);
    }
    public static string AutomationText<T>(T[] ranges, Func<T, string> read, bool emptyIsUnavailable = false) where T : class {
        // The whole array may legitimately be null when no caret is exposed.
        if (ranges == null) return null;
        StringBuilder text = new StringBuilder();
        foreach (T range in ranges) {
            if (range == null) throw new InvalidOperationException("SELECTION: The source returned an invalid text range; select text and retry.");
            string part = read(range);
            if (!String.IsNullOrEmpty(part)) { if (text.Length > 0) text.AppendLine(); text.Append(part); }
        }
        if (!String.IsNullOrWhiteSpace(text.ToString())) return text.ToString();
        if (emptyIsUnavailable) return null;
        throw new InvalidOperationException("NO_SELECTION: No text is selected in the source application.");
    }

    public enum Observation { Waiting, Completed, UnchangedTimeout, UnfinishedTimeout, Superseded }
    public sealed class Completion {
        readonly uint initial;
        uint? candidate;
        public uint CompletedSequence { get; private set; }
        public string CompletedText { get; private set; }
        public uint? CandidateSequence { get { return candidate; } }
        public Completion(uint initialSequence) { initial = initialSequence; }
        public Observation Observe(uint before, string text, uint after, long elapsedMilliseconds) {
            bool expired = elapsedMilliseconds >= 1200;
            if (candidate.HasValue && (before != after || candidate.Value != after)) return Observation.Superseded;
            // OleGetClipboard/GetData may render a delayed format and advance
            // the sequence during the first read. Discard that torn read in
            // full; only a coherent before/after snapshot can become the first
            // candidate. After that, every generation change still aborts.
            if (before != after) return expired ? Observation.UnfinishedTimeout : Observation.Waiting;
            if (after == initial) return expired ? Observation.UnchangedTimeout : Observation.Waiting;
            if (expired) return Observation.UnfinishedTimeout;
            if (!String.IsNullOrWhiteSpace(text)) {
                candidate = after;
                CompletedSequence = after; CompletedText = text;
                return Observation.Completed;
            } else if (candidate.HasValue) return Observation.Superseded;
            return Observation.Waiting;
        }
    }

    public static void RequireCurrentSequence(uint expected, uint current) {
        if (expected != current) throw new InvalidOperationException("CLIPBOARD_CHANGED: Another copy operation occurred; the newer clipboard was preserved. Retry.");
    }

    // Modifier release and lazy clipboard materialization may take time. Read
    // UIA again immediately before input so a newly focused password/confirmed
    // empty control cannot inherit the earlier unavailable-provider decision.
    public static string RevalidateAndCopy(Func<string> selection, Action requireContext, Func<string> copy) {
        requireContext();
        string direct = selection();
        requireContext();
        return !String.IsNullOrWhiteSpace(direct) ? direct : copy();
    }

    // Even a partial SendInput may already have inserted Ctrl-down + C-down.
    // Complete one bounded observation/restoration before reporting that input
    // failure. With zero/one inserted event, no copy was sent: do not claim or
    // restore an unrelated clipboard generation. No key input is retried here.
    public static string CompleteCopy(uint initial, uint inserted, Func<uint> sequence, Func<string> readText,
                                      Action<uint> restore, Func<long> elapsedMilliseconds, Action wait,
                                      Action<string> trace = null, Action requireContextAfterRestore = null, Action requireCopyOwner = null,
                                      Action requireCopyTicket = null) {
        bool inputFailed = inserted != 4;
        if (inserted < 2) throw new InvalidOperationException(InputBlocked);
        Completion completion = new Completion(initial);
        while (true) {
            if (requireCopyTicket != null) requireCopyTicket();
            uint before = sequence();
            string text;
            try { text = before == initial ? null : readText(); }
            catch (Exception error) {
                // A clipboard owner may still hold its publication lock.
                // Retry only the documented temporary-open HRESULT, within the
                // original deadline, without resending input or restoring data.
                if (error is System.Runtime.InteropServices.ExternalException && unchecked((uint)error.HResult) == 0x800401D0u && elapsedMilliseconds() < 1200) {
                    wait(); continue;
                }
                throw new InvalidOperationException("CLIPBOARD_RESTORE_SKIPPED: Copied text could not be read safely. The original clipboard was not restored over this uncertain update; current contents were preserved.");
            }
            if (requireCopyTicket != null) requireCopyTicket();
            uint after = sequence();
            if (before == after && after != initial && !String.IsNullOrWhiteSpace(text) && requireCopyOwner != null) {
                requireCopyOwner();
                after = sequence(); // Owner observation cannot admit a torn generation.
            }
            long elapsed = elapsedMilliseconds();
            uint? candidateBefore = completion.CandidateSequence;
            Observation observation = completion.Observe(before, text, after, elapsed);
            // Explicit synthetic-desktop diagnostics only: no copied text,
            // window titles, application identities or clipboard formats.
            if (trace != null) trace("SELECTION_TRACE before=" + before + " after=" + after
                + " candidateBefore=" + (candidateBefore.HasValue ? candidateBefore.Value.ToString() : "none")
                + " candidateAfter=" + (completion.CandidateSequence.HasValue ? completion.CandidateSequence.Value.ToString() : "none")
                + " elapsedMs=" + elapsed + " observation=" + observation);
            switch (observation) {
                case Observation.Waiting: wait(); break;
                case Observation.Completed:
                    RequireCurrentSequence(completion.CompletedSequence, sequence());
                    if (requireCopyOwner != null) requireCopyOwner();
                    if (requireCopyTicket != null) requireCopyTicket();
                    restore(completion.CompletedSequence);
                    if (inputFailed) throw new InvalidOperationException(InputBlocked);
                    // A completed copy still owns its necessary restoration.
                    // Only then reject a source-window/focus change, without
                    // returning that obsolete result to the translation view.
                    if (requireContextAfterRestore != null) requireContextAfterRestore();
                    if (requireCopyTicket != null) requireCopyTicket();
                    return completion.CompletedText;
                case Observation.UnchangedTimeout:
                    throw new InvalidOperationException(inputFailed ? InputBlocked : "NO_SELECTION: No text was copied. Try screenshot OCR for nonselectable text or apps running as administrator.");
                case Observation.UnfinishedTimeout:
                    throw new InvalidOperationException("CLIPBOARD_RESTORE_SKIPPED: Copy did not finish before the deadline, so the original clipboard could not be restored safely. Current contents were preserved; retry or use screenshot OCR.");
                default:
                    throw new InvalidOperationException("CLIPBOARD_CHANGED: Another clipboard update occurred during selection capture; the newer clipboard was preserved. Retry.");
            }
        }
    }
}

public static class EchoLingoNative {
    public static uint ExcludedSourceProcessId { get; set; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
    [DllImport("user32.dll", SetLastError=true)] static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll", SetLastError=true)] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] static extern int DwmFlush();
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll", SetLastError=true)] static extern bool BitBlt(IntPtr target, int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, int operation);
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion data; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mouse;
        [FieldOffset(0)] public KEYBDINPUT keyboard;
        [FieldOffset(0)] public HARDWAREINPUT hardware;
    }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct HARDWAREINPUT { public uint message; public ushort low, high; }

    public static void ConfigureDpi() {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
        catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
        // PowerShell's host may have already chosen a process DPI mode. Set
        // the helper UI thread as well, before enumerating monitors or HWNDs.
        try {
            if (SetThreadDpiAwarenessContext(new IntPtr(-4)) == IntPtr.Zero)
                SetThreadDpiAwarenessContext(new IntPtr(-3));
        } catch (EntryPointNotFoundException) { }
    }
    static bool ModifiersDown() {
        foreach (int key in new int[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })
            if ((GetAsyncKeyState(key) & 0x8000) != 0) return true;
        return false;
    }
    sealed class SelectionContext {
        public IntPtr Foreground;
        public int[] FocusIdentity;
        public int InitialRoleId;
        public readonly HashSet<int> SourceProcesses = new HashSet<int>();
    }
    sealed class SelectionBudgetExceededException : InvalidOperationException {
        public SelectionBudgetExceededException() : base("SELECTION: The selected-text accessibility budget was exhausted; no further copy input was sent.") { }
    }
    sealed class SelectionBudget {
        readonly Stopwatch elapsed = Stopwatch.StartNew();
        volatile bool ended;
        public long LimitMilliseconds { get; private set; }
        public SelectionBudget(long milliseconds) {
            if (milliseconds <= 0) throw new ArgumentOutOfRangeException("milliseconds");
            LimitMilliseconds = milliseconds;
        }
        public long RemainingMilliseconds { get { return ended ? 0 : Math.Max(0, LimitMilliseconds - elapsed.ElapsedMilliseconds); } }
        public double ElapsedMilliseconds { get { return elapsed.Elapsed.TotalMilliseconds; } }
        public bool Expired { get { return RemainingMilliseconds <= 0; } }
        public void RequireActive() {
            if (Expired) throw new SelectionBudgetExceededException();
        }
        public void End() { ended = true; }
    }
    sealed class SelectionSession : IDisposable {
        readonly SelectionSession previous;
        public readonly SelectionBudget Budget;
        bool disposed;
        public SelectionSession() : this(new SelectionBudget(5000)) { }
        // Private injectable budget is used by isolated reflection fixtures;
        // the sole production entry above always uses the fixed 5000ms budget.
        SelectionSession(SelectionBudget budget) {
            if (budget == null) throw new ArgumentNullException("budget");
            previous = currentSelectionSession; Budget = budget; currentSelectionSession = this;
        }
        public void RequireActive() { Budget.RequireActive(); }
        public void Dispose() {
            if (disposed) return; disposed = true; Budget.End();
            if (Object.ReferenceEquals(currentSelectionSession, this)) currentSelectionSession = previous;
        }
    }
    [ThreadStatic] static SelectionSession currentSelectionSession;
    static void RequireSelectionBudget() {
        SelectionSession session = currentSelectionSession;
        if (session == null || !session.Budget.Expired) return;
        lock (selectionWorkerGate) { if (selectionWorker != null) selectionWorker.Abandon(); }
        session.RequireActive();
    }
    // One windowless MTA owns all UIA calls for this helper invocation. Never
    // move live AutomationElements between apartments or abort a provider call.
    sealed class SelectionAutomationWorker {
        readonly object gate = new object();
        readonly AutoResetEvent wake = new AutoResetEvent(false);
        readonly Thread thread;
        Action pending;
        bool unusable;
        public SelectionAutomationWorker() {
            thread = new Thread(Run); thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.MTA); thread.Start();
        }
        void Run() {
            while (true) {
                wake.WaitOne(); Action action;
                lock (gate) { if (unusable) return; action = pending; pending = null; }
                if (action != null) action();
                lock (gate) { if (unusable) return; }
            }
        }
        public Task<T> Enqueue<T>(Func<T> query) {
            TaskCompletionSource<T> result = new TaskCompletionSource<T>();
            lock (gate) {
                if (unusable || pending != null)
                    throw new InvalidOperationException("SELECTION: The accessibility query worker is unavailable; no copy input was sent.");
                pending = delegate { try { result.SetResult(query()); } catch (Exception error) { result.SetException(error); } };
                wake.Set();
            }
            return result.Task;
        }
        public void Abandon() { lock (gate) { unusable = true; wake.Set(); } }
    }
    sealed class SelectionTrace {
        public SelectionBudget Budget;
        public volatile int Stage, Depth;
        public volatile int InitialRoleId, FreshRoleId, InitialIdentityLength, FreshIdentityLength;
        public volatile int IdentityCompared, IdentityEqual, RootWalkReason, ExceptionKind;
        public volatile bool Abandoned;
        public void Mark(int stage, int depth) { Depth = depth; Stage = stage; }
    }
    static readonly object selectionWorkerGate = new object();
    static SelectionAutomationWorker selectionWorker;
    static int selectionQueryCount;
    [ThreadStatic] static SelectionTrace selectionTrace;
    static void SelectionStage(int stage, int depth) { if (selectionTrace != null) selectionTrace.Mark(stage, depth); }
    static void SelectionException(Exception error) {
        if (selectionTrace == null || selectionTrace.ExceptionKind != 0) return;
        selectionTrace.ExceptionKind = error is ElementNotAvailableException ? 1
            : error is OperationCanceledException ? 2 : error is ArgumentException ? 3
            : error is COMException ? 4 : error is InvalidOperationException ? 5 : 6;
    }
    static void RequireSelectionQueryActive() {
        NativeCancellation.ThrowIfRequested();
        if (selectionTrace != null && selectionTrace.Abandoned)
            throw new OperationCanceledException("CANCELLED: The accessibility query expired.");
        if (selectionTrace != null && selectionTrace.Budget != null) selectionTrace.Budget.RequireActive();
    }
    static T SelectionQuery<T>(Func<T> query) {
        NativeCancellation.ThrowIfRequested();
        RequireSelectionBudget();
        SelectionBudget budget = currentSelectionSession == null ? null : currentSelectionSession.Budget;
        long budgetRemainingAtStart = budget == null ? 0 : budget.RemainingMilliseconds;
        SelectionAutomationWorker worker;
        lock (selectionWorkerGate) {
            if (selectionWorker == null) selectionWorker = new SelectionAutomationWorker();
            worker = selectionWorker;
        }
        SelectionTrace trace = new SelectionTrace(); trace.Budget = budget;
        int index = ++selectionQueryCount;
        Stopwatch elapsed = Stopwatch.StartNew();
        bool deadlineExceeded = false, drainAttempted = false, completionObserved = false, drainCancelled = false, drainObservationError = false;
        double outcomeMilliseconds = -1, drainMilliseconds = 0, completionObservedMilliseconds = 0;
        double budgetElapsedAtOutcome = -1;
        int outcomeStage = -1, outcomeDepth = 0, outcomeExceptionKind = 0;
        Task<T> task = worker.Enqueue(delegate {
            selectionTrace = trace; SelectionStage(1, 0);
            try { RequireSelectionQueryActive(); return query(); } catch (Exception error) { SelectionException(error); throw; }
            finally { selectionTrace = null; }
        });
        try {
            while (!task.IsCompleted) {
                NativeCancellation.ThrowIfRequested();
                if (budget == null ? elapsed.ElapsedMilliseconds >= 2000 : budget.Expired) {
                    deadlineExceeded = true;
                    if (budget != null) budget.RequireActive();
                    throw new InvalidOperationException("SELECTION: The source accessibility provider did not answer in time; no copy input was sent.");
                }
                Thread.Sleep(5); // Condition polling, never a fixed preparation delay.
            }
            NativeCancellation.ThrowIfRequested();
            if (budget != null) budget.RequireActive();
            if (task.IsFaulted) throw task.Exception.InnerException;
            return task.Result;
        } catch (Exception queryError) {
            if (queryError is SelectionBudgetExceededException) deadlineExceeded = true;
            outcomeMilliseconds = elapsed.Elapsed.TotalMilliseconds;
            budgetElapsedAtOutcome = budget == null ? 0 : budget.ElapsedMilliseconds;
            outcomeStage = trace.Stage; outcomeDepth = trace.Depth; outcomeExceptionKind = trace.ExceptionKind;
            trace.Abandoned = true; worker.Abandon();
            // Only explicit diagnostics observe the one already-in-flight task.
            // The original deadline error remains the outcome. Never use its
            // late result, issue another provider call or hold up a new intent.
            if (deadlineExceeded && CapturePerformance.Enabled) {
                Stopwatch drain = new Stopwatch();
                try {
                    drainCancelled = NativeCancellation.Requested;
                    if (!drainCancelled) {
                        drainAttempted = true; drain.Start();
                        while (!task.IsCompleted && drain.ElapsedMilliseconds < 3000) {
                            if (NativeCancellation.Requested) { drainCancelled = true; break; }
                            Thread.Sleep(5); // Conditional observation, not a settling delay.
                        }
                    }
                    completionObserved = task.IsCompleted;
                    if (completionObserved) {
                        completionObservedMilliseconds = elapsed.Elapsed.TotalMilliseconds;
                        if (task.IsFaulted) GC.KeepAlive(task.Exception); // Observe, never serialize an error/result.
                    }
                } catch { drainObservationError = true; }
                finally {
                    drainMilliseconds = drain.Elapsed.TotalMilliseconds;
                }
            }
            throw;
        }
        finally {
            // Numeric diagnostics are opt-in. Only this calling thread writes
            // CapturePerformance, even when a timed-out provider is still busy.
            if (CapturePerformance.Enabled && index <= 16) {
                string prefix = "selectionQuery" + index;
                CapturePerformance.Set(prefix + "Milliseconds", outcomeMilliseconds < 0 ? elapsed.Elapsed.TotalMilliseconds : outcomeMilliseconds);
                CapturePerformance.Set(prefix + "Stage", outcomeStage < 0 ? trace.Stage : outcomeStage);
                CapturePerformance.Set(prefix + "Depth", outcomeStage < 0 ? trace.Depth : outcomeDepth);
                CapturePerformance.Set(prefix + "InitialRoleId", trace.InitialRoleId);
                CapturePerformance.Set(prefix + "FreshRoleId", trace.FreshRoleId);
                CapturePerformance.Set(prefix + "InitialIdentityLength", trace.InitialIdentityLength);
                CapturePerformance.Set(prefix + "FreshIdentityLength", trace.FreshIdentityLength);
                CapturePerformance.Set(prefix + "IdentityCompared", trace.IdentityCompared);
                CapturePerformance.Set(prefix + "IdentityEqual", trace.IdentityEqual);
                CapturePerformance.Set(prefix + "RootWalkReason", trace.RootWalkReason);
                CapturePerformance.Set(prefix + "ExceptionKind", outcomeStage < 0 ? trace.ExceptionKind : outcomeExceptionKind);
                if (budget != null) {
                    CapturePerformance.Set(prefix + "BudgetLimitMilliseconds", budget.LimitMilliseconds);
                    CapturePerformance.Set(prefix + "BudgetRemainingAtStartMilliseconds", budgetRemainingAtStart);
                    CapturePerformance.Set(prefix + "BudgetElapsedAtOutcomeMilliseconds", budgetElapsedAtOutcome < 0 ? budget.ElapsedMilliseconds : budgetElapsedAtOutcome);
                }
                if (deadlineExceeded) {
                    CapturePerformance.Set(prefix + "DeadlineExceeded", 1);
                    CapturePerformance.Set(prefix + "DrainAttempted", drainAttempted ? 1 : 0);
                    CapturePerformance.Set(prefix + "DrainMilliseconds", drainMilliseconds);
                    CapturePerformance.Set(prefix + "DrainCancelled", drainCancelled ? 1 : 0);
                    CapturePerformance.Set(prefix + "DrainObservationError", drainObservationError ? 1 : 0);
                    CapturePerformance.Set(prefix + "WorkerCompletionObserved", completionObserved ? 1 : 0);
                    CapturePerformance.Set(prefix + "WorkerCompletionObservedMilliseconds", completionObservedMilliseconds);
                    CapturePerformance.Set(prefix + "WorkerStillBlocked", task.IsCompleted ? 0 : 1);
                    CapturePerformance.Set(prefix + "WorkerStageAtDrainEnd", trace.Stage);
                    CapturePerformance.Set(prefix + "WorkerExceptionKindAtDrainEnd", trace.ExceptionKind);
                }
            }
        }
    }
    static bool SameIdentity(int[] expected, int[] current) {
        if (expected == null || current == null || expected.Length == 0 || expected.Length != current.Length) return false;
        for (int i = 0; i < expected.Length; i++) if (expected[i] != current[i]) return false;
        return true;
    }
    static CacheRequest SelectionCache() {
        CacheRequest cache = new CacheRequest();
        cache.TreeScope = TreeScope.Element;
        cache.TreeFilter = Automation.RawViewCondition;
        cache.AutomationElementMode = AutomationElementMode.Full;
        cache.Add(AutomationElement.ProcessIdProperty);
        cache.Add(AutomationElement.NativeWindowHandleProperty);
        cache.Add(AutomationElement.ControlTypeProperty);
        cache.Add(AutomationElement.IsPasswordProperty);
        return cache;
    }
    static bool FocusBelongsToWindow(AutomationElement focused, IntPtr foreground, CacheRequest cache, out List<AutomationElement> ancestors) {
        ancestors = new List<AutomationElement>();
        IntPtr root = GetAncestor(foreground, 2); // GA_ROOT, not process identity.
        if (root == IntPtr.Zero) { if (selectionTrace != null) selectionTrace.RootWalkReason = 2; SelectionStage(12, 0); return false; }
        AutomationElement current = focused;
        for (int depth = 0; current != null && depth < 64; depth++) {
            RequireSelectionQueryActive(); SelectionStage(4, depth);
            AutomationElement.AutomationElementInformation info = current.Cached;
            if (info.IsPassword) { if (selectionTrace != null) selectionTrace.RootWalkReason = 6; SelectionStage(16, depth); throw new InvalidOperationException("PROTECTED: Selected text is inside a password control."); }
            int handle = info.NativeWindowHandle;
            if (handle != 0 && GetAncestor(new IntPtr(handle), 2) != root) { if (selectionTrace != null) selectionTrace.RootWalkReason = 3; SelectionStage(13, depth); return false; }
            ancestors.Add(current);
            if (handle != 0 && new IntPtr(handle) == root) { if (selectionTrace != null) selectionTrace.RootWalkReason = 1; return true; }
            SelectionStage(5, depth);
            RequireSelectionQueryActive();
            current = TreeWalker.RawViewWalker.GetParent(current, cache);
        }
        if (selectionTrace != null) selectionTrace.RootWalkReason = current == null ? 5 : 4;
        SelectionStage(current == null ? 15 : 14, ancestors.Count); return false;
    }
    static AutomationElement CurrentSelectionFocus(SelectionContext context, out List<AutomationElement> ancestors) {
        try {
            if (context.Foreground == IntPtr.Zero || GetForegroundWindow() != context.Foreground) {
                SelectionStage(18, 0);
                throw new InvalidOperationException("SELECTION: Foreground application changed; select text and retry.");
            }
            CacheRequest cache = SelectionCache(); AutomationElement focused;
            RequireSelectionQueryActive(); SelectionStage(2, 0);
            focused = SelectionCopyPolicy.RequireFocus(AutomationElement.FocusedElement);
            SelectionStage(21, 0); RequireSelectionQueryActive();
            SelectionStage(22, 0);
            focused = focused.GetUpdatedCache(cache);
            SelectionStage(23, 0);
            RequireSelectionQueryActive(); int roleId = 0;
            // Cached role reads add no provider RPC. Diagnostic unavailability
            // must not become a new acquisition failure or weaken a guard.
            if (CapturePerformance.Enabled) { SelectionStage(20, 0); try { ControlType role = focused.Cached.ControlType; if (role != null) roleId = role.Id; } catch { } }
            if (selectionTrace != null) { selectionTrace.InitialRoleId = context.FocusIdentity == null ? roleId : context.InitialRoleId; selectionTrace.FreshRoleId = roleId; }
            RequireSelectionQueryActive(); SelectionStage(3, 0); int[] identity = focused.GetRuntimeId(); SelectionStage(10, 0);
            bool identityCompared = context.FocusIdentity != null;
            bool identityEqual = identityCompared && SameIdentity(context.FocusIdentity, identity);
            if (selectionTrace != null) {
                selectionTrace.InitialIdentityLength = context.FocusIdentity == null ? (identity == null ? 0 : identity.Length) : context.FocusIdentity.Length;
                selectionTrace.FreshIdentityLength = identity == null ? 0 : identity.Length;
                selectionTrace.IdentityCompared = identityCompared ? 1 : 0;
                selectionTrace.IdentityEqual = identityEqual ? 1 : 0;
            }
            if (identityCompared && !identityEqual) {
                SelectionStage(11, 0);
                throw new InvalidOperationException("SELECTION: The focused control changed or is outside the source window; select text and retry.");
            }
            if (!FocusBelongsToWindow(focused, context.Foreground, cache, out ancestors))
                throw new InvalidOperationException("SELECTION: The focused control changed or is outside the source window; select text and retry.");
            if (context.FocusIdentity == null) {
                if (identity == null || identity.Length == 0) {
                    SelectionStage(17, 0);
                    throw new InvalidOperationException("SELECTION: The source focus identity is unavailable; select text and retry.");
                }
                context.FocusIdentity = identity;
                context.InitialRoleId = roleId;
            }
            if (GetForegroundWindow() != context.Foreground) {
                SelectionStage(19, ancestors.Count);
                throw new InvalidOperationException("SELECTION: Foreground application changed; select text and retry.");
            }
            SelectionStage(9, ancestors.Count);
            return focused;
        } catch (ElementNotAvailableException error) {
            SelectionException(error);
            throw new InvalidOperationException("SELECTION: The source control is no longer available; select text and retry.");
        }
    }
    static AutomationElement CurrentSelectionFocus(SelectionContext context) {
        List<AutomationElement> ancestors; return CurrentSelectionFocus(context, out ancestors);
    }
    static void ValidateSelectionSourceRoot(SelectionContext context) {
        // Validate only the captured source's native root before asking for its
        // focus. This uses the same query worker/budget and reads no selection,
        // descendant, or preliminary FocusedElement identity.
        RequireSelectionQueryActive();
        IntPtr root = GetAncestor(context.Foreground, 2);
        uint process; uint thread = GetWindowThreadProcessId(root, out process);
        if (context.Foreground == IntPtr.Zero || root == IntPtr.Zero || process == 0 || thread == 0
            || GetForegroundWindow() != context.Foreground)
            throw new InvalidOperationException("SELECTION: The source window is no longer available; select text and retry.");
        SelectionStage(24, 0);
        AutomationElement source = AutomationElement.FromHandle(root);
        SelectionStage(25, 0); RequireSelectionQueryActive();
        if (source == null)
            throw new InvalidOperationException("SELECTION: The source window accessibility root is unavailable; select text and retry.");
        SelectionStage(26, 0);
        source = source.GetUpdatedCache(SelectionCache());
        SelectionStage(27, 0); RequireSelectionQueryActive();
        AutomationElement.AutomationElementInformation info = source.Cached;
        if (info.IsPassword)
            throw new InvalidOperationException("PROTECTED: Selected text is inside a password control.");
        uint currentProcess; uint currentThread = GetWindowThreadProcessId(root, out currentProcess);
        if (new IntPtr(info.NativeWindowHandle) != root || unchecked((uint)info.ProcessId) != process
            || info.ControlType == null || GetForegroundWindow() != context.Foreground
            || GetAncestor(context.Foreground, 2) != root || currentProcess != process || currentThread != thread)
            throw new InvalidOperationException("SELECTION: The source window accessibility root changed; select text and retry.");
        SelectionStage(28, 0);
    }
    static SelectionContext CaptureSelectionContext() {
        try {
            SelectionContext context = new SelectionContext();
            context.Foreground = GetForegroundWindow();
            uint nativePid; GetWindowThreadProcessId(context.Foreground, out nativePid);
            if (nativePid != 0 && nativePid == ExcludedSourceProcessId)
                throw new InvalidOperationException("NO_SELECTION: EchoLingo is the foreground application.");
            if (nativePid != 0) context.SourceProcesses.Add(unchecked((int)nativePid));
            ValidateSelectionSourceRoot(context);
            AutomationElement focused = CurrentSelectionFocus(context);
            int process = focused.Cached.ProcessId;
            if (process != 0) context.SourceProcesses.Add(process);
            return context;
        } catch (ElementNotAvailableException error) {
            SelectionException(error);
            throw new InvalidOperationException("SELECTION: The source control is no longer available; select text and retry.");
        }
    }
    static void RequireSelectionContext(SelectionContext context) {
        SelectionQuery(delegate { CurrentSelectionFocus(context); return true; });
    }
    static bool DocumentCopyAllowed(string role) {
        return SelectionCopyPolicy.CopyFallbackAllowed(role) || role == "ControlType.Hyperlink"
            || role == "ControlType.Group" || role == "ControlType.ListItem";
    }
    static string AutomationSelection(SelectionContext context) {
        try {
            List<AutomationElement> ancestors;
            AutomationElement focused = CurrentSelectionFocus(context, out ancestors);
            string focusedRole = focused.Cached.ControlType.ProgrammaticName;
            bool focusedEmpty = false, document = false;
            // Validate the complete bounded ancestor chain before reading any
            // selected text. A provider below a protected ancestor must never
            // disclose its range just because its own IsPassword is false.
            for (int depth = 0; depth < ancestors.Count; depth++) {
                RequireSelectionQueryActive(); SelectionStage(6, depth);
                AutomationElement element = ancestors[depth];
                string role = element.Cached.ControlType.ProgrammaticName;
                if (depth == 0 || role == "ControlType.Document" || role == "ControlType.Edit") {
                    RequireSelectionQueryActive(); object raw; bool available = element.TryGetCurrentPattern(TextPattern.Pattern, out raw);
                    TextPattern pattern = raw as TextPattern;
                    if (available && pattern == null) throw new InvalidOperationException("SELECTION: The source returned an invalid text provider; select text and retry.");
                    if (role == "ControlType.Document") {
                        document = true;
                        if (element.Cached.ProcessId != 0) context.SourceProcesses.Add(element.Cached.ProcessId);
                    }
                    if (available) {
                        // An empty Edit is authoritative. A document or its
                        // focused descendant can expose a different caret than
                        // the document selection; only walk this ancestor path.
                        string selected = SelectionCopyPolicy.ReadAutomation(false, true, true,
                            delegate { RequireSelectionQueryActive(); SelectionStage(7, depth); return pattern.GetSelection(); },
                            delegate(TextPatternRange range) { RequireSelectionQueryActive(); SelectionStage(8, depth); return range.GetText(-1); }, role != "ControlType.Edit");
                        if (!String.IsNullOrWhiteSpace(selected)) return selected;
                        if (depth == 0) focusedEmpty = true;
                    }
                    if (role == "ControlType.Edit") {
                        if (!SelectionCopyPolicy.CopyFallbackAllowed(focusedRole))
                            throw new InvalidOperationException("NO_SELECTION: The focused editable control does not provide a selection.");
                        return null; // Unsupported editable provider, not an empty valid range.
                    }
                }
            }
            if (document && DocumentCopyAllowed(focusedRole)) return null;
            if (!focusedEmpty && SelectionCopyPolicy.CopyFallbackAllowed(focusedRole)) return null;
            throw new InvalidOperationException("NO_SELECTION: No text is selected in the source application.");
        } catch (InvalidOperationException error) {
            if (error.Message.StartsWith("PROTECTED:") || error.Message.StartsWith("NO_SELECTION:") || error.Message.StartsWith("SELECTION:")) throw;
            throw new InvalidOperationException("SELECTION: The source selection query failed; select text and retry.");
        } catch (ElementNotAvailableException error) {
            SelectionException(error);
            throw new InvalidOperationException("SELECTION: The source control is no longer available; select text and retry.");
        }
    }
    static void RequireCopiedSourceOwner(SelectionContext context) {
        IntPtr owner = GetClipboardOwner(); uint process;
        if (owner == IntPtr.Zero || GetWindowThreadProcessId(owner, out process) == 0 || !context.SourceProcesses.Contains(unchecked((int)process)))
            throw new InvalidOperationException("CLIPBOARD_CHANGED: The new clipboard data does not belong to the verified source; current contents were preserved.");
    }
    static object CloneClipboardValue(object value) {
        if (value == null) throw new InvalidOperationException("Clipboard format could not be materialized.");
        Bitmap bitmap = value as Bitmap;
        if (bitmap != null) return new Bitmap(bitmap);
        Stream stream = value as Stream;
        if (stream != null) {
            if (!stream.CanSeek) throw new InvalidOperationException("Clipboard stream cannot be preserved safely.");
            long position = stream.Position;
            try { stream.Position = 0; MemoryStream copy = new MemoryStream(); stream.CopyTo(copy); copy.Position = 0; return copy; }
            finally { stream.Position = position; }
        }
        Array array = value as Array;
        if (array != null) return array.Clone();
        if (value is string || value.GetType().IsValueType) return value;
        throw new InvalidOperationException("Unsupported clipboard representation: " + value.GetType().Name);
    }
    static DataObject SnapshotClipboard(List<IDisposable> resources) {
        IDataObject existing = Clipboard.GetDataObject();
        DataObject saved = new DataObject();
        if (existing == null) return saved;
        foreach (string format in existing.GetFormats(false)) {
            object value = CloneClipboardValue(existing.GetData(format, false));
            IDisposable disposable = value as IDisposable;
            if (disposable != null) resources.Add(disposable);
            saved.SetData(format, false, value);
        }
        return saved;
    }
    static INPUT Key(ushort code, bool up) {
        return Key(code, up, UIntPtr.Zero);
    }
    static INPUT Key(ushort code, bool up, UIntPtr marker) {
        INPUT input = new INPUT(); input.type = 1;
        input.data.keyboard.vk = code; input.data.keyboard.flags = up ? 2u : 0u;
        input.data.keyboard.extra = marker;
        return input;
    }
    public static string SelectedText() {
        using (SelectionSession session = new SelectionSession()) {
            string result = SelectedTextCore();
            // Cleanup/restore exceptions from the core take precedence. The
            // budget may reject a cleaned-up result; it must never skip cleanup.
            RequireSelectionBudget();
            return result;
        }
    }
    static string SelectedTextCore() {
        NativeCancellation.ThrowIfRequested();
        SelectionContext context = SelectionQuery(CaptureSelectionContext);
        string direct = SelectionQuery(delegate { return AutomationSelection(context); });
        RequireSelectionContext(context);
        if (!String.IsNullOrWhiteSpace(direct)) return direct;
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(1500);
        while (ModifiersDown()) {
            NativeCancellation.ThrowIfRequested();
            RequireSelectionBudget();
            if (DateTime.UtcNow >= deadline) throw new InvalidOperationException("SELECTION: Release the shortcut keys and retry.");
            Thread.Sleep(20);
        }
        RequireSelectionContext(context);
        List<IDisposable> resources = new List<IDisposable>();
        DataObject saved;
        uint initial = GetClipboardSequenceNumber();
        try {
            NativeCancellation.ThrowIfRequested();
            saved = SnapshotClipboard(resources);
            if (GetClipboardSequenceNumber() != initial) throw new InvalidOperationException("Clipboard changed while its formats were being preserved. Retry.");
        }
        catch (OperationCanceledException) {
            foreach (IDisposable resource in resources) resource.Dispose(); throw;
        }
        catch (Exception error) {
            foreach (IDisposable resource in resources) resource.Dispose();
            throw new InvalidOperationException("CLIPBOARD: Cannot preserve all clipboard formats. Selection capture was stopped before changing the clipboard. " + error.Message);
        }
        try {
            return SelectionCopyPolicy.RevalidateAndCopy(delegate { return SelectionQuery(delegate { return AutomationSelection(context); }); },
                delegate {
                    NativeCancellation.ThrowIfRequested();
                    RequireSelectionContext(context);
                    if (ModifiersDown())
                        throw new InvalidOperationException("SELECTION: Foreground application or shortcut modifiers changed before copy; retry.");
                    SelectionCopyPolicy.RequireCurrentSequence(initial, GetClipboardSequenceNumber());
                }, delegate {
                    using (SelectionCopyObserver observer = new SelectionCopyObserver()) {
                    NativeCancellation.ThrowIfRequested();
                    RequireSelectionContext(context);
                    observer.RequireCurrent();
                    if (ModifiersDown()) throw new InvalidOperationException("SELECTION: Shortcut modifiers changed before copy; retry.");
                    SelectionCopyPolicy.RequireCurrentSequence(initial, GetClipboardSequenceNumber());
                    INPUT[] keys = new INPUT[] { Key(0x11, false, observer.Marker), Key(0x43, false, observer.Marker), Key(0x43, true, observer.Marker), Key(0x11, true, observer.Marker) };
                    Stopwatch clock = Stopwatch.StartNew();
                    observer.Issued();
                    RequireSelectionBudget();
                    uint inserted = SendInput((uint)keys.Length, keys, Marshal.SizeOf(typeof(INPUT)));
                    if (inserted != keys.Length) {
                        // Ensure our Ctrl-down cannot leave a modifier stuck.
                        INPUT[] release = new INPUT[] { Key(0x43, true, observer.Marker), Key(0x11, true, observer.Marker) };
                        SendInput((uint)release.Length, release, Marshal.SizeOf(typeof(INPUT)));
                    }
                    if (inserted >= 2) observer.AwaitOwnInput(delegate { return clock.ElapsedMilliseconds; });
                    string result = SelectionCopyPolicy.CompleteCopy(initial, inserted, GetClipboardSequenceNumber,
                        delegate { return Clipboard.ContainsText() ? Clipboard.GetText(TextDataFormat.UnicodeText) : null; },
                        delegate(uint copied) {
                            // Recheck immediately before the restoration write as well
                            // as before invoking this callback; a newer copy wins.
                            SelectionCopyPolicy.RequireCurrentSequence(copied, GetClipboardSequenceNumber());
                            observer.RequireCurrent();
                            try {
                                if (saved.GetFormats(false).Length == 0) {
                                    if (!OpenClipboard(IntPtr.Zero)) throw new InvalidOperationException("Clipboard is busy.");
                                    try {
                                        SelectionCopyPolicy.RequireCurrentSequence(copied, GetClipboardSequenceNumber());
                                        observer.RequireCurrent();
                                        if (!EmptyClipboard()) throw new InvalidOperationException("Cannot restore an empty clipboard.");
                                    } finally { CloseClipboard(); }
                                }
                                else { observer.RequireCurrent(); Clipboard.SetDataObject(saved, true, 0, 0); }
                            } catch (Exception error) {
                                if (error.Message.StartsWith("CANCELLED:", StringComparison.Ordinal)
                                    || error.Message.StartsWith("CLIPBOARD_RESTORE_SKIPPED:", StringComparison.Ordinal)) throw;
                                throw new InvalidOperationException("CLIPBOARD_RESTORE_FAILED: Could not restore original clipboard formats. " + error.Message);
                            }
                        }, delegate { return clock.ElapsedMilliseconds; }, delegate { Thread.Sleep(5); },
                        Environment.GetEnvironmentVariable("ECHOLINGO_SELECTION_TRACE") == "1"
                            ? (Action<string>)delegate(string message) { Console.Error.WriteLine(message); } : null,
                        delegate { NativeCancellation.ThrowIfRequested(); RequireSelectionContext(context); },
                        delegate { RequireCopiedSourceOwner(context); }, observer.RequireCurrent);
                    observer.Finish();
                    return result;
                    }
            });
        } finally { foreach (IDisposable resource in resources) resource.Dispose(); }
    }
    public static string ClipboardText() {
        if (!Clipboard.ContainsText()) throw new InvalidOperationException("CLIPBOARD_EMPTY: The clipboard does not contain text.");
        return Clipboard.GetText(TextDataFormat.UnicodeText);
    }
    public static void CopyText(string text) {
        if (String.IsNullOrEmpty(text)) { Clipboard.Clear(); return; }
        Clipboard.SetDataObject(text, true, 5, 40);
    }
    static Bitmap ScreenBitmap(Rectangle bounds) {
        if (bounds.Width < 3 || bounds.Height < 3 || bounds.Width > 16384 || bounds.Height > 16384 || (long)bounds.Width * bounds.Height > 32000000)
            throw new InvalidOperationException("CAPTURE_TOO_LARGE: Select a smaller region (maximum 32 million pixels).");
        Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        try {
            using (Graphics graphics = Graphics.FromImage(bitmap)) {
                IntPtr target = graphics.GetHdc();
                IntPtr source = GetDC(IntPtr.Zero);
                try {
                    if (source == IntPtr.Zero || !BitBlt(target, 0, 0, bounds.Width, bounds.Height, source, bounds.X, bounds.Y, 0x40CC0020))
                        throw new InvalidOperationException("CAPTURE: Windows could not capture the desktop.");
                } finally { if (source != IntPtr.Zero) ReleaseDC(IntPtr.Zero, source); graphics.ReleaseHdc(target); }
            }
            return bitmap;
        } catch { bitmap.Dispose(); throw; }
    }
    public static void CaptureRegion(string path) { CaptureRegion(path, true); }
    public static void CaptureRegion(string path, bool mouseHook) { CaptureRegion(path, mouseHook, 0, 0); }
    public static void CaptureRegion(string path, bool mouseHook, uint hostThread, long hostToken) {
        NativeCancellation.ThrowIfRequested();
        ConfigureDpi();
        try {
            if (GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext()) != 2)
                throw new InvalidOperationException("CAPTURE_DPI: Windows could not establish per-monitor capture coordinates.");
        } catch (EntryPointNotFoundException) {
            throw new InvalidOperationException("CAPTURE_DPI: This Windows version lacks per-monitor capture coordinates.");
        }
        using (RegionPicker picker = new RegionPicker(mouseHook, hostThread, hostToken)) {
            Rectangle selected = picker.SelectRegion();
            // Observing display changes continues after selection completion.
            // Validate both sides of BitBlt and discard pixels if the saved
            // physical rectangle no longer belongs to the same configuration.
            if (DwmFlush() < 0) throw new InvalidOperationException("CAPTURE: Windows could not finish removing the selection overlay.");
            CapturePerformance.Mark("dwmFlushedMilliseconds");
            picker.ValidateCaptureEnvironment();
            using (Bitmap crop = ScreenBitmap(selected)) {
                CapturePerformance.Mark("pixelsCapturedMilliseconds");
                picker.ValidateCaptureEnvironment();
                crop.Save(path, ImageFormat.Png);
                CapturePerformance.Mark("pngSavedMilliseconds");CaptureHealth.Duration("releaseToPngMilliseconds","releaseAtMilliseconds");
            }
        }
    }
    public static void CreateFixture(string path) {
        using (Bitmap bitmap = new Bitmap(1100, 160))
        using (Graphics graphics = Graphics.FromImage(bitmap))
        using (Font font = new Font("Arial", 38)) {
            graphics.Clear(Color.White);
            graphics.DrawString("EchoLingo translation 2468", font, Brushes.Black, 20, 40);
            bitmap.Save(path, ImageFormat.Png);
        }
    }
}

// Pure physical-pixel geometry/state. The real mouse hook and synthetic tests
// use this same policy; none of these methods reads the desktop or clipboard.
public sealed class CaptureSelectionState {
    readonly Rectangle[] screens;
    public readonly Rectangle Desktop;
    Point origin;
    public bool Dragging { get; private set; }
    public bool Finished { get; private set; }
    public bool Cancelled { get; private set; }
    public int Highlighted { get; private set; }
    public Rectangle Selected { get; private set; }
    public CaptureSelectionState(Rectangle[] displays, Point pointer) {
        if (displays == null || displays.Length == 0) throw new InvalidOperationException("CAPTURE: No display is available.");
        screens = (Rectangle[])displays.Clone();
        Rectangle desktop = screens[0];
        foreach (Rectangle screen in screens) {
            if (screen.Width <= 0 || screen.Height <= 0) throw new InvalidOperationException("CAPTURE: Invalid display geometry.");
            desktop = Rectangle.Union(desktop, screen);
        }
        Desktop = desktop;
        Move(pointer);
    }
    Point Clamp(Point point) {
        return new Point(Math.Max(Desktop.Left, Math.Min(Desktop.Right - 1, point.X)), Math.Max(Desktop.Top, Math.Min(Desktop.Bottom - 1, point.Y)));
    }
    public void Move(Point point) {
        if (Finished) return;
        Highlighted = -1;
        for (int i = 0; i < screens.Length; i++) if (screens[i].Contains(point)) { Highlighted = i; break; }
        if (Dragging) {
            Point end = Clamp(point);
            Selected = Rectangle.FromLTRB(Math.Min(origin.X, end.X), Math.Min(origin.Y, end.Y), Math.Max(origin.X, end.X), Math.Max(origin.Y, end.Y));
        }
    }
    public void Begin(Point point) {
        if (Finished || Dragging) return;
        Move(point);
        if (Highlighted < 0) return;
        origin = Clamp(point);
        Selected = Rectangle.Empty;
        Dragging = true;
    }
    public void End(Point point) {
        if (Finished || !Dragging) return;
        Move(point);
        Dragging = false;
        Finished = true;
        Cancelled = Selected.Width < 3 || Selected.Height < 3;
    }
    public void Cancel() { if (!Finished) { Dragging = false; Finished = true; Cancelled = true; } }
    public void Expire(long elapsedMilliseconds) { if (elapsedMilliseconds >= 120000) Cancel(); }

    static void Assert(bool value, string message) { if (!value) throw new InvalidOperationException("SELF_TEST: " + message); }
    public static Dictionary<string, object> SelfTest() {
        Rectangle[] displays = new Rectangle[] { new Rectangle(0, 0, 1920, 1080), new Rectangle(-2560, -300, 2560, 1440), new Rectangle(100, -1200, 1600, 900) };
        CaptureSelectionState state = new CaptureSelectionState(displays, new Point(-2000, 20));
        Assert(state.Highlighted == 1 && !state.Dragging && !state.Finished, "Pointer display must use negative physical coordinates.");
        state.Move(new Point(300, -900));
        Assert(state.Highlighted == 2, "Only the pointer's current display is highlighted.");
        state.Move(new Point(-2000, -900));
        Assert(state.Highlighted == -1, "A gap between screens must not highlight a different screen.");
        state.Begin(new Point(-2000, -900));
        Assert(!state.Dragging, "A drag cannot begin in a screen gap.");
        state.Begin(new Point(-100, 100)); state.Move(new Point(200, 300)); state.End(new Point(300, 350));
        Assert(state.Finished && !state.Cancelled && state.Selected == new Rectangle(-100, 100, 400, 250), "Cross-screen drag must return global physical coordinates.");
        Rectangle selected = state.Selected;
        state.Begin(new Point(10, 10)); state.Move(new Point(20, 20)); state.Cancel();
        Assert(state.Selected == selected && !state.Cancelled, "A completed capture cannot be replaced by a later event.");
        CaptureSelectionState reverse = new CaptureSelectionState(displays, Point.Empty);
        reverse.Begin(new Point(500, 400)); reverse.End(new Point(-200, -100));
        Assert(reverse.Selected == new Rectangle(-200, -100, 700, 500), "Reverse drag must preserve negative origins.");
        CaptureSelectionState tiny = new CaptureSelectionState(displays, Point.Empty);
        tiny.Begin(new Point(10, 10)); tiny.End(new Point(11, 30));
        Assert(tiny.Cancelled, "A tiny selection must not capture anything.");
        CaptureSelectionState timeout = new CaptureSelectionState(displays, Point.Empty);
        timeout.Expire(119999); Assert(!timeout.Finished, "Capture must not time out early.");
        timeout.Expire(120000); Assert(timeout.Cancelled, "Capture must expire at 120 seconds.");
        CaptureSelectionState cancel = new CaptureSelectionState(displays, Point.Empty);
        cancel.Begin(new Point(10, 10)); cancel.Cancel();
        Assert(cancel.Cancelled && !cancel.Dragging, "Escape/right cancellation must end dragging.");
        int inputAssertions = CaptureInputPolicy.SelfTest();
        int topologyAssertions = CaptureTopologyPolicy.SelfTest();
        int outlineAssertions = CaptureOutlinePolicy.SelfTest();
        int hoverAssertions = CaptureHoverPolicy.SelfTest(), redrawAssertions = CaptureMoveMailbox.SelfTest(), healthAssertions = CaptureInputHealthPolicy.SelfTest();
        return new Dictionary<string, object> { { "captureStateFixturePassed", true }, { "fixtureAssertions", 11 + inputAssertions + topologyAssertions + outlineAssertions + hoverAssertions + redrawAssertions + healthAssertions }, { "inputPolicyAssertions", inputAssertions }, { "topologyPolicyAssertions", topologyAssertions }, { "outlinePolicyAssertions", outlineAssertions }, { "hoverPolicyAssertions", hoverAssertions }, { "redrawPolicyAssertions", redrawAssertions }, { "inputHealthPolicyAssertions", healthAssertions }, { "hoverQueryMilliseconds", CaptureHoverPolicy.QueryMilliseconds }, { "releaseGraceMilliseconds", 500 }, { "screenCaptured", false }, { "clipboardChanged", false }, { "interactiveCaptureTested", false } };
    }
}

// Shared by real hooks and pure fixtures. Escape is the only keyboard key this
// policy accepts; all other key events are forwarded without being retained.
public sealed class CaptureInputPolicy {
    bool initialLeft, initialRight, initialEscape;
    public bool Armed { get; private set; }
    public bool LeftSwallowed { get; private set; }
    public bool RightSwallowed { get; private set; }
    public bool EscapeSwallowed { get; private set; }
    public bool EscapeCancelled { get; private set; }
    public bool ReleaseGraceExceeded { get; private set; }
    long stoppingAt = -1;
    public bool PendingRelease { get { return LeftSwallowed || RightSwallowed || EscapeSwallowed; } }
    public bool PlaneReady(CaptureSelectionState state) { return Armed && !state.Finished; }
    public void ResyncReleasedButtons(bool left, bool right) {
        if (Armed || PendingRelease) return;
        initialLeft = left; initialRight = right;
        Armed = !left && !right;
    }
    public void ResyncEscape(bool down) {
        if (EscapeSwallowed) return;
        initialEscape = down;
        if (down) EscapeCancelled = true;
    }
    public bool Escape(bool down, bool up) {
        if (initialEscape) { if (up) initialEscape = false; return false; }
        if (down) { EscapeSwallowed = true; EscapeCancelled = true; return true; }
        if (up && EscapeSwallowed) { EscapeSwallowed = false; return true; }
        return false;
    }
    public bool Mouse(int kind, Point pointer, CaptureSelectionState state) {
        if (!Armed) {
            // A new down proves the previous press of that same button ended,
            // even if its release fell between sampling and hook installation.
            bool freshDown = kind == 0x0201 || kind == 0x0204;
            if (kind == 0x0201) initialLeft = false;
            if (kind == 0x0204) initialRight = false;
            if (kind == 0x0202) initialLeft = false;
            if (kind == 0x0205) initialRight = false;
            Armed = !initialLeft && !initialRight;
            if (!Armed || !freshDown) return false;
        }
        if (kind == 0x0202 && LeftSwallowed) { LeftSwallowed = false; state.End(pointer); return true; }
        if (kind == 0x0205 && RightSwallowed) { RightSwallowed = false; return true; }
        if (state.Finished) return false;
        if (kind == 0x0201) { state.Begin(pointer); LeftSwallowed = true; return true; }
        if (kind == 0x0204) { state.Cancel(); RightSwallowed = true; return true; }
        state.Move(pointer);
        return false;
    }
    public void AbortOwnedMouse(int kind, CaptureSelectionState state) {
        // A native HWND already owns this event even if coordinate decoding
        // failed. Drain the matching up without fabricating a crop or sending
        // a compensating click into another application.
        if (kind == 0x0201) LeftSwallowed = true;
        if (kind == 0x0204) RightSwallowed = true;
        if (kind == 0x0202) LeftSwallowed = false;
        if (kind == 0x0205) RightSwallowed = false;
        state.Cancel();
    }
    public bool MayStop(bool finished, long elapsedMilliseconds) {
        if (!finished) return false;
        if (stoppingAt < 0) stoppingAt = elapsedMilliseconds;
        if (!PendingRelease) return true;
        if (elapsedMilliseconds - stoppingAt < 500) return false;
        // No unbounded global hook. A deliberately held key/button can still
        // release to the source after this bounded shutdown; report that limit
        // and take no screenshot rather than claiming a fully drained pair.
        ReleaseGraceExceeded = true;
        return true;
    }
    static void Assert(bool value, string message) { if (!value) throw new InvalidOperationException("SELF_TEST: " + message); }
    public static int SelfTest() {
        CaptureInputPolicy escape = new CaptureInputPolicy();
        Assert(escape.Escape(true, false) && escape.EscapeCancelled, "A short Escape down must cancel and be consumed.");
        Assert(escape.Escape(true, false) && escape.Escape(false, true) && !escape.PendingRelease, "Escape repeats and matching release must be consumed.");
        Assert(!escape.Escape(false, true), "An unmatched Escape release must pass through.");
        CaptureInputPolicy startup = new CaptureInputPolicy(); startup.ResyncEscape(true);
        Assert(startup.EscapeCancelled && !startup.Escape(false, true) && !startup.PendingRelease, "Escape already down before the hook must retain its source-app release.");
        CaptureInputPolicy pendingEscape = new CaptureInputPolicy(); pendingEscape.Escape(true, false); pendingEscape.ResyncEscape(true);
        Assert(pendingEscape.Escape(false, true), "Post-install resync must not lose a down already swallowed by the hook.");
        CaptureSelectionState state = new CaptureSelectionState(new Rectangle[] { new Rectangle(0, 0, 800, 600) }, Point.Empty);
        CaptureInputPolicy gap = new CaptureInputPolicy(); gap.ResyncReleasedButtons(true, false); gap.ResyncReleasedButtons(false, false);
        Assert(gap.Armed && gap.Mouse(0x0201, new Point(10, 10), state), "A release missed during hook installation must not leave selection unarmed.");
        Assert(gap.Mouse(0x0202, new Point(40, 40), state) && state.Finished && !gap.PendingRelease, "The fresh drag release must be consumed after resync.");
        CaptureInputPolicy held = new CaptureInputPolicy(); held.ResyncReleasedButtons(true, false);
        Assert(!held.Mouse(0x0202, new Point(10, 10), state) && held.Armed, "A pre-hook mouse down keeps its source-app matching release.");
        CaptureInputPolicy missedRelease = new CaptureInputPolicy(); missedRelease.ResyncReleasedButtons(true, false);
        CaptureSelectionState next = new CaptureSelectionState(new Rectangle[] { new Rectangle(0, 0, 800, 600) }, Point.Empty);
        Assert(missedRelease.Mouse(0x0201, new Point(20, 20), next) && next.Dragging, "The first fresh down must recover a missed old release even before the next timer tick.");
        CaptureInputPolicy grace = new CaptureInputPolicy(); grace.Escape(true, false);
        Assert(!grace.MayStop(true, 120000) && !grace.MayStop(true, 120499), "Shutdown must allow a bounded matching-release grace.");
        Assert(grace.MayStop(true, 120500) && grace.ReleaseGraceExceeded, "A held key must not keep hooks installed without a deadline.");
        CaptureInputPolicy handoff = new CaptureInputPolicy(); handoff.ResyncReleasedButtons(false, false);
        CaptureSelectionState cross = new CaptureSelectionState(new Rectangle[] { new Rectangle(-800, 0, 800, 600), new Rectangle(0, 0, 800, 600) }, Point.Empty);
        Assert(handoff.Mouse(0x0201, new Point(-100, 100), cross) && cross.Dragging, "A hook-owned down must begin the shared drag.");
        Assert(handoff.Mouse(0x0202, new Point(100, 200), cross) && cross.Finished && !handoff.PendingRelease && cross.Selected == new Rectangle(-100, 100, 200, 100), "A plane-owned up on another display must finish the original hook-owned drag.");
        Assert(!handoff.Mouse(0x0202, new Point(500, 500), cross) && cross.Selected == new Rectangle(-100, 100, 200, 100), "A duplicate up must not change a completed crop.");
        CaptureInputPolicy reverseHandoff = new CaptureInputPolicy(); reverseHandoff.ResyncReleasedButtons(false, false);
        CaptureSelectionState reverseCross = new CaptureSelectionState(new Rectangle[] { new Rectangle(0, 0, 800, 600) }, Point.Empty);
        Assert(reverseHandoff.Mouse(0x0201, new Point(20, 20), reverseCross) && reverseCross.Dragging, "A plane-owned down must use the same selection policy.");
        Assert(reverseHandoff.Mouse(0x0202, new Point(80, 60), reverseCross) && reverseCross.Selected == new Rectangle(20, 20, 60, 40), "A hook-owned up must finish a plane-owned down only once.");
        CaptureInputPolicy abort = new CaptureInputPolicy(); CaptureSelectionState abortState = new CaptureSelectionState(new Rectangle[] { new Rectangle(0, 0, 800, 600) }, Point.Empty);
        abort.ResyncReleasedButtons(false, false); abort.AbortOwnedMouse(0x0201, abortState);
        Assert(abortState.Cancelled && abort.PendingRelease && !abort.PlaneReady(abortState), "A failed owned down must cancel without dropping the matching-up drain.");
        Assert(abort.Mouse(0x0202, Point.Empty, abortState) && !abort.PendingRelease, "An aborted HWND down must consume its matching up without fabricating pixels.");
        CaptureInputPolicy beforePlane = new CaptureInputPolicy(); CaptureSelectionState beforeState = new CaptureSelectionState(new Rectangle[] { new Rectangle(0, 0, 800, 600) }, Point.Empty);
        beforePlane.ResyncReleasedButtons(true, false);
        Assert(!beforePlane.PlaneReady(beforeState), "An input plane must stay hidden while a pre-existing source press is held.");
        Assert(!beforePlane.Mouse(0x0202, Point.Empty, beforeState) && beforePlane.PlaneReady(beforeState) && !beforeState.Dragging, "The old source up must remain unconsumed before a fresh plane can appear.");
        Assert(beforePlane.Mouse(0x0204, new Point(10, 10), beforeState) && beforeState.Cancelled && beforePlane.Mouse(0x0205, new Point(10, 10), beforeState) && !beforePlane.PendingRelease, "Plane right cancellation must drain its real matching release.");
        return 21;
    }
}

// Physical polling is only a one-way health check. GetAsyncKeyState can return
// zero when its query fails, and is not proof of our owned matching release.
// False MUST NOT cancel a valid long drag. Only an actual
// owned up ends it; Escape/right/desktop change/timeout remain cancellation.
public sealed class CaptureInputHealthPolicy {
    int mismatch;
    long since = -1;
    public int Observe(bool armed, bool finished, bool dragging, bool swallowed, bool physicalLeft, long elapsed) {
        int observed = armed && !finished && !dragging && !swallowed && physicalLeft ? 1 : 0;
        if (elapsed < 0 || observed == 0) { mismatch = 0; since = -1; return 0; }
        if (observed != mismatch || since < 0 || elapsed < since) { mismatch = observed; since = elapsed; return 0; }
        return elapsed - since >= 750 ? mismatch : 0;
    }
    public static int SelfTest() {
        int assertions = 0;
        Action<bool> check = delegate(bool ok) { if (!ok) throw new InvalidOperationException("SELF_TEST: Capture input health guard failed."); assertions++; };
        CaptureInputHealthPolicy health = new CaptureInputHealthPolicy();
        check(health.Observe(false, false, false, false, true, 0) == 0 && health.Observe(false, false, false, false, true, 2000) == 0);
        check(health.Observe(true, false, false, false, true, 2100) == 0 && health.Observe(true, false, false, false, true, 2849) == 0);
        check(health.Observe(true, false, false, false, true, 2850) == 1);
        check(health.Observe(true, false, true, true, true, 2860) == 0);
        check(health.Observe(true, false, true, true, false, 3000) == 0 && health.Observe(true, false, true, true, false, 3749) == 0);
        check(health.Observe(true, false, true, true, false, 3750) == 0);
        check(health.Observe(true, true, false, false, false, 3760) == 0);
        check(health.Observe(true, false, true, true, false, 4000) == 0 && health.Observe(true, false, true, true, false, 3900) == 0);
        check(health.Observe(true, false, true, true, true, 5000) == 0 && health.Observe(true, false, true, true, false, 6000) == 0 && health.Observe(true, false, true, true, false, 120000) == 0);
        return assertions;
    }
}

public struct CaptureDisplaySnapshot {
    public readonly string Device;
    public readonly Rectangle Bounds;
    public readonly uint Dpi;
    public CaptureDisplaySnapshot(string device, Rectangle bounds, uint dpi) { Device = device; Bounds = bounds; Dpi = dpi; }
}
public sealed class CaptureTopologyPolicy {
    readonly CaptureDisplaySnapshot[] displays;
    readonly int awareness;
    int invalid;
    public bool Invalid { get { return System.Threading.Interlocked.CompareExchange(ref invalid, 0, 0) != 0; } }
    public void Invalidate() { System.Threading.Interlocked.Exchange(ref invalid, 1); }
    public CaptureDisplaySnapshot[] Displays { get { return (CaptureDisplaySnapshot[])displays.Clone(); } }
    public CaptureTopologyPolicy(CaptureDisplaySnapshot[] source, int dpiAwareness) {
        if (source == null || source.Length == 0) throw new InvalidOperationException("CAPTURE_DISPLAY_CHANGED: No capture display is available.");
        displays = (CaptureDisplaySnapshot[])source.Clone(); awareness = dpiAwareness;
        Array.Sort(displays, delegate(CaptureDisplaySnapshot a, CaptureDisplaySnapshot b) { return StringComparer.Ordinal.Compare(a.Device, b.Device); });
        for (int i = 0; i < displays.Length; i++) {
            CaptureDisplaySnapshot display = displays[i];
            if (String.IsNullOrEmpty(display.Device) || display.Bounds.Width <= 0 || display.Bounds.Height <= 0 || display.Dpi == 0 || (i > 0 && displays[i - 1].Device == display.Device))
                throw new InvalidOperationException("CAPTURE_DISPLAY_CHANGED: Invalid capture display metadata.");
        }
    }
    public bool Matches(CaptureTopologyPolicy other) {
        if (other == null || Invalid || other.Invalid || awareness != 2 || other.awareness != 2 || displays.Length != other.displays.Length) return false;
        for (int i = 0; i < displays.Length; i++)
            if (displays[i].Device != other.displays[i].Device || displays[i].Bounds != other.displays[i].Bounds || displays[i].Dpi != other.displays[i].Dpi) return false;
        return !Invalid && !other.Invalid;
    }
    static void Assert(bool value, string message) { if (!value) throw new InvalidOperationException("SELF_TEST: " + message); }
    public static int SelfTest() {
        CaptureDisplaySnapshot left = new CaptureDisplaySnapshot("left", new Rectangle(-1600, 0, 1600, 1000), 144);
        CaptureDisplaySnapshot main = new CaptureDisplaySnapshot("main", new Rectangle(0, 0, 1920, 1080), 96);
        CaptureTopologyPolicy expected = new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { left, main }, 2);
        Assert(expected.Matches(new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { main, left }, 2)), "Monitor enumeration order must not change the topology.");
        Assert(!expected.Matches(new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { main }, 2)), "Disconnected displays must invalidate capture.");
        Assert(!expected.Matches(new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { new CaptureDisplaySnapshot("left", left.Bounds, 192), main }, 2)), "A scale/DPI change must invalidate physical coordinates.");
        Assert(!expected.Matches(new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { new CaptureDisplaySnapshot("left", new Rectangle(-1600, -200, 1600, 1000), 144), main }, 2)), "A display move must invalidate physical coordinates.");
        Assert(!expected.Matches(new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { left, main }, 1)), "A thread DPI-awareness change must invalidate capture.");
        CaptureSelectionState finished = new CaptureSelectionState(new Rectangle[] { main.Bounds }, Point.Empty);
        finished.Begin(new Point(10, 10)); finished.End(new Point(20, 20));
        expected.Invalidate();
        Assert(finished.Finished && !expected.Matches(new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { left, main }, 2)), "A display event after completion must invalidate even identical current geometry.");
        Assert(expected.Invalid && !expected.Matches(new CaptureTopologyPolicy(new CaptureDisplaySnapshot[] { main, left }, 2)), "An invalidated capture cannot become valid when displays return to their previous arrangement.");
        return 7;
    }
}

// The hook only publishes one atomically packed point and at most one queued
// wake. It never waits for the UI, enters the selection lock, or queries HWNDs.
public sealed class CaptureMoveMailbox {
    readonly Func<bool> post;
    long point, moves, posts, failures;
    int active = 1, pending, hasPoint;
    public CaptureMoveMailbox(Func<bool> postWake) { post = postWake; }
    public void Publish(Point value, bool wake) { Publish(value, wake, wake); }
    public void Publish(Point value, bool wake, bool hookMove) {
        if (Interlocked.CompareExchange(ref active, 0, 0) == 0) return;
        Interlocked.Exchange(ref point, ((long)(uint)value.X << 32) | (uint)value.Y);
        Interlocked.Exchange(ref hasPoint, 1);
        if (!wake) return;
        if (hookMove) Interlocked.Increment(ref moves);
        if (Interlocked.CompareExchange(ref pending, 1, 0) != 0) return;
        bool posted = false;
        try { posted = Interlocked.CompareExchange(ref active, 0, 0) != 0 && post(); }
        catch { } // A lost decorative wake must not escape a native hook callback.
        if (posted) Interlocked.Increment(ref posts);
        else { Interlocked.Increment(ref failures); Interlocked.Exchange(ref pending, 0); }
    }
    public bool TakeWake() { return Interlocked.Exchange(ref pending, 0) != 0 && Interlocked.CompareExchange(ref active, 0, 0) != 0; }
    public bool TryRead(out Point value) {
        long packed = Interlocked.Read(ref point);
        value = new Point(unchecked((int)(packed >> 32)), unchecked((int)packed));
        return Interlocked.CompareExchange(ref active, 0, 0) != 0 && Interlocked.CompareExchange(ref hasPoint, 0, 0) != 0;
    }
    public void Stop() { Interlocked.Exchange(ref active, 0); Interlocked.Exchange(ref pending, 0); }
    public long Moves { get { return Interlocked.Read(ref moves); } }
    public long Posts { get { return Interlocked.Read(ref posts); } }
    public long Failures { get { return Interlocked.Read(ref failures); } }
    public static int SelfTest() {
        int assertions = 0, queued = 0; Point observed;
        Action<bool> check = delegate(bool ok) { if (!ok) throw new InvalidOperationException("SELF_TEST: Capture move coalescing failed."); assertions++; };
        CaptureMoveMailbox box = new CaptureMoveMailbox(delegate { queued++; return true; });
        check(!box.TryRead(out observed));
        for (int i = 0; i < 1000; i++) box.Publish(new Point(-1000 + i, Int32.MinValue + i), true);
        check(queued == 1 && box.Moves == 1000 && box.Posts == 1);
        check(box.TryRead(out observed) && observed == new Point(-1, Int32.MinValue + 999));
        check(box.TakeWake()); check(!box.TakeWake()); box.Publish(new Point(Int32.MaxValue, -400), true);
        check(queued == 2 && box.TryRead(out observed) && observed == new Point(Int32.MaxValue, -400));
        box.Publish(new Point(2, 3), false); check(queued == 2 && box.TryRead(out observed) && observed == new Point(2, 3));
        box.Stop(); box.Publish(new Point(7, 8), true); check(queued == 2 && !box.TakeWake() && !box.TryRead(out observed));
        int attempts = 0; CaptureMoveMailbox failed = new CaptureMoveMailbox(delegate { attempts++; return false; });
        failed.Publish(new Point(1, 2), true); failed.Publish(new Point(3, 4), true);
        check(attempts == 2 && failed.Failures == 2 && failed.TryRead(out observed) && observed == new Point(3, 4));
        CaptureMoveMailbox throwing = new CaptureMoveMailbox(delegate { throw new InvalidOperationException(); });
        throwing.Publish(new Point(4, 5), true); check(throwing.Failures == 1 && throwing.TryRead(out observed));
        CaptureMoveMailbox plane = new CaptureMoveMailbox(delegate { return true; });
        plane.Publish(new Point(-5, 30), true, false);
        check(plane.Moves == 0 && plane.Posts == 1 && plane.TakeWake() && plane.TryRead(out observed) && observed == new Point(-5, 30));
        CaptureRedrawPolicy redraw = new CaptureRedrawPolicy();
        check(redraw.IsDue(0)); redraw.Presented(0); check(!redraw.IsDue(15) && redraw.IsDue(16));
        redraw.Presented(16); check(!redraw.IsDue(20) && redraw.IsDue(32));
        check(!redraw.IsDue(-1) && !redraw.IsDue(15)); check(redraw.IsDue(5000));
        return assertions;
    }
}
public sealed class CaptureRedrawPolicy {
    long presented = -1;
    public bool IsDue(long elapsed) { return elapsed >= 0 && (presented < 0 || (elapsed >= presented && elapsed - presented >= 16)); }
    public void Presented(long elapsed) { presented = elapsed; }
}

// These temporary probes are never shown or ordered. GetDpiForWindow reports
// actual per-monitor HWND DPI even when PowerShell chose a process-wide DPI
// mode before this helper could set its own UI-thread awareness.
sealed class CaptureDpiProbe : Form {
    public CaptureDpiProbe(Rectangle screen) {
        AutoScaleMode = AutoScaleMode.None; FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual; ShowInTaskbar = false;
        Bounds = new Rectangle(screen.Left + screen.Width / 2, screen.Top + screen.Height / 2, 1, 1);
    }
    protected override bool ShowWithoutActivation { get { return true; } }
}

// Four narrow rectangles, never a display-sized surface. The same physical-
// pixel clipping policy feeds actual edge HWNDs and the host-only fixtures.
public static class CaptureOutlinePolicy {
    public const int Thickness = 2;
    public static Rectangle[] Edges(Rectangle outline, Rectangle display) {
        Rectangle[] result = new Rectangle[4];
        if (outline.Width <= 0 || outline.Height <= 0) return result;
        int horizontal = Math.Min(Thickness, outline.Height), vertical = Math.Min(Thickness, outline.Width);
        Rectangle[] edges = new Rectangle[] {
            new Rectangle(outline.Left, outline.Top, outline.Width, horizontal),
            new Rectangle(outline.Left, outline.Bottom - horizontal, outline.Width, horizontal),
            new Rectangle(outline.Left, outline.Top + horizontal, vertical, Math.Max(0, outline.Height - horizontal * 2)),
            new Rectangle(outline.Right - vertical, outline.Top + horizontal, vertical, Math.Max(0, outline.Height - horizontal * 2))
        };
        for (int i = 0; i < edges.Length; i++) {
            Rectangle clipped = Rectangle.Intersect(edges[i], display);
            if (clipped.Width > 0 && clipped.Height > 0) result[i] = clipped;
        }
        return result;
    }
    static long Area(Rectangle[] edges) { long result = 0; foreach (Rectangle edge in edges) result += (long)edge.Width * edge.Height; return result; }
    static void Assert(bool value, string message) { if (!value) throw new InvalidOperationException("SELF_TEST: " + message); }
    public static int SelfTest() {
        Rectangle display = new Rectangle(-3840, -300, 3840, 2160);
        Rectangle[] border = Edges(display, display);
        Assert(border.Length == 4 && Area(border) == 2L * Thickness * (display.Width + display.Height - 2 * Thickness), "A display border must contain only its four thin edges.");
        Assert(Area(border) < (long)display.Width * display.Height / 100, "A 4K border must occupy less than one percent of a display, with no full-screen surface.");
        foreach (Rectangle edge in border) Assert(display.Contains(edge) && Math.Min(edge.Width, edge.Height) <= Thickness, "Negative display origins must retain small physical edge rectangles.");
        Rectangle selection = new Rectangle(-120, -150, 300, 400);
        Rectangle left = new Rectangle(-1920, -1080, 1920, 1080), right = new Rectangle(0, 0, 1920, 1080);
        Rectangle[] leftEdges = Edges(selection, left), rightEdges = Edges(selection, right);
        foreach (Rectangle edge in leftEdges) if (!edge.IsEmpty) Assert(left.Contains(edge), "Cross-display selection edges must be clipped to their own negative-origin display.");
        foreach (Rectangle edge in rightEdges) if (!edge.IsEmpty) Assert(right.Contains(edge), "Cross-display selection edges must be clipped to their own positive-origin display.");
        Assert(leftEdges[0].Width == 120 && rightEdges[1].Width == 180, "Cross-display outer edges must retain global coordinates without adding an edge along the screen seam.");
        Assert(Area(Edges(selection, new Rectangle(500, 500, 800, 600))) == 0, "A display outside the selected rectangle must have no visible edges.");
        Assert(Area(Edges(Rectangle.Empty, display)) == 0, "No selection must create no selection surface.");
        Rectangle[] tiny = Edges(new Rectangle(10, 10, 1, 1), new Rectangle(0, 0, 800, 600));
        foreach (Rectangle edge in tiny) Assert(edge.Width >= 0 && edge.Height >= 0, "A tiny gesture must never create negative-sized windows.");
        return 17;
    }
}

// Decorative metadata only. This policy cannot start/end a drag, alter its
// freely selected ROI, capture pixels, inspect content or request activation.
public struct CaptureHoverCandidate {
    public Rectangle Frame;
    public string ClassName;
    public bool RootKnown, Visible, Minimized, CloakKnown, OwnWindow, ShellWindow, ExcludedFromCapture;
    public uint Cloaked;
}
public sealed class CaptureHoverPolicy {
    public const int QueryMilliseconds = 80;
    long queriedAt = -1;
    Rectangle frame;
    public static Rectangle Bounds(int left, int top, int right, int bottom) {
        long width = (long)right - left, height = (long)bottom - top;
        return width > 0 && height > 0 && width <= Int32.MaxValue && height <= Int32.MaxValue
            ? new Rectangle(left, top, (int)width, (int)height) : Rectangle.Empty;
    }
    public static bool ShellClass(string name) {
        return name == "Progman" || name == "WorkerW" || name == "Shell_TrayWnd" || name == "Shell_SecondaryTrayWnd"
            || name == "SHELLDLL_DefView" || name == "SysListView32";
    }
    public static bool KnownOverlay(IntPtr window, ICollection<IntPtr> hints, ICollection<IntPtr> planes) {
        // Only registered overlay handles may be skipped by the metadata walk.
        // Being in our process alone never grants a transparent exception.
        return window != IntPtr.Zero && (hints.Contains(window) || planes.Contains(window));
    }
    public static Rectangle CandidateFrame(CaptureHoverCandidate candidate, Point pointer) {
        return candidate.RootKnown && candidate.Visible && !candidate.Minimized && candidate.CloakKnown && candidate.Cloaked == 0
            && !candidate.OwnWindow && !candidate.ShellWindow && !candidate.ExcludedFromCapture
            && !String.IsNullOrEmpty(candidate.ClassName) && !ShellClass(candidate.ClassName)
            && candidate.Frame.Width > 0 && candidate.Frame.Height > 0 && candidate.Frame.Contains(pointer)
            ? candidate.Frame : Rectangle.Empty;
    }
    public void Clear() { frame = Rectangle.Empty; }
    public bool BeginQuery(long elapsed) {
        if (elapsed < 0 || (queriedAt >= 0 && elapsed < queriedAt)) { Clear(); return false; }
        if (queriedAt >= 0 && elapsed - queriedAt < QueryMilliseconds) return false;
        queriedAt = elapsed; Clear(); // Failure must never reuse an old frame.
        return true;
    }
    public void SetFrame(Rectangle value) { frame = value; }
    public Rectangle Current(Point pointer, long elapsed, bool idle) {
        if (!idle || queriedAt < 0 || elapsed < queriedAt || elapsed - queriedAt >= QueryMilliseconds) { Clear(); return Rectangle.Empty; }
        return frame.Width > 0 && frame.Height > 0 && frame.Contains(pointer) ? frame : Rectangle.Empty;
    }
    public static int SelfTest() {
        int assertions = 0;
        Action<bool, string> check = delegate(bool value, string message) {
            if (!value) throw new InvalidOperationException("SELF_TEST: " + message);
            assertions++;
        };
        Rectangle bounds = Bounds(-1400, -200, 200, 700);
        check(bounds == new Rectangle(-1400, -200, 1600, 900), "Hover frames must retain physical negative origins.");
        check(Bounds(4, 0, 4, 100).IsEmpty && Bounds(Int32.MinValue, 0, Int32.MaxValue, 100).IsEmpty, "Empty/overflow hover frames must be rejected.");
        Point pointer = new Point(-300, 100);
        CaptureHoverCandidate valid = new CaptureHoverCandidate { Frame = bounds, ClassName = "GeneratedWindow", RootKnown = true, Visible = true, CloakKnown = true };
        check(CandidateFrame(valid, pointer) == bounds, "Eligible real root metadata must keep its exact visible frame, without snapping the ROI.");
        Action<CaptureHoverCandidate> reject = delegate(CaptureHoverCandidate bad) { check(CandidateFrame(bad, pointer).IsEmpty, "Ineligible/unknown hover metadata must fall back to the screen outline."); };
        CaptureHoverCandidate candidate = valid; candidate.Visible = false; reject(candidate);
        candidate = valid; candidate.Minimized = true; reject(candidate);
        candidate = valid; candidate.CloakKnown = false; reject(candidate);
        candidate = valid; candidate.Cloaked = 1; reject(candidate);
        candidate = valid; candidate.OwnWindow = true; reject(candidate);
        candidate = valid; candidate.ShellWindow = true; reject(candidate);
        candidate = valid; candidate.ExcludedFromCapture = true; reject(candidate);
        candidate = valid; candidate.RootKnown = false; reject(candidate);
        candidate = valid; candidate.ClassName = null; reject(candidate);
        foreach (string shell in new string[] { "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "SHELLDLL_DefView", "SysListView32" }) { candidate = valid; candidate.ClassName = shell; reject(candidate); }
        check(CandidateFrame(valid, new Point(200, 100)).IsEmpty, "Right/bottom frame edges are exclusive and cannot retain a stale hover.");
        IntPtr ordinary = new IntPtr(20), disabled = new IntPtr(30), hint = new IntPtr(40), plane = new IntPtr(50);
        ICollection<IntPtr> hints = new HashSet<IntPtr> { hint }, planes = new HashSet<IntPtr> { plane };
        check(!KnownOverlay(ordinary, hints, planes), "An ordinary root must not be skipped as our overlay.");
        check(!KnownOverlay(disabled, hints, planes), "A disabled root must not be skipped as an overlay, obscuring the enabled root beneath it.");
        check(!KnownOverlay(IntPtr.Zero, hints, planes), "An unavailable root cannot count as a registered overlay.");
        check(KnownOverlay(hint, hints, planes), "A registered thin edge may be skipped by the metadata-only underlay query.");
        check(KnownOverlay(plane, hints, planes), "A registered input plane may be skipped without changing live hit testing.");
        CaptureHoverPolicy policy = new CaptureHoverPolicy();
        check(policy.BeginQuery(0), "The initial hover query must be available immediately."); policy.SetFrame(bounds);
        check(policy.Current(pointer, 0, true) == bounds && !policy.BeginQuery(79), "Idle native metadata queries must be throttled.");
        check(policy.Current(pointer, 80, true).IsEmpty, "An expired frame must never be reused.");
        check(policy.BeginQuery(80) && policy.Current(pointer, 80, true).IsEmpty, "Beginning a replacement query must clear old geometry before native failure.");
        policy.SetFrame(bounds);
        check(policy.Current(pointer, 81, false).IsEmpty && policy.Current(pointer, 82, true).IsEmpty, "Dragging/completion must clear hover immediately without restoring cached geometry.");
        check(!policy.BeginQuery(20) && policy.Current(pointer, 20, true).IsEmpty, "Backwards timestamps cannot restore an old frame.");
        return assertions;
    }
}

// Read-only native metadata, called only by the UI timer and never by a hook
// or while selectionGate is held. A failed/ambiguous hint is simply omitted.
sealed class CaptureHoverResolver {
    [StructLayout(LayoutKind.Sequential)] struct FrameRect { public int left, top, right, bottom; }
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr window, Point point, uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window, uint relation);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out FrameRect bounds);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPointer(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int GetWindowLong32(IntPtr window, int index);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll")] static extern bool GetWindowDisplayAffinity(IntPtr window, out uint affinity);
    [DllImport("dwmapi.dll", EntryPoint="DwmGetWindowAttribute")] static extern int DwmFrame(IntPtr window, uint attribute, out FrameRect value, int size);
    [DllImport("dwmapi.dll", EntryPoint="DwmGetWindowAttribute")] static extern int DwmCloak(IntPtr window, uint attribute, out uint value, int size);
    readonly ICollection<IntPtr> hints;
    readonly ICollection<IntPtr> planes;
    readonly uint process = (uint)Process.GetCurrentProcess().Id;
    public CaptureHoverResolver(ICollection<IntPtr> ownHints, ICollection<IntPtr> inputPlanes) { hints = ownHints; planes = inputPlanes; }
    bool OwnWindow(IntPtr window) {
        if (window == IntPtr.Zero) return false;
        uint owner; GetWindowThreadProcessId(window, out owner);
        return owner == process || CaptureHoverPolicy.KnownOverlay(window, hints, planes);
    }
    IntPtr UnderlyingRoot(Point pointer, IntPtr first, IntPtr desktop) {
        // The non-transparent input plane is intentionally the first desktop
        // hit. Walk beneath only our EXACT registered overlay HWNDs; never
        // hide/retag them to query underneath or skip arbitrary own-PID windows.
        // Include disabled roots (WindowFromPoint omits them). GetWindow can
        // race destruction/reordering, so bound traversal and reject cycles.
        HashSet<IntPtr> visited = new HashSet<IntPtr>();
        IntPtr current = first;
        for (int count = 0; count < 256 && current != IntPtr.Zero && current != desktop; count++) {
            if (!visited.Add(current) || !IsWindow(current) || GetAncestor(current, 2) != current) return IntPtr.Zero;
            if (!CaptureHoverPolicy.KnownOverlay(current, hints, planes) && IsWindowVisible(current) && !IsIconic(current)) {
                FrameRect bounds;
                if (!GetWindowRect(current, out bounds)) return IntPtr.Zero;
                Rectangle rectangle = CaptureHoverPolicy.Bounds(bounds.left, bounds.top, bounds.right, bounds.bottom);
                if (rectangle.IsEmpty && bounds.left != bounds.right && bounds.top != bounds.bottom) return IntPtr.Zero;
                if (!rectangle.IsEmpty && rectangle.Contains(pointer)) {
                    long style = IntPtr.Size == 8 ? GetWindowLongPointer(current, -20).ToInt64() : GetWindowLong32(current, -20);
                    if ((style & 0x20) == 0) {
                        uint cloaked;
                        if (DwmCloak(current, 14, out cloaked, sizeof(uint)) != 0) return IntPtr.Zero;
                        if (cloaked == 0) return OwnWindow(current) ? IntPtr.Zero : current;
                    }
                }
            }
            current = GetWindow(current, 2); // GW_HWNDNEXT; no titles/content/foreign messages.
        }
        return IntPtr.Zero;
    }
    public Rectangle Resolve(Point pointer) {
        IntPtr desktop = GetDesktopWindow();
        // Check real top-level occlusion on every throttled query, not only
        // over our own bars. Unlike WindowFromPoint, this deliberately keeps
        // disabled roots; skipping them could frame an obscured window behind.
        // Convert physical screen coordinates, including negative displays.
        Point client = pointer;
        if (desktop == IntPtr.Zero || !ScreenToClient(desktop, ref client)) return Rectangle.Empty;
        IntPtr desktopHit = ChildWindowFromPointEx(desktop, client, 0x1 | 0x4); // SKIPINVISIBLE | SKIPTRANSPARENT
        IntPtr desktopRoot = desktopHit == IntPtr.Zero ? IntPtr.Zero : GetAncestor(desktopHit, 2);
        IntPtr root = UnderlyingRoot(pointer, desktopRoot, desktop);
        if (root == IntPtr.Zero || root == desktop || root == GetShellWindow() || OwnWindow(root)
            || !IsWindow(root) || !IsWindowVisible(root) || IsIconic(root)) return Rectangle.Empty;
        uint owner;
        if (GetWindowThreadProcessId(root, out owner) == 0 || owner == 0) return Rectangle.Empty;
        StringBuilder name = new StringBuilder(256);
        if (GetClassName(root, name, name.Capacity) == 0 || CaptureHoverPolicy.ShellClass(name.ToString())) return Rectangle.Empty;
        uint cloaked; FrameRect frame;
        if (DwmCloak(root, 14, out cloaked, sizeof(uint)) != 0 || cloaked != 0
            || DwmFrame(root, 9, out frame, Marshal.SizeOf(typeof(FrameRect))) != 0) return Rectangle.Empty;
        // Optional documented read: failure is common for ordinary non-layered
        // windows and does not imply exclusion. Never change another app's flag.
        uint affinity; bool excluded = GetWindowDisplayAffinity(root, out affinity) && (affinity == 0x11 || affinity == 0x1);
        uint after;
        CaptureHoverCandidate candidate = new CaptureHoverCandidate {
            Frame = CaptureHoverPolicy.Bounds(frame.left, frame.top, frame.right, frame.bottom), ClassName = name.ToString(),
            RootKnown = IsWindow(root) && GetAncestor(root, 2) == root && GetWindowThreadProcessId(root, out after) != 0 && after == owner,
            Visible = IsWindowVisible(root), Minimized = IsIconic(root), CloakKnown = true, Cloaked = cloaked,
            OwnWindow = false, ShellWindow = false, ExcludedFromCapture = excluded
        };
        return CaptureHoverPolicy.CandidateFrame(candidate, pointer);
    }
}

// A color-keyed, click-through HWND only as wide as the blue edge. Unlike a
// full-screen DoubleBuffered Form, it cannot allocate/repaint a 4K frame for
// each drag update. No activation, dimming, frozen screenshot or source pixels.
sealed class CaptureEdgeWindow : Form {
    [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    readonly uint expectedDpi;
    readonly Action invalidated;
    static readonly Color ClearKey = Color.FromArgb(255, 0, 255);
    public CaptureEdgeWindow(Rectangle screen, uint dpi, Action onInvalidated) {
        expectedDpi = dpi; invalidated = onInvalidated;
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(screen.Left, screen.Top, 1, 1);
        TopMost = true;
        ShowInTaskbar = false;
        BackColor = Color.FromArgb(45, 145, 255);
        TransparencyKey = ClearKey;
        DoubleBuffered = false;
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams value = base.CreateParams;
            value.ExStyle |= 0x08000000 | 0x00000080 | 0x00080000 | 0x00000020; // NOACTIVATE/TOOLWINDOW/LAYERED/TRANSPARENT
            return value;
        }
    }
    protected override void WndProc(ref Message message) {
        if (message.Msg == 0x0021) { message.Result = new IntPtr(3); return; } // MA_NOACTIVATE
        if (message.Msg == 0x007E || (message.Msg == 0x02E0 && (uint)(message.WParam.ToInt64() & 0xFFFF) != expectedDpi)) invalidated();
        base.WndProc(ref message);
    }
    public void Present(Rectangle edge, bool raise) {
        if (edge.Width <= 0 || edge.Height <= 0) { if (Visible) Hide(); return; }
        bool changed = Bounds != edge, showing = !Visible;
        if (showing) { Bounds = edge; Show(); }
        // HWND_TOPMOST is a group, not permanent precedence over other topmost
        // windows. Refresh its order passively, at most once per 250ms when idle.
        if (changed || showing || raise) {
            // A visible edge moves/resizes and optionally repairs Z order in
            // one native call, instead of Bounds followed by another Z call.
            uint flags = 0x0010 | 0x0200; // NOACTIVATE | NOOWNERZORDER
            if (!raise && !showing) flags |= 0x0004; // Keep existing Z order during ordinary drag.
            if (!SetWindowPos(Handle, new IntPtr(-1), edge.X, edge.Y, edge.Width, edge.Height, flags))
                throw new InvalidOperationException("CAPTURE_OVERLAY: Windows could not display the selection border above ordinary windows.");
        }
    }
}

sealed class CaptureOverlay : IDisposable {
    readonly Rectangle screen;
    readonly int index;
    readonly CaptureEdgeWindow[] edges = new CaptureEdgeWindow[12];
    public CaptureOverlay(Rectangle display, int screenIndex, uint dpi, Action onInvalidated, Action<IntPtr> register) {
        screen = display; index = screenIndex;
        try {
            for (int i = 0; i < edges.Length; i++) {
                edges[i] = new CaptureEdgeWindow(screen, dpi, onInvalidated);
                register(edges[i].Handle);
            }
        } catch { Dispose(); throw; }
    }
    public void Present(int highlighted, Rectangle selected, Rectangle hovered, bool raise) {
        Rectangle[] border = CaptureOutlinePolicy.Edges(highlighted == index ? screen : Rectangle.Empty, screen);
        Rectangle outline = selected;
        if (outline.Width > 0 && outline.Height > 0) outline.Inflate(1, 1);
        Rectangle[] selection = CaptureOutlinePolicy.Edges(outline, screen);
        Rectangle[] window = CaptureOutlinePolicy.Edges(hovered, screen);
        for (int i = 0; i < 4; i++) { edges[i].Present(border[i], raise); edges[i + 4].Present(selection[i], raise); edges[i + 8].Present(window[i], raise); }
    }
    public void Hide() { foreach (CaptureEdgeWindow edge in edges) if (edge != null) edge.Hide(); }
    public void Dispose() { foreach (CaptureEdgeWindow edge in edges) if (edge != null) { edge.Close(); edge.Dispose(); } }
}

// Low-level input hooks are synchronous on their installation thread. Keep
// them on a dedicated native message pump, completely separate from drawing,
// window positioning, monitor enumeration, OCR, file I/O and PowerShell work.
// Movement/wheel and all non-Escape keys immediately pass through. The UI
// samples physical pointer motion; hooks retain only selection button/Esc state.
// https://learn.microsoft.com/windows/win32/winmsg/lowlevelmouseproc
sealed class CaptureWakeWindow : NativeWindow, IDisposable {
    const int WakeMessage = 0x8000 + 0x361;
    [DllImport("user32.dll", EntryPoint="PostMessageW")] static extern bool PostMessage(IntPtr window, uint message, IntPtr word, IntPtr parameter);
    static int nextToken;
    readonly IntPtr token, target;
    readonly Action update;
    CaptureMoveMailbox mailbox;
    int stopped;
    public CaptureWakeWindow(Action onMove) {
        update = onMove; token = new IntPtr(Interlocked.Increment(ref nextToken));
        CreateParams parameters = new CreateParams(); parameters.Parent = new IntPtr(-3); // HWND_MESSAGE: invisible, no Z order or activation.
        CreateHandle(parameters); target = Handle;
        if (target == IntPtr.Zero) throw new InvalidOperationException("CAPTURE_INPUT: Windows could not create the capture update listener.");
    }
    public void Bind(CaptureMoveMailbox value) { mailbox = value; }
    public bool Post() { return Interlocked.CompareExchange(ref stopped, 0, 0) == 0 && PostMessage(target, WakeMessage, token, IntPtr.Zero); }
    protected override void WndProc(ref Message message) {
        if (message.Msg == WakeMessage) {
            if (message.WParam == token && Interlocked.CompareExchange(ref stopped, 0, 0) == 0 && mailbox != null && mailbox.TakeWake()) update();
            return;
        }
        base.WndProc(ref message);
    }
    public void Stop() { Interlocked.Exchange(ref stopped, 1); if (mailbox != null) mailbox.Stop(); }
    public void Dispose() { Stop(); DestroyHandle(); }
}

// One rectangular input HWND per physical display, with no redirection bitmap,
// layered alpha, GDI background, swap chain or DirectComposition surface. The
// desktop remains live and fully visible; User32 still hit-tests the rectangle.
// Normal hook-owned buttons never reach this WndProc. If Windows removes or
// bypasses that mouse hook, these HWND messages use the SAME selection policy.
// https://learn.microsoft.com/en-us/archive/msdn-magazine/2014/june/windows-with-c-high-performance-window-layering-using-the-windows-composition-engine
sealed class CaptureInputPlanes : IDisposable {
    delegate IntPtr WindowProc(IntPtr window, uint message, IntPtr wp, IntPtr lp);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WindowClass {
        public uint size, style; public IntPtr procedure; public int classBytes, windowBytes;
        public IntPtr instance, icon, cursor, background; public string menu, name; public IntPtr smallIcon;
    }
    [StructLayout(LayoutKind.Sequential)] struct PaintData {
        public IntPtr dc; public int erase; public RectangleData rectangle; public int restore, update;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=32)] public byte[] reserved;
    }
    [StructLayout(LayoutKind.Sequential)] struct RectangleData { public int left, top, right, bottom; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern ushort RegisterClassEx(ref WindowClass value);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool UnregisterClass(string name, IntPtr module);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateWindowEx(uint ex, string cls, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr module, IntPtr parameter);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr DefWindowProc(IntPtr window, uint message, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out Point point);
    [DllImport("user32.dll")] static extern IntPtr LoadCursor(IntPtr instance, IntPtr name);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPointer(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int GetWindowLong32(IntPtr window, int index);
    [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] static extern IntPtr BeginPaint(IntPtr window, out PaintData paint);
    [DllImport("user32.dll")] static extern bool EndPaint(IntPtr window, ref PaintData paint);
    [DllImport("dwmapi.dll")] static extern int DwmIsCompositionEnabled([MarshalAs(UnmanagedType.Bool)] out bool enabled);
    const uint Styles = 0x00200000 | 0x08000000 | 0x00000080 | 0x00000008; // NOREDIR/NOACTIVATE/TOOLWINDOW/TOPMOST
    readonly WindowProc callback;
    readonly List<IntPtr> handles = new List<IntPtr>();
    readonly object gate;
    readonly CaptureSelectionState state;
    readonly CaptureInputPolicy input;
    readonly CaptureMoveMailbox moves;
    readonly Action invalidated;
    readonly IntPtr instance;
    readonly string className;
    bool registered, shown, disposed;
    long downs, ups, movement;
    string failure;
    public ICollection<IntPtr> Handles { get { return handles; } }
    public string Failure { get { return failure; } }
    public long Downs { get { return downs; } }
    public long Ups { get { return ups; } }
    public long Moves { get { return movement; } }
    public int Count { get { return handles.Count; } }
    public int VisibleCount { get { int count = 0; foreach (IntPtr window in handles) if (IsWindowVisible(window)) count++; return count; } }
    public int RemainingCount { get { int count = 0; foreach (IntPtr window in handles) if (IsWindow(window)) count++; return count; } }
    static bool StylesMatch(IntPtr window, bool topmost) {
        long actual = IntPtr.Size == 8 ? GetWindowLongPointer(window, -20).ToInt64() : GetWindowLong32(window, -20);
        uint expected = topmost ? Styles : Styles & ~0x8U;
        return (actual & expected) == expected && (actual & (0x00080000 | 0x00000020)) == 0;
    }
    public CaptureInputPlanes(Rectangle[] displays, object selectionGate, CaptureSelectionState selection,
        CaptureInputPolicy policy, CaptureMoveMailbox mailbox, Action onInvalidated, Action<IntPtr> register) {
        gate = selectionGate; state = selection; input = policy; moves = mailbox; invalidated = onInvalidated;
        callback = WndProc; instance = GetModuleHandle(null);
        className = "EchoLingoCaptureInputPlane-" + Process.GetCurrentProcess().Id;
        try {
            bool composition;
            if (DwmIsCompositionEnabled(out composition) != 0 || !composition)
                throw new InvalidOperationException("CAPTURE_INPUT_PLANE: Windows desktop composition is unavailable; no screenshot was taken.");
            WindowClass value = new WindowClass(); value.size = (uint)Marshal.SizeOf(typeof(WindowClass));
            value.instance = instance; value.name = className; value.procedure = Marshal.GetFunctionPointerForDelegate(callback);
            value.cursor = LoadCursor(IntPtr.Zero, new IntPtr(32515)); // Shared system crosshair; no owned GDI resource.
            // No CS_DBLCLKS: every physical press remains a normal button down.
            if (RegisterClassEx(ref value) == 0)
                throw new InvalidOperationException("CAPTURE_INPUT_PLANE: Windows could not create the capture input class.");
            registered = true;
            foreach (Rectangle display in displays) {
                if (display.Width <= 0 || display.Height <= 0 || display.Width > Int16.MaxValue || display.Height > Int16.MaxValue)
                    throw new InvalidOperationException("CAPTURE_INPUT_PLANE: The display exceeds Windows mouse-message coordinate limits.");
                // Created hidden. Do not eat an existing source application's
                // matching up: Show waits until the shared startup gate arms.
                IntPtr window = CreateWindowEx(Styles, className, "", 0x80000000, display.X, display.Y, display.Width, display.Height,
                    IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
                if (window == IntPtr.Zero) throw new InvalidOperationException("CAPTURE_INPUT_PLANE: Windows could not create a display input window.");
                handles.Add(window); register(window);
                if (!StylesMatch(window, false))
                    throw new InvalidOperationException("CAPTURE_INPUT_PLANE: The capture input window styles could not be verified.");
            }
        } catch { Dispose(); throw; }
    }
    public bool Present(bool raise) {
        if (disposed) throw new InvalidOperationException("CAPTURE_INPUT_PLANE: The capture input windows have already stopped.");
        lock (gate) if (!input.PlaneReady(state)) return false;
        if (shown && !raise) return true;
        foreach (IntPtr window in handles) {
            uint flags = 0x0001 | 0x0002 | 0x0010 | 0x0200; // NOSIZE/NOMOVE/NOACTIVATE/NOOWNERZORDER
            if (!shown) flags |= 0x0040;
            if (!SetWindowPos(window, new IntPtr(-1), 0, 0, 0, 0, flags) || !IsWindowVisible(window) || !StylesMatch(window, true))
                throw new InvalidOperationException("CAPTURE_INPUT_PLANE: Windows could not show the capture input windows without activation.");
        }
        shown = true;
        return true;
    }
    void Abort(int kind) {
        failure = "CAPTURE_INPUT_PLANE: Windows could not process capture input; selection was cancelled without taking a screenshot.";
        lock (gate) input.AbortOwnedMouse(kind, state);
    }
    IntPtr WndProc(IntPtr window, uint message, IntPtr wp, IntPtr lp) {
        try {
            if (message == 0x0084) return new IntPtr(1); // HTCLIENT; never transparent hit testing.
            if (message == 0x0021) return new IntPtr(3); // MA_NOACTIVATE; keep the actual first down.
            if (message == 0x0014) return new IntPtr(1); // No background brush or GDI surface.
            if (message == 0x000F) { PaintData paint; BeginPaint(window, out paint); EndPaint(window, ref paint); return IntPtr.Zero; }
            if (message == 0x007E || (message == 0x02E0 && shown)) { invalidated(); return IntPtr.Zero; }
            if (message == 0x001F) { lock (gate) state.Cancel(); return IntPtr.Zero; } // WM_CANCELMODE
            if (message == 0x0215) { lock (gate) state.Cancel(); return IntPtr.Zero; } // Unexpected WM_CAPTURECHANGED; never activate to recapture.
            if (message >= 0x0200 && message <= 0x020E) {
                // Other buttons/wheel stay inside capture mode too. Never let
                // DefWindowProc turn XBUTTON into a foreign WM_APPCOMMAND.
                if (disposed || !shown) return IntPtr.Zero;
                int kind = (int)message;
                if (kind != 0x0200 && kind != 0x0201 && kind != 0x0202 && kind != 0x0204 && kind != 0x0205) return IntPtr.Zero;
                long packed = lp.ToInt64();
                Point pointer = new Point(unchecked((short)(packed & 0xffff)), unchecked((short)((packed >> 16) & 0xffff)));
                if (!ClientToScreen(window, ref pointer)) { Abort(kind); return IntPtr.Zero; }
                if (kind == 0x0200) {
                    movement++;
                    // A queued HWND move can be older than a fresh hook move.
                    // Read the current physical pointer on the UI thread so
                    // this fallback cannot regress the shared latest mailbox.
                    Point latest; if (GetPhysicalCursorPos(out latest)) moves.Publish(latest, true, false);
                }
                else {
                    if (kind == 0x0201 || kind == 0x0204) downs++; else ups++;
                    moves.Publish(pointer, false);
                    lock (gate) input.Mouse(kind, pointer, state);
                }
                return IntPtr.Zero;
            }
        } catch { Abort((int)message); return IntPtr.Zero; }
        return DefWindowProc(window, message, wp, lp);
    }
    public void Dispose() {
        if (disposed) return;
        disposed = true;
        foreach (IntPtr window in handles) if (IsWindow(window) && !DestroyWindow(window))
            failure = "CAPTURE_INPUT_PLANE: Windows could not remove a capture input window; no screenshot was taken.";
        if (registered && !UnregisterClass(className, instance))
            failure = "CAPTURE_INPUT_PLANE: Windows could not release the capture input class; no screenshot was taken.";
        registered = false;
        GC.KeepAlive(callback);
    }
}

// One read-only handle for this fresh helper lifetime. The parent owns the
// manual-reset event; no ACL/policy changes, inherited handles or stored token.
public static class NativeCancellation {
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenEvent(uint access,bool inherit,string name);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    static IntPtr cancellation;
    public static void Configure(string name){
        if(String.IsNullOrEmpty(name))return;
        if(name.Length>128||!System.Text.RegularExpressions.Regex.IsMatch(name,@"\ALocal\\EchoLingo-cancel-[0-9a-fA-F-]+\z"))throw new InvalidOperationException("NATIVE_CANCEL: Invalid task cancellation session.");
        cancellation=OpenEvent(0x100000,false,name);
        if(cancellation==IntPtr.Zero)throw new InvalidOperationException("NATIVE_CANCEL: Task cancellation session is unavailable.");
    }
    public static bool Requested {get{
        if(cancellation==IntPtr.Zero)return false;
        uint result=WaitForSingleObject(cancellation,0);
        if(result==0)return true;if(result==258)return false;
        throw new InvalidOperationException("NATIVE_CANCEL: Windows could not inspect task cancellation.");
    }}
    public static void ThrowIfRequested(){if(Requested)throw new OperationCanceledException("CANCELLED: Native task was superseded.");}
}

// The production Rust hook consumes legacy input before it reaches any source
// HWND. This own message-only mailbox transfers scalar physical coordinates;
// no focus/activation, shared pointers, clipboard or content crosses this bridge.
sealed class CaptureDelegatedInput : NativeWindow, IDisposable {
    const uint Ready=0x8381, Arm=0x8382, MoveAck=0x8383, StopMessage=0x8384, Ping=0x8385;
    const int ReadyAck=0x8390, ArmAck=0x8391, MoveMessage=0x8392, LeftDown=0x8393, LeftUp=0x8394, RightDown=0x8395, RightUp=0x8396, StopAck=0x8397, Failed=0x8398, PingAck=0x8399;
    [DllImport("user32.dll", EntryPoint="PostThreadMessageW")] static extern bool PostThreadMessage(uint thread, uint message, IntPtr word, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out Point pointer);
    readonly uint host;
    readonly IntPtr token;
    readonly object gate;
    readonly CaptureSelectionState state;
    readonly CaptureInputPolicy input;
    readonly CaptureMoveMailbox moves;
    readonly Stopwatch clock=Stopwatch.StartNew();
    long lastControl=-250, lastAck, lastPing=-250;
    bool ready, armed, finishing, stopAck, disposed, stopSent, stopAttempted;
    public bool Armed { get { return armed&&!finishing&&failure==null; } }
    string failure;
    public string Failure { get { return failure; } }
    void Fail() { failure="CAPTURE_INPUT_HOST: The native region input session could not continue; no screenshot was taken.";CaptureHealth.Set("nativeHostFailed",1);lock(gate)state.Cancel(); }
    bool Send(uint kind) { if(disposed||!PostThreadMessage(host,kind,Handle,token)){Fail();return false;}return true; }
    public CaptureDelegatedInput(uint thread,long session,object selectionGate,CaptureSelectionState selection,CaptureInputPolicy policy,CaptureMoveMailbox mailbox) {
        if(IntPtr.Size!=8||thread==0||session<=0)throw new InvalidOperationException("CAPTURE_INPUT_HOST: Invalid native input session.");
        host=thread;token=new IntPtr(session);gate=selectionGate;state=selection;input=policy;moves=mailbox;
        CreateParams parameters=new CreateParams();parameters.Parent=new IntPtr(-3);CreateHandle(parameters);
        if(Handle==IntPtr.Zero)throw new InvalidOperationException("CAPTURE_INPUT_HOST: Native mailbox creation failed.");
    }
    public void Pulse(bool finished) {
        if(disposed)return;
        long now=clock.ElapsedMilliseconds;
        if(finished)finishing=true;
        if(!ready&&now>3000){Fail();return;}
        if(ready&&now-lastAck>1250){Fail();return;}
        // A completed release sends STOP immediately; its acknowledgement is
        // the condition, not a50ms control-throttle or a fixed cleanup pause.
        if(finishing&&ready&&!stopAck&&!stopSent){stopSent=true;lastControl=now;Send(StopMessage);return;}
        if(now-lastControl<50)return;lastControl=now;
        if(!ready){Send(Ready);return;}
        if(finishing){if(!stopAck)Send(StopMessage);return;}
        bool mayArm;lock(gate)mayArm=input.Armed&&!state.Finished;
        if(!armed&&mayArm)Send(Arm);
        if(now-lastPing>=250){lastPing=now;Send(Ping);}
    }
    protected override void WndProc(ref Message message) {
        if(message.Msg>=ReadyAck&&message.Msg<=PingAck){
            if(message.WParam!=token||disposed)return;
            lastAck=clock.ElapsedMilliseconds;
            if(message.Msg==ReadyAck){ready=true;CaptureHealth.Set("nativeHostReady",1);}
            else if(message.Msg==ArmAck){armed=true;CaptureHealth.Set("nativeHostArmed",1);}
            else if(message.Msg==Failed||(message.Msg==PingAck&&message.LParam!=IntPtr.Zero)){Fail();}
            else if(message.Msg==StopAck){stopAck=true;CaptureHealth.Set("nativeHostStopped",1);if(message.LParam!=IntPtr.Zero)Fail();}
            else if(message.Msg==MoveMessage){
                Point pointer;if(GetPhysicalCursorPos(out pointer))moves.Publish(pointer,true,false);
                CaptureHealth.Increment("nativeHostMoves");Send(MoveAck);
            }else if(message.Msg>=LeftDown&&message.Msg<=RightUp){
                long packed=message.LParam.ToInt64();Point pointer=new Point(unchecked((int)(packed>>32)),unchecked((int)packed));
                int kind=message.Msg==LeftDown?0x0201:message.Msg==LeftUp?0x0202:message.Msg==RightDown?0x0204:0x0205;
                CaptureHealth.Increment(kind==0x0201||kind==0x0204?"nativeHostDowns":"nativeHostUps");
                moves.Publish(pointer,false);lock(gate){input.Mouse(kind,pointer,state);if(kind==0x0202&&state.Finished)CaptureHealth.Mark("releaseAtMilliseconds");}
            }
            return;
        }
        base.WndProc(ref message);
    }
    public bool Stop() {
        if(disposed||stopAttempted)return stopAck&&failure==null;
        stopAttempted=true;finishing=true;Stopwatch wait=Stopwatch.StartNew();
        do{Pulse(true);Application.DoEvents();if(stopAck)break;Thread.Sleep(5);}while(wait.ElapsedMilliseconds<600);
        if(!stopAck)Fail();return stopAck&&failure==null;
    }
    public void Dispose(){if(disposed)return;Stop();disposed=true;DestroyHandle();}
}

sealed class CaptureInputPump : IDisposable {
    delegate IntPtr MouseHook(int code, IntPtr message, IntPtr data);
    delegate IntPtr KeyboardHook(int code, IntPtr message, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] struct NativeMessage { public IntPtr window; public uint message; public UIntPtr wParam; public IntPtr lParam; public uint time; public Point point; public uint privateData; }
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id, MouseHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll", EntryPoint="SetWindowsHookExW", SetLastError=true)] static extern IntPtr SetKeyboardHook(int id, KeyboardHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll", SetLastError=true)] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool PeekMessage(out NativeMessage message, IntPtr window, uint min, uint max, uint remove);
    [DllImport("user32.dll", SetLastError=true)] static extern int GetMessage(out NativeMessage message, IntPtr window, uint min, uint max);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref NativeMessage message);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref NativeMessage message);
    [DllImport("user32.dll", SetLastError=true)] static extern bool PostThreadMessage(uint thread, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string module);
    readonly object gate;
    readonly CaptureSelectionState state;
    readonly CaptureInputPolicy input;
    readonly CaptureMoveMailbox moves;
    readonly bool installMouseHook;
    readonly MouseHook callback;
    readonly KeyboardHook keyboardCallback;
    readonly ManualResetEvent ready = new ManualResetEvent(false);
    Thread thread;
    IntPtr hook, keyboardHook;
    volatile uint threadId;
    volatile bool running;
    volatile string failure;
    int stopRequested;
    long mouseDowns, mouseUps, escapeDowns, escapeUps;
    long mouseHookInstalled;
    public long MouseDowns { get { return Interlocked.Read(ref mouseDowns); } }
    public long MouseUps { get { return Interlocked.Read(ref mouseUps); } }
    public long EscapeDowns { get { return Interlocked.Read(ref escapeDowns); } }
    public long EscapeUps { get { return Interlocked.Read(ref escapeUps); } }
    public long MouseHookInstalled { get { return Interlocked.Read(ref mouseHookInstalled); } }
    public bool Running { get { return running; } }
    public string Failure { get { return failure; } }
    public CaptureInputPump(object selectionGate, CaptureSelectionState selection, CaptureInputPolicy policy, CaptureMoveMailbox mailbox, bool mouseHook) {
        gate = selectionGate; state = selection; input = policy; moves = mailbox; installMouseHook = mouseHook;
        callback = OnMouse; keyboardCallback = OnKeyboard;
    }
    static bool Down(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
    void Fail(string message) { failure = message; lock (gate) state.Cancel(); }
    public void Start() {
        thread = new Thread(Run); thread.IsBackground = true; thread.Name = "EchoLingo capture input";
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
        if (!ready.WaitOne(3000)) { Stop(); throw new InvalidOperationException("CAPTURE_INPUT: Windows did not start the capture input listener in time."); }
        if (failure != null || !running) throw new InvalidOperationException(failure ?? "CAPTURE_INPUT: The capture input listener stopped before selection.");
    }
    void Run() {
        try {
            threadId = GetCurrentThreadId();
            NativeMessage message;
            PeekMessage(out message, IntPtr.Zero, 0, 0, 0); // Establish queue before publishing readiness/WM_QUIT.
            if (installMouseHook) {
                hook = SetWindowsHookEx(14, callback, GetModuleHandle(null), 0);
                // Legacy standalone diagnostics retain this managed path.
                // TOPMOST/HWND hit testing alone does not prove exclusive
                // ownership; the app uses its native session input bridge.
                if (hook != IntPtr.Zero) Interlocked.Exchange(ref mouseHookInstalled, 1);
            }
            keyboardHook = SetKeyboardHook(13, keyboardCallback, GetModuleHandle(null), 0);
            if (keyboardHook == IntPtr.Zero) { Fail("CAPTURE_INPUT: Windows could not install Escape cancellation."); return; }
            lock (gate) {
                input.ResyncReleasedButtons(Down(0x01), Down(0x02)); input.ResyncEscape(Down(0x1B));
                if (input.EscapeCancelled) state.Cancel();
            }
            running = true; ready.Set();
            while (Interlocked.CompareExchange(ref stopRequested, 0, 0) == 0) {
                int result = GetMessage(out message, IntPtr.Zero, 0, 0);
                if (result == 0) break;
                if (result < 0) { Fail("CAPTURE_INPUT: Windows could not continue listening for selection input."); break; }
                TranslateMessage(ref message); DispatchMessage(ref message);
            }
        } catch { Fail("CAPTURE_INPUT: The capture input listener failed; no screenshot was taken."); }
        finally {
            if (keyboardHook != IntPtr.Zero && !UnhookWindowsHookEx(keyboardHook)) Fail("CAPTURE_INPUT: Windows could not stop Escape cancellation; no screenshot was taken.");
            keyboardHook = IntPtr.Zero;
            if (hook != IntPtr.Zero && !UnhookWindowsHookEx(hook)) Fail("CAPTURE_INPUT: Windows could not stop region selection; no screenshot was taken.");
            hook = IntPtr.Zero; running = false; ready.Set();
        }
    }
    IntPtr OnKeyboard(int code, IntPtr message, IntPtr data) {
        if (code != 0) return CallNextHookEx(keyboardHook, code, message, data);
        int kind = message.ToInt32();
        bool down = kind == 0x0100 || kind == 0x0104, up = kind == 0x0101 || kind == 0x0105;
        if ((!down && !up) || Marshal.ReadInt32(data) != 0x1B) return CallNextHookEx(keyboardHook, code, message, data);
        if (down) Interlocked.Increment(ref escapeDowns); else Interlocked.Increment(ref escapeUps);
        bool consumed;
        lock (gate) { consumed = input.Escape(down, up); if (input.EscapeCancelled) state.Cancel(); }
        return consumed ? new IntPtr(1) : CallNextHookEx(keyboardHook, code, message, data);
    }
    IntPtr OnMouse(int code, IntPtr message, IntPtr data) {
        if (code != 0) return CallNextHookEx(hook, code, message, data);
        int kind = message.ToInt32();
        if (kind == 0x0200) {
            // No lock, HWND lookup, drawing, or consumed movement on this
            // synchronous hook thread. The latest point replaces older moves.
            try { moves.Publish(new Point(Marshal.ReadInt32(data, 0), Marshal.ReadInt32(data, 4)), true); }
            catch { moves.Stop(); } // Continue with the existing physical-cursor heartbeat.
            return CallNextHookEx(hook, code, message, data);
        }
        if (kind != 0x0201 && kind != 0x0202 && kind != 0x0204 && kind != 0x0205)
            return CallNextHookEx(hook, code, message, data);
        if (kind == 0x0201 || kind == 0x0204) Interlocked.Increment(ref mouseDowns); else Interlocked.Increment(ref mouseUps);
        try {
            Point pointer = new Point(Marshal.ReadInt32(data, 0), Marshal.ReadInt32(data, 4));
            moves.Publish(pointer, false);
            lock (gate) if (input.Mouse(kind, pointer, state)) return new IntPtr(1);
        } catch { Fail("CAPTURE_INPUT: Region selection could not process pointer input."); return new IntPtr(1); }
        return CallNextHookEx(hook, code, message, data);
    }
    public bool Stop() {
        Interlocked.Exchange(ref stopRequested, 1);
        if (thread == null) return true;
        uint owner = threadId;
        if (owner != 0 && thread.IsAlive) PostThreadMessage(owner, 0x0012, UIntPtr.Zero, IntPtr.Zero);
        return thread.Join(2000);
    }
    public void Dispose() { if (Stop()) ready.Dispose(); }
}

sealed class RegionPicker : ApplicationContext {
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out Point point);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern IntPtr GetThreadDesktop(uint thread);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder information, int length, out int needed);
    readonly List<CaptureOverlay> overlays = new List<CaptureOverlay>();
    readonly List<IntPtr> handles = new List<IntPtr>();
    readonly List<IntPtr> hintHandles = new List<IntPtr>();
    readonly CaptureInputPlanes planes;
    readonly bool mouseHook;
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly Stopwatch lifetime = new Stopwatch();
    readonly CaptureSelectionState state;
    readonly CaptureInputPolicy input = new CaptureInputPolicy();
    readonly CaptureTopologyPolicy topology;
    readonly CaptureHoverPolicy hoverPolicy = new CaptureHoverPolicy();
    readonly CaptureHoverResolver hoverResolver;
    readonly object selectionGate = new object();
    readonly CaptureRedrawPolicy redraw = new CaptureRedrawPolicy();
    readonly CaptureInputHealthPolicy health = new CaptureInputHealthPolicy();
    readonly CaptureWakeWindow wake;
    readonly CaptureMoveMailbox moves;
    CaptureInputPump inputPump;
    CaptureDelegatedInput delegated;
    readonly uint hostThread;
    readonly long hostToken;
    bool stopping, cleaned, observing;
    int renderedHighlight = -2;
    Rectangle renderedSelection;
    Rectangle renderedHover;
    long lastRaise = -250;
    string failure;
    public RegionPicker(bool useMouseHook, uint nativeHostThread, long nativeHostToken) {
        hostThread=nativeHostThread;hostToken=nativeHostToken;
        mouseHook = useMouseHook && hostThread==0;
        CaptureHealth.Set("inputBackend", hostThread!=0 ? 3 : mouseHook ? 1 : 2);
        Point pointer;
        if (!GetPhysicalCursorPos(out pointer)) throw new InvalidOperationException("CAPTURE: Windows could not read the capture pointer.");
        topology = ReadTopology();
        CaptureDisplaySnapshot[] displays = topology.Displays;
        Rectangle[] rectangles = new Rectangle[displays.Length];
        for (int i = 0; i < displays.Length; i++) rectangles[i] = displays[i].Bounds;
        state = new CaptureSelectionState(rectangles, pointer);
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += DisplaysChanged;
        observing = true;
        try {
            wake = new CaptureWakeWindow(OnMoveWake);
            moves = new CaptureMoveMailbox(wake.Post); wake.Bind(moves);
            planes = new CaptureInputPlanes(rectangles, selectionGate, state, input, moves, InvalidateEnvironment, handles.Add);
            CaptureHealth.Set("inputPlaneCount", planes.Count);
            for (int i = 0; i < rectangles.Length; i++) overlays.Add(new CaptureOverlay(rectangles[i], i, displays[i].Dpi, InvalidateEnvironment,
                delegate(IntPtr handle) { handles.Add(handle); hintHandles.Add(handle); }));
            hoverResolver = new CaptureHoverResolver(hintHandles, planes.Handles);
        } catch { Dispose(); throw; }
        timer.Interval = 16;
        timer.Tick += Tick;
        CapturePerformance.Mark("pickerConstructedMilliseconds");
    }
    static bool Down(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
    static CaptureTopologyPolicy ReadTopology() {
        Screen[] screens = Screen.AllScreens;
        CaptureDisplaySnapshot[] displays = new CaptureDisplaySnapshot[screens.Length];
        for (int i = 0; i < screens.Length; i++) {
            uint dpi;
            using (CaptureDpiProbe probe = new CaptureDpiProbe(screens[i].Bounds)) dpi = GetDpiForWindow(probe.Handle);
            displays[i] = new CaptureDisplaySnapshot(screens[i].DeviceName, screens[i].Bounds, dpi);
        }
        return new CaptureTopologyPolicy(displays, GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext()));
    }
    void InvalidateEnvironment() { topology.Invalidate(); }
    static string DesktopName(IntPtr desktop) {
        StringBuilder name = new StringBuilder(256); int needed;
        if (desktop == IntPtr.Zero || !GetUserObjectInformation(desktop, 2, name, name.Capacity * 2, out needed)) return null;
        return name.ToString();
    }
    static void ValidateInputDesktop() {
        // Read-only validation; never switch desktops, elevate or alter security.
        IntPtr active = OpenInputDesktop(0, false, 0x0001);
        try {
            string activeName = DesktopName(active), currentName = DesktopName(GetThreadDesktop(GetCurrentThreadId()));
            if (activeName == null || currentName == null || !String.Equals(activeName, currentName, StringComparison.Ordinal))
            {
                CapturePerformance.Set("desktopMatched", 0);
                CaptureHealth.Set("desktopMatched", 0);
                throw new InvalidOperationException("CAPTURE_DESKTOP_UNAVAILABLE: Return to the unlocked Windows desktop; protected system dialogs cannot be selected.");
            }
            CapturePerformance.Set("desktopMatched", 1);
            CaptureHealth.Set("desktopMatched", 1);
        } finally { if (active != IntPtr.Zero) CloseDesktop(active); }
    }
    public void ValidateCaptureEnvironment() {
        ValidateInputDesktop();
        bool valid = !topology.Invalid && topology.Matches(ReadTopology());
        if (!valid || topology.Invalid)
            throw new InvalidOperationException("CAPTURE_DISPLAY_CHANGED: Display geometry or DPI changed; select the region again.");
    }
    public Rectangle SelectRegion() {
        try {
            inputPump = new CaptureInputPump(selectionGate, state, input, moves, mouseHook); inputPump.Start();
            if(hostThread!=0)delegated=new CaptureDelegatedInput(hostThread,hostToken,selectionGate,state,input,moves);
            CapturePerformance.Mark("inputReadyMilliseconds");
            ValidateCaptureEnvironment();
            lifetime.Start(); timer.Start();
            Application.Run(this);
        } finally { Cleanup(); }
        if (failure != null) throw new InvalidOperationException(failure);
        if (!state.Finished || state.Cancelled || input.EscapeCancelled)
            throw new OperationCanceledException("CANCELLED: Screenshot selection was cancelled (Escape, right click, display change, or 120-second timeout).");
        foreach (IntPtr handle in handles) if (IsWindow(handle)) throw new InvalidOperationException("CAPTURE: A selection overlay could not be removed.");
        return state.Selected;
    }
    void Tick(object sender, EventArgs args) { UpdateFrame(false); }
    void OnMoveWake() { if (!cleaned && !stopping && lifetime.IsRunning) UpdateFrame(true); }
    void UpdateFrame(bool moved) {
        if (cleaned) return;
        long elapsed = lifetime.ElapsedMilliseconds;
        bool redrawDue = redraw.IsDue(elapsed);
        if (moved && !redrawDue) return; // The unchanged 16ms heartbeat supplies a final coalesced frame.
        long frameStarted = CapturePerformance.Begin();
        bool raise = elapsed - lastRaise >= 250, finished, dragging, mayStop, releaseExceeded, armed, swallowed;
        int highlighted; Rectangle selected; Point pointer;
        if (!(moved && moves.TryRead(out pointer)) && !GetPhysicalCursorPos(out pointer)) failure = "CAPTURE: Windows could not read the capture pointer.";
        else { CapturePerformance.Set("knownPointer", 1); CaptureHealth.Set("knownPointer", 1); }
        if (inputPump != null && (inputPump.Failure != null || !inputPump.Running)) failure = inputPump.Failure ?? "CAPTURE_INPUT: The selection input listener stopped; no screenshot was taken.";
        if (planes != null && planes.Failure != null) failure = planes.Failure;
        if (topology.Invalid) failure = "CAPTURE_DISPLAY_CHANGED: Display geometry or DPI changed; select the region again.";
        if (raise) {
            try { ValidateInputDesktop(); }
            catch (InvalidOperationException error) { failure = error.Message; }
        }
        bool left = Down(0x01), right = Down(0x02);
        if(NativeCancellation.Requested){lock(selectionGate)state.Cancel();}
        lock (selectionGate) {
            if (!input.Armed) input.ResyncReleasedButtons(left, right);
            if (input.EscapeCancelled || failure != null) state.Cancel();
            int mismatch = health.Observe(input.Armed, state.Finished, state.Dragging, input.LeftSwallowed, left, elapsed);
            if (mismatch != 0) {
                CaptureHealth.Set("mismatchKind", mismatch);
                failure = "CAPTURE_INPUT_STATE: The capture input windows did not receive a mouse press. Selection was cancelled without taking a screenshot; retry and include the capture diagnostics.";
                state.Cancel();
            }
            state.Expire(elapsed);
            if (!state.Finished) state.Move(pointer);
            finished = state.Finished; dragging = state.Dragging; highlighted = state.Highlighted; selected = state.Selected;
            mayStop = input.MayStop(finished, elapsed); releaseExceeded = input.ReleaseGraceExceeded;
            armed = input.Armed; swallowed = input.LeftSwallowed;
        }
        if(delegated!=null){
            delegated.Pulse(finished);
            if(delegated.Failure!=null){failure=delegated.Failure;lock(selectionGate)state.Cancel();}
            armed=armed&&delegated.Armed;
        }
        CapturePerformance.Set("uiPhase", finished ? 3 : dragging ? 2 : armed ? 1 : 0);
        CapturePerformance.Set("inputArmed", armed ? 1 : 0);
        CapturePerformance.Set("leftSwallowed", swallowed ? 1 : 0);
        CapturePerformance.Set("physicalLeftDown", left ? 1 : 0);
        CaptureHealth.Set("uiPhase", finished ? 3 : dragging ? 2 : armed ? 1 : 0);
        CaptureHealth.Set("inputArmed", armed ? 1 : 0);
        CaptureHealth.Set("leftSwallowed", swallowed ? 1 : 0);
        CaptureHealth.Set("physicalLeftDown", left ? 1 : 0);
        CaptureHealth.Set("dragging", dragging ? 1 : 0);
        Rectangle hovered = Rectangle.Empty;
        if (armed && !finished && !dragging && highlighted >= 0) {
            if (hoverPolicy.BeginQuery(elapsed)) {
                try { hoverPolicy.SetFrame(hoverResolver.Resolve(pointer)); }
                catch { hoverPolicy.Clear(); } // A decorative hint cannot invalidate free ROI selection.
            }
            hovered = hoverPolicy.Current(pointer, lifetime.ElapsedMilliseconds, true);
        } else hoverPolicy.Clear();
        // The input pump may begin/end a drag while metadata is being queried.
        // Recheck only phase under its short lock; native queries stay outside.
        lock (selectionGate) if (state.Dragging || state.Finished) { hovered = Rectangle.Empty; hoverPolicy.Clear(); }
        if (finished) {
            if (!stopping) { stopping = true; CaptureHealth.Mark("releaseAtMilliseconds");CapturePerformance.Mark("selectionFinishedMilliseconds"); foreach (CaptureOverlay overlay in overlays) overlay.Hide(); }
            // Keep a short bounded drain for matching mouse/Escape releases.
            if (mayStop) {
                if (releaseExceeded && failure == null)
                    failure = "CAPTURE_INPUT_RELEASE: Selection stopped while a button or Escape was still held. Release it before retrying; no screenshot was taken.";
                ExitThread();
            }
        } else if (armed && redrawDue && (raise || renderedHighlight != highlighted || renderedSelection != selected || renderedHover != hovered)) {
            redraw.Presented(elapsed);
            renderedHighlight = highlighted; renderedSelection = selected; renderedHover = hovered;
            bool presented = false;
            try {
                // Repair the input plane first, THEN the thin blue windows,
                // so input coverage never covers the visual hints in Z order.
                if (planes.Present(raise)) {
                    foreach (CaptureOverlay overlay in overlays) overlay.Present(highlighted, selected, hovered, raise);
                    presented = true;
                }
            }
            catch (Exception error) {
                failure = error is InvalidOperationException && error.Message.StartsWith("CAPTURE_", StringComparison.Ordinal)
                    ? error.Message : "CAPTURE_OVERLAY: Windows could not update the selection border; no screenshot was taken.";
                lock (selectionGate) state.Cancel();
            }
            if (presented && raise) lastRaise = elapsed;
            if (presented) CapturePerformance.Mark("firstBordersVisibleMilliseconds");
        }
        CapturePerformance.End(moved ? "moveFrame" : "heartbeatFrame", frameStarted);
    }
    void DisplaysChanged(object sender, EventArgs args) {
        // A separate sticky flag remains effective after state.End(). It is
        // set directly on the event thread, including while BitBlt is running.
        InvalidateEnvironment();
    }
    void Cleanup() {
        if (cleaned) return;
        cleaned = true;
        timer.Stop();
        if (wake != null) wake.Stop();
        if(delegated!=null){
            if(!delegated.Stop())failure=delegated.Failure??"CAPTURE_INPUT_HOST: Native input could not stop safely; no screenshot was taken.";
            delegated.Dispose();delegated=null;
        }
        if (inputPump != null) {
            if (!inputPump.Stop()) failure = "CAPTURE_INPUT: Windows could not stop the selection input listener; no screenshot was taken.";
            else if (inputPump.Failure != null) failure = inputPump.Failure;
            CapturePerformance.Set("hookMouseDowns", inputPump.MouseDowns); CapturePerformance.Set("hookMouseUps", inputPump.MouseUps);
            CapturePerformance.Set("hookEscapeDowns", inputPump.EscapeDowns); CapturePerformance.Set("hookEscapeUps", inputPump.EscapeUps);
            CaptureHealth.Set("hookMouseDowns", inputPump.MouseDowns); CaptureHealth.Set("hookMouseUps", inputPump.MouseUps);
            CaptureHealth.Set("hookEscapeDowns", inputPump.EscapeDowns); CaptureHealth.Set("hookEscapeUps", inputPump.EscapeUps);
            CaptureHealth.Set("hookRunningAfterStop", inputPump.Running ? 1 : 0);
            CaptureHealth.Set("mouseHookInstalled", inputPump.MouseHookInstalled);
            inputPump.Dispose(); inputPump = null;
        }
        if (planes != null) {
            CaptureHealth.Set("inputPlaneDowns", planes.Downs); CaptureHealth.Set("inputPlaneUps", planes.Ups); CaptureHealth.Set("inputPlaneMoves", planes.Moves);
            CaptureHealth.Set("inputPlaneFallbackUsed", planes.Downs + planes.Ups > 0 ? 1 : 0);
            planes.Dispose();
            CaptureHealth.Set("inputPlaneVisibleCount", planes.VisibleCount);
            CaptureHealth.Set("inputPlaneRemainingAfterCleanup", planes.RemainingCount);
            if (planes.Failure != null) failure = planes.Failure;
        }
        foreach (CaptureOverlay overlay in overlays) overlay.Dispose();
        if (moves != null) { CapturePerformance.Set("movesPublished", moves.Moves); CapturePerformance.Set("moveWakesPosted", moves.Posts); CapturePerformance.Set("movePostFailures", moves.Failures); }
        if (moves != null) { CaptureHealth.Set("hookMouseMoves", moves.Moves); CaptureHealth.Set("moveWakesPosted", moves.Posts); CaptureHealth.Set("movePostFailures", moves.Failures); }
        if (wake != null) wake.Dispose();
        CapturePerformance.Mark("overlaysDisposedMilliseconds");CaptureHealth.Duration("releaseToCleanupMilliseconds","releaseAtMilliseconds");
    }
    protected override void Dispose(bool disposing) {
        if (disposing) {
            Cleanup(); timer.Dispose();
            if (observing) { Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= DisplaysChanged; observing = false; }
        }
        base.Dispose(disposing);
    }
}
'@
    $references = @(
        [System.Windows.Forms.Form].Assembly.Location
        [System.Drawing.Bitmap].Assembly.Location
        [System.Windows.Automation.AutomationElement].Assembly.Location
        [System.Windows.Automation.AutomationPattern].Assembly.Location
        [System.Windows.DependencyObject].Assembly.Location
    ) | Select-Object -Unique
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    }
    [NativeCancellation]::Configure($NativeCancellationEvent)
    [EchoLingoNative]::ExcludedSourceProcessId = $ExcludedSourceProcessId
    [NativeCancellation]::ThrowIfRequested()
    $script:HelperPhases['nativeTypesReadyMilliseconds'] = $script:HelperWatch.Elapsed.TotalMilliseconds
    if ($PerformanceDiagnostics) { [CapturePerformance]::Enable() }
    [EchoLingoNative]::ConfigureDpi()

    function Initialize-Ocr {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
        $null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]
        $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapPixelFormat, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapAlphaMode, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
        $script:AsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
            $_.GetGenericArguments().Length -eq 1 -and $_.GetParameters().Length -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } | Select-Object -First 1
        if ($null -eq $script:AsTask) { throw 'OCR_UNAVAILABLE: Windows Runtime async support is unavailable.' }
    }
    function Await-WinRt($Operation, [Type]$ResultType) {
        $method = $script:AsTask.MakeGenericMethod($ResultType)
        $task = $method.Invoke($null, @($Operation))
        while (-not $task.IsCompleted) {
            if ([NativeCancellation]::Requested) {
                try { $Operation.Cancel() } catch { }
                [NativeCancellation]::ThrowIfRequested()
            }
            $remaining = [int][Math]::Max(0.0, ($script:OcrDeadline - [DateTime]::UtcNow).TotalMilliseconds)
            if ($remaining -le 0) {
                try { $Operation.Cancel() } catch { }
                throw 'OCR_TIMEOUT: Local OCR exceeded 30 seconds.'
            }
            # A task completion wakes immediately.30ms only bounds cancellation
            # checks; this is not a delay applied after OCR has completed.
            $null = $task.Wait([Math]::Min(30, $remaining))
        }
        [NativeCancellation]::ThrowIfRequested()
        return $task.GetAwaiter().GetResult()
    }
    function Test-OcrBounds($Line) {
        foreach ($name in @('X', 'Y', 'Width', 'Height')) {
            $number = [double]$Line.$name
            if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $false }
        }
        return ([double]$Line.Width -gt 0 -and [double]$Line.Height -gt 0)
    }
    function Test-OcrStructuralLine([string]$Text) {
        return ($Text -match '^\s' -or $Text.Contains("`t") -or $Text.Contains('|') -or
            $Text -cmatch '^\s*(?:[-*+\u2022]\s|\d+[.)]\s|#{1,6}\s|>\s|```|~~~|//|/\*|\*/|[{}]|(?:if|for|while|def|class|import|return|const|let|var|function)\b|https?://|www\.)')
    }
    function Join-OcrLayoutLines([object[]]$OcrLines, [bool]$AllowGeometry = $true) {
        $heights = @($OcrLines | Where-Object { Test-OcrBounds $_ } | ForEach-Object { [double]$_.Height } | Sort-Object)
        if (-not $AllowGeometry -or $heights.Count -eq 0) {
            return (($OcrLines | ForEach-Object { $_.Text }) -join "`n")
        }
        $middle = [int][Math]::Floor($heights.Count / 2)
        $median = [double]$heights[$middle]
        if (($heights.Count % 2) -eq 0) { $median = ([double]$heights[$middle - 1] + $median) / 2 }
        # Estimate ordinary baseline pitch within each consecutive column.
        # Glyph height alone cannot distinguish generous leading from a blank
        # paragraph. The lower median resists a single unusually large gap.
        $groups = [int[]]::new($OcrLines.Count)
        $pitches = @{}
        $group = 0
        for ($i = 1; $i -lt $OcrLines.Count; $i++) {
            $a = $OcrLines[$i - 1]; $b = $OcrLines[$i]
            if ((Test-OcrBounds $a) -and (Test-OcrBounds $b)) {
                # Windows PowerShell5.1 can select Math.Max(Int32,Int32) when
                # its first argument is integer0, rounding fractional layout
                # widths to0. Pin every geometry operand to Double.
                $overlap = [Math]::Max([double]0.0, [Math]::Min(([double]$a.X + [double]$a.Width), ([double]$b.X + [double]$b.Width)) - [Math]::Max([double]$a.X, [double]$b.X))
                $sameColumn = $overlap -gt (0.1 * [Math]::Min([double]$a.Width, [double]$b.Width))
                if (-not $sameColumn -and $b.Y -lt ($a.Y - 0.9 * $median)) { $group++ }
                $pitch = [double]$b.Y - [double]$a.Y
                if ($sameColumn -and $pitch -gt 0 -and -not (Test-OcrStructuralLine ([string]$a.Text)) -and -not (Test-OcrStructuralLine ([string]$b.Text))) {
                    if (-not $pitches.ContainsKey($group)) { $pitches[$group] = [Collections.Generic.List[double]]::new() }
                    $pitches[$group].Add($pitch)
                }
            }
            $groups[$i] = $group
        }
        $normalPitch = @{}
        foreach ($key in @($pitches.Keys)) {
            $ordered = @($pitches[$key] | Sort-Object)
            if ($ordered.Count -ge 2) { $normalPitch[$key] = [double]$ordered[[int][Math]::Floor(($ordered.Count - 1) / 2)] }
        }
        $builder = [Text.StringBuilder]::new()
        $insideCodeFence = $false
        for ($index = 0; $index -lt $OcrLines.Count; $index++) {
            $current = $OcrLines[$index]
            $trimmed = ([string]$current.Text).TrimStart()
            $fence = $trimmed.StartsWith('```') -or $trimmed.StartsWith('~~~')
            if ($index -gt 0) {
                $previous = $OcrLines[$index - 1]
                $paragraphBreak = $false
                $structured = $insideCodeFence -or (Test-OcrStructuralLine ([string]$previous.Text)) -or (Test-OcrStructuralLine ([string]$current.Text))
                if (-not $structured -and (Test-OcrBounds $previous) -and (Test-OcrBounds $current)) {
                    $referenceHeight = [Math]::Max($median, [Math]::Min([double]$previous.Height, [double]$current.Height))
                    $verticalGap = [double]$current.Y - ([double]$previous.Y + [double]$previous.Height)
                    $overlap = [Math]::Max([double]0.0, [Math]::Min(([double]$previous.X + [double]$previous.Width), ([double]$current.X + [double]$current.Width)) - [Math]::Max([double]$previous.X, [double]$current.X))
                    $columnReset = ($overlap -le (0.1 * [Math]::Min([double]$previous.Width, [double]$current.Width))) -and
                        ([double]$current.Y -lt ([double]$previous.Y - 0.9 * $referenceHeight))
                    $pitch = [double]$current.Y - [double]$previous.Y
                    $baseline = $normalPitch[$groups[$index]]
                    $unusualPitch = $null -ne $baseline -and $pitch -ge (1.6 * $baseline) -and
                        ($pitch - $baseline) -ge [Math]::Max((0.9 * $referenceHeight), (0.35 * $baseline))
                    $absoluteGap = $verticalGap -ge (3.0 * $referenceHeight)
                    $paragraphBreak = $columnReset -or $unusualPitch -or $absoluteGap
                }
                if ($paragraphBreak) { $null = $builder.Append("`n`n") }
                else { $null = $builder.Append("`n") }
            }
            # Keep recognizer order, whitespace, list markers and code lines.
            # This helper only adds high-confidence paragraph separators.
            $null = $builder.Append([string]$current.Text)
            if ($fence) { $insideCodeFence = -not $insideCodeFence }
        }
        return $builder.ToString()
    }
    function Get-OcrLayoutLines($Result) {
        $lines = [Collections.Generic.List[object]]::new()
        foreach ($line in $Result.Lines) {
            $left = [double]::PositiveInfinity
            $top = [double]::PositiveInfinity
            $right = [double]::NegativeInfinity
            $bottom = [double]::NegativeInfinity
            try {
                foreach ($word in $line.Words) {
                    $box = $word.BoundingRect
                    $candidate = [pscustomobject]@{ X = $box.X; Y = $box.Y; Width = $box.Width; Height = $box.Height }
                    if (Test-OcrBounds $candidate) {
                        $left = [Math]::Min($left, [double]$box.X)
                        $top = [Math]::Min($top, [double]$box.Y)
                        $right = [Math]::Max($right, ([double]$box.X + [double]$box.Width))
                        $bottom = [Math]::Max($bottom, ([double]$box.Y + [double]$box.Height))
                    }
                }
            } catch {
                # Optional layout metadata must never discard recognized text.
                $left = [double]::NaN
                $top = [double]::NaN
            }
            $lines.Add([pscustomobject]@{ Text = [string]$line.Text; X = $left; Y = $top; Width = ($right - $left); Height = ($bottom - $top) })
        }
        return $lines.ToArray()
    }
    function Test-OcrParagraphGeometry {
        $lines = @(
            [pscustomobject]@{ Text = 'first line'; X = 0; Y = 0; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'second line'; X = 0; Y = 14; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'next paragraph'; X = 0; Y = 38; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'continued paragraph'; X = 0; Y = 52; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'column two'; X = 130; Y = 0; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'still column two'; X = 130; Y = 14; Width = 100; Height = 10 }
        )
        $expected = "first line`nsecond line`n`nnext paragraph`ncontinued paragraph`n`ncolumn two`nstill column two"
        $scaled = @($lines | ForEach-Object {
            [pscustomobject]@{ Text = $_.Text; X = ($_.X / 1000.0); Y = ($_.Y / 1000.0); Width = ($_.Width / 1000.0); Height = ($_.Height / 1000.0) }
        })
        $flat = ($lines | ForEach-Object { $_.Text }) -join "`n"
        if ((Join-OcrLayoutLines $lines) -cne $expected) { throw 'SELF_TEST: OCR paragraph geometry fixture failed: pixel-layout-and-column-order.' }
        if ((Join-OcrLayoutLines $scaled) -cne $expected) { throw 'SELF_TEST: OCR paragraph geometry fixture failed: fractional-scale-layout.' }
        if ((Join-OcrLayoutLines $lines $false) -cne $flat) { throw 'SELF_TEST: OCR paragraph geometry fixture failed: rotated-plain-order-fallback.' }
        $subpixel = @(
            [pscustomobject]@{ Text = 'fraction first'; X = 0.11; Y = 0.1; Width = 0.15; Height = 0.01 }
            [pscustomobject]@{ Text = 'fraction second'; X = 0.12; Y = 0.114; Width = 0.14; Height = 0.01 }
            [pscustomobject]@{ Text = 'fraction paragraph'; X = 0.12; Y = 0.138; Width = 0.14; Height = 0.01 }
            [pscustomobject]@{ Text = 'fraction continued'; X = 0.12; Y = 0.152; Width = 0.14; Height = 0.01 }
        )
        if ((Join-OcrLayoutLines $subpixel) -cne "fraction first`nfraction second`n`nfraction paragraph`nfraction continued") {
            throw 'SELF_TEST: OCR paragraph geometry fixture failed: fractional-overlap-and-baseline.'
        }
        $structured = @(
            [pscustomobject]@{ Text = '- first item'; X = 0; Y = 0; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = '  indented continuation'; X = 10; Y = 80; Width = 90; Height = 10 }
            [pscustomobject]@{ Text = '    return value;'; X = 20; Y = 180; Width = 80; Height = 10 }
        )
        if ((Join-OcrLayoutLines $structured) -cne "- first item`n  indented continuation`n    return value;") {
            throw 'SELF_TEST: OCR layout changed a list or indented code line.'
        }
        $leading = @(
            [pscustomobject]@{ Text = 'wide first'; X = 0; Y = 0; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'wide second'; X = 0; Y = 24; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'wide third'; X = 0; Y = 48; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'new paragraph'; X = 0; Y = 102; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = 'paragraph continued'; X = 0; Y = 126; Width = 100; Height = 10 }
        )
        if ((Join-OcrLayoutLines $leading) -cne "wide first`nwide second`nwide third`n`nnew paragraph`nparagraph continued") {
            throw 'SELF_TEST: Ordinary wide leading became an empty paragraph, or a real paragraph gap was lost.'
        }
        if ((Join-OcrLayoutLines @($leading[0], $leading[1])) -cne "wide first`nwide second") {
            throw 'SELF_TEST: Sparse OCR lines must not infer a paragraph from glyph height alone.'
        }
        $invalid = @([pscustomobject]@{ Text = 'unmodified  spaces'; X = [double]::NaN; Y = 0; Width = 100; Height = 10 })
        if ((Join-OcrLayoutLines $invalid) -cne 'unmodified  spaces') { throw 'SELF_TEST: Invalid geometry changed original recognizer text.' }
    }
    function Get-OcrText([string]$Path) {
        [NativeCancellation]::ThrowIfRequested()
        $script:HelperPhases['ocrStartMilliseconds'] = $script:HelperWatch.Elapsed.TotalMilliseconds
        Initialize-Ocr
        $script:OcrDeadline = [DateTime]::UtcNow.AddSeconds(30)
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        if ($null -eq $engine) {
            $languages = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages)
            if ($languages.Count -gt 0) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($languages[0]) }
        }
        $script:HelperPhases['ocrEngineReadyMilliseconds'] = $script:HelperWatch.Elapsed.TotalMilliseconds
        if ($null -eq $engine) {
            throw 'OCR_LANGUAGE_MISSING: Install an OCR-capable language in Windows Settings > Time & language > Language & region > Language options. English or Chinese basic typing/OCR language features are suitable.'
        }
        $stream = $null
        $bitmap = $null
        try {
            $file = Await-WinRt ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
            $stream = Await-WinRt ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
            $decoder = Await-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
            $maximum = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
            if ($decoder.PixelWidth -gt $maximum -or $decoder.PixelHeight -gt $maximum) {
                throw "OCR_IMAGE_TOO_LARGE: Selected image exceeds the Windows OCR limit of $maximum pixels per dimension. Select a smaller region."
            }
            $bitmap = Await-WinRt ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)) ([Windows.Graphics.Imaging.SoftwareBitmap])
            $script:HelperPhases['ocrBitmapReadyMilliseconds'] = $script:HelperWatch.Elapsed.TotalMilliseconds
            $result = Await-WinRt ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
            $script:HelperPhases['ocrRecognizedMilliseconds'] = $script:HelperWatch.Elapsed.TotalMilliseconds
            $lines = @(Get-OcrLayoutLines $result)
            $allowGeometry = $true
            try {
                $angle = $result.TextAngle
                if ($null -ne $angle) {
                    $degrees = [double]$angle
                    $allowGeometry = -not ([double]::IsNaN($degrees) -or [double]::IsInfinity($degrees)) -and [Math]::Abs($degrees) -le 10
                }
            } catch { $allowGeometry = $false }
            $text = Join-OcrLayoutLines $lines $allowGeometry
            if ([string]::IsNullOrWhiteSpace($text)) { throw 'NO_TEXT: No text was recognized. Select a larger, clearer area and retry.' }
            return $text
        } finally {
            if ($null -ne $bitmap) { $bitmap.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
    function Get-Diagnostics {
        $available = @()
        $ocrError = $null
        try {
            Initialize-Ocr
            $available = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag })
        } catch { $ocrError = $_.Exception.Message }
        return @{
            platform = 'windows'; helper = 'windows-powershell-dotnet-winrt'; nativeBackend = $script:NativeBackend; localOcr = $true
            ocrEngine = 'Windows.Media.Ocr'; ocrLanguages = $available; ocrAvailable = ($available.Count -gt 0)
            ocrError = $ocrError; powerShellVersion = $PSVersionTable.PSVersion.ToString()
            selection = 'UI Automation TextPattern, then Ctrl+C with clipboard restoration'
            screenCount = [System.Windows.Forms.Screen]::AllScreens.Length
            virtualScreen = [System.Windows.Forms.SystemInformation]::VirtualScreen.ToString()
            dpiMode = 'Per-monitor v2 requested; system-aware fallback on older Windows'
            captureSelection = 'Live transparent per-display blue border; left drag; Escape/right/120-second cancellation'
        }
    }

    function Get-PngBase64([string]$Path) {
        if ((Get-Item -LiteralPath $Path).Length -gt (8 * 1024 * 1024)) {
            throw 'CAPTURE_TOO_LARGE: Captured PNG exceeds 8 MiB. Select a smaller region.'
        }
        $bytes = [IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -eq 0) { throw 'CAPTURE: Captured PNG was empty.' }
        if ($bytes.Length -gt (8 * 1024 * 1024)) {
            throw 'CAPTURE_TOO_LARGE: Captured PNG exceeds 8 MiB. Select a smaller region.'
        }
        return [Convert]::ToBase64String($bytes)
    }

    switch ($Mode) {
        'selected-text' { Write-Result @{ ok = $true; text = [EchoLingoNative]::SelectedText() } }
        'clipboard' { Write-Result @{ ok = $true; text = [EchoLingoNative]::ClipboardText() } }
        'copy' {
            # PowerShell may initialize Console.In before InputEncoding changes.
            # Read the redirected byte stream explicitly so Unicode survives the
            # Rust/helper boundary, including when the host console is not UTF-8.
            $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false, $true), $false)
            try { [EchoLingoNative]::CopyText($reader.ReadToEnd()) }
            finally { $reader.Dispose() }
            Write-Result @{ ok = $true; text = '' }
        }
        'diagnostics' { Write-Result @{ ok = $true; diagnostics = (Get-Diagnostics) } }
        'capture-state-self-test' { Write-Result @{ ok = $true; diagnostics = [CaptureSelectionState]::SelfTest() } }
        { $_ -in 'capture-ocr', 'capture-image', 'self-test' } {
            $path = [IO.Path]::Combine([IO.Path]::GetTempPath(), ('echolingo-' + [Guid]::NewGuid().ToString('N') + '.png'))
            try {
                if ($Mode -in 'capture-ocr', 'capture-image') { [EchoLingoNative]::CaptureRegion($path, ($InputBackend -ne 'planeOnly'), $CaptureHostThreadId, $CaptureHostToken) }
                else { [EchoLingoNative]::CreateFixture($path) }
                if ($Mode -eq 'capture-image') {
                    Write-Result @{ ok = $true; imageBase64 = (Get-PngBase64 $path) }
                } else {
                    $text = Get-OcrText $path
                    if ($Mode -eq 'self-test') {
                        $captureState = [CaptureSelectionState]::SelfTest()
                        Test-OcrParagraphGeometry
                        if ($text -notmatch '2468') { throw 'SELF_TEST: Local OCR did not recognize the generated fixture.' }
                        $base64 = Get-PngBase64 $path
                        if ([Convert]::FromBase64String($base64).Length -ne (Get-Item -LiteralPath $path).Length) { throw 'SELF_TEST: PNG base64 roundtrip failed.' }
                        Write-Result @{ ok = $true; diagnostics = @{ ocrFixturePassed = $true; pngBase64RoundtripPassed = $true; paragraphGeometryFixturePassed = $true; captureStateFixture = $captureState; recognized = $text; diagnostics = (Get-Diagnostics); interactiveCaptureTested = $false; clipboardChanged = $false } }
                    } else { Write-Result @{ ok = $true; text = $text } }
                }
            } finally { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }
        }
        default { throw 'Unsupported native helper mode.' }
    }
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    Write-Result @{ ok = $false; error = $message }
    exit 1
}
