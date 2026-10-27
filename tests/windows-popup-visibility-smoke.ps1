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
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions, UIAutomationClient, UIAutomationTypes
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

public static class EchoLingoPopupVisibilitySmoke {
    const string Identifier = "io.github.blueeeecho.echolingo", Marker = ".echolingo-visibility-owned";
    delegate bool Enumerate(IntPtr window, IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(Enumerate callback, IntPtr unused);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
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
    static IntPtr MainWindow(int process) {
        IntPtr result = IntPtr.Zero; long largest = 0;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; RECT bounds; GetWindowThreadProcessId(window, out owner);
            if (owner == process && GetWindowRect(window, out bounds)) {
                long area = (long)(bounds.right - bounds.left) * (bounds.bottom - bounds.top);
                if (bounds.right - bounds.left >= 200 && bounds.bottom - bounds.top >= 100 && area > largest) { result = window; largest = area; }
            }
            return true;
        }, IntPtr.Zero);
        return result;
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
    static AutomationElement Element(IntPtr app, string name) {
        return AutomationElement.FromHandle(app).FindFirst(TreeScope.Descendants,
            new PropertyCondition(AutomationElement.NameProperty, name));
    }
    static void Invoke(IntPtr app, string name) {
        AutomationElement element = null;
        Wait(delegate { element = Element(app, name); return element != null; }, 5000, "New app accessibility control missing: " + name);
        object pattern; Require(element.TryGetCurrentPattern(InvokePattern.Pattern, out pattern), "Control cannot be invoked: " + name);
        ((InvokePattern)pattern).Invoke();
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
            { "physicalWindows10Tested", false }, { "altTabKeySequenceTested", false }, { "screenshotsTested", false } };
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
            using (Form form = new Form()) using (TextBox source = new TextBox()) {
                form.Text = "EchoLingo generated visibility source"; form.Bounds = new Rectangle(30, 120, 720, 420);
                source.Multiline = true; source.SetBounds(20, 20, 660, 100); source.Text = "EchoLingo popup visibility generated source 2468";
                form.Controls.Add(source); int clicksReachedSource = 0; form.MouseDown += delegate { Interlocked.Increment(ref clicksReachedSource); };
                bool done = false; Exception failure = null;
                form.FormClosing += delegate(object sender, FormClosingEventArgs args) { if (!done) args.Cancel = true; };
                form.Shown += delegate {
                    Thread worker = new Thread(delegate() {
                        POINT original; bool restorePointer = GetPhysicalCursorPos(out original);
                        try {
                            Require(SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero, "Physical fixture coordinates unavailable.");
                            string childLocal = Path.Combine(root, "Local"), childTemp = Path.Combine(root, "Temp"); Directory.CreateDirectory(childLocal); Directory.CreateDirectory(childTemp);
                            ProcessStartInfo start = new ProcessStartInfo(executable); start.UseShellExecute = false; start.CreateNoWindow = true;
                            start.EnvironmentVariables["LOCALAPPDATA"] = childLocal; start.EnvironmentVariables["APPDATA"] = Path.Combine(root, "UnusedRoaming");
                            start.EnvironmentVariables["TEMP"] = childTemp; start.EnvironmentVariables["TMP"] = childTemp;
                            start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"] = Path.Combine(local, "fixture-webview");
                            app = Process.Start(start); report["actualApplicationTested"] = true; report["applicationProcessId"] = app.Id;
                            IntPtr main = IntPtr.Zero;
                            Wait(delegate { main = MainWindow(app.Id); return main != IntPtr.Zero; }, 20000, "New app window not created.");
                            Action sourceFocus = delegate { Ui(form, delegate { form.Activate(); source.Focus(); source.SelectAll(); });
                                Require(SetForegroundWindow(form.Handle), "Generated source foreground was rejected.");
                                Wait(delegate { return GetForegroundWindow() == form.Handle; }, 2000, "Generated source not foreground."); };
                            Action moveApp = delegate { Require(SetWindowPos(main, IntPtr.Zero, Math.Max(300, Screen.PrimaryScreen.Bounds.Right - 720), 20, 0, 0, 0x1 | 0x4 | 0x10), "Could not position own app fixture."); };
                            // Explicit warm-up, not a retried test hotkey: wait
                            // for actual WebView controls before dismissal cases.
                            sourceFocus(); Shortcut(form, 0x41);
                            Wait(delegate { return IsWindowVisible(main) && Element(main, "\u9489\u4f4f\u7a97\u53e3") != null; }, 20000, "New app WebView did not become ready.");
                            Invoke(main, "\u9690\u85cf\u7a97\u53e3"); Wait(delegate { return !IsWindowVisible(main); }, 5000, "Warm-up popup did not hide.");
                            sourceFocus(); Shortcut(form, 0x44);
                            Wait(delegate { return IsWindowVisible(main); }, 12000, "Selected-text popup did not show."); moveApp();
                            Require(GetForegroundWindow() == form.Handle, "Passive selected-text popup stole source foreground.");
                            int before = clicksReachedSource; Stopwatch outside = Stopwatch.StartNew();
                            Click(55, 500, form, main, true);
                            Wait(delegate { return !IsWindowVisible(main); }, 2000, "Short source click failed to hide unpinned popup.");
                            Wait(delegate { return clicksReachedSource > before; }, 2000, "Outside observer swallowed the source click.");
                            report["passiveOutsideClickPassed"] = true; report["outsideHideObservedMs"] = outside.ElapsedMilliseconds;
                            sourceFocus(); Shortcut(form, 0x41);
                            Wait(delegate { return IsWindowVisible(main) && GetForegroundWindow() == main; }, 5000, "Explicit input did not focus the new app."); moveApp();
                            RECT bounds; Require(GetWindowRect(main, out bounds), "Own app bounds unavailable.");
                            Click(bounds.left + 70, bounds.top + 70, form, main, false); Thread.Sleep(150);
                            Require(IsWindowVisible(main), "Inside click hid the popup."); report["insideClickRetainedPassed"] = true;
                            DragOwnToolbar(main); report["actualToolbarDragRetainedPassed"] = true;
                            sourceFocus(); Wait(delegate { return !IsWindowVisible(main); }, 2000, "Actual foreground deactivation failed to hide input popup.");
                            report["focusDeactivationPassed"] = true;
                            Shortcut(form, 0x41); Wait(delegate { return IsWindowVisible(main); }, 5000, "Pin test input did not show."); moveApp();
                            Invoke(main, "\u9489\u4f4f\u7a97\u53e3"); Wait(delegate { return Element(main, "\u53d6\u6d88\u9489\u4f4f") != null; }, 5000, "Pin state did not update.");
                            sourceFocus(); Click(55, 500, form, main, true); Thread.Sleep(250);
                            Require(IsWindowVisible(main), "Pinned popup hid on outside click/focus loss."); report["pinnedOutsideRetainedPassed"] = true;
                            Invoke(main, "\u53d6\u6d88\u9489\u4f4f"); Wait(delegate { return Element(main, "\u9489\u4f4f\u7a97\u53e3") != null; }, 5000, "Unpin state did not update.");
                            Click(55, 500, form, main, true); Wait(delegate { return !IsWindowVisible(main); }, 2000, "Unpinned popup did not resume outside dismissal.");
                            report["unpinOutsideHidePassed"] = true;
                            Shortcut(form, 0x41); Wait(delegate { return IsWindowVisible(main); }, 5000, "Management test input did not show.");
                            Invoke(main, "\u66f4\u591a"); Invoke(main, "\u8bbe\u7f6e");
                            Wait(delegate { return Element(main, "\u8fd4\u56de\u7ffb\u8bd1") != null; }, 5000, "Management did not open.");
                            sourceFocus(); Click(55, 500, form, main, true); Thread.Sleep(250);
                            Require(IsWindowVisible(main), "Management view hid on outside interaction."); report["managementOutsideRetainedPassed"] = true;
                            report["ok"] = true;
                        } catch (Exception error) { failure = error; }
                        finally {
                            IntPtr foreground = GetForegroundWindow();
                            if (foreground == form.Handle || (app != null && foreground == MainWindow(app.Id))) {
                                INPUT release = new INPUT(); release.type = 0; release.data.mouse.flags = 4;
                                SendInput(4, new INPUT[] { Key(0x12, true), Key(0x44, true), Key(0x41, true), release }, Marshal.SizeOf(typeof(INPUT)));
                            }
                            if (app != null) { try { if (!app.HasExited) { app.Kill(); app.WaitForExit(5000); } } catch { } }
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
            for (int index = owned.Count - 1; index >= 0; index--) {
                try { Clean(owned[index], token); } catch (Exception error) { report["ok"] = false; report["cleanupError"] = error.Message; }
            }
        }
        return new JavaScriptSerializer().Serialize(report);
    }
}
'@
    $references = @([System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location,
        [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,
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
