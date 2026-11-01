# F1-only generated-window acceptance. Never run against a user's active desktop.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$NativeCapturePath,
      [Parameter(Mandatory=$true)][string]$HarnessPath, [switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -and -not $env:GITHUB_ACTIONS) { throw 'ISOLATION_REQUIRED: Use an explicitly isolated generated-window session.' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) { throw 'DESKTOP_UNAVAILABLE: An unlocked Windows test desktop is required.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'TEST_APARTMENT: Use powershell.exe -STA.' }
    $NativeCapturePath=(Resolve-Path -LiteralPath $NativeCapturePath).Path
    $HarnessPath=(Resolve-Path -LiteralPath $HarnessPath).Path
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web.Extensions
    # Reuse exact source-window/host cleanup and input ownership observers; do
    # not replace or relax the separate 16-case native magnifier/region gate.
    $fixture=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'windows-native-capture-smoke.ps1')
    $match=[regex]::Match($fixture, '(?s)\$source = @''\r?\n(.*?)\r?\n''@')
    if(-not $match.Success){throw 'FIXTURE_SOURCE_REQUIRED: Native fixture source could not be located.'}
    $source=$match.Groups[1].Value
    if(-not $source.Contains('input.WriteLine("capture")')){throw 'FIXTURE_LIFECYCLE_REQUIRED'}
    $source=$source.Replace('input.WriteLine("capture")','input.WriteLine("screenshot")')
    # Screenshot adds hidden adjustment decorations; preserve the Region fixture
    # verbatim and account for the exact extra inventory only in this derived gate.
    $inventory='int allocated=0,loupes=0;bool loupeNear=false,pixelsReady=false;'
    $edges='long edges=0x08000000L|0x80000L|0x20L;'
    $exact='bool exact=thin.Count==8 && allocated==12*Screen.AllScreens.Length;'
    foreach($marker in @($inventory,$edges,$exact)){if(($source.Split([string[]]@($marker),[StringSplitOptions]::None).Length-1)-ne 1){throw 'SCREENSHOT_READINESS_SOURCE_REQUIRED'}}
    $source=$source.Replace($inventory,$inventory+'Dictionary<string,int> screenshotRoles=new Dictionary<string,int>();')
    $source=$source.Replace($edges,'string role=ScreenshotRole(window,helper);if(role!=null){Need(!IsWindowVisible(window),"Adjustment role appeared before selection.");screenshotRoles[role]=screenshotRoles.ContainsKey(role)?screenshotRoles[role]+1:1;return true;}'+$edges)
    $source=$source.Replace($exact,'bool exact=thin.Count==8 && allocated==12*Screen.AllScreens.Length && ScreenshotInventory(screenshotRoles);')
    $extra=@'
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowDisplayAffinity(IntPtr window,uint affinity);
    [DllImport("user32.dll",SetLastError=true)] static extern bool GetWindowDisplayAffinity(IntPtr window,out uint affinity);
    static readonly string[] ScreenshotActions={"select","rectangle","arrow","text","number","pen","highlight","mosaic","solid","crop","copy","save","pin","cancel"};
    static string ScreenshotRole(IntPtr window,int helper) {
        Need(Class(window)=="EchoLingoNativeCapture-"+helper,"Screenshot role has an unexpected native class.");
        StringBuilder title=new StringBuilder(128);GetWindowText(window,title,title.Capacity);string text=title.ToString();
        if(text=="EchoLingoCaptureResizeHandle")return "handle";
        if(text=="EchoLingoCaptureAdjustmentHint")return "hint";
        foreach(string action in ScreenshotActions)if(text=="EchoLingoCaptureAction:"+action)return action;
        Need(text.Length==0||text=="EchoLingoCaptureMagnifier","Unknown titled screenshot role.");return null;
    }
    static bool ScreenshotInventory(Dictionary<string,int> roles) {
        if(roles.Count!=16)return false;
        foreach(string action in ScreenshotActions)if(!roles.ContainsKey(action)||roles[action]!=1)return false;
        return roles.ContainsKey("handle")&&roles["handle"]==8&&roles.ContainsKey("hint")&&roles["hint"]==1;
    }
    static void ScreenshotChooseSelect(int helper,Sources source,Rectangle expected,Dictionary<string,object> report) {
        Stopwatch time=Stopwatch.StartNew();IntPtr button=IntPtr.Zero;bool ready=false;
        while(time.ElapsedMilliseconds<10000&&Alive(helper)) {
            Need(GetForegroundWindow()==source.AH&&Frame(source.AH)==source.AFrame,"Source changed before native screenshot action.");
            Dictionary<string,int> roles=new Dictionary<string,int>();List<Point> handles=new List<Point>();
            EnumWindows(delegate(IntPtr window,IntPtr unused){uint pid;GetWindowThreadProcessId(window,out pid);if(pid!=helper||!IsWindowVisible(window))return true;
                string role=ScreenshotRole(window,helper);if(role==null)return true;
                long required=0x08000000L|0x80000L|0x20L|0x80L|8;
                Need((GetWindowLongPtr(window,-20).ToInt64()&required)==required,"Screenshot adjustment role lost native passive styles.");
                Rectangle bounds=Bounds(window);Need(bounds.Width>0&&bounds.Height>0&&bounds.Width<=(role=="hint"?3808:(role=="handle"?64:512))&&bounds.Height<=(role=="hint"?864:(role=="handle"?64:240)),"Screenshot adjustment role has invalid bounds.");
                if(role!="handle")Need(Screen.FromHandle(window).WorkingArea.Contains(bounds),"Screenshot toolbar escaped its monitor work area.");
                roles[role]=roles.ContainsKey(role)?roles[role]+1:1;
                if(role=="handle")handles.Add(new Point(bounds.Left+bounds.Width/2,bounds.Top+bounds.Height/2));
                if(role=="select")button=window;return true;
            },IntPtr.Zero);
            if(ScreenshotInventory(roles)&&handles.Count==8) {
                HashSet<Point> wanted=new HashSet<Point>(new Point[]{new Point(expected.Left,expected.Top),new Point(expected.Left+expected.Width/2,expected.Top),new Point(expected.Right,expected.Top),new Point(expected.Right,expected.Top+expected.Height/2),new Point(expected.Right,expected.Bottom),new Point(expected.Left+expected.Width/2,expected.Bottom),new Point(expected.Left,expected.Bottom),new Point(expected.Left,expected.Top+expected.Height/2)});
                ready=wanted.SetEquals(handles);if(ready)break;
            }
            Thread.Sleep(10);
        }
        Need(ready&&Alive(helper)&&button!=IntPtr.Zero,"Screenshot release did not remain in exact eight-handle adjustment with complete native toolbar.");
        Rectangle action=Bounds(button);Point point=new Point(action.Left+action.Width/2,action.Top+action.Height/2);
        Send(new INPUT[]{Move(point)});
        Need(GetForegroundWindow()==source.AH&&Alive(helper)&&IsWindowVisible(button)&&ScreenshotRole(button,helper)=="select"&&Bounds(button).Contains(point),"Native select target changed before input.");
        IntPtr target=GetAncestor(WindowFromPoint(point),2);uint owner;GetWindowThreadProcessId(target,out owner);
        Need(owner==helper&&Class(target)=="EchoLingoNativeCapture-"+helper&&IsWindowVisible(target),"Native select input would target a foreign window.");
        Send(new INPUT[]{Mouse(2),Mouse(4)});
        Need(GetForegroundWindow()==source.AH,"Native select action activated another window.");report["nativeActionSourceForegroundPreserved"]=true;
        report["nativeAdjustmentObserved"]=true;report["nativeAdjustmentHandleCount"]=8;report["nativeAdjustmentHintVisible"]=true;
        report["nativeInitialAction"]="select";report["nativeActionClickCount"]=1;report["nativeActionOwnedTargetVerified"]=true;
    }
    static void ScreenshotPressed(int helper) {
        Stopwatch time=Stopwatch.StartNew();
        // The idle window hint disappears after the exact down was processed;
        // only one display outline, the loupe and all input planes remain.
        while(time.ElapsedMilliseconds<3000&&Alive(helper)&&VisibleOwnedWindows(helper)!=Screen.AllScreens.Length+5)Thread.Sleep(10);
        Need(Alive(helper)&&VisibleOwnedWindows(helper)==Screen.AllScreens.Length+5,"F1 down did not become a pressed gesture before the adversarial change.");
    }
    static Dictionary<string,object> ScreenshotCase(Host host,string kind) {
        Dictionary<string,object> report=new Dictionary<string,object>{{"mode",kind},{"ok",false}};
        Sources source=null; bool finished=false,hidden=false,protectedWindow=false;
        try {
            source=new Sources(report);
            if(kind=="protected-target-fails-closed") {
                source.OnUi(delegate { source.A.Opacity=0.99; });
                uint initialAffinity;Need(GetWindowDisplayAffinity(source.AH,out initialAffinity)&&initialAffinity==0,"Generated layered source did not expose a known initially unprotected affinity.");
            }
            if(kind=="visible-overlap-stays-in-image") {
                source.OnUi(delegate {
                    source.B.Bounds=new Rectangle(source.AFrame.Right-100,source.AFrame.Bottom-100,180,180);
                    Need(SetWindowPos(source.BH,new IntPtr(-1),0,0,0,0,0x10|1|2),"Generated overlap did not enter z-order.");
                });
                Need(GetForegroundWindow()==source.AH,"Overlap setup changed source foreground.");
            }
            int helper=host.Begin();report["generation"]=host.Generation;
            Dictionary<string,object> observation=new Dictionary<string,object>();
            Stopwatch time=Stopwatch.StartNew(); bool ready=false;
            while(time.ElapsedMilliseconds<25000&&Alive(helper)) {
                if(Ready(helper,source.AH,source.AFrame,source.Display,source.First,observation)){ready=true;break;}
                Thread.Sleep(10);
            }
            Need(ready,"F1 did not show the exact stable window hover outline and owned input surfaces.");
            report["hoverWindowOutlineVerified"]=true;
            Point end=source.First; Rectangle expected=source.AFrame;
            bool rejected=kind=="moved-target-fails-closed"||kind=="hidden-target-fails-closed"||kind=="protected-target-fails-closed"||kind=="drag-out-and-back-is-not-click"||kind=="escape-cancels";
            if(kind=="escape-cancels") Escape(source.AH);
            else {
                source.Partial=true;Send(new INPUT[]{Move(source.First),Mouse(2)});
                if(kind=="moved-target-fails-closed"||kind=="hidden-target-fails-closed"||kind=="protected-target-fails-closed") {
                    ScreenshotPressed(helper);
                    source.OnUi(delegate {
                        if(kind=="moved-target-fails-closed") source.A.Left+=12;
                        if(kind=="hidden-target-fails-closed") {source.A.Hide();hidden=true;}
                        if(kind=="protected-target-fails-closed") {
                            Need(SetWindowDisplayAffinity(source.AH,0x11),"Generated window could not set capture exclusion.");protectedWindow=true;
                            uint affinity;Need(GetWindowDisplayAffinity(source.AH,out affinity)&&affinity==0x11,"Generated exclusion was not observable; protected-case evidence is unavailable.");
                        }
                    });
                } else if(kind=="click-small-jitter") {end.Offset(2,1);Send(new INPUT[]{Move(end)});}
                else if(kind=="drag-rectangle-wins") {
                    end.Offset(80,60);expected=new Rectangle(source.First.X,source.First.Y,80,60);Send(new INPUT[]{Move(end)});
                } else if(kind=="drag-out-and-back-is-not-click") {
                    Point far=source.First;far.Offset(80,60);
                    // Both moves can be coalesced into one UI frame. The host's
                    // scalar maximum must still prevent an accidental click.
                    INPUT away=Move(far),back=Move(source.First);
                    away.data.mouse.flags|=0x2000;back.data.mouse.flags|=0x2000;
                    Send(new INPUT[]{away,back});
                }
                Send(new INPUT[]{Move(end),Mouse(4)});source.Partial=false;
            }
            if(!rejected)ScreenshotChooseSelect(helper,source,expected,report);
            Dictionary<string,object> reply=host.Finish(report,12000);finished=true;
            Need(!reply.ContainsKey("text"),"F1 capture unexpectedly returned OCR text.");
            Need(reply.ContainsKey("nativeBackend")&&Convert.ToString(reply["nativeBackend"])=="rust-win32-capture","F1 did not use the exact Rust native capture backend.");
            Need(reply.ContainsKey("captureHealth")&&reply["captureHealth"] is Dictionary<string,object>,"F1 native capture health is missing.");
            Dictionary<string,object> health=(Dictionary<string,object>)reply["captureHealth"];
            foreach(string key in new string[]{"nativeCaptureBackend","nativeHostReady","nativeHostArmed","nativeHostStopped"})
                Need(health.ContainsKey(key)&&Convert.ToInt64(health[key])==1,"F1 native lifecycle evidence is missing: "+key);
            foreach(string key in new string[]{"inputPlaneRemainingAfterCleanup","inputPlaneVisibleCount","hookRunningAfterStop"})
                Need(health.ContainsKey(key)&&Convert.ToInt64(health[key])==0,"F1 native cleanup left resources: "+key);
            if(rejected) {
                Need(!(bool)reply["ok"]&&!reply.ContainsKey("imageBase64"),"Invalid/stale F1 target produced pixels.");
                string error=Convert.ToString(reply["error"]);
                Need(error.StartsWith(kind.EndsWith("fails-closed",StringComparison.Ordinal)?"CAPTURE_WINDOW_CHANGED:":"CANCELLED:",StringComparison.Ordinal),"F1 failed for an unrelated native error.");
            } else {
                Need((bool)reply["ok"],"F1 capture failed.");
                Need(reply.ContainsKey("initialAction")&&Convert.ToString(reply["initialAction"])=="select","F1 result lost the chosen native action.");
                ((Dictionary<string,object>)report["helperDiagnostics"])["initialAction"]=reply["initialAction"];
                using(MemoryStream bytes=new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))using(Bitmap image=new Bitmap(bytes)) {
                    Need(image.Width==expected.Width&&image.Height==expected.Height,"F1 captured dimensions differ from the exact visible DWM frame/drag rectangle.");
                    for(int y=0;y<image.Height;y++)for(int x=0;x<image.Width;x++) {
                        Color c=image.GetPixel(x,y);Need(!(Math.Abs(c.R-45)<=2&&Math.Abs(c.G-145)<=2&&Math.Abs(c.B-255)<=2),"F1 blue selector outline leaked into the final PNG.");
                    }
                    if(kind=="visible-overlap-stays-in-image") {
                        Color visible=image.GetPixel(image.Width-70,image.Height-70);
                        Need(Math.Abs(visible.R-190)<=2&&Math.Abs(visible.G-70)<=2&&Math.Abs(visible.B-130)<=2,"F1 must preserve the visible overlapping window; hidden underlying content was returned.");
                    }
                    report["imageWidth"]=image.Width;report["imageHeight"]=image.Height;
                }
            }
            source.Drain();Need(source.Downs==0&&source.Ups==0&&source.Clicks==0,"F1 leaked a generated mouse pair/click to the underlying source.");
            Need(!Alive(helper),"F1 child remained alive after its closed reply.");
            report["zeroUnderlyingInput"]=true;report["ok"]=true;
        }catch(Exception error){report["error"]=error.Message;}
        finally {
            if(source!=null) {
                if(source.Partial){try{Send(new INPUT[]{Mouse(4)});}catch{}source.Partial=false;}
                if(protectedWindow||hidden)try{source.OnUi(delegate{if(protectedWindow)SetWindowDisplayAffinity(source.AH,0);if(hidden)source.A.Show();});}catch{}
                if(host.Child!=0&&host.Usable&&!finished)try{if(GetForegroundWindow()==source.AH)Escape(source.AH);host.Finish(report,12000);}catch{host.Usable=false;}
                try{source.Dispose();}catch(Exception cleanup){report["ok"]=false;report["cleanupError"]=cleanup.Message;}
            }
        }
        return report;
    }
    public static Dictionary<string,object> RunScreenshot(string helper,string harness) {
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Screenshot fixture DPI context failed.");
        List<object> cases=new List<object>(); bool ok=true;
        Dictionary<string,object> stopped=null;string shutdownError=null;int startedGenerations=0;bool hostExitedNormally=false;
        using(Host host=new Host(harness,helper)) {
            foreach(string kind in new string[]{"click-visible-window","click-small-jitter","drag-rectangle-wins","drag-out-and-back-is-not-click","moved-target-fails-closed","hidden-target-fails-closed","protected-target-fails-closed","visible-overlap-stays-in-image","escape-cancels","next-request-after-cancel"}) {
                Dictionary<string,object> result=ScreenshotCase(host,kind);cases.Add(result);ok=ok&&(bool)result["ok"];
                if(!host.Usable||host.Child!=0||host.Process.HasExited)break;
            }
            startedGenerations=host.Generation;
            if(host.Child==0&&!host.Process.HasExited) {
                try {
                    host.Shutdown();stopped=host.Read(4000);
                    Need((string)stopped["event"]=="stopped"&&Convert.ToInt32(stopped["completedGenerations"])==cases.Count&&host.Generation==cases.Count,"F1 generation cleanup mismatch.");
                    Need(host.Process.WaitForExit(4000)&&host.Process.ExitCode==0,"F1 host did not exit cleanly.");hostExitedNormally=true;
                } catch(Exception error) {ok=false;shutdownError=error.Message;}
            } else {ok=false;shutdownError="F1 host did not reach an idle normal shutdown.";}
        }
        return new Dictionary<string,object>{{"ok",ok&&cases.Count==10},{"cases",cases},{"hostShutdown",stopped},{"hostShutdownError",shutdownError},{"hostExitedNormally",hostExitedNormally},{"startedGenerations",startedGenerations},{"screenshotPurpose",true},{"productionModulesImported",true},{"userContentCaptured",false},{"clipboardAccessed",false},{"ocrInvoked",false},{"scope","Generated isolated Windows desktop only; actual F1 global shortcut/editor integration and physical multi-display acceptance are separate gates."}};
    }
'@
    $closing=$source.LastIndexOf("`n}")
    if($closing -lt 0){throw 'FIXTURE_CLASS_END_REQUIRED'}
    $source=$source.Insert($closing,"`n"+$extra)
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([System.Windows.Forms.Form].Assembly.Location,[System.Drawing.Bitmap].Assembly.Location,[System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    $result=[EchoLingoNativeCaptureSmoke]::RunScreenshot($NativeCapturePath,$HarnessPath)
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 14 -Compress))
    if(-not $result.ok){exit 1}
} catch {
    [Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message;userContentCaptured=$false;clipboardAccessed=$false}|ConvertTo-Json -Compress));exit 1
}
