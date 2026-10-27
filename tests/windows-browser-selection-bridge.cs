// Isolated, generated browser page only. No process-wide source selection or
// clipboard reads occur until the spawned browser HWND and focused root match.
using System;
using System.Collections.Generic;
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
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int capacity);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=1048576 };
    static string Helper,Assembly,Browser;
    static uint ownedClipboard;
    static bool seeded;
    static string Stage="setup";static Dictionary<string,object> LastMetadata;
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
            if(performance!=null)for(int i=1;i<=16;i++)foreach(string suffix in new string[]{"Milliseconds","Stage","Depth"}){string key="selectionQuery"+i+suffix;object value;if(performance.TryGetValue(key,out value)){double number=Convert.ToDouble(value);Need(!Double.IsNaN(number)&&!Double.IsInfinity(number)&&number>=0&&number<=10000000,"SELECTION_DIAGNOSTIC_BOUND");numeric[key]=number;}}
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
                    metadata["helperReplyErrorPrefix"]=error==""?null:split>=0?error.Substring(0,Math.Min(split,64)):"UNCLASSIFIED";metadata["helperReportedUiaDeadline"]=error.StartsWith("SELECTION:")&&error.Contains("did not answer in time");
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
    public static void Run(string helper,string assembly,string browser){
        Helper=Path.GetFullPath(helper);Assembly=Path.GetFullPath(assembly);Browser=Path.GetFullPath(browser);Need(!Helper.Contains("\"")&&!Assembly.Contains("\""),"INVALID_FIXTURE_PATH");
        IDataObject existing=Clipboard.GetDataObject();Need(existing==null||existing.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");
        Reply(new Dictionary<string,object>{{"ready",true},{"bridgeProcessId",Process.GetCurrentProcess().Id},{"clipboardContentRead",false}});
        try{
            string line;while((line=Console.ReadLine())!=null){
                Need(line.Length<=4096,"BRIDGE_COMMAND_BOUND");Dictionary<string,object> command=Json.Deserialize<Dictionary<string,object>>(line.TrimStart('\ufeff'));string op=Convert.ToString(command["op"]);
                if(op=="close"){bool cleared=ClearOwnedClipboard();Reply(new Dictionary<string,object>{{"ok",cleared},{"closing",true},{"clipboardCleanupComplete",cleared}});return;}
                try{Need(op=="case","BRIDGE_UNSUPPORTED_COMMAND");Reply(RunCase(command));}
                catch(Exception error){while(error.InnerException!=null)error=error.InnerException;Dictionary<string,object> failure=LastMetadata??new Dictionary<string,object>();failure["ok"]=false;failure["error"]=error.Message;failure["errorType"]=error.GetType().Name;failure["stage"]=Stage;failure["setupInconclusive"]=Stage=="native-identity";failure["browserRootCandidates"]=windowInventory;failure["boundBrowserRootHwnd"]=WindowId(boundMain);Reply(failure);}
            }
        }finally{ClearOwnedClipboard();}
    }
}
