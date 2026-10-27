# Real built-app integration, restricted to an ephemeral GitHub-hosted Windows
# desktop. Never run this against a user's installed app or existing app data.
# It creates generated source content, a loopback mock and empty owned app dirs.
[CmdletBinding()]
param([string]$ApplicationPath = '', [switch]$OfflineTranslation, [switch]$InstalledPackage)
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
    $ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web.Extensions
    Add-Type -AssemblyName System.Management
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

public static class EchoLingoApplicationSmoke {
    const string Identifier = "io.github.blueeeecho.echolingo";
    static bool Offline;
    static readonly Dictionary<string, object> ActualTranslations = new Dictionary<string, object>();
    static string Selected { get { return Offline ? "Hello world. This is a translation test." : "EchoLingo application selection 97531"; } }
    static string Typed { get { return Offline ? "\u4f60\u597d\uff0c\u4e16\u754c\u3002\u8fd9\u662f\u4e00\u6b21\u7ffb\u8bd1\u6d4b\u8bd5\u3002" : "EchoLingo typed input 86420"; } }
    static string OcrText { get { return Offline ? "Hello world 2468" : "EchoLingo OCR 2468"; } }
    const string MarkerName = ".echolingo-ci-owned";
    delegate bool EnumWindow(IntPtr window, IntPtr parameter);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr memory);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateDirectory(string path, IntPtr security);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
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
    static void Shortcut(Form form, ushort key) {
        RequireForeground(form);
        // Exactly one hotkey; do not retry and conceal a lost first event.
        Send(new INPUT[] { Key(0x12, false), Key(key, false), Key(key, true), Key(0x12, true) });
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
    static void ReleaseOwnInput(Form form, Process app) {
        // A failed partial SendInput must not leave a generated modifier/button
        // held. Restrict these releases to our source or our own actual app.
        if (GetForegroundWindow() != form.Handle && (app == null || ForegroundPid() != app.Id)) return;
        INPUT mouse = new INPUT(); mouse.data.mouse.flags = 4;
        INPUT[] input = new INPUT[] { Key(0x12, true), Key(0x44, true), Key(0x53, true), Key(0x0D, true), mouse };
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
    static List<AppEdge> AppInputPlanes(int appId, bool visibleOnly) {
        List<AppEdge> result = new List<AppEdge>();
        Dictionary<uint,int> parents = new Dictionary<uint,int>();
        EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window,out owner);
            if (!IsInputPlane(window,owner) || (visibleOnly && !IsWindowVisible(window))) return true;
            int parent; if (!parents.TryGetValue(owner,out parent)) { parent=ParentPid((int)owner); parents.Add(owner,parent); }
            if (parent != appId) return true;
            long style=GetWindowLongPtr(window,-20).ToInt64(), required=0x00200000L|0x08000000L|0x80L|8;
            Assert((style&required)==required && (style&(0x00080000L|0x20L))==0,
                "Actual input plane has incorrect NoRedirection/NoActivate/Topmost/ToolWindow styles.");
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
        Point expectedPointer, Rectangle display, Dictionary<string, object> probe) {
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
        List<AppEdge> allPlanes=AppInputPlanes(appId,false), planes=AppInputPlanes(appId,true);
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
                if (entry == null || !String.Equals((string)entry["text"], source, kind == "ocr" ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)) continue;
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
    public static Dictionary<string, object> Run(string executable, bool offline, bool installed) {
        Offline = offline; ActualTranslations.Clear();
        Dictionary<string, object> report = new Dictionary<string, object>(); List<string> passed = new List<string>();
        report["ok"] = false; report["passed"] = passed; report["actualApplicationTested"] = false;
        report["singleHotkeyPerAction"] = true; report["uiAutomationSelectorsUsed"] = false;
        report["credentialsCreated"] = false; report["credentialAccessScope"] = offline ? "None: bundled offline provider" : "One random absent provider account; no existing credential or key supplied";
        report["translationBackend"] = offline ? "real-bundled-offline-model" : "loopback-mock";
        report["multiMonitorTested"] = false; report["fullscreenTested"] = false; report["installedPackageTested"] = installed;
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
                    { "shortcuts", new Dictionary<string, object> { { "selection", "Alt+D" }, { "capture", "" }, { "ocr", "Alt+Shift+S" }, { "silentOcr", "Alt+S" }, { "input", "Alt+A" } } }
                };
                File.WriteAllText(Path.Combine(roaming, "settings.json"), json.Serialize(settings), new UTF8Encoding(false));
                SetProcessDpiAwarenessContext(new IntPtr(-4));
                Assert(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Fixture main-thread physical coordinates unavailable.");
                using (Form form = new Form()) using (TextBox source = new TextBox()) using (Panel image = new Panel()) {
                    form.Text = "EchoLingo generated real-app source"; form.ClientSize = new Size(720, 430); form.StartPosition = FormStartPosition.CenterScreen;
                    form.FormBorderStyle = FormBorderStyle.FixedDialog; form.MaximizeBox = false;
                    source.Multiline = true; source.SetBounds(20, 20, 680, 80); source.Text = "Prefix " + Selected + " suffix";
                    image.SetBounds(20, 170, 680, 150); image.BackColor = Color.White;
                    image.Paint += delegate(object sender, PaintEventArgs args) { using (Font font = new Font("Segoe UI", 30, FontStyle.Regular)) args.Graphics.DrawString(OcrText, font, Brushes.Black, 12, 40); };
                    int sourceMouseEvents = 0; image.MouseDown += delegate { sourceMouseEvents++; }; image.MouseUp += delegate { sourceMouseEvents++; };
                    form.Controls.Add(source); form.Controls.Add(image); bool finished = false;
                    form.FormClosing += delegate(object sender, FormClosingEventArgs args) { if (!finished) args.Cancel = true; };
                    form.Shown += delegate {
                        Thread worker = new Thread(delegate() {
                            Point originalPointer = Point.Empty; bool restorePointer = GetPhysicalCursorPos(out originalPointer);
                            try {
                                Assert(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Fixture worker physical coordinates unavailable.");
                                ProcessStartInfo start = new ProcessStartInfo(executable); start.UseShellExecute = false; start.CreateNoWindow = true;
                                start.EnvironmentVariables["APPDATA"] = Path.Combine(root, "UnusedRoamingEnvironment");
                                start.EnvironmentVariables["LOCALAPPDATA"] = childLocal;
                                start.EnvironmentVariables["TEMP"] = childTemp; start.EnvironmentVariables["TMP"] = childTemp;
                                start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"] = Path.Combine(local, "webview-fixture");
                                app = Process.Start(start); report["applicationProcessId"] = app.Id; report["actualApplicationTested"] = true;
                                try { Assert(app.WaitForInputIdle(15000), "Actual app did not become input-idle."); } catch (InvalidOperationException) { throw new InvalidOperationException("Actual app has no observable GUI message loop."); }
                                WaitFor(delegate { return AppWindows(app.Id, false).Count > 0; }, 20, "Actual app native window was not created.", app);
                                // Message-loop readiness is not frontend subscription readiness.
                                // Warm the actual packaged WebView once; do not repeat shortcuts.
                                Thread.Sleep(4000);
                                OnUi(form, delegate { form.Activate(); SetForegroundWindow(form.Handle); source.Focus(); source.Select(7, Selected.Length); }); Thread.Sleep(150);
                                Shortcut(form, 0x44);
                                WaitFor(delegate { if (server != null && server.Error != null) throw new InvalidOperationException(server.Error); return HasHistory(history, Selected, "selection", providerId); }, 45, "Alt+D never produced valid translation/history from the configured backend.", app);
                                Assert(server == null || server.Count == 1, "Selection triggered duplicate or unrelated requests.");
                                RequireForeground(form); List<Dictionary<string, object>> passive = AppWindows(app.Id, true);
                                Assert(passive.Count == 1 && (bool)passive[0]["topmost"], "Selection popup was not a visible topmost own window."); report["selectionWindow"] = passive[0];
                                passed.Add("Actual Alt+D -> native source selection -> frontend automatic translation -> " + (offline ? "real offline en-zh model" : "loopback mock") + " -> durable synthetic history; source foreground preserved");
                                OnUi(form, delegate { form.Activate(); SetForegroundWindow(form.Handle); source.Focus(); source.Select(0, 0); }); Thread.Sleep(150);
                                Shortcut(form, 0x44);
                                WaitFor(delegate { return ForegroundPid() == app.Id; }, 15, "Empty Alt+D did not focus the actual application.", app); Thread.Sleep(150); TypeIntoApp(app.Id);
                                WaitFor(delegate { if (server != null && server.Error != null) throw new InvalidOperationException(server.Error); return HasHistory(history, Typed, "typed", providerId); }, 45, "Blank popup typing+Enter did not translate exact full text.", app);
                                Assert(server == null || server.Count == 2, "Empty selection or typed submission sent duplicate/unexpected requests.");
                                passed.Add("Actual empty Alt+D -> focused blank source -> first Unicode SendInput text + Enter -> " + (offline ? "real offline zh-en model" : "second mock") + "/history");
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
                                Shortcut(form, 0x53);
                                Stopwatch readyElapsed = Stopwatch.StartNew();
                                WaitFor(delegate { return AppOcrReady(form, app.Id, ocrSource, ocrSourceFrame, first, pointerDisplay, ocrReady); }, 25,
                                    "Actual Alt+S did not create exact screen and generated-source hover thin edge perimeters.", app);
                                ocrReady["observedAfterHotkeyMilliseconds"] = readyElapsed.Elapsed.TotalMilliseconds;
                                move(first); Thread.Sleep(100); INPUT down = new INPUT(); down.data.mouse.flags = 2; Send(new INPUT[] { down }); Thread.Sleep(100); move(last); Thread.Sleep(100);
                                RequireForeground(form); INPUT up = new INPUT(); up.data.mouse.flags = 4; Send(new INPUT[] { up });
                                WaitFor(delegate { if (server != null && server.Error != null) throw new InvalidOperationException(server.Error); return HasHistory(history, OcrText, "ocr", providerId); }, 50, "Actual Alt+S left-drag OCR did not fill/translate exact generated text.", app);
                                Assert(server == null || server.Count == 3, "OCR caused duplicate or unexpected translations."); RequireForeground(form);
                                OnUi(form, delegate { Assert(sourceMouseEvents == 0, "OCR drag reached generated source control."); });
                                Assert(AppOverlays(app.Id) == 0, "Actual OCR left selection overlays behind.");
                                passed.Add("Actual Alt+S -> production transparent overlays -> left-drag -> WinRT OCR -> frontend source/automatic " + (offline ? "real offline model" : "mock") + " translation -> history; foreground preserved");
                                report["mockRequests"] = server == null ? new List<Dictionary<string, object>>() : server.Requests;
                                if (offline) {
                                    Assert(ActualTranslations.Count == 3 && new JavaScriptSerializer().Deserialize<object[]>(File.ReadAllText(history)).Length == 3, "Offline flows did not produce exactly three successful synthetic histories.");
                                }
                                report["actualOfflineTranslations"] = ActualTranslations; report["ok"] = true;
                            } catch (Exception error) { report["error"] = error.Message; }
                            finally {
                                if (!(bool)report["ok"]) ReleaseOwnInput(form, app);
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
        [Web.Script.Serialization.JavaScriptSerializer].Assembly.Location, [Management.ManagementObject].Assembly.Location) | Select-Object -Unique
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    $result = [EchoLingoApplicationSmoke]::Run($ApplicationPath, [bool]$OfflineTranslation, [bool]$InstalledPackage)
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
