// Isolated, generated browser page only. No process-wide source selection or
// clipboard reads occur until the spawned browser HWND and focused root match.
using System;
using System.Collections.Generic;
using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

public static class WindowsBrowserSelectionBridge {
    delegate bool EnumWindow(IntPtr window,IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out RECT rectangle);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
    [StructLayout(LayoutKind.Sequential)] struct RECT {public int Left,Top,Right,Bottom;}
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr window,IntPtr dc,uint flags);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int capacity);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,INPUT[] input,int size);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid id,uint flags,IntPtr token,out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr memory);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string path,IntPtr security);
    [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort key,scan;public uint flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Explicit)] struct INPUTDATA {[FieldOffset(0)]public KEY key;[FieldOffset(0)]public MOUSE mouse;}
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public INPUTDATA data;}
    [StructLayout(LayoutKind.Sequential)] struct POINT {public int x,y;}
    [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=1048576 };
    static string Helper,Assembly,Browser;
    static uint ownedClipboard;
    static bool seeded;
    static string Stage="setup";static Dictionary<string,object> LastMetadata;
    static AppSession HostedApplication;
    static string ShortcutGesture="instant";
    static IntPtr boundMain,boundOwner;static int boundPid;static uint boundThread;static long boundStyleKind;
    static List<Dictionary<string,object>> windowInventory=new List<Dictionary<string,object>>();
    static void Need(bool value,string error){if(!value)throw new InvalidOperationException(error);}
    static void Reply(object value){Console.WriteLine(Json.Serialize(value));Console.Out.Flush();}
    static string WindowId(IntPtr window){return "0x"+window.ToInt64().ToString("X");}
    static IntPtr BrowserMain(int pid){
        using(Process process=Process.GetProcessById(pid))Need(String.Equals(Path.GetFullPath(process.MainModule.FileName),Browser,StringComparison.OrdinalIgnoreCase),"BROWSER_IDENTITY_MISMATCH");
        List<IntPtr> windows=new List<IntPtr>();windowInventory=new List<Dictionary<string,object>>();
        EnumWindows(delegate(IntPtr window,IntPtr unused){
            uint owner;uint thread=GetWindowThreadProcessId(window,out owner);if(owner!=pid)return true;
            StringBuilder name=new StringBuilder(256);GetClassName(window,name,name.Capacity);
            if(name.ToString()!="Chrome_WidgetWin_1")return true;
            RECT r;bool hasRect=GetWindowRect(window,out r);bool root=GetAncestor(window,2)==window,visible=IsWindowVisible(window);
            windowInventory.Add(new Dictionary<string,object>{{"hwnd",WindowId(window)},{"pid",owner},{"threadId",thread},{"class",name.ToString()},{"root",root},{"visible",visible},{"ownerHwnd",WindowId(GetWindow(window,4))},{"foreground",GetForegroundWindow()==window},{"style",GetWindowLongPtr(window,-16).ToInt64()},{"extendedStyle",GetWindowLongPtr(window,-20).ToInt64()},{"bounds",hasRect?(object)new int[]{r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top}:null}});
            if(root&&visible)windows.Add(window);return true;
        },IntPtr.Zero);
        if(boundMain==IntPtr.Zero){
            Need(windows.Count==1,"BROWSER_ROOT_NOT_UNIQUE");boundMain=windows[0];boundPid=pid;uint originalPid;boundThread=GetWindowThreadProcessId(boundMain,out originalPid);Need(originalPid==pid,"BROWSER_INITIAL_ROOT_PID_CHANGED");boundOwner=GetWindow(boundMain,4);boundStyleKind=GetWindowLongPtr(boundMain,-16).ToInt64()&0xC0C00000L;
        }
        uint actualPid;uint actualThread=GetWindowThreadProcessId(boundMain,out actualPid);StringBuilder actualClass=new StringBuilder(256);GetClassName(boundMain,actualClass,actualClass.Capacity);
        Need(boundPid==pid&&IsWindow(boundMain)&&actualPid==pid&&actualThread==boundThread&&actualClass.ToString()=="Chrome_WidgetWin_1"&&GetAncestor(boundMain,2)==boundMain&&IsWindowVisible(boundMain)&&GetWindow(boundMain,4)==boundOwner&&(GetWindowLongPtr(boundMain,-16).ToInt64()&0xC0C00000L)==boundStyleKind,"BROWSER_BOUND_ROOT_IDENTITY_CHANGED");
        return boundMain;
    }
    sealed class AuditTrace {
        readonly object gate=new object();readonly Stopwatch time=Stopwatch.StartNew();
        readonly Dictionary<string,object> points=new Dictionary<string,object>();readonly List<double[]> parents=new List<double[]>();
        public void Mark(string stage,int depth){lock(gate){points["lastStage"]=stage;points["lastDepth"]=depth;points[stage+"AtMilliseconds"]=time.Elapsed.TotalMilliseconds;if(stage=="parentQueryStart")parents.Add(new double[]{depth,time.Elapsed.TotalMilliseconds,-1});if(stage=="parentQueryDone"&&parents.Count>0)parents[parents.Count-1][2]=time.Elapsed.TotalMilliseconds;}}
        public void Worker(){lock(gate){points["workerThreadId"]=Thread.CurrentThread.ManagedThreadId;points["workerApartment"]=Thread.CurrentThread.GetApartmentState().ToString();}Mark("workerEntered",0);}
        public Dictionary<string,object> Snapshot(){lock(gate){Dictionary<string,object> copy=new Dictionary<string,object>(points);copy["elapsedMilliseconds"]=time.Elapsed.TotalMilliseconds;copy["deadlineMilliseconds"]=2000;copy["parentQueryDepthStartEndMilliseconds"]=parents.ConvertAll(delegate(double[] value){return (double[])value.Clone();});return copy;}}
    }
    static Dictionary<string,object> FocusMetadata(IntPtr main,int browserPid,bool protectedExpected,AuditTrace trace){
        Need(GetForegroundWindow()==main,"BROWSER_NOT_FOREGROUND");trace.Mark("queued",0);
        Task<Dictionary<string,object>> query=Task.Factory.StartNew(delegate{
            trace.Worker();Need(Thread.CurrentThread.GetApartmentState()==ApartmentState.MTA,"BROWSER_UIA_WORKER_NOT_MTA");
            CacheRequest cache=new CacheRequest();cache.TreeScope=TreeScope.Element;cache.AutomationElementMode=AutomationElementMode.Full;
            cache.Add(AutomationElement.ControlTypeProperty);cache.Add(AutomationElement.ProcessIdProperty);cache.Add(AutomationElement.NativeWindowHandleProperty);cache.Add(AutomationElement.IsPasswordProperty);
            trace.Mark("focusedElementStart",0);AutomationElement focus=AutomationElement.FocusedElement;trace.Mark("focusedElementDone",0);Need(focus!=null,"BROWSER_UIA_FOCUS_MISSING");
            trace.Mark("focusCacheStart",0);focus=focus.GetUpdatedCache(cache);trace.Mark("focusCacheDone",0);
            trace.Mark("runtimeIdStart",0);int[] runtime=focus.GetRuntimeId();trace.Mark("runtimeIdDone",0);
            Dictionary<string,object> result=new Dictionary<string,object>{{"focusedRole",focus.Cached.ControlType.ProgrammaticName},{"focusedProcessId",focus.Cached.ProcessId},{"focusedIsPassword",focus.Cached.IsPassword},{"runtimeIdPresent",runtime!=null&&runtime.Length>0}};
            List<int> sourcePids=new List<int>();bool matched=false,password=false;int depth=0;AutomationElement current=focus;
            while(current!=null&&depth<64){
                trace.Mark("ancestorCacheRead",depth);AutomationElement.AutomationElementInformation info=current.Cached;password=password||info.IsPassword;
                int pid=info.ProcessId;if(pid!=0&&!sourcePids.Contains(pid))sourcePids.Add(pid);
                int handle=info.NativeWindowHandle;if(handle!=0){Need(GetAncestor(new IntPtr(handle),2)==main,"BROWSER_UIA_FOCUS_ROOT_MISMATCH");if(new IntPtr(handle)==main){matched=true;break;}}
                trace.Mark("parentQueryStart",depth);current=TreeWalker.RawViewWalker.GetParent(current,cache);trace.Mark("parentQueryDone",depth);depth++;
            }
            Need(matched,"BROWSER_UIA_ROOT_UNVERIFIED");Need(protectedExpected?password:!password,"BROWSER_PASSWORD_METADATA_MISMATCH");
            trace.Mark("rootVerified",depth);result["ancestorProcessIds"]=sourcePids;result["ancestorDepth"]=depth;result["foregroundBrowserProcessId"]=browserPid;result["sourceRootVerified"]=true;result["ancestorPasswordPresent"]=password;trace.Mark("complete",depth);return result;
        },CancellationToken.None,TaskCreationOptions.DenyChildAttach,TaskScheduler.Default);
        Stopwatch deadline=Stopwatch.StartNew();
        // This fixture's STA owns an OLE clipboard HWND. Keep it responsive;
        // the provider query itself remains on the separate windowless MTA.
        while(!query.IsCompleted&&deadline.ElapsedMilliseconds<2000){Application.DoEvents();Thread.Sleep(2);}
        Need(query.IsCompleted,"BROWSER_UIA_METADATA_TIMEOUT");Need(GetForegroundWindow()==main,"BROWSER_FOREGROUND_CHANGED");if(query.IsFaulted)throw query.Exception.InnerException;return query.Result;
    }
    static DataObject Seed(){
        DataObject data=new DataObject();data.SetData(DataFormats.UnicodeText,false,"Generated browser clipboard original 24680");data.SetData(DataFormats.Html,false,"<p>Generated browser rich original 24680</p>");data.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated browser rich original 24680}");Clipboard.SetDataObject(data,true,0,0);ownedClipboard=GetClipboardSequenceNumber();seeded=true;return data;
    }
    static bool Restored(DataObject expected){IDataObject actual=Clipboard.GetDataObject();if(actual==null)return false;foreach(string format in expected.GetFormats(false))if(!Object.Equals(expected.GetData(format,false),actual.GetData(format,false)))return false;return true;}
    static Dictionary<string,object> QueryDiagnostics(Dictionary<string,object> reply){
        Dictionary<string,object> numeric=new Dictionary<string,object>();object raw;
        if(reply.TryGetValue("capturePerformance",out raw)){
            Dictionary<string,object> performance=raw as Dictionary<string,object>;
            if(performance!=null)for(int i=1;i<=16;i++)foreach(string suffix in new string[]{"Milliseconds","Stage","Depth","InitialRoleId","FreshRoleId","InitialIdentityLength","FreshIdentityLength","IdentityCompared","IdentityEqual","RootWalkReason","ExceptionKind","BudgetLimitMilliseconds","BudgetRemainingAtStartMilliseconds","BudgetElapsedAtOutcomeMilliseconds","DeadlineExceeded","DrainAttempted","DrainMilliseconds","DrainCancelled","DrainObservationError","WorkerCompletionObserved","WorkerCompletionObservedMilliseconds","WorkerStillBlocked","WorkerStageAtDrainEnd","WorkerExceptionKindAtDrainEnd"}){string key="selectionQuery"+i+suffix;object value;if(performance.TryGetValue(key,out value)){double number=Convert.ToDouble(value);Need(!Double.IsNaN(number)&&!Double.IsInfinity(number)&&number>=0&&number<=10000000,"SELECTION_DIAGNOSTIC_BOUND");numeric[key]=number;}}
        }
        if(reply.TryGetValue("helperPerformance",out raw)){
            Dictionary<string,object> phases=raw as Dictionary<string,object>;
            if(phases!=null)foreach(string key in new string[]{"assembliesLoadedMilliseconds","nativeTypesReadyMilliseconds","replyMilliseconds"}){object value;if(phases.TryGetValue(key,out value)){double number=Convert.ToDouble(value);Need(!Double.IsNaN(number)&&!Double.IsInfinity(number)&&number>=0&&number<=10000000,"HELPER_DIAGNOSTIC_BOUND");numeric[key]=number;}}
        }
        return numeric;
    }
    static Dictionary<string,object> RunCase(Dictionary<string,object> command){
        int pid=Convert.ToInt32(command["browserPid"]);string expected=Convert.ToString(command["expected"]),outcome=Convert.ToString(command["outcome"]),requiredRole=Convert.ToString(command["requiredRole"]);Need(expected.Length<=512,"GENERATED_EXPECTATION_TOO_LARGE");
        Need(outcome=="selection"||outcome=="empty"||outcome=="protected","GENERATED_OUTCOME_INVALID");
        Stage="native-identity";LastMetadata=new Dictionary<string,object>{{"ok",false},{"helperInvocations",0},{"safeToContinue",false},{"preHelperUiaCalls",0}};Dictionary<string,object> metadata=LastMetadata;
        windowInventory=new List<Dictionary<string,object>>();bool alreadyBound=boundMain!=IntPtr.Zero;IntPtr main=BrowserMain(pid);if(GetForegroundWindow()!=main)SetForegroundWindow(main);
        Stopwatch focus=Stopwatch.StartNew();while(GetForegroundWindow()!=main&&focus.ElapsedMilliseconds<1000)Thread.Sleep(10);Need(GetForegroundWindow()==main,"BROWSER_NOT_FOREGROUND");
        metadata["boundBrowserRootHwnd"]=WindowId(main);metadata["browserRootCandidates"]=windowInventory;metadata["sameVerifiedBrowserRootReused"]=alreadyBound;metadata["initialUniqueBrowserRootBinding"]=!alreadyBound;
        object requireReleased;if(command.TryGetValue("requireMouseReleased",out requireReleased)&&Convert.ToBoolean(requireReleased)){
            bool released=(GetAsyncKeyState(1)&0x8000)==0;metadata["mouseLeftReleasedBeforeHelper"]=released;Need(released,"BROWSER_MOUSE_LEFT_NOT_RELEASED_BEFORE_HELPER");
        }
        if(HostedApplication!=null)return RunApplicationCase(command,main,metadata);
        // No accessibility query precedes the helper: the first case measures
        // the real production client's cold UIA path, without a warm-up probe.
        Stage="clipboard-seed";DataObject seed=Seed();uint initial=ownedClipboard;string cancelName="Local\\EchoLingo-cancel-"+Guid.NewGuid().ToString("N");
        using(EventWaitHandle cancel=new EventWaitHandle(false,EventResetMode.ManualReset,cancelName)){
            ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell/v1.0/powershell.exe"));
            start.Arguments="-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \""+Helper+"\" -Mode selected-text -NativeAssemblyPath \""+Assembly+"\" -NativeCancellationEvent \""+cancelName+"\" -PerformanceDiagnostics";
            start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=new UTF8Encoding(false);
            HashSet<int> observedOwners=new HashSet<int>();HashSet<uint> observedGenerations=new HashSet<uint>();Stopwatch clock=Stopwatch.StartNew();Dictionary<string,object> reply;
            Stage="native-helper";using(Process helper=Process.Start(start)){
                metadata["helperInvocations"]=1;metadata["helperProcessId"]=helper.Id;
                Task<string> stdout=helper.StandardOutput.ReadToEndAsync(),stderr=helper.StandardError.ReadToEndAsync();
                try{
                    while(!helper.WaitForExit(2)){
                        Application.DoEvents();uint sequence=GetClipboardSequenceNumber();if(sequence!=initial){observedGenerations.Add(sequence);uint owner;GetWindowThreadProcessId(GetClipboardOwner(),out owner);if(owner!=0)observedOwners.Add((int)owner);}
                        Need(clock.ElapsedMilliseconds<12000,"BROWSER_HELPER_DEADLINE");
                    }
                    Need(Task.WaitAll(new Task[]{stdout,stderr},2000),"BROWSER_HELPER_PIPE_TIMEOUT");Need(stdout.Result.Length<262144&&stderr.Result.Length<65536,"BROWSER_HELPER_OUTPUT_BOUND");
                    reply=Json.Deserialize<Dictionary<string,object>>(stdout.Result.Trim('\ufeff',' ','\r','\n'));
                    metadata["selectionQueryDiagnostics"]=QueryDiagnostics(reply);
                    Need(reply.ContainsKey("nativeBackend")&&Convert.ToString(reply["nativeBackend"])=="precompiled-framework-dll","BROWSER_HELPER_EXACT_DLL_NOT_USED");
                    metadata["nativeBackend"]=reply["nativeBackend"];metadata["helperActualExitCode"]=helper.ExitCode;bool nativeOk=Convert.ToBoolean(reply["ok"]);Need(helper.ExitCode==(nativeOk?0:1),"BROWSER_HELPER_EXIT_MISMATCH");metadata["nativeHelperReportedOk"]=nativeOk;
                    string error=reply.ContainsKey("error")?Convert.ToString(reply["error"]):"",text=reply.ContainsKey("text")?Convert.ToString(reply["text"]):"";int split=error.IndexOf(':');
                    metadata["helperReplyErrorPrefix"]=error==""?null:split>=0?error.Substring(0,Math.Min(split,64)):"UNCLASSIFIED";metadata["helperReportedPerQueryDeadline"]=error.StartsWith("SELECTION:")&&error.Contains("did not answer in time");metadata["helperReportedSelectionBudgetDeadline"]=error.StartsWith("SELECTION:")&&error.Contains("accessibility budget was exhausted");metadata["helperReportedUiaDeadline"]=Convert.ToBoolean(metadata["helperReportedPerQueryDeadline"])||Convert.ToBoolean(metadata["helperReportedSelectionBudgetDeadline"]);
                    metadata["expectedTextLength"]=expected.Length;metadata["actualTextLength"]=text.Length;metadata["exactSelectedTextMatched"]=nativeOk&&text==expected;
                    bool expectedResult=outcome=="selection"?nativeOk&&text==expected:!nativeOk&&error.StartsWith(outcome=="protected"?"PROTECTED:":"NO_SELECTION:");metadata["acquisitionExpectationPassed"]=expectedResult;metadata["helperElapsedMilliseconds"]=clock.Elapsed.TotalMilliseconds;
                }finally{if(!helper.HasExited){cancel.Set();if(!helper.WaitForExit(2000)){helper.Kill();Need(helper.WaitForExit(2000),"OWN_BROWSER_HELPER_CLEANUP_FAILED");}}}
            }
            Stage="clipboard-check";Need(Restored(seed),"BROWSER_ORIGINAL_RICH_CLIPBOARD_NOT_RESTORED");ownedClipboard=GetClipboardSequenceNumber();Need(GetForegroundWindow()==main,"BROWSER_HELPER_CHANGED_FOREGROUND");Need(BrowserMain(pid)==main,"BROWSER_ROOT_CHANGED_AFTER_HELPER");
            metadata["richClipboardRestored"]=true;metadata["sourceForegroundPreserved"]=true;metadata["clipboardGenerationChanged"]=ownedClipboard!=initial;metadata["sampledClipboardOwnerProcessIds"]=new List<int>(observedOwners);metadata["sampledClipboardGenerationCount"]=observedGenerations.Count;metadata["clipboardOwnerPollMilliseconds"]=2;metadata["clipboardOwnerSamplingMayMissBriefOwnership"]=true;
            Stage="post-helper-uia-audit";AuditTrace trace=new AuditTrace();bool auditOk=false;
            try{Dictionary<string,object> audit=FocusMetadata(main,pid,outcome=="protected",trace);foreach(KeyValuePair<string,object> pair in audit)metadata[pair.Key]=pair.Value;
                string role=Convert.ToString(audit["focusedRole"]);Need(requiredRole==""||requiredRole==role,"BROWSER_ACTUAL_FOCUSED_ROLE_MISMATCH");auditOk=true;}
            catch(Exception error){while(error.InnerException!=null)error=error.InnerException;metadata["auditError"]=error.Message;metadata["auditErrorType"]=error.GetType().Name;}
            metadata["uiaAuditTrace"]=trace.Snapshot();metadata["postHelperAuditPassed"]=auditOk;if(metadata.ContainsKey("ancestorProcessIds"))metadata["sampledVerifiedSourceOwnerObserved"]=new List<int>(observedOwners).Exists(delegate(int owner){return ((List<int>)metadata["ancestorProcessIds"]).Contains(owner);});
            metadata["safeToContinue"]=auditOk&&GetForegroundWindow()==main;metadata["ok"]=Convert.ToBoolean(metadata["acquisitionExpectationPassed"])&&auditOk;
            metadata["failureClassification"]=Convert.ToBoolean(metadata["acquisitionExpectationPassed"])?auditOk?null:"post-helper-identity-audit":"native-acquisition";if(!Convert.ToBoolean(metadata["ok"]))metadata["error"]=!Convert.ToBoolean(metadata["acquisitionExpectationPassed"])?"NATIVE_ACQUISITION_EXPECTATION_FAILED":"POST_HELPER_AUDIT_FAILED";
            return metadata;
        }
    }
    static bool ClearOwnedClipboard(){
        if(!seeded)return true;bool owned=GetClipboardSequenceNumber()==ownedClipboard;seeded=false;
        if(!owned)return false;Clipboard.Clear();return true;
    }
    static Dictionary<string,object> GuardMouseStart(Dictionary<string,object> command){
        IntPtr root=BrowserMain(Convert.ToInt32(command["browserPid"]));Need(GetForegroundWindow()==root,"MOUSE_SOURCE_BROWSER_NOT_FOREGROUND");
        int x=(int)Math.Round(Convert.ToDouble(command["x"])),y=(int)Math.Round(Convert.ToDouble(command["y"]));Need(x>=-32768&&x<=32767&&y>=-32768&&y<=32767,"MOUSE_SOURCE_COORDINATE_BOUND");
        POINT p=new POINT();p.x=x;p.y=y;IntPtr hit=WindowFromPoint(p);uint pid;GetWindowThreadProcessId(hit,out pid);bool same=GetAncestor(hit,2)==root;
        Need(same,"NATIVE_MOUSE_START_HIT_NOT_OWN_BROWSER");POINT nearby=p;nearby.x++;Need(GetAncestor(WindowFromPoint(nearby),2)==root,"NATIVE_MOUSE_PROBE_NOT_OWN_BROWSER");Need(SetCursorPos(x+1,y)&&SetCursorPos(x,y),"NATIVE_MOUSE_POSITION_FAILED");
        return new Dictionary<string,object>{{"ok",same},{"mouseStartHitsBoundBrowserRoot",same},{"hitProcessId",pid},{"hitHwnd",WindowId(hit)},{"expectedBrowserRoot",WindowId(root)},{"preHelperUiaCalls",0}};
    }
    static Dictionary<string,object> DragMouseOnce(Dictionary<string,object> command){
        IntPtr root=BrowserMain(Convert.ToInt32(command["browserPid"]));Need(GetForegroundWindow()==root,"NATIVE_DRAG_BROWSER_NOT_FOREGROUND");
        int x=Convert.ToInt32(command["x"]),y=Convert.ToInt32(command["y"]),endX=Convert.ToInt32(command["endX"]),endY=Convert.ToInt32(command["endY"]);POINT p=new POINT();p.x=x;p.y=y;
        Need(GetAncestor(WindowFromPoint(p),2)==root&&(GetAsyncKeyState(1)&0x8000)==0,"NATIVE_DRAG_START_UNVERIFIED_OR_HELD");Need(Math.Abs(endX)<=32767&&Math.Abs(endY)<=32767,"NATIVE_DRAG_END_BOUND");
        INPUT down=new INPUT();down.type=0;down.data.mouse.flags=2;INPUT up=down;up.data.mouse.flags=4;uint sent=0;
        try{Need(SetCursorPos(x,y),"NATIVE_DRAG_POSITION_FAILED");sent=SendInput(1,new INPUT[]{down},Marshal.SizeOf(typeof(INPUT)));Need(sent==1,"NATIVE_DRAG_DOWN_REJECTED");for(int step=1;step<=8;step++){Need(GetForegroundWindow()==root,"NATIVE_DRAG_SOURCE_FOREGROUND_CHANGED");Need(SetCursorPos(x+(endX-x)*step/8,y+(endY-y)*step/8),"NATIVE_DRAG_MOVE_FAILED");Thread.Sleep(15);}int desktopLeft=GetSystemMetrics(76),desktopTop=GetSystemMetrics(77),desktopWidth=GetSystemMetrics(78),desktopHeight=GetSystemMetrics(79);Need(desktopWidth>1&&desktopHeight>1&&endX>=desktopLeft&&endX<desktopLeft+desktopWidth&&endY>=desktopTop&&endY<desktopTop+desktopHeight,"NATIVE_DRAG_END_OUTSIDE_DESKTOP");INPUT finalMove=new INPUT();finalMove.type=0;finalMove.data.mouse.flags=0x8000|0x4000|1;finalMove.data.mouse.x=(int)Math.Round((endX-desktopLeft)*65535.0/(desktopWidth-1));finalMove.data.mouse.y=(int)Math.Round((endY-desktopTop)*65535.0/(desktopHeight-1));Need(SendInput(2,new INPUT[]{finalMove,up},Marshal.SizeOf(typeof(INPUT)))==2,"NATIVE_DRAG_FINAL_MOVE_UP_REJECTED");sent=0;}
        finally{if(sent!=0)SendInput(1,new INPUT[]{up},Marshal.SizeOf(typeof(INPUT)));}
        Stopwatch release=Stopwatch.StartNew();while((GetAsyncKeyState(1)&0x8000)!=0&&release.ElapsedMilliseconds<1000)Thread.Sleep(2);Need((GetAsyncKeyState(1)&0x8000)==0,"NATIVE_DRAG_LEFT_RELEASE_NOT_OBSERVED");
        return new Dictionary<string,object>{{"ok",true},{"nativeMouseDragPairsSent",1},{"nativeMouseLeftReleased",true},{"mouseInputBackend","Win32 SendInput down/up + SetCursorPos moves"},{"preHelperUiaCalls",0}};
    }
    static Dictionary<string,object> OutsideClickOnce(Dictionary<string,object> command){
        Need(HostedApplication!=null&&HostedApplication.Visible,"OUTSIDE_CLICK_REQUIRES_PREVIOUS_VISIBLE_POPUP");IntPtr root=BrowserMain(Convert.ToInt32(command["browserPid"]));Need(GetForegroundWindow()==root,"OUTSIDE_CLICK_SOURCE_FOREGROUND_CHANGED");POINT point=new POINT();point.x=Convert.ToInt32(command["x"]);point.y=Convert.ToInt32(command["y"]);Need(GetAncestor(WindowFromPoint(point),2)==root&&(GetAsyncKeyState(1)&0x8000)==0,"OUTSIDE_CLICK_POINT_NOT_OWN_BROWSER_OR_MOUSE_HELD");
        INPUT down=new INPUT();down.type=0;down.data.mouse.flags=2;INPUT up=down;up.data.mouse.flags=4;Stopwatch watch=Stopwatch.StartNew();uint sent=SendInput(2,new INPUT[]{down,up},Marshal.SizeOf(typeof(INPUT)));if(sent!=2){if(sent>0)SendInput(1,new INPUT[]{up},Marshal.SizeOf(typeof(INPUT)));throw new InvalidOperationException("OUTSIDE_CLICK_INPUT_REJECTED_NO_RETRY");}
        while(watch.ElapsedMilliseconds<2000){Need(GetForegroundWindow()==root,"OUTSIDE_CLICK_CHANGED_BROWSER_FOREGROUND");if(!HostedApplication.Visible)return new Dictionary<string,object>{{"ok",true},{"outsideClickPairsSent",1},{"previousPopupVisibleBeforeClick",true},{"previousPopupHidden",true},{"sourceForegroundPreserved",true},{"hideObservedMilliseconds",watch.Elapsed.TotalMilliseconds}};Application.DoEvents();Thread.Sleep(5);}throw new InvalidOperationException("ONE_SAME_BROWSER_OUTSIDE_CLICK_DID_NOT_HIDE_POPUP");
    }
    sealed class AppSession {
        const string Identifier="io.github.blueeeecho.echolingo",Marker=".echolingo-browser-app-owned";
        readonly string token=Guid.NewGuid().ToString("N"),provider;readonly List<string> owned=new List<string>();
        readonly AutoResetEvent wake=new AutoResetEvent(false);readonly object uiGate=new object();Thread uiThread;Action pending;volatile bool uiStop,uiPoisoned;bool closed;
        Process app;IntPtr main;string history;Dictionary<string,object> cleanup;
        public readonly bool Diagnostics;
        public readonly Dictionary<string,object> Identity;
        static string Folder(string id){Guid guid=new Guid(id);IntPtr p;Need(SHGetKnownFolderPath(ref guid,0,IntPtr.Zero,out p)==0,"APP_KNOWN_FOLDER_FAILED");try{return Marshal.PtrToStringUni(p);}finally{CoTaskMemFree(p);}}
        void Claim(string p){Need(CreateDirectory(p,IntPtr.Zero),"EXISTING_APP_DATA_REFUSED");owned.Add(p);File.WriteAllText(Path.Combine(p,Marker),token,new UTF8Encoding(false));}
        void CheckRoot(string p){Need(Directory.Exists(p)&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(p,Marker))==token,"APP_DIRECTORY_OWNERSHIP_CHANGED");}
        void NoLinks(string p){Need((File.GetAttributes(p)&FileAttributes.ReparsePoint)==0,"APP_DATA_REPARSE_POINT");foreach(string child in Directory.GetFileSystemEntries(p)){try{Need((File.GetAttributes(child)&FileAttributes.ReparsePoint)==0,"APP_DATA_REPARSE_POINT");if(Directory.Exists(child))NoLinks(child);}catch(FileNotFoundException){if(File.Exists(child)||Directory.Exists(child))throw;}catch(DirectoryNotFoundException){if(File.Exists(child)||Directory.Exists(child))throw;}}}
        void DeleteOwn(string p){if(!Directory.Exists(p))return;CheckRoot(p);Stopwatch elapsed=Stopwatch.StartNew();bool deleting=false;while(true){try{Need((File.GetAttributes(p)&FileAttributes.ReparsePoint)==0,"APP_ROOT_REPARSE_POINT");NoLinks(p);deleting=true;Directory.Delete(p,true);return;}catch(IOException){if(!Directory.Exists(p))return;if(elapsed.ElapsedMilliseconds>=5000)throw;}catch(UnauthorizedAccessException){if(elapsed.ElapsedMilliseconds>=5000)throw;}if(!deleting)CheckRoot(p);Thread.Sleep((int)Math.Min(20,Math.Max(1,5000-elapsed.ElapsedMilliseconds)));}}
        IntPtr OwnMain(){List<IntPtr> found=new List<IntPtr>();EnumWindows(delegate(IntPtr w,IntPtr ignored){uint pid;GetWindowThreadProcessId(w,out pid);if(pid==app.Id&&GetAncestor(w,2)==w){StringBuilder c=new StringBuilder(128);GetClassName(w,c,c.Capacity);if(c.ToString()=="Tauri Window")found.Add(w);}return true;},IntPtr.Zero);Need(found.Count<=1,"APP_MAIN_NOT_UNIQUE");return found.Count==1?found[0]:IntPtr.Zero;}
        bool NativeReady(){int hotkeys=0,trays=0;EnumWindows(delegate(IntPtr w,IntPtr ignored){uint pid;GetWindowThreadProcessId(w,out pid);if(pid==app.Id){StringBuilder c=new StringBuilder(128);GetClassName(w,c,c.Capacity);if(c.ToString()=="global_hotkey_app")hotkeys++;if(c.ToString()=="tray_icon_app")trays++;}return true;},IntPtr.Zero);return hotkeys>0&&trays>0;}
        static void WaitNative(Func<bool> condition,int ms,string error){Stopwatch s=Stopwatch.StartNew();while(s.ElapsedMilliseconds<ms){if(condition())return;Thread.Sleep(10);}throw new InvalidOperationException(error);}
        public AppSession(string executable,string mockUrl,string providerId,string hash,long bytes,bool diagnostics){
            Diagnostics=diagnostics;
            provider=providerId;Need(provider.StartsWith("generated-browser-",StringComparison.Ordinal)&&provider.Length<=100,"APP_PROVIDER_NOT_GENERATED");Uri endpoint;Need(Uri.TryCreate(mockUrl,UriKind.Absolute,out endpoint)&&endpoint.Scheme=="http"&&endpoint.Host=="127.0.0.1"&&endpoint.Port>1024&&endpoint.AbsolutePath=="/","APP_MOCK_NOT_LOOPBACK");
            Identity=new Dictionary<string,object>{{"applicationSha256",hash},{"applicationBytes",bytes},{"actualApplicationTested",true},{"actualRegisteredAltD",true},{"shortcutGesture",ShortcutGesture},{"fakeIpcUsed",false},{"translationBackend","generated-loopback-mock"},{"credentialScope","One random absent provider ID only; no existing credential account"},{"nativeReadinessIsOsRegistrationProof",false},{"fixedFrontendWarmupMilliseconds",0},{"preHotkeyAppUiaCalls",0}};
            try{
                foreach(Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))using(p)Need(p.HasExited,"EXISTING_APP_PROCESS_REFUSED");
                string roaming=Path.Combine(Folder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"),Identifier),local=Path.Combine(Folder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"),Identifier),root=Path.Combine(Path.GetTempPath(),"echolingo-browser-app-"+token);
                Claim(roaming);Claim(local);Claim(root);history=Path.Combine(roaming,"history.json");
                var settings=new Dictionary<string,object>{{"providers",new object[]{new Dictionary<string,object>{{"id",provider},{"name","Generated browser loopback mock"},{"kind","libretranslate"},{"baseUrl",mockUrl},{"requiresApiKey",false},{"enabled",true},{"model",""},{"prompt",""}}}},{"ocrProviders",new object[0]},{"sourceLanguage","auto"},{"targetLanguage","auto"},{"languageDirectionVersion",1},{"shortcutDefaultsVersion",1},{"saveHistory",true},{"maxHistory",100},{"theme","light"},{"autoHideSeconds",0},{"shortcuts",new Dictionary<string,object>{{"selection","Alt+D"},{"silentOcr",""},{"ocr",""},{"capture",""},{"input",""}}}};
                File.WriteAllText(Path.Combine(roaming,"settings.json"),Json.Serialize(settings),new UTF8Encoding(false));
                ProcessStartInfo start=new ProcessStartInfo(executable);start.UseShellExecute=false;start.CreateNoWindow=true;string temp=Path.Combine(root,"Temp");Directory.CreateDirectory(temp);start.EnvironmentVariables["TEMP"]=temp;start.EnvironmentVariables["TMP"]=temp;start.EnvironmentVariables["LOCALAPPDATA"]=local;start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"]=Path.Combine(local,"webview-browser-fixture");app=Process.Start(start);Need(app.WaitForInputIdle(15000),"APP_NATIVE_INPUT_IDLE_DEADLINE");
                WaitNative(delegate{Need(!app.HasExited,"APP_EXITED_BEFORE_NATIVE_MAIN");main=OwnMain();return main!=IntPtr.Zero;},20000,"APP_NATIVE_MAIN_DEADLINE");WaitNative(NativeReady,15000,"APP_HOTKEY_HOST_AND_TRAY_DEADLINE");Need(!IsWindowVisible(main),"APP_DID_NOT_START_SILENTLY");Identity["applicationProcessId"]=app.Id;Identity["mainHwnd"]=WindowId(main);
                uiThread=new Thread(delegate(){while(true){wake.WaitOne();Action next;lock(uiGate){next=pending;pending=null;}if(next!=null)next();if(uiStop)return;}});uiThread.IsBackground=true;uiThread.SetApartmentState(ApartmentState.MTA);uiThread.Start();
            }catch{Close();throw;}
        }
        public bool Visible {get{return IsWindowVisible(main);}}
        public int Pid {get{return app.Id;}}
        public Dictionary<string,object> ReadSource(int remainingMilliseconds){
            Need(!uiPoisoned&&!closed,"APP_UIA_WORKER_UNAVAILABLE");TaskCompletionSource<Dictionary<string,object>> done=new TaskCompletionSource<Dictionary<string,object>>();
            lock(uiGate){Need(pending==null,"APP_UIA_WORKER_BUSY");pending=delegate{try{
                Need(!uiPoisoned&&!uiStop,"APP_UIA_WORKER_ABANDONED");Need(OwnMain()==main,"APP_MAIN_IDENTITY_CHANGED");AutomationElement root=AutomationElement.FromHandle(main);Need(root.Current.ProcessId==app.Id,"APP_UIA_ROOT_PID_CHANGED");
                AutomationElementCollection edits=root.FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));
                string value=null;int visible=0;foreach(AutomationElement e in edits){if(e.Current.IsOffscreen)continue;visible++;object p;Need(e.TryGetCurrentPattern(ValuePattern.Pattern,out p),"APP_SOURCE_VALUE_PATTERN_MISSING");value=((ValuePattern)p).Current.Value;}
                Need(visible<=1,"APP_SOURCE_EDITOR_NOT_UNIQUE");Need(value==null||value.Length<=65536,"APP_SOURCE_VALUE_BOUND");done.SetResult(new Dictionary<string,object>{{"value",value},{"sourceEditorVisibleCount",visible},{"nativeVisible",IsWindowVisible(main)}});
            }catch(Exception e){done.SetException(e);}};}
            wake.Set();Stopwatch clock=Stopwatch.StartNew();int limit=Math.Max(1,Math.Min(5000,remainingMilliseconds));while(!done.Task.IsCompleted&&clock.ElapsedMilliseconds<limit){Application.DoEvents();Thread.Sleep(2);}if(!done.Task.IsCompleted){uiPoisoned=true;throw new InvalidOperationException("APP_SOURCE_UIA_CALL_DEADLINE");}if(done.Task.IsFaulted)throw done.Task.Exception.InnerException;return done.Task.Result;
        }
        public int HistoryCount(string expected,string translation){CheckRoot(Path.GetDirectoryName(history));if(!File.Exists(history))return 0;Need(new FileInfo(history).Length<=1048576,"APP_HISTORY_BOUND");try{object[] rows=Json.Deserialize<object[]>(File.ReadAllText(history));Need(rows.Length<=100,"APP_HISTORY_COUNT_BOUND");int count=0;foreach(object item in rows){var row=(Dictionary<string,object>)item;if(Convert.ToString(row["text"])!=expected)continue;foreach(object raw in (IEnumerable)row["results"]){var r=(Dictionary<string,object>)raw;if(Convert.ToString(r["providerId"])==provider&&!r.ContainsKey("error")&&Convert.ToString(r["text"])==translation){count++;break;}}}return count;}catch(IOException){return 0;}catch(ArgumentException){return 0;}}
        static object RectMetadata(System.Windows.Rect r){if(Double.IsNaN(r.X)||Double.IsNaN(r.Y)||Double.IsNaN(r.Width)||Double.IsNaN(r.Height)||Double.IsInfinity(r.X)||Double.IsInfinity(r.Y)||Double.IsInfinity(r.Width)||Double.IsInfinity(r.Height)||Math.Abs(r.X)>100000||Math.Abs(r.Y)>100000||r.Width<0||r.Width>100000||r.Height<0||r.Height>100000)return null;return new double[]{r.X,r.Y,r.Width,r.Height};}
        Dictionary<string,object> SourceMetadataOnly(){
            Need(!uiPoisoned&&!closed,"DIAGNOSTIC_UIA_WORKER_UNAVAILABLE");var done=new TaskCompletionSource<Dictionary<string,object>>();
            lock(uiGate){Need(pending==null,"DIAGNOSTIC_UIA_WORKER_BUSY");pending=delegate{try{
                Need(!uiPoisoned&&!uiStop&&OwnMain()==main,"DIAGNOSTIC_OWN_MAIN_CHANGED");AutomationElement root=AutomationElement.FromHandle(main);Need(root.Current.ProcessId==app.Id,"DIAGNOSTIC_UIA_ROOT_PID_CHANGED");
                var matches=root.FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));var list=new List<object>();int visible=0;
                foreach(AutomationElement e in matches){if(list.Count>=8)break;bool offscreen=e.Current.IsOffscreen;if(!offscreen)visible++;object pattern;int kind=(e.Current.AutomationId=="source-text"?1:0)|(e.Current.Name=="\u539f\u6587"?2:0);list.Add(new Dictionary<string,object>{{"sourceMatchKind",kind},{"processId",e.Current.ProcessId},{"controlTypeId",e.Current.ControlType==null?0:e.Current.ControlType.Id},{"isOffscreen",offscreen},{"boundingRectangle",RectMetadata(e.Current.BoundingRectangle)},{"supportsValuePattern",e.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)}});}
                done.SetResult(new Dictionary<string,object>{{"matchingSourceCount",matches.Count},{"sampledVisibleSourceCount",visible},{"sourceCandidates",list},{"truncated",matches.Count>8},{"valueRead",false},{"rootProcessId",root.Current.ProcessId},{"rootControlTypeId",root.Current.ControlType==null?0:root.Current.ControlType.Id},{"rootBoundingRectangle",RectMetadata(root.Current.BoundingRectangle)}});
            }catch(Exception e){done.SetException(e);}};}
            wake.Set();Stopwatch watch=Stopwatch.StartNew();while(!done.Task.IsCompleted&&watch.ElapsedMilliseconds<5000){Application.DoEvents();Thread.Sleep(2);}if(!done.Task.IsCompleted){uiPoisoned=true;throw new InvalidOperationException("DIAGNOSTIC_UIA_METADATA_DEADLINE");}if(done.Task.IsFaulted)throw done.Task.Exception.InnerException;return done.Task.Result;
        }
        public Dictionary<string,object> FailureDiagnostics(){
            var result=new Dictionary<string,object>{{"diagnosticOnly",true},{"originalFailureUnchanged",true},{"sourceValueRead",false},{"pngMethod","PrintWindow of verified own HWND only; accelerated content may be omitted"}};
            Need(Diagnostics&&OwnMain()==main,"DIAGNOSTIC_OWN_MAIN_NOT_VERIFIED");uint owner;uint thread=GetWindowThreadProcessId(main,out owner);Need(owner==app.Id,"DIAGNOSTIC_NATIVE_PID_CHANGED");RECT bounds;bool hasBounds=GetWindowRect(main,out bounds);bool visible=IsWindowVisible(main);result["nativeVisible"]=visible;result["nativeProcessId"]=owner;result["nativeThreadId"]=thread;result["nativeClassKind"]="Tauri Window";
            var desktop=System.Windows.Forms.SystemInformation.VirtualScreen;var work=System.Windows.Forms.Screen.FromHandle(main).WorkingArea;result["virtualScreenBounds"]=new int[]{desktop.Left,desktop.Top,desktop.Width,desktop.Height};result["workAreaBounds"]=new int[]{work.Left,work.Top,work.Width,work.Height};result["nativeBounds"]=hasBounds?(object)new int[]{bounds.Left,bounds.Top,bounds.Right-bounds.Left,bounds.Bottom-bounds.Top}:null;
            try{result["sourceMetadata"]=SourceMetadataOnly();}catch(Exception e){result["sourceMetadataErrorType"]=e.GetType().Name;result["sourceMetadataErrorHResult"]=e.HResult;}
            if(!hasBounds||!visible){result["pngSkippedReason"]="own-window-bounds-or-visibility-unavailable";return result;}
            int width=bounds.Right-bounds.Left,height=bounds.Bottom-bounds.Top;var own=new System.Drawing.Rectangle(bounds.Left,bounds.Top,width,height);if(width<1||height<1||(long)width*height>2000000||!desktop.Contains(own)){result["pngSkippedReason"]="own-window-not-fully-on-screen-or-over-2mp";return result;}
            for(int y=1;y<=3;y++)for(int x=1;x<=3;x++){POINT p=new POINT();p.x=bounds.Left+width*x/4;p.y=bounds.Top+height*y/4;if(GetAncestor(WindowFromPoint(p),2)!=main){result["pngSkippedReason"]="own-window-not-visible-at-native-sample";return result;}}
            var capture=Task.Factory.StartNew(delegate{
                uint pid;Need(GetWindowThreadProcessId(main,out pid)!=0&&pid==app.Id&&OwnMain()==main,"DIAGNOSTIC_CAPTURE_WINDOW_CHANGED");
                using(var bitmap=new System.Drawing.Bitmap(width,height,System.Drawing.Imaging.PixelFormat.Format32bppArgb)){
                    using(var graphics=System.Drawing.Graphics.FromImage(bitmap)){graphics.Clear(System.Drawing.Color.Transparent);IntPtr dc=graphics.GetHdc();bool printed;try{printed=PrintWindow(main,dc,2);}finally{graphics.ReleaseHdc(dc);}if(!printed)return null;}
                    using(var memory=new MemoryStream()){bitmap.Save(memory,System.Drawing.Imaging.ImageFormat.Png);Need(memory.Length<=10485760,"DIAGNOSTIC_PNG_SIZE_BOUND");return memory.ToArray();}
                }
            });
            bool complete=false;try{complete=capture.Wait(2000);}catch(AggregateException e){result["pngErrorType"]=e.InnerException.GetType().Name;result["pngErrorHResult"]=e.InnerException.HResult;return result;}if(!complete){result["pngSkippedReason"]="own-printwindow-did-not-return-within-2s";return result;}byte[] png=capture.Result;if(png==null){result["pngSkippedReason"]="own-printwindow-failed";return result;}
            string temp=Environment.GetEnvironmentVariable("RUNNER_TEMP");Need(!String.IsNullOrEmpty(temp)&&Path.IsPathRooted(temp)&&Directory.Exists(temp)&&(File.GetAttributes(temp)&FileAttributes.ReparsePoint)==0,"DIAGNOSTIC_RUNNER_TEMP_INVALID");string dir=Path.Combine(temp,"echolingo-browser-app-diagnostics-"+Guid.NewGuid().ToString("N"));Need(CreateDirectory(dir,IntPtr.Zero),"DIAGNOSTIC_DIRECTORY_NOT_EXCLUSIVE");File.WriteAllText(Path.Combine(dir,".echolingo-diagnostic-owned"),token,new UTF8Encoding(false));Need((File.GetAttributes(dir)&FileAttributes.ReparsePoint)==0,"DIAGNOSTIC_DIRECTORY_REPARSE_POINT");string file=Path.Combine(dir,"cold-edge-source.png");using(var output=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None))output.Write(png,0,png.Length);string hash;using(var sha=System.Security.Cryptography.SHA256.Create())hash=BitConverter.ToString(sha.ComputeHash(png)).Replace("-","").ToLowerInvariant();result["pngDirectory"]=Path.GetFileName(dir);result["pngFile"]="cold-edge-source.png";result["pngBytes"]=png.Length;result["pngSha256"]=hash;result["pngWidth"]=width;result["pngHeight"]=height;return result;
        }
        public Dictionary<string,object> Close(){
            if(closed)return cleanup;closed=true;cleanup=new Dictionary<string,object>{{"ok",false},{"method","owned-process-tree-termination"},{"completeDescendantEnumeration",false}};List<string> errors=new List<string>();
            try{if(app!=null){if(!app.HasExited){ProcessStartInfo start=new ProcessStartInfo("taskkill.exe","/PID "+app.Id+" /T /F");start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;using(Process p=Process.Start(start)){Task<string> o=p.StandardOutput.ReadToEndAsync(),e=p.StandardError.ReadToEndAsync();Need(p.WaitForExit(5000),"OWN_APP_TREE_KILL_DEADLINE");Need(Task.WaitAll(new Task[]{o,e},1000),"OWN_APP_KILL_PIPE_DEADLINE");}}Need(app.WaitForExit(5000),"OWN_APP_NOT_EXITED");cleanup["ownAppExited"]=true;app.Dispose();}}catch(Exception e){errors.Add(e.GetType().Name+":"+e.Message);}
            try{uiStop=true;wake.Set();if(uiThread!=null)Need(uiThread.Join(2000),"OWN_APP_UIA_WORKER_NOT_STOPPED");}catch(Exception e){errors.Add(e.GetType().Name+":"+e.Message);}
            for(int i=owned.Count-1;i>=0;i--)try{DeleteOwn(owned[i]);}catch(Exception e){errors.Add(e.GetType().Name+":"+e.Message);}
            cleanup["errors"]=errors;cleanup["ownedDirectoriesRemoved"]=errors.Count==0;cleanup["ok"]=errors.Count==0;return cleanup;
        }
    }
    static INPUT AppKey(ushort code,bool up){INPUT i=new INPUT();i.type=1;i.data.key.key=code;i.data.key.flags=up?2U:0U;return i;}
    static void SendAppShortcut(IntPtr main,Dictionary<string,object> metadata){
        metadata["shortcutGesture"]=ShortcutGesture;metadata["shortcutGestureAttempts"]=1;
        metadata["gestureAltLeadMilliseconds"]=ShortcutGesture=="paced"?40:0;metadata["gestureDHoldMilliseconds"]=ShortcutGesture=="paced"?80:0;
        if(ShortcutGesture=="instant"){
            INPUT[] keys=new INPUT[]{AppKey(0x12,false),AppKey(0x44,false),AppKey(0x44,true),AppKey(0x12,true)};uint sent=SendInput(4,keys,Marshal.SizeOf(typeof(INPUT)));metadata["actualShortcutPresses"]=1;metadata["insertedInputEvents"]=sent;if(sent!=4){SendInput(2,new INPUT[]{AppKey(0x44,true),AppKey(0x12,true)},Marshal.SizeOf(typeof(INPUT)));throw new InvalidOperationException("APP_ALT_D_INPUT_REJECTED_NO_RETRY");}return;
        }
        Need((GetAsyncKeyState(0x44)&0x8000)==0,"APP_GESTURE_D_ALREADY_HELD");bool altOwned=false,dOwned=false;uint inserted=0;Stopwatch gesture=Stopwatch.StartNew();
        metadata["gestureOwnedKeyCleanupRequired"]=false;
        try{
            Stage="actual-alt-d-once:alt-down";uint alt=SendInput(1,new INPUT[]{AppKey(0x12,false)},Marshal.SizeOf(typeof(INPUT)));inserted+=alt;altOwned=alt==1;Need(alt==1,"APP_GESTURE_ALT_DOWN_REJECTED_NO_RETRY");
            // These are test-only human gesture intervals, never product waits.
            Thread.Sleep(40);metadata["gestureSourceForegroundAfterAltLead"]=GetForegroundWindow()==main;Need(GetForegroundWindow()==main,"APP_GESTURE_SOURCE_CHANGED_AFTER_ALT");
            Stage="actual-alt-d-once:d-down";uint down=SendInput(1,new INPUT[]{AppKey(0x44,false)},Marshal.SizeOf(typeof(INPUT)));inserted+=down;dOwned=down==1;metadata["actualShortcutPresses"]=dOwned?1:0;metadata["gestureDDownAtMilliseconds"]=gesture.Elapsed.TotalMilliseconds;Need(down==1,"APP_GESTURE_D_DOWN_REJECTED_NO_RETRY");
            Thread.Sleep(80);Stage="actual-alt-d-once:release";uint up=SendInput(2,new INPUT[]{AppKey(0x44,true),AppKey(0x12,true)},Marshal.SizeOf(typeof(INPUT)));inserted+=up;if(up>=1)dOwned=false;if(up>=2)altOwned=false;Need(up==2,"APP_GESTURE_RELEASE_REJECTED_NO_RETRY");
        }finally{
            metadata["insertedInputEvents"]=inserted;metadata["gestureDurationMilliseconds"]=gesture.Elapsed.TotalMilliseconds;
            if(dOwned||altOwned){var release=new List<INPUT>();if(dOwned)release.Add(AppKey(0x44,true));if(altOwned)release.Add(AppKey(0x12,true));metadata["gestureOwnedKeyCleanupRequired"]=true;metadata["gestureOwnedKeyCleanupExpectedEvents"]=release.Count;metadata["gestureOwnedKeyCleanupInsertedEvents"]=SendInput((uint)release.Count,release.ToArray(),Marshal.SizeOf(typeof(INPUT)));}
        }
    }
    static Dictionary<string,object> RunApplicationCase(Dictionary<string,object> command,IntPtr main,Dictionary<string,object> metadata){
        string expected=Convert.ToString(command["expected"]),translation=Convert.ToString(command["expectedTranslation"]);Need(Convert.ToString(command["outcome"])=="selection"&&expected.Length>0&&translation.Length<=512,"APP_GENERATED_SELECTION_REQUIRED");
        metadata["actualApplicationTested"]=true;metadata["actualRegisteredAltD"]=true;metadata["helperInvocations"]=0;metadata["actualShortcutPresses"]=0;metadata["preHotkeyAppUiaCalls"]=0;metadata["safeToContinue"]=false;
        Stage="app-clipboard-seed";DataObject seed=Seed();int before=HostedApplication.HistoryCount(expected,translation);metadata["historyExactCountBefore"]=before;metadata["popupVisibleBeforeHotkey"]=HostedApplication.Visible;
        Need(GetForegroundWindow()==main&&(GetAsyncKeyState(1)&0x8000)==0,"APP_SOURCE_OR_MOUSE_CHANGED_BEFORE_HOTKEY");foreach(int key in new int[]{0x10,0x11,0x12,0x5B,0x5C})Need((GetAsyncKeyState(key)&0x8000)==0,"APP_SHORTCUT_MODIFIER_ALREADY_HELD");
        Stopwatch clock=Stopwatch.StartNew();Stage="actual-alt-d-once";SendAppShortcut(main,metadata);
        Stage="actual-app-source-and-new-history";bool exact=false,foregroundAlways=true;int staleReads=0;while(clock.ElapsedMilliseconds<30000){
            metadata["popupNativeVisible"]=HostedApplication.Visible;bool sourceForeground=GetForegroundWindow()==main;foregroundAlways=foregroundAlways&&sourceForeground;metadata["sourceForegroundPreserved"]=sourceForeground;metadata["sourceForegroundPreservedThroughoutObservation"]=foregroundAlways;
            // Wait only for native presentation before the first app UIA read:
            // do not prime UIA while the first cold helper is acquiring text.
            if(HostedApplication.Visible){try{Dictionary<string,object> source=HostedApplication.ReadSource((int)Math.Max(1,30000-clock.ElapsedMilliseconds));string value=source["value"] as string;metadata["sourceEditorVisibleCount"]=source["sourceEditorVisibleCount"];metadata["actualSourceLength"]=value==null?-1:value.Length;metadata["actualSourceEmpty"]=value!=null&&value.Length==0;metadata["exactSelectedTextMatched"]=value==expected;metadata["historyExactCountAfter"]=HostedApplication.HistoryCount(expected,translation);exact=value==expected&&Convert.ToInt32(metadata["historyExactCountAfter"])==before+1;if(exact)break;}catch(ElementNotAvailableException){staleReads++;metadata["staleAppSourceReadObservations"]=staleReads;}}
            Application.DoEvents();Thread.Sleep(10);
        }
        metadata["hotkeyToExactSourceAndHistoryMilliseconds"]=clock.Elapsed.TotalMilliseconds;metadata["shortcutKeysReleasedAfterAction"]=(GetAsyncKeyState(0x12)&0x8000)==0&&(GetAsyncKeyState(0x44)&0x8000)==0;Stage="app-clipboard-and-foreground-check";metadata["richClipboardRestored"]=Restored(seed);if(Convert.ToBoolean(metadata["richClipboardRestored"]))ownedClipboard=GetClipboardSequenceNumber();
        metadata["sourceForegroundPreserved"]=GetForegroundWindow()==main;metadata["browserBoundRootPreserved"]=BrowserMain(Convert.ToInt32(command["browserPid"]))==main;metadata["safeToContinue"]=Convert.ToBoolean(metadata["richClipboardRestored"])&&Convert.ToBoolean(metadata["sourceForegroundPreserved"]);
        metadata["ok"]=exact&&foregroundAlways&&Convert.ToBoolean(metadata["richClipboardRestored"])&&Convert.ToBoolean(metadata["sourceForegroundPreserved"])&&Convert.ToBoolean(metadata["browserBoundRootPreserved"])&&Convert.ToBoolean(metadata["shortcutKeysReleasedAfterAction"]);metadata["safeToContinue"]=metadata["ok"];metadata["acquisitionExpectationPassed"]=metadata["ok"];metadata["failureClassification"]=Convert.ToBoolean(metadata["ok"])?null:"actual-app-hotkey-acquisition";if(!Convert.ToBoolean(metadata["ok"])){
            metadata["error"]="ACTUAL_APP_EXACT_SOURCE_NEW_HISTORY_OR_FOREGROUND_FAILED";
            if(HostedApplication.Diagnostics)try{metadata["ownAppFailureDiagnostics"]=HostedApplication.FailureDiagnostics();}catch(Exception e){metadata["ownAppFailureDiagnosticErrorType"]=e.GetType().Name;metadata["ownAppFailureDiagnosticErrorHResult"]=e.HResult;}
        }return metadata;
    }
    public static void Run(string helper,string assembly,string browser,string application,string mockUrl,string provider,string hash,long bytes,bool diagnostics,string shortcutGesture){
        Need(shortcutGesture=="instant"||shortcutGesture=="paced","SHORTCUT_GESTURE_INVALID");Need(shortcutGesture=="instant"||!String.IsNullOrEmpty(application),"PACED_GESTURE_REQUIRES_APPLICATION");ShortcutGesture=shortcutGesture;
        Helper=String.IsNullOrEmpty(helper)?null:Path.GetFullPath(helper);Assembly=String.IsNullOrEmpty(assembly)?null:Path.GetFullPath(assembly);Browser=Path.GetFullPath(browser);Need(Helper==null||!Helper.Contains("\"")&&!Assembly.Contains("\""),"INVALID_FIXTURE_PATH");
        IDataObject existing=Clipboard.GetDataObject();Need(existing==null||existing.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");
        try{
            if(!String.IsNullOrEmpty(application))HostedApplication=new AppSession(application,mockUrl,provider,hash,bytes,diagnostics);
            if(HostedApplication!=null){SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"NATIVE_MOUSE_PHYSICAL_COORDINATES_REQUIRED");}
            Reply(new Dictionary<string,object>{{"ready",true},{"bridgeProcessId",Process.GetCurrentProcess().Id},{"clipboardContentRead",false},{"application",HostedApplication==null?null:HostedApplication.Identity}});
            string line;while((line=Console.ReadLine())!=null){
                Need(line.Length<=4096,"BRIDGE_COMMAND_BOUND");Dictionary<string,object> command=Json.Deserialize<Dictionary<string,object>>(line.TrimStart('\ufeff'));string op=Convert.ToString(command["op"]);
                if(op=="close"){bool cleared=ClearOwnedClipboard();Dictionary<string,object> cleanup=HostedApplication==null?null:HostedApplication.Close();Reply(new Dictionary<string,object>{{"ok",cleared&&(cleanup==null||Convert.ToBoolean(cleanup["ok"]))},{"closing",true},{"clipboardCleanupComplete",cleared},{"applicationCleanup",cleanup}});return;}
                try{
                    if(op!="case"){Stage="native-mouse-"+op;LastMetadata=new Dictionary<string,object>{{"ok",false},{"helperInvocations",0},{"actualShortcutPresses",0},{"safeToContinue",false},{"preHelperUiaCalls",0}};}
                    if(op=="mouse-point"){Reply(GuardMouseStart(command));continue;}
                    if(op=="mouse-drag"){Reply(DragMouseOnce(command));continue;}
                    if(op=="outside-click"){Reply(OutsideClickOnce(command));continue;}
                    Need(op=="case","BRIDGE_UNSUPPORTED_COMMAND");Reply(RunCase(command));}
                catch(Exception error){while(error.InnerException!=null)error=error.InnerException;Dictionary<string,object> failure=LastMetadata??new Dictionary<string,object>();failure["ok"]=false;failure["error"]=error.Message;failure["errorType"]=error.GetType().Name;failure["stage"]=Stage;failure["setupInconclusive"]=Stage=="native-identity";failure["browserRootCandidates"]=windowInventory;failure["boundBrowserRootHwnd"]=WindowId(boundMain);Reply(failure);}
            }
        }finally{try{if(HostedApplication!=null)HostedApplication.Close();}finally{ClearOwnedClipboard();}}
    }
}
