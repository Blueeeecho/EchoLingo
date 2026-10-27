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
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT rectangle);
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
    static bool BordersAboveSource(int processId, IntPtr source) {
        int borders = 0, steps = 0;
        for (IntPtr window = GetWindow(source, 3); window != IntPtr.Zero && steps++ < 4096; window = GetWindow(window, 3)) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == processId && IsWindowVisible(window)) borders++;
        }
        return borders == 4;
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
    static Dictionary<string, object> Trial(TrialContext context, string helper, string mode, Color liveColor) {
        Form form = context.Source;
        context.Mode = mode; context.Stage = "prepare-generated-source"; context.HelperProcessId = 0; context.ForegroundFailure = null;
        context.GeneratedLayerHwnd = IntPtr.Zero;
        Form layer = null; int layerMouseEvents = 0;
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
                    DateTime deadline = DateTime.UtcNow.AddSeconds(25);
                    // Before dragging only the pointer display has four thin blue
                    // edge HWNDs; inactive displays have no visible border.
                    while (!process.HasExited && ReadyOverlays(process.Id) != 4 && DateTime.UtcNow < deadline) Thread.Sleep(30);
                    Assert(!process.HasExited && ReadyOverlays(process.Id) == 4, "The pointer display's four live thin border windows did not become ready.");
                    context.Stage = "inspect-ready-overlays";
                    int readyCount; long readyLargest;
                    metrics["readyVisibleBorderAreaPixels"] = BorderArea(process.Id, out readyCount, out readyLargest);
                    metrics["readyVisibleBorderWindowCount"] = readyCount; metrics["readyLargestSurfacePixels"] = readyLargest;
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
                        while (!BordersAboveSource(process.Id, layer.Handle) && DateTime.UtcNow < raisedDeadline) Thread.Sleep(20);
                        Assert(BordersAboveSource(process.Id, layer.Handle), "Capture borders did not passively recover above the ordinary topmost source.");
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
                        metrics["draggingVisibleBorderAreaPixels"] = BorderArea(process.Id, out draggingCount, out draggingLargest);
                        metrics["draggingVisibleBorderWindowCount"] = draggingCount; metrics["draggingLargestSurfacePixels"] = draggingLargest;
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
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 8 -Compress))
    if (-not $result['ok']) { exit 1 }
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    [Console]::Out.WriteLine((@{ ok = $false; error = $message; clipboardAccessed = $false; userContentCaptured = $false } | ConvertTo-Json -Compress))
    exit 1
}
