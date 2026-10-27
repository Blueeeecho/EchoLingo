# Explicit Windows desktop fixture: captures only an opaque generated test
# window. No clipboard, translation API, user text, or full-desktop screenshot.
# Run in an unlocked isolated test session; it moves the pointer inside its own
# window and tests the real helper hook/transparent overlays via SendInput.
[CmdletBinding()]
param([string]$HelperPath = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) {
        throw 'DESKTOP_UNAVAILABLE: This test requires an unlocked interactive Windows test session.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw 'TEST_APARTMENT: Run powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-live-capture-smoke.ps1.'
    }
    if ([string]::IsNullOrWhiteSpace($HelperPath)) { $HelperPath = Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1' }
    $HelperPath = (Resolve-Path -LiteralPath $HelperPath).Path
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web.Extensions
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class EchoLingoLiveCaptureSmoke {
    sealed class PassiveGeneratedLayer : Form {
        public PassiveGeneratedLayer() {
            AutoScaleMode = AutoScaleMode.None; FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual; ShowInTaskbar = false; TopMost = true;
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams { get { CreateParams value = base.CreateParams; value.ExStyle |= 0x08000000 | 0x00000080; return value; } }
        protected override void WndProc(ref Message message) {
            if (message.Msg == 0x0021) { message.Result = new IntPtr(3); return; } // MA_NOACTIVATE, matching production edges.
            base.WndProc(ref message);
        }
    }
    sealed class EscapeFilter : IMessageFilter {
        public int Count;
        public bool PreFilterMessage(ref Message message) {
            if ((message.Msg == 0x0100 || message.Msg == 0x0101 || message.Msg == 0x0104 || message.Msg == 0x0105) && message.WParam.ToInt32() == 0x1B) Count++;
            return false;
        }
    }
    delegate bool EnumWindow(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr parent, Point point, uint flags);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT rectangle);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window, uint attribute, out RECT rectangle, int size);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out Point point);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion data; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mouse;
        [FieldOffset(0)] public KEYBDINPUT keyboard;
    }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left, top, right, bottom; }

    static void Assert(bool condition, string message) { if (!condition) throw new InvalidOperationException("ASSERTION_FAILED: " + message); }
    static void OnUi(Form form, Action action) { form.Invoke(action); }
    sealed class TrialContext {
        public readonly Form Source;
        public string Mode = "setup", Stage = "setup";
        public int HelperProcessId;
        public IntPtr GeneratedLayerHwnd;
        public Dictionary<string, object> ForegroundFailure;
        public Dictionary<string, object> LastEdges;
        public Dictionary<string, object> HoverTrial;
        public TrialContext(Form source) { Source = source; }
    }
    static string WindowId(IntPtr window) { return "0x" + window.ToInt64().ToString("X"); }
    static Dictionary<string, object> ForegroundMetadata(TrialContext context, IntPtr foreground) {
        uint process = 0; GetWindowThreadProcessId(foreground, out process);
        int fixtureProcess = Process.GetCurrentProcess().Id;
        StringBuilder className = new StringBuilder(256);
        if (foreground != IntPtr.Zero) GetClassName(foreground, className, className.Capacity);
        return new Dictionary<string, object> {
            { "mode", context.Mode }, { "stage", context.Stage },
            { "foregroundHwnd", WindowId(foreground) }, { "foregroundProcessId", process },
            { "foregroundClass", className.ToString() },
            { "fixtureHwnd", WindowId(context.Source.Handle) }, { "fixtureProcessId", fixtureProcess },
            { "helperProcessId", context.HelperProcessId },
            { "generatedLayerHwnd", WindowId(context.GeneratedLayerHwnd) },
            { "isGeneratedLayer", foreground == context.GeneratedLayerHwnd && context.GeneratedLayerHwnd != IntPtr.Zero },
            { "isFixtureWindow", foreground == context.Source.Handle },
            { "isFixtureProcess", process == fixtureProcess },
            { "isHelperProcess", context.HelperProcessId != 0 && process == context.HelperProcessId }
        };
    }
    static void RequireFixtureForeground(TrialContext context, string stage) {
        context.Stage = stage;
        IntPtr foreground = GetForegroundWindow();
        if (foreground == context.Source.Handle) return;
        context.ForegroundFailure = ForegroundMetadata(context, foreground);
        Assert(false, "Dedicated test window lost foreground at " + context.Mode + "/" + stage + "; no input will be sent to another app.");
    }
    static void Send(TrialContext context, string stage, INPUT input) {
        RequireFixtureForeground(context, stage);
        Assert(SendInput(1, new INPUT[] { input }, Marshal.SizeOf(typeof(INPUT))) == 1, "Windows rejected dedicated fixture input.");
    }
    static void Move(TrialContext context, string stage, Point point) {
        Rectangle desktop = SystemInformation.VirtualScreen;
        INPUT input = new INPUT();
        input.data.mouse.dx = (int)Math.Round((point.X - desktop.Left) * 65535.0 / (desktop.Width - 1));
        input.data.mouse.dy = (int)Math.Round((point.Y - desktop.Top) * 65535.0 / (desktop.Height - 1));
        input.data.mouse.flags = 0x8000 | 0x4000 | 0x0001;
        Send(context, stage, input);
    }
    static void Button(TrialContext context, string stage, uint flags) { INPUT input = new INPUT(); input.data.mouse.flags = flags; Send(context, stage, input); }
    sealed class EdgeWindow {
        public IntPtr Handle;
        public Rectangle Bounds;
    }
    static Rectangle Frame(IntPtr window) {
        RECT value;
        Assert(DwmGetWindowAttribute(window, 9, out value, Marshal.SizeOf(typeof(RECT))) == 0,
            "DWM could not independently measure the generated window's physical frame.");
        Assert(value.right > value.left && value.bottom > value.top, "Generated DWM frame is empty.");
        return Rectangle.FromLTRB(value.left, value.top, value.right, value.bottom);
    }
    static int[] RectValue(Rectangle value) { return new int[] { value.Left, value.Top, value.Width, value.Height }; }
    static List<Rectangle> Perimeter(Rectangle frame, Rectangle display) {
        List<Rectangle> result = new List<Rectangle>();
        if (frame.Width <= 0 || frame.Height <= 0) return result;
        // Independently expected two-pixel perimeter. Hover uses the DWM frame
        // directly; only a free selection is inflated by one pixel at its caller.
        int horizontal = Math.Min(2, frame.Height), vertical = Math.Min(2, frame.Width);
        foreach (Rectangle edge in new Rectangle[] {
            new Rectangle(frame.Left, frame.Top, frame.Width, horizontal),
            new Rectangle(frame.Left, frame.Bottom - horizontal, frame.Width, horizontal),
            new Rectangle(frame.Left, frame.Top + horizontal, vertical, Math.Max(0, frame.Height - horizontal * 2)),
            new Rectangle(frame.Right - vertical, frame.Top + horizontal, vertical, Math.Max(0, frame.Height - horizontal * 2))
        }) {
            Rectangle clipped = Rectangle.Intersect(edge, display);
            if (clipped.Width > 0 && clipped.Height > 0) result.Add(clipped);
        }
        return result;
    }
    static List<EdgeWindow> VisibleEdges(int processId) {
        List<EdgeWindow> result = new List<EdgeWindow>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner != processId || !IsWindowVisible(window)) return true;
            long style = GetWindowLongPtr(window, -20).ToInt64();
            long required = 0x08000000L | 0x00080000L | 0x00000020L | 0x00000008L;
            Assert((style & required) == required, "Capture overlay lacks layered/transparent/no-activate/topmost styles.");
            RECT value; Assert(GetWindowRect(window, out value), "Cannot inspect capture border geometry.");
            Rectangle bounds = Rectangle.FromLTRB(value.left, value.top, value.right, value.bottom);
            Assert(bounds.Width > 0 && bounds.Height > 0 && Math.Min(bounds.Width, bounds.Height) <= 2,
                "Selector unexpectedly created a large surface instead of a thin edge window.");
            result.Add(new EdgeWindow { Handle = window, Bounds = bounds });
            return true;
        }, IntPtr.Zero);
        return result;
    }
    static bool Matches(List<EdgeWindow> windows, List<Rectangle> expected) {
        if (windows.Count != expected.Count) return false;
        List<Rectangle> remaining = new List<Rectangle>(expected);
        foreach (EdgeWindow window in windows) {
            int index = remaining.IndexOf(window.Bounds);
            if (index < 0) return false;
            remaining.RemoveAt(index);
        }
        return remaining.Count == 0;
    }
    static List<IntPtr> RoleHandles(List<EdgeWindow> windows, List<Rectangle> expected) {
        List<EdgeWindow> remaining = new List<EdgeWindow>(windows);
        List<IntPtr> result = new List<IntPtr>();
        foreach (Rectangle edge in expected) {
            int index = remaining.FindIndex(delegate(EdgeWindow window) { return window.Bounds == edge; });
            Assert(index >= 0, "Expected role perimeter is missing a real HWND.");
            result.Add(remaining[index].Handle); remaining.RemoveAt(index);
        }
        return result;
    }
    static Dictionary<string, object> EdgeMetadata(TrialContext context, List<EdgeWindow> windows, string stage, double elapsed) {
        List<Dictionary<string, object>> values = new List<Dictionary<string, object>>();
        foreach (EdgeWindow window in windows) values.Add(new Dictionary<string, object> {
            { "hwnd", WindowId(window.Handle) }, { "bounds", RectValue(window.Bounds) }
        });
        return new Dictionary<string, object> {
            { "stage", stage }, { "helperProcessId", context.HelperProcessId },
            { "visibleCount", windows.Count }, { "edges", values },
            { "thinEdgeStylesVerified", true },
            { "foregroundHwnd", WindowId(GetForegroundWindow()) }, { "settlementObservedMilliseconds", elapsed }
        };
    }
    static List<EdgeWindow> WaitEdges(TrialContext context, Process process, Rectangle display, Rectangle hover,
        Rectangle selection, string stage, int budget) {
        context.Stage = stage;
        List<Rectangle> expected = Perimeter(display, display);
        expected.AddRange(Perimeter(hover, display)); expected.AddRange(Perimeter(selection, display));
        Stopwatch elapsed = Stopwatch.StartNew(); List<EdgeWindow> actual;
        do {
            RequireFixtureForeground(context, stage);
            actual = VisibleEdges(process.Id);
            context.LastEdges = EdgeMetadata(context, actual, stage, elapsed.Elapsed.TotalMilliseconds);
            if (!process.HasExited && Matches(actual, expected)) return actual;
            if (process.HasExited) break;
            Thread.Sleep(20);
        } while (elapsed.ElapsedMilliseconds < budget);
        Assert(false, "Expected screen/hover/selection physical edge composition did not settle at " + stage + ".");
        return actual;
    }
    static void MoveAndSettle(TrialContext context, string stage, Point point) {
        Move(context, stage, point);
        Stopwatch elapsed = Stopwatch.StartNew(); Point actual;
        while ((!GetPhysicalCursorPos(out actual) || actual != point) && elapsed.ElapsedMilliseconds < 1500) Thread.Sleep(10);
        Assert(GetPhysicalCursorPos(out actual) && actual == point, "Generated pointer did not reach its physical target.");
        RequireFixtureForeground(context, stage);
    }
    static IntPtr RequireGeneratedTarget(Point point, IntPtr first, IntPtr second) {
        IntPtr root = GetAncestor(WindowFromPoint(point), 2); uint owner;
        GetWindowThreadProcessId(root, out owner);
        Assert((root == first || (second != IntPtr.Zero && root == second)) && owner == Process.GetCurrentProcess().Id,
            "Pointer target is not the exact generated source/layer; no fixture input will target another app.");
        return root;
    }
    static long BorderArea(int processId, out int total, out long largest) {
        int count = 0; long area = 0, maximum = 0;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == processId && IsWindowVisible(window)) {
                long style = GetWindowLongPtr(window, -20).ToInt64();
                long required = 0x08000000L | 0x00080000L | 0x00000020L | 0x00000008L;
                Assert((style & required) == required, "Capture overlay lacks layered/transparent/no-activate/topmost styles.");
                RECT bounds; Assert(GetWindowRect(window, out bounds), "Cannot inspect capture border geometry.");
                int width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
                Assert(width > 0 && height > 0 && Math.Min(width, height) <= 2, "Selector unexpectedly created a full-screen surface instead of a thin edge window.");
                long pixels = (long)width * height; area += pixels; maximum = Math.Max(maximum, pixels);
                count++;
            }
            return true;
        }, IntPtr.Zero);
        total = count; largest = maximum; return area;
    }
    static int ReadyOverlays(int processId) {
        int count; long largest; BorderArea(processId, out count, out largest); return count;
    }
    static bool BordersAboveSource(int processId, IntPtr source, int expectedCount) {
        int borders = 0, steps = 0;
        for (IntPtr window = GetWindow(source, 3); window != IntPtr.Zero && steps++ < 4096; window = GetWindow(window, 3)) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == processId && IsWindowVisible(window)) borders++;
        }
        return borders == expectedCount;
    }
    static bool SelectionEdgeAt(int processId, Point origin, Point end) {
        bool found = false;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner); RECT bounds;
            if (owner == processId && IsWindowVisible(window) && GetWindowRect(window, out bounds)
                && bounds.left == origin.X - 1 && bounds.top == end.Y - 1
                && bounds.right == end.X + 1 && bounds.bottom == end.Y + 1) found = true;
            return !found;
        }, IntPtr.Zero);
        return found;
    }
    static bool ShellClass(string name) {
        return name == "Progman" || name == "WorkerW" || name == "Shell_TrayWnd" || name == "Shell_SecondaryTrayWnd";
    }
    static Dictionary<string, object> ShellAt(Point point, IntPtr expected) {
        IntPtr hit = WindowFromPoint(point), root = GetAncestor(hit, 2); uint owner;
        GetWindowThreadProcessId(root, out owner);
        StringBuilder name = new StringBuilder(256); GetClassName(root, name, name.Capacity);
        if (root == IntPtr.Zero || (expected != IntPtr.Zero && root != expected) || owner == 0
            || owner == Process.GetCurrentProcess().Id || !IsWindowVisible(root) || !ShellClass(name.ToString())) return null;
        return new Dictionary<string, object> {
            { "hitHwnd", WindowId(hit) }, { "rootHwnd", WindowId(root) }, { "processId", owner },
            { "rootClass", name.ToString() }, { "pointerPhysicalXY", new int[] { point.X, point.Y } },
            { "scope", name.ToString().StartsWith("Shell_", StringComparison.Ordinal) ? "visible-shell-taskbar" : "visible-desktop-shell" }
        };
    }
    static Point FindVisibleShellPoint(Rectangle display) {
        List<Rectangle> candidates = new List<Rectangle>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            if (candidates.Count >= 16 || !IsWindowVisible(window)) return true;
            StringBuilder name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
            RECT value;
            if (ShellClass(name.ToString()) && GetWindowRect(window, out value)) {
                Rectangle bounds = Rectangle.Intersect(display, Rectangle.FromLTRB(value.left, value.top, value.right, value.bottom));
                if (bounds.Width > 16 && bounds.Height > 16) candidates.Add(bounds);
            }
            return true;
        }, IntPtr.Zero);
        foreach (Rectangle bounds in candidates) {
            foreach (int x in new int[] { bounds.Left + 8, bounds.Left + bounds.Width / 2, bounds.Right - 9 })
            foreach (int y in new int[] { bounds.Top + 8, bounds.Top + bounds.Height / 2, bounds.Bottom - 9 }) {
                Point point = new Point(x, y);
                if (ShellAt(point, IntPtr.Zero) != null) return point;
            }
        }
        throw new InvalidOperationException("SHELL_TARGET_UNAVAILABLE: No actually visible desktop/shell point was found; fallback was not executed. Foreign windows were not moved or hidden.");
    }
    static List<EdgeWindow> ObserveHoverPhase(TrialContext context, Process process, Rectangle display, Rectangle hover,
        Rectangle selection, string stage, int budget, List<Dictionary<string, object>> observations, HashSet<IntPtr> known) {
        List<EdgeWindow> windows = WaitEdges(context, process, display, hover, selection, stage, budget);
        foreach (EdgeWindow window in windows) known.Add(window.Handle);
        Assert(known.Count <= 12, "Active-display edge HWNDs accumulated beyond the three four-edge groups.");
        Dictionary<string, object> value = context.LastEdges;
        value["expectedScreenBounds"] = RectValue(display); value["expectedHoverBounds"] = RectValue(hover);
        value["expectedSelectionOutlineBounds"] = RectValue(selection);
        Point pointer; Assert(GetPhysicalCursorPos(out pointer), "Cannot observe the generated pointer.");
        value["pointerPhysicalXY"] = new int[] { pointer.X, pointer.Y };
        value["observedUniqueEdgeHwndCount"] = known.Count;
        observations.Add(value);
        return windows;
    }
    static void RequireHidden(List<IntPtr> windows, string message) {
        foreach (IntPtr window in windows) Assert(IsWindow(window) && !IsWindowVisible(window), message);
    }
    static bool SameHandles(List<IntPtr> first, List<IntPtr> second) {
        return first.Count == second.Count && new HashSet<IntPtr>(first).SetEquals(second);
    }
    static string[] HandleValues(List<IntPtr> windows) {
        List<string> result = new List<string>(); foreach (IntPtr window in windows) result.Add(WindowId(window));
        return result.ToArray();
    }
    static void ObserveDisabledOcclusion(TrialContext context, Process process, Rectangle display, Rectangle aFrame,
        Rectangle bFrame, Dictionary<string, object> metrics, List<Dictionary<string, object>> observations) {
        string stage = "disabled-B-occlusion"; context.Stage = stage;
        List<Rectangle> screen = Perimeter(display, display), above = new List<Rectangle>(screen), below = new List<Rectangle>(screen);
        above.AddRange(Perimeter(bFrame, display)); below.AddRange(Perimeter(aFrame, display));
        Stopwatch elapsed = Stopwatch.StartNew(); double stableSince = -1; string outcome = null;
        do {
            RequireFixtureForeground(context, stage);
            List<EdgeWindow> edges = VisibleEdges(process.Id);
            context.LastEdges = EdgeMetadata(context, edges, stage, elapsed.Elapsed.TotalMilliseconds);
            Assert(!Matches(edges, below), "Disabled B is still visibly above A, but the helper hinted the obscured underlying A.");
            string current = Matches(edges, above) ? "correct-disabled-B-frame" : (Matches(edges, screen) ? "conservative-screen-fallback" : null);
            if (current == null) stableSince = -1;
            else {
                if (stableSince < 0) stableSince = elapsed.Elapsed.TotalMilliseconds;
                outcome = current;
                // Observe more than four80ms metadata intervals; a single
                // pre-query frame cannot accidentally satisfy this case.
                if (elapsed.ElapsedMilliseconds >= 400 && elapsed.Elapsed.TotalMilliseconds - stableSince >= 150) {
                    context.LastEdges["disabledOcclusionOutcome"] = outcome; observations.Add(context.LastEdges);
                    metrics["disabledBOcclusionPassed"] = true;
                    metrics["disabledBOcclusionOutcome"] = outcome;
                    metrics["disabledBOcclusionObservedMilliseconds"] = elapsed.Elapsed.TotalMilliseconds;
                    return;
                }
            }
            Thread.Sleep(20);
        } while (elapsed.ElapsedMilliseconds < 1500);
        Assert(false, "Disabled-window hover did not settle to B or safe screen fallback; disabled case unproven.");
    }
    static Dictionary<string, object> HoverTrial(TrialContext context, string helper) {
        Form form = context.Source; Form layer = null; int layerButtons = 0; bool leftHeld = false;
        context.Mode = "hover-window-follow"; context.Stage = "prepare-two-generated-windows";
        context.HelperProcessId = 0; context.ForegroundFailure = null; context.LastEdges = null;
        Dictionary<string, object> metrics = new Dictionary<string, object> { { "mode", context.Mode }, { "passed", false } };
        Stopwatch trialElapsed = Stopwatch.StartNew();
        metrics["readinessBudgetMilliseconds"] = 25000; metrics["hoverSettlementBudgetMilliseconds"] = 1500;
        metrics["disabledObservationMinimumMilliseconds"] = 400; metrics["completionBudgetMilliseconds"] = 10000;
        context.HoverTrial = metrics;
        List<Dictionary<string, object>> observations = new List<Dictionary<string, object>>(); metrics["observations"] = observations;
        HashSet<IntPtr> known = new HashSet<IntPtr>();
        Rectangle display = Rectangle.Empty, aClient = Rectangle.Empty, bClient = Rectangle.Empty;
        Point aPoint = Point.Empty, bPoint = Point.Empty;
        try {
            OnUi(form, delegate {
                Rectangle work = Screen.FromControl(form).WorkingArea; display = Screen.FromControl(form).Bounds;
                Assert(work.Width >= 900 && work.Height >= 600, "Two-window hover fixture needs at least900x600 work area.");
                form.FormBorderStyle = FormBorderStyle.None;
                form.Bounds = new Rectangle(work.Left + 40, work.Top + 50, work.Width - 220, work.Height - 130);
                form.BackColor = Color.FromArgb(50, 210, 110); form.Refresh();
                layer = new PassiveGeneratedLayer();
                layer.Bounds = new Rectangle(form.Left + 170, form.Top + 100, 240, 160);
                layer.BackColor = Color.FromArgb(180, 130, 60);
                layer.MouseDown += delegate { layerButtons++; }; layer.MouseUp += delegate { layerButtons++; };
                layer.Show(); context.GeneratedLayerHwnd = layer.Handle;
                // Complete all Form.Show/activation setup before product hooks.
                form.Activate(); Assert(SetForegroundWindow(form.Handle), "Generated A could not gain foreground before helper startup.");
                aClient = form.RectangleToScreen(form.ClientRectangle); bClient = layer.RectangleToScreen(layer.ClientRectangle);
                aPoint = new Point(aClient.Left + 40, aClient.Top + 40);
                bPoint = new Point(bClient.Left + 40, bClient.Top + 40);
            });
            Rectangle aFrame = Frame(form.Handle), bFrame = Frame(layer.Handle);
            Assert(display.Contains(aFrame) && aClient.Contains(bFrame), "Generated windows must lie wholly inside one display/opaque A client.");
            metrics["sourceHwnd"] = WindowId(form.Handle); metrics["generatedLayerHwnd"] = WindowId(layer.Handle);
            metrics["sourceProcessId"] = Process.GetCurrentProcess().Id;
            metrics["aPhysicalDwmBounds"] = RectValue(aFrame); metrics["bPhysicalDwmBounds"] = RectValue(bFrame);
            MoveAndSettle(context, "prepare-pointer-A-before-helper", aPoint);
            RequireGeneratedTarget(aPoint, form.Handle, IntPtr.Zero);
            ProcessStartInfo start = new ProcessStartInfo("powershell.exe");
            start.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + helper + "\" -Mode capture-image";
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
            using (Process process = Process.Start(start)) {
                context.HelperProcessId = process.Id; metrics["helperProcessId"] = process.Id;
                Task<string> output = process.StandardOutput.ReadToEndAsync(), error = process.StandardError.ReadToEndAsync();
                try {
                    List<EdgeWindow> atA = ObserveHoverPhase(context, process, display, aFrame, Rectangle.Empty,
                        "hover-A", 25000, observations, known);
                    List<IntPtr> screenHandles = RoleHandles(atA, Perimeter(display, display));
                    List<IntPtr> hoverHandles = RoleHandles(atA, Perimeter(aFrame, display));
                    MoveAndSettle(context, "move-to-generated-B", bPoint); RequireGeneratedTarget(bPoint, layer.Handle, IntPtr.Zero);
                    List<EdgeWindow> atB = ObserveHoverPhase(context, process, display, bFrame, Rectangle.Empty,
                        "hover-B", 1500, observations, known);
                    Assert(SameHandles(hoverHandles, RoleHandles(atB, Perimeter(bFrame, display)))
                        && SameHandles(screenHandles, RoleHandles(atB, Perimeter(display, display))), "Hover A->B did not reuse the exact role HWNDs.");
                    metrics["hoverFollowsGeneratedWindowsObserved"] = true;
                    RequireFixtureForeground(context, "before-disable-generated-B");
                    OnUi(form, delegate { layer.Enabled = false; });
                    RequireFixtureForeground(context, "after-disable-generated-B");
                    Assert(!IsWindowEnabled(layer.Handle) && IsWindowVisible(layer.Handle), "Generated B did not become a visible disabled native window.");
                    Point desktopPoint = bPoint; IntPtr desktop = GetDesktopWindow();
                    Assert(desktop != IntPtr.Zero && ScreenToClient(desktop, ref desktopPoint), "Cannot map generated occlusion point to desktop client coordinates.");
                    IntPtr occluding = GetAncestor(ChildWindowFromPointEx(desktop, desktopPoint, 0x1 | 0x4), 2);
                    Assert(occluding == layer.Handle, "Disabled B is not independently observed as the actual opaque topmost occluder.");
                    metrics["disabledBActualOccluderHwnd"] = WindowId(occluding);
                    ObserveDisabledOcclusion(context, process, display, aFrame, bFrame, metrics, observations);
                    OnUi(form, delegate { layer.Enabled = true; });
                    RequireFixtureForeground(context, "after-enable-generated-B");
                    Assert(IsWindowEnabled(layer.Handle), "Generated B did not return to enabled state.");
                    ObserveHoverPhase(context, process, display, bFrame, Rectangle.Empty,
                        "enabled-B-after-disabled-occlusion", 1500, observations, known);
                    context.Stage = "find-actually-visible-shell-point";
                    Point shellPoint = FindVisibleShellPoint(display);
                    Dictionary<string, object> shell = ShellAt(shellPoint, IntPtr.Zero);
                    Assert(shell != null, "Visible shell target changed before fallback move.");
                    MoveAndSettle(context, "move-to-guarded-visible-shell", shellPoint);
                    Assert(ShellAt(shellPoint, new IntPtr(Convert.ToInt64(((string)shell["rootHwnd"]).Substring(2), 16))) != null,
                        "Actual pointer root is no longer the guarded system shell.");
                    ObserveHoverPhase(context, process, display, Rectangle.Empty, Rectangle.Empty,
                        "desktop-or-shell-fallback", 1500, observations, known);
                    RequireHidden(hoverHandles, "Hover HWND remained visible on actual shell fallback.");
                    metrics["shellFallbackTarget"] = shell; metrics["hoverDesktopOrShellFallbackPassed"] = true;
                    MoveAndSettle(context, "return-to-generated-B", bPoint); RequireGeneratedTarget(bPoint, layer.Handle, IntPtr.Zero);
                    List<EdgeWindow> returned = ObserveHoverPhase(context, process, display, bFrame, Rectangle.Empty,
                        "hover-B-again", 1500, observations, known);
                    Assert(SameHandles(hoverHandles, RoleHandles(returned, Perimeter(bFrame, display))), "Hover did not return using its original HWND group.");
                    Color aColor = Color.FromArgb(220, 70, 85), bColor = Color.FromArgb(165, 120, 45);
                    OnUi(form, delegate { form.BackColor = aColor; form.Refresh(); layer.BackColor = bColor; layer.Refresh(); });
                    Thread.Sleep(150);
                    Point end = new Point(bClient.Right + 120, bClient.Bottom + 100);
                    Assert(aClient.Contains(end), "Free-drag destination is outside generated opaque A.");
                    Button(context, "hover-free-drag-left-down", 0x0002); leftHeld = true; Thread.Sleep(80);
                    MoveAndSettle(context, "hover-free-drag-move", end);
                    Rectangle crop = Rectangle.FromLTRB(bPoint.X, bPoint.Y, end.X, end.Y), outline = crop; outline.Inflate(1, 1);
                    List<EdgeWindow> dragging = ObserveHoverPhase(context, process, display, Rectangle.Empty, outline,
                        "held-drag-hover-hidden", 1500, observations, known);
                    RequireHidden(hoverHandles, "Hover HWND must be allocated but hidden while left drag is still held.");
                    List<IntPtr> selectionHandles = RoleHandles(dragging, Perimeter(outline, display));
                    HashSet<IntPtr> groups = new HashSet<IntPtr>(screenHandles); groups.UnionWith(hoverHandles); groups.UnionWith(selectionHandles);
                    Assert(groups.Count == 12 && known.SetEquals(groups), "Screen/hover/selection must use three distinct four-HWND groups.");
                    foreach (IntPtr edge in groups) Assert(IsWindow(edge), "An allocated edge disappeared before capture release.");
                    metrics["screenEdgeHwnds"] = HandleValues(screenHandles); metrics["hoverEdgeHwnds"] = HandleValues(hoverHandles);
                    metrics["selectionEdgeHwnds"] = HandleValues(selectionHandles);
                    metrics["roleHwndSetsDistinct"] = true;
                    metrics["observedAllocatedEdgeWindowCount"] = groups.Count; metrics["hoverHiddenWhileLeftHeldPassed"] = true;
                    metrics["freeDragPhysicalRectangle"] = RectValue(crop);
                    Button(context, "hover-free-drag-left-up", 0x0004); leftHeld = false;
                    context.Stage = "wait-hover-free-capture-exit";
                    Assert(process.WaitForExit(10000), "Hover free-drag helper did not finish.");
                    JavaScriptSerializer json = new JavaScriptSerializer(); json.MaxJsonLength = 16 * 1024 * 1024;
                    Dictionary<string, object> reply = json.Deserialize<Dictionary<string, object>>(output.GetAwaiter().GetResult());
                    Assert(process.ExitCode == 0 && (bool)reply["ok"], "Hover free-drag capture failed.");
                    using (MemoryStream bytes = new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))
                    using (Bitmap image = new Bitmap(bytes)) {
                        Assert(image.Width == crop.Width && image.Height == crop.Height, "Hover snapped capture to a window instead of the free physical region.");
                        Point[] probes = new Point[] { bPoint, new Point(end.X - 1, end.Y - 1),
                            new Point(crop.Left + crop.Width / 2, crop.Top + crop.Height / 2),
                            new Point(bFrame.Right - 1, bPoint.Y + 20), new Point(bFrame.Right, bPoint.Y + 20),
                            new Point(bPoint.X + 20, bFrame.Bottom - 1), new Point(bPoint.X + 20, bFrame.Bottom) };
                        List<Dictionary<string, object>> pixelResults = new List<Dictionary<string, object>>();
                        foreach (Point point in probes) {
                            Assert(crop.Contains(point) && aClient.Contains(point), "Former-hover-border probe left the generated crop.");
                            Color expected = bClient.Contains(point) ? bColor : aColor;
                            Color actual = image.GetPixel(point.X - crop.Left, point.Y - crop.Top);
                            pixelResults.Add(new Dictionary<string, object> {
                                { "screenPhysicalXY", new int[] { point.X, point.Y } },
                                { "expectedRgb", new int[] { expected.R, expected.G, expected.B } },
                                { "actualRgb", new int[] { actual.R, actual.G, actual.B } }
                            });
                            Assert(Math.Abs(actual.R - expected.R) <= 2 && Math.Abs(actual.G - expected.G) <= 2 && Math.Abs(actual.B - expected.B) <= 2,
                                "Free capture froze old content or retained hover/selection blue pixels at a generated composite probe.");
                        }
                        metrics["generatedCompositePixelProbeCount"] = probes.Length;
                        metrics["generatedCompositePixelProbes"] = pixelResults;
                    }
                    RequireFixtureForeground(context, "hover-capture-complete");
                    OnUi(form, delegate { Assert(layerButtons == 0, "Selection button input reached generated B."); });
                    foreach (IntPtr edge in groups) Assert(!IsWindow(edge), "An observed edge HWND survived helper exit.");
                    Assert(ReadyOverlays(process.Id) == 0, "Hover capture left visible border HWNDs.");
                    metrics["hoverOverlayAbsentInCapturePassed"] = true; metrics["freeRegionCapturePassed"] = true;
                    metrics["foregroundPreserved"] = true; metrics["passed"] = true;
                    return metrics;
                } finally {
                    if (leftHeld && !process.HasExited && GetForegroundWindow() == form.Handle) {
                        Button(context, "cleanup-own-held-left-up", 0x0004); leftHeld = false;
                    }
                    if (!process.HasExited) { process.Kill(); process.WaitForExit(3000); }
                }
            }
        } finally {
            metrics["trialElapsedMilliseconds"] = trialElapsed.Elapsed.TotalMilliseconds;
            if (layer != null) OnUi(form, delegate { layer.Close(); layer.Dispose(); });
        }
    }
    static Dictionary<string, object> Trial(TrialContext context, string helper, string mode, Color liveColor) {
        Form form = context.Source;
        context.Mode = mode; context.Stage = "prepare-generated-source"; context.HelperProcessId = 0; context.ForegroundFailure = null;
        context.LastEdges = null;
        context.GeneratedLayerHwnd = IntPtr.Zero;
        Form layer = null; int layerMouseEvents = 0;
        Rectangle display = Rectangle.Empty, hoverFrame = Rectangle.Empty;
        Point preparedPointer = Point.Empty;
        try {
            if (mode == "topmost-capture") {
                OnUi(form, delegate {
                    // WinForms can activate another fixture HWND while showing
                    // a no-activate Form. Finish that setup BEFORE the product
                    // starts, then establish the exact source foreground once.
                    layer = new PassiveGeneratedLayer(); layer.Bounds = Screen.FromControl(form).Bounds;
                    layer.BackColor = Color.FromArgb(60, 170, 220);
                    layer.MouseDown += delegate { layerMouseEvents++; }; layer.MouseUp += delegate { layerMouseEvents++; };
                    layer.Show(); context.GeneratedLayerHwnd = layer.Handle;
                    form.Activate();
                    Assert(SetForegroundWindow(form.Handle), "Generated source could not gain foreground during pre-helper setup.");
                });
            }
            RequireFixtureForeground(context, "generated-source-prepared-before-helper");
            OnUi(form, delegate {
                display = Screen.FromControl(form).Bounds;
                preparedPointer = form.PointToScreen(new Point(50, 50));
            });
            MoveAndSettle(context, "prepare-generated-pointer-before-helper", preparedPointer);
            IntPtr hoverTarget = RequireGeneratedTarget(preparedPointer, form.Handle, context.GeneratedLayerHwnd);
            hoverFrame = Frame(hoverTarget);
            context.Stage = "start-helper";
            ProcessStartInfo start = new ProcessStartInfo("powershell.exe");
            start.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + helper + "\" -Mode capture-image";
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
            using (Process process = Process.Start(start)) {
                context.HelperProcessId = process.Id;
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                Dictionary<string, object> metrics = new Dictionary<string, object>();
                bool capture = mode == "capture" || mode == "capture-burst" || mode == "topmost-capture";
                try {
                    context.Stage = "wait-ready-overlays";
                    // Both the pointer display and eligible generated window
                    // have exact four-edge perimeters. A bare count of4/8 is
                    // insufficient: the actual physical geometries must match.
                    WaitEdges(context, process, display, hoverFrame, Rectangle.Empty, "wait-ready-overlays", 25000);
                    context.Stage = "inspect-ready-overlays";
                    int readyCount; long readyLargest;
                    metrics["readyVisibleBorderAreaPixels"] = BorderArea(process.Id, out readyCount, out readyLargest);
                    metrics["readyVisibleBorderWindowCount"] = readyCount; metrics["readyLargestSurfacePixels"] = readyLargest;
                    metrics["readyScreenEdgeCount"] = 4; metrics["readyHoverEdgeCount"] = 4;
                    metrics["readyHoverTargetHwnd"] = WindowId(hoverTarget); metrics["readyHoverPhysicalBounds"] = RectValue(hoverFrame);
                    RequireFixtureForeground(context, "selector-ready");
                    if (mode == "topmost-capture") {
                        context.Stage = "raise-existing-generated-topmost-layer";
                        OnUi(form, delegate {
                            // Reorder an already-visible ordinary topmost source
                            // after picker readiness. No Form.Show/focus operation
                            // is allowed during the actual passive-capture test.
                            Assert(SetWindowPos(layer.Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0010 | 0x0001 | 0x0002), "Cannot position the dedicated ordinary topmost source.");
                        });
                        uint layerOwner; GetWindowThreadProcessId(layer.Handle, out layerOwner);
                        Assert(layerOwner == Process.GetCurrentProcess().Id, "Generated topmost HWND is not fixture-owned.");
                        metrics["generatedLayerHwnd"] = WindowId(layer.Handle); metrics["generatedLayerProcessId"] = layerOwner;
                        metrics["generatedLayerShownBeforeHelper"] = true;
                        metrics["generatedLayerRaisedWithoutActivationAfterPicker"] = true;
                        metrics["generatedForegroundPixelRgb"] = new int[] { 25, 45, 70 };
                        metrics["generatedLayerInitialPixelRgb"] = new int[] { 60, 170, 220 };
                        context.Stage = "wait-borders-above-generated-topmost-layer";
                        DateTime raisedDeadline = DateTime.UtcNow.AddSeconds(3);
                        while (!BordersAboveSource(process.Id, layer.Handle, 8) && DateTime.UtcNow < raisedDeadline) Thread.Sleep(20);
                        Assert(BordersAboveSource(process.Id, layer.Handle, 8), "Screen and hover borders did not passively recover above the ordinary topmost source.");
                        WaitEdges(context, process, display, hoverFrame, Rectangle.Empty, "verify-raised-screen-hover-geometry", 1500);
                        RequireFixtureForeground(context, "generated-topmost-layer-shown");
                        metrics["ordinaryTopmostRaisedAfterPicker"] = true;
                        metrics["bordersAboveGeneratedLayerObserved"] = true;
                        metrics["generatedTopmostFullScreen"] = true;
                        metrics["visibleCompositeDiffersFromForegroundWindow"] = true;
                    }
                    // Change the generated content only AFTER the selector exists.
                    // A frozen pre-selection desktop image fails the color check.
                    Point first = Point.Empty, last = Point.Empty;
                    context.Stage = "update-generated-source";
                    OnUi(form, delegate {
                        form.BackColor = mode == "topmost-capture" ? Color.FromArgb(25, 45, 70) : liveColor; form.Refresh();
                        if (layer != null) { layer.BackColor = liveColor; layer.Refresh(); }
                        first = form.PointToScreen(new Point(50, 50));
                        last = form.PointToScreen(new Point(260, 160));
                    });
                    Thread.Sleep(150);
                    Move(context, "move-to-selection-origin", first); Thread.Sleep(80);
                    if (mode == "escape-short") {
                        INPUT down = new INPUT(); down.type = 1; down.data.keyboard.vk = 0x1B;
                        INPUT up = down; up.data.keyboard.flags = 2;
                        RequireFixtureForeground(context, "send-short-escape");
                        Assert(SendInput(2, new INPUT[] { down, up }, Marshal.SizeOf(typeof(INPUT))) == 2, "Windows rejected a paired short Escape tap.");
                    } else if (mode == "escape") {
                        INPUT key = new INPUT(); key.type = 1; key.data.keyboard.vk = 0x1B;
                        Send(context, "escape-down", key); Thread.Sleep(80); key.data.keyboard.flags = 2; Send(context, "escape-up", key);
                    } else if (mode == "right") {
                        Button(context, "cancel-right-down", 0x0008); Thread.Sleep(80); Button(context, "cancel-right-up", 0x0010);
                    } else {
                        context.Stage = "measure-before-drag";
                        process.Refresh(); TimeSpan cpuBefore = process.TotalProcessorTime;
                        metrics["helperPrivateBytesBeforeDrag"] = process.PrivateMemorySize64;
                        metrics["helperWorkingSetBytesBeforeDrag"] = process.WorkingSet64;
                        Button(context, "selection-left-down", 0x0002); Thread.Sleep(80);
                        if (mode == "capture-burst") {
                            double longestInput = 0;
                            List<double> borderDelays = new List<double>();
                            for (int step = 1; step <= 90; step++) {
                                Stopwatch inputTime = Stopwatch.StartNew();
                                Point target = new Point(first.X + (last.X - first.X) * step / 90, first.Y + (last.Y - first.Y) * step / 90);
                                Move(context, "burst-move-" + step, target);
                                longestInput = Math.Max(longestInput, inputTime.Elapsed.TotalMilliseconds);
                                if (step % 10 == 0) {
                                    context.Stage = "observe-burst-edge-" + step;
                                    while (!SelectionEdgeAt(process.Id, first, target) && inputTime.ElapsedMilliseconds < 2500) Thread.Sleep(2);
                                    Assert(SelectionEdgeAt(process.Id, first, target), "A sampled drag move did not reach its actual thin edge HWND coordinates.");
                                    borderDelays.Add(inputTime.Elapsed.TotalMilliseconds);
                                }
                                Thread.Sleep(8);
                            }
                            Stopwatch settled = Stopwatch.StartNew();
                            context.Stage = "settle-final-burst-edge";
                            while (!SelectionEdgeAt(process.Id, first, last) && settled.ElapsedMilliseconds < 2500) Thread.Sleep(10);
                            Assert(SelectionEdgeAt(process.Id, first, last), "The visual selection border did not reach the actual final drag coordinates.");
                            metrics["burstMoves"] = 90; metrics["longestSendInputCallMilliseconds"] = longestInput;
                            metrics["finalBorderSettlementMilliseconds"] = settled.Elapsed.TotalMilliseconds;
                            borderDelays.Sort();
                            metrics["dragToObservedBorderSamples"] = borderDelays.Count;
                            metrics["dragToObservedBorderP50Milliseconds"] = borderDelays[(int)Math.Ceiling(borderDelays.Count * 0.5) - 1];
                            metrics["dragToObservedBorderP95Milliseconds"] = borderDelays[(int)Math.Ceiling(borderDelays.Count * 0.95) - 1];
                            // Timings are observations on this Windows test host,
                            // not proof of the owner's Intel/AMD PC performance.
                        } else { Move(context, "move-to-selection-end", last); Thread.Sleep(100); }
                        context.Stage = "measure-drag";
                        process.Refresh();
                        metrics["helperCpuMillisecondsDuringDrag"] = (process.TotalProcessorTime - cpuBefore).TotalMilliseconds;
                        metrics["helperPrivateBytesDuringDrag"] = process.PrivateMemorySize64;
                        metrics["helperWorkingSetBytesDuringDrag"] = process.WorkingSet64;
                        metrics["helperPeakWorkingSetBytesDuringSession"] = process.PeakWorkingSet64;
                        int draggingCount; long draggingLargest;
                        Rectangle expectedSelection = Rectangle.FromLTRB(first.X - 1, first.Y - 1, last.X + 1, last.Y + 1);
                        WaitEdges(context, process, display, Rectangle.Empty, expectedSelection, "verify-no-hover-during-drag", 1500);
                        metrics["draggingVisibleBorderAreaPixels"] = BorderArea(process.Id, out draggingCount, out draggingLargest);
                        metrics["draggingVisibleBorderWindowCount"] = draggingCount; metrics["draggingLargestSurfacePixels"] = draggingLargest;
                        metrics["hoverHiddenDuringDrag"] = true;
                        Button(context, "selection-left-up", 0x0004);
                    }
                    context.Stage = "wait-helper-exit";
                    Assert(process.WaitForExit(10000), "Capture helper did not finish after the fixture selection/cancellation.");
                    JavaScriptSerializer json = new JavaScriptSerializer(); json.MaxJsonLength = 16 * 1024 * 1024;
                    Dictionary<string, object> reply = json.Deserialize<Dictionary<string, object>>(output.GetAwaiter().GetResult());
                    context.Stage = "verify-helper-response";
                    if (!capture) {
                        Assert(!(bool)reply["ok"] && process.ExitCode != 0 && ((string)reply["error"]).StartsWith("CANCELLED:", StringComparison.Ordinal), "Cancel did not return CANCELLED.");
                    } else {
                        Assert((bool)reply["ok"] && process.ExitCode == 0, "Generated fixture capture failed.");
                        using (MemoryStream bytes = new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))
                        using (Bitmap image = new Bitmap(bytes)) {
                            Assert(image.Width == last.X - first.X && image.Height == last.Y - first.Y, "Physical-pixel crop dimensions differ from the selected rectangle.");
                            metrics["capturedPhysicalWidth"] = image.Width; metrics["capturedPhysicalHeight"] = image.Height;
                            foreach (Point at in new Point[] { Point.Empty, new Point(image.Width / 2, image.Height / 2), new Point(image.Width - 1, image.Height - 1) }) {
                                Color pixel = image.GetPixel(at.X, at.Y);
                                Assert(Math.Abs(pixel.R - liveColor.R) <= 2 && Math.Abs(pixel.G - liveColor.G) <= 2 && Math.Abs(pixel.B - liveColor.B) <= 2, "Capture froze old content or included its selection overlay.");
                            }
                            metrics["generatedVisiblePixelRgb"] = new int[] { liveColor.R, liveColor.G, liveColor.B };
                        }
                    }
                    RequireFixtureForeground(context, "capture-complete");
                    context.Stage = "verify-generated-layer-input";
                    if (layer != null) OnUi(form, delegate { Assert(layerMouseEvents == 0, "Selection button input reached the generated topmost layer."); });
                    context.Stage = "verify-no-leftover-borders";
                    Assert(ReadyOverlays(process.Id) == 0, "Capture border windows survived their helper process.");
                    metrics["mode"] = mode; metrics["passed"] = true; metrics["foregroundPreserved"] = true;
                    metrics["sourceHwnd"] = WindowId(form.Handle); metrics["sourceProcessId"] = Process.GetCurrentProcess().Id;
                    metrics["helperProcessId"] = process.Id;
                    return metrics;
                } finally {
                    if (!process.HasExited) { process.Kill(); process.WaitForExit(3000); }
                }
            }
        } finally {
            if (layer != null) OnUi(form, delegate { layer.Close(); layer.Dispose(); });
        }
    }
    public static Dictionary<string, object> Run(string helper) {
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        Assert(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Fixture could not establish physical per-monitor coordinates.");
        Dictionary<string, object> report = new Dictionary<string, object>();
        List<Dictionary<string, object>> trials = new List<Dictionary<string, object>>();
        report["ok"] = false; report["trials"] = trials;
        report["clipboardAccessed"] = false; report["userContentCaptured"] = false;
        report["multiMonitorInteractiveTested"] = false; report["mixedDpiInteractiveTested"] = false;
        report["pinnedAppExclusionTested"] = false; report["globalShortcutsTested"] = false;
        using (Form form = new Form()) {
            TrialContext context = new TrialContext(form);
            form.Text = "EchoLingo generated live-capture fixture";
            form.AutoScaleMode = AutoScaleMode.None;
            form.ClientSize = new Size(400, 250); form.StartPosition = FormStartPosition.CenterScreen;
            form.FormBorderStyle = FormBorderStyle.FixedDialog; form.MaximizeBox = false;
            form.BackColor = Color.FromArgb(50, 210, 110);
            int sourceMouseEvents = 0;
            EscapeFilter escapeEvents = new EscapeFilter();
            Application.AddMessageFilter(escapeEvents);
            form.MouseDown += delegate { sourceMouseEvents++; }; form.MouseUp += delegate { sourceMouseEvents++; };
            Thread worker = null;
            bool finished = false;
            form.FormClosing += delegate(object sender, FormClosingEventArgs args) { if (!finished) args.Cancel = true; };
            form.Shown += delegate {
                form.Activate(); SetForegroundWindow(form.Handle);
                worker = new Thread(delegate() {
                    Point originalPointer = Point.Empty;
                    bool restorePointer = GetPhysicalCursorPos(out originalPointer);
                    try {
                        Assert(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Fixture worker DPI context failed.");
                        foreach (string mode in new string[] { "capture", "capture-burst", "topmost-capture", "escape-short", "escape", "right", "capture" }) {
                            context.Mode = mode; context.Stage = "reset-generated-source";
                            OnUi(form, delegate { form.BackColor = Color.FromArgb(50, 210, 110); form.Refresh(); });
                            trials.Add(Trial(context, helper, mode, Color.FromArgb(220, 70, 85)));
                        }
                        Dictionary<string, object> hover = HoverTrial(context, helper);
                        trials.Add(hover);
                        report["hoverWindowFollowingPassed"] = true;
                        report["hoverDesktopOrShellFallbackPassed"] = true;
                        report["hoverNeverActivatedPassed"] = true;
                        report["hoverHiddenDuringDragPassed"] = true;
                        report["hoverOverlayAbsentInCapturePassed"] = true;
                        report["disabledWindowOcclusionPassed"] = true;
                        report["observedAllocatedEdgeWindowCount"] = hover["observedAllocatedEdgeWindowCount"];
                        context.Stage = "verify-generated-source-input";
                        OnUi(form, delegate {
                            Assert(sourceMouseEvents == 0, "Selection/cancel button input reached the generated source window.");
                            Assert(escapeEvents.Count == 0, "Escape down/up reached the generated source window.");
                        });
                        report["selectionButtonsConsumed"] = true;
                        report["escapeDownUpConsumed"] = true;
                        report["liveCaptureAfterSelectionPassed"] = true;
                        report["overlayAbsentInCapture"] = true;
                        report["ok"] = true;
                    } catch (Exception error) {
                        report["error"] = error.Message;
                        report["stack"] = error.ToString();
                        report["failedMode"] = context.Mode; report["failedStage"] = context.Stage;
                        report["foregroundAtFailure"] = context.ForegroundFailure ?? ForegroundMetadata(context, GetForegroundWindow());
                        if (context.LastEdges != null) report["lastObservedEdges"] = context.LastEdges;
                        if (context.HoverTrial != null) report["partialHoverTrial"] = context.HoverTrial;
                    }
                    finally {
                        try { if (restorePointer && GetForegroundWindow() == form.Handle) Move(context, "restore-original-pointer", originalPointer); }
                        catch (Exception error) {
                            report["ok"] = false; report["pointerRestoreError"] = error.Message;
                            report["pointerRestoreStack"] = error.ToString();
                            report["pointerRestoreForeground"] = context.ForegroundFailure ?? ForegroundMetadata(context, GetForegroundWindow());
                        }
                        finally { OnUi(form, delegate { finished = true; form.Close(); }); }
                    }
                });
                worker.SetApartmentState(ApartmentState.STA); worker.Start();
            };
            Application.Run(form);
            Application.RemoveMessageFilter(escapeEvents);
            if (worker != null) worker.Join(5000);
        }
        return report;
    }
}
'@
    $references = @([System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    $result = [EchoLingoLiveCaptureSmoke]::Run($HelperPath)
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 10 -Compress))
    if (-not $result['ok']) { exit 1 }
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    [Console]::Out.WriteLine((@{ ok = $false; error = $message; clipboardAccessed = $false; userContentCaptured = $false } | ConvertTo-Json -Compress))
    exit 1
}
