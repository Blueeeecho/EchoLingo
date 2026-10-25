# Windows PowerShell 5.1, built-in .NET Framework, UI Automation and Windows OCR.
# No download, OCR package, PowerShell module or network access is required.
[CmdletBinding()]
param(
    [ValidateSet('selected-text', 'capture-ocr', 'capture-image', 'clipboard', 'copy', 'diagnostics', 'self-test', 'capture-state-self-test')]
    [string]$Mode = $env:ECHOLINGO_NATIVE_MODE
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-Result($Value) {
    [Console]::Out.WriteLine(($Value | ConvertTo-Json -Depth 12 -Compress))
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName WindowsBase
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
using System.Windows.Automation;
using System.Windows.Automation.Text;
using System.Windows.Forms;

// Pure policies shared by the real UIA/copy path and synthetic tests. A null
// UIA result is unavailable, while a supported empty range remains an explicit
// empty selection. A clipboard clear alone is not a completed copy operation.
public static class SelectionCopyPolicy {
    public const string InputBlocked = "SELECTION: Windows blocked copy input. Elevated or protected apps may not allow selection capture; try screenshot OCR.";
    public static string AutomationText<T>(T[] ranges, Func<T, string> read) where T : class {
        if (ranges == null) return null;
        StringBuilder text = new StringBuilder();
        foreach (T range in ranges) {
            if (range == null) return null;
            string part = read(range);
            if (!String.IsNullOrEmpty(part)) { if (text.Length > 0) text.AppendLine(); text.Append(part); }
        }
        if (!String.IsNullOrWhiteSpace(text.ToString())) return text.ToString();
        throw new InvalidOperationException("NO_SELECTION: No text is selected in the source application.");
    }

    public enum Observation { Waiting, Completed, UnchangedTimeout, UnfinishedTimeout, Superseded }
    public sealed class Completion {
        readonly uint initial;
        uint? candidate;
        string candidateText;
        long stableSince;
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
                if (!candidate.HasValue || candidateText != text) {
                    candidate = after; candidateText = text; stableSince = elapsedMilliseconds;
                }
                if (elapsedMilliseconds - stableSince >= 20) {
                    CompletedSequence = after; CompletedText = text;
                    return Observation.Completed;
                }
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
                                      Action<string> trace = null) {
        bool inputFailed = inserted != 4;
        if (inserted < 2) throw new InvalidOperationException(InputBlocked);
        Completion completion = new Completion(initial);
        while (true) {
            uint before = sequence();
            string text;
            try { text = before == initial ? null : readText(); }
            catch (Exception) {
                throw new InvalidOperationException("CLIPBOARD_RESTORE_SKIPPED: Copied text could not be read safely. The original clipboard was not restored over this uncertain update; current contents were preserved.");
            }
            uint after = sequence();
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
                    restore(completion.CompletedSequence);
                    if (inputFailed) throw new InvalidOperationException(InputBlocked);
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
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
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
    static string AutomationSelection() {
        try {
            AutomationElement focused = AutomationElement.FocusedElement;
            if (focused == null) return null;
            // Password controls must never be copied by the fallback.
            if (focused.Current.IsPassword) throw new InvalidOperationException("PROTECTED: Selected text is inside a password control.");
            object pattern;
            if (focused.TryGetCurrentPattern(TextPattern.Pattern, out pattern)) {
                TextPatternRange[] ranges = ((TextPattern)pattern).GetSelection();
                return SelectionCopyPolicy.AutomationText(ranges, delegate(TextPatternRange range) { return range.GetText(-1); });
            }
        } catch (InvalidOperationException error) {
            if (error.Message.StartsWith("PROTECTED:") || error.Message.StartsWith("NO_SELECTION:")) throw;
        } catch (ElementNotAvailableException) { }
        return null;
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
        INPUT input = new INPUT(); input.type = 1;
        input.data.keyboard.vk = code; input.data.keyboard.flags = up ? 2u : 0u;
        return input;
    }
    public static string SelectedText() {
        IntPtr foreground = GetForegroundWindow();
        string direct = AutomationSelection();
        if (GetForegroundWindow() != foreground) throw new InvalidOperationException("SELECTION: Foreground application changed; select text in the source application and retry.");
        if (!String.IsNullOrWhiteSpace(direct)) return direct;
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(1500);
        while (ModifiersDown()) {
            if (DateTime.UtcNow >= deadline) throw new InvalidOperationException("SELECTION: Release the shortcut keys and retry.");
            Thread.Sleep(20);
        }
        if (GetForegroundWindow() != foreground) throw new InvalidOperationException("SELECTION: Foreground application changed; select text in the source application and retry.");
        List<IDisposable> resources = new List<IDisposable>();
        DataObject saved;
        uint initial = GetClipboardSequenceNumber();
        try {
            saved = SnapshotClipboard(resources);
            if (GetClipboardSequenceNumber() != initial) throw new InvalidOperationException("Clipboard changed while its formats were being preserved. Retry.");
        }
        catch (Exception error) {
            foreach (IDisposable resource in resources) resource.Dispose();
            throw new InvalidOperationException("CLIPBOARD: Cannot preserve all clipboard formats. Selection capture was stopped before changing the clipboard. " + error.Message);
        }
        try {
            return SelectionCopyPolicy.RevalidateAndCopy(AutomationSelection,
                delegate {
                    if (GetForegroundWindow() != foreground || ModifiersDown())
                        throw new InvalidOperationException("SELECTION: Foreground application or shortcut modifiers changed before copy; retry.");
                    SelectionCopyPolicy.RequireCurrentSequence(initial, GetClipboardSequenceNumber());
                }, delegate {
                    INPUT[] keys = new INPUT[] { Key(0x11, false), Key(0x43, false), Key(0x43, true), Key(0x11, true) };
                    uint inserted = SendInput((uint)keys.Length, keys, Marshal.SizeOf(typeof(INPUT)));
                    if (inserted != keys.Length) {
                        // Ensure our Ctrl-down cannot leave a modifier stuck.
                        INPUT[] release = new INPUT[] { Key(0x43, true), Key(0x11, true) };
                        SendInput((uint)release.Length, release, Marshal.SizeOf(typeof(INPUT)));
                    }
                    Stopwatch clock = Stopwatch.StartNew();
                    return SelectionCopyPolicy.CompleteCopy(initial, inserted, GetClipboardSequenceNumber,
                        delegate { return Clipboard.ContainsText() ? Clipboard.GetText(TextDataFormat.UnicodeText) : null; },
                        delegate(uint copied) {
                            // Recheck immediately before the restoration write as well
                            // as before invoking this callback; a newer copy wins.
                            SelectionCopyPolicy.RequireCurrentSequence(copied, GetClipboardSequenceNumber());
                            try {
                                if (saved.GetFormats(false).Length == 0) Clipboard.Clear();
                                else Clipboard.SetDataObject(saved, true, 5, 40);
                            } catch (Exception error) {
                                throw new InvalidOperationException("CLIPBOARD_RESTORE_FAILED: Could not restore original clipboard formats. " + error.Message);
                            }
                        }, delegate { return clock.ElapsedMilliseconds; }, delegate { Thread.Sleep(5); },
                        Environment.GetEnvironmentVariable("ECHOLINGO_SELECTION_TRACE") == "1"
                            ? (Action<string>)delegate(string message) { Console.Error.WriteLine(message); } : null);
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
    public static void CaptureRegion(string path) {
        ConfigureDpi();
        try {
            if (GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext()) != 2)
                throw new InvalidOperationException("CAPTURE_DPI: Windows could not establish per-monitor capture coordinates.");
        } catch (EntryPointNotFoundException) {
            throw new InvalidOperationException("CAPTURE_DPI: This Windows version lacks per-monitor capture coordinates.");
        }
        using (RegionPicker picker = new RegionPicker()) {
            Rectangle selected = picker.SelectRegion();
            // Observing display changes continues after selection completion.
            // Validate both sides of BitBlt and discard pixels if the saved
            // physical rectangle no longer belongs to the same configuration.
            if (DwmFlush() < 0) throw new InvalidOperationException("CAPTURE: Windows could not finish removing the selection overlay.");
            picker.ValidateCaptureEnvironment();
            using (Bitmap crop = ScreenBitmap(selected)) {
                picker.ValidateCaptureEnvironment();
                crop.Save(path, ImageFormat.Png);
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
        return new Dictionary<string, object> { { "captureStateFixturePassed", true }, { "fixtureAssertions", 11 + inputAssertions + topologyAssertions }, { "inputPolicyAssertions", inputAssertions }, { "topologyPolicyAssertions", topologyAssertions }, { "releaseGraceMilliseconds", 500 }, { "screenCaptured", false }, { "clipboardChanged", false }, { "interactiveCaptureTested", false } };
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
        return 11;
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

sealed class CaptureOverlay : Form {
    readonly CaptureSelectionState state;
    readonly int index;
    readonly uint expectedDpi;
    readonly Action invalidated;
    static readonly Color ClearKey = Color.FromArgb(255, 0, 255);
    public CaptureOverlay(Rectangle screen, int screenIndex, uint dpi, CaptureSelectionState selection, Action onInvalidated) {
        state = selection; index = screenIndex; expectedDpi = dpi; invalidated = onInvalidated;
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = screen;
        TopMost = true;
        ShowInTaskbar = false;
        BackColor = ClearKey;
        TransparencyKey = ClearKey;
        DoubleBuffered = true;
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
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(ClearKey);
        using (Pen blue = new Pen(Color.FromArgb(45, 145, 255), 2)) {
            if (!state.Finished && state.Highlighted == index && Width > 2 && Height > 2)
                e.Graphics.DrawRectangle(blue, 1, 1, Width - 2, Height - 2);
            if (!state.Finished && state.Selected.Width > 0 && state.Selected.Height > 0) {
                Rectangle local = state.Selected;
                local.Offset(-Left, -Top);
                e.Graphics.DrawRectangle(blue, local);
            }
        }
        base.OnPaint(e);
    }
}

// Transparent color-keyed pixels deliberately do not receive mouse input.
// Short-lived mouse/Escape hooks consume only selection/cancel gestures;
// movement, scrolling and other keys keep their normal behavior. They run on
// this message-pumping helper thread, never injects code into source apps, and
// store no source-window title, pixels, other key events or clipboard content.
// https://learn.microsoft.com/windows/win32/winmsg/lowlevelmouseproc
sealed class RegionPicker : ApplicationContext {
    delegate IntPtr MouseHook(int code, IntPtr message, IntPtr data);
    delegate IntPtr KeyboardHook(int code, IntPtr message, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] struct MouseData { public Point point; public uint mouseData, flags, time; public UIntPtr extra; }
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id, MouseHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll", EntryPoint="SetWindowsHookExW", SetLastError=true)] static extern IntPtr SetKeyboardHook(int id, KeyboardHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll", SetLastError=true)] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out Point point);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string module);
    readonly List<CaptureOverlay> overlays = new List<CaptureOverlay>();
    readonly List<IntPtr> handles = new List<IntPtr>();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly Stopwatch lifetime = new Stopwatch();
    readonly CaptureSelectionState state;
    readonly CaptureInputPolicy input = new CaptureInputPolicy();
    readonly CaptureTopologyPolicy topology;
    readonly MouseHook callback;
    readonly KeyboardHook keyboardCallback;
    IntPtr hook, keyboardHook;
    bool stopping, cleaned, observing;
    int renderedHighlight = -2;
    Rectangle renderedSelection;
    string failure;
    public RegionPicker() {
        Point pointer;
        if (!GetPhysicalCursorPos(out pointer)) throw new InvalidOperationException("CAPTURE: Windows could not read the capture pointer.");
        topology = ReadTopology();
        CaptureDisplaySnapshot[] displays = topology.Displays;
        Rectangle[] rectangles = new Rectangle[displays.Length];
        for (int i = 0; i < displays.Length; i++) rectangles[i] = displays[i].Bounds;
        state = new CaptureSelectionState(rectangles, pointer);
        callback = OnMouse; keyboardCallback = OnKeyboard;
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += DisplaysChanged;
        observing = true;
        for (int i = 0; i < rectangles.Length; i++) overlays.Add(new CaptureOverlay(rectangles[i], i, displays[i].Dpi, state, InvalidateEnvironment));
        timer.Interval = 16;
        timer.Tick += Tick;
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
    public void ValidateCaptureEnvironment() {
        bool valid = !topology.Invalid && topology.Matches(ReadTopology());
        if (!valid || topology.Invalid)
            throw new InvalidOperationException("CAPTURE_DISPLAY_CHANGED: Display geometry or DPI changed; select the region again.");
    }
    public Rectangle SelectRegion() {
        try {
            hook = SetWindowsHookEx(14, callback, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero) throw new InvalidOperationException("CAPTURE_INPUT: Windows could not start region selection.");
            keyboardHook = SetKeyboardHook(13, keyboardCallback, GetModuleHandle(null), 0);
            if (keyboardHook == IntPtr.Zero) throw new InvalidOperationException("CAPTURE_INPUT: Windows could not install Escape cancellation.");
            // Sample after installation so a release in the startup gap cannot
            // leave the session waiting forever. Already swallowed downs are
            // retained by policy; pre-hook downs keep their source-app releases.
            input.ResyncReleasedButtons(Down(0x01), Down(0x02));
            input.ResyncEscape(Down(0x1B));
            if (input.EscapeCancelled) state.Cancel();
            ValidateCaptureEnvironment();
            foreach (CaptureOverlay overlay in overlays) { overlay.Show(); handles.Add(overlay.Handle); }
            lifetime.Start(); timer.Start();
            Application.Run(this);
        } finally { Cleanup(); }
        if (failure != null) throw new InvalidOperationException(failure);
        if (!state.Finished || state.Cancelled || input.EscapeCancelled)
            throw new OperationCanceledException("CANCELLED: Screenshot selection was cancelled (Escape, right click, display change, or 120-second timeout).");
        foreach (IntPtr handle in handles) if (IsWindow(handle)) throw new InvalidOperationException("CAPTURE: A selection overlay could not be removed.");
        return state.Selected;
    }
    IntPtr OnKeyboard(int code, IntPtr message, IntPtr data) {
        if (code != 0) return CallNextHookEx(keyboardHook, code, message, data);
        int kind = message.ToInt32();
        bool down = kind == 0x0100 || kind == 0x0104;
        bool up = kind == 0x0101 || kind == 0x0105;
        if ((!down && !up) || Marshal.ReadInt32(data) != 0x1B)
            return CallNextHookEx(keyboardHook, code, message, data);
        // Read only the Escape discriminator. No other key details are stored,
        // decoded or passed into the session's input policy.
        bool consumed = input.Escape(down, up);
        if (input.EscapeCancelled) state.Cancel();
        return consumed ? new IntPtr(1) : CallNextHookEx(keyboardHook, code, message, data);
    }
    IntPtr OnMouse(int code, IntPtr message, IntPtr data) {
        if (code != 0) return CallNextHookEx(hook, code, message, data);
        int kind = message.ToInt32();
        bool button = kind == 0x0201 || kind == 0x0202 || kind == 0x0204 || kind == 0x0205;
        try {
            Point pointer = ((MouseData)Marshal.PtrToStructure(data, typeof(MouseData))).point;
            if (input.Mouse(kind, pointer, state)) return new IntPtr(1);
        } catch {
            failure = "CAPTURE_INPUT: Region selection could not process pointer input.";
            state.Cancel();
            if (button) return new IntPtr(1);
        }
        return CallNextHookEx(hook, code, message, data);
    }
    void Tick(object sender, EventArgs args) {
        if (!input.Armed) input.ResyncReleasedButtons(Down(0x01), Down(0x02));
        if (input.EscapeCancelled) state.Cancel();
        if (topology.Invalid) {
            failure = "CAPTURE_DISPLAY_CHANGED: Display geometry or DPI changed; select the region again.";
            state.Cancel();
        }
        state.Expire(lifetime.ElapsedMilliseconds);
        if (!state.Finished) {
            Point pointer;
            if (!GetPhysicalCursorPos(out pointer)) { failure = "CAPTURE: Windows could not read the capture pointer."; state.Cancel(); }
            else state.Move(pointer);
        }
        if (state.Finished) {
            if (!stopping) { stopping = true; foreach (CaptureOverlay overlay in overlays) overlay.Hide(); }
            // Keep a short bounded drain for matching mouse/Escape releases.
            if (input.MayStop(true, lifetime.ElapsedMilliseconds)) {
                if (input.ReleaseGraceExceeded)
                    failure = "CAPTURE_INPUT_RELEASE: Selection stopped while a button or Escape was still held. Release it before retrying; no screenshot was taken.";
                ExitThread();
            }
        } else if (renderedHighlight != state.Highlighted || renderedSelection != state.Selected) {
            renderedHighlight = state.Highlighted; renderedSelection = state.Selected;
            foreach (CaptureOverlay overlay in overlays) overlay.Invalidate();
        }
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
        if (hook != IntPtr.Zero) {
            if (!UnhookWindowsHookEx(hook)) failure = "CAPTURE_INPUT: Windows could not stop region selection; no screenshot was taken.";
            hook = IntPtr.Zero;
        }
        if (keyboardHook != IntPtr.Zero) {
            if (!UnhookWindowsHookEx(keyboardHook)) failure = "CAPTURE_INPUT: Windows could not stop Escape cancellation; no screenshot was taken.";
            keyboardHook = IntPtr.Zero;
        }
        foreach (CaptureOverlay overlay in overlays) { overlay.Hide(); overlay.Close(); overlay.Dispose(); }
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
        $remaining = [int][Math]::Max(1, ($script:OcrDeadline - [DateTime]::UtcNow).TotalMilliseconds)
        if (-not $task.Wait($remaining)) {
            try { $Operation.Cancel() } catch { }
            throw 'OCR_TIMEOUT: Local OCR exceeded 30 seconds.'
        }
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
                    $overlap = [Math]::Max(0, [Math]::Min(([double]$previous.X + [double]$previous.Width), ([double]$current.X + [double]$current.Width)) - [Math]::Max([double]$previous.X, [double]$current.X))
                    $columnReset = ($overlap -le (0.1 * [Math]::Min([double]$previous.Width, [double]$current.Width))) -and
                        ([double]$current.Y -lt ([double]$previous.Y - 0.9 * $referenceHeight))
                    $paragraphBreak = ($verticalGap -ge (0.9 * $referenceHeight)) -or $columnReset
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
        if ((Join-OcrLayoutLines $lines) -cne $expected -or (Join-OcrLayoutLines $scaled) -cne $expected -or
            (Join-OcrLayoutLines $lines $false) -cne $flat) {
            throw 'SELF_TEST: Paragraph geometry, scaling, rotation fallback, or original line order was not preserved.'
        }
        $structured = @(
            [pscustomobject]@{ Text = '- first item'; X = 0; Y = 0; Width = 100; Height = 10 }
            [pscustomobject]@{ Text = '  indented continuation'; X = 10; Y = 80; Width = 90; Height = 10 }
            [pscustomobject]@{ Text = '    return value;'; X = 20; Y = 180; Width = 80; Height = 10 }
        )
        if ((Join-OcrLayoutLines $structured) -cne "- first item`n  indented continuation`n    return value;") {
            throw 'SELF_TEST: OCR layout changed a list or indented code line.'
        }
    }
    function Get-OcrText([string]$Path) {
        Initialize-Ocr
        $script:OcrDeadline = [DateTime]::UtcNow.AddSeconds(30)
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        if ($null -eq $engine) {
            $languages = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages)
            if ($languages.Count -gt 0) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($languages[0]) }
        }
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
            $result = Await-WinRt ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
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
            platform = 'windows'; helper = 'windows-powershell-dotnet-winrt'; localOcr = $true
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
                if ($Mode -in 'capture-ocr', 'capture-image') { [EchoLingoNative]::CaptureRegion($path) }
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
