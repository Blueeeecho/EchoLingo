# Controlled counterexamples only: generated ordinary non-fullscreen source,
# its own UI-thread native capture, and the exact production picker helper.
[CmdletBinding()]
param([string]$HelperPath='', [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,
      [ValidateSet('hybrid','planeOnly')][string]$InputBackend='planeOnly', [switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -and -not $env:GITHUB_ACTIONS) { throw 'ISOLATION_REQUIRED: Use an explicitly isolated generated-window session.' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) { throw 'DESKTOP_UNAVAILABLE: An unlocked Windows desktop is required.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'TEST_APARTMENT: Use powershell.exe -STA.' }
    if (-not $HelperPath) { $HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1' }
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
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
public static class EchoLingoInputOwnershipAdversarial {
    delegate bool EnumWindow(IntPtr window,IntPtr parameter);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left,top,right,bottom; }
    [StructLayout(LayoutKind.Sequential)] struct GUI { public uint size,flags; public IntPtr active,focus,capture,menuOwner,moveSize,caret; public RECT caretRect; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public Union data; }
    [StructLayout(LayoutKind.Explicit)] struct Union { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window,uint relation);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out RECT bounds);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window,ref Point point);
    [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr window,Point point,uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder value,int count);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetCapture(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetCapture();
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUI value);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] values,int size);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window,uint attribute,out RECT bounds,int size);
    sealed class WindowInfo { public IntPtr Handle; public Rectangle Bounds; }
    static readonly JavaScriptSerializer json=new JavaScriptSerializer { MaxJsonLength=16*1024*1024 };
    static void Need(bool value,string message) { if (!value) throw new InvalidOperationException(message); }
    static string Id(IntPtr value) { return "0x"+value.ToInt64().ToString("X"); }
    static int[] Rect(Rectangle value) { return new int[] { value.X,value.Y,value.Width,value.Height }; }
    static Rectangle Bounds(IntPtr window) { RECT value; Need(GetWindowRect(window,out value),"Cannot read owned window bounds.");return Rectangle.FromLTRB(value.left,value.top,value.right,value.bottom); }
    static Rectangle Frame(IntPtr window) { RECT value;Need(DwmGetWindowAttribute(window,9,out value,Marshal.SizeOf(typeof(RECT)))==0,"Cannot read source DWM frame.");return Rectangle.FromLTRB(value.left,value.top,value.right,value.bottom); }
    static string Class(IntPtr window) { StringBuilder value=new StringBuilder(256);GetClassName(window,value,value.Capacity);return value.ToString(); }
    static bool Plane(IntPtr window,int pid) { return Class(window)=="EchoLingoCaptureInputPlane-"+pid; }
    static INPUT Move(Point point) {
        Rectangle desktop=SystemInformation.VirtualScreen;INPUT value=new INPUT();
        value.data.mouse.x=(int)Math.Round((point.X-desktop.X)*65535.0/(desktop.Width-1));
        value.data.mouse.y=(int)Math.Round((point.Y-desktop.Y)*65535.0/(desktop.Height-1));value.data.mouse.flags=0x8000|0x4000|1;return value;
    }
    static INPUT Mouse(uint flags) { INPUT value=new INPUT();value.data.mouse.flags=flags;return value; }
    static void Send(INPUT[] values) { Need(SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)))==values.Length,"Windows rejected owned generated input."); }
    static void Escape(IntPtr source) { Need(GetForegroundWindow()==source,"Source foreground changed; no key sent elsewhere.");INPUT down=new INPUT();down.type=1;down.data.key.vk=0x1b;INPUT up=down;up.data.key.flags=2;Send(new INPUT[] { down,up }); }
    static List<Rectangle> Perimeter(Rectangle frame) {
        return new List<Rectangle> { new Rectangle(frame.X,frame.Y,frame.Width,2),new Rectangle(frame.X,frame.Bottom-2,frame.Width,2),
            new Rectangle(frame.X,frame.Y+2,2,frame.Height-4),new Rectangle(frame.Right-2,frame.Y+2,2,frame.Height-4) };
    }
    static bool Ready(int helper,IntPtr source,Rectangle frame,Rectangle display,Point point,Dictionary<string,object> observed) {
        Need(GetForegroundWindow()==source && Frame(source)==frame,"Source foreground/DWM changed before adversarial action.");
        List<WindowInfo> thin=new List<WindowInfo>(),planes=new List<WindowInfo>();int allocated=0;
        EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint pid;GetWindowThreadProcessId(window,out pid);if (pid!=helper) return true;
            long style=GetWindowLongPtr(window,-20).ToInt64();
            if (Plane(window,helper)) {
                if (!IsWindowVisible(window)) return true;
                const long required=0x00200000L|0x08000000L|0x80L|8;
                Need((style&required)==required&&(style&(0x80000L|0x20L))==0,"Input plane styles invalid.");
                planes.Add(new WindowInfo { Handle=window,Bounds=Bounds(window) });return true;
            }
            long edges=0x08000000L|0x80000L|0x20L;
            if ((style&edges)==edges) allocated++;
            if (!IsWindowVisible(window)) return true;
            Rectangle r=Bounds(window);Need((style&(edges|8))==(edges|8)&&Math.Min(r.Width,r.Height)<=2,"Unknown visible helper surface.");
            thin.Add(new WindowInfo { Handle=window,Bounds=r });return true;
        },IntPtr.Zero);
        List<Rectangle> wanted=Perimeter(display);wanted.AddRange(Perimeter(frame));
        bool exact=thin.Count==8 && allocated==12*Screen.AllScreens.Length;
        foreach (WindowInfo edge in thin) { int index=wanted.IndexOf(edge.Bounds);if (index<0) exact=false;else wanted.RemoveAt(index); }
        List<Rectangle> monitors=new List<Rectangle>();foreach (Screen screen in Screen.AllScreens) monitors.Add(screen.Bounds);
        bool planeGeometry=planes.Count==monitors.Count;
        foreach (WindowInfo plane in planes) {int index=monitors.IndexOf(plane.Bounds);if(index<0)planeGeometry=false;else monitors.RemoveAt(index);}
        IntPtr raw=GetAncestor(WindowFromPoint(point),2);Point client=point;IntPtr desktop=GetDesktopWindow();
        IntPtr through=ScreenToClient(desktop,ref client)?GetAncestor(ChildWindowFromPointEx(desktop,client,5),2):IntPtr.Zero;
        bool hit=planes.Exists(delegate(WindowInfo p){return p.Handle==through&&p.Bounds.Contains(point);})
            && (planes.Exists(delegate(WindowInfo p){return p.Handle==raw;})||thin.Exists(delegate(WindowInfo e){return e.Handle==raw&&e.Bounds.Contains(point);}));
        observed["thinVisibleCount"]=thin.Count;observed["thinAllocatedCount"]=allocated;observed["planeVisibleCount"]=planes.Count;
        observed["rawPointerRootHwnd"]=Id(raw);observed["transparentSkippingRootHwnd"]=Id(through);
        observed["exactPlanePointerHit"]=hit;return exact&&wanted.Count==0&&planeGeometry&&monitors.Count==0&&hit;
    }
    static Dictionary<string,object> SafeReply(Dictionary<string,object> reply) {
        Dictionary<string,object> safe=new Dictionary<string,object>();
        foreach(string key in new string[] { "ok","nativeBackend" }) if(reply.ContainsKey(key))safe[key]=reply[key];
        if(reply.ContainsKey("error")) { string error=Convert.ToString(reply["error"]);safe["error"]=error.Substring(0,Math.Min(error.Length,600)); }
        foreach(string key in new string[] { "captureHealth","capturePerformance","helperPerformance" }) {
            object raw; if(!reply.TryGetValue(key,out raw))continue;Dictionary<string,object> values=raw as Dictionary<string,object>;
            if(values==null||values.Count>128)continue;Dictionary<string,object> numbers=new Dictionary<string,object>();
            foreach(KeyValuePair<string,object> field in values)if(field.Value is int||field.Value is long||field.Value is double||field.Value is decimal)numbers[field.Key]=field.Value;
            safe[key]=numbers;
        }
        return safe;
    }
    static Dictionary<string,object> Case(string helper,string assembly,string backend,string kind) {
        Dictionary<string,object> report=new Dictionary<string,object> { { "mode",kind },{ "ok",false } };
        Form source=null;IntPtr hwnd=IntPtr.Zero;uint sourceThread=0;int downs=0,ups=0,clicks=0;
        Rectangle frame=Rectangle.Empty,display=Rectangle.Empty;Point first=Point.Empty,last=Point.Empty;
        ManualResetEvent ready=new ManualResetEvent(false);string setupError=null;
        Thread ui=new Thread(delegate() {
            try {
                Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Source DPI context failed.");
                using(Form form=new Form())using(Button button=new Button()) {
                    source=form;form.Text="EchoLingo controlled input ownership source";form.AutoScaleMode=AutoScaleMode.None;
                    form.FormBorderStyle=FormBorderStyle.None;form.StartPosition=FormStartPosition.Manual;form.ShowInTaskbar=true;form.Owner=null;form.TopMost=true;
                    Rectangle work=Screen.PrimaryScreen.WorkingArea;display=Screen.PrimaryScreen.Bounds;
                    Need(work.Width>=640&&work.Height>=440,"Generated adversarial fixture requires640x440 work area.");
                    form.Bounds=new Rectangle(work.X+60,work.Y+50,520,340);form.BackColor=Color.FromArgb(40,180,90);
                    button.Bounds=new Rectangle(40,50,240,75);button.Text="Generated button";button.FlatStyle=FlatStyle.Flat;button.UseVisualStyleBackColor=false;button.BackColor=Color.FromArgb(230,150,40);
                    button.MouseDown+=delegate { Interlocked.Increment(ref downs); };button.MouseUp+=delegate { Interlocked.Increment(ref ups); };button.Click+=delegate { Interlocked.Increment(ref clicks); };
                    form.MouseDown+=delegate { Interlocked.Increment(ref downs); };form.MouseUp+=delegate { Interlocked.Increment(ref ups); };form.Controls.Add(button);
                    form.Shown+=delegate { try { form.Activate();SetForegroundWindow(form.Handle);hwnd=form.Handle;sourceThread=GetCurrentThreadId();frame=Frame(hwnd);first=form.PointToScreen(new Point(65,70));last=new Point(first.X+35,first.Y+15); }catch(Exception error){setupError=error.Message;}finally{ready.Set();} };
                    Application.Run(form);
                }
            }catch(Exception error){setupError=error.Message;ready.Set();}
        });ui.IsBackground=true;ui.SetApartmentState(ApartmentState.STA);ui.Start();
        Process process=null;Task<string> output=null;bool partialInput=false;
        try {
            Need(ready.WaitOne(10000)&&setupError==null,"Source setup failed: "+setupError);
            Need(sourceThread!=GetCurrentThreadId()&&GetForegroundWindow()==hwnd,"Source is not on its independent foreground UI thread.");
            uint sourcePid;Need(GetWindowThreadProcessId(hwnd,out sourcePid)==sourceThread&&sourcePid==Process.GetCurrentProcess().Id,"Source identity changed.");
            Need(GetWindow(hwnd,4)==IntPtr.Zero&&GetParent(hwnd)==IntPtr.Zero&&frame!=display&&display.Contains(frame),"Source is not an ordinary ownerless non-fullscreen topmost window.");
            Need(GetAncestor(WindowFromPoint(first),2)==hwnd,"Generated source endpoint is initially obscured; no input sent.");
            Send(new INPUT[] { Move(first) });Thread.Sleep(80);
            ProcessStartInfo start=new ProcessStartInfo("powershell.exe");start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+helper+"\" -Mode capture-image -NativeAssemblyPath \""+assembly+"\" -InputBackend "+backend+" -PerformanceDiagnostics";
            start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=Encoding.UTF8;
            process=Process.Start(start);output=process.StandardOutput.ReadToEndAsync();process.StandardError.ReadToEndAsync();
            Dictionary<string,object> observed=new Dictionary<string,object>();report["readyObservation"]=observed;Stopwatch clock=Stopwatch.StartNew();bool pickerReady=false;
            while(clock.ElapsedMilliseconds<25000&&!process.HasExited) {if(Ready(process.Id,hwnd,frame,display,first,observed)){pickerReady=true;break;}Thread.Sleep(10);}
            Need(pickerReady,"Exact production input plane/screen+hover readiness was not observed.");
            report["helperReadyMilliseconds"]=clock.Elapsed.TotalMilliseconds;report["helperProcessId"]=process.Id;report["sourceHwnd"]=Id(hwnd);report["sourceProcessId"]=sourcePid;
            report["sourceUiThreadId"]=sourceThread;report["controllerThreadId"]=GetCurrentThreadId();report["sourcePhysicalDwmBounds"]=Rect(frame);report["sourceNotFullscreen"]=true;
            Thread.Sleep(40); // Deliberately inside the current250ms repair interval, not a wait-for-recovery test.
            source.Invoke((Action)delegate {
                Need(GetForegroundWindow()==hwnd,"Source foreground changed before controlled action.");
                Stopwatch gap=Stopwatch.StartNew();
                if(kind=="topmost-self-raise-immediate-drag") {
                    Need(SetWindowPos(hwnd,new IntPtr(-1),0,0,0,0,0x10|0x1|0x2),"Generated ordinary topmost source could not re-raise itself.");
                } else {
                    SetCapture(hwnd);Need(GetCapture()==hwnd,"Independent source UI thread could not obtain real native capture.");
                }
                GUI gui=new GUI();gui.size=(uint)Marshal.SizeOf(typeof(GUI));Need(GetGUIThreadInfo(sourceThread,ref gui),"Cannot observe native source-thread capture.");
                report["nativeCaptureHwndBeforeInput"]=Id(gui.capture);report["nativeCaptureConfirmed"]=kind=="cross-thread-native-capture"&&gui.capture==hwnd;
                IntPtr root=GetAncestor(WindowFromPoint(first),2);uint hitPid;GetWindowThreadProcessId(root,out hitPid);
                Need(hitPid==sourcePid||hitPid==process.Id,"Pointer now targets a foreign process; no input sent.");
                report["pointerRootImmediatelyBeforeInput"]=Id(root);report["pointerRootProcessIdImmediatelyBeforeInput"]=hitPid;
                report["pointerRootClassImmediatelyBeforeInput"]=Class(root);report["sourceRaisedImmediatelyBeforeInput"]=kind=="topmost-self-raise-immediate-drag";
                report["adversarialPreconditionMet"]=false;
                if(kind=="topmost-self-raise-immediate-drag") {
                    // An uncontested/repaired plane is not evidence that this
                    // test actually exercised the uncovered self-raise gap.
                    if(root!=hwnd)report["setupInconclusive"]=true;
                    Need(root==hwnd,"SETUP_NOT_REPRODUCED: The source self-raise gap was already repaired before input; no contention result is claimed.");
                } else {
                    Dictionary<string,object> atCapture=new Dictionary<string,object>();report["planeObservationWhileSourceOwnsCapture"]=atCapture;
                    Need(Ready(process.Id,hwnd,frame,display,first,atCapture),"SETUP_NOT_REPRODUCED: Native source capture was not concurrent with exact production plane coverage.");
                    GUI after=new GUI();after.size=(uint)Marshal.SizeOf(typeof(GUI));
                    Need(GetGUIThreadInfo(sourceThread,ref after)&&after.capture==hwnd,"Source native capture ownership changed before input.");
                    report["nativeCaptureHwndAfterPlaneObservation"]=Id(after.capture);
                }
                report["adversarialPreconditionMet"]=true;
                report["actionToInputMilliseconds"]=gap.Elapsed.TotalMilliseconds;partialInput=true;
                Send(new INPUT[] { Move(first),Mouse(2),Move(last),Mouse(4) });partialInput=false;
            });
            Thread.Sleep(180);
            // Drain this generated source thread's own queue before claiming
            // that no native button messages reached its controls.
            source.Invoke((Action)delegate { Application.DoEvents(); });
            report["underlyingMouseDowns"]=Interlocked.CompareExchange(ref downs,0,0);report["underlyingMouseUps"]=Interlocked.CompareExchange(ref ups,0,0);report["underlyingButtonClicks"]=Interlocked.CompareExchange(ref clicks,0,0);
            bool leak=downs!=0||ups!=0||clicks!=0;report["zeroUnderlyingInput"]=!leak;report["foregroundPreserved"]=GetForegroundWindow()==hwnd;
            source.Invoke((Action)delegate { if(GetCapture()==hwnd)ReleaseCapture(); });
            if(leak&&!process.HasExited)Escape(hwnd);
            Need(process.WaitForExit(10000),"Production picker did not finish after owned input/cancellation.");
            Dictionary<string,object> reply=json.Deserialize<Dictionary<string,object>>(output.GetAwaiter().GetResult());report["helperDiagnostics"]=SafeReply(reply);report["helperExitCode"]=process.ExitCode;
            Dictionary<string,object> health=(Dictionary<string,object>)reply["captureHealth"];
            Need(Convert.ToInt64(health["inputBackend"])==(backend=="planeOnly"?2:1),"Actual helper input backend differs from requested mode.");
            if(backend=="planeOnly")Need(Convert.ToInt64(health["mouseHookInstalled"])==0&&Convert.ToInt64(health["hookMouseDowns"])==0&&Convert.ToInt64(health["hookMouseUps"])==0,"Forced no-hook test did not actually disable mouse hooks.");
            Need(!leak,"UNDERLYING_INPUT: A generated ordinary source received the actual drag/click while the production picker was ready.");
            Need((bool)reply["ok"]&&process.ExitCode==0,"Production picker failed to return a valid region.");
            if(backend=="planeOnly")Need(Convert.ToInt64(health["inputPlaneDowns"])>0&&Convert.ToInt64(health["inputPlaneUps"])>0,"No actual input plane down/up delivery was proven.");
            using(MemoryStream bytes=new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))using(Bitmap image=new Bitmap(bytes)) {
                Need(image.Width==last.X-first.X&&image.Height==last.Y-first.Y,"Free ROI dimensions changed.");
                for(int y=0;y<image.Height;y++)for(int x=0;x<image.Width;x++){Color c=image.GetPixel(x,y);Need(!(Math.Abs(c.R-45)<=2&&Math.Abs(c.G-145)<=2&&Math.Abs(c.B-255)<=2),"Production hint pixels entered the generated ROI.");}
                report["capturedPhysicalSize"]=new int[] { image.Width,image.Height };report["blueHintPixelsInCapture"]=0;
            }
            Need(GetForegroundWindow()==hwnd&&Convert.ToInt64(health["inputPlaneRemainingAfterCleanup"])==0,"Source foreground or input plane cleanup failed.");report["ok"]=true;
        }catch(Exception error){report["error"]=error.Message;}
        finally {
            if(source!=null&&!source.IsDisposed)try{source.Invoke((Action)delegate { if(GetCapture()==hwnd)ReleaseCapture(); });}catch{}
            if(partialInput&&GetForegroundWindow()==hwnd)try{Send(new INPUT[] { Mouse(4) });}catch{}
            if(process!=null) {
                if(!process.HasExited&&GetForegroundWindow()==hwnd)try{Escape(hwnd);process.WaitForExit(3000);}catch{}
                if(!process.HasExited){process.Kill();process.WaitForExit(3000);}
                if(output!=null&&output.IsCompleted)try{report["helperDiagnostics"]=SafeReply(json.Deserialize<Dictionary<string,object>>(output.GetAwaiter().GetResult()));}catch{}
                process.Dispose();
            }
            if(source!=null&&!source.IsDisposed)try{source.Invoke((Action)delegate { source.Close(); });}catch{}
            if(!ui.Join(5000)){report["ok"]=false;report["cleanupError"]="Own generated source UI thread did not stop.";}ready.Dispose();
        }
        return report;
    }
    public static Dictionary<string,object> Run(string helper,string assembly,string backend) {
        Need(!helper.Contains("\"")&&!assembly.Contains("\""),"Invalid helper path.");SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Controller physical DPI context failed.");
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();bool ok=true;
        foreach(string kind in new string[] { "topmost-self-raise-immediate-drag","cross-thread-native-capture" }) {Dictionary<string,object> result=Case(helper,assembly,backend,kind);cases.Add(result);ok=ok&&(bool)result["ok"];}
        return new Dictionary<string,object> { { "ok",ok },{ "cases",cases },{ "requestedInputBackend",backend },{ "controlledCounterexample",true },{ "userContentCaptured",false },{ "clipboardAccessed",false },{ "scope","Generated ordinary topmost non-fullscreen window and its independent UI-thread capture only; no elevated/protected desktop or physical owner-app conclusion." } };
    }
}
'@
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([System.Windows.Forms.Form].Assembly.Location,[System.Drawing.Bitmap].Assembly.Location,[System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    $result=[EchoLingoInputOwnershipAdversarial]::Run($HelperPath,$NativeAssemblyPath,$InputBackend)
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 12 -Compress))
    if(-not $result.ok){exit 1}
} catch {
    [Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message;controlledCounterexample=$true;userContentCaptured=$false;clipboardAccessed=$false}|ConvertTo-Json -Compress));exit 1
}
