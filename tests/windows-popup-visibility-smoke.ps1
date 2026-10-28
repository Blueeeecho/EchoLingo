# Real new-app visibility checks for an explicitly isolated Windows desktop.
# Refuses existing app processes/data; never reads daily settings or credentials.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath, [switch]$IsolatedTestSession)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) {
        throw 'ISOLATION_REQUIRED: Use -IsolatedTestSession only in a dedicated unlocked test account/VM with no existing EchoLingo data.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw 'TEST_APARTMENT: Run Windows powershell.exe -NoProfile -STA -File tests/windows-popup-visibility-smoke.ps1.'
    }
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions, System.Management, UIAutomationClient, UIAutomationTypes
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

public static class EchoLingoPopupVisibilitySmoke {
    const string Identifier = "io.github.blueeeecho.echolingo", Marker = ".echolingo-visibility-owned";
    // Pinned tauri-runtime-wry2.12.3 overrides the Tao default with this
    // class (src/lib.rs:790), confirmed by the actual Windows HWND inventory.
    // The global-hotkey helper is also a top-level HWND with default size.
    const string MainWindowClass = "Tauri Window";
    const string OcrSource = "EchoLingo OCR visibility 2468";
    delegate bool Enumerate(IntPtr window, IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(Enumerate callback, IntPtr unused);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window, uint kind);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("kernel32.dll")] static extern void SetLastError(uint error);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT rectangle);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out POINT point);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr memory);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool CreateDirectory(string path, IntPtr security);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct INPUTDATA { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTDATA data; }
    sealed class Owner : IWin32Window {
        readonly IntPtr handle;
        public Owner(IntPtr window) { handle = window; }
        public IntPtr Handle { get { return handle; } }
    }

    static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    static void Wait(Func<bool> condition, int milliseconds, string failure) {
        Stopwatch watch = Stopwatch.StartNew();
        while (watch.ElapsedMilliseconds < milliseconds) { if (condition()) return; Thread.Sleep(10); }
        throw new InvalidOperationException(failure);
    }
    static void Ui(Form form, Action action) { if (form.InvokeRequired) form.Invoke(action); else action(); }
    static INPUT Key(ushort key, bool up) { INPUT value = new INPUT(); value.type = 1; value.data.key.vk = key; value.data.key.flags = up ? 2U : 0U; return value; }
    static void Send(INPUT[] input) { Require(SendInput((uint)input.Length, input, Marshal.SizeOf(typeof(INPUT))) == input.Length, "Generated fixture input was rejected."); }
    static void Shortcut(Form form, ushort key) {
        Require(GetForegroundWindow() == form.Handle, "Generated source is not foreground; no input sent elsewhere.");
        Send(new INPUT[] { Key(0x12, false), Key(key, false), Key(key, true), Key(0x12, true) });
    }
    static bool MainWindowCandidate(IntPtr window, int process) {
        uint owner; GetWindowThreadProcessId(window, out owner);
        if (window == IntPtr.Zero || owner != process || GetAncestor(window, 2) != window) return false;
        StringBuilder name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
        return name.ToString() == MainWindowClass;
    }
    static List<IntPtr> MainWindowCandidates(int process) {
        List<IntPtr> candidates = new List<IntPtr>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            if (MainWindowCandidate(window, process)) candidates.Add(window);
            return true;
        }, IntPtr.Zero);
        return candidates;
    }
    static IntPtr MainWindow(int process) {
        List<IntPtr> candidates = MainWindowCandidates(process);
        return candidates.Count == 1 ? candidates[0] : IntPtr.Zero;
    }
    static void RequireUniqueOwnedMainWindow(Process app, IntPtr main) {
        List<IntPtr> candidates = MainWindowCandidates(app.Id);
        Require(candidates.Count == 1 && candidates[0] == main, "Native preparation refused: no unique root HWND of the pinned Tao class belongs to the fixture-started PID.");
    }
    static Dictionary<string, object> OwnTopLevelWindowInventory(Process app) {
        const int maximum = 32; bool truncated = false;
        List<Dictionary<string, object>> windows = new List<Dictionary<string, object>>();
        if (app != null) EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; uint thread = GetWindowThreadProcessId(window, out owner);
            if (owner != app.Id) return true;
            if (windows.Count >= maximum) { truncated = true; return false; }
            StringBuilder name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
            Dictionary<string, object> value = new Dictionary<string, object> {
                { "hwnd", "0x" + window.ToInt64().ToString("X") }, { "processId", owner }, { "threadId", thread },
                { "class", name.ToString() }, { "visible", IsWindowVisible(window) },
                { "rootHwnd", "0x" + GetAncestor(window, 2).ToInt64().ToString("X") },
                { "mainCandidate", MainWindowCandidate(window, app.Id) }
            };
            RECT bounds;
            if (GetWindowRect(window, out bounds)) value["size"] = new int[] { bounds.right - bounds.left, bounds.bottom - bounds.top };
            else value["boundsUnavailable"] = true;
            windows.Add(value); return true;
        }, IntPtr.Zero);
        return new Dictionary<string, object> { { "maximum", maximum }, { "truncated", truncated }, { "windows", windows } };
    }
    static IntPtr SingleInstanceWindow(int process) {
        IntPtr result = IntPtr.Zero; int count = 0;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == process) {
                StringBuilder name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
                if (name.ToString() == Identifier + "-sic") { result = window; count++; }
            }
            return true;
        }, IntPtr.Zero);
        Require(count == 1, "Dedicated app PID has no unique single-instance target HWND.");
        return result;
    }
    static Dictionary<string, object> WindowIdentityMetadata(IntPtr window) {
        uint process; uint thread = GetWindowThreadProcessId(window, out process);
        StringBuilder name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
        IntPtr root = GetAncestor(window, 2);
        IntPtr owner = GetWindow(window, 4), rootOwner = GetAncestor(window, 3);
        StringBuilder rootName = new StringBuilder(256); GetClassName(root, rootName, rootName.Capacity);
        // Public window identity only, including on an unexpected foreground.
        // Never query titles, UIA contents, process paths or source text.
        return new Dictionary<string, object> {
            { "hwnd", "0x" + window.ToInt64().ToString("X") }, { "processId", process }, { "threadId", thread },
            { "class", name.ToString() }, { "rootHwnd", "0x" + root.ToInt64().ToString("X") }, { "rootClass", rootName.ToString() },
            { "directOwnerHwnd", "0x" + owner.ToInt64().ToString("X") },
            { "rootOwnerHwnd", "0x" + rootOwner.ToInt64().ToString("X") }, { "nativeVisible", window != IntPtr.Zero && IsWindowVisible(window) }
        };
    }
    static Dictionary<string, object> OwnedLifecycleSnapshot(IntPtr main, Form owned, string phase, double elapsed) {
        Dictionary<string, object> snapshot = new Dictionary<string, object> {
            { "phase", phase }, { "elapsedMs", elapsed }, { "main", WindowIdentityMetadata(main) },
            { "foreground", WindowIdentityMetadata(GetForegroundWindow()) },
            { "ownedHandleCreated", owned.IsHandleCreated }, { "ownedManagedVisible", owned.Visible }
        };
        // Do not create a handle just for diagnosis: that would change the
        // very owner/creation/activation sequence being measured.
        if (owned.IsHandleCreated) {
            IntPtr window = owned.Handle;
            snapshot["owned"] = WindowIdentityMetadata(window);
            snapshot["directOwnerMatchesMain"] = GetWindow(window, 4) == main;
            snapshot["rootOwnerMatchesMain"] = GetAncestor(window, 3) == main;
        }
        return snapshot;
    }
    static void PrepareSourceClickOnce(Form form, TextBox source, IntPtr main, Dictionary<string, object> report) {
        Require(!IsWindowVisible(main), "Source click preparation requires the real app window to be hidden.");
        Dictionary<string, object> preparation = new Dictionary<string, object> {
            { "isPopupAcceptance", false }, { "clickPairsSent", 0 }, { "foregroundBefore", WindowIdentityMetadata(GetForegroundWindow()) }
        };
        report["initialSourceClickPreparation"] = preparation;
        POINT point = new POINT(); IntPtr sourceHandle = IntPtr.Zero, formHandle = IntPtr.Zero;
        Ui(form, delegate {
            form.WindowState = FormWindowState.Normal;
            // HWND_TOP for this ordinary generated form only. No TOPMOST,
            // activation request or product-window mutation in preparation.
            Require(SetWindowPos(form.Handle, IntPtr.Zero, 0, 0, 0, 0, 0x1 | 0x2 | 0x10), "Could not raise the ordinary generated source window for its one setup click.");
            sourceHandle = source.Handle; formHandle = form.Handle;
            Point center = source.PointToScreen(new Point(source.ClientSize.Width / 2, source.ClientSize.Height / 2));
            point.x = center.X; point.y = center.Y;
        });
        Require(SetCursorPos(point.x, point.y), "Could not position the one generated source setup click.");
        IntPtr target = WindowFromPoint(point); uint owner; GetWindowThreadProcessId(target, out owner);
        preparation["target"] = WindowIdentityMetadata(target);
        Require(target == sourceHandle && owner == Process.GetCurrentProcess().Id && GetAncestor(target, 2) == formHandle,
            "The one setup click does not hit the exact generated source editor/PID/root; no input sent.");
        Require(!IsWindowVisible(main), "App became visible before source preparation; no click sent.");
        INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2;
        INPUT up = down; up.data.mouse.flags = 4;
        Send(new INPUT[] { down, up }); preparation["clickPairsSent"] = 1;
        Wait(delegate {
            bool ready = false;
            Ui(form, delegate { ready = GetForegroundWindow() == formHandle && form.ContainsFocus && source.Focused; });
            preparation["foregroundAfter"] = WindowIdentityMetadata(GetForegroundWindow());
            preparation["actualSourceReady"] = ready;
            return ready;
        }, 3000, "One generated source setup click did not establish actual foreground/editor focus; no shortcut sent.");
        Require(!IsWindowVisible(main), "Product became visible during source-only preparation; popup case not tested.");
    }
    static Dictionary<string, object> NativeWindowMetadata(Process app, IntPtr window) {
        uint owner; uint thread = GetWindowThreadProcessId(window, out owner);
        bool own = app != null && owner == app.Id && window != IntPtr.Zero;
        Dictionary<string, object> value = new Dictionary<string, object> {
            { "hwnd", "0x" + window.ToInt64().ToString("X") }, { "processId", owner }, { "threadId", thread },
            { "ownedByStartedApp", own }, { "visible", window != IntPtr.Zero && IsWindowVisible(window) }
        };
        if (!own) return value; // Never probe a foreign/expired/reused HWND.
        StringBuilder name = new StringBuilder(256); GetClassName(window, name, name.Capacity); value["class"] = name.ToString();
        UIntPtr result; SetLastError(0); Stopwatch ping = Stopwatch.StartNew();
        // WM_NULL only, exact own HWND, bounded 200ms. This observes sent-
        // message responsiveness, not frontend/IPC/callback completion.
        IntPtr sent = SendMessageTimeout(window, 0, UIntPtr.Zero, IntPtr.Zero, 0x0001 | 0x0002 | 0x0020, 200, out result);
        int error = Marshal.GetLastWin32Error();
        value["wmNullResponded"] = sent != IntPtr.Zero; value["wmNullElapsedMs"] = ping.Elapsed.TotalMilliseconds;
        value["wmNullLastError"] = error; value["wmNullMessageResult"] = result.ToUInt64(); value["wmNullTimeoutMs"] = 200;
        return value;
    }
    static void Click(int x, int y, Form source, IntPtr app, bool requireSource) {
        IntPtr foreground = GetForegroundWindow();
        Require(foreground == source.Handle || foreground == app, "Unexpected foreground; generated click aborted.");
        if (requireSource) Require(foreground == source.Handle, "Passive popup activated the app before the source click.");
        Require(SetCursorPos(x, y), "Could not position the generated fixture pointer.");
        INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2;
        INPUT up = down; up.data.mouse.flags = 4;
        // Down/up in the same SendInput call deliberately exercises clicks
        // shorter than a polling interval. The click must reach the source.
        Send(new INPUT[] { down, up });
    }
    static Dictionary<string, object> ClickGeneratedBody(Form target, IntPtr app, Func<int> clickCount, Dictionary<string, object> report, string label) {
        Dictionary<string, object> click = new Dictionary<string, object> { { "case", label }, { "clickPairsSent", 0 }, { "productHiddenObservedAfterClick", false } };
        if (!report.ContainsKey("generatedClientClicks")) report["generatedClientClicks"] = new List<Dictionary<string, object>>();
        ((List<Dictionary<string, object>>)report["generatedClientClicks"]).Add(click);
        POINT point = new POINT(); IntPtr expected = IntPtr.Zero;
        Ui(target, delegate {
            Require(target.ClientSize.Width > 48 && target.ClientSize.Height > 48, "Generated client is too small for its empty-body click.");
            // Actual client coordinates, not the form's requested outer Bounds:
            // WinForms placement, borders and display scaling may differ.
            Point body = target.PointToScreen(new Point(24, target.ClientSize.Height - 24));
            point.x = body.X; point.y = body.Y; expected = target.Handle;
        });
        Require(IsWindowVisible(app), "Popup was already hidden before the generated outside click; outside behavior not tested.");
        IntPtr foreground = GetForegroundWindow();
        Require(foreground == expected || foreground == app, "Neither generated target nor the app is foreground before the outside click; no input sent.");
        RECT bounds; Require(GetWindowRect(app, out bounds), "Product bounds unavailable before generated outside click.");
        Require(point.x < bounds.left || point.x >= bounds.right || point.y < bounds.top || point.y >= bounds.bottom,
            "Generated client point is not outside the actual product bounds; no input sent.");
        Require(SetCursorPos(point.x, point.y), "Could not position the generated client click.");
        IntPtr hit = WindowFromPoint(point); uint owner; GetWindowThreadProcessId(hit, out owner);
        click["screenPoint"] = new int[] { point.x, point.y }; click["expectedTarget"] = WindowIdentityMetadata(expected);
        click["actualTarget"] = WindowIdentityMetadata(hit);
        Require(hit == expected && owner == Process.GetCurrentProcess().Id && GetAncestor(hit, 2) == expected,
            "Generated client click missed its exact Form HWND/PID/root; no input sent.");
        int before = clickCount(); click["targetMouseDownCountBefore"] = before;
        click["targetMouseDownCountAfter"] = before;
        INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2;
        INPUT up = down; up.data.mouse.flags = 4;
        Stopwatch watch = Stopwatch.StartNew();
        Send(new INPUT[] { down, up }); click["clickPairsSent"] = 1;
        Wait(delegate {
            int after = clickCount(); click["targetMouseDownCountAfter"] = after;
            if (!IsWindowVisible(app) && !(bool)click["productHiddenObservedAfterClick"]) {
                click["productHiddenObservedAfterClick"] = true; click["hiddenObservedMs"] = watch.Elapsed.TotalMilliseconds;
            }
            return after > before;
        }, 2000, "The exact generated target did not observe its mouse-down; input delivery is unproven (see hit-test/count/visibility metadata).");
        click["targetMouseDownDelivered"] = true;
        return click;
    }
    static int ParentProcess(uint process) {
        using (ManagementObjectSearcher query = new ManagementObjectSearcher("SELECT ParentProcessId FROM Win32_Process WHERE ProcessId=" + process))
            foreach (ManagementObject item in query.Get()) using (item) return Convert.ToInt32(item["ParentProcessId"]);
        return 0;
    }
    static string SourceValue(IntPtr main) {
        AutomationElement edit = AutomationElement.FromHandle(main).FindFirst(TreeScope.Descendants, new AndCondition(
            new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit),
            new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty, "source-text"), new PropertyCondition(AutomationElement.NameProperty, "\u539f\u6587"))));
        object pattern;
        return edit != null && !edit.Current.IsOffscreen && edit.TryGetCurrentPattern(ValuePattern.Pattern, out pattern)
            ? ((ValuePattern)pattern).Current.Value : null;
    }
    static bool OcrSourceMatches(IntPtr main) {
        return String.Equals(SourceValue(main), OcrSource, StringComparison.OrdinalIgnoreCase);
    }
    static void OcrThenSameForegroundClick(Form form, Panel image, Process app, IntPtr main, Func<int> sourceClicks, Func<int> imageEvents, Dictionary<string, object> report) {
        Dictionary<string, object> result = new Dictionary<string, object> { { "shortcutPresses", 0 }, { "dragPairsSent", 0 }, { "outsideClickPairsSent", 0 } };
        report["ocrSameForegroundOutsideClick"] = result;
        Require(!IsWindowVisible(main), "OCR same-source case requires its own hidden-popup baseline.");
        Require(GetForegroundWindow() == form.Handle, "Generated OCR source is not foreground; no shortcut sent.");
        result["sourceForegroundBeforeCapture"] = WindowIdentityMetadata(GetForegroundWindow());
        Point first = Point.Empty, last = Point.Empty;
        Ui(form, delegate { first = image.PointToScreen(new Point(2, 2)); last = image.PointToScreen(new Point(image.Width - 2, image.Height - 2)); });
        Require(SetCursorPos(first.X, first.Y), "Cannot position pointer over generated OCR image.");
        POINT start = new POINT(); start.x = first.X; start.y = first.Y;
        Require(GetAncestor(WindowFromPoint(start), 2) == form.Handle, "Generated OCR image is occluded; no shortcut sent.");
        int before = imageEvents();
        Shortcut(form, 0x53); result["shortcutPresses"] = 1;
        IntPtr plane = IntPtr.Zero; uint helper = 0;
        Wait(delegate {
            Require(GetForegroundWindow() == form.Handle, "OCR picker activated a different window.");
            IntPtr candidate = WindowFromPoint(start); uint owner; GetWindowThreadProcessId(candidate, out owner);
            StringBuilder name = new StringBuilder(256); GetClassName(candidate, name, name.Capacity);
            if (name.ToString() != "EchoLingoCaptureInputPlane-" + owner) return false;
            Require(ParentProcess(owner) == app.Id, "OCR input plane is not a direct child of this actual app.");
            plane = candidate; helper = owner; return true;
        }, 25000, "Actual Alt+S did not create its generated-source input plane.");
        result["helperProcessId"] = helper; result["inputPlaneHwnd"] = "0x" + plane.ToInt64().ToString("X");
        Require(GetForegroundWindow() == form.Handle, "Source foreground changed before the OCR drag.");
        Rectangle desktop = SystemInformation.VirtualScreen;
        INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2;
        INPUT move = new INPUT(); move.type = 0; move.data.mouse.flags = 0x8000 | 0x4000 | 1;
        move.data.mouse.x = (int)Math.Round((last.X - desktop.Left) * 65535.0 / (desktop.Width - 1));
        move.data.mouse.y = (int)Math.Round((last.Y - desktop.Top) * 65535.0 / (desktop.Height - 1));
        INPUT up = down; up.data.mouse.flags = 4;
        Send(new INPUT[] { down, move, up }); result["dragPairsSent"] = 1;
        Wait(delegate { Require(GetForegroundWindow() == form.Handle, "OCR result activated a different window."); return IsWindowVisible(main) && OcrSourceMatches(main); }, 50000, "Actual WinRT OCR did not show the exact generated source in the passive popup.");
        result["generatedImageMouseEventsBefore"] = before; result["generatedImageMouseEventsAfter"] = imageEvents();
        Require(imageEvents() == before, "OCR drag leaked input into the generated image control.");
        Require(!IsWindowVisible(plane), "OCR input plane remains visible after the source result.");
        result["actualWinRtSourceMatched"] = true; result["sourceForegroundBeforeOutsideClick"] = WindowIdentityMetadata(GetForegroundWindow());
        Dictionary<string, object> click = ClickGeneratedBody(form, main, sourceClicks, report, "ocr-same-foreground-source-outside-click");
        result["outsideClickPairsSent"] = 1;
        Wait(delegate { Require(GetForegroundWindow() == form.Handle, "Same-source outside click changed foreground unexpectedly."); return !IsWindowVisible(main); }, 2000, "One click in the same foreground OCR source did not hide the unpinned popup.");
        click["productHiddenObservedAfterClick"] = true; result["sourceForegroundUnchanged"] = true; result["passed"] = true;
        report["ocrSameForegroundOutsideClickPassed"] = true; report["screenshotsTested"] = true;
    }
    static void DragOwnToolbar(IntPtr app) {
        Require(GetForegroundWindow() == app, "Own input popup is not foreground; toolbar drag aborted.");
        RECT before; Require(GetWindowRect(app, out before), "Own toolbar bounds unavailable.");
        int x = (before.left + before.right) / 2, y = before.top + 16;
        Require(SetCursorPos(x, y), "Could not position generated toolbar gesture.");
        INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2; Send(new INPUT[] { down });
        Thread.Sleep(40);
        for (int step = 1; step <= 4; step++) { SetCursorPos(x + step * 10, y + step * 5); Thread.Sleep(20); }
        INPUT up = down; up.data.mouse.flags = 4; Send(new INPUT[] { up });
        Wait(delegate { RECT after; return GetWindowRect(app, out after) && (after.left != before.left || after.top != before.top); }, 2000, "Native toolbar did not actually move; drag retention was not tested.");
        Require(IsWindowVisible(app), "An inside toolbar down was reclassified outside after native movement.");
    }
    static void ResizeOwnEdge(IntPtr app) {
        Require(GetForegroundWindow() == app, "Own popup not foreground; resize aborted.");
        RECT before; Require(GetWindowRect(app, out before), "Own resize bounds unavailable.");
        int x = before.right - 2, y = (before.top + before.bottom) / 2;
        Require(SetCursorPos(x, y), "Could not position generated resize gesture.");
        INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2; Send(new INPUT[] { down });
        Thread.Sleep(40);
        for (int step = 1; step <= 4; step++) { SetCursorPos(x + step * 5, y); Thread.Sleep(20); }
        INPUT up = down; up.data.mouse.flags = 4; Send(new INPUT[] { up });
        Wait(delegate { RECT after; return GetWindowRect(app, out after) && after.right - after.left != before.right - before.left; }, 2000, "Native edge did not actually resize; retention was not tested.");
        Require(IsWindowVisible(app), "An inside edge down was reclassified outside after native resizing.");
    }
    static AutomationElement Element(IntPtr app, string name) {
        return AutomationElement.FromHandle(app).FindFirst(TreeScope.Descendants,
            new PropertyCondition(AutomationElement.NameProperty, name));
    }
    static void Invoke(IntPtr app, string name) {
        AutomationElement element = null;
        Wait(delegate { element = Element(app, name); return element != null; }, 5000, "New app accessibility control missing: " + name);
        object pattern;
        if (element.TryGetCurrentPattern(InvokePattern.Pattern, out pattern)) ((InvokePattern)pattern).Invoke();
        else if (element.TryGetCurrentPattern(TogglePattern.Pattern, out pattern)) ((TogglePattern)pattern).Toggle();
        else if (element.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out pattern)) ((ExpandCollapsePattern)pattern).Expand();
        else throw new InvalidOperationException("Control has no Invoke, Toggle or ExpandCollapse action: " + name);
    }
    static Dictionary<string, object> ReadinessMetadata(Process app, IntPtr main) {
        Dictionary<string, object> value = new Dictionary<string, object>();
        value["mainHwnd"] = "0x" + main.ToInt64().ToString("X");
        value["nativeVisible"] = main != IntPtr.Zero && IsWindowVisible(main);
        IntPtr foreground = GetForegroundWindow(); uint foregroundProcess; GetWindowThreadProcessId(foreground, out foregroundProcess);
        value["foregroundHwnd"] = "0x" + foreground.ToInt64().ToString("X"); value["foregroundProcessId"] = foregroundProcess;
        value["foregroundWindow"] = WindowIdentityMetadata(foreground);
        value["appExited"] = app == null || app.HasExited;
        Dictionary<string, object> native = NativeWindowMetadata(app, main); value["nativeProbe"] = native;
        if (!native.ContainsKey("wmNullResponded") || !(bool)native["wmNullResponded"]) { value["uiaSkipped"] = "Own native HWND unavailable or WM_NULL did not respond within 200ms."; return value; }
        RECT bounds; if (GetWindowRect(main, out bounds)) value["nativeSize"] = new int[] { bounds.right - bounds.left, bounds.bottom - bounds.top };
        try {
            AutomationElement root = AutomationElement.FromHandle(main);
            value["uiaRootControlType"] = root.Current.ControlType.ProgrammaticName;
            value["uiaRootFrameworkId"] = root.Current.FrameworkId;
            value["uiaRootProcessId"] = root.Current.ProcessId;
        } catch (Exception error) { value["uiaRootMetadataError"] = error.GetType().Name; }
        List<Dictionary<string, object>> controls = new List<Dictionary<string, object>>();
        // Read only static fixture-targeted control metadata. Never inspect
        // source values, provider fields, clipboard or arbitrary UIA names.
        foreach (string name in new string[] { "\u8fd4\u56de\u7ffb\u8bd1", "\u9489\u4f4f\u7a97\u53e3", "\u9690\u85cf\u7a97\u53e3", "\u66f4\u591a" }) {
            Dictionary<string, object> control = new Dictionary<string, object> { { "name", name } };
            try {
                AutomationElement element = Element(main, name); control["found"] = element != null;
                if (element != null) {
                    control["controlType"] = element.Current.ControlType.ProgrammaticName;
                    control["enabled"] = element.Current.IsEnabled; control["offscreen"] = element.Current.IsOffscreen;
                    object pattern; control["supportsInvoke"] = element.TryGetCurrentPattern(InvokePattern.Pattern, out pattern);
                    control["supportsToggle"] = element.TryGetCurrentPattern(TogglePattern.Pattern, out pattern);
                    bool expand = element.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out pattern);
                    control["supportsExpandCollapse"] = expand;
                    if (expand) control["expandCollapseState"] = ((ExpandCollapsePattern)pattern).Current.ExpandCollapseState.ToString();
                }
            } catch (Exception error) { control["metadataError"] = error.GetType().Name; }
            controls.Add(control);
        }
        value["staticControls"] = controls;
        return value;
    }
    static string KnownFolder(string id) {
        Guid folder = new Guid(id); IntPtr value;
        Require(SHGetKnownFolderPath(ref folder, 0, IntPtr.Zero, out value) == 0, "Could not resolve the dedicated test account's data directory.");
        try { return Marshal.PtrToStringUni(value); } finally { CoTaskMemFree(value); }
    }
    static void Claim(string path, string token, List<string> owned) {
        Require(CreateDirectory(path, IntPtr.Zero), "Existing application data or create failure; no existing data will be read or overwritten.");
        File.WriteAllText(Path.Combine(path, Marker), token, new UTF8Encoding(false)); owned.Add(path);
    }
    static void Clean(string path, string token) {
        if (!Directory.Exists(path)) return;
        Require((File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0, "Owned test directory became a link; preserved.");
        Require(File.ReadAllText(Path.Combine(path, Marker)) == token, "Owned test marker changed; directory preserved.");
        for (int attempt = 0; attempt < 50; attempt++) {
            try { Directory.Delete(path, true); return; }
            catch (IOException) { if (attempt == 49) throw; }
            catch (UnauthorizedAccessException) { if (attempt == 49) throw; }
            Thread.Sleep(100);
        }
    }

    public static string Run(string executable) {
        foreach (Process existing in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable))) using (existing) {
            Require(existing.HasExited, "An EchoLingo process already runs; refused to touch the daily app.");
        }
        string token = Guid.NewGuid().ToString("N"), root = Path.Combine(Path.GetTempPath(), "echolingo-visibility-" + token);
        List<string> owned = new List<string>(); Process app = null;
        Dictionary<string, object> report = new Dictionary<string, object> { { "ok", false }, { "actualApplicationTested", false },
            { "windowsInteractiveTested", true }, { "fixtureReadsClipboard", false }, { "credentialsCreated", false },
            { "physicalWindows10Tested", false }, { "altTabKeySequenceTested", false }, { "screenshotsTested", false },
            { "earlyStartupHotkeyTested", false }, { "singleShortcutPerAction", true } };
        try {
            string roaming = Path.Combine(KnownFolder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"), Identifier);
            string local = Path.Combine(KnownFolder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"), Identifier);
            Claim(roaming, token, owned); Claim(local, token, owned); Claim(root, token, owned);
            JavaScriptSerializer json = new JavaScriptSerializer();
            Dictionary<string, object> settings = new Dictionary<string, object> {
                { "providers", new object[] { new Dictionary<string, object> { { "id", "offline-translation" }, { "name", "Generated visibility fixture offline" },
                    { "kind", "offline" }, { "baseUrl", "" }, { "model", "" }, { "enabled", true }, { "prompt", "" } } } },
                { "ocrProviders", new object[0] }, { "activeOcrProviderId", null }, { "sourceLanguage", "auto" }, { "targetLanguage", "auto" },
                { "languageDirectionVersion", 1 }, { "shortcutDefaultsVersion", 1 }, { "saveHistory", false }, { "maxHistory", 20 },
                { "theme", "light" }, { "autoHideSeconds", 0 }, { "shortcuts", new Dictionary<string, object> {
                    { "selection", "Alt+D" }, { "capture", "Alt+S" }, { "ocr", "Alt+Shift+S" }, { "silentOcr", "Alt+C" }, { "input", "Alt+A" } } }
            };
            File.WriteAllText(Path.Combine(roaming, "settings.json"), json.Serialize(settings), new UTF8Encoding(false));
            SetProcessDpiAwarenessContext(new IntPtr(-4));
            Require(Screen.PrimaryScreen.Bounds.Width >= 1024 && Screen.PrimaryScreen.Bounds.Height >= 600, "Generated desktop fixture needs at least 1024x600; no product failure inferred.");
            using (Form form = new Form()) using (TextBox source = new TextBox()) using (Panel image = new Panel()) {
                form.Text = "EchoLingo generated visibility source"; form.StartPosition = FormStartPosition.Manual; form.Bounds = new Rectangle(30, 120, 720, 420);
                source.Multiline = true; source.SetBounds(20, 20, 660, 100); source.Text = "EchoLingo popup visibility generated source 2468";
                image.SetBounds(20, 145, 660, 145); image.BackColor = Color.White;
                image.Paint += delegate(object sender, PaintEventArgs args) { using (Font font = new Font("Segoe UI", 26, FontStyle.Regular)) args.Graphics.DrawString(OcrSource, font, Brushes.Black, 12, 36); };
                int imageMouseEvents = 0; image.MouseDown += delegate { Interlocked.Increment(ref imageMouseEvents); }; image.MouseUp += delegate { Interlocked.Increment(ref imageMouseEvents); };
                form.Controls.Add(source); form.Controls.Add(image); int clicksReachedSource = 0; form.MouseDown += delegate { Interlocked.Increment(ref clicksReachedSource); };
                Func<int> sourceClickCount = delegate { return Interlocked.CompareExchange(ref clicksReachedSource, 0, 0); };
                bool done = false; Exception failure = null;
                form.FormClosing += delegate(object sender, FormClosingEventArgs args) { if (!done) args.Cancel = true; };
                form.Shown += delegate {
                    Thread worker = new Thread(delegate() {
                        POINT original; bool restorePointer = GetPhysicalCursorPos(out original);
                        IntPtr main = IntPtr.Zero; string stage = "start-application";
                        try {
                            Require(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Physical fixture coordinates unavailable.");
                            string childLocal = Path.Combine(root, "Local"), childTemp = Path.Combine(root, "Temp"); Directory.CreateDirectory(childLocal); Directory.CreateDirectory(childTemp);
                            ProcessStartInfo start = new ProcessStartInfo(executable); start.UseShellExecute = false; start.CreateNoWindow = true;
                            start.EnvironmentVariables["LOCALAPPDATA"] = childLocal; start.EnvironmentVariables["APPDATA"] = Path.Combine(root, "UnusedRoaming");
                            start.EnvironmentVariables["TEMP"] = childTemp; start.EnvironmentVariables["TMP"] = childTemp;
                            start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"] = Path.Combine(local, "fixture-webview");
                            app = Process.Start(start); report["actualApplicationTested"] = true; report["applicationProcessId"] = app.Id;
                            stage = "wait-native-input-idle";
                            try { Require(app.WaitForInputIdle(15000), "New app native message loop did not become input-idle."); }
                            catch (InvalidOperationException) { throw new InvalidOperationException("New app has no observable GUI message loop."); }
                            report["nativeInputIdleObserved"] = true;
                            stage = "wait-native-window";
                            Wait(delegate { Require(!app.HasExited, "New app exited before creating its native window."); main = MainWindow(app.Id); return main != IntPtr.Zero; }, 20000, "No unique root HWND of the pinned Tao class became available for the started app PID.");
                            Action sourceFocus = delegate {
                                Dictionary<string, object> focus = new Dictionary<string, object>();
                                report["lastSourceFocusPreparation"] = focus;
                                // Keep activation and focus on the actual source
                                // UI thread, as in the native/application/live
                                // fixtures. A worker's second foreground call
                                // is not the readiness condition. Do not retry
                                // activation or send a shortcut if denied.
                                Ui(form, delegate {
                                    form.WindowState = FormWindowState.Normal;
                                    form.Activate();
                                    focus["setForegroundReturned"] = SetForegroundWindow(form.Handle);
                                    source.Focus(); source.SelectAll();
                                    uint owner; uint thread = GetWindowThreadProcessId(form.Handle, out owner);
                                    focus["sourceHwnd"] = "0x" + form.Handle.ToInt64().ToString("X");
                                    focus["sourceProcessId"] = owner; focus["sourceUiThreadId"] = thread;
                                });
                                Wait(delegate {
                                    bool ready = false;
                                    Ui(form, delegate {
                                        IntPtr foreground = GetForegroundWindow(); uint owner;
                                        GetWindowThreadProcessId(foreground, out owner);
                                        focus["foregroundHwnd"] = "0x" + foreground.ToInt64().ToString("X");
                                        focus["foregroundProcessId"] = owner;
                                        focus["foregroundWindow"] = WindowIdentityMetadata(foreground);
                                        focus["sourceContainsFocus"] = form.ContainsFocus;
                                        focus["sourceControlFocused"] = source.Focused;
                                        ready = foreground == form.Handle && form.ContainsFocus && source.Focused;
                                        focus["actualSourceReady"] = ready;
                                    });
                                    return ready;
                                }, 3000, "Generated source did not become foreground with its editor focused; no shortcut was sent.");
                            };
                            Action moveApp = delegate { Require(SetWindowPos(main, IntPtr.Zero, Math.Max(300, Screen.PrimaryScreen.Bounds.Right - 720), 20, 0, 0, 0x1 | 0x4 | 0x10), "Could not position own app fixture."); };
                            // Native-only fixture preparation. This one owned-
                            // HWND show is explicitly NOT shortcut/presentation
                            // acceptance. All behavior cases below use the real
                            // single hotkey or real UI controls after close.
                            stage = "native-owned-window-preparation-once";
                            RequireUniqueOwnedMainWindow(app, main);
                            report["silentStartupObserved"] = !IsWindowVisible(main);
                            Require(!IsWindowVisible(main), "Fresh dedicated app did not start silently.");
                            Stopwatch preparation = Stopwatch.StartNew();
                            Require(ShowWindowAsync(main, 4), "One native SW_SHOWNOACTIVATE preparation request was rejected.");
                            report["nativePreparationIsShortcutAcceptance"] = false;
                            report["nativePreparationShowRequests"] = 1;
                            report["readinessSetup"] = "One ShowWindowAsync(SW_SHOWNOACTIVATE) of unique own main HWND; real UIA ready; real close IPC";
                            stage = "wait-preparation-native-visible";
                            Wait(delegate { Require(!app.HasExited, "New app exited during native preparation."); return IsWindowVisible(main); }, 5000, "Native preparation was queued, but the app window did not become visible.");
                            report["setupNativeVisibleObserved"] = true;
                            stage = "wait-preparation-accessibility-controls";
                            Wait(delegate { return Element(main, "\u9489\u4f4f\u7a97\u53e3") != null && Element(main, "\u9690\u85cf\u7a97\u53e3") != null; }, 15000, "Prepared native window is visible, but its real WebView pin/close controls did not become ready.");
                            report["nativePreparationObservedMs"] = preparation.Elapsed.TotalMilliseconds;
                            report["setupReadiness"] = ReadinessMetadata(app, main);
                            stage = "finish-native-preparation-by-real-close";
                            Invoke(main, "\u9690\u85cf\u7a97\u53e3"); Wait(delegate { return !IsWindowVisible(main); }, 5000, "Real close IPC did not hide the prepared popup.");
                            // A real user clicks/selects the source before Alt+D.
                            // This one source-only setup click occurs while the
                            // product is already hidden, so it cannot satisfy
                            // any outside-hide, pin or management assertion.
                            // Later sourceFocus calls never fall back to clicks.
                            stage = "initial-source-click-preparation-once";
                            PrepareSourceClickOnce(form, source, main, report);
                            stage = "passive-selected-text-outside-click";
                            sourceFocus(); Shortcut(form, 0x44);
                            Wait(delegate { return IsWindowVisible(main); }, 12000, "Selected-text popup did not show."); moveApp();
                            Require(GetForegroundWindow() == form.Handle, "Passive selected-text popup stole source foreground.");
                            Stopwatch outside = Stopwatch.StartNew();
                            Dictionary<string, object> passiveClick = ClickGeneratedBody(form, main, sourceClickCount, report, "passive-selected-text-outside-click");
                            Wait(delegate { return !IsWindowVisible(main); }, 2000, "Short source click failed to hide unpinned popup.");
                            passiveClick["productHiddenObservedAfterClick"] = true;
                            report["passiveOutsideHideObserved"] = true; report["passiveSourceClickDelivered"] = true;
                            report["passiveOutsideClickPassed"] = true; report["outsideHideObservedMs"] = outside.ElapsedMilliseconds;
                            // Empty Alt+D is its own focused-input path, not the
                            // passive selected/OCR presentation or Alt+A. Keep
                            // the exact source HWND and send only one down/up.
                            stage = "empty-selection-same-source-outside-click";
                            sourceFocus(); Ui(form, delegate { source.Select(0, 0); }); Shortcut(form, 0x44);
                            Wait(delegate { return IsWindowVisible(main) && GetForegroundWindow() == main && SourceValue(main) == ""; }, 12000,
                                "Empty Alt+D did not produce a focused blank editor; no outside click sent.");
                            moveApp();
                            Dictionary<string, object> emptyClick = ClickGeneratedBody(form, main, sourceClickCount, report, "empty-selection-same-source-outside-click");
                            Wait(delegate { return !IsWindowVisible(main); }, 2000, "One same-source click did not hide the unpinned empty Alt+D popup.");
                            Require(GetForegroundWindow() == form.Handle, "Empty Alt+D dismissal did not leave the clicked source foreground.");
                            emptyClick["productHiddenObservedAfterClick"] = true;
                            report["emptySelectionSameSourceOutsideClickPassed"] = true;
                            stage = "pinned-empty-selection-same-source-outside-retention";
                            sourceFocus(); Ui(form, delegate { source.Select(0, 0); }); Shortcut(form, 0x44);
                            Wait(delegate { return IsWindowVisible(main) && GetForegroundWindow() == main && SourceValue(main) == ""; }, 12000,
                                "Pinned empty Alt+D case did not start from its own focused blank editor.");
                            moveApp(); Invoke(main, "\u9489\u4f4f\u7a97\u53e3");
                            Wait(delegate { return Element(main, "\u53d6\u6d88\u9489\u4f4f") != null; }, 5000, "Empty Alt+D pin state did not update.");
                            ClickGeneratedBody(form, main, sourceClickCount, report, "pinned-empty-selection-same-source-outside-retention");
                            Thread.Sleep(250);
                            Require(IsWindowVisible(main), "Pinned empty Alt+D popup hid on the same-source click.");
                            Require(GetForegroundWindow() == form.Handle, "Pinned empty Alt+D click did not reach the same source.");
                            report["pinnedEmptySelectionOutsideRetainedPassed"] = true;
                            Invoke(main, "\u53d6\u6d88\u9489\u4f4f");
                            Wait(delegate { return Element(main, "\u9489\u4f4f\u7a97\u53e3") != null; }, 5000, "Empty Alt+D unpin state did not update.");
                            ClickGeneratedBody(form, main, sourceClickCount, report, "unpinned-empty-selection-already-foreground-source-click");
                            Wait(delegate { return !IsWindowVisible(main); }, 2000, "Unpin did not resume same-source click dismissal for the blank popup.");
                            report["unpinnedEmptySelectionSameSourceOutsideClickPassed"] = true;
                            stage = "ocr-same-foreground-source-outside-click";
                            sourceFocus(); OcrThenSameForegroundClick(form, image, app, main, sourceClickCount, delegate { return Interlocked.CompareExchange(ref imageMouseEvents, 0, 0); }, report);
                            stage = "explicit-input-inside-retention";
                            sourceFocus(); Shortcut(form, 0x41);
                            Wait(delegate { return IsWindowVisible(main) && GetForegroundWindow() == main; }, 5000, "Explicit input did not focus the new app."); moveApp();
                            RECT bounds; Require(GetWindowRect(main, out bounds), "Own app bounds unavailable.");
                            Click(bounds.left + 70, bounds.top + 70, form, main, false); Thread.Sleep(150);
                            Require(IsWindowVisible(main), "Inside click hid the popup."); report["insideClickRetainedPassed"] = true;
                            stage = "actual-toolbar-drag";
                            DragOwnToolbar(main); report["actualToolbarDragRetainedPassed"] = true;
                            stage = "actual-edge-resize";
                            moveApp(); ResizeOwnEdge(main); report["actualEdgeResizeRetainedPassed"] = true;
                            stage = "actual-owned-native-window";
                            using (Form ownedDialog = new Form()) {
                                int ownedClicks = 0; ownedDialog.MouseDown += delegate { Interlocked.Increment(ref ownedClicks); };
                                List<Dictionary<string, object>> ownerLifecycle = new List<Dictionary<string, object>>();
                                report["ownedWindowLifecycle"] = ownerLifecycle; report["ownedWindowLifecycleLimit"] = 16;
                                Stopwatch ownerClock = Stopwatch.StartNew();
                                Action<string> observeOwner = delegate(string phase) {
                                    if (ownerLifecycle.Count < 16) ownerLifecycle.Add(OwnedLifecycleSnapshot(main, ownedDialog, phase, ownerClock.Elapsed.TotalMilliseconds));
                                    else report["ownedWindowLifecycleTruncated"] = true;
                                };
                                ownedDialog.HandleCreated += delegate { observeOwner("handle-created"); };
                                ownedDialog.VisibleChanged += delegate { observeOwner("visible-changed"); };
                                ownedDialog.Activated += delegate { observeOwner("activated"); };
                                ownedDialog.HandleDestroyed += delegate { observeOwner("handle-destroyed"); };
                                Ui(form, delegate {
                                    ownedDialog.Text = "EchoLingo generated native owned-window fixture";
                                    ownedDialog.StartPosition = FormStartPosition.Manual; ownedDialog.Bounds = new Rectangle(30, 360, 240, 140);
                                    observeOwner("before-show-with-owner");
                                    ownedDialog.Show(new Owner(main));
                                    observeOwner("after-show-with-owner");
                                });
                                Wait(delegate { return GetForegroundWindow() == ownedDialog.Handle; }, 2000, "Generated owned window did not gain focus.");
                                Ui(form, delegate { observeOwner("before-owner-assertion"); });
                                uint ownedProcess; GetWindowThreadProcessId(ownedDialog.Handle, out ownedProcess);
                                Require(ownedProcess == Process.GetCurrentProcess().Id && GetAncestor(ownedDialog.Handle, 2) == ownedDialog.Handle && GetWindow(ownedDialog.Handle, 4) == main,
                                    "Generated owned window has no verified fixture PID/top-level root/direct app owner; case not tested.");
                                report["generatedDirectOwnershipVerified"] = true;
                                report["ownedActivationMainVisibleObserved"] = IsWindowVisible(main);
                                Require(IsWindowVisible(main), "Activating the verified direct-owned window dismissed its popup owner.");
                                ClickGeneratedBody(ownedDialog, main, delegate { return Interlocked.CompareExchange(ref ownedClicks, 0, 0); }, report, "actual-owned-native-window"); Thread.Sleep(150);
                                Require(IsWindowVisible(main), "Clicking an actual owned window dismissed its popup owner.");
                                report["generatedNativeOwnedWindowRetainedPassed"] = true;
                                Ui(form, delegate { ownedDialog.Close(); });
                            }
                            stage = "focus-deactivation";
                            sourceFocus(); Wait(delegate { return !IsWindowVisible(main); }, 2000, "Actual foreground deactivation failed to hide input popup.");
                            report["focusDeactivationPassed"] = true;
                            stage = "pin-outside-retention";
                            Shortcut(form, 0x41); Wait(delegate { return IsWindowVisible(main); }, 5000, "Pin test input did not show."); moveApp();
                            Invoke(main, "\u9489\u4f4f\u7a97\u53e3"); Wait(delegate { return Element(main, "\u53d6\u6d88\u9489\u4f4f") != null; }, 5000, "Pin state did not update.");
                            sourceFocus(); ClickGeneratedBody(form, main, sourceClickCount, report, "pin-outside-retention"); Thread.Sleep(250);
                            Require(IsWindowVisible(main), "Pinned popup hid on outside click/focus loss."); report["pinnedOutsideRetainedPassed"] = true;
                            Invoke(main, "\u53d6\u6d88\u9489\u4f4f"); Wait(delegate { return Element(main, "\u9489\u4f4f\u7a97\u53e3") != null; }, 5000, "Unpin state did not update.");
                            ClickGeneratedBody(form, main, sourceClickCount, report, "unpin-outside-hide"); Wait(delegate { return !IsWindowVisible(main); }, 2000, "Unpinned popup did not resume outside dismissal.");
                            report["unpinOutsideHidePassed"] = true;
                            stage = "management-outside-retention";
                            Shortcut(form, 0x41); Wait(delegate { return IsWindowVisible(main); }, 5000, "Management test input did not show.");
                            Invoke(main, "\u66f4\u591a"); Invoke(main, "\u8bbe\u7f6e");
                            Wait(delegate { return Element(main, "\u8fd4\u56de\u7ffb\u8bd1") != null; }, 5000, "Management did not open.");
                            sourceFocus(); ClickGeneratedBody(form, main, sourceClickCount, report, "management-outside-retention"); Thread.Sleep(250);
                            Require(IsWindowVisible(main), "Management view hid on outside interaction."); report["managementOutsideRetainedPassed"] = true;
                            report["corePopupCasesPassed"] = true;
                            // Keep independent launch/handoff acceptance last:
                            // a failure here must preserve all core case results.
                            stage = "single-instance-hide-management-by-real-close";
                            Invoke(main, "\u9690\u85cf\u7ba1\u7406\u7a97\u53e3");
                            Wait(delegate { return !IsWindowVisible(main); }, 5000, "Real management close did not prepare a hidden single-instance target.");
                            IntPtr singleTarget = SingleInstanceWindow(app.Id);
                            report["singleInstancePrimaryBefore"] = NativeWindowMetadata(app, main);
                            report["singleInstanceTargetBefore"] = NativeWindowMetadata(app, singleTarget);
                            stage = "single-instance-handoff-and-secondary-exit";
                            List<Dictionary<string, object>> observations = new List<Dictionary<string, object>>();
                            report["singleInstanceObservations"] = observations;
                            Stopwatch handoff = Stopwatch.StartNew();
                            using (Process second = Process.Start(start)) {
                                report["singleInstanceSecondaryProcessId"] = second.Id;
                                report["singleInstanceLaunchRequests"] = 1;
                                report["singleInstanceDeadlineMs"] = 15000;
                                report["singleInstanceLibraryForwardTimeoutMs"] = 10000;
                                long nextObservation = 0;
                                while (!second.HasExited && handoff.ElapsedMilliseconds < 15000) {
                                    if (handoff.ElapsedMilliseconds >= nextObservation && observations.Count < 6) {
                                        observations.Add(new Dictionary<string, object> {
                                            { "elapsedMs", handoff.Elapsed.TotalMilliseconds },
                                            { "primaryMain", NativeWindowMetadata(app, main) },
                                            { "primarySingleInstanceTarget", NativeWindowMetadata(app, singleTarget) }
                                        });
                                        nextObservation += 2500;
                                    }
                                    second.WaitForExit(50);
                                }
                                report["singleInstanceSecondaryExitObservedMs"] = handoff.Elapsed.TotalMilliseconds;
                                report["singleInstanceSecondaryExited"] = second.HasExited;
                                if (!second.HasExited) {
                                    report["singleInstanceReadinessBeforeAbort"] = ReadinessMetadata(app, main);
                                    second.Kill(); second.WaitForExit(3000); report["singleInstanceSecondaryStoppedAfterFailure"] = second.HasExited;
                                    throw new InvalidOperationException("Single-instance secondary did not exit within the bounded 15s diagnostic deadline (library forward timeout is 10s).");
                                }
                                report["singleInstanceSecondaryExitCode"] = second.ExitCode;
                                Require(second.ExitCode == 0, "Single-instance secondary failed.");
                            }
                            // Exit0 also occurs on library forward timeout. Only
                            // the actual primary Settings view proves handoff.
                            stage = "single-instance-primary-settings-native-visible";
                            Wait(delegate { Require(!app.HasExited, "Primary exited after single-instance launch."); return IsWindowVisible(main); }, 5000, "Secondary exited, but the primary settings native window did not show.");
                            report["singleInstancePrimaryNativeVisible"] = true;
                            stage = "single-instance-primary-settings-accessibility";
                            Wait(delegate { return Element(main, "\u8fd4\u56de\u7ffb\u8bd1") != null; }, 5000, "Primary native window is visible after second launch, but the real Settings return control is unavailable.");
                            report["singleInstanceSettingsReadiness"] = ReadinessMetadata(app, main);
                            report["singleInstanceSettingsObservedMs"] = handoff.Elapsed.TotalMilliseconds;
                            report["singleInstanceHandoffPassed"] = true;
                            report["ok"] = true;
                        } catch (Exception error) {
                            report["failedStage"] = stage; report["ownTopLevelWindowsAtFailure"] = OwnTopLevelWindowInventory(app);
                            report["failureReadiness"] = ReadinessMetadata(app, main);
                            report["failureDetails"] = error.ToString(); failure = error;
                        }
                        finally {
                            IntPtr foreground = GetForegroundWindow();
                            if (foreground == form.Handle || (app != null && foreground == MainWindow(app.Id))) {
                                INPUT release = new INPUT(); release.type = 0; release.data.mouse.flags = 4;
                                SendInput(5, new INPUT[] { Key(0x12, true), Key(0x44, true), Key(0x41, true), Key(0x53, true), release }, Marshal.SizeOf(typeof(INPUT)));
                            }
                            if (app != null) {
                                try { if (!app.HasExited) { app.Kill(); app.WaitForExit(5000); } Require(app.HasExited, "Own app did not stop during cleanup."); report["ownApplicationStopped"] = true; }
                                catch (Exception error) { report["ok"] = false; report["applicationCleanupError"] = error.Message; }
                            }
                            if (restorePointer && GetForegroundWindow() == form.Handle) SetCursorPos(original.x, original.y);
                            Ui(form, delegate { done = true; form.Close(); });
                        }
                    });
                    worker.IsBackground = true; worker.Start();
                };
                Application.Run(form);
                if (failure != null) throw failure;
            }
        } catch (Exception error) { report["error"] = error.Message; }
        finally {
            bool removed = true;
            for (int index = owned.Count - 1; index >= 0; index--) {
                try { Clean(owned[index], token); } catch (Exception error) { removed = false; report["ok"] = false; report["cleanupError"] = error.Message; }
            }
            report["ownedDirectoriesRemoved"] = removed;
        }
        return new JavaScriptSerializer().Serialize(report);
    }
}
'@
    $references = @([System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location,
        [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,
        [System.Management.ManagementObject].Assembly.Location,
        [System.Windows.Automation.AutomationElement].Assembly.Location,
        [System.Windows.Automation.ControlType].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references -Language CSharp
    $result = [EchoLingoPopupVisibilitySmoke]::Run($ApplicationPath)
    [Console]::Out.WriteLine($result)
    if (-not ($result | ConvertFrom-Json).ok) { exit 1 }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
