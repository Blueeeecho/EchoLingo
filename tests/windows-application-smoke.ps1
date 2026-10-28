# Real built-app integration, restricted to an ephemeral GitHub-hosted Windows
# desktop. Never run this against a user's installed app or existing app data.
# It creates generated source content, a loopback mock and empty owned app dirs.
# CustomShortcutsTests exercises loaded custom bindings, not Settings UI saving.
[CmdletBinding()]
param([string]$ApplicationPath = '', [switch]$OfflineTranslation, [switch]$InstalledPackage, [switch]$LatestIntentTests, [switch]$CustomShortcutsTests)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
        -not [Environment]::UserInteractive) {
        throw 'ISOLATION_REQUIRED: Run only on an unlocked ephemeral GitHub-hosted Windows runner.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw 'TEST_APARTMENT: Run powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-application-smoke.ps1.'
    }
    if ([string]::IsNullOrWhiteSpace($ApplicationPath)) {
        $ApplicationPath = Join-Path $PSScriptRoot '..\src-tauri\target\release\echolingo.exe'
    }
    if ($LatestIntentTests -and $OfflineTranslation) { throw 'LATEST_INTENT_MOCK_ONLY: Existing three offline-model flows are unchanged.' }
    if ($CustomShortcutsTests -and ($OfflineTranslation -or $LatestIntentTests)) { throw 'CUSTOM_SHORTCUTS_MOCK_ONLY: Run the three loaded-custom-bindings workflows separately from offline/latest-intent modes.' }
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web.Extensions
    Add-Type -AssemblyName System.Management
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName WindowsBase
    $source = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Windows.Automation;

