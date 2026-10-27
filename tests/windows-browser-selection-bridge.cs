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
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int capacity);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=1048576 };
    static string Helper,Assembly,Browser;
    static uint ownedClipboard;
    static bool seeded;
    static string Stage="setup";static Dictionary<string,object> LastMetadata;
    static void Need(bool value,string error){if(!value)throw new InvalidOperationException(error);}
    static void Reply(object value){Console.WriteLine(Json.Serialize(value));Console.Out.Flush();}
    static IntPtr BrowserMain(int pid){
        using(Process process=Process.GetProcessById(pid))Need(String.Equals(Path.GetFullPath(process.MainModule.FileName),Browser,StringComparison.OrdinalIgnoreCase),"BROWSER_IDENTITY_MISMATCH");
        List<IntPtr> windows=new List<IntPtr>();EnumWindows(delegate(IntPtr window,IntPtr unused){uint owner;GetWindowThreadProcessId(window,out owner);StringBuilder name=new StringBuilder(256);GetClassName(window,name,name.Capacity);if(owner==pid&&GetAncestor(window,2)==window&&IsWindowVisible(window)&&name.ToString()=="Chrome_WidgetWin_1")windows.Add(window);return true;},IntPtr.Zero);
        Need(windows.Count==1,"BROWSER_ROOT_NOT_UNIQUE");return windows[0];
    }
    static Dictionary<string,object> FocusMetadata(IntPtr main,int browserPid){
        Need(GetForegroundWindow()==main,"BROWSER_NOT_FOREGROUND");
        Task<Dictionary<string,object>> query=Task.Factory.StartNew(delegate{
            AutomationElement focus=AutomationElement.FocusedElement;Need(focus!=null,"BROWSER_UIA_FOCUS_MISSING");
            Dictionary<string,object> result=new Dictionary<string,object>{{"focusedRole",focus.Current.ControlType.ProgrammaticName},{"focusedProcessId",focus.Current.ProcessId},{"runtimeIdPresent",focus.GetRuntimeId()!=null&&focus.GetRuntimeId().Length>0}};
            List<int> sourcePids=new List<int>();bool matched=false;int depth=0;
            for(AutomationElement current=focus;current!=null&&depth<64;current=TreeWalker.RawViewWalker.GetParent(current),depth++){
                Need(!current.Current.IsPassword,"GENERATED_PAGE_UNEXPECTED_PASSWORD");int pid=current.Current.ProcessId;if(pid!=0&&!sourcePids.Contains(pid))sourcePids.Add(pid);
                int handle=current.Current.NativeWindowHandle;if(handle!=0){Need(GetAncestor(new IntPtr(handle),2)==main,"BROWSER_UIA_FOCUS_ROOT_MISMATCH");if(new IntPtr(handle)==main){matched=true;break;}}
            }
            Need(matched,"BROWSER_UIA_ROOT_UNVERIFIED");result["ancestorProcessIds"]=sourcePids;result["ancestorDepth"]=depth;result["foregroundBrowserProcessId"]=browserPid;result["sourceRootVerified"]=true;return result;
        },CancellationToken.None,TaskCreationOptions.DenyChildAttach,TaskScheduler.Default);
        Need(query.Wait(2000),"BROWSER_UIA_METADATA_TIMEOUT");Need(GetForegroundWindow()==main,"BROWSER_FOREGROUND_CHANGED");return query.Result;
    }
    static DataObject Seed(){
        DataObject data=new DataObject();data.SetData(DataFormats.UnicodeText,false,"Generated browser clipboard original 24680");data.SetData(DataFormats.Html,false,"<p>Generated browser rich original 24680</p>");data.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated browser rich original 24680}");Clipboard.SetDataObject(data,true,0,0);ownedClipboard=GetClipboardSequenceNumber();seeded=true;return data;
    }
    static bool Restored(DataObject expected){IDataObject actual=Clipboard.GetDataObject();if(actual==null)return false;foreach(string format in expected.GetFormats(false))if(!Object.Equals(expected.GetData(format,false),actual.GetData(format,false)))return false;return true;}
    static Dictionary<string,object> RunCase(Dictionary<string,object> command){
        int pid=Convert.ToInt32(command["browserPid"]);string expected=Convert.ToString(command["expected"]);bool empty=Convert.ToBoolean(command["empty"]);Need(expected.Length<=512,"GENERATED_EXPECTATION_TOO_LARGE");
        Stage="setup";LastMetadata=null;IntPtr main=BrowserMain(pid);if(GetForegroundWindow()!=main)SetForegroundWindow(main);
        Stopwatch focus=Stopwatch.StartNew();while(GetForegroundWindow()!=main&&focus.ElapsedMilliseconds<1000)Thread.Sleep(10);Need(GetForegroundWindow()==main,"BROWSER_NOT_FOREGROUND");
        Dictionary<string,object> metadata=FocusMetadata(main,pid);LastMetadata=metadata;
        string role=Convert.ToString(metadata["focusedRole"]);string requiredRole=Convert.ToString(command["requiredRole"]);Need(requiredRole==""||requiredRole==role,"BROWSER_ACTUAL_FOCUSED_ROLE_MISMATCH");
        Stage="clipboard-seed";DataObject seed=Seed();uint initial=ownedClipboard;string cancelName="Local\\EchoLingo-cancel-"+Guid.NewGuid().ToString("N");
        using(EventWaitHandle cancel=new EventWaitHandle(false,EventResetMode.ManualReset,cancelName)){
            ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell/v1.0/powershell.exe"));
            start.Arguments="-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \""+Helper+"\" -Mode selected-text -NativeAssemblyPath \""+Assembly+"\" -NativeCancellationEvent \""+cancelName+"\"";
            start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=new UTF8Encoding(false);
            HashSet<int> observedOwners=new HashSet<int>();HashSet<uint> observedGenerations=new HashSet<uint>();Stopwatch clock=Stopwatch.StartNew();Dictionary<string,object> reply;
            Stage="native-helper";using(Process helper=Process.Start(start)){
                Task<string> stdout=helper.StandardOutput.ReadToEndAsync(),stderr=helper.StandardError.ReadToEndAsync();
                try{
                    while(!helper.WaitForExit(2)){
                        // The STA owns the generated OLE clipboard window. Pump
                        // its render/destroy messages while observing our helper.
                        Application.DoEvents();
                        uint sequence=GetClipboardSequenceNumber();if(sequence!=initial){observedGenerations.Add(sequence);uint owner;GetWindowThreadProcessId(GetClipboardOwner(),out owner);if(owner!=0)observedOwners.Add((int)owner);}
                        Need(clock.ElapsedMilliseconds<12000,"BROWSER_HELPER_DEADLINE");
                    }
                    Need(Task.WaitAll(new Task[]{stdout,stderr},2000),"BROWSER_HELPER_PIPE_TIMEOUT");Need(stdout.Result.Length<262144&&stderr.Result.Length<65536,"BROWSER_HELPER_OUTPUT_BOUND");
                    reply=Json.Deserialize<Dictionary<string,object>>(stdout.Result.Trim('\ufeff',' ','\r','\n'));
                    Need(reply.ContainsKey("nativeBackend")&&Convert.ToString(reply["nativeBackend"])=="precompiled-framework-dll","BROWSER_HELPER_EXACT_DLL_NOT_USED");
                    metadata["nativeBackend"]=reply.ContainsKey("nativeBackend")?reply["nativeBackend"]:null;metadata["helperActualExitCode"]=helper.ExitCode;if(reply.ContainsKey("error")){string value=Convert.ToString(reply["error"]);int split=value.IndexOf(':');metadata["helperReplyErrorPrefix"]=split>=0?value.Substring(0,Math.Min(split,64)):"UNCLASSIFIED";}
                    bool ok=Convert.ToBoolean(reply["ok"]);Need(helper.ExitCode==(ok?0:1),"BROWSER_HELPER_EXIT_MISMATCH");
                    Need(ok!=empty,"BROWSER_SELECTION_UNEXPECTED_RESULT");
                    if(empty)Need(reply.ContainsKey("error")&&Convert.ToString(reply["error"]).StartsWith("NO_SELECTION:"),"BROWSER_EMPTY_TEXTAREA_WRONG_GUARD");
                    else Need(Convert.ToString(reply["text"])==expected,"BROWSER_SELECTION_TEXT_MISMATCH");
                }finally{
                    if(!helper.HasExited){cancel.Set();if(!helper.WaitForExit(2000)){helper.Kill();Need(helper.WaitForExit(2000),"OWN_BROWSER_HELPER_CLEANUP_FAILED");}}
                }
            }
            Stage="clipboard-check";Need(Restored(seed),"BROWSER_ORIGINAL_RICH_CLIPBOARD_NOT_RESTORED");ownedClipboard=GetClipboardSequenceNumber();Need(GetForegroundWindow()==main,"BROWSER_HELPER_CHANGED_FOREGROUND");
            metadata["ok"]=true;metadata["helperInvocations"]=1;metadata["helperBackend"]="precompiled-framework-dll";metadata["helperElapsedMilliseconds"]=clock.Elapsed.TotalMilliseconds;metadata["richClipboardRestored"]=true;metadata["sourceForegroundPreserved"]=true;
            metadata["clipboardGenerationChanged"]=ownedClipboard!=initial;metadata["sampledClipboardOwnerProcessIds"]=new List<int>(observedOwners);metadata["sampledVerifiedSourceOwnerObserved"]=new List<int>(observedOwners).Exists(delegate(int owner){return ((List<int>)metadata["ancestorProcessIds"]).Contains(owner);});metadata["sampledClipboardGenerationCount"]=observedGenerations.Count;metadata["clipboardOwnerPollMilliseconds"]=2;metadata["clipboardOwnerSamplingMayMissBriefOwnership"]=true;metadata["emptySelectionRejected"]=empty;return metadata;
        }
    }
    public static void Run(string helper,string assembly,string browser){
        Helper=Path.GetFullPath(helper);Assembly=Path.GetFullPath(assembly);Browser=Path.GetFullPath(browser);Need(!Helper.Contains("\"")&&!Assembly.Contains("\""),"INVALID_FIXTURE_PATH");
        IDataObject existing=Clipboard.GetDataObject();Need(existing==null||existing.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");
        Reply(new Dictionary<string,object>{{"ready",true},{"bridgeProcessId",Process.GetCurrentProcess().Id},{"clipboardContentRead",false}});
        try{
            string line;while((line=Console.ReadLine())!=null){
                Need(line.Length<=4096,"BRIDGE_COMMAND_BOUND");Dictionary<string,object> command=Json.Deserialize<Dictionary<string,object>>(line.TrimStart('\ufeff'));string op=Convert.ToString(command["op"]);
                if(op=="close"){Reply(new Dictionary<string,object>{{"ok",true},{"closing",true}});return;}
                try{Need(op=="case","BRIDGE_UNSUPPORTED_COMMAND");Reply(RunCase(command));}
                catch(Exception error){while(error.InnerException!=null)error=error.InnerException;Dictionary<string,object> failure=LastMetadata??new Dictionary<string,object>();failure["ok"]=false;failure["error"]=error.Message;failure["errorType"]=error.GetType().Name;failure["stage"]=Stage;failure["setupInconclusive"]=Stage=="setup";Reply(failure);}
            }
        }finally{if(seeded&&GetClipboardSequenceNumber()==ownedClipboard)Clipboard.Clear();}
    }
}
