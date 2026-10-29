// Compiled with the existing visibility harness as a partial class. Only
// RunResize executes: its other visibility/OCR/clipboard cases are not run.
public static partial class EchoLingoPopupVisibilitySmoke {
    static System.Collections.Generic.Dictionary<string, object> activeResizeObservation;
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern uint GetDpiForWindow(System.IntPtr window);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetClientRect(System.IntPtr window, out RECT bounds);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread, ref ResizeGuiInfo info);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)] static extern bool RegisterHotKey(System.IntPtr window, int id, uint modifiers, uint key);
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)] static extern bool UnregisterHotKey(System.IntPtr window, int id);
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    struct ResizeGuiInfo {
        public uint size, flags;
        public System.IntPtr active, focus, capture, menu, move, caret;
        public RECT caretBounds;
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
        RequireUniqueOwnedMainWindow(app, main);
        Require(IsWindowVisible(main) && GetForegroundWindow() == main, "Only the exact foreground app HWND may receive the generated resize.");
        RECT before = ResizeBounds(main); int startWidth = before.right - before.left;
        int x = west ? before.left + 2 : before.right - 2, y = (before.top + before.bottom) / 2;
        Require(SetCursorPos(x, y), "Could not position the generated resize pointer.");
        POINT point = new POINT(); point.x = x; point.y = y;
        uint owner; System.IntPtr hit = WindowFromPoint(point); GetWindowThreadProcessId(hit, out owner);
        Require(owner == app.Id && GetAncestor(hit, 2) == main, "Resize edge is occluded or belongs to another window; no button-down sent.");
        var samples = new System.Collections.Generic.List<int>(); bool held = false;
        var result = new System.Collections.Generic.Dictionary<string, object> {
            { "edge", west ? "west" : "east" }, { "initialPhysicalWidth", startWidth }, { "deltaPhysicalPixels", distance },
            { "nativeSizingLoopObserved", false }, { "widthSamples", samples }, { "retentionRequired", retainAfterRelease }
        };
        activeResizeObservation = result;
        var motion = new System.Collections.Generic.List<object>(); result["boundedMotionObservations"] = motion;
        result["initialBounds"] = new int[] { before.left, before.top, before.right, before.bottom };
        try {
            INPUT down = new INPUT(); down.type = 0; down.data.mouse.flags = 2; Send(new INPUT[] { down }); held = true;
            Wait(delegate { Require(IsWindowVisible(main), "Popup hid during edge-down."); return ResizeLoop(main); }, 3000, "Actual native WM move/size loop did not start; resize was not tested.");
            result["nativeSizingLoopObserved"] = true;
            for (int step = 1; step <= 8; step++) {
                Require(GetForegroundWindow() == main && IsWindowVisible(main), "Foreground changed during generated drag.");
                int delta = distance * step / 8, expected = startWidth + delta;
                Require(SetCursorPos(x + (west ? -delta : delta), y), "Could not move the generated resize pointer.");
                result["lastStep"] = step; result["expectedPhysicalWidth"] = expected;
                result["expectedPointer"] = new int[] { x + (west ? -delta : delta), y };
                Wait(delegate {
                    int actual = ResizeWidth(main); result["lastObservedPhysicalWidth"] = actual;
                    POINT pointer; bool pointerKnown = GetPhysicalCursorPos(out pointer);
                    if (motion.Count < 256) motion.Add(new object[] { step, expected, actual, pointerKnown, pointer.x, pointer.y, ResizeLoop(main), (GetAsyncKeyState(1) & 0x8000) != 0 });
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
    static double SavedResizeWidth(string directory) {
        string file = Path.Combine(directory, "window-layout.json");
        if (!File.Exists(file)) return -1;
        Require(new FileInfo(file).Length <= 4096, "Owned layout preference unexpectedly exceeds its limit.");
        var value = new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string, object>>(File.ReadAllText(file));
        return System.Convert.ToDouble(value["popupWidth"], System.Globalization.CultureInfo.InvariantCulture);
    }
    public static System.Collections.Generic.Dictionary<string, object> RunResize(string executable) {
        foreach (Process existing in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable))) using (existing)
            Require(existing.HasExited, "An EchoLingo process already runs; refused to touch the daily app.");
        string token = System.Guid.NewGuid().ToString("N"), root = Path.Combine(Path.GetTempPath(), "echolingo-resize-" + System.Guid.NewGuid().ToString("N"));
        var owned = new System.Collections.Generic.List<string>(); Process app = null;
        var report = new System.Collections.Generic.Dictionary<string, object> {
            { "ok", false }, { "actualWindowsResizeTested", false }, { "fakeIpcUsed", false }, { "userContentRead", false },
            { "clipboardRead", false }, { "externalApiUsed", false }, { "physicalWindows10Tested", false }, { "dwmFrameRateMeasured", false }
        };
        activeResizeObservation = null;
        string stage = "claim-isolated-data";
        try {
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
                        try {
                            Require(SetThreadDpiAwarenessContext(new System.IntPtr(-4)) != System.IntPtr.Zero, "Physical test coordinates are unavailable.");
                            stage = "launch-real-stage-app";
                            var start = new ProcessStartInfo(executable); start.UseShellExecute = false; start.CreateNoWindow = true;
                            string temp = Path.Combine(root, "Temp"); Directory.CreateDirectory(temp);
                            start.EnvironmentVariables["TEMP"] = temp; start.EnvironmentVariables["TMP"] = temp;
                            start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"] = Path.Combine(local, "fixture-webview");
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
                            System.IntPtr main = System.IntPtr.Zero;
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
                            report["managementDrag"] = DragResize(app, main, false, -64, false);
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
                        } catch (System.Exception error) { report["failedStage"] = stage; report["error"] = error.ToString(); if (activeResizeObservation != null) report["activeResizeObservation"] = activeResizeObservation; }
                        finally {
                            INPUT release = new INPUT(); release.type = 0; release.data.mouse.flags = 4;
                            SendInput(2, new INPUT[] { release, Key(0x12, true) }, System.Runtime.InteropServices.Marshal.SizeOf(typeof(INPUT)));
                            if (app != null) try { if (!app.HasExited) { app.Kill(); app.WaitForExit(5000); } Require(app.HasExited, "Own test app failed to stop."); report["ownApplicationStopped"] = true; }
                                catch (System.Exception error) { report["ok"] = false; report["cleanupError"] = error.Message; }
                            Ui(form, delegate { done = true; form.Close(); });
                        }
                    });
                    worker.IsBackground = true; worker.Start();
                };
                System.Windows.Forms.Application.Run(form);
            }
        } catch (System.Exception error) { report["failedStage"] = stage; report["error"] = error.Message; }
        finally {
            bool clean = true;
            for (int at = owned.Count - 1; at >= 0; at--) try { Clean(owned[at], token); } catch (System.Exception error) { clean = false; report["ok"] = false; report["cleanupError"] = error.Message; }
            report["ownedDirectoriesRemoved"] = clean;
        }
        return report;
    }
}
