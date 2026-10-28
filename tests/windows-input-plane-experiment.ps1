# Experimental input-only HWND, never production/native fallback. Run only on
# an unlocked disposable Windows desktop. Captures generated opaque A/B only.
[CmdletBinding()]
param([switch]$IsolatedTestSession)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) {
        throw 'EXPERIMENT_SESSION: Use an explicitly isolated unlocked Windows test desktop.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'EXPERIMENT_APARTMENT: Use Windows PowerShell5.1 -STA.' }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
public static class EchoLingoInputPlaneExperiment {
    delegate IntPtr WindowProc(IntPtr window, uint message, IntPtr wp, IntPtr lp);
    static readonly WindowProc callback = WndProc;
    static readonly List<IntPtr> planes = new List<IntPtr>();
    static string className, messageFailure;
    static IntPtr instance;
    static int downs, ups, moves;
    static bool dragging;
    static Point origin, end;
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x,y; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int l,t,r,b; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WNDCLASS {
        public uint size, style; public IntPtr procedure; public int classBytes, windowBytes;
        public IntPtr instance, icon, cursor, background; public string menu, name; public IntPtr smallIcon;
    }
    [StructLayout(LayoutKind.Sequential)] struct PAINT { public IntPtr dc; public int erase; public RECT rectangle; public int restore, update; [MarshalAs(UnmanagedType.ByValArray,SizeConst=32)] public byte[] reserved; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct DATA { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public DATA data; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern ushort RegisterClassEx(ref WNDCLASS value);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool UnregisterClass(string name,IntPtr module);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr module,IntPtr parameter);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr DefWindowProc(IntPtr window,uint message,IntPtr wp,IntPtr lp);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern IntPtr BeginPaint(IntPtr window,out PAINT paint);
    [DllImport("user32.dll")] static extern bool EndPaint(IntPtr window,ref PAINT paint);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref POINT point);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] input,int size);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out POINT point);
    [DllImport("dwmapi.dll")] static extern int DwmIsCompositionEnabled([MarshalAs(UnmanagedType.Bool)] out bool enabled);
    [DllImport("dwmapi.dll")] static extern int DwmFlush();
    static void Require(bool value,string error) { if(!value)throw new InvalidOperationException("INPUT_PLANE: "+error); }
    static POINT Native(Point value) { POINT p=new POINT();p.x=value.X;p.y=value.Y;return p; }
    static IntPtr Root(Point point) { return GetAncestor(WindowFromPoint(Native(point)),2); }
    static bool Own(IntPtr window) { uint owner;GetWindowThreadProcessId(window,out owner);return window!=IntPtr.Zero&&owner==Process.GetCurrentProcess().Id; }
    static IntPtr WndProc(IntPtr window,uint message,IntPtr wp,IntPtr lp) {
        try {
            if(message==0x0084)return new IntPtr(1); // HTCLIENT: rectangular input remains intentional.
            if(message==0x0021)return new IntPtr(3); // MA_NOACTIVATE: deliver click, retain source foreground.
            if(message==0x0014)return new IntPtr(1); // No GDI background/brush/surface.
            if(message==0x000F){PAINT paint;BeginPaint(window,out paint);EndPaint(window,ref paint);return IntPtr.Zero;}
            if(message==0x0200||message==0x0201||message==0x0202){
                long packed=lp.ToInt64();POINT pointer=new POINT();pointer.x=unchecked((short)(packed&0xffff));pointer.y=unchecked((short)((packed>>16)&0xffff));
                if(!ClientToScreen(window,ref pointer)){messageFailure="ClientToScreen failed.";return IntPtr.Zero;}
                Point at=new Point(pointer.x,pointer.y);
                if(message==0x0201){downs++;origin=at;dragging=true;}
                else if(message==0x0202){ups++;end=at;dragging=false;}
                else {moves++;if(dragging)end=at;}
                return IntPtr.Zero; // Do not forward any selected button/move to the source.
            }
        }catch{messageFailure="The input HWND callback failed.";return IntPtr.Zero;}
        return DefWindowProc(window,message,wp,lp);
    }
    static void CreatePlanes() {
        bool composition;Require(DwmIsCompositionEnabled(out composition)==0&&composition,"DWM composition is unavailable.");
        instance=GetModuleHandle(null);className="EchoLingoInputPlaneExperiment-"+Process.GetCurrentProcess().Id;
        WNDCLASS cls=new WNDCLASS();cls.size=(uint)Marshal.SizeOf(typeof(WNDCLASS));cls.instance=instance;
        cls.name=className;cls.procedure=Marshal.GetFunctionPointerForDelegate(callback);cls.background=IntPtr.Zero;
        Require(RegisterClassEx(ref cls)!=0,"Cannot register the isolated input class.");
        foreach(Screen screen in Screen.AllScreens){Rectangle r=screen.Bounds;
            // No layered/transparent style, bitmap, DComp surface or swap chain.
            uint ex=0x00200000|0x08000000|0x00000080|0x00000008;
            IntPtr plane=CreateWindowEx(ex,className,"",0x80000000,r.X,r.Y,r.Width,r.Height,IntPtr.Zero,IntPtr.Zero,instance,IntPtr.Zero);
            Require(plane!=IntPtr.Zero,"Cannot create the input-only HWND.");planes.Add(plane);
            Require(SetWindowPos(plane,new IntPtr(-1),r.X,r.Y,r.Width,r.Height,0x0010|0x0200|0x0040),"Cannot show the input HWND without activation.");
            long actual=GetWindowLongPtr(plane,-20).ToInt64();
            Require((actual&ex)==ex&&(actual&(0x00080000|0x00000020))==0,"Input HWND styles differ from NoRedirection/NoActivate/Topmost.");
        }
        Require(DwmFlush()==0,"Cannot observe the committed transparent desktop.");
    }
    static void RemovePlanes() { foreach(IntPtr plane in planes)if(IsWindow(plane))Require(DestroyWindow(plane),"Cannot destroy an input HWND.");planes.Clear(); }
    static void Guard(IntPtr source,Point point,bool inputPlane) {
        Require(GetForegroundWindow()==source&&Own(source),"Foreground left the exact generated A; refusing input.");
        IntPtr hit=Root(point);Require(Own(hit)&&(inputPlane?planes.Contains(hit):hit==source),"Point no longer belongs to the expected generated input target.");
    }
    static void SendMouse(IntPtr source,Point point,uint flags,bool plane) {
        Guard(source,point,plane);INPUT value=new INPUT();
        if(flags==1){Rectangle desktop=SystemInformation.VirtualScreen;value.data.mouse.x=(int)Math.Round((point.X-desktop.Left)*65535.0/(desktop.Width-1));value.data.mouse.y=(int)Math.Round((point.Y-desktop.Top)*65535.0/(desktop.Height-1));flags=0x8000|0x4000|1;}
        value.data.mouse.flags=flags;Require(SendInput(1,new INPUT[]{value},Marshal.SizeOf(typeof(INPUT)))==1,"Windows rejected own generated mouse input.");
    }
    static void Escape(IntPtr source) {
        Require(GetForegroundWindow()==source&&Own(source),"Refusing Escape outside exact generated A.");
        INPUT down=new INPUT();down.type=1;down.data.key.vk=0x1B;INPUT up=down;up.data.key.flags=2;
        Require(SendInput(2,new INPUT[]{down,up},Marshal.SizeOf(typeof(INPUT)))==2,"Windows rejected generated Escape.");
    }
    static Bitmap ReadGenerated(Rectangle area) { Bitmap image=new Bitmap(area.Width,area.Height);using(Graphics graphics=Graphics.FromImage(image))graphics.CopyFromScreen(area.Location,Point.Empty,area.Size,CopyPixelOperation.SourceCopy);return image; }
    static int Difference(Bitmap before,Bitmap after,out int maximum) {int count=0;maximum=0;for(int y=0;y<before.Height;y++)for(int x=0;x<before.Width;x++){Color a=before.GetPixel(x,y),b=after.GetPixel(x,y);int delta=Math.Max(Math.Abs(a.R-b.R),Math.Max(Math.Abs(a.G-b.G),Math.Abs(a.B-b.B)));if(delta>0)count++;maximum=Math.Max(maximum,delta);}return count;}
    public static Dictionary<string,object> Run() {
        SetProcessDpiAwarenessContext(new IntPtr(-4));Require(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Cannot set physical DPI context.");
        Require(IntPtr.Size==8,"Use the x64 Windows experimental fixture.");
        Dictionary<string,object> report=new Dictionary<string,object>();report["ok"]=false;report["experimental"]=true;
        report["globalMouseHookInstalled"]=false;report["directCompositionObjectsCreated"]=false;report["redirectionSurfaceRequested"]=false;
        report["productionFallbackImplemented"]=false;report["physicalWindows11Tested"]=false;report["vendorHookBypassTested"]=false;report["sourceAndPlaneSameProcess"]=true;
        report["multiMonitorDragTested"]=false;report["layeredWindowCreated"]=false;
        report["sourceScreenshotsRetained"]=false;report["userContentCaptured"]=false;report["clipboardAccessed"]=false;
        report["scope"]="Generated A/B and raw NoRedirectionBitmap input HWNDs only; no production fallback or physical Windows11 acceptance.";
        using(Form a=new Form())using(Form b=new Form()){
            a.Text="EchoLingo input-plane generated A";b.Text="EchoLingo input-plane generated B";
            a.FormBorderStyle=b.FormBorderStyle=FormBorderStyle.None;a.AutoScaleMode=b.AutoScaleMode=AutoScaleMode.None;
            a.StartPosition=b.StartPosition=FormStartPosition.Manual;a.TopMost=b.TopMost=false;b.ShowInTaskbar=false;a.KeyPreview=true;
            Rectangle area=Screen.PrimaryScreen.WorkingArea;Require(area.Width>=720&&area.Height>=360,"Need a720x360 generated work area.");
            a.Bounds=new Rectangle(area.X+40,area.Y+40,320,240);b.Bounds=new Rectangle(a.Left+280,a.Top,320,240);
            a.BackColor=Color.FromArgb(220,70,85);b.BackColor=Color.FromArgb(40,180,90);
            Button buttonA=new Button(),buttonB=new Button();buttonA.Text="Generated A";buttonB.Text="Generated B";
            buttonA.Bounds=new Rectangle(25,45,75,35);buttonB.Bounds=new Rectangle(185,165,75,35);
            foreach(Button button in new Button[]{buttonA,buttonB}){button.FlatStyle=FlatStyle.Flat;button.UseVisualStyleBackColor=false;button.BackColor=Color.FromArgb(230,150,40);button.ForeColor=Color.Black;}
            a.Controls.Add(buttonA);b.Controls.Add(buttonB);int sourceMouse=0,clickA=0,clickB=0;bool escaped=false,finished=false;
            MouseEventHandler observe=delegate{sourceMouse++;};a.MouseDown+=observe;a.MouseUp+=observe;b.MouseDown+=observe;b.MouseUp+=observe;buttonA.MouseDown+=observe;buttonA.MouseUp+=observe;buttonB.MouseDown+=observe;buttonB.MouseUp+=observe;
            buttonA.Click+=delegate{clickA++;};buttonB.Click+=delegate{clickB++;};
            a.KeyDown+=delegate(object sender,KeyEventArgs e){if(e.KeyCode==Keys.Escape){e.Handled=true;e.SuppressKeyPress=true;try{RemovePlanes();escaped=true;}catch{messageFailure="Escape cleanup failed.";}}};
            a.FormClosing+=delegate(object sender,FormClosingEventArgs e){if(!finished)e.Cancel=true;};
            Thread worker=null;
            a.Shown+=delegate{
                b.Show();a.Activate();SetForegroundWindow(a.Handle);
                worker=new Thread(delegate(){bool leftHeld=false;POINT saved;bool restore=GetPhysicalCursorPos(out saved);
                    try{
                        Require(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Worker physical DPI setup failed.");
                        Point first=Point.Empty,last=Point.Empty,safe=Point.Empty;Rectangle generated=Rectangle.Empty;IntPtr source=IntPtr.Zero,peer=IntPtr.Zero;
                        a.Invoke((Action)delegate{source=a.Handle;peer=b.Handle;first=a.PointToScreen(new Point(40,60));last=b.PointToScreen(new Point(200,180));safe=a.PointToScreen(new Point(200,200));generated=Rectangle.Union(a.Bounds,b.Bounds);});
                        Require(Root(first)==source&&Root(last)==peer&&Own(peer),"A/B endpoints are not independently generated source windows.");
                        SendMouse(source,safe,1,false);Thread.Sleep(100);DwmFlush();
                        using(Bitmap baseline=ReadGenerated(generated)){
                            a.Invoke((Action)CreatePlanes);Require(GetForegroundWindow()==source,"Input HWND activation changed the source foreground.");
                            Thread.Sleep(100);DwmFlush();
                            using(Bitmap transparent=ReadGenerated(generated)){int maximum;int changed=Difference(baseline,transparent,out maximum);report["pixelComparisonWidth"]=baseline.Width;report["pixelComparisonHeight"]=baseline.Height;report["changedGeneratedPixels"]=changed;report["maximumRgbDifference"]=maximum;Require(maximum<=1,"Input HWND visibly dimmed/painted/froze the generated sources.");}
                        }
                        Guard(source,first,true);Guard(source,last,true);report["inputPlaneCount"]=planes.Count;
                        report["sourceAHwnd"]="0x"+source.ToInt64().ToString("X");report["sourceBHwnd"]="0x"+peer.ToInt64().ToString("X");report["sourceAndPlaneProcessId"]=Process.GetCurrentProcess().Id;
                        report["startPhysicalPoint"]=new int[]{first.X,first.Y};report["endPhysicalPoint"]=new int[]{last.X,last.Y};
                        SendMouse(source,first,1,true);Thread.Sleep(50);SendMouse(source,first,2,true);leftHeld=true;Thread.Sleep(80);
                        for(int step=1;step<=20;step++){Point point=new Point(first.X+(last.X-first.X)*step/20,first.Y+(last.Y-first.Y)*step/20);SendMouse(source,point,1,true);Thread.Sleep(10);}
                        Thread.Sleep(900);
                        a.Invoke((Action)delegate{Require(downs==1&&ups==0&&dragging&&origin==first&&messageFailure==null,"The transparent input HWND did not own the exact drag start/held state.");});
                        SendMouse(source,last,4,true);leftHeld=false;Thread.Sleep(100);
                        a.Invoke((Action)delegate{Require(downs==1&&ups==1&&!dragging&&end==last&&moves>0&&messageFailure==null,"The input HWND did not receive exact cross-peer release/movement.");Require(sourceMouse==0&&clickA==0&&clickB==0,"Drag input reached underlying generated buttons.");report["planeMouseDowns"]=downs;report["planeMouseUps"]=ups;report["planeMouseMoves"]=moves;report["underlyingMouseEventsDuringPlane"]=sourceMouse;});
                        a.Invoke((Action)delegate{a.BackColor=Color.FromArgb(65,100,180);b.BackColor=Color.FromArgb(180,65,150);a.Refresh();b.Refresh();});DwmFlush();
                        using(Bitmap live=ReadGenerated(generated)){Color x=live.GetPixel(10,220),y=live.GetPixel(live.Width-10,10);Require(Math.Abs(x.R-65)<=1&&Math.Abs(x.G-100)<=1&&Math.Abs(x.B-180)<=1&&Math.Abs(y.R-180)<=1&&Math.Abs(y.G-65)<=1&&Math.Abs(y.B-150)<=1,"Generated source updates did not remain live through the empty input plane.");}
                        Escape(source);Thread.Sleep(100);
                        a.Invoke((Action)delegate{Require(escaped&&planes.Count==0,"Generated Escape did not remove the input plane.");});
                        SendMouse(source,first,1,false);Thread.Sleep(50);SendMouse(source,first,2,false);SendMouse(source,first,4,false);Thread.Sleep(100);
                        a.Invoke((Action)delegate{Require(clickA==1&&clickB==0&&sourceMouse==2,"Normal generated button input was not restored after cancellation.");});
                        Require(GetForegroundWindow()==source,"Source foreground changed during the experiment.");
                        report["crossPeerDragPassed"]=true;report["foregroundPreserved"]=true;report["transparentPixelsPassed"]=true;report["liveGeneratedContentPassed"]=true;report["escapeCleanupPassed"]=true;report["normalClickAfterCleanupPassed"]=true;
                        report["heldDragMilliseconds"]=900;report["noBitmapOrSwapChainCreatedForInputPlane"]=true;report["ok"]=true;
                    }catch(Exception error){report["error"]=error.Message;report["messageFailure"]=messageFailure;}
                    finally{
                        try{if(leftHeld&&Own(GetForegroundWindow())){INPUT up=new INPUT();up.data.mouse.flags=4;SendInput(1,new INPUT[]{up},Marshal.SizeOf(typeof(INPUT)));}}catch{}
                        a.Invoke((Action)delegate{
                            try{RemovePlanes();}catch{report["ok"]=false;report["cleanupError"]="Input HWND cleanup failed.";}
                            if(className!=null&&!UnregisterClass(className,instance)){report["ok"]=false;report["cleanupError"]="Input HWND class cleanup failed.";}
                            // Restore only into these generated A/B windows;
                            // never move the pointer onto another application's content.
                            Point previous=new Point(saved.x,saved.y);IntPtr previousRoot=restore?Root(previous):IntPtr.Zero;
                            if(restore&&GetForegroundWindow()==a.Handle&&(previousRoot==a.Handle||previousRoot==b.Handle)&&Own(previousRoot)){
                                INPUT move=new INPUT();Rectangle desktop=SystemInformation.VirtualScreen;move.data.mouse.x=(int)Math.Round((saved.x-desktop.X)*65535.0/(desktop.Width-1));move.data.mouse.y=(int)Math.Round((saved.y-desktop.Y)*65535.0/(desktop.Height-1));move.data.mouse.flags=0x8000|0x4000|1;
                                if(SendInput(1,new INPUT[]{move},Marshal.SizeOf(typeof(INPUT)))!=1){report["ok"]=false;report["cleanupError"]="Own pointer restoration failed.";}
                            }
                            finished=true;b.Close();a.Close();
                        });
                    }
                });worker.SetApartmentState(ApartmentState.STA);worker.Start();
            };
            Application.Run(a);if(worker!=null)worker.Join(3000);
        }
        return report;
    }
}
'@
    $references = @([System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location)
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references
    $result = [EchoLingoInputPlaneExperiment]::Run()
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 8 -Compress))
    if (-not $result.ok) { exit 1 }
} catch {
    [Console]::Out.WriteLine((@{ok=$false; experimental=$true; error=$_.Exception.Message; userContentCaptured=$false; clipboardAccessed=$false} | ConvertTo-Json -Compress))
    exit 1
}
