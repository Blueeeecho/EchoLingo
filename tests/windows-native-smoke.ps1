# A real Windows desktop smoke test against our dedicated temporary fixture.
# Run with Windows PowerShell 5.1 -STA. It deliberately uses the test desktop's
# clipboard, preserving all supported original formats and restoring in finally.
[CmdletBinding()]
param(
    [string]$HelperPath = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'DESKTOP_UNAVAILABLE: This smoke test only runs on a Windows interactive desktop.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw 'TEST_APARTMENT: Run powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/windows-native-smoke.ps1.'
    }
    # Windows PowerShell 5.1 may not initialize PSScriptRoot while evaluating
    # parameter defaults. Resolve the default only after entering the script body.
    if ([string]::IsNullOrWhiteSpace($HelperPath)) {
        $scriptDirectory = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
            $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
            throw 'TEST_PATH: Cannot locate the smoke script directory. Pass -HelperPath explicitly.'
        }
        $HelperPath = Join-Path $scriptDirectory '..\src-tauri\native\windows.ps1'
    }
    $HelperPath = (Resolve-Path -LiteralPath $HelperPath).Path
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web.Extensions
    $references = @(
        [System.Windows.Forms.Form].Assembly.Location
        [System.Drawing.Bitmap].Assembly.Location
        [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location
    ) | Select-Object -Unique

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

public static class EchoLingoDesktopSmoke {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder information, int length, out int needed);
    static readonly object processLock = new object();
    static Process activeHelper;
    static volatile bool cancelled;

    sealed class SavedClipboard : IDisposable {
        readonly DataObject data = new DataObject();
        readonly List<IDisposable> resources = new List<IDisposable>();
        public SavedClipboard() {
            try {
                IDataObject original = Clipboard.GetDataObject();
                if (original == null) return;
                foreach (string format in original.GetFormats(false)) {
                    object value = original.GetData(format, false);
                    if (value == null) throw new InvalidOperationException("Cannot materialize original clipboard format " + format);
                    Bitmap bitmap = value as Bitmap;
                    Stream stream = value as Stream;
                    Array array = value as Array;
                    object copy;
                    if (bitmap != null) copy = new Bitmap(bitmap);
                    else if (stream != null) {
                        if (!stream.CanSeek) throw new InvalidOperationException("Cannot preserve nonseekable clipboard stream " + format);
                        long position = stream.Position;
                        try {
                            stream.Position = 0;
                            MemoryStream buffer = new MemoryStream();
                            stream.CopyTo(buffer);
                            buffer.Position = 0;
                            copy = buffer;
                        } finally { stream.Position = position; }
                    } else if (array != null) copy = array.Clone();
                    else if (value is string || value.GetType().IsValueType) copy = value;
                    else throw new InvalidOperationException("Unsupported original clipboard format " + format + " (" + value.GetType().Name + "). The test stopped before writing the clipboard.");
                    IDisposable disposable = copy as IDisposable;
                    if (disposable != null) resources.Add(disposable);
                    data.SetData(format, false, copy);
                }
            } catch { Dispose(); throw; }
        }
        public void Restore() {
            if (data.GetFormats(false).Length == 0) Clipboard.Clear();
            else Clipboard.SetDataObject(data, true, 10, 50);
        }
        public void Dispose() { foreach (IDisposable resource in resources) resource.Dispose(); resources.Clear(); }
    }

    sealed class Reply {
        public bool Ok;
        public string Text;
        public string Error;
        public int ExitCode;
    }

    // This selectable test control intentionally supplies no text-provider
    // selection. A genuine injected Ctrl+C is observable through CopyCount.
    sealed class CopyFallbackControl : Control {
        public int CopyCount;
        public const string Selection = "EchoLingo real Ctrl+C fallback 97531";
        public CopyFallbackControl() {
            SetStyle(ControlStyles.Selectable, true);
            TabStop = true;
            AccessibleRole = AccessibleRole.Client;
            AccessibleName = "EchoLingo dedicated copy-fallback fixture";
            BackColor = Color.FromArgb(224, 245, 240);
        }
        protected override bool ProcessCmdKey(ref Message message, Keys keyData) {
            if (keyData == (Keys.Control | Keys.C)) {
                Clipboard.SetText(Selection, TextDataFormat.UnicodeText);
                CopyCount++;
                return true;
            }
            return base.ProcessCmdKey(ref message, keyData);
        }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.DrawString("Dedicated Ctrl+C fallback fixture", Font, Brushes.Black, 10, 12);
            base.OnPaint(e);
        }
    }

    static string InputDesktopName() {
        if (!Environment.UserInteractive || Process.GetCurrentProcess().SessionId == 0)
            throw new InvalidOperationException("DESKTOP_UNAVAILABLE: The runner is a service/session-0 process and has no interactive user desktop. Use an interactive Windows runner; this test does not silently skip.");
        IntPtr desktop = OpenInputDesktop(0, false, 0x0001);
        if (desktop == IntPtr.Zero)
            throw new InvalidOperationException("DESKTOP_UNAVAILABLE: Cannot open the input desktop. Win32 error " + Marshal.GetLastWin32Error());
        try {
            StringBuilder name = new StringBuilder(256);
            int needed;
            if (!GetUserObjectInformation(desktop, 2, name, name.Capacity * 2, out needed))
                throw new InvalidOperationException("DESKTOP_UNAVAILABLE: Cannot inspect the input desktop. Win32 error " + Marshal.GetLastWin32Error());
            if (name.ToString().IndexOf("winlogon", StringComparison.OrdinalIgnoreCase) >= 0)
                throw new InvalidOperationException("DESKTOP_UNAVAILABLE: The active desktop is locked or protected.");
            return name.ToString();
        } finally { CloseDesktop(desktop); }
    }

    static string Quote(string value) {
        // Only a filesystem path uses this function. All user/test text is stdin.
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    static Reply CallHelper(string path, string mode, string input) {
        if (cancelled) throw new OperationCanceledException("TEST_TIMEOUT: Desktop smoke test exceeded 180 seconds.");
        string executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        ProcessStartInfo info = new ProcessStartInfo(executable);
        info.Arguments = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File " + Quote(path) + " -Mode " + mode;
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.RedirectStandardInput = true;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.StandardOutputEncoding = new UTF8Encoding(false);
        info.StandardErrorEncoding = new UTF8Encoding(false);
        using (Process process = new Process()) {
            process.StartInfo = info;
            try {
                if (!process.Start()) throw new InvalidOperationException("HELPER_START: Could not start native helper.");
                lock (processLock) activeHelper = process;
                Task<string> outputTask = process.StandardOutput.ReadToEndAsync();
                Task<string> errorTask = process.StandardError.ReadToEndAsync();
                using (StreamWriter writer = new StreamWriter(process.StandardInput.BaseStream, new UTF8Encoding(false))) {
                    if (input != null) writer.Write(input);
                }
                if (!process.WaitForExit(60000)) {
                    process.Kill();
                    process.WaitForExit();
                    throw new InvalidOperationException("HELPER_TIMEOUT: Native mode " + mode + " exceeded 60 seconds.");
                }
                string output = outputTask.Result.Trim(new char[] { '\uFEFF', ' ', '\r', '\n' });
                string errors = errorTask.Result;
                if (String.IsNullOrWhiteSpace(output)) throw new InvalidOperationException("HELPER_PROTOCOL: No JSON for " + mode + ". Exit " + process.ExitCode + ". " + errors);
                Dictionary<string, object> result;
                try { result = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(output); }
                catch (Exception error) { throw new InvalidOperationException("HELPER_PROTOCOL: Invalid JSON for " + mode + ": " + error.Message + ". " + output); }
                Reply reply = new Reply();
                reply.Ok = result.ContainsKey("ok") && result["ok"] is bool && (bool)result["ok"];
                reply.Text = result.ContainsKey("text") ? result["text"] as string : null;
                reply.Error = result.ContainsKey("error") ? result["error"] as string : null;
                reply.ExitCode = process.ExitCode;
                return reply;
            } finally {
                lock (processLock) {
                    try { if (!process.HasExited) { process.Kill(); process.WaitForExit(); } } catch { }
                    activeHelper = null;
                }
            }
        }
    }

    static void Assert(bool condition, string message) {
        if (!condition) throw new InvalidOperationException("ASSERTION_FAILED: " + message);
    }
    static void AssertSuccess(Reply reply, string expected, string label) {
        Assert(reply.Ok && reply.ExitCode == 0, label + " failed: " + reply.Error);
        if (!String.Equals(reply.Text, expected, StringComparison.Ordinal)) {
            // This script only handles its dedicated generated fixture. Report
            // code points at the first mismatch to diagnose pipe encodings.
            string actual = reply.Text ?? "";
            int at = 0;
            while (at < actual.Length && at < expected.Length && actual[at] == expected[at]) at++;
            string received = at < actual.Length ? ((int)actual[at]).ToString("X4") : "EOF";
            string wanted = at < expected.Length ? ((int)expected[at]).ToString("X4") : "EOF";
            Assert(false, label + " returned different text: expected length " + expected.Length + ", actual length " + actual.Length + ", offset " + at + ", expected U+" + wanted + ", actual U+" + received + ".");
        }
    }
    static Reply CaptureFixtureSelection(Form form, string helperPath) {
        Assert(GetForegroundWindow() == form.Handle, "Dedicated fixture lost foreground before capture.");
        Reply reply = CallHelper(helperPath, "selected-text", null);
        Assert(GetForegroundWindow() == form.Handle, "Dedicated fixture lost foreground during capture.");
        return reply;
    }
    static void OnUi(Form form, Action action) {
        if (form.IsDisposed) throw new InvalidOperationException("DESKTOP_UNAVAILABLE: Fixture window closed unexpectedly.");
        form.Invoke(action);
    }
    static void FocusFixture(Form form, Control target, Action prepare) {
        OnUi(form, delegate {
            form.WindowState = FormWindowState.Normal;
            form.Activate();
            SetForegroundWindow(form.Handle);
            target.Focus();
            if (prepare != null) prepare();
        });
        DateTime deadline = DateTime.UtcNow.AddSeconds(3);
        bool focused = false;
        while (DateTime.UtcNow < deadline) {
            OnUi(form, delegate { focused = target.Focused && form.ContainsFocus && GetForegroundWindow() == form.Handle; });
            if (focused) break;
            Thread.Sleep(30);
        }
        if (!focused) throw new InvalidOperationException("DESKTOP_FOCUS_FAILED: Windows did not allow the dedicated fixture to become foreground/focused. The runner may lack an unlocked interactive desktop. No other application's selection will be tested.");
        Thread.Sleep(150);
    }
    static Dictionary<string, string> SeedRichClipboard() {
        Dictionary<string, string> values = new Dictionary<string, string>();
        values[DataFormats.UnicodeText] = "EchoLingo original clipboard \u4e2d\u6587 13579";
        values[DataFormats.Html] = "<html><body><b>EchoLingo original HTML 13579</b></body></html>";
        values[DataFormats.Rtf] = "{\\rtf1\\ansi EchoLingo original RTF 13579}";
        DataObject data = new DataObject();
        foreach (KeyValuePair<string, string> pair in values) data.SetData(pair.Key, false, pair.Value);
        Clipboard.SetDataObject(data, true, 10, 50);
        AssertRichClipboard(values);
        return values;
    }
    static void AssertRichClipboard(Dictionary<string, string> values) {
        IDataObject data = Clipboard.GetDataObject();
        Assert(data != null, "Clipboard lost all rich-text formats.");
        foreach (KeyValuePair<string, string> pair in values) {
            Assert(data.GetDataPresent(pair.Key, false), "Clipboard lost format " + pair.Key);
            Assert(String.Equals(data.GetData(pair.Key, false) as string, pair.Value, StringComparison.Ordinal), "Clipboard changed format " + pair.Key);
        }
    }

    public static Dictionary<string, object> Run(string helperPath) {
        cancelled = false;
        Dictionary<string, object> report = new Dictionary<string, object>();
        List<string> passed = new List<string>();
        report["ok"] = false;
        report["passed"] = passed;
        report["sessionId"] = Process.GetCurrentProcess().SessionId;
        report["clipboardRestored"] = false;
        report["screenshotsTested"] = false;
        report["multiMonitorTested"] = false;
        report["globalShortcutRegistrationTested"] = false;
        try { report["inputDesktop"] = InputDesktopName(); }
        catch (Exception error) { report["error"] = error.Message; return report; }

        using (Form form = new Form())
        using (TextBox selection = new TextBox())
        using (TextBox password = new TextBox())
        using (CopyFallbackControl fallback = new CopyFallbackControl())
        using (System.Windows.Forms.Timer timeout = new System.Windows.Forms.Timer()) {
            form.Text = "EchoLingo temporary native smoke fixture";
            form.StartPosition = FormStartPosition.CenterScreen;
            form.ClientSize = new Size(560, 250);
            form.FormBorderStyle = FormBorderStyle.FixedDialog;
            form.MaximizeBox = false;
            form.MinimizeBox = false;
            selection.Multiline = true;
            selection.SetBounds(20, 20, 520, 72);
            selection.Text = "Prefix EchoLingo selected text 2468 suffix";
            password.SetBounds(20, 108, 520, 28);
            password.UseSystemPasswordChar = true;
            password.Text = "EchoLingo temporary test secret 86420";
            fallback.SetBounds(20, 155, 520, 65);
            form.Controls.Add(selection);
            form.Controls.Add(password);
            form.Controls.Add(fallback);

            Thread worker = null;
            bool finished = false;
            form.FormClosing += delegate(object sender, FormClosingEventArgs e) {
                if (!finished) e.Cancel = true;
            };
            timeout.Interval = 180000;
            timeout.Tick += delegate {
                timeout.Stop();
                cancelled = true;
                lock (processLock) { try { if (activeHelper != null && !activeHelper.HasExited) activeHelper.Kill(); } catch { } }
            };
            form.Shown += delegate {
                timeout.Start();
                worker = new Thread(delegate() {
                    SavedClipboard original = null;
                    try {
                        // Snapshot before any copy or clipboard seed is written.
                        original = new SavedClipboard();
                        string unicode = "EchoLingo \u56de\u58f0\u8bd1 \u65e5\u672c\u8a9e\r\nquotes: \" ' ` $() ; & | \\ end";
                        AssertSuccess(CallHelper(helperPath, "copy", unicode), "", "UTF-8 copy");
                        AssertSuccess(CallHelper(helperPath, "clipboard", null), unicode, "UTF-8 clipboard read");
                        passed.Add("Unicode copy/read exact roundtrip via real helper stdin/JSON");

                        Dictionary<string, string> seeded = SeedRichClipboard();
                        const string expected = "EchoLingo selected text 2468";
                        FocusFixture(form, selection, delegate { selection.Select(selection.Text.IndexOf(expected, StringComparison.Ordinal), expected.Length); });
                        AssertSuccess(CaptureFixtureSelection(form, helperPath), expected, "TextBox selected-text capture");
                        AssertRichClipboard(seeded);
                        passed.Add("Foreground TextBox selection captured; Unicode/HTML/RTF clipboard preserved");

                        FocusFixture(form, selection, delegate { selection.Select(0, 0); });
                        Reply emptyReply = CaptureFixtureSelection(form, helperPath);
                        Assert(!emptyReply.Ok && emptyReply.ExitCode != 0 && emptyReply.Error != null && emptyReply.Error.StartsWith("NO_SELECTION:", StringComparison.Ordinal), "Empty TextBox selection must return NO_SELECTION, received " + emptyReply.Error);
                        AssertRichClipboard(seeded);
                        passed.Add("Empty TextBox selection returns NO_SELECTION; rich clipboard preserved");

                        FocusFixture(form, fallback, null);
                        AssertSuccess(CaptureFixtureSelection(form, helperPath), CopyFallbackControl.Selection, "Forced Ctrl+C selection fallback");
                        int copyCount = 0;
                        OnUi(form, delegate { copyCount = fallback.CopyCount; });
                        Assert(copyCount == 1, "Expected one real Ctrl+C in the dedicated fallback control; received " + copyCount);
                        AssertRichClipboard(seeded);
                        passed.Add("Real injected Ctrl+C observed once; Unicode/HTML/RTF clipboard restored");

                        FocusFixture(form, password, delegate { password.SelectAll(); });
                        Reply protectedReply = CaptureFixtureSelection(form, helperPath);
                        Assert(!protectedReply.Ok && protectedReply.ExitCode != 0 && protectedReply.Error != null && protectedReply.Error.StartsWith("PROTECTED:", StringComparison.Ordinal), "Password control must return PROTECTED, received " + protectedReply.Error);
                        AssertRichClipboard(seeded);
                        passed.Add("Password selection rejected without changing seeded clipboard formats");
                        if (cancelled) throw new OperationCanceledException("TEST_TIMEOUT: Desktop smoke test exceeded 180 seconds.");
                        report["ok"] = true;
                    } catch (Exception error) {
                        report["ok"] = false;
                        report["error"] = error.Message;
                    } finally {
                        if (original != null) {
                            try { original.Restore(); report["clipboardRestored"] = true; }
                            catch (Exception error) { report["ok"] = false; report["clipboardRestoreError"] = error.Message; }
                            finally { original.Dispose(); }
                        }
                        OnUi(form, delegate { finished = true; timeout.Stop(); form.Close(); });
                    }
                });
                worker.SetApartmentState(ApartmentState.STA);
                worker.IsBackground = false;
                worker.Start();
            };
            Application.Run(form);
            if (worker != null) worker.Join(5000);
        }
        return report;
    }
}
'@
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    $result = [EchoLingoDesktopSmoke]::Run($HelperPath)
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 8 -Compress))
    if (-not $result['ok']) { exit 1 }
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    [Console]::Out.WriteLine((@{ ok = $false; error = $message; screenshotsTested = $false; multiMonitorTested = $false } | ConvertTo-Json -Compress))
    exit 1
}
