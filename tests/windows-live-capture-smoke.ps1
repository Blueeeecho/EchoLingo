# Explicit Windows desktop fixture: captures only an opaque generated test
# window. No clipboard, translation API, user text, or full-desktop screenshot.
# Run in an unlocked isolated test session; it moves the pointer inside its own
# window and tests the real helper hook/transparent overlays via SendInput.
[CmdletBinding()]
param([string]$HelperPath = '', [string]$NativeAssemblyPath = '', [switch]$PerformanceDiagnostics, [switch]$LegacyBaseline, [ValidateSet('hybrid','planeOnly')][string]$InputBackend = 'hybrid')
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
    if (-not [string]::IsNullOrWhiteSpace($NativeAssemblyPath)) { $NativeAssemblyPath = (Resolve-Path -LiteralPath $NativeAssemblyPath).Path }
    if ($LegacyBaseline) {
        $baselineText = [IO.File]::ReadAllText($HelperPath).TrimStart([char]0xfeff).Replace("`r`n", "`n")
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $baselineHash = ([BitConverter]::ToString($hash.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($baselineText)))).Replace('-', '').ToLowerInvariant() } finally { $hash.Dispose() }
        if ($baselineHash -ne '4a3674ff1b7da09b664fe807ead116d45b5689adcfc2bc2a47eea77ee6d7b1b7' -or $InputBackend -ne 'hybrid' -or $NativeAssemblyPath) { throw 'BASELINE_IDENTITY: Legacy expectations require the exact source-only ab4405c helper.' }
    }
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
    static string nativeArguments = "";
    static bool requireInputPlanes = true;
    static string inputBackend = "hybrid";
    static int activeHelperProcessId;
    static Dictionary<string,object> failedPlaneComposition;
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
    [DllImport("user32.dll")] static extern IntPtr GetTopWindow(IntPtr parent);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr parent, Point point, uint flags);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
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
        public Dictionary<string, object> LastHelperDiagnostics;
        public Dictionary<string, object> HoverTrial;
        public Dictionary<string, object> CrossPeerTrial;
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
    static bool IsInputPlane(IntPtr window, int processId) {
        StringBuilder name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
        return name.ToString() == "EchoLingoCaptureInputPlane-" + processId;
    }
    static List<EdgeWindow> InputPlanes(int processId, bool visibleOnly) {
        List<EdgeWindow> result = new List<EdgeWindow>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner != processId || !IsInputPlane(window, processId) || (visibleOnly && !IsWindowVisible(window))) return true;
            long style = GetWindowLongPtr(window, -20).ToInt64();
            const long required = 0x00200000L | 0x08000000L | 0x00000080L | 8;
            Assert((style & required) == required && (style & (0x00080000L | 0x00000020L)) == 0,
                "Input plane must be NoRedirection/NoActivate/ToolWindow/Topmost, never layered or transparent-style.");
            RECT r; Assert(GetWindowRect(window, out r), "Cannot inspect the actual input plane.");
            result.Add(new EdgeWindow { Handle = window, Bounds = Rectangle.FromLTRB(r.left,r.top,r.right,r.bottom) }); return true;
        }, IntPtr.Zero);
        return result;
    }
    static int AllocatedThinCount(int processId) {
        int count = 0;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            long flags = GetWindowLongPtr(window, -20).ToInt64();
            if (owner == processId && !IsInputPlane(window, processId) && (flags & (0x08000000L|0x00080000L|0x20L)) == (0x08000000L|0x00080000L|0x20L)) count++;
            return true;
        }, IntPtr.Zero); return count;
    }
    static bool Above(IntPtr upper, IntPtr lower) {
        int count = 0; for (IntPtr window = GetWindow(lower,3); window != IntPtr.Zero && count++ < 4096; window = GetWindow(window,3)) if (window == upper) return true;
        return false;
    }
    static bool PlaneComposition(int processId, List<EdgeWindow> edges, Point pointer, Dictionary<string,object> metadata, bool failureDetails = false) {
        List<EdgeWindow> all = InputPlanes(processId,false), visible = InputPlanes(processId,true);
        metadata["allocatedInputPlaneCount"] = all.Count; metadata["visibleInputPlaneCount"] = visible.Count;
        metadata["requiredInputPlane"] = requireInputPlanes;
        if (!requireInputPlanes) return all.Count == 0;
        List<Rectangle> displays = new List<Rectangle>(); foreach (Screen screen in Screen.AllScreens) displays.Add(screen.Bounds);
        bool countsMatch = all.Count == displays.Count && visible.Count == displays.Count;
        bool geometry = countsMatch; int unmatchedPlaneFrames = 0, intersectingEdges = 0, edgeOrderFailures = 0;
        List<Rectangle> remaining = new List<Rectangle>(displays);
        List<Dictionary<string,object>> observed = new List<Dictionary<string,object>>();
        foreach (EdgeWindow plane in visible) {
            int index = remaining.IndexOf(plane.Bounds); if (index < 0) { geometry = false; unmatchedPlaneFrames++; } else remaining.RemoveAt(index);
            observed.Add(new Dictionary<string,object> { { "hwnd",WindowId(plane.Handle) }, { "physicalBounds",RectValue(plane.Bounds) }, { "noRedirectionBitmap",true } });
            foreach (EdgeWindow edge in edges) if (!Rectangle.Intersect(edge.Bounds,plane.Bounds).IsEmpty) {
                intersectingEdges++; if (!Above(edge.Handle,plane.Handle)) { geometry = false; edgeOrderFailures++; }
            }
        }
        int allocated = AllocatedThinCount(processId); metadata["allocatedThinWindowCount"] = allocated;
        metadata["observedInputPlanes"] = observed;
        geometry = geometry && remaining.Count == 0 && allocated == 12 * displays.Count;
        IntPtr raw = WindowFromPoint(pointer), rawRoot = GetAncestor(raw,2);
        Point client = pointer; IntPtr desktop = GetDesktopWindow();
        bool mapped = desktop != IntPtr.Zero && ScreenToClient(desktop,ref client);
        IntPtr through = mapped ? GetAncestor(ChildWindowFromPointEx(desktop,client,0x1|0x4),2) : IntPtr.Zero;
        bool rawPlane = visible.Exists(delegate(EdgeWindow plane) { return plane.Handle == rawRoot && plane.Bounds.Contains(pointer); });
        bool rawEdge = edges.Exists(delegate(EdgeWindow edge) { return edge.Handle == rawRoot && edge.Bounds.Contains(pointer); });
        bool actualPlane = visible.Exists(delegate(EdgeWindow plane) { return plane.Handle == through && plane.Bounds.Contains(pointer); });
        metadata["rawPointerRootHwnd"] = WindowId(rawRoot); metadata["transparentSkippingPointerRootHwnd"] = WindowId(through);
        metadata["rawPointerIsExactPlane"] = rawPlane; metadata["rawPointerIsVerifiedThinEdge"] = rawEdge;
        metadata["transparentSkippingHitIsExactPlane"] = actualPlane;
        bool matched = geometry && actualPlane && (rawPlane || rawEdge);
        if (failureDetails && !matched) {
            // Observe only the failing check. No new move, input, capture,
            // repeated hit test, settling wait or window-order mutation.
            metadata["planeCountsMatch"] = countsMatch; metadata["planeFramesMatch"] = unmatchedPlaneFrames == 0 && remaining.Count == 0;
            metadata["thinAllocationMatches"] = allocated == 12 * displays.Count; metadata["geometryMatched"] = geometry;
            metadata["intersectingEdgePlanePairs"] = intersectingEdges; metadata["edgePlaneOrderFailures"] = edgeOrderFailures;
            metadata["visibleThinEdgeCount"] = edges.Count; metadata["desktopClientMappingSucceeded"] = mapped;
            List<Dictionary<string,object>> edgeValues = new List<Dictionary<string,object>>();
            foreach (EdgeWindow edge in edges) edgeValues.Add(new Dictionary<string,object> { { "hwnd",WindowId(edge.Handle) }, { "bounds",RectValue(edge.Bounds) } });
            metadata["visibleThinEdges"] = edgeValues;
            List<Dictionary<string,object>> planeValues = new List<Dictionary<string,object>>();
            foreach (EdgeWindow plane in all) planeValues.Add(new Dictionary<string,object> { { "hwnd",WindowId(plane.Handle) }, { "bounds",RectValue(plane.Bounds) },
                { "observedVisible",visible.Exists(delegate(EdgeWindow item) { return item.Handle == plane.Handle; }) } });
            metadata["allAllocatedInputPlanes"] = planeValues;
            try { metadata["rawRootMetadata"] = ReadonlyWindowMetadata(rawRoot); metadata["transparentSkippingRootMetadata"] = ReadonlyWindowMetadata(through); }
            catch { metadata["nativeRootMetadataUnavailable"] = true; }
        }
        return matched;
    }
    static Dictionary<string,object> ReadonlyWindowMetadata(IntPtr window) {
        uint process; uint thread = GetWindowThreadProcessId(window,out process); StringBuilder name = new StringBuilder(128);
        GetClassName(window,name,name.Capacity);
        return new Dictionary<string,object> { { "hwnd",WindowId(window) }, { "processId",process }, { "threadId",thread }, { "class",name.ToString() },
            { "exists",IsWindow(window) }, { "visible",IsWindowVisible(window) }, { "enabled",IsWindowEnabled(window) },
            { "style",GetWindowLongPtr(window,-16).ToInt64() }, { "extendedStyle",GetWindowLongPtr(window,-20).ToInt64() } };
    }
    static void SaveFailedPlaneObservation(Dictionary<string,object> observed, Point pointer) {
        failedPlaneComposition = observed;
        try {
            observed["checkedPointerPhysicalXY"] = new int[] { pointer.X,pointer.Y };
            Point actual; bool known = GetPhysicalCursorPos(out actual); observed["actualPointerKnown"] = known;
            if (known) observed["actualPointerPhysicalXY"] = new int[] { actual.X,actual.Y };
            observed["foregroundMetadata"] = ReadonlyWindowMetadata(GetForegroundWindow());
            observed["observationScope"] = "Same failing check; Win32 enumeration and hit-testing are non-atomic metadata observations.";
        } catch { observed["additionalObservationUnavailable"] = true; }
    }
    static void RequirePlaneAt(int processId, Point pointer) {
        Dictionary<string,object> observed = new Dictionary<string,object>(); bool matched;
        try { matched = PlaneComposition(processId,VisibleEdges(processId),pointer,observed,true); }
        catch (Exception error) { observed["compositionObservationExceptionType"] = error.GetType().Name; SaveFailedPlaneObservation(observed,pointer); throw; }
        if (!matched) SaveFailedPlaneObservation(observed,pointer);
        Assert(matched, "The actual pointer does not hit the exact required helper input plane composition.");
    }
    static IntPtr UnderlyingRootAt(Point point, int helperId) {
        int count = 0;
        for (IntPtr window = GetTopWindow(IntPtr.Zero); window != IntPtr.Zero && count++ < 4096; window = GetWindow(window,2)) {
            if (!IsWindowVisible(window)) continue;
            uint owner; GetWindowThreadProcessId(window,out owner);
            if (owner == helperId) continue; // Exact helper overlays are independently validated, never a foreign PID.
            long style = GetWindowLongPtr(window,-20).ToInt64(); if ((style & 0x20) != 0) continue;
            RECT r; if (GetWindowRect(window,out r) && Rectangle.FromLTRB(r.left,r.top,r.right,r.bottom).Contains(point)) return GetAncestor(window,2);
        }
        return IntPtr.Zero;
    }
    static Dictionary<string,object> SafeNumericMetadata(object value) {
        Dictionary<string,object> source = value as Dictionary<string,object>;
        Dictionary<string,object> result = new Dictionary<string,object>();
        if (source == null || source.Count > 128) return result;
        foreach (KeyValuePair<string,object> field in source) {
            if (!System.Text.RegularExpressions.Regex.IsMatch(field.Key, "^[A-Za-z][A-Za-z0-9]{0,63}$")) continue;
            if (!(field.Value is int || field.Value is long || field.Value is decimal || field.Value is double || field.Value is float)) continue;
            double number = Convert.ToDouble(field.Value);
            if (!Double.IsNaN(number) && !Double.IsInfinity(number)) result[field.Key] = field.Value;
        }
        return result;
    }
    static void PreserveExitedHelper(TrialContext context, Process process, Task<string> output, Dictionary<string,object> metrics) {
        // A failed readiness/held-drag observation must retain a naturally
        // exited helper's safe diagnosis, never its imageBase64 or stderr.
        try {
            if (!process.HasExited || !output.Wait(1000)) return;
            string raw = output.GetAwaiter().GetResult();
            if (String.IsNullOrEmpty(raw) || raw.Length > 16 * 1024 * 1024) return;
            JavaScriptSerializer json = new JavaScriptSerializer(); json.MaxJsonLength = 16 * 1024 * 1024;
            Dictionary<string,object> reply = json.Deserialize<Dictionary<string,object>>(raw);
            Dictionary<string,object> safe = new Dictionary<string,object> { { "exitCode",process.ExitCode } };
            if (reply.ContainsKey("ok") && reply["ok"] is bool) safe["ok"] = reply["ok"];
            if (reply.ContainsKey("error") && reply["error"] is string) {
                string error = (string)reply["error"]; safe["error"] = error.Substring(0,Math.Min(error.Length,600));
            }
            if (reply.ContainsKey("nativeBackend") && ((string)reply["nativeBackend"] == "precompiled-framework-dll" || (string)reply["nativeBackend"] == "source-compiled-cli")) safe["nativeBackend"] = reply["nativeBackend"];
            foreach (string key in new string[] { "captureHealth","capturePerformance","helperPerformance" })
                if (reply.ContainsKey(key)) safe[key] = SafeNumericMetadata(reply[key]);
            metrics["helperExitedBeforeFixtureCleanup"] = true; metrics["helperDiagnostics"] = safe;
            context.LastHelperDiagnostics = safe;
        } catch { /* Diagnostic collection must not replace the original failure. */ }
    }
    static void VerifyBackend(Dictionary<string,object> reply, bool capture) {
        if (!requireInputPlanes) return;
        Assert(reply.ContainsKey("captureHealth"), "Candidate helper omitted real input backend metadata.");
        Dictionary<string,object> health = (Dictionary<string,object>)reply["captureHealth"];
        bool planeOnly = inputBackend == "planeOnly";
        Assert(Convert.ToInt64(health["inputBackend"]) == (planeOnly ? 2 : 1), "Actual helper used a different input backend.");
        Assert(Convert.ToInt64(health["mouseHookInstalled"]) == (planeOnly ? 0 : 1), "Forced plane-only did not actually disable the mouse hook.");
        if (planeOnly) Assert(Convert.ToInt64(health["hookMouseMoves"])==0 && Convert.ToInt64(health["hookMouseDowns"])==0 && Convert.ToInt64(health["hookMouseUps"])==0,
            "Forced no-hook session unexpectedly reported mouse hook events.");
        Assert(Convert.ToInt64(health["inputPlaneCount"]) == Screen.AllScreens.Length && Convert.ToInt64(health["inputPlaneRemainingAfterCleanup"]) == 0,
            "Input plane allocation/cleanup metadata is incorrect.");
        if (planeOnly && capture) Assert(Convert.ToInt64(health["inputPlaneDowns"]) > 0 && Convert.ToInt64(health["inputPlaneUps"]) > 0 && Convert.ToInt64(health["inputPlaneFallbackUsed"]) == 1,
            "No-hook fallback did not prove actual input HWND down/up delivery.");
    }
    static List<EdgeWindow> VisibleEdges(int processId) {
        List<EdgeWindow> result = new List<EdgeWindow>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner != processId || !IsWindowVisible(window) || IsInputPlane(window,processId)) return true;
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
            Point pointer; bool pointerKnown = GetPhysicalCursorPos(out pointer);
            bool planesReady = pointerKnown && PlaneComposition(process.Id,actual,pointer,context.LastEdges);
            if (!process.HasExited && Matches(actual, expected) && planesReady) return actual;
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
        if (requireInputPlanes && activeHelperProcessId != 0) RequirePlaneAt(activeHelperProcessId,point);
        IntPtr root = requireInputPlanes && activeHelperProcessId != 0 ? UnderlyingRootAt(point,activeHelperProcessId) : GetAncestor(WindowFromPoint(point), 2); uint owner;
        GetWindowThreadProcessId(root, out owner);
        Assert((root == first || (second != IntPtr.Zero && root == second)) && owner == Process.GetCurrentProcess().Id,
            "Pointer target is not the exact generated source/layer; no fixture input will target another app.");
        Assert(IsWindowVisible(root) && Frame(root).Contains(point), "Generated source frame/PID is no longer independently valid.");
        return root;
    }
    static long BorderArea(int processId, out int total, out long largest) {
        int count = 0; long area = 0, maximum = 0;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == processId && IsWindowVisible(window) && !IsInputPlane(window,processId)) {
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
            if (owner == processId && IsWindowVisible(window) && !IsInputPlane(window,processId)) borders++;
        }
        return borders == expectedCount;
    }
    static bool SelectionEdgeAt(int processId, Point origin, Point end) {
        bool found = false;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner); RECT bounds;
            if (owner == processId && IsWindowVisible(window) && !IsInputPlane(window,processId) && GetWindowRect(window, out bounds)
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
        IntPtr hit = WindowFromPoint(point), root = requireInputPlanes && activeHelperProcessId != 0 ? UnderlyingRootAt(point,activeHelperProcessId) : GetAncestor(hit, 2); uint owner;
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
        context.HelperProcessId = 0; activeHelperProcessId = 0; context.LastHelperDiagnostics = null; context.ForegroundFailure = null; context.LastEdges = null;
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
            start.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + helper + "\" -Mode capture-image" + nativeArguments;
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
            Stopwatch startup = Stopwatch.StartNew();
            using (Process process = Process.Start(start)) {
                context.HelperProcessId = process.Id; activeHelperProcessId = process.Id; metrics["helperProcessId"] = process.Id;
                Task<string> output = process.StandardOutput.ReadToEndAsync(), error = process.StandardError.ReadToEndAsync();
                try {
                    List<EdgeWindow> atA = ObserveHoverPhase(context, process, display, aFrame, Rectangle.Empty,
                        "hover-A", 25000, observations, known);
                    metrics["helperStartupToReadyMilliseconds"] = startup.Elapsed.TotalMilliseconds;
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
                    IntPtr occluding = requireInputPlanes ? UnderlyingRootAt(bPoint,process.Id) : GetAncestor(ChildWindowFromPointEx(desktop, desktopPoint, 0x1 | 0x4), 2);
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
                    VerifyBackend(reply, true);
                    Assert(process.ExitCode == 0 && (bool)reply["ok"], "Hover free-drag capture failed.");
                    if (reply.ContainsKey("nativeBackend")) metrics["nativeBackend"] = reply["nativeBackend"];
                    if (reply.ContainsKey("helperPerformance")) metrics["helperPerformance"] = reply["helperPerformance"];
                    if (reply.ContainsKey("capturePerformance")) metrics["capturePerformance"] = reply["capturePerformance"];
                    if (reply.ContainsKey("captureHealth")) metrics["captureHealth"] = reply["captureHealth"];
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
                    Assert(ReadyOverlays(process.Id) == 0 && InputPlanes(process.Id,false).Count == 0, "Hover capture left visible border HWNDs.");
                    metrics["hoverOverlayAbsentInCapturePassed"] = true; metrics["freeRegionCapturePassed"] = true;
                    metrics["foregroundPreserved"] = true; metrics["passed"] = true;
                    return metrics;
                } finally {
                    PreserveExitedHelper(context,process,output,metrics);
                    if (leftHeld && GetForegroundWindow() == form.Handle) {
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
        context.Mode = mode; context.Stage = "prepare-generated-source"; context.HelperProcessId = 0; activeHelperProcessId = 0; context.LastHelperDiagnostics = null; context.ForegroundFailure = null;
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
            start.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + helper + "\" -Mode capture-image" + nativeArguments;
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
            Stopwatch startup = Stopwatch.StartNew();
            using (Process process = Process.Start(start)) {
                context.HelperProcessId = process.Id; activeHelperProcessId = process.Id;
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                Dictionary<string, object> metrics = new Dictionary<string, object>();
                bool capture = mode == "capture" || mode == "capture-burst" || mode == "topmost-capture", leftHeld = false;
                try {
                    context.Stage = "wait-ready-overlays";
                    // Both the pointer display and eligible generated window
                    // have exact four-edge perimeters. A bare count of4/8 is
                    // insufficient: the actual physical geometries must match.
                    WaitEdges(context, process, display, hoverFrame, Rectangle.Empty, "wait-ready-overlays", 25000);
                    metrics["helperStartupToReadyMilliseconds"] = startup.Elapsed.TotalMilliseconds;
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
                        Stopwatch dragWall = Stopwatch.StartNew();
                        metrics["helperPrivateBytesBeforeDrag"] = process.PrivateMemorySize64;
                        metrics["helperWorkingSetBytesBeforeDrag"] = process.WorkingSet64;
                        Button(context, "selection-left-down", 0x0002); leftHeld = true; Thread.Sleep(80);
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
                        metrics["dragWallMilliseconds"] = dragWall.Elapsed.TotalMilliseconds;
                        metrics["helperPrivateBytesDuringDrag"] = process.PrivateMemorySize64;
                        metrics["helperWorkingSetBytesDuringDrag"] = process.WorkingSet64;
                        metrics["helperPeakWorkingSetBytesDuringSession"] = process.PeakWorkingSet64;
                        int draggingCount; long draggingLargest;
                        Rectangle expectedSelection = Rectangle.FromLTRB(first.X - 1, first.Y - 1, last.X + 1, last.Y + 1);
                        WaitEdges(context, process, display, Rectangle.Empty, expectedSelection, "verify-no-hover-during-drag", 1500);
                        metrics["draggingVisibleBorderAreaPixels"] = BorderArea(process.Id, out draggingCount, out draggingLargest);
                        metrics["draggingVisibleBorderWindowCount"] = draggingCount; metrics["draggingLargestSurfacePixels"] = draggingLargest;
                        metrics["hoverHiddenDuringDrag"] = true;
                        Button(context, "selection-left-up", 0x0004); leftHeld = false;
                    }
                    context.Stage = "wait-helper-exit";
                    Assert(process.WaitForExit(10000), "Capture helper did not finish after the fixture selection/cancellation.");
                    JavaScriptSerializer json = new JavaScriptSerializer(); json.MaxJsonLength = 16 * 1024 * 1024;
                    Dictionary<string, object> reply = json.Deserialize<Dictionary<string, object>>(output.GetAwaiter().GetResult());
                    VerifyBackend(reply, capture);
                    metrics["nativeBackend"] = reply.ContainsKey("nativeBackend") ? reply["nativeBackend"] : "legacy-source-compiled-cli";
                    if (reply.ContainsKey("helperPerformance")) metrics["helperPerformance"] = reply["helperPerformance"];
                    if (reply.ContainsKey("capturePerformance")) metrics["capturePerformance"] = reply["capturePerformance"];
                    if (reply.ContainsKey("captureHealth")) {
                        metrics["captureHealth"] = reply["captureHealth"];
                        Dictionary<string, object> health = (Dictionary<string, object>)reply["captureHealth"];
                        if (capture && inputBackend != "planeOnly") Assert(Convert.ToInt64(health["hookMouseDowns"]) > 0 && Convert.ToInt64(health["hookMouseUps"]) > 0,
                            "Visible blue borders did not prove a real mouse down/up capture.");
                    }
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
                    Assert(ReadyOverlays(process.Id) == 0 && InputPlanes(process.Id,false).Count == 0, "Capture border windows survived their helper process.");
                    metrics["mode"] = mode; metrics["passed"] = true; metrics["foregroundPreserved"] = true;
                    metrics["sourceHwnd"] = WindowId(form.Handle); metrics["sourceProcessId"] = Process.GetCurrentProcess().Id;
                    metrics["helperProcessId"] = process.Id;
                    return metrics;
                } finally {
                    PreserveExitedHelper(context,process,output,metrics);
                    if (leftHeld && GetForegroundWindow()==form.Handle) {
                        INPUT release=new INPUT(); release.data.mouse.flags=0x0004;
                        SendInput(1,new INPUT[] { release },Marshal.SizeOf(typeof(INPUT)));
                    }
                    if (!process.HasExited) { process.Kill(); process.WaitForExit(3000); }
                }
            }
        } finally {
            if (layer != null) OnUi(form, delegate { layer.Close(); layer.Dispose(); });
        }
    }
    // A separate ninth session keeps the original eight trials/counts intact.
    // Both opaque ordinary peers belong to this fixture, with no Owner/parent
    // relationship and no topmost/no-activate shortcut. The ROI spans both.
    static Dictionary<string, object> CrossPeerTrial(TrialContext context, string helper) {
        Form form = context.Source, peer = null;
        Button originButton = null, endButton = null;
        Rectangle previousBounds = Rectangle.Empty, display = Rectangle.Empty;
        FormBorderStyle previousBorder = FormBorderStyle.FixedDialog;
        Point first = Point.Empty, last = Point.Empty;
        IntPtr peerHwnd = IntPtr.Zero;
        int peerButtons = 0, originButtons = 0, peerClicks = 0;
        MouseEventHandler sourceEvents = delegate { originButtons++; };
        bool leftHeld = false;
        Dictionary<string, object> metrics = new Dictionary<string, object>();
        context.CrossPeerTrial = metrics; metrics["passed"] = false;
        context.Mode = "cross-peer-capture"; context.Stage = "prepare-independent-ordinary-peers";
        context.HelperProcessId = 0; activeHelperProcessId = 0; context.LastHelperDiagnostics = null; context.ForegroundFailure = null; context.LastEdges = null;
        context.GeneratedLayerHwnd = IntPtr.Zero;
        Color liveA = Color.FromArgb(220, 70, 85), liveB = Color.FromArgb(40, 180, 90);
        try {
            OnUi(form, delegate {
                previousBounds = form.Bounds; previousBorder = form.FormBorderStyle;
                Rectangle area = Screen.FromControl(form).WorkingArea; display = Screen.FromControl(form).Bounds;
                Assert(area.Width >= 720 && area.Height >= 360, "Peer fixture needs an actual720x360 generated-window work area.");
                form.FormBorderStyle = FormBorderStyle.None; form.TopMost = false;
                form.Bounds = new Rectangle(area.Left + 40, area.Top + 40, 320, 240);
                form.BackColor = Color.FromArgb(50, 210, 110);
                peer = new Form(); peer.Text = "EchoLingo generated independent peer B";
                peer.AutoScaleMode = AutoScaleMode.None; peer.FormBorderStyle = FormBorderStyle.None;
                // ShowInTaskbar=false gives a WinForms top-level Form a
                // hidden native taskbar owner even when Form.Owner is null.
                // These peers deliberately use normal taskbar windows so the
                // native GW_OWNER/GetParent assertions remain genuinely zero.
                peer.StartPosition = FormStartPosition.Manual; peer.ShowInTaskbar = true; peer.TopMost = false;
                peer.Owner = null;
                peer.Bounds = new Rectangle(form.Left + 280, form.Top, 320, 240);
                peer.BackColor = Color.FromArgb(210, 120, 40);
                originButton = new Button(); originButton.Text = "Generated A"; originButton.Bounds = new Rectangle(25, 45, 75, 35);
                endButton = new Button(); endButton.Text = "Generated B"; endButton.Bounds = new Rectangle(185, 165, 75, 35);
                foreach (Button button in new Button[] { originButton, endButton }) {
                    button.FlatStyle = FlatStyle.Flat; button.UseVisualStyleBackColor = false;
                    button.BackColor = Color.FromArgb(230, 150, 40); button.ForeColor = Color.Black;
                }
                originButton.MouseDown += delegate { originButtons++; }; originButton.MouseUp += delegate { originButtons++; };
                endButton.MouseDown += delegate { peerButtons++; }; endButton.MouseUp += delegate { peerButtons++; };
                originButton.Click += delegate { peerClicks++; }; endButton.Click += delegate { peerClicks++; };
                peer.MouseDown += delegate { peerButtons++; }; peer.MouseUp += delegate { peerButtons++; };
                form.MouseDown += sourceEvents; form.MouseUp += sourceEvents;
                form.Controls.Add(originButton); peer.Controls.Add(endButton);
                peer.Show(); peerHwnd = peer.Handle;
                form.Activate(); SetForegroundWindow(form.Handle);
                Assert(GetForegroundWindow() == form.Handle, "Peer source A could not hold actual foreground before helper startup.");
                IntPtr aOwner = GetWindow(form.Handle, 4), bOwner = GetWindow(peerHwnd, 4);
                IntPtr aParent = GetParent(form.Handle), bParent = GetParent(peerHwnd);
                metrics["preparedSourceAHwnd"] = WindowId(form.Handle); metrics["preparedSourceBHwnd"] = WindowId(peerHwnd);
                metrics["sourceANativeOwnerHwnd"] = WindowId(aOwner); metrics["sourceBNativeOwnerHwnd"] = WindowId(bOwner);
                metrics["sourceANativeParentHwnd"] = WindowId(aParent); metrics["sourceBNativeParentHwnd"] = WindowId(bParent);
                metrics["sourceAManagedOwnerIsNull"] = form.Owner == null; metrics["sourceBManagedOwnerIsNull"] = peer.Owner == null;
                Assert(form.Handle != peerHwnd && aOwner == IntPtr.Zero && bOwner == IntPtr.Zero && aParent == IntPtr.Zero && bParent == IntPtr.Zero
                    && form.Owner == null && peer.Owner == null && GetAncestor(form.Handle, 2) == form.Handle && GetAncestor(peerHwnd, 2) == peerHwnd,
                    "The generated A/B windows are not independent ownerless peers.");
                Assert((GetWindowLongPtr(form.Handle, -20).ToInt64() & 8) == 0 && (GetWindowLongPtr(peerHwnd, -20).ToInt64() & 8) == 0,
                    "The peer fixture accidentally created a topmost window.");
                first = form.PointToScreen(new Point(40, 60)); last = peer.PointToScreen(new Point(200, 180));
                Assert(GetAncestor(WindowFromPoint(first), 2) == form.Handle && GetAncestor(WindowFromPoint(last), 2) == peerHwnd,
                    "Actual pointer endpoints do not hit distinct generated peers.");
                form.Refresh(); peer.Refresh();
            });
            RequireFixtureForeground(context, "peer-source-ready-before-helper");
            uint peerOwner; GetWindowThreadProcessId(peerHwnd, out peerOwner);
            Assert(peerOwner == Process.GetCurrentProcess().Id, "Peer B is not fixture-owned.");
            MoveAndSettle(context, "move-to-generated-A-button", first);
            Rectangle hover = Frame(form.Handle);
            ProcessStartInfo start = new ProcessStartInfo("powershell.exe");
            start.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + helper + "\" -Mode capture-image" + nativeArguments;
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
            Stopwatch startup = Stopwatch.StartNew();
            using (Process process = Process.Start(start)) {
                context.HelperProcessId = process.Id; activeHelperProcessId = process.Id;
                Task<string> output = process.StandardOutput.ReadToEndAsync(), errors = process.StandardError.ReadToEndAsync();
                try {
                    WaitEdges(context, process, display, hover, Rectangle.Empty, "peer-ready-exact-screen-plus-A-hover", 25000);
                    metrics["helperStartupToReadyMilliseconds"] = startup.Elapsed.TotalMilliseconds;
                    OnUi(form, delegate { form.BackColor = liveA; peer.BackColor = liveB; form.Refresh(); peer.Refresh(); });
                    Thread.Sleep(150);
                    RequireGeneratedTarget(first,form.Handle,IntPtr.Zero); RequireGeneratedTarget(last,peerHwnd,IntPtr.Zero);
                    Button(context, "peer-A-button-left-down", 0x0002); leftHeld = true;
                    Thread.Sleep(100); Move(context, "peer-drag-to-B-button", last);
                    Rectangle selection = Rectangle.FromLTRB(first.X - 1, first.Y - 1, last.X + 1, last.Y + 1);
                    WaitEdges(context, process, display, Rectangle.Empty, selection, "peer-drag-exact-free-ROI-no-hover", 1500);
                    // Observe a deliberately held real drag beyond the750ms health
                    // threshold. Polling must not falsely cancel an owned pair.
                    Thread.Sleep(900);
                    WaitEdges(context, process, display, Rectangle.Empty, selection, "peer-held-drag-still-owned", 1500);
                    RequireGeneratedTarget(last,peerHwnd,IntPtr.Zero);
                    Button(context, "peer-B-button-left-up", 0x0004); leftHeld = false;
                    Assert(process.WaitForExit(10000), "Cross-peer capture did not complete after release.");
                    JavaScriptSerializer json = new JavaScriptSerializer(); json.MaxJsonLength = 16 * 1024 * 1024;
                    Dictionary<string, object> reply = json.Deserialize<Dictionary<string, object>>(output.GetAwaiter().GetResult());
                    VerifyBackend(reply, true);
                    if (reply.ContainsKey("helperPerformance")) metrics["helperPerformance"] = reply["helperPerformance"];
                    if (reply.ContainsKey("capturePerformance")) metrics["capturePerformance"] = reply["capturePerformance"];
                    if (reply.ContainsKey("captureHealth")) metrics["captureHealth"] = reply["captureHealth"];
                    Assert((bool)reply["ok"] && process.ExitCode == 0, "Cross-peer selection failed or was cancelled.");
                    metrics["nativeBackend"] = reply.ContainsKey("nativeBackend") ? reply["nativeBackend"] : "legacy-source-compiled-cli";
                    if (reply.ContainsKey("captureHealth")) {
                        Dictionary<string, object> health = (Dictionary<string, object>)reply["captureHealth"];
                        Assert(inputBackend == "planeOnly" || (Convert.ToInt64(health["hookMouseDowns"]) > 0 && Convert.ToInt64(health["hookMouseUps"]) > 0),
                            "Cross-peer visible borders did not prove owned hook down/up.");
                        Assert(!health.ContainsKey("mismatchKind") || Convert.ToInt64(health["mismatchKind"]) == 0, "A real held cross-peer drag caused a health mismatch.");
                        metrics["captureHealth"] = health;
                    }
                    using (MemoryStream bytes = new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))
                    using (Bitmap image = new Bitmap(bytes)) {
                        Assert(image.Width == last.X - first.X && image.Height == last.Y - first.Y, "Cross-peer free ROI dimensions changed.");
                        Color a = image.GetPixel(10, image.Height - 10), b = image.GetPixel(image.Width - 10, 10);
                        Assert(Math.Abs(a.R-liveA.R) <= 2 && Math.Abs(a.G-liveA.G) <= 2 && Math.Abs(a.B-liveA.B) <= 2 &&
                            Math.Abs(b.R-liveB.R) <= 2 && Math.Abs(b.G-liveB.G) <= 2 && Math.Abs(b.B-liveB.B) <= 2,
                            "Cross-peer screenshot did not retain both newly changed generated sources.");
                        for (int y = 0; y < image.Height; y++) for (int x = 0; x < image.Width; x++) {
                            Color pixel = image.GetPixel(x,y);
                            Assert(!(Math.Abs(pixel.R-45) <= 2 && Math.Abs(pixel.G-145) <= 2 && Math.Abs(pixel.B-255) <= 2),
                                "A blue screen/hover/selection hint pixel entered the cross-peer capture.");
                        }
                        metrics["capturedPhysicalWidth"] = image.Width; metrics["capturedPhysicalHeight"] = image.Height;
                    }
                    RequireFixtureForeground(context, "peer-capture-complete");
                    OnUi(form, delegate { Assert(originButtons == 0 && peerButtons == 0 && peerClicks == 0,
                        "Capture down/up or click reached an underlying generated peer button/window."); });
                    Assert(ReadyOverlays(process.Id) == 0 && InputPlanes(process.Id,false).Count == 0, "Cross-peer helper left capture borders alive.");
                    metrics["mode"] = context.Mode; metrics["passed"] = true; metrics["foregroundPreserved"] = true;
                    metrics["independentOrdinaryPeers"] = true; metrics["sourceAHwnd"] = WindowId(form.Handle); metrics["sourceBHwnd"] = WindowId(peerHwnd);
                    metrics["sourceProcessId"] = Process.GetCurrentProcess().Id; metrics["helperProcessId"] = process.Id;
                    metrics["startPhysicalPoint"] = new int[] { first.X, first.Y }; metrics["endPhysicalPoint"] = new int[] { last.X, last.Y };
                    metrics["underlyingMouseEvents"] = originButtons + peerButtons; metrics["underlyingButtonClicks"] = peerClicks;
                    metrics["hoverHiddenDuringDrag"] = true; metrics["blueHintPixelsInCapture"] = 0; metrics["heldDragMilliseconds"] = 900;
                    return metrics;
                } finally {
                    PreserveExitedHelper(context,process,output,metrics);
                    if (leftHeld) {
                        // Failure may activate peer B when interception is the
                        // very behavior under test. Release only over exact
                        // independently verified fixture A/B HWNDs, never any
                        // foreign foreground window, before killing the helper.
                        IntPtr foreground = GetForegroundWindow(); uint owner;
                        GetWindowThreadProcessId(foreground, out owner);
                        if ((foreground == form.Handle || foreground == peerHwnd) && owner == Process.GetCurrentProcess().Id) {
                            INPUT release = new INPUT(); release.data.mouse.flags = 0x0004;
                            SendInput(1, new INPUT[] { release }, Marshal.SizeOf(typeof(INPUT)));
                        }
                    }
                    if (!process.HasExited) { process.Kill(); process.WaitForExit(3000); }
                }
            }
        } finally {
            OnUi(form, delegate {
                if (peer != null) { peer.Close(); peer.Dispose(); }
                form.MouseDown -= sourceEvents; form.MouseUp -= sourceEvents;
                if (originButton != null) { form.Controls.Remove(originButton); originButton.Dispose(); }
                form.FormBorderStyle = previousBorder; form.Bounds = previousBounds;
            });
        }
    }
    public static Dictionary<string, object> Run(string helper, string assembly, bool performance, bool legacy, string backend) {
        requireInputPlanes = !legacy; inputBackend = backend; failedPlaneComposition = null;
        Assert(!assembly.Contains("\""), "Invalid native DLL path.");
        nativeArguments = String.IsNullOrEmpty(assembly) ? "" : " -NativeAssemblyPath \"" + assembly + "\"";
        if (performance) nativeArguments += " -PerformanceDiagnostics";
        if (backend == "planeOnly") nativeArguments += " -InputBackend planeOnly";
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        Assert(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Fixture could not establish physical per-monitor coordinates.");
        Dictionary<string, object> report = new Dictionary<string, object>();
        List<Dictionary<string, object>> trials = new List<Dictionary<string, object>>();
        report["ok"] = false; report["trials"] = trials;
        report["requiredInputPlanes"] = requireInputPlanes; report["requestedInputBackend"] = inputBackend;
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
                        report["crossPeerCapture"] = CrossPeerTrial(context, helper);
                        report["crossPeerCapturePassed"] = true;
                        report["forcedPlaneOnlyEndToEndPassed"] = requireInputPlanes && inputBackend=="planeOnly";
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
                        if (failedPlaneComposition != null) { failedPlaneComposition["stage"] = context.Stage; report["failedPlaneComposition"] = failedPlaneComposition; }
                        report["foregroundAtFailure"] = context.ForegroundFailure ?? ForegroundMetadata(context, GetForegroundWindow());
                        if (context.LastEdges != null) report["lastObservedEdges"] = context.LastEdges;
                        if (context.LastHelperDiagnostics != null) report["lastHelperDiagnostics"] = context.LastHelperDiagnostics;
                        if (context.HoverTrial != null) report["partialHoverTrial"] = context.HoverTrial;
                        if (context.CrossPeerTrial != null) report["crossPeerCapture"] = context.CrossPeerTrial;
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
    $result = [EchoLingoLiveCaptureSmoke]::Run($HelperPath, $NativeAssemblyPath, [bool]$PerformanceDiagnostics, [bool]$LegacyBaseline, $InputBackend)
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 10 -Compress))
    if (-not $result['ok']) { exit 1 }
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    [Console]::Out.WriteLine((@{ ok = $false; error = $message; clipboardAccessed = $false; userContentCaptured = $false } | ConvertTo-Json -Compress))
    exit 1
}