public static class EchoLingoApplicationSmoke {
    const string Identifier = "io.github.blueeeecho.echolingo";
    static bool Offline;
    static readonly Dictionary<string, object> ActualTranslations = new Dictionary<string, object>();
    static string Selected { get { return Offline ? "Hello world. This is a translation test." : "EchoLingo application selection 97531"; } }
    static string Typed { get { return Offline ? "\u4f60\u597d\uff0c\u4e16\u754c\u3002\u8fd9\u662f\u4e00\u6b21\u7ffb\u8bd1\u6d4b\u8bd5\u3002" : "EchoLingo typed input 86420"; } }
    static string OcrText { get { return Offline ? "Hello world 2468" : "EchoLingo OCR 2468"; } }
    const string PinnedSelectionOne = "EchoLingo pinned selection alpha 13579";
    const string PinnedSelectionTwo = "EchoLingo pinned selection bravo 86421";
    const string PinnedOcr = "EchoLingo pinned OCR 3579";
    const string AbandonedOcr = "EchoLingo abandoned OCR 7788";
    const string SwitchedSelection = "EchoLingo switched selection 11223";
    const string MarkerName = ".echolingo-ci-owned";
    delegate bool EnumWindow(IntPtr window, IntPtr parameter);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr memory);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateDirectory(string path, IntPtr security);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", SetLastError=true)] static extern bool GetWindowDisplayAffinity(IntPtr window, out uint affinity);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] static extern IntPtr GetTopWindow(IntPtr parent);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr parent, Point point, uint flags);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT rectangle);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window, uint attribute, out RECT rectangle, int size);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError=true)] static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out Point point);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion data; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mouse;
        [FieldOffset(0)] public KEYBDINPUT keyboard;
    }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    static void Assert(bool condition, string message) { if (!condition) throw new InvalidOperationException("ASSERTION_FAILED: " + message); }
    static void OnUi(Form form, Action action) { form.Invoke(action); }
    static int ForegroundPid() { uint process; GetWindowThreadProcessId(GetForegroundWindow(), out process); return (int)process; }
    static void RequireForeground(Form form) { Assert(GetForegroundWindow() == form.Handle, "Generated source lost foreground; no input sent elsewhere."); }
    static INPUT Key(ushort key, bool up) { INPUT input = new INPUT(); input.type = 1; input.data.keyboard.vk = key; input.data.keyboard.flags = up ? 2U : 0U; return input; }
    static void Send(INPUT[] input) { Assert(SendInput((uint)input.Length, input, Marshal.SizeOf(typeof(INPUT))) == input.Length, "Windows rejected generated fixture input."); }
    static void Shortcut(Form form, ushort key, bool customBindings=false) {
        RequireForeground(form);
        // Exactly one hotkey; do not retry and conceal a lost first event.
        Send(customBindings ? new INPUT[] { Key(0x11, false), Key(0x12, false), Key(0x10, false), Key(key, false), Key(key, true), Key(0x10, true), Key(0x12, true), Key(0x11, true) }
            : new INPUT[] { Key(0x12, false), Key(key, false), Key(key, true), Key(0x12, true) });
    }
    static Dictionary<string, object> ProbeHotkey(int id, string name, uint modifiers, uint key, bool available) {
        bool registered = RegisterHotKey(IntPtr.Zero, id, modifiers, key);
        int error = registered ? 0 : Marshal.GetLastWin32Error();
        if (registered) Assert(UnregisterHotKey(IntPtr.Zero, id), "Could not release the fixture's temporary hotkey probe: " + name);
        Assert(registered == available && (available || error == 1409), "Unexpected independent hotkey availability: " + name + "; Win32=" + error);
        return new Dictionary<string, object> { { "shortcut", name }, { "available", registered }, { "win32Error", error }, { "probeHoldsRegistration", false }, { "ownershipAttributedByProbeAlone", false } };
    }
    static void TypeIntoApp(int processId) {
        Assert(ForegroundPid() == processId, "Blank popup did not become foreground; no text sent elsewhere.");
        List<INPUT> input = new List<INPUT>();
        foreach (char value in Typed) {
            INPUT down = new INPUT(); down.type = 1; down.data.keyboard.scan = value; down.data.keyboard.flags = 4;
            INPUT up = down; up.data.keyboard.flags |= 2; input.Add(down); input.Add(up);
        }
        input.Add(Key(0x0D, false)); input.Add(Key(0x0D, true)); Send(input.ToArray());
    }
    static void ReleaseOwnInput(Form form, Process app, bool customBindings=false) {
        // A failed partial SendInput must not leave a generated modifier/button
        // held. Restrict these releases to our source or our own actual app.
        if (GetForegroundWindow() != form.Handle && (app == null || ForegroundPid() != app.Id)) return;
        INPUT mouse = new INPUT(); mouse.data.mouse.flags = 4;
        INPUT[] input = customBindings
            ? new INPUT[] { Key(0x11, true), Key(0x12, true), Key(0x10, true), Key(0x78, true), Key(0x79, true), Key(0x0D, true), mouse }
            : new INPUT[] { Key(0x12, true), Key(0x44, true), Key(0x53, true), Key(0x0D, true), mouse };
        SendInput((uint)input.Length, input, Marshal.SizeOf(typeof(INPUT)));
    }
    static string KnownFolder(string id) {
        Guid folder = new Guid(id); IntPtr value;
        Assert(SHGetKnownFolderPath(ref folder, 0, IntPtr.Zero, out value) == 0, "KnownFolder lookup failed.");
        try { string path = Marshal.PtrToStringUni(value); Assert(Path.IsPathRooted(path), "KnownFolder path is not absolute."); return path; }
        finally { CoTaskMemFree(value); }
    }
    static void ClaimDirectory(string path, string token, List<string> owned) {
        // Atomic create refuses an existing directory, including a racing app.
        Assert(CreateDirectory(path, IntPtr.Zero), "Existing app directory or create failure; never read/overwrite pre-existing user data.");
        File.WriteAllText(Path.Combine(path, MarkerName), token, new UTF8Encoding(false)); owned.Add(path);
    }
    static void CleanDirectory(string path, string token) {
        if (!Directory.Exists(path)) return;
        string marker = Path.Combine(path, MarkerName);
        Assert(File.Exists(marker) && File.ReadAllText(marker) == token, "Ownership marker missing; directory preserved.");
        Assert((File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0, "Owned directory became a reparse point; preserved.");
        // WebView2 can release its file handles shortly after taskkill returns.
        // Retry cleanup only; never repeat the user shortcut or translation.
        for (int attempt = 0; ; attempt++) {
            try { Directory.Delete(path, true); return; }
            catch (IOException) { if (attempt >= 19) throw; }
            catch (UnauthorizedAccessException) { if (attempt >= 19) throw; }
            Thread.Sleep(100);
        }
    }
    static int ParentPid(int process) {
        using (ManagementObjectSearcher query = new ManagementObjectSearcher("SELECT ParentProcessId FROM Win32_Process WHERE ProcessId=" + process)) {
            foreach (ManagementObject item in query.Get()) using (item) { return Convert.ToInt32(item["ParentProcessId"]); }
        }
        return 0;
    }
    static List<Dictionary<string, object>> AppWindows(int processId, bool visibleOnly) {
        List<Dictionary<string, object>> result = new List<Dictionary<string, object>>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            RECT rectangle;
            if (owner == processId && (!visibleOnly || IsWindowVisible(window)) && GetWindowRect(window, out rectangle) && rectangle.right - rectangle.left >= 100 && rectangle.bottom - rectangle.top >= 100) {
                result.Add(new Dictionary<string, object> { { "visible", IsWindowVisible(window) }, { "topmost", (GetWindowLongPtr(window, -20).ToInt64() & 8) != 0 },
                    { "width", rectangle.right - rectangle.left }, { "height", rectangle.bottom - rectangle.top }, { "foreground", GetForegroundWindow() == window } });
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
    sealed class AppEdge {
        public IntPtr Handle;
        public uint ProcessId;
        public int ParentProcessId;
        public Rectangle Bounds;
    }
    static List<AppEdge> AppOverlayWindows(int appId) {
        List<AppEdge> result = new List<AppEdge>();
        Dictionary<uint, int> helperParents = new Dictionary<uint, int>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            if (!IsWindowVisible(window)) return true;
            long style = GetWindowLongPtr(window, -20).ToInt64();
            long required = 0x08000000L | 0x00080000L | 0x00000020L | 8;
            if ((style & required) != required) return true;
            uint owner; GetWindowThreadProcessId(window, out owner);
            int parent;
            if (!helperParents.TryGetValue(owner, out parent)) { parent = ParentPid((int)owner); helperParents.Add(owner, parent); }
            if (parent == appId) {
                RECT rectangle; Assert(GetWindowRect(window, out rectangle), "Cannot inspect the actual app's capture border geometry.");
                int width = rectangle.right - rectangle.left, height = rectangle.bottom - rectangle.top;
                Assert(width > 0 && height > 0 && Math.Min(width, height) <= 2, "Actual OCR still created a full-screen overlay surface instead of thin edges.");
                result.Add(new AppEdge { Handle = window, ProcessId = owner, ParentProcessId = parent,
                    Bounds = Rectangle.FromLTRB(rectangle.left, rectangle.top, rectangle.right, rectangle.bottom) });
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
    static bool IsInputPlane(IntPtr window, uint processId) {
        StringBuilder name = new StringBuilder(256); GetClassName(window,name,name.Capacity);
        return name.ToString() == "EchoLingoCaptureInputPlane-" + processId;
    }
    sealed class InputPlaneStyleException : InvalidOperationException {
        public readonly Dictionary<string,object> ScalarMetadata;
        public InputPlaneStyleException(Dictionary<string,object> metadata)
            : base("ASSERTION_FAILED: Actual input plane has incorrect NoRedirection/NoActivate/Topmost/ToolWindow styles.") { ScalarMetadata=metadata; }
    }
    static long hiddenPlaneStyleChecks, hiddenPlaneWithoutTopmostChecks, visiblePlaneStyleChecks;
    static List<AppEdge> AppInputPlanes(int appId, bool visibleOnly, uint edgeHelper=0, uint rejectedHelper=0) {
        List<AppEdge> result = new List<AppEdge>();
        Dictionary<uint,int> parents = new Dictionary<uint,int>();
        EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window,out owner);
            if (!IsInputPlane(window,owner) || (visibleOnly && !IsWindowVisible(window))) return true;
            int parent; if (!parents.TryGetValue(owner,out parent)) { parent=ParentPid((int)owner); parents.Add(owner,parent); }
            if (parent != appId) return true;
            // Production verifies hidden construction before Present() adds
            // HWND_TOPMOST. A new picker can be observed in that valid phase
            // while the previous helper is stopping. Visible planes, including
            // those of the old helper, still require the complete shown styles.
            bool visible=IsWindowVisible(window), requireTopmost=visibleOnly||visible;
            long style=GetWindowLongPtr(window,-20).ToInt64(), required=0x00200000L|0x08000000L|0x80L|(requireTopmost?8L:0L);
            if (requireTopmost) visiblePlaneStyleChecks++; else { hiddenPlaneStyleChecks++; if ((style&8)==0) hiddenPlaneWithoutTopmostChecks++; }
            if ((style&required)!=required || (style&(0x00080000L|0x20L))!=0) {
                throw new InputPlaneStyleException(new Dictionary<string,object> {
                    {"scanPhase",visibleOnly?1:0},{"visibleAtStyleRead",visible},{"topmostRequired",requireTopmost},
                    {"extendedStyle",style},{"requiredExtendedStyle",required},{"noRedirection",(style&0x00200000L)!=0},
                    {"noActivate",(style&0x08000000L)!=0},{"toolWindow",(style&0x80L)!=0},{"topmost",(style&8L)!=0},
                    {"layered",(style&0x00080000L)!=0},{"transparent",(style&0x20L)!=0},
                    {"windowExistsAfterStyleRead",IsWindow(window)},{"visibleAfterStyleRead",IsWindowVisible(window)},
                    {"edgeHelperKnown",edgeHelper!=0},{"matchesEdgeHelper",edgeHelper!=0&&owner==edgeHelper},
                    {"rejectedHelperKnown",rejectedHelper!=0},{"matchesRejectedHelper",rejectedHelper!=0&&owner==rejectedHelper}
                });
            }
            RECT r; Assert(GetWindowRect(window,out r),"Cannot inspect actual input plane rectangle.");
            result.Add(new AppEdge { Handle=window, ProcessId=owner, ParentProcessId=parent, Bounds=Rectangle.FromLTRB(r.left,r.top,r.right,r.bottom) }); return true;
        },IntPtr.Zero); return result;
    }
    static int AppOverlays(int appId) { return AppOverlayWindows(appId).Count + AppInputPlanes(appId,false).Count; }
    static bool Above(IntPtr upper, IntPtr lower) {
        int count=0; for (IntPtr window=GetWindow(lower,3); window!=IntPtr.Zero && count++<4096; window=GetWindow(window,3)) if (window==upper) return true;
        return false;
    }
    static IntPtr UnderlyingRootAt(Point point, uint helper) {
        int count=0;
        for (IntPtr window=GetTopWindow(IntPtr.Zero); window!=IntPtr.Zero && count++<4096; window=GetWindow(window,2)) {
            if (!IsWindowVisible(window)) continue;
            uint owner; GetWindowThreadProcessId(window,out owner); if (owner==helper) continue;
            if ((GetWindowLongPtr(window,-20).ToInt64()&0x20L)!=0) continue;
            RECT r; if (GetWindowRect(window,out r) && Rectangle.FromLTRB(r.left,r.top,r.right,r.bottom).Contains(point)) return GetAncestor(window,2);
        }
        return IntPtr.Zero;
    }
    static int AllocatedThinCount(uint helper) {
        int count=0;
        EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window,out owner); long style=GetWindowLongPtr(window,-20).ToInt64();
            if (owner==helper && !IsInputPlane(window,owner) && (style&(0x08000000L|0x00080000L|0x20L))==(0x08000000L|0x00080000L|0x20L)) count++;
            return true;
        },IntPtr.Zero); return count;
    }
    static int[] RectValue(Rectangle value) { return new int[] { value.Left, value.Top, value.Width, value.Height }; }
    static string WindowId(IntPtr value) { return "0x" + value.ToInt64().ToString("X"); }
    static List<Rectangle> ExpectedPerimeter(Rectangle frame, Rectangle display) {
        List<Rectangle> result = new List<Rectangle>();
        if (frame.Width <= 0 || frame.Height <= 0) return result;
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
    static bool AppOcrReady(Form form, int appId, IntPtr expectedSource, Rectangle expectedFrame,
        Point expectedPointer, Rectangle display, Dictionary<string, object> probe, uint rejectedHelper=0) {
        RequireForeground(form);
        Point pointer; bool pointerKnown = GetPhysicalCursorPos(out pointer);
        IntPtr hit = pointerKnown ? WindowFromPoint(pointer) : IntPtr.Zero;
        IntPtr target = hit == IntPtr.Zero ? IntPtr.Zero : GetAncestor(hit, 2); uint targetPid;
        GetWindowThreadProcessId(target, out targetPid);
        RECT measured; int frameResult = DwmGetWindowAttribute(form.Handle, 9, out measured, Marshal.SizeOf(typeof(RECT)));
        Rectangle frame = frameResult == 0 ? Rectangle.FromLTRB(measured.left, measured.top, measured.right, measured.bottom) : Rectangle.Empty;
        uint sourcePid; GetWindowThreadProcessId(expectedSource,out sourcePid);
        bool validSource = pointerKnown && pointer == expectedPointer && form.Handle == expectedSource
            && sourcePid == Process.GetCurrentProcess().Id && GetAncestor(expectedSource, 2) == expectedSource
            && IsWindowVisible(expectedSource) && frame == expectedFrame && frame.Width > 0 && frame.Height > 0 && frame.Contains(pointer);
        List<Rectangle> screen = ExpectedPerimeter(display, display), hover = ExpectedPerimeter(expectedFrame, display);
        List<Rectangle> remaining = new List<Rectangle>(screen); remaining.AddRange(hover);
        List<AppEdge> actual = AppOverlayWindows(appId);
        List<Dictionary<string, object>> windows = new List<Dictionary<string, object>>();
        uint helper = 0; bool oneHelper = actual.Count > 0, exactGeometry = actual.Count == remaining.Count;
        foreach (AppEdge edge in actual) {
            if (helper == 0) helper = edge.ProcessId; else if (helper != edge.ProcessId) oneHelper = false;
            int index = remaining.IndexOf(edge.Bounds);
            if (index < 0) exactGeometry = false; else remaining.RemoveAt(index);
            windows.Add(new Dictionary<string, object> { { "hwnd", WindowId(edge.Handle) },
                { "helperProcessId", edge.ProcessId }, { "helperParentProcessId", edge.ParentProcessId }, { "physicalBounds", RectValue(edge.Bounds) } });
        }
        List<AppEdge> allPlanes=AppInputPlanes(appId,false,helper,rejectedHelper), planes=AppInputPlanes(appId,true,helper,rejectedHelper);
        List<Rectangle> planeBounds=new List<Rectangle>(); foreach (Screen monitor in Screen.AllScreens) planeBounds.Add(monitor.Bounds);
        bool exactPlanes=helper!=0 && allPlanes.Count==planeBounds.Count && planes.Count==planeBounds.Count;
        List<Dictionary<string,object>> planeMetadata=new List<Dictionary<string,object>>();
        foreach (AppEdge plane in planes) {
            int index=planeBounds.IndexOf(plane.Bounds); if (index<0) exactPlanes=false; else planeBounds.RemoveAt(index);
            if (plane.ProcessId!=helper) exactPlanes=false;
            foreach (AppEdge edge in actual) if (!Rectangle.Intersect(edge.Bounds,plane.Bounds).IsEmpty && !Above(edge.Handle,plane.Handle)) exactPlanes=false;
            planeMetadata.Add(new Dictionary<string,object> { { "hwnd",WindowId(plane.Handle) }, { "helperProcessId",plane.ProcessId }, { "physicalBounds",RectValue(plane.Bounds) } });
        }
        Point client=pointer; IntPtr desktop=GetDesktopWindow();
        bool mapped=pointerKnown && desktop!=IntPtr.Zero && ScreenToClient(desktop,ref client);
        IntPtr through=mapped ? GetAncestor(ChildWindowFromPointEx(desktop,client,0x1|0x4),2) : IntPtr.Zero;
        bool rawPlane=planes.Exists(delegate(AppEdge plane) { return plane.Handle==target && plane.Bounds.Contains(pointer); });
        bool rawThin=actual.Exists(delegate(AppEdge edge) { return edge.Handle==target && edge.Bounds.Contains(pointer); });
        bool throughPlane=planes.Exists(delegate(AppEdge plane) { return plane.Handle==through && plane.Bounds.Contains(pointer); });
        int thinAllocated=helper==0 ? 0 : AllocatedThinCount(helper), visibleOwned=0;
        if (helper!=0) EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window,out owner); if (owner==helper && IsWindowVisible(window)) visibleOwned++;
            return true;
        },IntPtr.Zero);
        exactPlanes=exactPlanes && visibleOwned==actual.Count+planes.Count;
        probe["allVisibleHelperWindowsClassified"]=visibleOwned==actual.Count+planes.Count;
        probe["actualVisibleHelperWindowCount"]=visibleOwned;
        IntPtr underneath=helper==0 ? IntPtr.Zero : UnderlyingRootAt(pointer,helper);
        validSource=validSource && underneath==expectedSource;
        exactPlanes=exactPlanes && planeBounds.Count==0 && thinAllocated==12*Screen.AllScreens.Length;
        bool ready = validSource && screen.Count == 4 && hover.Count == 4 && oneHelper && exactGeometry && remaining.Count == 0
            && exactPlanes && throughPlane && (rawPlane || rawThin);
        probe["requiredInputPlane"]=true; probe["allocatedInputPlaneCount"]=allPlanes.Count; probe["visibleInputPlaneCount"]=planes.Count;
        probe["allocatedThinWindowCount"]=thinAllocated; probe["physicalInputPlaneMultisetMatches"]=exactPlanes;
        probe["rawPointerIsExactPlane"]=rawPlane; probe["rawPointerIsVerifiedThinEdge"]=rawThin;
        probe["transparentSkippingHitIsExactPlane"]=throughPlane; probe["transparentSkippingPointerRootHwnd"]=WindowId(through);
        probe["independentlyUnderlyingSourceHwnd"]=WindowId(underneath); probe["observedInputPlanes"]=planeMetadata;
        probe["pointerPhysicalXY"] = pointerKnown ? (object)new int[] { pointer.X, pointer.Y } : null;
        probe["expectedPointerPhysicalXY"] = new int[] { expectedPointer.X, expectedPointer.Y };
        probe["pointerHitHwnd"] = WindowId(hit); probe["pointerRootHwnd"] = WindowId(target);
        probe["pointerRootProcessId"] = targetPid; probe["expectedSourceHwnd"] = WindowId(expectedSource);
        probe["expectedSourceProcessId"] = Process.GetCurrentProcess().Id; probe["sourceTargetVerified"] = validSource;
        probe["sourceDwmFrameHRESULT"] = frameResult; probe["expectedHoverPhysicalBounds"] = RectValue(expectedFrame);
        probe["actualSourceDwmPhysicalBounds"] = RectValue(frame); probe["sourceDwmFrameStable"] = frame == expectedFrame;
        probe["expectedScreenPhysicalBounds"] = RectValue(display);
        probe["expectedScreenEdgeCount"] = 4; probe["expectedHoverEdgeCount"] = 4;
        probe["actualVisibleEdgeCount"] = actual.Count; probe["oneDirectApplicationChildHelper"] = oneHelper;
        probe["helperProcessId"] = helper; probe["physicalEdgeMultisetMatches"] = screen.Count == 4 && hover.Count == 4 && exactGeometry && remaining.Count == 0;
        probe["observedEdges"] = windows; probe["ready"] = ready;
        RequireForeground(form);
        return ready;
    }
    static void WaitFor(Func<bool> condition, int seconds, string failure, Process app) {
        DateTime deadline = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < deadline) {
            Assert(!app.HasExited, "Actual application exited before workflow completed.");
            if (condition()) return;
            Thread.Sleep(50);
        }
        throw new InvalidOperationException("TIMEOUT: " + failure);
    }
    static IntPtr MainWindow(int process) {
        List<IntPtr> candidates=new List<IntPtr>();
        EnumWindows(delegate(IntPtr window,IntPtr unused){
            uint owner;GetWindowThreadProcessId(window,out owner);StringBuilder name=new StringBuilder(256);GetClassName(window,name,name.Capacity);
            if(owner==process&&GetAncestor(window,2)==window&&name.ToString()=="Tauri Window")candidates.Add(window);return true;
        },IntPtr.Zero);return candidates.Count==1?candidates[0]:IntPtr.Zero;
    }
    static Dictionary<string,object> NativeStartup(Process app) {
        int trays=0,hotkeys=0;
        EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint owner;GetWindowThreadProcessId(window,out owner);
            if(owner!=app.Id||GetAncestor(window,2)!=window)return true;
            StringBuilder name=new StringBuilder(128);GetClassName(window,name,name.Capacity);
            if(name.ToString()=="tray_icon_app")trays++;
            if(name.ToString()=="global_hotkey_app")hotkeys++;
            return true;
        },IntPtr.Zero);
        return new Dictionary<string,object>{{"trayWindowCount",trays},{"globalHotkeyWindowCount",hotkeys},{"nativeMilestoneIsNotFrontendReadiness",true},{"fixedFrontendWarmupMilliseconds",0}};
    }
    static AutomationElement Element(IntPtr window,string name) {
        return AutomationElement.FromHandle(window).FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.NameProperty,name));
    }
    static void InvokeControl(Process app,IntPtr main,string name) {
        AutomationElement element=null;
        WaitFor(delegate{return (element=Element(main,name))!=null;},5,"Actual popup accessibility control missing: "+name,app);
        object pattern;
        if(element.TryGetCurrentPattern(InvokePattern.Pattern,out pattern))((InvokePattern)pattern).Invoke();
        else if(element.TryGetCurrentPattern(TogglePattern.Pattern,out pattern))((TogglePattern)pattern).Toggle();
        else if(element.TryGetCurrentPattern(ExpandCollapsePattern.Pattern,out pattern))((ExpandCollapsePattern)pattern).Expand();
        else throw new InvalidOperationException("Actual popup control has no supported action pattern: "+name);
    }
    static bool SourceMatches(IntPtr main,string expected,bool foldCase=false) {
        AutomationElement element=AutomationElement.FromHandle(main).FindFirst(TreeScope.Descendants,new AndCondition(
            new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),
            new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));
        object pattern;return element!=null&&!element.Current.IsOffscreen&&element.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)&&String.Equals(((ValuePattern)pattern).Current.Value,expected,foldCase?StringComparison.OrdinalIgnoreCase:StringComparison.Ordinal);
    }
    static bool AppSourceMatches(int process, string expected, bool foldCase=false) {
        IntPtr main = MainWindow(process); return main != IntPtr.Zero && SourceMatches(main, expected, foldCase);
    }
    static Dictionary<string,object> MainMetadata(Process app) {
        IntPtr main=MainWindow(app.Id);uint affinity;bool affinityOk=GetWindowDisplayAffinity(main,out affinity);int affinityError=affinityOk?0:Marshal.GetLastWin32Error();RECT r;bool rectOk=GetWindowRect(main,out r);
        return new Dictionary<string,object>{{"mainHwnd",WindowId(main)},{"mainProcessId",app.Id},{"visible",main!=IntPtr.Zero&&IsWindowVisible(main)},
            {"style",GetWindowLongPtr(main,-16).ToInt64()},{"extendedStyle",GetWindowLongPtr(main,-20).ToInt64()},
            {"displayAffinityQuerySucceeded",affinityOk},{"displayAffinity",affinityOk?(object)affinity:null},{"displayAffinityWin32Error",affinityError},
            {"physicalBounds",rectOk?(object)new int[]{r.left,r.top,r.right-r.left,r.bottom-r.top}:null}};
    }
    sealed class FailedEditorObservation { public int Complete,Available,Visible,Nonempty,Failed; }
    static HashSet<string> FailureHealthFields() {
        HashSet<string> fields=new HashSet<string>(new string[]{"selectionQueryCount","helperResponseReceived","helperElapsedMilliseconds","helperResultNonempty","cancellationRequested","cancellationSignalled","cancellationSignalFailed","attemptId","attemptPhase","configuredCopyStrategy","actionResultOk","actionResultNonempty"});
        foreach(string suffix in new string[]{"Stage","Depth","IdentityCompared","IdentityEqual","RootWalkReason","ExceptionKind","Milliseconds"})for(int i=1;i<=16;i++)fields.Add("selectionQuery"+i+suffix);
        foreach(string key in new string[]{"copyStrategy","copyPhase","copyNativeContextValid","copyNativeContextChecks","copyNativeGuardReason","copyNativeEditable","copyNativeProtection","copyNativeSelectionKnown","copyNativeSelectionNonempty","copyProtectionProbe","copyProtectionProbeMilliseconds","copyProtectionUnknown","copySnapshotOutcome","copyDispatchInserted","copyOwnInputObserved","copyOwnerOutcome","copyClipboardRestored","copyTerminalReason","copyNativeInvalidReason","copyNativeGtiSucceeded","copyNativeGtiFlags","copyNativeFocusPresent","copyNativeFocusProcessMatchesForeground","copyNativeFocusRootMatchesForeground","copyNativeActivePresent","copyNativeActiveRootMatchesForeground"})fields.Add(key);
        return fields;
    }
    static long BoundedDiagnosticNumber(object value,long maximum) {
        Assert(value is int||value is long,"Failure diagnostic must contain integer metadata.");
        long number=Convert.ToInt64(value);Assert(number>=0&&number<=maximum,"Failure diagnostic metadata exceeds its bound.");return number;
    }
    // One read-only export after the original action has already failed. This
    // never retries a shortcut, changes focus or extends its acceptance budget.
    static void ObserveFailedWorkflow(Dictionary<string,object> report,Process app,ProcessStartInfo primaryStart,
        string executable,string roaming,string token,Form source,MockServer server) {
        Dictionary<string,object> snapshot=new Dictionary<string,object>{{"takenAfterWorkflowFailure",1},{"budgetMilliseconds",2000},{"captureOrKeyRequests",0},{"primaryLaunchedWithSelectionDiagnostics",0}};
        report["failureOnlyObservation"]=snapshot;Stopwatch budget=Stopwatch.StartNew();Process secondary=null;
        FailedEditorObservation editor=new FailedEditorObservation();
        try {
            Assert(app!=null&&!app.HasExited,"Failure observation requires the owned primary.");
            IntPtr main=MainWindow(app.Id);snapshot["ownMainFound"]=main!=IntPtr.Zero?1:0;snapshot["ownMainVisible"]=main!=IntPtr.Zero&&IsWindowVisible(main)?1:0;
            snapshot["foregroundIsSource"]=GetForegroundWindow()==source.Handle?1:0;snapshot["foregroundIsApp"]=ForegroundPid()==app.Id?1:0;
            snapshot["mockEnabled"]=server!=null?1:0;snapshot["mockRequestCount"]=server==null?0:server.Count;snapshot["mockErrorPresent"]=server!=null&&server.Error!=null?1:0;
            Thread reader=new Thread(delegate(){try {
                if(main==IntPtr.Zero)return;
                AutomationElement own=AutomationElement.FromHandle(main);Assert(own!=null&&own.Current.ProcessId==app.Id,"Failure editor root is not owned.");
                AutomationElement input=own.FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));object raw;
                if(input!=null){editor.Available=1;editor.Visible=input.Current.IsOffscreen?0:1;if(input.TryGetCurrentPattern(ValuePattern.Pattern,out raw))editor.Nonempty=String.IsNullOrEmpty(((ValuePattern)raw).Current.Value)?0:1;}
            }catch{editor.Failed=1;}finally{Interlocked.Exchange(ref editor.Complete,1);}});
            reader.IsBackground=true;reader.SetApartmentState(ApartmentState.MTA);reader.Start();
            Assert(primaryStart!=null&&(File.GetAttributes(roaming)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(roaming,MarkerName))==token,"Failure diagnostic directory is not owned.");
            string file=Path.Combine(roaming,"selection-diagnostics.json");
            ProcessStartInfo start=new ProcessStartInfo(executable,"--selection-diagnostics");start.UseShellExecute=false;start.CreateNoWindow=true;
            foreach(string key in new string[]{"APPDATA","LOCALAPPDATA","TEMP","TMP","WEBVIEW2_USER_DATA_FOLDER"})start.EnvironmentVariables[key]=primaryStart.EnvironmentVariables[key];
            long earliest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;
            snapshot["diagnosticExportsRequested"]=1;secondary=Process.Start(start);
            while(budget.ElapsedMilliseconds<2000){if(secondary.HasExited)break;Thread.Sleep((int)Math.Min(10,Math.Max(1,2000-budget.ElapsedMilliseconds)));}
            snapshot["diagnosticExportExited"]=secondary.HasExited?1:0;
            if(secondary.HasExited&&secondary.ExitCode==0&&File.Exists(file)&&budget.ElapsedMilliseconds<2000){
                Assert((File.GetAttributes(file)&FileAttributes.ReparsePoint)==0&&new FileInfo(file).Length>0&&new FileInfo(file).Length<=16384,"Failure diagnostic file exceeds its ownership/bound contract.");
                Dictionary<string,object> payload=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(file));
                Assert((string)payload["diagnostic"]=="last-selection-attempt"&&BoundedDiagnosticNumber(payload["processId"],Int32.MaxValue)==app.Id&&String.Equals((string)payload["executablePath"],Path.GetFullPath(executable),StringComparison.OrdinalIgnoreCase),"Failure diagnostic primary identity differs.");
                long recorded=BoundedDiagnosticNumber(payload["recordedAtUnixMs"],Int64.MaxValue),latest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;
                snapshot["diagnosticIsFreshAfterFailure"]=recorded>=earliest&&recorded<=latest?1:0;
                if(recorded>=earliest&&recorded<=latest){
                    Dictionary<string,object> health=payload["diagnostics"] as Dictionary<string,object>;Assert(health!=null,"Failure numeric health is missing.");
                    Dictionary<string,object> numeric=new Dictionary<string,object>();HashSet<string> allowed=FailureHealthFields();
                    foreach(KeyValuePair<string,object> pair in health)if(allowed.Contains(pair.Key))numeric[pair.Key]=BoundedDiagnosticNumber(pair.Value,10000000);
                    snapshot["nativeHealth"]=numeric;snapshot["primaryIdentityVerified"]=1;
                }
            }
        }catch{snapshot["observationFailed"]=1;}
        finally {
            if(secondary!=null){try{if(!secondary.HasExited){secondary.Kill();snapshot["ownDiagnosticProcessStopped"]=1;}}catch{snapshot["ownDiagnosticProcessCleanupFailed"]=1;}secondary.Dispose();}
            snapshot["sourceObservationCompleted"]=Interlocked.CompareExchange(ref editor.Complete,0,0)!=0?1:0;
            if(Interlocked.CompareExchange(ref editor.Complete,0,0)!=0){snapshot["sourceAvailable"]=editor.Available;snapshot["sourceVisible"]=editor.Visible;snapshot["sourceNonempty"]=editor.Nonempty;snapshot["sourceObservationFailed"]=editor.Failed;}
            snapshot["elapsedMilliseconds"]=Math.Min(10000000,budget.ElapsedMilliseconds);
        }
    }
    sealed class PinnedVisibilityWatch : IDisposable {
        readonly IntPtr window;readonly Thread thread;volatile bool stop;int samples,hidden;long maximumGapTicks;
        public PinnedVisibilityWatch(IntPtr main){window=main;thread=new Thread(delegate(){long last=Stopwatch.GetTimestamp();while(!stop){long now=Stopwatch.GetTimestamp();maximumGapTicks=Math.Max(maximumGapTicks,now-last);last=now;Interlocked.Increment(ref samples);if(!IsWindowVisible(window))Interlocked.Increment(ref hidden);Thread.Sleep(10);}});thread.IsBackground=true;thread.Start();}
        public void Check(){Assert(IsWindowVisible(window)&&Interlocked.CompareExchange(ref hidden,0,0)==0,"Pinned actual popup became hidden during a latest-intent workflow.");}
        public Dictionary<string,object> Snapshot(){return new Dictionary<string,object>{{"samples",samples},{"hiddenSamples",hidden},{"maximumSampleGapMilliseconds",maximumGapTicks*1000.0/Stopwatch.Frequency},{"pollMilliseconds",10}};}
        public void Dispose(){if(stop)return;stop=true;Assert(thread.Join(2000),"Pinned visibility observer did not stop.");}
    }
    static Dictionary<string,object> PlaceGeneratedSource(Form form,TextBox source,Panel image,IntPtr main,string text) {
        RECT raw;Assert(GetWindowRect(main,out raw),"Cannot measure own popup for generated-source placement.");Rectangle actualPopup=Rectangle.FromLTRB(raw.left,raw.top,raw.right,raw.bottom),popup=actualPopup;popup.Inflate(12,12);
        Dictionary<string,object> layout=new Dictionary<string,object>();
        OnUi(form,delegate{
            bool placed=false;Size frame=new Size(form.Width-form.ClientSize.Width,form.Height-form.ClientSize.Height);SizeF required;
            using(Font font=new Font("Segoe UI",24,FontStyle.Regular))using(Graphics graphics=form.CreateGraphics()){
                SizeF pinned=graphics.MeasureString(PinnedOcr,font),abandoned=graphics.MeasureString(AbandonedOcr,font);required=new SizeF(Math.Max(pinned.Width,abandoned.Width),Math.Max(pinned.Height,abandoned.Height));
            }
            Size minimumClient=new Size(Math.Max(490,(int)Math.Ceiling(required.Width)+56),Math.Max(168,(int)Math.Ceiling(required.Height)+128));
            foreach(Screen screen in Screen.AllScreens){Rectangle area=screen.WorkingArea;Rectangle inset=Rectangle.Inflate(area,-8,-8);
                Rectangle[] regions={
                    Rectangle.Intersect(inset,Rectangle.FromLTRB(inset.Left,inset.Top,inset.Right,Math.Max(inset.Top,popup.Top))),
                    Rectangle.Intersect(inset,Rectangle.FromLTRB(inset.Left,Math.Min(inset.Bottom,popup.Bottom),inset.Right,inset.Bottom)),
                    Rectangle.Intersect(inset,Rectangle.FromLTRB(inset.Left,inset.Top,Math.Max(inset.Left,popup.Left),inset.Bottom)),
                    Rectangle.Intersect(inset,Rectangle.FromLTRB(Math.Min(inset.Right,popup.Right),inset.Top,inset.Right,inset.Bottom))};
                foreach(Rectangle region in regions){
                    Size client=new Size(Math.Min(720,region.Width-frame.Width),Math.Min(430,region.Height-frame.Height));
                    if(client.Width<minimumClient.Width||client.Height<minimumClient.Height)continue;
                    form.ClientSize=client;form.Location=region.Location;
                    source.SetBounds(12,8,client.Width-24,44);image.SetBounds(12,64,client.Width-24,client.Height-76);
                    // DrawString uses(12,40); require the entire generated line
                    // inside the two-pixel-inset capture, without clipping.
                    Assert(required.Width+24<=image.Width-4&&required.Height+44<=image.Height-4,"Adaptive generated OCR image would clip its known text.");
                    Assert(region.Contains(form.Bounds)&&area.Contains(form.Bounds)&&!form.Bounds.IntersectsWith(popup),"Adaptive generated form escaped its verified free rectangle.");
                    layout["sourceBounds"]=RectValue(form.Bounds);layout["sourceClientSize"]=new int[]{client.Width,client.Height};layout["imageClientBounds"]=RectValue(image.Bounds);layout["workingArea"]=RectValue(area);layout["freeRegion"]=RectValue(region);layout["pinnedPopupBounds"]=RectValue(actualPopup);layout["ocrFontPoints"]=24;layout["measuredMaximumOcrTextSize"]=new double[]{required.Width,required.Height};layout["popupMovedOrHidden"]=false;placed=true;break;
                }if(placed)break;
            }
            Assert(placed,"No non-overlapping generated-source placement after safe adaptive layout; actual popup was not moved or hidden.");
            form.Activate();SetForegroundWindow(form.Handle);source.Focus();if(text!=null){source.Text="Prefix "+text+" suffix";source.Select(7,text.Length);}else source.Select(0,0);
        });RequireForeground(form);
        RECT moved;Assert(GetWindowRect(form.Handle,out moved)&&!Rectangle.FromLTRB(moved.left,moved.top,moved.right,moved.bottom).IntersectsWith(popup),"Generated form still overlaps the pinned popup.");layout["nonOverlapVerified"]=true;return layout;
    }
    static void MoveGenerated(Form form,Point point) {
        RequireForeground(form);Rectangle desktop=SystemInformation.VirtualScreen;INPUT input=new INPUT();input.data.mouse.dx=(int)Math.Round((point.X-desktop.Left)*65535.0/(desktop.Width-1));input.data.mouse.dy=(int)Math.Round((point.Y-desktop.Top)*65535.0/(desktop.Height-1));input.data.mouse.flags=0x8000|0x4000|1;Send(new INPUT[]{input});
    }
    static Dictionary<string,object> StartPinnedPicker(Form form,Panel image,Process app,IntPtr main,PinnedVisibilityWatch visibility,uint rejectedPid) {
        Point first=Point.Empty,last=Point.Empty;Rectangle display=Rectangle.Empty;OnUi(form,delegate{first=image.PointToScreen(new Point(2,2));last=image.PointToScreen(new Point(image.Width-2,image.Height-2));display=Screen.FromPoint(first).Bounds;});
        RECT raw;Assert(DwmGetWindowAttribute(form.Handle,9,out raw,Marshal.SizeOf(typeof(RECT)))==0,"Cannot measure generated picker source.");Rectangle frame=Rectangle.FromLTRB(raw.left,raw.top,raw.right,raw.bottom);
        MoveGenerated(form,first);Dictionary<string,object> probe=new Dictionary<string,object>();Stopwatch time=Stopwatch.StartNew();Shortcut(form,0x53);
        WaitFor(delegate{visibility.Check();return AppOcrReady(form,app.Id,form.Handle,frame,first,display,probe,rejectedPid)&&Convert.ToUInt32(probe["helperProcessId"])!=rejectedPid;},25,"Pinned latest Alt+S did not create a new exact ready helper.",app);
        visibility.Check();probe["hotkeyToReadyMilliseconds"]=time.Elapsed.TotalMilliseconds;probe["rejectedPreviousHelperPid"]=rejectedPid;probe["first"]=new int[]{first.X,first.Y};probe["last"]=new int[]{last.X,last.Y};probe["pinnedMainMetadata"]=MainMetadata(app);return probe;
    }
    static bool ProcessExited(uint pid){try{using(Process process=Process.GetProcessById((int)pid))return process.HasExited;}catch(ArgumentException){return true;}}
    static void LatestIntents(Form form,TextBox source,Panel image,Process app,MockServer server,string history,string providerId,List<string> passed,Dictionary<string,object> report,Action<string> paint,Func<int> sourceEvents) {
        Assert(server!=null&&!Offline,"Latest-intent extra flows require the generated loopback mock.");IntPtr main=MainWindow(app.Id);Assert(main!=IntPtr.Zero&&IsWindowVisible(main),"Latest-intent test has no unique visible actual Tauri popup.");
        report["uiAutomationSelectorsUsed"]=true;List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();report["latestIntentCases"]=cases;report["latestIntentRequiredCaseCount"]=4;report["latestIntentUsesEscape"]=false;report["latestIntentExpectedHistoryCount"]=7;List<Dictionary<string,object>> layouts=new List<Dictionary<string,object>>();report["generatedSourceLayouts"]=layouts;paint(OcrText);
        InvokeControl(app,main,"\u9489\u4f4f\u7a97\u53e3");WaitFor(delegate{return Element(main,"\u53d6\u6d88\u9489\u4f4f")!=null&&IsWindowVisible(main);},5,"Actual popup pin did not engage.",app);
        using(PinnedVisibilityWatch visibility=new PinnedVisibilityWatch(main)){
            try{
                foreach(string selected in new string[]{PinnedSelectionOne,PinnedSelectionTwo}){
                    string kind=MockServer.Kind(selected);Dictionary<string,object> test=new Dictionary<string,object>{{"kind",kind},{"ok",false}};cases.Add(test);
                    layouts.Add(PlaceGeneratedSource(form,source,image,main,selected));visibility.Check();Stopwatch time=Stopwatch.StartNew();Shortcut(form,0x44);
                    WaitFor(delegate{visibility.Check();if(server.Error!=null)throw new InvalidOperationException(server.Error);return HasHistory(history,selected,kind,providerId)&&SourceMatches(main,selected);},45,"One Alt+D did not replace the pinned source and commit distinct history.",app);
                    test["hotkeyToHistoryMilliseconds"]=time.Elapsed.TotalMilliseconds;RequireForeground(form);test["ok"]=true;
                }
                Assert(server.Count==5,"Pinned selections caused duplicate or missing translations.");passed.Add("Pinned actual popup accepted two distinct one-press Alt+D selections and durable histories");
                layouts.Add(PlaceGeneratedSource(form,source,image,main,null));paint(PinnedOcr);
                Dictionary<string,object> first=StartPinnedPicker(form,image,app,main,visibility,0);uint oldPid=Convert.ToUInt32(first["helperProcessId"]);
                Dictionary<string,object> restarted=new Dictionary<string,object>{{"kind","pinned-ocr-restart"},{"ok",false},{"firstReadiness",first}};cases.Add(restarted);
                // No Escape and no mouse release: the next Alt+S is a new task.
                Dictionary<string,object> second=StartPinnedPicker(form,image,app,main,visibility,oldPid);restarted["secondReadiness"]=second;
                Assert(Convert.ToUInt32(second["helperProcessId"])!=oldPid,"Repeated Alt+S reused the old picker process.");WaitFor(delegate{visibility.Check();return ProcessExited(oldPid);},5,"Superseded picker did not exit.",app);
                int[] begin=(int[])second["first"],end=(int[])second["last"];Point a=new Point(begin[0],begin[1]),b=new Point(end[0],end[1]);
                MoveGenerated(form,a);INPUT down=new INPUT();down.data.mouse.flags=2;Send(new INPUT[]{down});MoveGenerated(form,b);RequireForeground(form);INPUT up=new INPUT();up.data.mouse.flags=4;Stopwatch release=Stopwatch.StartNew();Send(new INPUT[]{up});
                WaitFor(delegate{visibility.Check();if(server.Error!=null)throw new InvalidOperationException(server.Error);return HasHistory(history,PinnedOcr,"pinned-ocr",providerId)&&SourceMatches(main,PinnedOcr,true);},50,"Repeated pinned Alt+S did not OCR/replace/translate the generated image.",app);
                restarted["releaseToHistoryMilliseconds"]=release.Elapsed.TotalMilliseconds;visibility.Check();RequireForeground(form);Assert(AppOverlays(app.Id)==0&&sourceEvents()==0,"Pinned OCR left an overlay or delivered input to generated content.");Assert(server.Count==6,"Repeated OCR caused duplicate or stale translations.");restarted["ok"]=true;passed.Add("Pinned Alt+S then Alt+S without Esc created a new helper and completed one fresh OCR/history while visible");
                layouts.Add(PlaceGeneratedSource(form,source,image,main,SwitchedSelection));paint(AbandonedOcr);
                Dictionary<string,object> abandoned=StartPinnedPicker(form,image,app,main,visibility,0);uint abandonedPid=Convert.ToUInt32(abandoned["helperProcessId"]);
                Dictionary<string,object> switched=new Dictionary<string,object>{{"kind","ocr-to-selection"},{"ok",false},{"cancelledReadiness",abandoned}};cases.Add(switched);
                Stopwatch switchTime=Stopwatch.StartNew();Shortcut(form,0x44);
                WaitFor(delegate{visibility.Check();if(server.Error!=null)throw new InvalidOperationException(server.Error);return HasHistory(history,SwitchedSelection,"switched-selection",providerId)&&SourceMatches(main,SwitchedSelection)&&ProcessExited(abandonedPid)&&AppOverlays(app.Id)==0;},45,"Alt+D did not replace/cancel the ready OCR task and commit one new selection.",app);
                switched["hotkeyToHistoryMilliseconds"]=switchTime.Elapsed.TotalMilliseconds;visibility.Check();RequireForeground(form);Assert(server.Count==7,"OCR-to-selection caused a stale or duplicate translation.");
                Assert(new JavaScriptSerializer().Deserialize<object[]>(File.ReadAllText(history)).Length==7,"Latest-intent fixture did not commit exactly seven distinct generated histories.");Assert(Element(main,"\u53d6\u6d88\u9489\u4f4f")!=null,"Popup pin state was lost.");switched["ok"]=true;passed.Add("Pinned ready Alt+S -> one Alt+D cancelled the picker with no Esc, fresh source/history and zero remaining overlays");
                report["latestIntentTestsPassed"]=true;
            }finally{visibility.Dispose();report["pinnedVisibilityObservation"]=visibility.Snapshot();report["latestIntentExecutedCaseCount"]=cases.Count;report["latestIntentPassedCaseCount"]=cases.FindAll(delegate(Dictionary<string,object> value){return Convert.ToBoolean(value["ok"]);}).Count;}
        }
    }
    sealed class MockServer : IDisposable {
        readonly TcpListener listener; readonly Thread thread; readonly object gate = new object();
        readonly JavaScriptSerializer json = new JavaScriptSerializer();
        public readonly List<Dictionary<string, object>> Requests = new List<Dictionary<string, object>>();
        public volatile string Error; volatile bool stopping;
        public MockServer() {
            listener = new TcpListener(IPAddress.Loopback, 0); listener.Start();
            thread = new Thread(Loop); thread.IsBackground = true; thread.Start();
        }
        public string Url { get { return "http://127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port; } }
        public int Count { get { lock (gate) return Requests.Count; } }
        public static string Kind(string text) {
            if (text == PinnedSelectionOne) return "pinned-selection-one";
            if (text == PinnedSelectionTwo) return "pinned-selection-two";
            if (String.Equals(text.Trim(),PinnedOcr,StringComparison.OrdinalIgnoreCase)) return "pinned-ocr";
            if (String.Equals(text.Trim(),AbandonedOcr,StringComparison.OrdinalIgnoreCase)) return "abandoned-ocr";
            if (text == SwitchedSelection) return "switched-selection";
            if (text == Selected) return "selection";
            if (text == Typed) return "typed";
            if (String.Equals(text.Trim(), OcrText, StringComparison.OrdinalIgnoreCase)) return "ocr";
            throw new InvalidOperationException("Unexpected non-fixture source reached loopback; content not logged.");
        }
        public static string Result(string kind) { return "ECHOLINGO_MOCK_" + kind.ToUpperInvariant() + "_TRANSLATED"; }
        void Loop() {
            while (!stopping) {
                try { using (TcpClient client = listener.AcceptTcpClient()) Handle(client); }
                catch (Exception error) { if (!stopping) Error = error.Message; }
            }
        }
        void Handle(TcpClient client) {
            client.ReceiveTimeout = 10000; client.SendTimeout = 10000;
            NetworkStream stream = client.GetStream(); List<byte> head = new List<byte>();
            while (head.Count < 16384) {
                int next = stream.ReadByte(); Assert(next >= 0, "Mock received truncated headers."); head.Add((byte)next);
                int n = head.Count;
                if (n >= 4 && head[n - 4] == 13 && head[n - 3] == 10 && head[n - 2] == 13 && head[n - 1] == 10) break;
            }
            string headers = Encoding.ASCII.GetString(head.ToArray());
            Assert(headers.StartsWith("POST /translate HTTP/1.1\r\n", StringComparison.Ordinal), "Mock accepts only LibreTranslate POST.");
            int length = -1;
            foreach (string line in headers.Split(new string[] { "\r\n" }, StringSplitOptions.None)) {
                if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase)) length = Int32.Parse(line.Substring(15).Trim());
                Assert(!line.StartsWith("Authorization:", StringComparison.OrdinalIgnoreCase), "No credential may reach the fixture.");
            }
            Assert(length >= 0 && length <= 65536, "Mock body size invalid.");
            byte[] bytes = new byte[length]; int offset = 0;
            while (offset < length) { int read = stream.Read(bytes, offset, length - offset); Assert(read > 0, "Mock body truncated."); offset += read; }
            Dictionary<string, object> body = json.Deserialize<Dictionary<string, object>>(Encoding.UTF8.GetString(bytes));
            string kind = Kind((string)body["q"]);
            Assert((string)body["target"] == "zh", "Automatic English-to-Chinese target did not reach mock.");
            Assert(!body.ContainsKey("api_key") || String.IsNullOrEmpty(body["api_key"] as string), "Fixture must have no API key.");
            byte[] response = Encoding.UTF8.GetBytes(json.Serialize(new Dictionary<string, object> { { "translatedText", Result(kind) } }));
            byte[] responseHead = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + response.Length + "\r\n\r\n");
            lock (gate) Requests.Add(new Dictionary<string, object> { { "kind", kind }, { "target", body["target"] }, { "emptyCredential", true } });
            stream.Write(responseHead, 0, responseHead.Length); stream.Write(response, 0, response.Length); stream.Flush();
        }
        public void Dispose() { stopping = true; listener.Stop(); thread.Join(2000); }
    }
    static bool ValidOfflineResult(string text, string kind) {
        if (String.IsNullOrWhiteSpace(text)) return false;
        if (kind == "typed") return text.IndexOf("world", StringComparison.OrdinalIgnoreCase) >= 0 && text.IndexOf("test", StringComparison.OrdinalIgnoreCase) >= 0;
        bool greeting = text.Contains("\u4e16\u754c") || text.Contains("\u4f60\u597d");
        if (kind == "ocr") return greeting && text.Contains("2468");
        return greeting && (text.Contains("\u6d4b\u8bd5") || text.Contains("\u8bd5\u9a8c"));
    }
    static bool HasHistory(string path, string source, string kind, string providerId) {
        if (!File.Exists(path)) return false;
        try {
            JavaScriptSerializer json = new JavaScriptSerializer();
            object[] entries = json.Deserialize<object[]>(File.ReadAllText(path));
            foreach (object raw in entries) {
                Dictionary<string, object> entry = raw as Dictionary<string, object>;
                if (entry == null || !String.Equals((string)entry["text"], source, (kind == "ocr" || kind == "pinned-ocr") ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)) continue;
                foreach (object value in (IEnumerable)entry["results"]) {
                    Dictionary<string, object> result = (Dictionary<string, object>)value;
                    if ((string)result["providerId"] != providerId || result.ContainsKey("error")) continue;
                    string translated = (string)result["text"];
                    if (Offline) {
                        Assert(ValidOfflineResult(translated, kind), "Real offline result failed direction/semantic checks for " + kind + ": " + translated);
                        ActualTranslations[kind] = new Dictionary<string, object> { { "text", translated }, { "sourceLanguage", entry["sourceLanguage"] }, { "targetLanguage", entry["targetLanguage"] }, { "backendElapsedMs", result["elapsedMs"] } };
                        return true;
                    }
                    if (translated == MockServer.Result(kind)) return true;
                }
            }
        } catch (IOException) { } catch (ArgumentException) { }
        return false;
    }
    static void KillOwnTree(Process app) {
        if (app == null || app.HasExited) return;
        ProcessStartInfo stop = new ProcessStartInfo("taskkill.exe", "/PID " + app.Id + " /T /F");
        stop.UseShellExecute = false; stop.CreateNoWindow = true; stop.RedirectStandardOutput = true; stop.RedirectStandardError = true;
        using (Process command = Process.Start(stop)) { command.StandardOutput.ReadToEnd(); command.StandardError.ReadToEnd(); Assert(command.WaitForExit(10000), "Own process-tree cleanup timed out."); }
        Assert(app.WaitForExit(5000), "Own application did not exit during cleanup.");
    }
    public static Dictionary<string, object> Run(string executable, bool offline, bool installed, bool latest, bool customBindings) {
        Assert(!latest||!offline,"Latest-intent extra tests are mock-only.");
        Assert(!customBindings||(!offline&&!latest),"Loaded-custom-bindings workflows require their own mock-only run.");
        Offline = offline; ActualTranslations.Clear(); hiddenPlaneStyleChecks=hiddenPlaneWithoutTopmostChecks=visiblePlaneStyleChecks=0;
        Dictionary<string, object> report = new Dictionary<string, object>(); List<string> passed = new List<string>();
        report["ok"] = false; report["passed"] = passed; report["actualApplicationTested"] = false;
        report["latestIntentTestsRequested"]=latest; report["singleHotkeyPerAction"] = true; report["uiAutomationSelectorsUsed"] = false;
        report["credentialsCreated"] = false; report["credentialAccessScope"] = offline ? "None: bundled offline provider" : "One random absent provider account; no existing credential or key supplied";
        report["translationBackend"] = offline ? "real-bundled-offline-model" : "loopback-mock";
        report["multiMonitorTested"] = false; report["fullscreenTested"] = false; report["installedPackageTested"] = installed;
        string selectionShortcut = customBindings ? "Ctrl+Alt+Shift+F9" : "Alt+D", silentOcrShortcut = customBindings ? "Ctrl+Alt+Shift+F10" : "Alt+S";
        ushort selectionKey = customBindings ? (ushort)0x78 : (ushort)0x44, silentOcrKey = customBindings ? (ushort)0x79 : (ushort)0x53;
        List<Dictionary<string, object>> customCases = new List<Dictionary<string, object>>();
        Dictionary<string, object> hotkeys = new Dictionary<string, object>();
        report["startupHotkeyAvailability"]=hotkeys;
        if (customBindings) {
            report["customShortcutsTestsRequested"] = true; report["shortcutWorkflow"] = "loaded-custom-bindings";
            report["startupSettingsWrittenDirectly"] = true;
            report["settingsUiSaveTested"] = false; report["restartPersistenceTested"] = false;
            report["selectionShortcut"] = selectionShortcut; report["silentOcrShortcut"] = silentOcrShortcut;
            report["customShortcutRequiredWorkflowCount"] = 3; report["customShortcutCases"] = customCases;
            report["customShortcutExecutedWorkflowCount"] = 0; report["customShortcutPassedWorkflowCount"] = 0;
            report["hotkeyAvailability"] = hotkeys; report["customBindingCallbacksProveApplicationOwnership"] = false;
            report["uiAutomationSelectorsUsed"] = true;
        }
        string token = Guid.NewGuid().ToString("N"), providerId = offline ? "offline-translation" : "ci-application-" + Guid.NewGuid().ToString("N");
        List<string> owned = new List<string>(); Process app = null;
        string root = Path.Combine(Path.GetTempPath(), "echolingo-app-smoke-" + token);
        string roaming = Path.Combine(KnownFolder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"), Identifier);
        string local = Path.Combine(KnownFolder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"), Identifier);
        foreach (Process process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable))) using (process) {
            Assert(process.HasExited, "An application with the same executable name already runs; refused to interfere.");
        }
        try {
            ClaimDirectory(roaming, token, owned); ClaimDirectory(local, token, owned);
            ClaimDirectory(root, token, owned);
            string childLocal = Path.Combine(root, "LocalAppData"); Directory.CreateDirectory(childLocal);
            string childTemp = Path.Combine(root, "Temp"); Directory.CreateDirectory(childTemp);
            string history = Path.Combine(roaming, "history.json");
            using (MockServer server = offline ? null : new MockServer()) {
                JavaScriptSerializer json = new JavaScriptSerializer();
                Dictionary<string, object> settings = new Dictionary<string, object> {
                    { "providers", new object[] { new Dictionary<string, object> { { "id", providerId }, { "name", offline ? "Real bundled offline model" : "Loopback generated fixture" }, { "kind", offline ? "offline" : "libretranslate" }, { "baseUrl", offline ? "" : server.Url }, { "model", "" }, { "enabled", true }, { "prompt", "" } } } },
                    { "ocrProviders", new object[0] }, { "activeOcrProviderId", null }, { "sourceLanguage", "auto" }, { "targetLanguage", "auto" },
                    { "languageDirectionVersion", 1 }, { "shortcutDefaultsVersion", 1 }, { "saveHistory", true }, { "maxHistory", 20 }, { "theme", "light" }, { "autoHideSeconds", 0 },
                    { "shortcuts", new Dictionary<string, object> { { "selection", selectionShortcut }, { "capture", "" }, { "ocr", "Alt+Shift+S" }, { "silentOcr", silentOcrShortcut }, { "input", "Alt+A" } } }
                };
                File.WriteAllText(Path.Combine(roaming, "settings.json"), json.Serialize(settings), new UTF8Encoding(false));
                SetProcessDpiAwarenessContext(new IntPtr(-4));
                Assert(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Fixture main-thread physical coordinates unavailable.");
                using (Form form = new Form()) using (TextBox source = new TextBox()) using (Panel image = new Panel()) {
                    form.Text = "EchoLingo generated real-app source"; form.ClientSize = new Size(720, 430); form.StartPosition = FormStartPosition.CenterScreen;
                    form.FormBorderStyle = FormBorderStyle.FixedDialog; form.MaximizeBox = false;
                    source.Multiline = true; source.SetBounds(20, 20, 680, 80); source.Text = "Prefix " + Selected + " suffix";
                    image.SetBounds(20, 170, 680, 150); image.BackColor = Color.White;
                    string paintedOcrText=OcrText;float paintedOcrFontPoints=30;
                    image.Paint += delegate(object sender, PaintEventArgs args) { using (Font font = new Font("Segoe UI", paintedOcrFontPoints, FontStyle.Regular)) args.Graphics.DrawString(paintedOcrText, font, Brushes.Black, 12, 40); };
                    int sourceMouseEvents = 0; image.MouseDown += delegate { sourceMouseEvents++; }; image.MouseUp += delegate { sourceMouseEvents++; };
                    form.Controls.Add(source); form.Controls.Add(image); bool finished = false;
                    form.FormClosing += delegate(object sender, FormClosingEventArgs args) { if (!finished) args.Cancel = true; };
                    form.Shown += delegate {
                        Thread worker = new Thread(delegate() {
                            Point originalPointer = Point.Empty; bool restorePointer = GetPhysicalCursorPos(out originalPointer);
                            ProcessStartInfo start=null;string stage="launch-owned-application";
                            try {
                                Assert(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Fixture worker physical coordinates unavailable.");
                                start = new ProcessStartInfo(executable); start.UseShellExecute = false; start.CreateNoWindow = true;
                                start.EnvironmentVariables["APPDATA"] = Path.Combine(root, "UnusedRoamingEnvironment");
                                start.EnvironmentVariables["LOCALAPPDATA"] = childLocal;
                                start.EnvironmentVariables["TEMP"] = childTemp; start.EnvironmentVariables["TMP"] = childTemp;
                                start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"] = Path.Combine(local, "webview-fixture");
                                if (customBindings) hotkeys["beforeApplicationStart"] = new object[] {
                                    ProbeHotkey(0x6E19, selectionShortcut, 7, 0x78, true), ProbeHotkey(0x6E1A, silentOcrShortcut, 7, 0x79, true),
                                    ProbeHotkey(0x6E1B, "Alt+D", 1, 0x44, true), ProbeHotkey(0x6E1C, "Alt+S", 1, 0x53, true) };
                                else hotkeys["beforeApplicationStart"]=ProbeHotkey(0x6E19,selectionShortcut,1,selectionKey,true);
                                app = Process.Start(start); report["applicationProcessId"] = app.Id; report["actualApplicationTested"] = true;
                                try { Assert(app.WaitForInputIdle(15000), "Actual app did not become input-idle."); } catch (InvalidOperationException) { throw new InvalidOperationException("Actual app has no observable GUI message loop."); }
                                stage="native-startup-milestone";
                                // tray-icon 0.25.1 creates this owned top-level
                                // window after setup has called install_shortcuts.
                                // Observe without showing/focusing or repeatedly
                                // stealing a shortcut registration. This remains
                                // a native milestone, not frontend readiness proof.
                                WaitFor(delegate { var readiness=NativeStartup(app);report["beforeFirstHotkeyReadiness"]=readiness;return MainWindow(app.Id)!=IntPtr.Zero&&Convert.ToInt32(readiness["trayWindowCount"])==1; },20,"Actual app did not reach its unique main and after-shortcut tray milestone.",app);
                                if (customBindings) hotkeys["afterApplicationStart"] = new object[] {
                                    ProbeHotkey(0x6E19, selectionShortcut, 7, 0x78, false), ProbeHotkey(0x6E1A, silentOcrShortcut, 7, 0x79, false),
                                    ProbeHotkey(0x6E1B, "Alt+D", 1, 0x44, true), ProbeHotkey(0x6E1C, "Alt+S", 1, 0x53, true) };
                                else hotkeys["afterApplicationStart"]=ProbeHotkey(0x6E19,selectionShortcut,1,selectionKey,false);
                                OnUi(form, delegate { form.Activate(); SetForegroundWindow(form.Handle); source.Focus(); source.Select(7, Selected.Length); }); Thread.Sleep(150);
                                stage="first-selected-text-shortcut";
                                Shortcut(form, selectionKey, customBindings);
                                if (customBindings) report["customShortcutExecutedWorkflowCount"] = 1;
                                WaitFor(delegate { if (server != null && server.Error != null) throw new InvalidOperationException(server.Error); return HasHistory(history, Selected, "selection", providerId) && (!customBindings || AppSourceMatches(app.Id, Selected)); }, 45, selectionShortcut + (customBindings ? " never produced valid source/translation/history from the configured backend." : " never produced valid translation/history from the configured backend."), app);
                                Assert(server == null || server.Count == 1, "Selection triggered duplicate or unrelated requests.");
                                RequireForeground(form); List<Dictionary<string, object>> passive = AppWindows(app.Id, true);
                                Assert(passive.Count == 1 && (bool)passive[0]["topmost"], "Selection popup was not a visible topmost own window."); report["selectionWindow"] = passive[0];
                                passed.Add("Actual " + selectionShortcut + " -> native source selection -> frontend automatic translation -> " + (offline ? "real offline en-zh model" : "loopback mock") + " -> durable synthetic history; source foreground preserved");
                                if (customBindings) customCases.Add(new Dictionary<string, object> { { "workflow", "selection" }, { "shortcut", selectionShortcut }, { "hotkeyPresses", 1 }, { "actualSourceMatched", true }, { "mockRequestsAfter", server.Count }, { "durableHistoryMatched", true }, { "ok", true } });
                                OnUi(form, delegate { form.Activate(); SetForegroundWindow(form.Handle); source.Focus(); source.Select(0, 0); }); Thread.Sleep(150);
                                stage="empty-selection-and-typed-submit";
                                Shortcut(form, selectionKey, customBindings);
                                if (customBindings) report["customShortcutExecutedWorkflowCount"] = 2;
                                WaitFor(delegate { return ForegroundPid() == app.Id; }, 15, "Empty " + selectionShortcut + " did not focus the actual application.", app); Thread.Sleep(150); TypeIntoApp(app.Id);
                                WaitFor(delegate { if (server != null && server.Error != null) throw new InvalidOperationException(server.Error); return HasHistory(history, Typed, "typed", providerId) && (!customBindings || AppSourceMatches(app.Id, Typed)); }, 45, "Blank popup typing+Enter did not translate exact full text.", app);
                                Assert(server == null || server.Count == 2, "Empty selection or typed submission sent duplicate/unexpected requests.");
                                passed.Add("Actual empty " + selectionShortcut + " -> focused blank source -> first Unicode SendInput text + Enter -> " + (offline ? "real offline zh-en model" : "second mock") + "/history");
                                if (customBindings) customCases.Add(new Dictionary<string, object> { { "workflow", "empty-selection-typing" }, { "shortcut", selectionShortcut }, { "hotkeyPresses", 1 }, { "actualSourceMatched", true }, { "mockRequestsAfter", server.Count }, { "durableHistoryMatched", true }, { "ok", true } });
                                OnUi(form, delegate { form.Activate(); SetForegroundWindow(form.Handle); source.Focus(); source.Select(0, 0); }); Thread.Sleep(150);
                                Point first = Point.Empty, last = Point.Empty;
                                Rectangle pointerDisplay = Rectangle.Empty;
                                OnUi(form, delegate { first = image.PointToScreen(new Point(2, 2)); last = image.PointToScreen(new Point(image.Width - 2, image.Height - 2)); pointerDisplay = Screen.FromPoint(first).Bounds; });
                                IntPtr ocrSource = form.Handle; RECT sourceDwm;
                                Assert(DwmGetWindowAttribute(ocrSource, 9, out sourceDwm, Marshal.SizeOf(typeof(RECT))) == 0,
                                    "Cannot independently measure the generated OCR source DWM frame.");
                                Rectangle ocrSourceFrame = Rectangle.FromLTRB(sourceDwm.left, sourceDwm.top, sourceDwm.right, sourceDwm.bottom);
                                RequireForeground(form); Rectangle desktop = SystemInformation.VirtualScreen;
                                Action<Point> move = delegate(Point point) { RequireForeground(form); INPUT input = new INPUT(); input.data.mouse.dx = (int)Math.Round((point.X - desktop.Left) * 65535.0 / (desktop.Width - 1)); input.data.mouse.dy = (int)Math.Round((point.Y - desktop.Top) * 65535.0 / (desktop.Height - 1)); input.data.mouse.flags = 0x8000 | 0x4000 | 1; Send(new INPUT[] { input }); };
                                // Put the pointer over generated content before
                                // the one real hotkey, then require its actual
                                // source HWND and screen+hover physical frames.
                                // Four arbitrary borders or eight wrong ones
                                // cannot satisfy the readiness condition.
                                move(first);
                                Dictionary<string, object> ocrReady = new Dictionary<string, object>(); report["ocrOverlayReadiness"] = ocrReady;
                                stage="first-region-ocr";
                                Shortcut(form, silentOcrKey, customBindings);
                                if (customBindings) report["customShortcutExecutedWorkflowCount"] = 3;
                                Stopwatch readyElapsed = Stopwatch.StartNew();
                                WaitFor(delegate { return AppOcrReady(form, app.Id, ocrSource, ocrSourceFrame, first, pointerDisplay, ocrReady); }, 25,
                                    "Actual " + silentOcrShortcut + " did not create exact screen and generated-source hover thin edge perimeters.", app);
                                ocrReady["observedAfterHotkeyMilliseconds"] = readyElapsed.Elapsed.TotalMilliseconds;
                                move(first); Thread.Sleep(100); INPUT down = new INPUT(); down.data.mouse.flags = 2; Send(new INPUT[] { down }); Thread.Sleep(100); move(last); Thread.Sleep(100);
                                RequireForeground(form); INPUT up = new INPUT(); up.data.mouse.flags = 4; Send(new INPUT[] { up });
                                WaitFor(delegate { if (server != null && server.Error != null) throw new InvalidOperationException(server.Error); return HasHistory(history, OcrText, "ocr", providerId) && (!customBindings || AppSourceMatches(app.Id, OcrText, true)); }, 50, "Actual " + silentOcrShortcut + " left-drag OCR did not fill/translate exact generated text.", app);
                                Assert(server == null || server.Count == 3, "OCR caused duplicate or unexpected translations."); RequireForeground(form);
                                OnUi(form, delegate { Assert(sourceMouseEvents == 0, "OCR drag reached generated source control."); });
                                Assert(AppOverlays(app.Id) == 0, "Actual OCR left selection overlays behind.");
                                passed.Add("Actual " + silentOcrShortcut + " -> production transparent overlays -> left-drag -> WinRT OCR -> frontend source/automatic " + (offline ? "real offline model" : "mock") + " translation -> history; foreground preserved");
                                if (customBindings) {
                                    customCases.Add(new Dictionary<string, object> { { "workflow", "left-drag-winrt-ocr" }, { "shortcut", silentOcrShortcut }, { "hotkeyPresses", 1 }, { "actualSourceMatched", true }, { "mockRequestsAfter", server.Count }, { "durableHistoryMatched", true }, { "ok", true } });
                                    int count = new JavaScriptSerializer().Deserialize<object[]>(File.ReadAllText(history)).Length;
                                    Assert(count == 3 && customCases.Count == 3, "Custom bindings did not complete exactly three distinct generated histories/workflows.");
                                    report["customShortcutHistoryCount"] = count; report["customShortcutPassedWorkflowCount"] = customCases.Count;
                                    report["customBindingCallbacksProveApplicationOwnership"] = true;
                                }
                                stage="latest-intent-workflows";
                                if(latest) LatestIntents(form,source,image,app,server,history,providerId,passed,report,
                                    delegate(string text){OnUi(form,delegate{paintedOcrText=text;paintedOcrFontPoints=24;image.Refresh();});},delegate{int events=0;OnUi(form,delegate{events=sourceMouseEvents;});return events;});
                                report["mockRequests"] = server == null ? new List<Dictionary<string, object>>() : server.Requests;
                                if (offline) {
                                    Assert(ActualTranslations.Count == 3 && new JavaScriptSerializer().Deserialize<object[]>(File.ReadAllText(history)).Length == 3, "Offline flows did not produce exactly three successful synthetic histories.");
                                }
                                report["actualOfflineTranslations"] = ActualTranslations; report["ok"] = true;
                            } catch (Exception error) { report["failedStage"]=stage;report["error"] = error.Message;InputPlaneStyleException planeError=error as InputPlaneStyleException;if(planeError!=null)report["inputPlaneStyleFailure"]=planeError.ScalarMetadata;if(app!=null&&!app.HasExited){try{report["ownMainFailureMetadata"]=MainMetadata(app);}catch(Exception diagnostic){report["mainMetadataErrorType"]=diagnostic.GetType().Name;}ObserveFailedWorkflow(report,app,start,executable,roaming,token,form,server);} }
                            finally {
                                if (customBindings) report["customShortcutPassedWorkflowCount"] = customCases.Count;
                                if (!(bool)report["ok"]) ReleaseOwnInput(form, app, customBindings);
                                try { KillOwnTree(app); report["ownApplicationTreeStopped"] = true; } catch (Exception error) { report["ok"] = false; report["cleanupError"] = error.Message; }
                                if (restorePointer && GetForegroundWindow() == form.Handle) {
                                    // Restore only while our generated source remains foreground.
                                    Rectangle desktop = SystemInformation.VirtualScreen; INPUT input = new INPUT(); input.data.mouse.dx = (int)Math.Round((originalPointer.X - desktop.Left) * 65535.0 / (desktop.Width - 1)); input.data.mouse.dy = (int)Math.Round((originalPointer.Y - desktop.Top) * 65535.0 / (desktop.Height - 1)); input.data.mouse.flags = 0x8000 | 0x4000 | 1;
                                    try { Send(new INPUT[] { input }); } catch { }
                                }
                                OnUi(form, delegate { finished = true; form.Close(); });
                            }
                        }); worker.SetApartmentState(ApartmentState.STA); worker.IsBackground = false; worker.Start();
                    };
                    Application.Run(form);
                }
            }
        } catch (Exception error) { report["error"] = error.Message; }
        finally {
            report["inputPlaneStyleChecks"]=new Dictionary<string,object>{{"hidden",hiddenPlaneStyleChecks},{"hiddenWithoutTopmost",hiddenPlaneWithoutTopmostChecks},{"visibleRequiringTopmost",visiblePlaneStyleChecks},{"visiblePlanesStillRequireTopmost",true},{"hiddenPlanesCannotSatisfyReadiness",true}};
            for (int index = owned.Count - 1; index >= 0; index--) {
                try { CleanDirectory(owned[index], token); }
                catch (Exception error) { report["ok"] = false; report["directoryCleanupError"] = error.Message; }
            }
            report["ownedDirectoriesRemoved"] = owned.TrueForAll(delegate(string path) { return !Directory.Exists(path); });
            if (app != null) app.Dispose();
        }
        return report;
    }
}
'@
    $references = @([Windows.Forms.Form].Assembly.Location, [Drawing.Bitmap].Assembly.Location,
        [Web.Script.Serialization.JavaScriptSerializer].Assembly.Location, [Management.ManagementObject].Assembly.Location, [Windows.Automation.AutomationElement].Assembly.Location,
        [Windows.Automation.ControlType].Assembly.Location, [Windows.DependencyObject].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    $result = [EchoLingoApplicationSmoke]::Run($ApplicationPath, [bool]$OfflineTranslation, [bool]$InstalledPackage, [bool]$LatestIntentTests, [bool]$CustomShortcutsTests)
    $result['powerShellVersion'] = $PSVersionTable.PSVersion.ToString()
    $result['applicationSha256'] = (Get-FileHash -Algorithm SHA256 -LiteralPath $ApplicationPath).Hash.ToLowerInvariant()
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 12 -Compress))
    if (-not $result.ok) { exit 1 }
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    [Console]::Out.WriteLine((@{ ok = $false; actualApplicationTested = $false; error = $message } | ConvertTo-Json -Compress))
    exit 1
}
