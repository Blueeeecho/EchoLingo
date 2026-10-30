# Exact production Rust hook/message-pump + Rust candidate picker, generated input only.
# C# oracle fixture stays unchanged; this exercises the same ten strict cases.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$NativeCapturePath,
      [Parameter(Mandatory=$true)][string]$HarnessPath, [switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -and -not $env:GITHUB_ACTIONS) { throw 'ISOLATION_REQUIRED: Use an explicitly isolated generated-window session.' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) { throw 'DESKTOP_UNAVAILABLE: An unlocked Windows desktop is required.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'TEST_APARTMENT: Use powershell.exe -STA.' }
    $NativeCapturePath=(Resolve-Path -LiteralPath $NativeCapturePath).Path
    $HarnessPath=(Resolve-Path -LiteralPath $HarnessPath).Path
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
public static class EchoLingoNativeCaptureSmoke {
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
    [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",SetLastError=true)] static extern IntPtr SendOwnedDisplayChange(IntPtr window,uint message,IntPtr wparam,IntPtr lparam,uint flags,uint timeout,out IntPtr result);
    static void SendOwnedPickerMessage(int helper,uint message) {
        IntPtr target=IntPtr.Zero;
        EnumWindows(delegate(IntPtr window,IntPtr unused){uint pid;GetWindowThreadProcessId(window,out pid);if(pid==helper&&Plane(window,helper)&&IsWindowVisible(window)){target=window;return false;}return true;},IntPtr.Zero);
        Need(target!=IntPtr.Zero,"Display notification requires a visible plane from this exact helper.");
        uint owner;GetWindowThreadProcessId(target,out owner);Need(owner==helper&&IsWindowVisible(target),"Display target ownership changed.");
        IntPtr result;Need(SendOwnedDisplayChange(target,message,IntPtr.Zero,IntPtr.Zero,2,1500,out result)!=IntPtr.Zero,"Owned display-change notification timed out.");
    }
    static void InvalidateOwnedPickerDisplay(int helper){SendOwnedPickerMessage(helper,0x007e);}
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window,ref Point point);
    [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr window,Point point,uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder value,int count);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window,StringBuilder text,int count);
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
    static bool Plane(IntPtr window,int pid) { return Class(window)=="EchoLingoNativeCapture-"+pid && (GetWindowLongPtr(window,-20).ToInt64()&0x00200000L)!=0; }
    static bool Loupe(IntPtr window) { StringBuilder title=new StringBuilder(64); return GetWindowText(window,title,title.Capacity)>0 && title.ToString()=="EchoLingoCaptureMagnifier"; }
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
        List<WindowInfo> thin=new List<WindowInfo>(),planes=new List<WindowInfo>();int allocated=0,loupes=0;bool loupeNear=false;
        EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint pid;GetWindowThreadProcessId(window,out pid);if (pid!=helper) return true;
            long style=GetWindowLongPtr(window,-20).ToInt64();
            if (Plane(window,helper)) {
                if (!IsWindowVisible(window)) return true;
                const long required=0x00200000L|0x08000000L|0x80L|8;
                Need((style&required)==required&&(style&(0x80000L|0x20L))==0,"Input plane styles invalid.");
                planes.Add(new WindowInfo { Handle=window,Bounds=Bounds(window) });return true;
            }
            if (Loupe(window)) {
                if (!IsWindowVisible(window)) return true;
                loupes++; Rectangle candidate=Bounds(window);
                int dx=candidate.Left+candidate.Width/2-point.X, dy=candidate.Top+candidate.Height/2-point.Y;
                bool styleOk=(style&0x08000000L)!=0 && (style&0x20L)!=0 && (style&0x80000L)==0;
                bool sizeOk=candidate.Width>=140 && candidate.Width<=360 && candidate.Height>=150 && candidate.Height<=420;
                if (styleOk && sizeOk && (long)dx*dx+(long)dy*dy<=500L*500L && !candidate.Contains(point)) loupeNear=true;
                return true;
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
        long rawStyle=GetWindowLongPtr(raw,-20).ToInt64();
        bool rawLoupe=Loupe(raw)&&(rawStyle&0x20L)!=0&&(rawStyle&0x80000L)==0;
        bool hit=planes.Exists(delegate(WindowInfo p){return p.Handle==through&&p.Bounds.Contains(point);})
            && (planes.Exists(delegate(WindowInfo p){return p.Handle==raw;})||thin.Exists(delegate(WindowInfo e){return e.Handle==raw&&e.Bounds.Contains(point);})||rawLoupe);
        bool loupeReady=loupes==1 && loupeNear;
        observed["thinVisibleCount"]=thin.Count;observed["thinAllocatedCount"]=allocated;observed["planeVisibleCount"]=planes.Count;
        observed["captureMagnifierCount"]=loupes;observed["captureMagnifierNearPointer"]=loupeReady;
        observed["rawPointerRootHwnd"]=Id(raw);observed["transparentSkippingRootHwnd"]=Id(through);
        observed["exactPlanePointerHit"]=hit;return exact&&wanted.Count==0&&planeGeometry&&monitors.Count==0&&hit&&loupeReady;
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
    sealed class Host : IDisposable {
        public Process Process;public int Child;public int Generation;public bool Usable=true;
        Task<string> error;Task<string> pending;StreamWriter input;public bool FirstCommandBomRemoved;public bool OrdinaryPathsVerified;
        public Host(string harness,string helper) {
            ProcessStartInfo start=new ProcessStartInfo(harness,"\""+helper+"\"");
            start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardInput=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=Encoding.UTF8;
            Process=Process.Start(start);input=new StreamWriter(Process.StandardInput.BaseStream,new UTF8Encoding(false));input.AutoFlush=true;error=Process.StandardError.ReadToEndAsync();
            try { Dictionary<string,object> ready=Read(5000);Need((string)ready["event"]=="host"&&(bool)ready["productionModulesImported"]&&(bool)ready["outsideClickGateDisarmed"],"Exact production observer did not start.");OrdinaryPathsVerified=ready.ContainsKey("ordinaryNativeCapturePathVerified")&&(bool)ready["ordinaryNativeCapturePathVerified"];Need(OrdinaryPathsVerified,"Ordinary native executable path equivalence was not verified."); }
            catch {if(!Process.HasExited){Process.Kill();Process.WaitForExit(3000);}Process.Dispose();throw;}
        }
        public Dictionary<string,object> Read(int milliseconds) {
            if(pending==null)pending=Process.StandardOutput.ReadLineAsync();
            Need(pending.Wait(milliseconds),"HOST_PROTOCOL_TIMEOUT: Bounded private host response did not arrive.");
            string line=pending.GetAwaiter().GetResult();pending=null;
            if(line==null){Usable=false;string ownError=error!=null&&error.IsCompleted?error.GetAwaiter().GetResult():"";Need(false,"HOST_PROTOCOL_EOF: "+ownError.Substring(0,Math.Min(ownError.Length,600)));}
            Need(line.Length<=32*1024*1024,"HOST_PROTOCOL_SIZE");
            return json.Deserialize<Dictionary<string,object>>(line);
        }
        public int Begin() {
            Need(Child==0&&Usable&&!Process.HasExited,"Previous session did not finish.");
            Dictionary<string,object> child;try{input.WriteLine("capture");child=Read(5000);}catch{Usable=false;throw;}
            Need((string)child["event"]=="child"&&Convert.ToInt32(child["hostProcessId"])==Process.Id,"Unexpected host child identity.");
            FirstCommandBomRemoved=(bool)child["firstCommandBomRemoved"];Generation++;Need(Convert.ToInt32(child["generation"])==Generation,"Host generation did not advance exactly once.");Child=Convert.ToInt32(child["helperProcessId"]);return Child;
        }
        public Dictionary<string,object> Finish(Dictionary<string,object> report,int timeout) {
            Dictionary<string,object> reply=Read(timeout);report["helperDiagnostics"]=SafeReply(reply);
            Dictionary<string,object> closed=Read(3000);report["hostSessionClosure"]=closed;
            Need((string)closed["event"]=="closed"&&Convert.ToInt32(closed["generation"])==Generation,"Host closure identity mismatch.");Child=0;
            Need((bool)closed["sessionCloseCalled"]&&!(bool)closed["helperDeadlineKilled"]&&Convert.ToInt64(closed["hostThreadId"])>0&&!Process.HasExited,"Host session did not close normally.");
            Need(reply.ContainsKey("ok")&&Convert.ToInt32(closed["helperExitCode"])==((bool)reply["ok"]?0:1),"Helper response and actual process exit code disagree.");return reply;
        }
        public void Shutdown(){input.WriteLine("shutdown");}
        public void Dispose() {
            if(Process==null)return;
            try {
                if(!Process.HasExited&&Child==0){input.WriteLine("shutdown");}
                if(!Process.WaitForExit(4000))Process.Kill();Process.WaitForExit(3000);
            }finally{Process.Dispose();}
        }
    }
    sealed class EscapeSourceFilter : IMessageFilter {
        readonly Sources owner;public EscapeSourceFilter(Sources value){owner=value;}
        public bool PreFilterMessage(ref Message message) {
            // This thread's OWN generated source only; observe Escape before
            // WinForms dialog-key routing, without swallowing or reading text.
            if(owner.AH!=IntPtr.Zero&&GetAncestor(message.HWnd,2)==owner.AH&&message.WParam.ToInt64()==0x1b) {
                if(message.Msg==0x100||message.Msg==0x104)Interlocked.Increment(ref owner.EscapeDowns);
                if(message.Msg==0x101||message.Msg==0x105)Interlocked.Increment(ref owner.EscapeUps);
            }
            return false;
        }
    }
    sealed class Sources : IDisposable {
        public Form A,B,Background;public IntPtr AH,BH;public uint ThreadId;public Rectangle AFrame,BFrame,Display;public Point First,Last;
        public int Downs,Ups,Clicks,EscapeDowns,EscapeUps;public bool Partial,EscapePartial;Thread ui;ManualResetEvent ready=new ManualResetEvent(false);string error;
        public Sources() {
            ui=new Thread(delegate(){
                try {
                    Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Source DPI context failed.");
                    A=new Form();B=new Form();Background=new Form();Rectangle work=Screen.PrimaryScreen.WorkingArea;Display=Screen.PrimaryScreen.Bounds;
                    Need(work.Width>=900&&work.Height>=440,"Generated peer fixture needs900x440 work area.");
                    Prepare(A,new Rectangle(work.X+35,work.Y+45,380,320),Color.FromArgb(40,180,90));
                    Prepare(B,new Rectangle(work.X+455,work.Y+45,380,320),Color.FromArgb(190,70,130));
                    Background.FormBorderStyle=FormBorderStyle.None;Background.StartPosition=FormStartPosition.Manual;Background.ShowInTaskbar=true;Background.Owner=null;Background.TopMost=true;Background.Bounds=Rectangle.Union(A.Bounds,B.Bounds);Background.BackColor=Color.FromArgb(72,90,110);
                    A.Shown+=delegate {
                        try {
                            Background.Show();B.Show();AH=A.Handle;BH=B.Handle;ThreadId=GetCurrentThreadId();
                            Need(AH!=BH&&GetWindow(AH,4)==IntPtr.Zero&&GetWindow(BH,4)==IntPtr.Zero&&GetParent(AH)==IntPtr.Zero&&GetParent(BH)==IntPtr.Zero,"Generated sources are not independent ownerless peers.");
                            Need(GetAncestor(AH,2)==AH&&GetAncestor(BH,2)==BH,"Peer roots changed.");
                            SetForegroundWindow(AH);A.Activate();AFrame=Frame(AH);BFrame=Frame(BH);First=A.PointToScreen(new Point(65,70));Last=B.PointToScreen(new Point(100,115));
                        }catch(Exception e){error=e.Message;}finally{ready.Set();}
                    };EscapeSourceFilter filter=new EscapeSourceFilter(this);Application.AddMessageFilter(filter);try{Application.Run(A);}finally{Application.RemoveMessageFilter(filter);}
                }catch(Exception e){error=e.Message;ready.Set();}
                finally {if(Background!=null)Background.Dispose();if(B!=null)B.Dispose();if(A!=null)A.Dispose();}
            });ui.IsBackground=true;ui.SetApartmentState(ApartmentState.STA);ui.Start();
            try {
            Need(ready.WaitOne(10000)&&error==null,"Generated peer setup failed: "+error);
            Need(ThreadId!=GetCurrentThreadId()&&GetForegroundWindow()==AH,"Source is not the independent foreground UI thread.");
            uint pid;Need(GetWindowThreadProcessId(AH,out pid)==ThreadId&&pid==Process.GetCurrentProcess().Id,"Source PID/TID mismatch.");
            Need(Display.Contains(AFrame)&&Display.Contains(BFrame)&&!AFrame.IntersectsWith(BFrame)&&AFrame!=Display&&BFrame!=Display,"Generated peers are not independent non-fullscreen windows.");
            Need(GetAncestor(WindowFromPoint(First),2)==AH&&GetAncestor(WindowFromPoint(Last),2)==BH,"Generated input endpoints are obscured.");
            Send(new INPUT[]{Move(First)});Thread.Sleep(70);
            }catch{Dispose();throw;}
        }
        void Prepare(Form form,Rectangle bounds,Color color) {
            form.Text="EchoLingo generated delegated-input peer";form.AutoScaleMode=AutoScaleMode.None;form.FormBorderStyle=FormBorderStyle.None;
            form.StartPosition=FormStartPosition.Manual;form.ShowInTaskbar=true;form.Owner=null;form.TopMost=true;form.Bounds=bounds;form.BackColor=color;
            Button button=new Button();button.Bounds=new Rectangle(40,50,240,100);button.Text="Generated input only";button.FlatStyle=FlatStyle.Flat;button.UseVisualStyleBackColor=false;button.BackColor=Color.FromArgb(230,150,40);
            button.FlatAppearance.MouseOverBackColor=button.BackColor;button.FlatAppearance.MouseDownBackColor=button.BackColor;
            button.MouseDown+=delegate {Interlocked.Increment(ref Downs);};button.MouseUp+=delegate {Interlocked.Increment(ref Ups);};button.Click+=delegate {Interlocked.Increment(ref Clicks);};
            form.MouseDown+=delegate {Interlocked.Increment(ref Downs);};form.MouseUp+=delegate {Interlocked.Increment(ref Ups);};form.Controls.Add(button);
        }
        public void OnUi(Action action){A.Invoke(action);}
        public void Drain(){OnUi(delegate {Application.DoEvents();});}
        public void Dispose(){
            if(A!=null&&!A.IsDisposed)try{OnUi(delegate {if(GetCapture()!=IntPtr.Zero)ReleaseCapture();B.Close();Background.Close();A.Close();});}catch{}
            Need(ui.Join(5000),"Generated peer UI thread did not clean up.");ready.Dispose();
        }
    }
    static void EscapePart(IntPtr source,bool up) {
        Need(GetForegroundWindow()==source,"Source foreground changed; no Escape input sent elsewhere.");
        INPUT value=new INPUT();value.type=1;value.data.key.vk=0x1b;value.data.key.flags=up?2u:0u;Send(new INPUT[]{value});
    }
    static int VisibleOwnedWindows(int helper) {
        int count=0;EnumWindows(delegate(IntPtr window,IntPtr unused){uint pid;GetWindowThreadProcessId(window,out pid);if(pid==helper&&IsWindowVisible(window))count++;return true;},IntPtr.Zero);return count;
    }
    static bool HasVisibleOwnedBorder(int helper) {
        bool seen=false;
        EnumWindows(delegate(IntPtr window,IntPtr unused){
            uint pid;GetWindowThreadProcessId(window,out pid);
            if(pid!=helper||Class(window)!="EchoLingoNativeCapture-"+helper||!IsWindowVisible(window))return true;
            long style=GetWindowLongPtr(window,-20).ToInt64();const long edge=0x08000000L|0x80000L|0x20L|8;
            if((style&edge)==edge){Rectangle r=Bounds(window);if(r.Width>0&&r.Height>0&&Math.Min(r.Width,r.Height)<=2){seen=true;return false;}}
            return true;
        },IntPtr.Zero);return seen;
    }
    static int VisiblePlanes(int helper) {
        int count=0;EnumWindows(delegate(IntPtr window,IntPtr unused){uint pid;GetWindowThreadProcessId(window,out pid);if(pid==helper&&Plane(window,helper)&&IsWindowVisible(window))count++;return true;},IntPtr.Zero);return count;
    }
    static int AllocatedEdges(int helper) {
        int count=0;EnumWindows(delegate(IntPtr window,IntPtr unused){uint pid;GetWindowThreadProcessId(window,out pid);if(pid==helper){long style=GetWindowLongPtr(window,-20).ToInt64();if((style&(0x8000000L|0x80000L|0x20L))==(0x8000000L|0x80000L|0x20L))count++;}return true;},IntPtr.Zero);return count;
    }
    static bool Alive(int pid){try{using(Process process=Process.GetProcessById(pid))return !process.HasExited;}catch(ArgumentException){return false;}}
    static void Drag(Sources source,Point last,bool held,bool cancel) {
        Need(GetForegroundWindow()==source.AH,"Source lost foreground before generated drag.");source.Partial=true;
        Send(new INPUT[]{Move(source.First),Mouse(2)});if(held){Thread.Sleep(100);Send(new INPUT[]{Move(last)});Thread.Sleep(900);}else Send(new INPUT[]{Move(last)});
        if(cancel)Escape(source.AH);Send(new INPUT[]{Mouse(4)});source.Partial=false;
    }
    static Dictionary<string,object> Case(Host host,string kind) {
        Dictionary<string,object> report=new Dictionary<string,object>{{"mode",kind},{"ok",false}};Sources source=null;bool finished=false;
        try {
            source=new Sources();int oldDown=0,oldUp=0,oldClick=0;
            bool preheld=kind=="preheld-source-release-then-first-fresh-pair";
            if(preheld){Send(new INPUT[]{Mouse(2)});source.Partial=true;Thread.Sleep(80);source.Drain();Need(source.Downs==1&&source.Ups==0,"Preheld setup did not deliver exactly one source down.");}
            if(kind=="escape-held900ms-drains-real-key-up") {
                Escape(source.AH);Stopwatch positive=Stopwatch.StartNew();
                while(positive.ElapsedMilliseconds<1500&&(source.EscapeDowns<1||source.EscapeUps<1)){source.Drain();Thread.Sleep(5);}
                source.Drain();
                Need(source.EscapeDowns==1&&source.EscapeUps==1,"Escape source observation positive control failed before capture.");
                report["escapeObservationPositiveControl"]=true;
            }
            Stopwatch requestToBorder=Stopwatch.StartNew();
            int helper=host.Begin();report["helperProcessId"]=helper;report["hostProcessId"]=host.Process.Id;report["generation"]=host.Generation;report["firstCommandBomRemoved"]=host.FirstCommandBomRemoved;report["ordinaryNativeCapturePathVerified"]=host.OrdinaryPathsVerified;
            report["sourceAHwnd"]=Id(source.AH);report["sourceBHwnd"]=Id(source.BH);report["sourceUiThreadId"]=source.ThreadId;report["controllerThreadId"]=GetCurrentThreadId();
            report["sourcePhysicalDwmBounds"]=Rect(source.AFrame);report["sourceForegroundBefore"]=Id(GetForegroundWindow());
            if(preheld){
                Stopwatch allocation=Stopwatch.StartNew();while(allocation.ElapsedMilliseconds<25000&&Alive(helper)&&AllocatedEdges(helper)!=12*Screen.AllScreens.Length)Thread.Sleep(10);
                Need(AllocatedEdges(helper)==12*Screen.AllScreens.Length&&VisiblePlanes(helper)==0,"Preheld helper did not remain unarmed/hidden after allocating exact thin windows.");
                GUI before=new GUI();before.size=(uint)Marshal.SizeOf(typeof(GUI));Need(GetGUIThreadInfo(source.ThreadId,ref before)&&before.capture!=IntPtr.Zero&&GetAncestor(before.capture,2)==source.AH,"Source did not retain its pre-existing real capture.");
                Send(new INPUT[]{Mouse(4)});source.Partial=false;Thread.Sleep(80);source.Drain();
                Need(source.Downs==1&&source.Ups==1&&source.Clicks==1,"Old source release was consumed or duplicated by the new session.");
                oldDown=source.Downs;oldUp=source.Ups;oldClick=source.Clicks;
                report["preheldSourceDowns"]=oldDown;report["preheldSourceUps"]=oldUp;report["preheldSourceClicks"]=oldClick;report["preheldPlanesHidden"]=true;
            }
            Dictionary<string,object> observed=new Dictionary<string,object>();report["readyObservation"]=observed;Stopwatch clock=Stopwatch.StartNew();bool ready=false;
            while(clock.ElapsedMilliseconds<25000&&Alive(helper)){
                if(!report.ContainsKey("requestToFirstBorderObservedMilliseconds")&&HasVisibleOwnedBorder(helper)) {
                    report["requestToFirstBorderObservedMilliseconds"]=requestToBorder.Elapsed.TotalMilliseconds;
                    report["borderTimingScope"]="Parent fixture capture command through child launch to first observed visible border; 10ms polling upper bound, NOT application Alt+S latency";
                }
                if(Ready(helper,source.AH,source.AFrame,source.Display,source.First,observed)){ready=true;break;}Thread.Sleep(10);}
            Need(ready,"Exact delegated helper screen/hover/plane readiness was not observed within25000ms.");report["helperReadyMilliseconds"]=clock.Elapsed.TotalMilliseconds;report["requestToFullPickerReadyObservedMilliseconds"]=requestToBorder.Elapsed.TotalMilliseconds;
            bool planeCancel=kind=="own-plane-cancelmode-no-input";bool heldEscape=kind=="escape-held900ms-drains-real-key-up";bool displayInvalid=kind=="display-change-before-input";bool late=kind=="escape-held-release-after-helper-close";Dictionary<string,object> reply=null;bool cross=kind=="cross-peer-held900ms";if(cross)source.OnUi(delegate {source.Background.BackColor=Color.FromArgb(75,115,165);source.Background.Refresh();});Point last=cross?source.Last:new Point(source.First.X+35,source.First.Y+15);bool cancel=kind=="escape-drains-owned-release";
            if(planeCancel){
                SendOwnedPickerMessage(helper,0x001f);report["ownedPlaneCancelModeMessage"]=0x001f;
            }else if(heldEscape){
                EscapePart(source.AH,false);source.EscapePartial=true;
                Stopwatch hidden=Stopwatch.StartNew();while(hidden.ElapsedMilliseconds<2500&&Alive(helper)&&VisibleOwnedWindows(helper)!=0)Thread.Sleep(10);
                Need(Alive(helper)&&VisibleOwnedWindows(helper)==0,"Held Escape must hide all picker visuals without abandoning its owned up.");
                Thread.Sleep(900);Need(Alive(helper)&&VisibleOwnedWindows(helper)==0,"Child exited or showed overlays before its real held Escape up.");
                EscapePart(source.AH,false); // Own auto-repeat must remain consumed while closing.
                EscapePart(source.AH,true);source.EscapePartial=false;
                source.Drain();Need(source.EscapeDowns==1&&source.EscapeUps==1,"Owned Escape down/repeat/up leaked into source beyond the verified positive-control pair.");
                report["heldEscapeMilliseconds"]=900;report["allVisualsHiddenWhileEscapeOwned"]=true;report["zeroUnderlyingEscapeInput"]=true;
            }else if(displayInvalid){
                InvalidateOwnedPickerDisplay(helper);report["actualDisplayConfigurationChanged"]=false;
            }else if(late){
                source.Partial=true;Send(new INPUT[]{Move(source.First),Mouse(2),Move(last)});Thread.Sleep(100);Escape(source.AH);
                reply=host.Finish(report,12000);finished=true;
                // Outlive both C# Stop(600ms) and native Session.close(500ms).
                // Its old owned up must still be consumed after child teardown.
                Thread.Sleep(1600);Need(!host.Process.HasExited,"Host exited before delayed old owned release.");
                Send(new INPUT[]{Mouse(4)});source.Partial=false;report["ownedReleaseAfterHelperCloseMilliseconds"]=1600;
            }else if(kind=="topmost-self-raise-immediate-first-pair"){
                source.OnUi(delegate {
                    Need(SetWindowPos(source.AH,new IntPtr(-1),0,0,0,0,0x10|1|2),"Source self-raise failed.");IntPtr raw=GetAncestor(WindowFromPoint(source.First),2);
                    report["pointerRootImmediatelyBeforeInput"]=Id(raw);Need(raw==source.AH,"SETUP_NOT_REPRODUCED: Source self-raise gap repaired before input.");report["adversarialPreconditionMet"]=true;
                    Drag(source,last,false,false);
                });
            }else if(kind=="foreign-thread-native-capture"){
                source.OnUi(delegate {SetCapture(source.AH);Need(GetCapture()==source.AH,"Source native capture setup failed.");});
                Dictionary<string,object> during=new Dictionary<string,object>();Need(Ready(helper,source.AH,source.AFrame,source.Display,source.First,during),"Native capture did not coexist with exact plane hit.");report["planeWhileForeignCapture"]=during;
                GUI after=new GUI();after.size=(uint)Marshal.SizeOf(typeof(GUI));Need(GetGUIThreadInfo(source.ThreadId,ref after)&&after.capture==source.AH,"Source native capture changed before input.");report["nativeCaptureBeforeInput"]=Id(after.capture);report["adversarialPreconditionMet"]=true;
                Drag(source,last,true,false);
            }else Drag(source,last,cross||cancel,cancel);
            Thread.Sleep(120);source.Drain();report["underlyingMouseDowns"]=source.Downs-oldDown;report["underlyingMouseUps"]=source.Ups-oldUp;report["underlyingButtonClicks"]=source.Clicks-oldClick;
            bool zero=source.Downs==oldDown&&source.Ups==oldUp&&source.Clicks==oldClick;report["zeroUnderlyingInput"]=zero;
            if(!zero&&Alive(helper))Escape(source.AH);
            if(reply==null){reply=host.Finish(report,12000);finished=true;}
            Need(zero,"UNDERLYING_INPUT: Generated source received a fresh capture down/up/click.");
            Dictionary<string,object> health=(Dictionary<string,object>)reply["captureHealth"];
            // Host down/up counters are sparse: production creates them only when an event occurs.
            // Only this intentionally no-input display-cancellation case may omit them.
            foreach(string key in new string[]{"inputBackend","nativeHostReady","nativeHostArmed","nativeHostDowns","mouseHookInstalled","hookMouseDowns","hookMouseUps","inputPlaneDowns","inputPlaneUps","inputPlaneRemainingAfterCleanup"})Need((displayInvalid&&key=="nativeHostDowns")||health.ContainsKey(key),"Missing delegated health field: "+key);
            Need(reply.ContainsKey("nativeBackend")&&(string)reply["nativeBackend"]=="rust-win32-capture"&&health.ContainsKey("nativeCaptureBackend")&&Convert.ToInt64(health["nativeCaptureBackend"])==1,"Candidate test must never silently use legacy PowerShell/C# capture.");
            Need(Convert.ToInt64(health["inputBackend"])==3&&Convert.ToInt64(health["nativeHostReady"])==1&&Convert.ToInt64(health["nativeHostArmed"])==1,"Actual production native host handshake did not complete.");
            Need(Convert.ToInt64(health["mouseHookInstalled"])==0&&Convert.ToInt64(health["hookMouseDowns"])==0&&Convert.ToInt64(health["hookMouseUps"])==0&&Convert.ToInt64(health["inputPlaneDowns"])==0&&Convert.ToInt64(health["inputPlaneUps"])==0,"Old managed hook or input plane handled this purported delegated capture.");
            if(planeCancel){
                Need(!(bool)reply["ok"]&&!reply.ContainsKey("imageBase64")&&reply.ContainsKey("error")&&Convert.ToString(reply["error"]).StartsWith("CANCELLED:",StringComparison.Ordinal),"Actual owned-plane WM_CANCELMODE must cancel without pixels.");
                Need(health.ContainsKey("inputWindowCancellationMessage")&&Convert.ToInt64(health["inputWindowCancellationMessage"])==0x001f,"Cancellation was not attributed to the actual input-plane message.");
                Need(Convert.ToInt64(health["nativeHostStopped"])==1&&Convert.ToInt64(health["nativeHostDowns"])==0&&Convert.ToInt64(health["nativeHostUps"])==0,"No-input plane cancellation fabricated input or missed STOP.");
                report["actualInputPlaneCancellationRetained"]=true;
            }else if(heldEscape){
                source.Drain();Need(source.EscapeDowns==1&&source.EscapeUps==1,"Owned Escape leaked after completed child teardown.");
                Need(!(bool)reply["ok"]&&!reply.ContainsKey("imageBase64")&&reply.ContainsKey("error"),"Held Escape cancellation produced pixels or success.");
                Need(Convert.ToString(reply["error"]).StartsWith("CANCELLED:",StringComparison.Ordinal)||Convert.ToString(reply["error"]).StartsWith("CAPTURE_INPUT_RELEASE:",StringComparison.Ordinal),"Held Escape failed for an unrelated native error.");
                Need(health.ContainsKey("nativeHostStopped")&&Convert.ToInt64(health["nativeHostStopped"])==1&&Convert.ToInt64(health["nativeHostDowns"])==0&&Convert.ToInt64(health["nativeHostUps"])==0,"Escape-only session fabricated a mouse pair or missed STOP.");
                Need(health.ContainsKey("hookEscapeReleaseUnconfirmed")&&Convert.ToInt64(health["hookEscapeReleaseUnconfirmed"])==0&&Convert.ToInt64(health["hookRunningAfterStop"])==0,"Escape hook exited without proving owned key-up drained.");
            }else if(displayInvalid){
                Need(health.ContainsKey("nativeHostStopped")&&Convert.ToInt64(health["nativeHostStopped"])==1
                    &&(!health.ContainsKey("nativeHostDowns")||Convert.ToInt64(health["nativeHostDowns"])==0)
                    &&(!health.ContainsKey("nativeHostUps")||Convert.ToInt64(health["nativeHostUps"])==0),
                    "Display cancellation did not stop the actual host session without consuming nonexistent input.");
                Need(!(bool)reply["ok"]&&reply.ContainsKey("error")
                    &&Convert.ToString(reply["error"]).StartsWith("CAPTURE_DISPLAY_CHANGED:",StringComparison.Ordinal)
                    &&!reply.ContainsKey("imageBase64"),"Display invalidation must fail closed without image.");
                report["displayChangeFailClosed"]=true;
            }else if(late){
                Need(Convert.ToInt64(health["nativeHostDowns"])==1&&(!health.ContainsKey("nativeHostUps")||Convert.ToInt64(health["nativeHostUps"])==0),"Delayed release unexpectedly reached the already closed child mailbox.");
                Need(!(bool)reply["ok"]&&reply.ContainsKey("error")&&Convert.ToString(reply["error"]).Contains("CAPTURE_INPUT_HOST")&&!reply.ContainsKey("imageBase64")&&health.ContainsKey("nativeHostFailed")&&Convert.ToInt64(health["nativeHostFailed"])==1,"Held release must make child shutdown fail closed visibly; it cannot return a screenshot.");
                report["childFailClosedBeforeDelayedOwnedUp"]=true;
            }else Need(health.ContainsKey("nativeHostStopped")&&Convert.ToInt64(health["nativeHostStopped"])==1&&health.ContainsKey("nativeHostUps")&&Convert.ToInt64(health["nativeHostDowns"])==1&&Convert.ToInt64(health["nativeHostUps"])==1,"First actual native host pair or stop handshake was lost/duplicated.");
            if(late||displayInvalid||heldEscape||planeCancel){}else if(cancel){Need(!(bool)reply["ok"]&&reply.ContainsKey("error")&&Convert.ToString(reply["error"]).ToLowerInvariant().Contains("cancel"),"Actual Esc did not cancel.");report["actualEscapeCancelled"]=true;}
            else {
                Need((bool)reply["ok"],"Delegated capture failed.");using(MemoryStream bytes=new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))using(Bitmap image=new Bitmap(bytes)){
                    Need(image.Width==last.X-source.First.X&&image.Height==last.Y-source.First.Y,"First-release free ROI dimensions changed.");
                    for(int y=0;y<image.Height;y++)for(int x=0;x<image.Width;x++){Color c=image.GetPixel(x,y);Need(!(Math.Abs(c.R-45)<=2&&Math.Abs(c.G-145)<=2&&Math.Abs(c.B-255)<=2),"Blue hint pixels entered generated ROI.");}
                    if(cross){
                        Point gap=new Point(source.AFrame.Right+20,source.First.Y+8);Need(source.Background.Bounds.Contains(Rectangle.FromLTRB(source.First.X,source.First.Y,last.X,last.Y)),"Generated background does not cover entire peer ROI.");
                        Color middle=image.GetPixel(gap.X-source.First.X,gap.Y-source.First.Y);Need(Math.Abs(middle.R-75)<=2&&Math.Abs(middle.G-115)<=2&&Math.Abs(middle.B-165)<=2,"Cross-peer ROI did not contain the freshly changed generated gap background.");
                        Color a=image.GetPixel(3,3),b=image.GetPixel(image.Width-3,image.Height-3);Need(Math.Abs(a.R-230)<=2&&Math.Abs(a.G-150)<=2&&Math.Abs(a.B-40)<=2&&Math.Abs(b.R-230)<=2&&Math.Abs(b.G-150)<=2&&Math.Abs(b.B-40)<=2,"Cross-peer ROI did not contain both generated source buttons.");
                        report["generatedPeerAndLiveGapColorProbes"]=true;
                    }
                    report["capturedPhysicalSize"]=new int[]{image.Width,image.Height};report["blueHintPixelsInCapture"]=0;
                }
            }
            Need(GetForegroundWindow()==source.AH&&Frame(source.AH)==source.AFrame&&Frame(source.BH)==source.BFrame,"Source foreground or peer frames changed.");report["foregroundPreserved"]=true;
            Need(Convert.ToInt64(health["inputPlaneRemainingAfterCleanup"])==0&&VisiblePlanes(helper)==0&&!Alive(helper),"Helper/input plane cleanup did not finish.");
            source.OnUi(delegate {if(GetCapture()!=IntPtr.Zero)ReleaseCapture();});
            // The exact production hook pump remains alive here. A normal click
            // must reach its source after this session closes, before process exit.
            Need(!host.Process.HasExited,"Host exited before post-session ownership test.");Send(new INPUT[]{Move(source.First),Mouse(2),Mouse(4)});Thread.Sleep(90);source.Drain();
            Need(source.Downs==oldDown+1&&source.Ups==oldUp+1&&source.Clicks==oldClick+1,"Closing delegated generation still consumed or duplicated normal input.");
            report["postSessionSourceClickRestored"]=true;report["hostAliveAfterSessionClose"]=true;report["ok"]=true;
        }catch(Exception error){while(error.InnerException!=null)error=error.InnerException;report["error"]=error.Message;}
        finally {
            if(source!=null){
                if(source.EscapePartial&&GetForegroundWindow()==source.AH)try{EscapePart(source.AH,true);source.EscapePartial=false;}catch{}
                if(source.Partial&&GetForegroundWindow()==source.AH)try{Send(new INPUT[]{Mouse(4)});source.Partial=false;}catch{}
                if(host.Child!=0){
                    if(GetForegroundWindow()==source.AH)try{Escape(source.AH);}catch{}
                    if(!finished)try{host.Finish(report,4000);finished=true;}catch{}
                    if(!finished){try{using(Process child=Process.GetProcessById(host.Child)){child.Kill();child.WaitForExit(3000);}}catch{}try{host.Finish(report,4000);finished=true;}catch{host.Usable=false;}}
                }
                try{source.Dispose();}catch(Exception cleanup){report["ok"]=false;report["cleanupError"]=cleanup.Message;}
            }
        }
        return report;
    }
    public static Dictionary<string,object> Run(string helper,string harness) {
        Need(!helper.Contains("\"")&&!harness.Contains("\""),"Invalid fixture path.");SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Controller physical DPI context failed.");
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();bool ok=true;Dictionary<string,object> stopped=null;
        using(Host host=new Host(harness,helper)){
            foreach(string kind in new string[]{"first-fresh-pair-immediate-release","topmost-self-raise-immediate-first-pair","foreign-thread-native-capture","cross-peer-held900ms","preheld-source-release-then-first-fresh-pair","escape-drains-owned-release","escape-held-release-after-helper-close","next-capture-after-escape","display-change-before-input","next-capture-after-display-change","escape-held900ms-drains-real-key-up","next-capture-after-held-escape","own-plane-cancelmode-no-input","next-capture-after-plane-cancelmode"}){
                Dictionary<string,object> result=Case(host,kind);cases.Add(result);ok=ok&&(bool)result["ok"];if(!host.Usable||host.Child!=0||host.Process.HasExited)break;
            }
            if(host.Child==0&&!host.Process.HasExited){host.Shutdown();stopped=host.Read(4000);Need((string)stopped["event"]=="stopped"&&Convert.ToInt32(stopped["completedGenerations"])==cases.Count,"Host stop/generation mismatch.");Need(host.Process.WaitForExit(4000)&&host.Process.ExitCode==0,"Production observer host failed to exit.");}
            else ok=false;
        }
        return new Dictionary<string,object>{{"ok",ok&&cases.Count==14},{"cases",cases},{"hostShutdown",stopped},{"productionModulesImported",true},{"requestedInputBackend","delegated-exact-production"},{"userContentCaptured",false},{"clipboardAccessed",false},{"scope","Exact production hook pump/session and Rust candidate picker with generated same-integrity peers only; no Tauri/engine, physical app, elevated boundary or universal acceptance claim."}};
    }
}
'@
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([System.Windows.Forms.Form].Assembly.Location,[System.Drawing.Bitmap].Assembly.Location,[System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    $result=[EchoLingoNativeCaptureSmoke]::Run($NativeCapturePath,$HarnessPath)
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 14 -Compress))
    if(-not $result.ok){exit 1}
} catch {
    [Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message;productionModulesImported=$true;userContentCaptured=$false;clipboardAccessed=$false}|ConvertTo-Json -Compress));exit 1
}
