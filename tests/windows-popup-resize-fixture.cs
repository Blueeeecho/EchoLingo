// Compiled with the existing visibility harness as a partial class. Only
// RunResize executes: its other visibility/OCR/clipboard cases are not run.
public static partial class EchoLingoPopupVisibilitySmoke {
    static System.Collections.Generic.Dictionary<string, object> activeResizeObservation;
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern uint GetDpiForWindow(System.IntPtr window);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetClientRect(System.IntPtr window, out RECT bounds);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool ClientToScreen(System.IntPtr window, ref POINT point);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool IsChild(System.IntPtr parent, System.IntPtr window);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread, ref ResizeGuiInfo info);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)]
    static extern int ResizeGetSystemParameter(uint action, uint parameter, out int value, uint flags);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)]
    static extern int ResizeSetSystemParameter(uint action, uint parameter, System.IntPtr value, uint flags);
    static int ReadResizeFullWindowDrag(System.Collections.Generic.Dictionary<string, object> observation, string phase) {
        int value; bool ok = ResizeGetSystemParameter(0x0026, 0, out value, 0) != 0;
        observation[phase + "QuerySucceeded"] = ok;
        observation[phase + "QueryLastError"] = ok ? 0 : System.Runtime.InteropServices.Marshal.GetLastWin32Error();
        Require(ok, "Could not query SPI_GETDRAGFULLWINDOWS on the isolated test desktop.");
        Require(value == 0 || value == 1, "SPI_GETDRAGFULLWINDOWS returned an invalid BOOL.");
        observation[phase + "Enabled"] = value != 0; return value;
    }
    static void SetResizeFullWindowDrag(System.Collections.Generic.Dictionary<string, object> observation, string phase, int value) {
        observation[phase + "SetAttempted"] = true;
        // Microsoft SystemParametersInfoW: SET uses uiParam, not pvParam.
        // fWinIni=0 keeps this temporary session change out of the user profile
        // and does not broadcast WM_SETTINGCHANGE. Restore in RunResize finally.
        bool ok = ResizeSetSystemParameter(0x0025, (uint)value, System.IntPtr.Zero, 0) != 0;
        observation[phase + "SetSucceeded"] = ok;
        observation[phase + "SetLastError"] = ok ? 0 : System.Runtime.InteropServices.Marshal.GetLastWin32Error();
        Require(ok, "Could not set SPI_SETDRAGFULLWINDOWS on the isolated test desktop.");
    }
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint="GetWindowLongW", SetLastError=true)] static extern int ResizeWindowStyle(System.IntPtr window, int index);
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)] static extern bool RegisterHotKey(System.IntPtr window, int id, uint modifiers, uint key);
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)] static extern bool UnregisterHotKey(System.IntPtr window, int id);
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    struct ResizeGuiInfo {
        public uint size, flags;
        public System.IntPtr active, focus, capture, menu, move, caret;
        public RECT caretBounds;
    }
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    struct ResizeMinMaxInfo {
        public POINT reserved, maximumSize, maximumPosition, minimumTrackSize, maximumTrackSize;
    }
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    static extern System.IntPtr ResizeQueryMinMax(System.IntPtr window, uint message, System.UIntPtr wParam,
        ref ResizeMinMaxInfo info, uint flags, uint timeout, out System.UIntPtr result);
    static System.Collections.Generic.Dictionary<string, object> ResizeTrackConstraints(Process app, System.IntPtr main) {
        RequireUniqueOwnedMainWindow(app, main);
        // WM_GETMINMAXINFO is a system message: User32 marshals this structure
        // to the owned HWND process. Query only; no geometry or constraints are changed.
        ResizeMinMaxInfo info = new ResizeMinMaxInfo(); System.UIntPtr result;
        bool responded = ResizeQueryMinMax(main, 0x0024, System.UIntPtr.Zero, ref info,
            0x0001 | 0x0002 | 0x0020, 500, out result) != System.IntPtr.Zero;
        return new System.Collections.Generic.Dictionary<string, object> {
            { "responded", responded }, { "lastError", responded ? 0 : System.Runtime.InteropServices.Marshal.GetLastWin32Error() },
            { "minimumTrackPhysicalSize", new int[] { info.minimumTrackSize.x, info.minimumTrackSize.y } },
            { "maximumTrackPhysicalSize", new int[] { info.maximumTrackSize.x, info.maximumTrackSize.y } },
            { "maximumPhysicalSize", new int[] { info.maximumSize.x, info.maximumSize.y } }
        };
    }
    static bool ResizeLoop(System.IntPtr main) {
        uint process; uint thread = GetWindowThreadProcessId(main, out process);
        ResizeGuiInfo info = new ResizeGuiInfo(); info.size = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(ResizeGuiInfo));
        Require(thread != 0 && GetGUIThreadInfo(thread, ref info), "Native sizing state is unavailable.");
        return (info.flags & 2) != 0;
    }
    static RECT ResizeBounds(System.IntPtr main) {
        RECT bounds; Require(GetWindowRect(main, out bounds), "Own window bounds are unavailable."); return bounds;
    }
    static int ResizeWidth(System.IntPtr main) { RECT bounds = ResizeBounds(main); return bounds.right - bounds.left; }
    static int ResizeHeight(System.IntPtr main) { RECT bounds = ResizeBounds(main); return bounds.bottom - bounds.top; }
    static POINT ResizeClientEdgePoint(System.IntPtr main, bool west, bool south) {
        RECT client; Require(GetClientRect(main, out client), "Own client edge bounds are unavailable.");
        int inset = (int)System.Math.Round(8 * GetDpiForWindow(main) / 96.0);
        POINT point = new POINT();
        point.x = south ? (client.left + client.right) / 2 : west ? client.left + inset : client.right - inset;
        point.y = south ? client.bottom - inset : (client.top + client.bottom) / 2;
        Require(ClientToScreen(main, ref point), "Own client edge position is unavailable.");
        return point;
    }
    static bool ResizeFiniteRectangle(double[] bounds) {
        if (bounds == null || bounds.Length != 4) return false;
        foreach (double value in bounds) if (double.IsNaN(value) || double.IsInfinity(value)) return false;
        return bounds[2] > bounds[0] && bounds[3] > bounds[1];
    }
    static bool ResizeScrollbarGeometry(double[] client, double[] bounds, double y, double scale, bool visible, bool vertical) {
        if (!visible || !vertical || !ResizeFiniteRectangle(client) || !ResizeFiniteRectangle(bounds) || scale <= 0) return false;
        double width = bounds[2] - bounds[0], gap = client[2] - bounds[0];
        return width <= 32 * scale && gap >= scale && gap <= 32 * scale && System.Math.Abs(bounds[2] - client[2]) <= scale &&
            bounds[0] >= client[0] && bounds[1] >= client[1] - scale && bounds[3] <= client[3] + scale &&
            bounds[3] - bounds[1] >= (client[3] - client[1]) / 2 && bounds[1] <= y && bounds[3] > y;
    }
    static bool ResizeDocumentGeometry(double[] client, double[] bounds, double y, double scale, bool visible, bool mainDocument) {
        if (!visible || !mainDocument || !ResizeFiniteRectangle(client) || !ResizeFiniteRectangle(bounds) || scale <= 0) return false;
        double gap = client[2] - bounds[2];
        return System.Math.Abs(bounds[0] - client[0]) <= scale && System.Math.Abs(bounds[1] - client[1]) <= scale &&
            gap >= scale && gap <= 32 * scale && bounds[3] >= client[3] - scale && bounds[1] <= y && bounds[3] > y;
    }
    static double ResizeObservedViewportRight(double originalRight, System.Collections.Generic.List<double[]> bars, System.Collections.Generic.List<double[]> documents, int visibleMainDocuments, bool complete, out string reason) {
        if (!complete) { reason = "incomplete-or-failed-owned-UIA-observation"; return originalRight; }
        if (bars.Count == 1) { reason = "unique-visible-right-vertical-scrollbar"; return bars[0][0]; }
        if (bars.Count > 1) { reason = "ambiguous-right-vertical-scrollbars"; return originalRight; }
        if (documents.Count == 1 && visibleMainDocuments == 1) { reason = "unique-main-document-viewport"; return documents[0][2]; }
        reason = documents.Count > 1 || visibleMainDocuments > 1 ? "ambiguous-main-document-viewport" : "no-reliable-layout-viewport-boundary";
        return originalRight;
    }
    static bool ResizeIsMainDocument(System.Windows.Automation.AutomationElement element, System.Windows.Automation.AutomationElement root) {
        // An iframe Document has a Document ancestor. Stop at the exact owned
        // root; never walk the desktop or read names, text, values or patterns.
        var parent = System.Windows.Automation.TreeWalker.RawViewWalker.GetParent(element);
        for (int depth = 0; parent != null && depth < 16; depth++) {
            if (System.Windows.Automation.Automation.Compare(parent, root)) return true;
            if (parent.Current.ControlType == System.Windows.Automation.ControlType.Document) return false;
            parent = System.Windows.Automation.TreeWalker.RawViewWalker.GetParent(parent);
        }
        return false;
    }
    static POINT ResizeLayoutViewportPoint(Process app, System.IntPtr main, POINT original, System.Collections.Generic.Dictionary<string, object> observation) {
        RequireUniqueOwnedMainWindow(app, main);
        RECT nativeClient; Require(GetClientRect(main, out nativeClient), "Owned layout viewport client bounds are unavailable.");
        POINT topLeft = new POINT(), bottomRight = new POINT(); topLeft.x = nativeClient.left; topLeft.y = nativeClient.top; bottomRight.x = nativeClient.right; bottomRight.y = nativeClient.bottom;
        Require(ClientToScreen(main, ref topLeft) && ClientToScreen(main, ref bottomRight), "Owned layout viewport position is unavailable.");
        double[] client = new double[] { topLeft.x, topLeft.y, bottomRight.x, bottomRight.y }; double scale = GetDpiForWindow(main) / 96.0;
        var candidates = new System.Collections.Generic.List<object>(); var bars = new System.Collections.Generic.List<double[]>(); var documents = new System.Collections.Generic.List<double[]>();
        var probe = new System.Collections.Generic.Dictionary<string, object> {
            { "originalPhysicalXY", new int[] { original.x, original.y } }, { "newPhysicalXY", new int[] { original.x, original.y } },
            { "clientPhysicalBounds", client }, { "scale", scale }, { "insetLogicalPixels", 8 }, { "candidates", candidates }, { "candidateLimit", 32 }
        };
        observation["layoutViewportObservation"] = probe; bool complete = false; int mainDocuments = 0;
        try {
            var root = System.Windows.Automation.AutomationElement.FromHandle(main);
            var found = root.FindAll(System.Windows.Automation.TreeScope.Descendants, new System.Windows.Automation.OrCondition(
                new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.ControlTypeProperty, System.Windows.Automation.ControlType.ScrollBar),
                new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.ControlTypeProperty, System.Windows.Automation.ControlType.Document)));
            probe["candidateCount"] = found.Count; probe["truncated"] = found.Count > 32;
            for (int index = 0; index < found.Count && index < 32; index++) {
                var element = found[index]; var info = element.Current; var rectangle = info.BoundingRectangle;
                double[] bounds = new double[] { rectangle.Left, rectangle.Top, rectangle.Right, rectangle.Bottom };
                bool valid = ResizeFiniteRectangle(bounds), visible = !info.IsOffscreen, scrollbar = info.ControlType == System.Windows.Automation.ControlType.ScrollBar;
                var orientation = info.Orientation; bool mainDocument = !scrollbar && ResizeIsMainDocument(element, root);
                if (!scrollbar && visible && mainDocument) mainDocuments++;
                bool eligible = scrollbar ? ResizeScrollbarGeometry(client, bounds, original.y, scale, visible, orientation == System.Windows.Automation.OrientationType.Vertical) : ResizeDocumentGeometry(client, bounds, original.y, scale, visible, mainDocument);
                candidates.Add(new System.Collections.Generic.Dictionary<string, object> {
                    { "controlType", info.ControlType.Id }, { "orientation", (int)orientation }, { "isOffscreen", !visible },
                    { "physicalBounds", valid ? (object)bounds : null }, { "finiteRectangle", valid }, { "mainDocumentVerified", mainDocument }, { "eligible", eligible }
                });
                if (eligible) { if (scrollbar) bars.Add(bounds); else documents.Add(bounds); }
            }
            complete = found.Count <= 32;
        } catch (System.Exception error) { probe["exceptionType"] = error.GetType().Name; }
        probe["eligibleScrollbarCount"] = bars.Count; probe["eligibleDocumentCount"] = documents.Count; probe["visibleMainDocumentCount"] = mainDocuments;
        string reason; double right = ResizeObservedViewportRight(client[2], bars, documents, mainDocuments, complete, out reason); probe["reason"] = reason; probe["observedRightPhysicalX"] = right;
        if (right != client[2]) original.x = (int)System.Math.Round(right - 8 * scale);
        probe["newPhysicalXY"] = new int[] { original.x, original.y }; return original;
    }
    static int ResizeHitTest(System.IntPtr main, int x, int y) {
        // Only query this exact owned HWND; never dispatch input to another app.
        System.UIntPtr result;
        int coordinates = unchecked((int)(((uint)y & 0xffff) << 16 | ((uint)x & 0xffff)));
        Require(SendMessageTimeout(main, 0x0084, System.UIntPtr.Zero, new System.IntPtr(coordinates), 0x0001 | 0x0002 | 0x0020, 500, out result) != System.IntPtr.Zero, "Own management nonclient hit-test did not respond.");
        return unchecked((int)result.ToUInt64());
    }
    static bool ResizePointerTargetAllowed(bool uniqueOwnedMain, bool mainVisible, bool foregroundIsMain, System.IntPtr main, System.IntPtr hit, System.IntPtr hitRoot, bool hitIsChild, bool hitVisible) {
        return uniqueOwnedMain && mainVisible && foregroundIsMain && main != System.IntPtr.Zero && hit != System.IntPtr.Zero &&
            hitVisible && hitRoot == main && (hit == main || hitIsChild);
    }
    static void RequireResizePointerTarget(Process app, System.IntPtr main, POINT point, System.Collections.Generic.Dictionary<string, object> observation) {
        var candidates = MainWindowCandidates(app.Id); uint mainOwner, hitOwner, rootOwner;
        uint mainThread = GetWindowThreadProcessId(main, out mainOwner);
        System.IntPtr mainRoot = GetAncestor(main, 2), hit = WindowFromPoint(point), hitRoot = GetAncestor(hit, 2), foreground = GetForegroundWindow();
        uint hitThread = GetWindowThreadProcessId(hit, out hitOwner), rootThread = GetWindowThreadProcessId(hitRoot, out rootOwner);
        bool uniqueOwnedMain = candidates.Count == 1 && candidates[0] == main && mainOwner == app.Id && mainRoot == main;
        bool visible = IsWindowVisible(main), hitVisible = hit != System.IntPtr.Zero && IsWindowVisible(hit), child = hit != System.IntPtr.Zero && IsChild(main, hit);
        POINT cursor; bool cursorKnown = GetPhysicalCursorPos(out cursor);
        var probe = new System.Collections.Generic.Dictionary<string, object> {
            { "appProcessId", app.Id }, { "mainHwnd", main.ToInt64() }, { "mainOwnerProcessId", mainOwner }, { "mainThreadId", mainThread },
            { "mainRootHwnd", mainRoot.ToInt64() }, { "mainCandidateCount", candidates.Count }, { "uniqueOwnedMain", uniqueOwnedMain },
            { "mainVisible", visible }, { "foregroundHwnd", foreground.ToInt64() }, { "foregroundIsMain", foreground == main },
            { "mainDpi", GetDpiForWindow(main) }, { "targetPhysicalXY", new int[] { point.x, point.y } },
            { "cursorPhysicalPositionKnown", cursorKnown }, { "cursorPhysicalXY", new int[] { cursor.x, cursor.y } },
            { "hitHwnd", hit.ToInt64() }, { "hitOwnerProcessId", hitOwner }, { "hitThreadId", hitThread }, { "hitDpi", GetDpiForWindow(hit) },
            { "hitRootHwnd", hitRoot.ToInt64() }, { "hitRootOwnerProcessId", rootOwner }, { "hitRootThreadId", rootThread },
            { "hitIsMain", hit == main }, { "hitIsChildOfMain", child }, { "hitVisible", hitVisible }
        };
        var probes = new System.Collections.Generic.List<object>(); probes.Add(probe);
        observation["targetProbes"] = probes; observation["targetProbeCount"] = probes.Count;
        // WebView2 creates a child HWND in its host; its process identity is
        // diagnostic only. Require both the native parent chain and exact root.
        bool accepted = ResizePointerTargetAllowed(uniqueOwnedMain, visible, foreground == main, main, hit, hitRoot, child, hitVisible);
        probe["accepted"] = accepted;
        Require(accepted, "Resize edge is occluded or is not the exact visible foreground main or its descendant; no button-down sent.");
    }
    static System.Collections.Generic.Dictionary<string, object> ManagementResizeFrame(Process app, System.IntPtr main) {
        RequireUniqueOwnedMainWindow(app, main); RECT bounds = ResizeBounds(main);
        int style = ResizeWindowStyle(main, -16), centerX = (bounds.left + bounds.right) / 2, centerY = (bounds.top + bounds.bottom) / 2;
        int west = ResizeHitTest(main, bounds.left + 2, centerY), east = ResizeHitTest(main, bounds.right - 2, centerY);
        int north = ResizeHitTest(main, centerX, bounds.top + 2), south = ResizeHitTest(main, centerX, bounds.bottom - 2);
        var result = new System.Collections.Generic.Dictionary<string, object> {
            { "style", style }, { "thickFrame", (style & 0x00040000) != 0 }, { "caption", (style & 0x00c00000) == 0x00c00000 },
            { "westHit", west }, { "eastHit", east }, { "northHit", north }, { "southHit", south }
        };
        activeResizeObservation = result;
        Require((bool)result["thickFrame"] && (bool)result["caption"], "Settings did not restore a decorated resizable native frame.");
        Require(west == 10 && east == 11 && south == 15, "Settings edges did not report native resize hit targets.");
        return result;
    }
    static System.Collections.Generic.Dictionary<string, object> ResizeInputRegistrationProbe() {
        // Never call while production may be registering: a successful probe
        // temporarily owns the binding. Call only before launch or after the
        // own tray HWND proves setup has already attempted registrations.
        const int probeId = 0x6e51;
        SetLastError(0); bool acquired = RegisterHotKey(System.IntPtr.Zero, probeId, 1, 0x41);
        int error = acquired ? 0 : System.Runtime.InteropServices.Marshal.GetLastWin32Error();
        bool released = !acquired || UnregisterHotKey(System.IntPtr.Zero, probeId);
        return new System.Collections.Generic.Dictionary<string, object> { { "attempts", 1 }, { "acquired", acquired }, { "lastError", error }, { "released", released } };
    }
    static int ResizeOwnedTrayCount(int process) {
        int count = 0;
        EnumWindows(delegate(System.IntPtr window, System.IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner != process || GetAncestor(window, 2) != window) return true;
            var name = new System.Text.StringBuilder(64); GetClassName(window, name, name.Capacity);
            // Cargo.lock tray-icon 0.25.1 creates this ordinary top-level
            // owner after main.rs setup's synchronous install_shortcuts call.
            if (name.ToString() == "tray_icon_app") count++;
            return true;
        }, System.IntPtr.Zero);
        return count;
    }
    static System.Collections.Generic.Dictionary<string, object> ResizeStartupMetadata(Process app, System.IntPtr main, System.IntPtr source, System.IntPtr editor) {
        System.IntPtr foreground = GetForegroundWindow();
        var candidates = MainWindowCandidates(app.Id); uint process;
        uint mainThread = GetWindowThreadProcessId(main, out process);
        bool owned = process == app.Id && candidates.Count == 1 && candidates[0] == main;
        uint sourceThread = GetWindowThreadProcessId(source, out process);
        ResizeGuiInfo mainInfo = new ResizeGuiInfo(), sourceInfo = new ResizeGuiInfo();
        mainInfo.size = sourceInfo.size = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(ResizeGuiInfo));
        bool mainGti = owned && mainThread != 0 && GetGUIThreadInfo(mainThread, ref mainInfo);
        bool sourceGti = sourceThread != 0 && GetGUIThreadInfo(sourceThread, ref sourceInfo);
        return new System.Collections.Generic.Dictionary<string, object> {
            { "appExited", app.HasExited }, { "mainCandidateCount", candidates.Count }, { "uniqueMainStillOwned", owned },
            { "nativeVisible", owned && IsWindowVisible(main) }, { "foregroundPresent", foreground != System.IntPtr.Zero },
            { "foregroundIsMain", foreground == main }, { "foregroundIsGeneratedSource", foreground == source },
            { "mainGtiAvailable", mainGti }, { "mainGtiFlags", mainInfo.flags },
            { "mainNativeFocusPresent", mainGti && mainInfo.focus != System.IntPtr.Zero },
            { "mainNativeFocusRootMatches", mainGti && mainInfo.focus != System.IntPtr.Zero && GetAncestor(mainInfo.focus, 2) == main },
            { "sourceGtiAvailable", sourceGti }, { "sourceGtiFlags", sourceInfo.flags },
            { "sourceNativeFocusIsEditor", sourceGti && sourceInfo.focus == editor },
            { "altHeld", (GetAsyncKeyState(0x12) & 0x8000) != 0 }, { "aHeld", (GetAsyncKeyState(0x41) & 0x8000) != 0 },
            { "controlHeld", (GetAsyncKeyState(0x11) & 0x8000) != 0 }, { "leftMouseHeld", (GetAsyncKeyState(1) & 0x8000) != 0 }
        };
    }
    static void SetGeneratedResizeSource(System.IntPtr main, string text) {
        System.Windows.Automation.AutomationElement edit = System.Windows.Automation.AutomationElement.FromHandle(main).FindFirst(
            System.Windows.Automation.TreeScope.Descendants, new System.Windows.Automation.AndCondition(
                new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.ControlTypeProperty, System.Windows.Automation.ControlType.Edit),
                new System.Windows.Automation.OrCondition(
                    new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.AutomationIdProperty, "source-text"),
                    new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.NameProperty, "\u539f\u6587"))));
        object pattern = null;
        Require(edit != null && !edit.Current.IsOffscreen && edit.TryGetCurrentPattern(System.Windows.Automation.ValuePattern.Pattern, out pattern), "The actual source editor has no writable ValuePattern.");
        ((System.Windows.Automation.ValuePattern)pattern).SetValue(text);
        Wait(delegate { return SourceValue(main) == text; }, 3000, "Generated long source was not accepted by the actual editor.");
    }
    static System.Collections.Generic.Dictionary<string, object> DragResize(Process app, System.IntPtr main, bool west, int distance, bool retainAfterRelease) {
        var samples = new System.Collections.Generic.List<int>(); bool held = false;
        var result = new System.Collections.Generic.Dictionary<string, object> {
            { "edge", west ? "west" : "east" }, { "deltaPhysicalPixels", distance },
            { "nativeSizingLoopObserved", false }, { "widthSamples", samples }, { "retentionRequired", retainAfterRelease }, { "clientInsetLogicalPixels", 8 }
        };
        activeResizeObservation = result;
        RequireUniqueOwnedMainWindow(app, main);
        Require(IsWindowVisible(main) && GetForegroundWindow() == main, "Only the exact foreground app HWND may receive the generated resize.");
        RECT before = ResizeBounds(main); int startWidth = before.right - before.left;
        result["initialPhysicalWidth"] = startWidth;
        result["trackConstraintsBeforeDrag"] = ResizeTrackConstraints(app, main);
        POINT point = ResizeClientEdgePoint(main, west, false);
        if (!west) point = ResizeLayoutViewportPoint(app, main, point, result);
        int x = point.x, y = point.y;
        Require(SetCursorPos(x, y), "Could not position the generated resize pointer.");
        RequireResizePointerTarget(app, main, point, result);
        var motion = new System.Collections.Generic.List<object>(); result["boundedMotionObservations"] = motion;
        result["initialBounds"] = new int[] { before.left, before.top, before.right, before.bottom };
        try {
            INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2; Send(new INPUT[] { down }); held = true;
            Wait(delegate { Require(IsWindowVisible(main), "Popup hid during edge-down."); return ResizeLoop(main); }, 3000, "Actual native WM move/size loop did not start; resize was not tested.");
            result["nativeSizingLoopObserved"] = true;
            POINT nativeAnchor; result["nativeLoopPointerKnown"] = GetPhysicalCursorPos(out nativeAnchor); result["nativeLoopPointer"] = new int[] { nativeAnchor.x, nativeAnchor.y };
            result["motionMethod"] = "SendInput absolute virtual desktop";
            for (int step = 1; step <= 8; step++) {
                Require(GetForegroundWindow() == main && IsWindowVisible(main), "Foreground changed during generated drag.");
                int delta = distance * step / 8, expected = startWidth + delta;
                // Use the existing OCR fixture's injected mouse-motion path
                // for the native modal loop, instead of the pointer-position
                // preparation API. Keep every width/deadline assertion below.
                var desktop = System.Windows.Forms.SystemInformation.VirtualScreen;
                INPUT move = new INPUT(); move.type = 0; move.data.mouse.flags = 0x8000 | 0x4000 | 1;
                move.data.mouse.x = (int)System.Math.Round((x + (west ? -delta : delta) - desktop.Left) * 65535.0 / (desktop.Width - 1));
                move.data.mouse.y = (int)System.Math.Round((y - desktop.Top) * 65535.0 / (desktop.Height - 1));
                Send(new INPUT[] { move });
                result["lastStep"] = step; result["expectedPhysicalWidth"] = expected;
                result["expectedPointer"] = new int[] { x + (west ? -delta : delta), y };
                Wait(delegate {
                    int actual = ResizeWidth(main); result["lastObservedPhysicalWidth"] = actual;
                    POINT pointer; bool pointerKnown = GetPhysicalCursorPos(out pointer);
                    RECT observedBounds = ResizeBounds(main);
                    if (motion.Count < 256) motion.Add(new object[] { step, expected, actual, pointerKnown, pointer.x, pointer.y, ResizeLoop(main), (GetAsyncKeyState(1) & 0x8000) != 0, observedBounds.left, observedBounds.top, observedBounds.right, observedBounds.bottom });
                    return System.Math.Abs(actual - expected) <= 5;
                }, 1500, "Native window failed to reach the generated edge position; possible layout fight.");
                // Test observation only: sample while the physical button is
                // still held, so a late content-fit rewind is not missed.
                Stopwatch observation = Stopwatch.StartNew();
                while (observation.ElapsedMilliseconds < 32) {
                    int actual = ResizeWidth(main); samples.Add(actual);
                    Require(System.Math.Abs(actual - expected) <= 5, "Width jumped away from the mouse position while native sizing was active.");
                    if (west) Require(System.Math.Abs(ResizeBounds(main).right - before.right) <= 5, "West drag moved the opposite right anchor.");
                    System.Threading.Thread.Sleep(4);
                }
            }
        } finally {
            if (held) { INPUT up = new INPUT(); up.type = 0; up.data.mouse.flags = 4; Send(new INPUT[] { up }); }
        }
        Wait(delegate { return !ResizeLoop(main); }, 3000, "Native sizing loop did not end after the generated release.");
        if (retainAfterRelease) {
            int expected = startWidth + distance;
            Wait(delegate { return System.Math.Abs(ResizeWidth(main) - expected) <= 5; }, 3000, "Released popup did not retain the actual resized width.");
            Stopwatch observation = Stopwatch.StartNew();
            while (observation.ElapsedMilliseconds < 350) {
                Require(IsWindowVisible(main) && System.Math.Abs(ResizeWidth(main) - expected) <= 5, "Popup width rewound after release/reflow.");
                System.Threading.Thread.Sleep(8);
            }
        }
        result["finalPhysicalWidth"] = ResizeWidth(main); result["passed"] = true; return result;
    }
    static System.Collections.Generic.Dictionary<string, object> DragManagementHeight(Process app, System.IntPtr main, int distance, bool corner = false) {
        var result = new System.Collections.Generic.Dictionary<string, object> {
            { "edge", corner ? "south-east" : "south" }, { "deltaPhysicalPixels", distance }, { "nativeSizingLoopObserved", false }, { "retentionRequired", true }, { "clientInsetLogicalPixels", 8 }
        };
        activeResizeObservation = result;
        RequireUniqueOwnedMainWindow(app, main);
        Require(IsWindowVisible(main) && GetForegroundWindow() == main, "Only the exact foreground settings HWND may receive a generated resize.");
        RECT before = ResizeBounds(main); int height = before.bottom - before.top, width = before.right - before.left;
        result["initialPhysicalHeight"] = height; result["initialPhysicalWidth"] = width;
        POINT point = ResizeClientEdgePoint(main, false, true);
        if (corner) {
            point.x = ResizeClientEdgePoint(main, false, false).x;
            point = ResizeLayoutViewportPoint(app, main, point, result);
        }
        int x = point.x, y = point.y;
        Require(SetCursorPos(x, y), "Could not position the generated settings resize pointer.");
        RequireResizePointerTarget(app, main, point, result);
        var samples = new System.Collections.Generic.List<int>(); result["heightSamples"] = samples; bool held = false;
        try {
            INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2; Send(new INPUT[] { down }); held = true;
            Wait(delegate { Require(IsWindowVisible(main), "Settings hid during resize edge-down."); return ResizeLoop(main); }, 3000, "Settings never entered an actual native sizing loop.");
            result["nativeSizingLoopObserved"] = true;
            var desktop = System.Windows.Forms.SystemInformation.VirtualScreen;
            for (int step = 1; step <= 8; step++) {
                Require(GetForegroundWindow() == main && IsWindowVisible(main), "Settings foreground changed during generated resize.");
                int delta = distance * step / 8, expected = height + delta;
                INPUT move = new INPUT(); move.type = 0; move.data.mouse.flags = 0x8000 | 0x4000 | 1;
                move.data.mouse.x = (int)System.Math.Round((x + (corner ? delta : 0) - desktop.Left) * 65535.0 / (desktop.Width - 1));
                move.data.mouse.y = (int)System.Math.Round((y + delta - desktop.Top) * 65535.0 / (desktop.Height - 1));
                Send(new INPUT[] { move }); result["lastStep"] = step; result["expectedPhysicalHeight"] = expected;
                Wait(delegate { int actual = ResizeHeight(main); result["lastObservedPhysicalHeight"] = actual; return System.Math.Abs(actual - expected) <= 5; }, 1500, "Settings height did not follow the native resize pointer.");
                Stopwatch observation = Stopwatch.StartNew();
                while (observation.ElapsedMilliseconds < 32) {
                    int actual = ResizeHeight(main); samples.Add(actual);
                    Require(System.Math.Abs(actual - expected) <= 5 && System.Math.Abs(ResizeWidth(main) - width - (corner ? delta : 0)) <= 5, "Settings geometry jumped during native resize.");
                    System.Threading.Thread.Sleep(4);
                }
            }
        } finally {
            if (held) { INPUT up = new INPUT(); up.type = 0; up.data.mouse.flags = 4; Send(new INPUT[] { up }); }
        }
        Wait(delegate { return !ResizeLoop(main); }, 3000, "Settings sizing loop did not end on mouse release.");
        int finalHeight = height + distance;
        Wait(delegate { return System.Math.Abs(ResizeHeight(main) - finalHeight) <= 5; }, 3000, "Settings height rewound after the native sizing loop ended.");
        Stopwatch retention = Stopwatch.StartNew();
        while (retention.ElapsedMilliseconds < 350) {
            Require(IsWindowVisible(main) && System.Math.Abs(ResizeHeight(main) - finalHeight) <= 5 && System.Math.Abs(ResizeWidth(main) - width - (corner ? distance : 0)) <= 5, "Settings size was replaced after native resize/reflow.");
            System.Threading.Thread.Sleep(8);
        }
        result["finalPhysicalHeight"] = ResizeHeight(main); result["finalPhysicalWidth"] = ResizeWidth(main); result["passed"] = true; return result;
    }
    static double SavedResizeWidth(string directory) {
        string file = Path.Combine(directory, "window-layout.json");
        if (!File.Exists(file)) return -1;
        Require(new FileInfo(file).Length <= 4096, "Owned layout preference unexpectedly exceeds its limit.");
        var value = new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string, object>>(File.ReadAllText(file));
        return System.Convert.ToDouble(value["popupWidth"], System.Globalization.CultureInfo.InvariantCulture);
    }
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
    struct ResizeProcessEntry {
        public uint size, usage, process; public System.UIntPtr heap; public uint module, threads, parent; public int priority; public uint flags;
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=260)] public string executable;
    }
    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)] static extern System.IntPtr CreateToolhelp32Snapshot(uint flags, uint process);
    [System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint="Process32FirstW", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] static extern bool ResizeProcessFirst(System.IntPtr snapshot, ref ResizeProcessEntry entry);
    [System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint="Process32NextW", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] static extern bool ResizeProcessNext(System.IntPtr snapshot, ref ResizeProcessEntry entry);
    [System.Runtime.InteropServices.DllImport("kernel32.dll")] static extern bool CloseHandle(System.IntPtr handle);
    static System.Collections.Generic.List<long[]> ResizeOwnedProcessSnapshot(Process app) {
        var rows = new System.Collections.Generic.List<int[]>(); System.IntPtr snapshot = CreateToolhelp32Snapshot(2, 0);
        Require(snapshot != System.IntPtr.Zero && snapshot != new System.IntPtr(-1), "Own process cleanup snapshot is unavailable.");
        try {
            ResizeProcessEntry entry = new ResizeProcessEntry(); entry.size = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(ResizeProcessEntry));
            bool next = ResizeProcessFirst(snapshot, ref entry);
            while (next) { Require(rows.Count < 4096, "Process metadata snapshot exceeded its bound."); rows.Add(new int[] { (int)entry.process, (int)entry.parent }); next = ResizeProcessNext(snapshot, ref entry); }
        } finally { CloseHandle(snapshot); }
        var own = new System.Collections.Generic.List<int>(); own.Add(app.Id);
        for (int depth = 0; depth < 16; depth++) {
            int before = own.Count;
            foreach (int[] row in rows) if (own.Contains(row[1]) && !own.Contains(row[0])) { Require(own.Count < 64, "Own process tree exceeded its bound."); own.Add(row[0]); }
            if (before == own.Count) break;
        }
        var result = new System.Collections.Generic.List<long[]>(); long started = app.StartTime.ToUniversalTime().Ticks;
        foreach (int process in own) if (process != app.Id) try { using (Process child = Process.GetProcessById(process)) { long time = child.StartTime.ToUniversalTime().Ticks; if (time >= started) result.Add(new long[] { process, time }); } } catch (System.ArgumentException) { }
        return result;
    }
    static string ResizeProbeQuote(string value) {
        Require(value.IndexOf('"') < 0 && value.IndexOf('\r') < 0 && value.IndexOf('\n') < 0, "Unexpected diagnostic argument."); return "\"" + value + "\"";
    }
    static System.Collections.Generic.Dictionary<string, object> ResizeFailureGeometryProbe(Process app, System.IntPtr main, string executable, string expectedHash, string script, int port) {
        Require((GetAsyncKeyState(1) & 0x8000) == 0, "Geometry observation refused while the generated mouse button is held.");
        Require(activeResizeObservation != null && activeResizeObservation.ContainsKey("targetProbes"), "Failed resize has no owned target metadata.");
        var targets = (System.Collections.Generic.List<object>)activeResizeObservation["targetProbes"];
        var target = (System.Collections.Generic.Dictionary<string, object>)targets[targets.Count - 1]; int[] point = (int[])target["targetPhysicalXY"];
        string powershell = Path.Combine(System.Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        var start = new ProcessStartInfo(powershell); start.UseShellExecute = false; start.CreateNoWindow = true; start.RedirectStandardOutput = true; start.RedirectStandardError = true;
        start.Arguments = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File " + ResizeProbeQuote(script) +
            " -ApplicationProcessId " + app.Id + " -ApplicationStartTimeUtcTicks " + app.StartTime.ToUniversalTime().Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture) +
            " -ApplicationPath " + ResizeProbeQuote(executable) + " -ApplicationSha256 " + expectedHash +
            " -MainHwnd " + main.ToInt64().ToString(System.Globalization.CultureInfo.InvariantCulture) + " -DebugPort " + port +
            " -TargetPhysicalX " + point[0] + " -TargetPhysicalY " + point[1] + " -IsolatedTestSession";
        using (Process helper = Process.Start(start)) {
            var output = helper.StandardOutput.ReadToEndAsync(); var error = helper.StandardError.ReadToEndAsync();
            if (!helper.WaitForExit(20000)) { helper.Kill(); helper.WaitForExit(5000); return new System.Collections.Generic.Dictionary<string, object> { { "ok", false }, { "failedPhase", "whole-helper-deadline" }, { "deadlineMilliseconds", 20000 }, { "ownHelperStopped", helper.HasExited } }; }
            Require(output.Wait(2000) && error.Wait(2000), "Diagnostic output pipes did not close.");
            Require(output.Result.Length <= 131072 && error.Result.Length <= 8192, "Diagnostic output exceeded its bound.");
            var result = new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string, object>>(output.Result.Trim());
            result["helperExitCode"] = helper.ExitCode; result["helperDeadlineMilliseconds"] = 20000; result["stderrCharacters"] = error.Result.Length; result["ownHelperStopped"] = helper.HasExited; return result;
        }
    }
    static void ResizeFinishProbeCleanup(System.Collections.Generic.List<long[]> children, int port, System.Collections.Generic.Dictionary<string, object> report) {
        var result = new System.Collections.Generic.Dictionary<string, object>(); report["geometryProbeCleanup"] = result;
        bool clean = !report.ContainsKey("geometryCleanupSnapshotExceptionType");
        var stopped = new System.Collections.Generic.List<object>(); result["verifiedOwnProcesses"] = stopped;
        for (int index = children.Count - 1; index >= 0; index--) {
            long[] row = children[index]; var item = new System.Collections.Generic.Dictionary<string, object> { { "processId", row[0] }, { "startTimeUtcTicks", row[1] } }; stopped.Add(item);
            try { using (Process child = Process.GetProcessById((int)row[0])) { bool same = child.StartTime.ToUniversalTime().Ticks == row[1]; item["startTimeMatches"] = same; if (same && !child.HasExited) { child.Kill(); child.WaitForExit(3000); } item["originalProcessGone"] = !same || child.HasExited; } }
            catch (System.ArgumentException) { item["originalProcessGone"] = true; }
            catch (System.Exception error) { item["cleanupExceptionType"] = error.GetType().FullName; }
            if (!item.ContainsKey("originalProcessGone") || !(bool)item["originalProcessGone"]) clean = false;
        }
        bool closed = false; Stopwatch clock = Stopwatch.StartNew();
        do { closed = true; foreach (var endpoint in System.Net.NetworkInformation.IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners()) if (endpoint.Port == port) closed = false; if (!closed) System.Threading.Thread.Sleep(25); } while (!closed && clock.ElapsedMilliseconds < 3000);
        result["port"] = port; result["portClosed"] = closed; result["noUnknownProcessKilled"] = true; result["ok"] = clean && closed;
        if (!clean || !closed) report["ok"] = false;
    }
    public static System.Collections.Generic.Dictionary<string, object> RunResize(string executable, bool isolatedTestSession) {
        return RunResize(executable, isolatedTestSession, null, null);
    }
    public static System.Collections.Generic.Dictionary<string, object> RunResize(string executable, bool isolatedTestSession, string geometryProbeScript, string expectedApplicationHash) {
        Require(isolatedTestSession && System.Environment.OSVersion.Platform == System.PlatformID.Win32NT &&
            System.Environment.GetEnvironmentVariable("GITHUB_ACTIONS") == "true" &&
            System.Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT") == "github-hosted" && System.Environment.UserInteractive,
            "ISOLATION_REQUIRED: Full-window drag setup is confined to an unlocked ephemeral GitHub-hosted desktop.");
        foreach (Process existing in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable))) using (existing)
            Require(existing.HasExited, "An EchoLingo process already runs; refused to touch the daily app.");
        string token = System.Guid.NewGuid().ToString("N"), root = Path.Combine(Path.GetTempPath(), "echolingo-resize-" + System.Guid.NewGuid().ToString("N"));
        var owned = new System.Collections.Generic.List<string>(); Process app = null;
        var report = new System.Collections.Generic.Dictionary<string, object> {
            { "ok", false }, { "actualWindowsResizeTested", false }, { "fakeIpcUsed", false }, { "userContentRead", false },
            { "clipboardRead", false }, { "externalApiUsed", false }, { "physicalWindows10Tested", false }, { "dwmFrameRateMeasured", false }
        };
        activeResizeObservation = null;
        int geometryPort = 0;
        if (geometryProbeScript != null) {
            Require(File.Exists(geometryProbeScript) && Path.GetFileName(geometryProbeScript) == "windows-webview-geometry-probe.ps1", "Exact geometry helper path is unavailable.");
            Require(expectedApplicationHash != null && System.Text.RegularExpressions.Regex.IsMatch(expectedApplicationHash, "^[a-f0-9]{64}$"), "Geometry probe requires the exact application hash.");
            var listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
            try { listener.Start(); geometryPort = ((System.Net.IPEndPoint)listener.LocalEndpoint).Port; } finally { listener.Stop(); }
            report["geometryProbeConfiguration"] = new System.Collections.Generic.Dictionary<string, object> { { "requested", true }, { "port", geometryPort }, { "scope", "own-child-process-environment-only" }, { "noOriginalAcceptanceChanges", true } };
        }
        var fullWindowDrag = new System.Collections.Generic.Dictionary<string, object> {
            { "scope", "ephemeral-github-hosted-interactive-session" }, { "getAction", 0x0026 }, { "setAction", 0x0025 },
            { "flags", 0 }, { "profileUpdated", false }, { "settingChangeBroadcast", false },
            { "enableSetAttempted", false }, { "restoreSetAttempted", false }, { "restoreRequired", false }, { "restoreVerified", false }
        };
        report["fullWindowDrag"] = fullWindowDrag;
        bool fullWindowDragInitialKnown = false, restoreFullWindowDrag = false; int initialFullWindowDrag = 0;
        string stage = "read-isolated-desktop-full-window-drag";
        try {
            initialFullWindowDrag = ReadResizeFullWindowDrag(fullWindowDrag, "initial"); fullWindowDragInitialKnown = true;
            if (initialFullWindowDrag == 0) {
                // RDP/Server may draw only an outline while the button is held.
                // The existing live-size assertions require full-window drag;
                // establish that explicit test precondition, without relaxing them.
                restoreFullWindowDrag = true; fullWindowDrag["restoreRequired"] = true;
                stage = "enable-isolated-desktop-full-window-drag";
                SetResizeFullWindowDrag(fullWindowDrag, "enable", 1);
            }
            Require(ReadResizeFullWindowDrag(fullWindowDrag, "effective") == 1, "Full-window dragging is unavailable; no live-size gesture sent.");
            stage = "claim-isolated-data";
            string roaming = Path.Combine(KnownFolder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"), Identifier);
            string local = Path.Combine(KnownFolder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"), Identifier);
            Claim(roaming, token, owned); Claim(local, token, owned); Claim(root, token, owned);
            var settings = new System.Collections.Generic.Dictionary<string, object> {
                { "providers", new object[0] }, { "ocrProviders", new object[0] }, { "saveHistory", false }, { "theme", "light" },
                { "autoHideSeconds", 0 }, { "maxHistory", 20 }, { "shortcutDefaultsVersion", 1 },
                { "shortcuts", new System.Collections.Generic.Dictionary<string, object> {
                    { "selection", "Alt+D" }, { "capture", "Alt+S" }, { "ocr", "Alt+Shift+S" }, { "silentOcr", "Alt+C" }, { "input", "Alt+A" } } }
            };
            File.WriteAllText(Path.Combine(roaming, "settings.json"), new JavaScriptSerializer().Serialize(settings), new System.Text.UTF8Encoding(false));
            SetProcessDpiAwarenessContext(new System.IntPtr(-4));
            using (var form = new System.Windows.Forms.Form()) using (var editor = new System.Windows.Forms.TextBox()) {
                form.Text = "EchoLingo generated resize input source"; form.StartPosition = System.Windows.Forms.FormStartPosition.Manual;
                form.SetBounds(20, 100, 320, 180); editor.SetBounds(15, 15, 280, 90); editor.Multiline = true; editor.Text = "Generated resize fixture input"; form.Controls.Add(editor);
                bool done = false;
                form.FormClosing += delegate(object sender, System.Windows.Forms.FormClosingEventArgs args) { if (!done) args.Cancel = true; };
                form.Shown += delegate {
                    System.IntPtr sourceHandle = form.Handle, editorHandle = editor.Handle;
                    var worker = new System.Threading.Thread(delegate() {
                        System.IntPtr main = System.IntPtr.Zero;
                        try {
                            Require(SetThreadDpiAwarenessContext(new System.IntPtr(-4)) != System.IntPtr.Zero, "Physical test coordinates are unavailable.");
                            stage = "launch-real-stage-app";
                            var start = new ProcessStartInfo(executable); start.UseShellExecute = false; start.CreateNoWindow = true;
                            string temp = Path.Combine(root, "Temp"); Directory.CreateDirectory(temp);
                            start.EnvironmentVariables["TEMP"] = temp; start.EnvironmentVariables["TMP"] = temp;
                            start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"] = Path.Combine(local, "fixture-webview");
                            if (geometryPort != 0) {
                                Require(string.IsNullOrEmpty(start.EnvironmentVariables["WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"]), "Unexpected inherited WebView arguments; refused to change the diagnostic baseline.");
                                start.EnvironmentVariables["WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"] = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=" + geometryPort;
                            }
                            var startup = new System.Collections.Generic.Dictionary<string, object> {
                                { "readinessDeadlineMilliseconds", 20000 }, { "trayPolls", 0 }, { "mainFirstObservedMilliseconds", -1.0 },
                                { "trayFirstObservedMilliseconds", -1.0 }, { "earliestColdStartKeyTested", false }, { "nativePreparationShowRequests", 0 }
                            };
                            report["inputShortcutStartupReadiness"] = startup;
                            stage = "input-shortcut-no-initial-conflict";
                            Stopwatch startupObservation = Stopwatch.StartNew();
                            var initialProbe = ResizeInputRegistrationProbe(); startup["initialProbe"] = initialProbe;
                            startup["initialProbeObservedMilliseconds"] = startupObservation.Elapsed.TotalMilliseconds;
                            Require((bool)initialProbe["acquired"] && (bool)initialProbe["released"], "Alt+A is not initially available/released on this isolated desktop; no app launched.");
                            stage = "launch-real-stage-app";
                            app = Process.Start(start); report["applicationProcessId"] = app.Id;
                            Require(app.WaitForInputIdle(15000), "New app native message loop did not become input-idle.");
                            startup["nativeInputIdleObservedMilliseconds"] = startupObservation.Elapsed.TotalMilliseconds;
                            main = System.IntPtr.Zero;
                            stage = "wait-own-native-setup-milestone";
                            Wait(delegate {
                                Require(!app.HasExited, "New app exited before its HWND became ready."); main = MainWindow(app.Id);
                                int trayCount = ResizeOwnedTrayCount(app.Id); int poll = (int)startup["trayPolls"];
                                if (poll == 0) startup["firstPollTrayCount"] = trayCount;
                                startup["trayPolls"] = poll + 1; startup["lastTrayCount"] = trayCount;
                                if (main != System.IntPtr.Zero && (double)startup["mainFirstObservedMilliseconds"] < 0) startup["mainFirstObservedMilliseconds"] = startupObservation.Elapsed.TotalMilliseconds;
                                if (trayCount == 1 && (double)startup["trayFirstObservedMilliseconds"] < 0) startup["trayFirstObservedMilliseconds"] = startupObservation.Elapsed.TotalMilliseconds;
                                return main != System.IntPtr.Zero && trayCount == 1;
                            }, 20000, "No unique owned main/tray HWND setup milestone became ready.");
                            stage = "input-shortcut-post-setup-registration";
                            var finalProbe = ResizeInputRegistrationProbe(); startup["postSetupProbe"] = finalProbe;
                            startup["postSetupProbeObservedMilliseconds"] = startupObservation.Elapsed.TotalMilliseconds;
                            Require(!(bool)finalProbe["acquired"] && (int)finalProbe["lastError"] == 1409 && (bool)finalProbe["released"], "Alt+A is not registered after own setup attempted registration; no shortcut sent.");
                            // An occupied binding alone does not identify its owner; the one
                            // actual Alt+A and unchanged popup gate below must still pass.
                            Require(!IsWindowVisible(main), "Fresh dedicated app did not start silently.");
                            stage = "single-actual-input-shortcut";
                            var readiness = new System.Collections.Generic.Dictionary<string, object> {
                                { "deadlineMilliseconds", 20000 }, { "shortcutPresses", 0 }, { "insertedKeyboardEvents", 0 },
                                { "pollCount", 0 }, { "visiblePolls", 0 }, { "foregroundMainPolls", 0 }, { "sourceQueries", 0 },
                                { "sourceAvailablePolls", 0 }, { "sourceQueryExceptions", 0 }, { "lastSourceQueryAttempted", false },
                                { "lastSourceValueAvailable", false }, { "lastSourceValueKnown", false }
                            };
                            report["inputPopupReadiness"] = readiness;
                            Ui(form, delegate { form.Activate(); readiness["sourceSetForegroundReturned"] = SetForegroundWindow(form.Handle); editor.Focus();
                                readiness["sourceManagedContainsFocus"] = form.ContainsFocus; readiness["sourceManagedEditorFocused"] = editor.Focused; });
                            Wait(delegate { return GetForegroundWindow() == form.Handle; }, 3000, "Generated source is not foreground; no shortcut sent.");
                            readiness["beforeShortcut"] = ResizeStartupMetadata(app, main, sourceHandle, editorHandle);
                            Shortcut(form, 0x41);
                            readiness["shortcutPresses"] = 1; readiness["insertedKeyboardEvents"] = 4;
                            Stopwatch inputObservation = Stopwatch.StartNew();
                            try {
                                Wait(delegate {
                                    bool visible = IsWindowVisible(main), foreground = GetForegroundWindow() == main, sourceAvailable = false;
                                    readiness["pollCount"] = (int)readiness["pollCount"] + 1;
                                    if (visible) readiness["visiblePolls"] = (int)readiness["visiblePolls"] + 1;
                                    if (foreground) readiness["foregroundMainPolls"] = (int)readiness["foregroundMainPolls"] + 1;
                                    readiness["lastNativeVisible"] = visible; readiness["lastForegroundIsMain"] = foreground;
                                    readiness["lastSourceQueryAttempted"] = visible && foreground;
                                    readiness["lastSourceValueKnown"] = false; readiness["lastSourceValueAvailable"] = false;
                                    // Preserve the original short-circuit gate/query order. A skipped
                                    // UIA query remains unknown, rather than being called an empty editor.
                                    if (visible && foreground) {
                                        readiness["sourceQueries"] = (int)readiness["sourceQueries"] + 1;
                                        Stopwatch query = Stopwatch.StartNew();
                                        try { sourceAvailable = SourceValue(main) != null; readiness["lastSourceValueKnown"] = true; readiness["lastSourceValueAvailable"] = sourceAvailable;
                                            if (sourceAvailable) readiness["sourceAvailablePolls"] = (int)readiness["sourceAvailablePolls"] + 1; }
                                        catch (System.Exception error) { readiness["sourceQueryExceptions"] = (int)readiness["sourceQueryExceptions"] + 1; readiness["lastSourceQueryHResult"] = error.HResult; throw; }
                                        finally { readiness["lastSourceQueryMilliseconds"] = query.Elapsed.TotalMilliseconds; }
                                    }
                                    return visible && foreground && sourceAvailable;
                                }, 20000, "One real Alt+A did not produce an editable focused popup.");
                            } finally {
                                readiness["observedMilliseconds"] = inputObservation.Elapsed.TotalMilliseconds;
                                readiness["afterObservation"] = ResizeStartupMetadata(app, main, sourceHandle, editorHandle);
                            }
                            stage = "long-generated-source";
                            string text = string.Join("\n", new string[] {
                                "Generated resize fixture: long source wraps repeatedly while the window changes width. No Enter is sent and no translation provider is enabled.",
                                "The actual textarea and ResizeObserver execute in the stage application. This test does not replace IPC or dispatch synthetic browser resize events.",
                                "The left edge must retain its opposite anchor, both edges must follow the pointer, and releasing the mouse must preserve the chosen width."
                            });
                            SetGeneratedResizeSource(main, text);
                            uint dpi = GetDpiForWindow(main); Require(dpi >= 96 && dpi <= 384, "Unexpected fixture DPI."); double scale = dpi / 96.0;
                            RECT before = ResizeBounds(main); var work = System.Windows.Forms.Screen.FromHandle(main).WorkingArea;
                            Require(work.Width >= (before.right - before.left) + 240, "Fixture desktop is too narrow for both generated edge drags; no product failure inferred.");
                            Require(SetWindowPos(main, System.IntPtr.Zero, work.Left + (work.Width - ResizeWidth(main)) / 2, work.Top + 20, 0, 0, 0x1 | 0x4 | 0x10), "Could not position the own popup before test gestures.");
                            report["nativePreparationMovesOnly"] = true;
                            stage = "actual-east-drag"; report["east"] = DragResize(app, main, false, 96, true);
                            stage = "actual-west-drag"; report["west"] = DragResize(app, main, true, 64, true);
                            int finalWidth = ResizeWidth(main); RECT client;
                            Require(GetClientRect(main, out client), "Actual popup client bounds are unavailable.");
                            double preference = (client.right - client.left) / scale;
                            stage = "persist-popup-width";
                            Wait(delegate { return System.Math.Abs(SavedResizeWidth(roaming) - preference) <= 2; }, 5000, "Actual drag width was not saved as the logical popup preference.");
                            report["savedLogicalPopupWidth"] = SavedResizeWidth(roaming); report["windowDpi"] = dpi;
                            string saved = File.ReadAllText(Path.Combine(roaming, "window-layout.json"));
                            stage = "management-does-not-overwrite-popup-preference";
                            Invoke(main, "\u66f4\u591a"); Invoke(main, "\u8bbe\u7f6e");
                            Wait(delegate { var back = Element(main, "\u8fd4\u56de\u7ffb\u8bd1"); return back != null && !back.Current.IsOffscreen; }, 5000, "Actual settings presentation did not open.");
                            stage = "management-native-resize-frame";
                            report["managementResizeFrame"] = ManagementResizeFrame(app, main);
                            stage = "management-width-retention";
                            report["managementDrag"] = DragResize(app, main, false, -64, true);
                            RECT managementClient; Require(GetClientRect(main, out managementClient), "Settings client bounds are unavailable.");
                            int verticalDistance = -(int)System.Math.Round(48 * scale);
                            Require(managementClient.bottom - managementClient.top + verticalDistance >= 480 * scale, "Fixture display has no space above the settings minimum for the generated vertical resize; no product failure inferred.");
                            stage = "management-height-retention";
                            report["managementVerticalDrag"] = DragManagementHeight(app, main, verticalDistance);
                            stage = "management-corner-retention";
                            int cornerDistance = -(int)System.Math.Round(24 * scale);
                            Require(GetClientRect(main, out managementClient) && managementClient.bottom - managementClient.top + cornerDistance >= 480 * scale, "Fixture has no space above the settings minimum for the corner resize; no product failure inferred.");
                            report["managementCornerDrag"] = DragManagementHeight(app, main, cornerDistance, true);
                            Require(File.ReadAllText(Path.Combine(roaming, "window-layout.json")) == saved, "Management resize overwrote the popup width preference.");
                            Invoke(main, "\u8fd4\u56de\u7ffb\u8bd1");
                            Wait(delegate { return System.Math.Abs(ResizeWidth(main) - finalWidth) <= 5 && SourceValue(main) == text; }, 5000, "Return from management failed to restore the saved popup width/source.");
                            report["managementPreservedPreference"] = true;
                            stage = "hidden-native-resize-never-shows";
                            Invoke(main, "\u9690\u85cf\u7a97\u53e3"); Wait(delegate { return !IsWindowVisible(main); }, 3000, "Actual close control did not hide the popup.");
                            RequireUniqueOwnedMainWindow(app, main); RECT hidden = ResizeBounds(main);
                            Require(SetWindowPos(main, System.IntPtr.Zero, 0, 0, hidden.right - hidden.left + 24, hidden.bottom - hidden.top, 0x2 | 0x4 | 0x10), "Own hidden HWND resize was rejected.");
                            Require(ResizeWidth(main) != hidden.right - hidden.left, "Hidden resize stimulus did not change actual native bounds.");
                            Stopwatch hiddenObservation = Stopwatch.StartNew();
                            while (hiddenObservation.ElapsedMilliseconds < 500) { Require(!IsWindowVisible(main), "Resize/reflow showed the hidden popup."); System.Threading.Thread.Sleep(8); }
                            report["hiddenResizeStayedHidden"] = true; report["actualWindowsResizeTested"] = true; report["ok"] = true;
                        } catch (System.Exception error) {
                            report["failedStage"] = stage; report["error"] = error.ToString(); if (activeResizeObservation != null) report["activeResizeObservation"] = activeResizeObservation;
                            if (geometryPort != 0 && stage == "management-width-retention" && app != null && !app.HasExited) {
                                try { report["failureGeometryProbe"] = ResizeFailureGeometryProbe(app, main, executable, expectedApplicationHash, geometryProbeScript, geometryPort); }
                                catch (System.Exception probeError) { report["failureGeometryProbe"] = new System.Collections.Generic.Dictionary<string, object> { { "ok", false }, { "failedPhase", "fixture-probe-launch" }, { "exceptionType", probeError.GetType().FullName } }; }
                            }
                        }
                        finally {
                            INPUT release = new INPUT(); release.type = 0; release.data.mouse.flags = 4;
                            SendInput(2, new INPUT[] { release, Key(0x12, true) }, System.Runtime.InteropServices.Marshal.SizeOf(typeof(INPUT)));
                            var geometryChildren = new System.Collections.Generic.List<long[]>();
                            if (geometryPort != 0 && app != null && !app.HasExited) try { geometryChildren = ResizeOwnedProcessSnapshot(app); report["geometryOwnedProcessSnapshot"] = geometryChildren; } catch (System.Exception snapshotError) { report["geometryCleanupSnapshotExceptionType"] = snapshotError.GetType().FullName; }
                            if (app != null) try { if (!app.HasExited) { app.Kill(); app.WaitForExit(5000); } Require(app.HasExited, "Own test app failed to stop."); report["ownApplicationStopped"] = true; }
                                catch (System.Exception error) { report["ok"] = false; report["cleanupError"] = error.Message; }
                            if (geometryPort != 0) try { ResizeFinishProbeCleanup(geometryChildren, geometryPort, report); } catch (System.Exception cleanupError) { report["ok"] = false; report["geometryProbeCleanupExceptionType"] = cleanupError.GetType().FullName; }
                            Ui(form, delegate { done = true; form.Close(); });
                        }
                    });
                    worker.IsBackground = true; worker.Start();
                };
                System.Windows.Forms.Application.Run(form);
            }
        } catch (System.Exception error) { report["failedStage"] = stage; report["error"] = error.Message; }
        finally {
            if (fullWindowDragInitialKnown) {
                try {
                    if (restoreFullWindowDrag) SetResizeFullWindowDrag(fullWindowDrag, "restore", initialFullWindowDrag);
                    Require(ReadResizeFullWindowDrag(fullWindowDrag, "restored") == initialFullWindowDrag, "The isolated desktop full-window drag setting was not restored.");
                    fullWindowDrag["restoreVerified"] = true;
                } catch (System.Exception error) { report["ok"] = false; report["fullWindowDragRestoreError"] = error.Message; }
            }
            bool clean = true;
            for (int at = owned.Count - 1; at >= 0; at--) try { Clean(owned[at], token); } catch (System.Exception error) { clean = false; report["ok"] = false; report["cleanupError"] = error.Message; }
            report["ownedDirectoriesRemoved"] = clean;
        }
        return report;
    }
}
