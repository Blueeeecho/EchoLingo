// Actual foreign child focus, same-root ancestry, manual Ctrl+C baseline and the
// exact compiled helper. A baseline rejection is not product acceptance.
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

public static class WindowsSelectionNativeFocusFixture {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUI info);
    [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr window,uint message,IntPtr word,IntPtr parameter);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr window,uint message,IntPtr word,IntPtr parameter);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] values,int size);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref POINT point);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [StructLayout(LayoutKind.Sequential)] struct POINT {public int x,y;}
    [StructLayout(LayoutKind.Sequential)] struct GUI {public uint size,flags;public IntPtr active,focus,capture,menu,move,caret;public int l,t,r,b;}
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public UNION data;}
    [StructLayout(LayoutKind.Explicit)] struct UNION {[FieldOffset(0)]public KEY keyboard;[FieldOffset(0)]public MOUSE mouse;}
    [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort key,scan;public uint flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=1048576};
    static void Need(bool condition,string reason){if(!condition)throw new InvalidOperationException(reason);}
    static INPUT Key(ushort key,bool up){INPUT value=new INPUT();value.type=1;value.data.keyboard.key=key;value.data.keyboard.flags=up?2U:0U;return value;}
    static void Send(params INPUT[] values){uint sent=SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)));Need(sent==values.Length,"GENERATED_INPUT_REJECTED");}
    static void Wait(Func<bool> condition,int milliseconds,string reason){Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<milliseconds){if(condition())return;Thread.Sleep(1);}throw new InvalidOperationException("TIMEOUT:"+reason);}
    static void Ui(Form form,Action action){form.Invoke(action);}
    static GUI Gui(uint thread,out bool success){GUI value=new GUI();value.size=(uint)Marshal.SizeOf(typeof(GUI));success=GetGUIThreadInfo(thread,ref value);return value;}
    static Dictionary<string,object> Context(IntPtr parent,IntPtr child){
        uint parentProcess,childProcess;uint parentThread=GetWindowThreadProcessId(parent,out parentProcess),childThread=GetWindowThreadProcessId(child,out childProcess);
        bool ok,foregroundOk;GUI info=Gui(parentThread,out ok),foreground=Gui(0,out foregroundOk);IntPtr root=GetAncestor(parent,2);uint focusProcess=0,focusThread=0;if(info.focus!=IntPtr.Zero)focusThread=GetWindowThreadProcessId(info.focus,out focusProcess);
        return new Dictionary<string,object>{{"foregroundIsParent",GetForegroundWindow()==parent},{"gtiSucceeded",ok},{"gtiFocusPresent",info.focus!=IntPtr.Zero},{"gtiFocusIsExpectedChild",info.focus==child},{"focusRootMatchesForeground",info.focus!=IntPtr.Zero&&GetAncestor(info.focus,2)==root},{"focusProcessMatchesForeground",focusProcess!=0&&focusProcess==parentProcess},{"focusThreadDiffersFromForeground",focusThread!=0&&focusThread!=parentThread},{"childProcessMatchesForeground",childProcess==parentProcess},{"childThreadDiffersFromForeground",childThread!=parentThread},{"gtiActiveRootMatchesForeground",info.active!=IntPtr.Zero&&GetAncestor(info.active,2)==root},{"gtiFlags",info.flags},{"foregroundQueueGtiSucceeded",foregroundOk},{"foregroundQueueFocusIsExpectedChild",foreground.focus==child},{"foregroundQueueMatchesThreadQuery",foregroundOk&&ok&&foreground.focus==info.focus}};
    }
    sealed class ClipboardSeed {public DataObject Declared;public string[] PublishedFormats;}
    static ClipboardSeed Seed(){DataObject data=new DataObject();data.SetData(DataFormats.UnicodeText,false,"Generated native focus original 16273");data.SetData(DataFormats.Html,false,"<p>Generated native focus original 16273</p>");data.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated native focus original 16273}");Clipboard.SetDataObject(data,true,0,0);IDataObject published=Clipboard.GetDataObject();Need(published!=null,"GENERATED_SEED_NOT_PUBLISHED");string[] formats=published.GetFormats(false);Array.Sort(formats,StringComparer.Ordinal);return new ClipboardSeed {Declared=data,PublishedFormats=formats};}
    static void CheckSeed(ClipboardSeed seed){IDataObject current=Clipboard.GetDataObject();Need(current!=null,"GENERATED_CLIPBOARD_MISSING");string[] expected=seed.PublishedFormats,actual=current.GetFormats(false);Array.Sort(actual,StringComparer.Ordinal);Need(expected.Length==actual.Length,"GENERATED_CLIPBOARD_FORMAT_SET_CHANGED");for(int i=0;i<expected.Length;i++)Need(expected[i]==actual[i],"GENERATED_CLIPBOARD_FORMAT_SET_CHANGED");foreach(string format in seed.Declared.GetFormats(false))Need(Object.Equals(current.GetData(format,false),seed.Declared.GetData(format,false)),"GENERATED_RICH_CLIPBOARD_CHANGED");}
    static Dictionary<string,object> Call(string helper,string assembly){
        string name="Local\\EchoLingo-cancel-"+Guid.NewGuid().ToString("N");
        using(EventWaitHandle cancel=new EventWaitHandle(false,EventResetMode.ManualReset,name)){
            ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell/v1.0/powershell.exe"));
            start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+helper+"\" -Mode selected-text -SelectionStrategy copy -NativeAssemblyPath \""+assembly+"\" -NativeCancellationEvent \""+name+"\"";start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=new UTF8Encoding(false);
            using(Process process=Process.Start(start)){Task<string> output=process.StandardOutput.ReadToEndAsync(),error=process.StandardError.ReadToEndAsync();try{Need(process.WaitForExit(12000),"OWN_HELPER_DEADLINE");Need(Task.WaitAll(new Task[]{output,error},2000),"OWN_HELPER_PIPE_DEADLINE");Need(output.Result.Length<=262144&&error.Result.Length<=65536,"OWN_HELPER_OUTPUT_BOUND");return Json.Deserialize<Dictionary<string,object>>(output.Result.Trim('\ufeff',' ','\r','\n'));}finally{if(!process.HasExited){cancel.Set();if(!process.WaitForExit(2000)){process.Kill();Need(process.WaitForExit(2000),"OWN_HELPER_STOP_FAILED");}}}}
        }
    }
    public static Dictionary<string,object> Run(string helper,string assembly,string childExecutable,bool expectCrossProcessSuccess){
        Need(!helper.Contains("\"")&&!assembly.Contains("\"")&&!childExecutable.Contains("\""),"INVALID_GENERATED_PATH");
        IDataObject old=Clipboard.GetDataObject();Need(old==null||old.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");uint ownedClipboard=GetClipboardSequenceNumber();
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();Dictionary<string,object> report=new Dictionary<string,object>{{"ok",false},{"cases",cases},{"requiredCases",2},{"expectCrossProcessSuccess",expectCrossProcessSuccess},{"generatedSourceOnly",true},{"actualWpsTested",false},{"actualApplicationTested",false},{"physicalWindowsTested",false},{"userContentRead",false},{"sourceFocusChangedByHelper",false},{"clipboardBackend","real-OS"}};
        SetProcessDpiAwarenessContext(new IntPtr(-4));SetThreadDpiAwarenessContext(new IntPtr(-4));
        using(Form source=new Form())using(Panel host=new Panel()){
            source.Text="Generated native focus host";source.StartPosition=FormStartPosition.Manual;source.Bounds=new Rectangle(25,40,700,230);host.Bounds=new Rectangle(10,20,660,130);source.Controls.Add(host);bool finished=false;source.FormClosing+=delegate(object sender,FormClosingEventArgs e){if(!finished)e.Cancel=true;};Thread worker=null;
            source.Shown+=delegate{IntPtr parent=source.Handle,hostHandle=host.Handle;uint parentProcess=(uint)Process.GetCurrentProcess().Id;worker=new Thread(delegate(){
                try{SetThreadDpiAwarenessContext(new IntPtr(-4));foreach(bool crossProcess in new bool[]{false,true}){
                    Dictionary<string,object> test=new Dictionary<string,object>{{"name",crossProcess?"cross-process-child-focus":"cross-thread-child-focus"},{"ok",false}};cases.Add(test);Process child=null;Thread childThread=null;IntPtr childHandle=IntPtr.Zero;Exception childFailure=null;using(ManualResetEvent ready=new ManualResetEvent(false)){
                        try{
                            if(crossProcess){ProcessStartInfo start=new ProcessStartInfo(childExecutable,hostHandle.ToInt64()+" "+parentProcess);start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;child=Process.Start(start);Task<string> first=child.StandardOutput.ReadLineAsync();Need(first.Wait(5000),"OWN_CHILD_READY_DEADLINE");long handle;Need(Int64.TryParse(first.Result,out handle)&&handle!=0,"OWN_CHILD_READY_INVALID");childHandle=new IntPtr(handle);}
                            else{childThread=new Thread(delegate(){try{WindowsSelectionNativeFocusChild.Run(hostHandle,parentProcess,delegate(IntPtr value){childHandle=value;ready.Set();});}catch(Exception e){childFailure=e;ready.Set();}});childThread.SetApartmentState(ApartmentState.STA);childThread.Start();Need(ready.WaitOne(5000)&&childFailure==null&&childHandle!=IntPtr.Zero,"OWN_THREAD_CHILD_READY_FAILED");}
                            uint actualChildProcess;GetWindowThreadProcessId(childHandle,out actualChildProcess);Need(actualChildProcess==(crossProcess?(uint)child.Id:parentProcess),"OWN_CHILD_PROCESS_MISMATCH");Need(GetAncestor(childHandle,2)==parent,"OWN_CHILD_ROOT_MISMATCH");
                            Ui(source,delegate{source.Activate();SetForegroundWindow(parent);});POINT point=new POINT{x=40,y=40};Need(ClientToScreen(childHandle,ref point)&&SetCursorPos(point.x,point.y),"OWN_CHILD_POINTER_SETUP_FAILED");INPUT down=new INPUT(),up=new INPUT();down.data.mouse.flags=2;up.data.mouse.flags=4;Send(down,up);
                            Wait(delegate{return GetForegroundWindow()==parent&&Convert.ToBoolean(Context(parent,childHandle)["gtiFocusIsExpectedChild"]);},3000,"OWN_CHILD_ACTUAL_FOCUS");
                            SendMessageW(childHandle,0xb1,new IntPtr(7),new IntPtr(7+WindowsSelectionNativeFocusChild.Selected.Length));test["nativeContextBeforeManualCopy"]=Context(parent,childHandle);
                            Seed();ownedClipboard=GetClipboardSequenceNumber();uint initial=ownedClipboard;Send(Key(0x11,false),Key(0x43,false),Key(0x43,true),Key(0x11,true));
                            Wait(delegate{return GetClipboardSequenceNumber()!=initial&&Clipboard.ContainsText()&&Clipboard.GetText(TextDataFormat.UnicodeText)==WindowsSelectionNativeFocusChild.Selected;},2500,"MANUAL_CTRL_C_EXACT_SELECTION");ownedClipboard=GetClipboardSequenceNumber();test["manualCtrlCExactSelection"]=true;
                            ClipboardSeed seed=Seed();ownedClipboard=GetClipboardSequenceNumber();Dictionary<string,object> before=Context(parent,childHandle);test["nativeContextBeforeHelper"]=before;Need(Convert.ToBoolean(before["foregroundIsParent"])&&Convert.ToBoolean(before["gtiFocusIsExpectedChild"])&&Convert.ToBoolean(before["focusRootMatchesForeground"]),"OWN_CURRENT_SOURCE_CONTEXT_INVALID");Need(Convert.ToBoolean(before["focusProcessMatchesForeground"])!=crossProcess,"OWN_CROSS_PROCESS_TOPOLOGY_NOT_PROVEN");
                            Dictionary<string,object> reply=Call(helper,assembly);bool success=Convert.ToBoolean(reply["ok"]);test["helperOk"]=success;test["nativeBackend"]=reply.ContainsKey("nativeBackend")?reply["nativeBackend"]:null;Need(Convert.ToString(test["nativeBackend"])=="precompiled-framework-dll","EXACT_PRECOMPILED_NATIVE_BACKEND_REQUIRED");
                            Dictionary<string,object> health=(Dictionary<string,object>)reply["captureHealth"];Dictionary<string,object> scalars=new Dictionary<string,object>();foreach(KeyValuePair<string,object> field in health)if(field.Key.StartsWith("copy")||field.Key=="selectionQueryCount")scalars[field.Key]=field.Value;test["nativeHealth"]=scalars;
                            if(reply.ContainsKey("error")){string error=Convert.ToString(reply["error"]);int colon=error.IndexOf(':');test["errorClass"]=colon<0?"OTHER":error.Substring(0,colon);}
                            bool expected=!crossProcess||expectCrossProcessSuccess;Need(success==expected,"COPY_CONTEXT_EXPECTATION_MISMATCH");if(success)Need(Convert.ToString(reply["text"])==WindowsSelectionNativeFocusChild.Selected,"HELPER_SELECTION_NOT_EXACT");else{Need(Convert.ToInt64(health["copyPhase"])==1&&Convert.ToInt64(health["copyNativeContextValid"])==0&&Convert.ToInt64(health["copyDispatchInserted"])==0,"BASELINE_WAS_NOT_INITIAL_NATIVE_CONTEXT_REJECTION");Need(Convert.ToInt64(health["copyNativeInvalidReason"])==10&&Convert.ToInt64(health["copyNativeGtiSucceeded"])==1&&Convert.ToInt64(health["copyNativeFocusPresent"])==1&&Convert.ToInt64(health["copyNativeFocusProcessMatchesForeground"])==0&&Convert.ToInt64(health["copyNativeFocusRootMatchesForeground"])==1,"BASELINE_DIFFERENT_PROCESS_SAME_ROOT_BRANCH_NOT_PROVEN");test["baselineRejectsValidCrossProcessFocus"]=true;}
                            CheckSeed(seed);ownedClipboard=GetClipboardSequenceNumber();test["richClipboardPreserved"]=true;Dictionary<string,object> after=Context(parent,childHandle);test["sourceFocusPreserved"]=Convert.ToBoolean(after["foregroundIsParent"])&&Convert.ToBoolean(after["gtiFocusIsExpectedChild"]);Need(Convert.ToBoolean(test["sourceFocusPreserved"]),"HELPER_CHANGED_SOURCE_FOCUS");test["ok"]=true;
                        }finally{
                            if(childHandle!=IntPtr.Zero)PostMessageW(childHandle,0x10,IntPtr.Zero,IntPtr.Zero);
                            if(child!=null){if(!child.WaitForExit(3000)){child.Kill();Need(child.WaitForExit(2000),"OWN_CHILD_PROCESS_STOP_FAILED");test["forcedChildCleanup"]=true;}child.Dispose();}
                            if(childThread!=null)Need(childThread.Join(3000),"OWN_CHILD_THREAD_STOP_FAILED");
                        }
                    }
                }report["ok"]=true;}catch(Exception error){report["error"]=error.Message;if(cases.Count>0)cases[cases.Count-1]["error"]=error.Message;}finally{if(GetClipboardSequenceNumber()==ownedClipboard)Clipboard.Clear();Ui(source,delegate{finished=true;source.Close();});}
            });worker.SetApartmentState(ApartmentState.STA);worker.Start();};Application.Run(source);if(worker!=null)Need(worker.Join(5000),"OWN_FOCUS_FIXTURE_WORKER_REMAINED");
        }report["executedCases"]=cases.Count;report["passedCases"]=cases.FindAll(delegate(Dictionary<string,object> row){return Convert.ToBoolean(row["ok"]);}).Count;return report;
    }
}
