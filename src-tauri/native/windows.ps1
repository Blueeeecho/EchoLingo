# Windows PowerShell 5.1, built-in .NET Framework, UI Automation and Windows OCR.
# No download, OCR package, PowerShell module or network access is required.
[CmdletBinding()]
param(
    [ValidateSet('selected-text', 'capture-ocr', 'capture-image', 'clipboard', 'copy', 'diagnostics', 'self-test')]
    [string]$Mode = $env:ECHOLINGO_NATIVE_MODE
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-Result($Value) {
    [Console]::Out.WriteLine(($Value | ConvertTo-Json -Depth 12 -Compress))
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName WindowsBase
    $source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using System.Windows.Forms;

public static class EchoLingoNative {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll", SetLastError=true)] static extern bool BitBlt(IntPtr target, int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, int operation);
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion data; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mouse;
        [FieldOffset(0)] public KEYBDINPUT keyboard;
        [FieldOffset(0)] public HARDWAREINPUT hardware;
    }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct HARDWAREINPUT { public uint message; public ushort low, high; }

    public static void ConfigureDpi() {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
        catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
    }
    static bool ModifiersDown() {
        foreach (int key in new int[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })
            if ((GetAsyncKeyState(key) & 0x8000) != 0) return true;
        return false;
    }
    static string AutomationSelection() {
        try {
            AutomationElement focused = AutomationElement.FocusedElement;
            if (focused == null) return null;
            // Password controls must never be copied by the fallback.
            if (focused.Current.IsPassword) throw new InvalidOperationException("PROTECTED: Selected text is inside a password control.");
            object pattern;
            if (focused.TryGetCurrentPattern(TextPattern.Pattern, out pattern)) {
                TextPatternRange[] ranges = ((TextPattern)pattern).GetSelection();
                StringBuilder text = new StringBuilder();
                foreach (TextPatternRange range in ranges) {
                    string part = range.GetText(-1);
                    if (!String.IsNullOrEmpty(part)) { if (text.Length > 0) text.AppendLine(); text.Append(part); }
                }
                if (!String.IsNullOrWhiteSpace(text.ToString())) return text.ToString();
                // Editors can copy a full line when Ctrl+C has no selection.
                // A supported provider with an empty range must never fall back.
                throw new InvalidOperationException("NO_SELECTION: No text is selected in the source application.");
            }
        } catch (InvalidOperationException error) {
            if (error.Message.StartsWith("PROTECTED:") || error.Message.StartsWith("NO_SELECTION:")) throw;
        } catch (ElementNotAvailableException) { }
        return null;
    }
    static object CloneClipboardValue(object value) {
        if (value == null) throw new InvalidOperationException("Clipboard format could not be materialized.");
        Bitmap bitmap = value as Bitmap;
        if (bitmap != null) return new Bitmap(bitmap);
        Stream stream = value as Stream;
        if (stream != null) {
            if (!stream.CanSeek) throw new InvalidOperationException("Clipboard stream cannot be preserved safely.");
            long position = stream.Position;
            try { stream.Position = 0; MemoryStream copy = new MemoryStream(); stream.CopyTo(copy); copy.Position = 0; return copy; }
            finally { stream.Position = position; }
        }
        Array array = value as Array;
        if (array != null) return array.Clone();
        if (value is string || value.GetType().IsValueType) return value;
        throw new InvalidOperationException("Unsupported clipboard representation: " + value.GetType().Name);
    }
    static DataObject SnapshotClipboard(List<IDisposable> resources) {
        IDataObject existing = Clipboard.GetDataObject();
        DataObject saved = new DataObject();
        if (existing == null) return saved;
        foreach (string format in existing.GetFormats(false)) {
            object value = CloneClipboardValue(existing.GetData(format, false));
            IDisposable disposable = value as IDisposable;
            if (disposable != null) resources.Add(disposable);
            saved.SetData(format, false, value);
        }
        return saved;
    }
    static INPUT Key(ushort code, bool up) {
        INPUT input = new INPUT(); input.type = 1;
        input.data.keyboard.vk = code; input.data.keyboard.flags = up ? 2u : 0u;
        return input;
    }
    public static string SelectedText() {
        string direct = AutomationSelection();
        if (!String.IsNullOrWhiteSpace(direct)) return direct;
        IntPtr foreground = GetForegroundWindow();
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(1500);
        while (ModifiersDown()) {
            if (DateTime.UtcNow >= deadline) throw new InvalidOperationException("SELECTION: Release the shortcut keys and retry.");
            Thread.Sleep(20);
        }
        if (GetForegroundWindow() != foreground) throw new InvalidOperationException("SELECTION: Foreground application changed; select text in the source application and retry.");
        List<IDisposable> resources = new List<IDisposable>();
        DataObject saved;
        uint initial = GetClipboardSequenceNumber();
        try {
            saved = SnapshotClipboard(resources);
            if (GetClipboardSequenceNumber() != initial) throw new InvalidOperationException("Clipboard changed while its formats were being preserved. Retry.");
        }
        catch (Exception error) {
            foreach (IDisposable resource in resources) resource.Dispose();
            throw new InvalidOperationException("CLIPBOARD: Cannot preserve all clipboard formats. Selection capture was stopped before changing the clipboard. " + error.Message);
        }
        uint copied = initial;
        bool changed = false;
        try {
            INPUT[] keys = new INPUT[] { Key(0x11, false), Key(0x43, false), Key(0x43, true), Key(0x11, true) };
            if (SendInput((uint)keys.Length, keys, Marshal.SizeOf(typeof(INPUT))) != keys.Length) {
                // Ensure our Ctrl-down cannot leave a modifier stuck.
                INPUT[] release = new INPUT[] { Key(0x43, true), Key(0x11, true) };
                SendInput((uint)release.Length, release, Marshal.SizeOf(typeof(INPUT)));
                throw new InvalidOperationException("SELECTION: Windows blocked copy input. Elevated or protected apps may not allow selection capture; try screenshot OCR.");
            }
            deadline = DateTime.UtcNow.AddMilliseconds(1200);
            while (GetClipboardSequenceNumber() == initial && DateTime.UtcNow < deadline) Thread.Sleep(20);
            copied = GetClipboardSequenceNumber();
            changed = copied != initial;
            if (!changed) throw new InvalidOperationException("NO_SELECTION: No text was copied. Try screenshot OCR for nonselectable text or apps running as administrator.");
            string text = Clipboard.ContainsText() ? Clipboard.GetText(TextDataFormat.UnicodeText) : null;
            if (String.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("NO_SELECTION: The selection does not contain plain text. Try screenshot OCR.");
            return text;
        } finally {
            try {
                if (changed) {
                    if (GetClipboardSequenceNumber() != copied) throw new InvalidOperationException("CLIPBOARD_CHANGED: Another copy operation occurred; the newer clipboard was preserved. Retry.");
                    try {
                        if (saved.GetFormats(false).Length == 0) Clipboard.Clear();
                        else Clipboard.SetDataObject(saved, true, 5, 40);
                    } catch (Exception error) {
                        throw new InvalidOperationException("CLIPBOARD_RESTORE_FAILED: Could not restore original clipboard formats. " + error.Message);
                    }
                }
            } finally { foreach (IDisposable resource in resources) resource.Dispose(); }
        }
    }
    public static string ClipboardText() {
        if (!Clipboard.ContainsText()) throw new InvalidOperationException("CLIPBOARD_EMPTY: The clipboard does not contain text.");
        return Clipboard.GetText(TextDataFormat.UnicodeText);
    }
    public static void CopyText(string text) {
        if (String.IsNullOrEmpty(text)) { Clipboard.Clear(); return; }
        Clipboard.SetDataObject(text, true, 5, 40);
    }
    static Bitmap ScreenBitmap(Rectangle bounds) {
        Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        try {
            using (Graphics graphics = Graphics.FromImage(bitmap)) {
                IntPtr target = graphics.GetHdc();
                IntPtr source = GetDC(IntPtr.Zero);
                try {
                    if (source == IntPtr.Zero || !BitBlt(target, 0, 0, bounds.Width, bounds.Height, source, bounds.X, bounds.Y, 0x40CC0020))
                        throw new InvalidOperationException("CAPTURE: Windows could not capture the desktop.");
                } finally { if (source != IntPtr.Zero) ReleaseDC(IntPtr.Zero, source); graphics.ReleaseHdc(target); }
            }
            return bitmap;
        } catch { bitmap.Dispose(); throw; }
    }
    public static void CaptureRegion(string path) {
        ConfigureDpi();
        Rectangle bounds = SystemInformation.VirtualScreen;
        // Snapshot before showing the overlay; selection never captures our UI.
        using (Bitmap desktop = ScreenBitmap(bounds))
        using (RegionPicker picker = new RegionPicker(desktop, bounds)) {
            if (picker.ShowDialog() != DialogResult.OK || picker.Selected.Width < 3 || picker.Selected.Height < 3)
                throw new OperationCanceledException("CANCELLED: Screenshot selection was cancelled (Escape, right click, or 120-second timeout).");
            using (Bitmap crop = desktop.Clone(picker.Selected, PixelFormat.Format32bppArgb)) crop.Save(path, ImageFormat.Png);
        }
    }
    public static void CreateFixture(string path) {
        using (Bitmap bitmap = new Bitmap(1100, 160))
        using (Graphics graphics = Graphics.FromImage(bitmap))
        using (Font font = new Font("Arial", 38)) {
            graphics.Clear(Color.White);
            graphics.DrawString("EchoLingo translation 2468", font, Brushes.Black, 20, 40);
            bitmap.Save(path, ImageFormat.Png);
        }
    }
}

sealed class RegionPicker : Form {
    readonly Bitmap desktop;
    readonly System.Windows.Forms.Timer timeout;
    Point origin;
    bool dragging;
    public Rectangle Selected { get; private set; }
    public RegionPicker(Bitmap image, Rectangle bounds) {
        desktop = image;
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = bounds;
        TopMost = true;
        ShowInTaskbar = false;
        KeyPreview = true;
        DoubleBuffered = true;
        Cursor = Cursors.Cross;
        timeout = new System.Windows.Forms.Timer();
        timeout.Interval = 120000;
        timeout.Tick += delegate { DialogResult = DialogResult.Cancel; Close(); };
        timeout.Start();
    }
    protected override void Dispose(bool disposing) { if (disposing) timeout.Dispose(); base.Dispose(disposing); }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.KeyCode == Keys.Escape) { DialogResult = DialogResult.Cancel; Close(); }
        base.OnKeyDown(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Right) { DialogResult = DialogResult.Cancel; Close(); return; }
        if (e.Button == MouseButtons.Left) { origin = e.Location; dragging = true; Capture = true; }
        base.OnMouseDown(e);
    }
    protected override void OnMouseMove(MouseEventArgs e) {
        if (dragging) {
            Selected = Rectangle.Intersect(new Rectangle(Math.Min(origin.X, e.X), Math.Min(origin.Y, e.Y), Math.Abs(origin.X - e.X), Math.Abs(origin.Y - e.Y)), ClientRectangle);
            Invalidate();
        }
        base.OnMouseMove(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        if (dragging && e.Button == MouseButtons.Left) {
            OnMouseMove(e);
            dragging = false; Capture = false;
            DialogResult = Selected.Width >= 3 && Selected.Height >= 3 ? DialogResult.OK : DialogResult.Cancel;
            Close();
        }
        base.OnMouseUp(e);
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.DrawImageUnscaled(desktop, 0, 0);
        using (Brush shade = new SolidBrush(Color.FromArgb(95, 0, 0, 0))) e.Graphics.FillRectangle(shade, ClientRectangle);
        if (Selected.Width > 0 && Selected.Height > 0) {
            e.Graphics.DrawImage(desktop, Selected, Selected, GraphicsUnit.Pixel);
            using (Pen border = new Pen(Color.FromArgb(70, 220, 215), 2)) e.Graphics.DrawRectangle(border, Selected);
        }
        using (Font font = new Font("Segoe UI", 14)) e.Graphics.DrawString("Drag to select text  |  Esc / right click to cancel", font, Brushes.White, 24, 24);
        base.OnPaint(e);
    }
}
'@
    $references = @(
        [System.Windows.Forms.Form].Assembly.Location
        [System.Drawing.Bitmap].Assembly.Location
        [System.Windows.Automation.AutomationElement].Assembly.Location
        [System.Windows.Automation.AutomationPattern].Assembly.Location
        [System.Windows.DependencyObject].Assembly.Location
    ) | Select-Object -Unique
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    [EchoLingoNative]::ConfigureDpi()

    function Initialize-Ocr {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
        $null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]
        $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapPixelFormat, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapAlphaMode, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
        $script:AsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
            $_.GetGenericArguments().Length -eq 1 -and $_.GetParameters().Length -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } | Select-Object -First 1
        if ($null -eq $script:AsTask) { throw 'OCR_UNAVAILABLE: Windows Runtime async support is unavailable.' }
    }
    function Await-WinRt($Operation, [Type]$ResultType) {
        $method = $script:AsTask.MakeGenericMethod($ResultType)
        $task = $method.Invoke($null, @($Operation))
        $remaining = [int][Math]::Max(1, ($script:OcrDeadline - [DateTime]::UtcNow).TotalMilliseconds)
        if (-not $task.Wait($remaining)) {
            try { $Operation.Cancel() } catch { }
            throw 'OCR_TIMEOUT: Local OCR exceeded 30 seconds.'
        }
        return $task.GetAwaiter().GetResult()
    }
    function Get-OcrText([string]$Path) {
        Initialize-Ocr
        $script:OcrDeadline = [DateTime]::UtcNow.AddSeconds(30)
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        if ($null -eq $engine) {
            $languages = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages)
            if ($languages.Count -gt 0) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($languages[0]) }
        }
        if ($null -eq $engine) {
            throw 'OCR_LANGUAGE_MISSING: Install an OCR-capable language in Windows Settings > Time & language > Language & region > Language options. English or Chinese basic typing/OCR language features are suitable.'
        }
        $stream = $null
        $bitmap = $null
        try {
            $file = Await-WinRt ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
            $stream = Await-WinRt ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
            $decoder = Await-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
            $maximum = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
            if ($decoder.PixelWidth -gt $maximum -or $decoder.PixelHeight -gt $maximum) {
                throw "OCR_IMAGE_TOO_LARGE: Selected image exceeds the Windows OCR limit of $maximum pixels per dimension. Select a smaller region."
            }
            $bitmap = Await-WinRt ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)) ([Windows.Graphics.Imaging.SoftwareBitmap])
            $result = Await-WinRt ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
            $lines = @($result.Lines | ForEach-Object { $_.Text })
            $text = $lines -join "`n"
            if ([string]::IsNullOrWhiteSpace($text)) { throw 'NO_TEXT: No text was recognized. Select a larger, clearer area and retry.' }
            return $text
        } finally {
            if ($null -ne $bitmap) { $bitmap.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
    function Get-Diagnostics {
        $available = @()
        $ocrError = $null
        try {
            Initialize-Ocr
            $available = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag })
        } catch { $ocrError = $_.Exception.Message }
        return @{
            platform = 'windows'; helper = 'windows-powershell-dotnet-winrt'; localOcr = $true
            ocrEngine = 'Windows.Media.Ocr'; ocrLanguages = $available; ocrAvailable = ($available.Count -gt 0)
            ocrError = $ocrError; powerShellVersion = $PSVersionTable.PSVersion.ToString()
            selection = 'UI Automation TextPattern, then Ctrl+C with clipboard restoration'
            screenCount = [System.Windows.Forms.Screen]::AllScreens.Length
            virtualScreen = [System.Windows.Forms.SystemInformation]::VirtualScreen.ToString()
            dpiMode = 'Per-monitor v2 requested; system-aware fallback on older Windows'
        }
    }

    function Get-PngBase64([string]$Path) {
        if ((Get-Item -LiteralPath $Path).Length -gt (8 * 1024 * 1024)) {
            throw 'CAPTURE_TOO_LARGE: Captured PNG exceeds 8 MiB. Select a smaller region.'
        }
        $bytes = [IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -eq 0) { throw 'CAPTURE: Captured PNG was empty.' }
        if ($bytes.Length -gt (8 * 1024 * 1024)) {
            throw 'CAPTURE_TOO_LARGE: Captured PNG exceeds 8 MiB. Select a smaller region.'
        }
        return [Convert]::ToBase64String($bytes)
    }

    switch ($Mode) {
        'selected-text' { Write-Result @{ ok = $true; text = [EchoLingoNative]::SelectedText() } }
        'clipboard' { Write-Result @{ ok = $true; text = [EchoLingoNative]::ClipboardText() } }
        'copy' { [EchoLingoNative]::CopyText([Console]::In.ReadToEnd()); Write-Result @{ ok = $true; text = '' } }
        'diagnostics' { Write-Result @{ ok = $true; diagnostics = (Get-Diagnostics) } }
        { $_ -in 'capture-ocr', 'capture-image', 'self-test' } {
            $path = [IO.Path]::Combine([IO.Path]::GetTempPath(), ('echolingo-' + [Guid]::NewGuid().ToString('N') + '.png'))
            try {
                if ($Mode -in 'capture-ocr', 'capture-image') { [EchoLingoNative]::CaptureRegion($path) }
                else { [EchoLingoNative]::CreateFixture($path) }
                if ($Mode -eq 'capture-image') {
                    Write-Result @{ ok = $true; imageBase64 = (Get-PngBase64 $path) }
                } else {
                    $text = Get-OcrText $path
                    if ($Mode -eq 'self-test') {
                        if ($text -notmatch '2468') { throw 'SELF_TEST: Local OCR did not recognize the generated fixture.' }
                        $base64 = Get-PngBase64 $path
                        if ([Convert]::FromBase64String($base64).Length -ne (Get-Item -LiteralPath $path).Length) { throw 'SELF_TEST: PNG base64 roundtrip failed.' }
                        Write-Result @{ ok = $true; diagnostics = @{ ocrFixturePassed = $true; pngBase64RoundtripPassed = $true; recognized = $text; diagnostics = (Get-Diagnostics); interactiveCaptureTested = $false; clipboardChanged = $false } }
                    } else { Write-Result @{ ok = $true; text = $text } }
                }
            } finally { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }
        }
        default { throw 'Unsupported native helper mode.' }
    }
} catch {
    $message = $_.Exception.Message
    $inner = $_.Exception.InnerException
    while ($null -ne $inner) { $message = $inner.Message; $inner = $inner.InnerException }
    Write-Result @{ ok = $false; error = $message }
    exit 1
}
