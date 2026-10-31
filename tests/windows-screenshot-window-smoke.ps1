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
    $extra=@'
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowDisplayAffinity(IntPtr window,uint affinity);
    [DllImport("user32.dll",SetLastError=true)] static extern bool GetWindowDisplayAffinity(IntPtr window,out uint affinity);
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
            source=new Sources();
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
