# Independent experiment, never a production picker or a fallback setting.
# Generated A/B and the input HWNDs share one process but use independent UI
# threads. This gives explicit foreground rights in this isolated test; it does
# NOT prove that Tauri's background PowerShell child has foreground permission.
[CmdletBinding()]
param([switch]$IsolatedTestSession)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) {
        throw 'ACTIVE_EXPERIMENT_SESSION: Use an explicitly isolated unlocked Windows desktop.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'ACTIVE_EXPERIMENT_APARTMENT: Use powershell.exe -STA.' }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
public static class EchoLingoActiveCaptureExperiment {
    delegate IntPtr WindowProc(IntPtr window, uint message, IntPtr wp, IntPtr lp);
    static readonly WindowProc callback = WndProc;
    static CaseState current;
    static int epoch;
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left,top,right,bottom; }
    [StructLayout(LayoutKind.Sequential)] struct GUI { public uint size,flags; public IntPtr active,focus,capture,menuOwner,moveSize,caret; public RECT caretRect; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WindowClass {
        public uint size,style; public IntPtr procedure; public int classBytes,windowBytes;
        public IntPtr instance,icon,cursor,background; public string menu,name; public IntPtr smallIcon;
    }
    [StructLayout(LayoutKind.Sequential)] struct Paint { public IntPtr dc; public int erase; public RECT rectangle; public int restore,update; [MarshalAs(UnmanagedType.ByValArray,SizeConst=32)] public byte[] reserved; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct DATA { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public DATA data; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern ushort RegisterClassEx(ref WindowClass value);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool UnregisterClass(string name,IntPtr instance);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int width,int height,IntPtr parent,IntPtr menu,IntPtr module,IntPtr parameter);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr DefWindowProc(IntPtr window,uint message,IntPtr wp,IntPtr lp);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr BeginPaint(IntPtr window,out Paint paint);
    [DllImport("user32.dll")] static extern bool EndPaint(IntPtr window,ref Paint paint);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref Point point);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetFocus();
    [DllImport("user32.dll")] static extern IntPtr SetCapture(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetCapture();
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUI value);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] input,int size);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("dwmapi.dll")] static extern int DwmIsCompositionEnabled([MarshalAs(UnmanagedType.Bool)] out bool enabled);
    [DllImport("dwmapi.dll")] static extern int DwmFlush();
    sealed class Source {
        public Form A,B; public IntPtr Ah,Bh; public uint Thread,Pid; public Rectangle Bounds; public Point First,Last;
        public int Downs,Ups,Clicks,Escapes,Raises; public string Failure;
        public readonly ManualResetEvent Ready = new ManualResetEvent(false);
        public System.Windows.Forms.Timer Raising;
    }
    sealed class CaseState {
        public readonly List<IntPtr> Planes = new List<IntPtr>();
        public string Class,Failure; public IntPtr Instance,Active,Original; public uint OriginalPid,OriginalThread;
        public int Downs,Ups,Moves,EscapeDowns,EscapeUps,CaptureChanges;
        public bool Dragging,Finished,Cancelled,Cleaning,Restored,SkippedRestore,ForegroundGranted,CaptureVerified,Registered;
        public Point Start,End; public readonly Dictionary<string,object> Report = new Dictionary<string,object>();
    }
    static void Need(bool value,string message) { if(!value)throw new InvalidOperationException("ACTIVE_EXPERIMENT: "+message); }
    static string Id(IntPtr value) { return "0x"+value.ToInt64().ToString("X"); }
    static bool OwnSource(Source source,IntPtr window) { uint pid;return IsWindow(window)&&GetWindowThreadProcessId(window,out pid)==source.Thread&&pid==source.Pid&&(window==source.Ah||window==source.Bh); }
    static bool KnownForeground(Source source,CaseState state) { IntPtr fg=GetForegroundWindow();return OwnSource(source,fg)||(state!=null&&state.Planes.Contains(fg)); }
    static IntPtr NativeCapture(uint thread) { GUI info=new GUI();info.size=(uint)Marshal.SizeOf(typeof(GUI));Need(GetGUIThreadInfo(thread,ref info),"Cannot query the generated UI thread capture.");return info.capture; }
    static IntPtr WndProc(IntPtr window,uint message,IntPtr wp,IntPtr lp) {
        CaseState state=current;
        try {
            if(message==0x0084)return new IntPtr(1);
            if(message==0x0021)return new IntPtr(3);
            if(message==0x0014)return new IntPtr(1);
            if(message==0x000F){Paint paint;BeginPaint(window,out paint);EndPaint(window,ref paint);return IntPtr.Zero;}
            if(state==null)return DefWindowProc(window,message,wp,lp);
            if(message==0x0215&&!state.Cleaning)state.CaptureChanges++;
            if((message==0x0100||message==0x0101)&&wp.ToInt32()==0x1b){
                if(message==0x0100){state.EscapeDowns++;state.Cancelled=true;state.Dragging=false;}
                else {state.EscapeUps++;state.Finished=true;}
                return IntPtr.Zero;
            }
            if(message>=0x0200&&message<=0x020E){
                if(state.Cleaning)return IntPtr.Zero;
                if(message==0x0200||message==0x0201||message==0x0202){
                    long packed=lp.ToInt64();Point point=new Point(unchecked((short)(packed&0xffff)),unchecked((short)((packed>>16)&0xffff)));
                    if(!ClientToScreen(window,ref point)){state.Failure="Own pointer conversion failed.";return IntPtr.Zero;}
                    if(message==0x0201){state.Downs++;if(!state.Finished&&!state.Dragging){state.Start=point;state.End=point;state.Dragging=true;}}
                    else if(message==0x0202){state.Ups++;if(state.Dragging){state.End=point;state.Dragging=false;state.Finished=true;}}
                    else {state.Moves++;if(state.Dragging)state.End=point;}
                }
                return IntPtr.Zero;
            }
        }catch { if(state!=null)state.Failure="The owned input callback failed.";return IntPtr.Zero; }
        return DefWindowProc(window,message,wp,lp);
    }
    static void CreatePlanes(CaseState state) {
        bool composition;Need(DwmIsCompositionEnabled(out composition)==0&&composition,"Desktop composition is unavailable.");
        state.Instance=GetModuleHandle(null);state.Class="EchoLingoActiveCaptureExperiment-"+Process.GetCurrentProcess().Id+"-"+(++epoch);
        WindowClass cls=new WindowClass();cls.size=(uint)Marshal.SizeOf(typeof(WindowClass));cls.instance=state.Instance;cls.name=state.Class;cls.procedure=Marshal.GetFunctionPointerForDelegate(callback);
        Need(RegisterClassEx(ref cls)!=0,"Own input class registration failed.");
        state.Registered=true;
        foreach(Screen display in Screen.AllScreens){Rectangle r=display.Bounds;uint ex=0x00200000|0x08000000|0x80|8;
            IntPtr window=CreateWindowEx(ex,state.Class,"",0x80000000,r.X,r.Y,r.Width,r.Height,IntPtr.Zero,IntPtr.Zero,state.Instance,IntPtr.Zero);
            Need(window!=IntPtr.Zero,"Own input HWND creation failed.");state.Planes.Add(window);
            Need(SetWindowPos(window,new IntPtr(-1),r.X,r.Y,r.Width,r.Height,0x10|0x200|0x40),"Own input HWND show failed.");
            long actual=GetWindowLongPtr(window,-20).ToInt64();Need((actual&ex)==ex&&(actual&(0x80000|0x20))==0,"Own input styles differ from raw NoRedirection/NoActivate/Topmost.");
        }
    }
    static void Acquire(Source source,CaseState state) {
        Need(GetForegroundWindow()==source.Ah,"Generated A is not the foreground owner; refusing to acquire focus.");
        state.Original=source.Ah;state.OriginalPid=source.Pid;state.OriginalThread=source.Thread;
        state.Report["foregroundPermissionSource"]="The generated source and picker are the same already-foreground process on different UI threads; no permission grant/elevation used.";
        state.Report["sourceCaptureBeforeActivation"]=Id(NativeCapture(source.Thread));
        CreatePlanes(state);
        state.Active=state.Planes.Find(delegate(IntPtr window){return GetAncestor(WindowFromPoint(source.First),2)==window;});
        Need(state.Active!=IntPtr.Zero,"No exact owned input plane covers the generated source.");
        Need(SetForegroundWindow(state.Active)&&GetForegroundWindow()==state.Active,"Actual foreground acquisition was denied.");state.ForegroundGranted=true;
        SetFocus(state.Active);Need(GetFocus()==state.Active,"Actual owned keyboard focus was not established.");
        state.Report["sourceCaptureAfterActivation"]=Id(NativeCapture(source.Thread));
        SetCapture(state.Active);Need(GetCapture()==state.Active&&NativeCapture(GetCurrentThreadId())==state.Active,"Actual owned native capture was not established.");state.CaptureVerified=true;
        state.Report["sourceCaptureAfterOwnCapture"]=Id(NativeCapture(source.Thread));
        state.Report["actualOwnedForegroundVerified"]=true;state.Report["actualOwnedCaptureVerified"]=true;
    }
    static void Cleanup(Source source,CaseState state) {
        state.Cleaning=true;
        string failure=null;
        IntPtr before=GetForegroundWindow();bool stillOwned=state.Planes.Contains(before);
        uint pid;bool originalValid=IsWindow(state.Original)&&GetWindowThreadProcessId(state.Original,out pid)==state.OriginalThread&&pid==state.OriginalPid;
        if(state.Planes.Contains(GetCapture())&&!ReleaseCapture())failure="Own native capture could not be released.";
        // A user-selected generated B must win. No restore unless our picker
        // still owns foreground immediately before this single attempt.
        if(stillOwned&&originalValid&&state.Planes.Contains(GetForegroundWindow())){
            state.Restored=SetForegroundWindow(state.Original)&&GetForegroundWindow()==state.Original;
            if(!state.Restored)failure="The exact original source focus could not be restored.";
        }else state.SkippedRestore=true;
        foreach(IntPtr window in state.Planes)if(IsWindow(window)&&!DestroyWindow(window))failure="Own input HWND cleanup failed.";
        int remaining=0;foreach(IntPtr window in state.Planes)if(IsWindow(window))remaining++;
        if(remaining!=0)failure="Own input HWND survived cleanup.";
        if(state.Registered){if(!UnregisterClass(state.Class,state.Instance))failure="Own input class cleanup failed.";else state.Registered=false;}
        state.Report["originalIdentityMatchedAtCleanup"]=originalValid;state.Report["foregroundWasOwnedBeforeCleanup"]=stillOwned;
        state.Report["originalSourceRestored"]=state.Restored;state.Report["restoreSkippedForNewForeground"]=state.SkippedRestore;
        state.Report["inputPlaneRemainingAfterCleanup"]=remaining;
        GC.KeepAlive(callback);
        Need(failure==null,failure);
    }
    static INPUT Mouse(uint flags) { INPUT value=new INPUT();value.data.mouse.flags=flags;return value; }
    static INPUT Move(Point point) { Rectangle desktop=SystemInformation.VirtualScreen;INPUT value=Mouse(0x8000|0x4000|1);value.data.mouse.x=(int)Math.Round((point.X-desktop.Left)*65535.0/(desktop.Width-1));value.data.mouse.y=(int)Math.Round((point.Y-desktop.Top)*65535.0/(desktop.Height-1));return value; }
    static void Input(Source source,CaseState state,Point point,INPUT[] values) {
        Need(KnownForeground(source,state)&&source.Bounds.Contains(point),"Input left the generated foreground/content; no input sent.");
        IntPtr hit=GetAncestor(WindowFromPoint(point),2);Need(OwnSource(source,hit)||state.Planes.Contains(hit),"Pointer target left the exact generated source/plane HWNDs.");
        Need(SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)))==values.Length,"Windows rejected the own generated input.");
    }
    static void Escape(Source source,CaseState state) {
        Need(state.Planes.Contains(GetForegroundWindow()),"Refused Escape outside the actual owned picker.");
        INPUT down=new INPUT();down.type=1;down.data.key.vk=0x1b;INPUT up=down;up.data.key.flags=2;
        Input(source,state,source.First,new INPUT[] { down,up });
    }
    static void Until(Func<bool> condition,string message,int timeout) { Stopwatch watch=Stopwatch.StartNew();do{if(condition())return;Thread.Sleep(10);}while(watch.ElapsedMilliseconds<timeout);throw new InvalidOperationException("ACTIVE_EXPERIMENT: "+message); }
    static Dictionary<string,object> RunCase(Control dispatch,Source source,string mode) {
        CaseState state=new CaseState();state.Report["mode"]=mode;state.Report["ok"]=false;bool leftHeld=false,cleaned=false;
        try {
            source.A.Invoke((Action)delegate{
                source.Raising.Stop();if(GetCapture()==source.Ah||GetCapture()==source.Bh)ReleaseCapture();
                source.A.TopMost=false;source.B.TopMost=false;source.A.Activate();SetForegroundWindow(source.Ah);
                Interlocked.Exchange(ref source.Downs,0);Interlocked.Exchange(ref source.Ups,0);Interlocked.Exchange(ref source.Clicks,0);Interlocked.Exchange(ref source.Escapes,0);Interlocked.Exchange(ref source.Raises,0);
                if(mode=="foreign-capture-takeover-cross-peer") {SetCapture(source.Ah);Need(GetCapture()==source.Ah,"Generated source could not obtain pre-existing capture.");}
            });
            Need(GetForegroundWindow()==source.Ah,"Could not prepare generated A foreground.");
            dispatch.Invoke((Action)delegate {current=state;Acquire(source,state);});
            Need(state.ForegroundGranted&&state.CaptureVerified,"Foreground/capture were not verified.");
            if(mode=="escape-restores-matched-source"){
                Escape(source,state);Until(delegate{return state.EscapeUps>0;},"Owned Escape up was not received.",3000);
                Need(state.Cancelled&&state.EscapeDowns==1&&source.Escapes==0,"Escape did not remain inside the owned picker.");
            }else if(mode=="new-generated-foreground-wins"){
                source.B.Invoke((Action)delegate {source.B.Activate();Need(SetForegroundWindow(source.Bh)&&GetForegroundWindow()==source.Bh,"Generated B could not become the explicit new foreground.");});
                Need(GetForegroundWindow()==source.Bh,"Generated B foreground was not retained.");
            }else{
                if(mode=="repeated-topmost-immediate-cross-peer")source.A.Invoke((Action)delegate{
                    source.Raising.Start();Need(SetWindowPos(source.Ah,new IntPtr(-1),0,0,0,0,0x10|1|2),"Own topmost adversary could not raise.");source.Raises++;
                    Need(GetAncestor(WindowFromPoint(source.First),2)==source.Ah,"The topmost adversary is not actually above the input plane; case inconclusive.");
                });
                Need(state.Planes.Contains(GetForegroundWindow()),"Owned foreground was lost before the first generated down.");
                dispatch.Invoke((Action)delegate {Need(GetCapture()==state.Active,"Owned capture was lost before the first generated down.");});
                state.Report["pointerRootBeforeDown"]=Id(GetAncestor(WindowFromPoint(source.First),2));
                Input(source,state,source.First,new INPUT[] {Move(source.First),Mouse(2)});leftHeld=true;
                Thread.Sleep(900);
                Input(source,state,source.Last,new INPUT[] {Move(source.Last),Mouse(4)});leftHeld=false;
                Thread.Sleep(100);source.A.Invoke((Action)delegate {source.Raising.Stop();Application.DoEvents();});
                state.Report["topmostRaiseCount"]=source.Raises;
                state.Report["actualSelectedPhysicalRectangle"]=new int[]{state.Start.X,state.Start.Y,state.End.X-state.Start.X,state.End.Y-state.Start.Y};
                state.Report["planeDowns"]=state.Downs;state.Report["planeUps"]=state.Ups;state.Report["planeMoves"]=state.Moves;
                state.Report["underlyingMouseDowns"]=source.Downs;state.Report["underlyingMouseUps"]=source.Ups;state.Report["underlyingButtonClicks"]=source.Clicks;
                Need(source.Downs==0&&source.Ups==0&&source.Clicks==0,"UNDERLYING_INPUT: The generated source received real input despite actual owned foreground/native capture.");
                dispatch.Invoke((Action)delegate {Need(state.Failure==null&&state.Finished&&!state.Cancelled&&state.Downs==1&&state.Ups==1&&state.Start==source.First&&state.End==source.Last,"Actual owned plane did not complete the exact cross-peer drag.");});
                Need(state.Planes.Contains(GetForegroundWindow()),"Source stole foreground during the owned drag.");
            }
            dispatch.Invoke((Action)delegate {Cleanup(source,state);});cleaned=true;
            if(mode=="new-generated-foreground-wins")Need(state.SkippedRestore&&!state.Restored&&GetForegroundWindow()==source.Bh,"Cleanup stole focus back from generated B.");
            else Need(state.Restored&&GetForegroundWindow()==source.Ah,"Matched original source was not restored.");
            if(mode=="repeated-topmost-immediate-cross-peer")Need(source.Raises>=2,"Repeated topmost adversary was not exercised.");
            state.Report["ok"]=true;
        }catch(Exception error){state.Report["error"]=error.Message;}
        finally{
            if(leftHeld&&KnownForeground(source,state))try{Input(source,state,source.Last,new INPUT[]{Mouse(4)});}catch{}
            try{source.A.Invoke((Action)delegate {source.Raising.Stop();if(GetCapture()==source.Ah||GetCapture()==source.Bh)ReleaseCapture();Application.DoEvents();});}catch{}
            if(!cleaned)try{dispatch.Invoke((Action)delegate {Cleanup(source,state);});}catch{state.Report["cleanupError"]="Owned experiment input cleanup failed.";state.Report["ok"]=false;}
            state.Report["planeDowns"]=state.Downs;state.Report["planeUps"]=state.Ups;state.Report["planeMoves"]=state.Moves;
            state.Report["escapeDowns"]=state.EscapeDowns;state.Report["escapeUps"]=state.EscapeUps;state.Report["unexpectedCaptureChanges"]=state.CaptureChanges;
            state.Report["underlyingMouseDowns"]=source.Downs;state.Report["underlyingMouseUps"]=source.Ups;state.Report["underlyingButtonClicks"]=source.Clicks;state.Report["underlyingEscapeEvents"]=source.Escapes;
        }
        return state.Report;
    }
    public static Dictionary<string,object> Run() {
        Need(IntPtr.Size==8,"Use x64 Windows for this experiment.");SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Controller physical DPI context failed.");
        Source source=new Source();Thread sourceUi=new Thread(delegate(){
            try{
                Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Source physical DPI context failed.");
                using(Form a=new Form())using(Form b=new Form())using(Button ba=new Button())using(Button bb=new Button())using(System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer()){
                    source.A=a;source.B=b;source.Raising=timer;a.Text="EchoLingo active-capture generated A";b.Text="EchoLingo active-capture generated B";
                    a.StartPosition=b.StartPosition=FormStartPosition.Manual;a.FormBorderStyle=b.FormBorderStyle=FormBorderStyle.None;a.AutoScaleMode=b.AutoScaleMode=AutoScaleMode.None;a.KeyPreview=b.KeyPreview=true;
                    Rectangle work=Screen.PrimaryScreen.WorkingArea;Need(work.Width>=900&&work.Height>=500,"Generated A/B need900x500 work area.");
                    a.Bounds=new Rectangle(work.X+60,work.Y+60,340,280);b.Bounds=new Rectangle(a.Right,a.Top,340,280);a.BackColor=Color.FromArgb(50,175,95);b.BackColor=Color.FromArgb(180,65,140);
                    ba.Bounds=bb.Bounds=new Rectangle(30,50,200,70);ba.Text="Generated A button";bb.Text="Generated B button";ba.FlatStyle=bb.FlatStyle=FlatStyle.Flat;
                    foreach(Form form in new Form[]{a,b}){form.MouseDown+=delegate{Interlocked.Increment(ref source.Downs);};form.MouseUp+=delegate{Interlocked.Increment(ref source.Ups);};form.KeyDown+=delegate(object sender,KeyEventArgs e){if(e.KeyCode==Keys.Escape)Interlocked.Increment(ref source.Escapes);};form.KeyUp+=delegate(object sender,KeyEventArgs e){if(e.KeyCode==Keys.Escape)Interlocked.Increment(ref source.Escapes);};}
                    foreach(Button button in new Button[]{ba,bb}){button.MouseDown+=delegate{Interlocked.Increment(ref source.Downs);};button.MouseUp+=delegate{Interlocked.Increment(ref source.Ups);};button.Click+=delegate{Interlocked.Increment(ref source.Clicks);};}
                    a.Controls.Add(ba);b.Controls.Add(bb);timer.Interval=16;timer.Tick+=delegate{if(SetWindowPos(a.Handle,new IntPtr(-1),0,0,0,0,0x10|1|2))Interlocked.Increment(ref source.Raises);};
                    b.Show();a.Show();a.Activate();SetForegroundWindow(a.Handle);source.Ah=a.Handle;source.Bh=b.Handle;source.Thread=GetCurrentThreadId();GetWindowThreadProcessId(source.Ah,out source.Pid);
                    Need(GetWindow(source.Ah,4)==IntPtr.Zero&&GetWindow(source.Bh,4)==IntPtr.Zero,"Generated A/B must be independent ownerless windows.");
                    source.Bounds=Rectangle.Union(a.Bounds,b.Bounds);source.First=a.PointToScreen(new Point(65,75));source.Last=b.PointToScreen(new Point(100,180));source.Ready.Set();Application.Run(a);
                }
            }catch(Exception error){source.Failure=error.Message;source.Ready.Set();}
        });sourceUi.IsBackground=true;sourceUi.SetApartmentState(ApartmentState.STA);sourceUi.Start();
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();string fatal=null;Thread worker=null;
        using(Control dispatch=new Control())using(ApplicationContext context=new ApplicationContext()){
            IntPtr force=dispatch.Handle;
            worker=new Thread(delegate(){try{
                Need(source.Ready.WaitOne(10000)&&source.Failure==null,"Generated source setup failed: "+source.Failure);
                uint controllerPid;uint controllerThread=GetWindowThreadProcessId(force,out controllerPid);
                Need(source.Thread!=GetCurrentThreadId()&&source.Thread!=controllerThread&&controllerPid==source.Pid&&source.Pid==(uint)Process.GetCurrentProcess().Id,"Generated source/plane identity or independent UI threads changed.");
                foreach(string mode in new string[]{"foreign-capture-takeover-cross-peer","repeated-topmost-immediate-cross-peer","escape-restores-matched-source","new-generated-foreground-wins"})cases.Add(RunCase(dispatch,source,mode));
            }catch(Exception error){fatal=error.Message;}finally{
                if(source.A!=null&&!source.A.IsDisposed)try{source.A.Invoke((Action)delegate{source.Raising.Stop();if(GetCapture()==source.Ah||GetCapture()==source.Bh)ReleaseCapture();source.B.Close();source.A.Close();});}catch{fatal="Generated source cleanup failed.";}
                dispatch.BeginInvoke((Action)delegate{context.ExitThread();});
            }});worker.IsBackground=true;worker.SetApartmentState(ApartmentState.STA);worker.Start();Application.Run(context);Need(worker.Join(5000),"Own experiment worker did not stop.");
        }
        Need(sourceUi.Join(5000),"Own generated source UI thread did not stop.");source.Ready.Dispose();
        bool ok=fatal==null&&cases.Count==4;foreach(Dictionary<string,object> result in cases)ok=ok&&(bool)result["ok"];
        return new Dictionary<string,object>{{"ok",ok},{"experimental",true},{"cases",cases},{"fatalError",fatal},{"globalMouseHookInstalled",false},{"globalKeyboardHookInstalled",false},{"sourceAndPlaneSameProcess",true},{"independentSourceUiThread",true},{"tauriBackgroundHelperForegroundGrantTested",false},{"rawInputSuppressionTested",false},{"physicalWindows11Tested",false},{"userContentCaptured",false},{"clipboardAccessed",false},{"screenshotCaptured",false},{"privilegeOrSecurityPolicyChanged",false},{"scope","Isolated generated A/B only. Active foreground/capture compatibility experiment; no production changes, universal input guarantee or Tauri child foreground permission claim."}};
    }
}
'@
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([System.Windows.Forms.Form].Assembly.Location,[System.Drawing.Bitmap].Assembly.Location)
    $result = [EchoLingoActiveCaptureExperiment]::Run()
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 12 -Compress))
    if (-not $result.ok) { exit 1 }
} catch {
    [Console]::Out.WriteLine((@{ok=$false;experimental=$true;error=$_.Exception.Message;userContentCaptured=$false;clipboardAccessed=$false;privilegeOrSecurityPolicyChanged=$false}|ConvertTo-Json -Compress))
    exit 1
}
