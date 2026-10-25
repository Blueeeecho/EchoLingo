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
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
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

    static void Assert(bool condition, string message) { if (!condition) throw new InvalidOperationException("ASSERTION_FAILED: " + message); }
    static void OnUi(Form form, Action action) { form.Invoke(action); }
    static void RequireFixtureForeground(Form form) {
        Assert(GetForegroundWindow() == form.Handle, "Dedicated test window lost foreground; no input will be sent to another app.");
    }
    static void Send(Form form, INPUT input) {
        RequireFixtureForeground(form);
        Assert(SendInput(1, new INPUT[] { input }, Marshal.SizeOf(typeof(INPUT))) == 1, "Windows rejected dedicated fixture input.");
    }
    static void Move(Form form, Point point) {
        Rectangle desktop = SystemInformation.VirtualScreen;
        INPUT input = new INPUT();
        input.data.mouse.dx = (int)Math.Round((point.X - desktop.Left) * 65535.0 / (desktop.Width - 1));
        input.data.mouse.dy = (int)Math.Round((point.Y - desktop.Top) * 65535.0 / (desktop.Height - 1));
        input.data.mouse.flags = 0x8000 | 0x4000 | 0x0001;
        Send(form, input);
    }
    static void Button(Form form, uint flags) { INPUT input = new INPUT(); input.data.mouse.flags = flags; Send(form, input); }
    static int ReadyOverlays(int processId) {
        int count = 0;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == processId && IsWindowVisible(window)) {
                long style = GetWindowLongPtr(window, -20).ToInt64();
                long required = 0x08000000L | 0x00080000L | 0x00000020L | 0x00000008L;
                Assert((style & required) == required, "Capture overlay lacks layered/transparent/no-activate/topmost styles.");
                count++;
            }
            return true;
        }, IntPtr.Zero);
        return count;
    }
    static Dictionary<string, object> Trial(Form form, string helper, string mode, Color liveColor) {
        ProcessStartInfo start = new ProcessStartInfo("powershell.exe");
        start.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + helper + "\" -Mode capture-image";
        start.UseShellExecute = false; start.CreateNoWindow = true;
        start.RedirectStandardOutput = true; start.RedirectStandardError = true;
        start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
        using (Process process = Process.Start(start)) {
            Task<string> output = process.StandardOutput.ReadToEndAsync();
            Task<string> error = process.StandardError.ReadToEndAsync();
            try {
                DateTime deadline = DateTime.UtcNow.AddSeconds(25);
                int screens = Screen.AllScreens.Length;
                while (!process.HasExited && ReadyOverlays(process.Id) != screens && DateTime.UtcNow < deadline) Thread.Sleep(30);
                Assert(!process.HasExited && ReadyOverlays(process.Id) == screens, "Live per-display overlays did not become ready.");
                RequireFixtureForeground(form);
                // Change the generated content only AFTER the selector exists.
                // A frozen pre-selection desktop image fails the color check.
                Point first = Point.Empty, last = Point.Empty;
                OnUi(form, delegate {
                    form.BackColor = liveColor; form.Refresh();
                    first = form.PointToScreen(new Point(50, 50));
                    last = form.PointToScreen(new Point(260, 160));
                });
                Thread.Sleep(150);
                Move(form, first); Thread.Sleep(80);
                if (mode == "escape-short") {
                    INPUT down = new INPUT(); down.type = 1; down.data.keyboard.vk = 0x1B;
                    INPUT up = down; up.data.keyboard.flags = 2;
                    RequireFixtureForeground(form);
                    Assert(SendInput(2, new INPUT[] { down, up }, Marshal.SizeOf(typeof(INPUT))) == 2, "Windows rejected a paired short Escape tap.");
                } else if (mode == "escape") {
                    INPUT key = new INPUT(); key.type = 1; key.data.keyboard.vk = 0x1B;
                    Send(form, key); Thread.Sleep(80); key.data.keyboard.flags = 2; Send(form, key);
                } else if (mode == "right") {
                    Button(form, 0x0008); Thread.Sleep(80); Button(form, 0x0010);
                } else {
                    Button(form, 0x0002); Thread.Sleep(80);
                    Move(form, last); Thread.Sleep(100); Button(form, 0x0004);
                }
                Assert(process.WaitForExit(10000), "Capture helper did not finish after the fixture selection/cancellation.");
                JavaScriptSerializer json = new JavaScriptSerializer(); json.MaxJsonLength = 16 * 1024 * 1024;
                Dictionary<string, object> reply = json.Deserialize<Dictionary<string, object>>(output.GetAwaiter().GetResult());
                if (mode != "capture") {
                    Assert(!(bool)reply["ok"] && process.ExitCode != 0 && ((string)reply["error"]).StartsWith("CANCELLED:", StringComparison.Ordinal), "Cancel did not return CANCELLED.");
                } else {
                    Assert((bool)reply["ok"] && process.ExitCode == 0, "Generated fixture capture failed.");
                    using (MemoryStream bytes = new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))
                    using (Bitmap image = new Bitmap(bytes)) {
                        Assert(image.Width == last.X - first.X && image.Height == last.Y - first.Y, "Physical-pixel crop dimensions differ from the selected rectangle.");
                        foreach (Point at in new Point[] { Point.Empty, new Point(image.Width / 2, image.Height / 2), new Point(image.Width - 1, image.Height - 1) }) {
                            Color pixel = image.GetPixel(at.X, at.Y);
                            Assert(Math.Abs(pixel.R - liveColor.R) <= 2 && Math.Abs(pixel.G - liveColor.G) <= 2 && Math.Abs(pixel.B - liveColor.B) <= 2, "Capture froze old content or included its selection overlay.");
                        }
                    }
                }
                RequireFixtureForeground(form);
                return new Dictionary<string, object> { { "mode", mode }, { "passed", true }, { "foregroundPreserved", true } };
            } finally {
                if (!process.HasExited) { process.Kill(); process.WaitForExit(3000); }
            }
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
                        foreach (string mode in new string[] { "capture", "escape-short", "escape", "right", "capture" }) {
                            OnUi(form, delegate { form.BackColor = Color.FromArgb(50, 210, 110); form.Refresh(); });
                            trials.Add(Trial(form, helper, mode, Color.FromArgb(220, 70, 85)));
                        }
                        OnUi(form, delegate {
                            Assert(sourceMouseEvents == 0, "Selection/cancel button input reached the generated source window.");
                            Assert(escapeEvents.Count == 0, "Escape down/up reached the generated source window.");
                        });
                        report["selectionButtonsConsumed"] = true;
                        report["escapeDownUpConsumed"] = true;
                        report["liveCaptureAfterSelectionPassed"] = true;
                        report["overlayAbsentInCapture"] = true;
                        report["ok"] = true;
                    } catch (Exception error) { report["error"] = error.Message; }
                    finally {
                        try { if (restorePointer && GetForegroundWindow() == form.Handle) Move(form, originalPointer); }
                        catch (Exception error) { report["ok"] = false; report["pointerRestoreError"] = error.Message; }
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
