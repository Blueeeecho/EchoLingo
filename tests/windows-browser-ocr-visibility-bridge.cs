// Generated loopback OCR page only. Source-browser UIA is never queried.
// The app UIA source read starts only after its first native presentation.
using System;
using System.Collections;
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

public static class WindowsBrowserOcrVisibilityBridge {
    const string ExpectedSource="EchoLingo OCR visibility 2468";
    delegate bool EnumWindow(IntPtr window,IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out RECT rectangle);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int capacity);
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,INPUT[] input,int size);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid id,uint flags,IntPtr token,out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr memory);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string path,IntPtr security);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint process);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool Process32First(IntPtr snapshot,ref PROCESSENTRY entry);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool Process32Next(IntPtr snapshot,ref PROCESSENTRY entry);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct PROCESSENTRY {public uint size,usage,pid;public UIntPtr heap;public uint module,threads,parent;public int priority;public uint flags;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]public string executable;}
    [StructLayout(LayoutKind.Sequential)] struct RECT {public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)] struct POINT {public int x,y;}
    [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort key,scan;public uint flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Explicit)] struct INPUTDATA {[FieldOffset(0)]public KEY key;[FieldOffset(0)]public MOUSE mouse;}
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public INPUTDATA data;}
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=1048576};
    static string Browser,Stage="startup";static AppSession HostedApplication;
    static IntPtr boundRoot;static int boundPid;static uint boundThread;static bool caseAttempted,clickAttempted,ocrCompleted;
    static Dictionary<string,object> Current;
    static void Need(bool value,string error){if(!value)throw new InvalidOperationException(error);}
    static string WindowId(IntPtr window){return "0x"+window.ToInt64().ToString("X");}
    static void Reply(object value){Console.WriteLine(Json.Serialize(value));Console.Out.Flush();}
    static string ClassName(IntPtr window){StringBuilder name=new StringBuilder(256);GetClassName(window,name,name.Capacity);return name.ToString();}
    static Dictionary<string,object> NativeIdentity(IntPtr window){uint pid;uint thread=GetWindowThreadProcessId(window,out pid);return new Dictionary<string,object>{{"hwnd",WindowId(window)},{"processId",pid},{"threadId",thread},{"class",ClassName(window)},{"rootHwnd",WindowId(GetAncestor(window,2))},{"visible",IsWindowVisible(window)}};}
    static IntPtr BrowserRoot(int pid){
        using(Process process=Process.GetProcessById(pid))Need(String.Equals(Path.GetFullPath(process.MainModule.FileName),Browser,StringComparison.OrdinalIgnoreCase),"BROWSER_EXECUTABLE_MISMATCH");
        List<IntPtr> roots=new List<IntPtr>();EnumWindows(delegate(IntPtr w,IntPtr ignored){uint owner;GetWindowThreadProcessId(w,out owner);if(owner==pid&&GetAncestor(w,2)==w&&IsWindowVisible(w)&&ClassName(w)=="Chrome_WidgetWin_1")roots.Add(w);return true;},IntPtr.Zero);
        if(boundRoot==IntPtr.Zero){Need(roots.Count==1,"BROWSER_ROOT_NOT_UNIQUE");boundRoot=roots[0];boundPid=pid;uint owner;boundThread=GetWindowThreadProcessId(boundRoot,out owner);}
        uint currentPid;uint thread=GetWindowThreadProcessId(boundRoot,out currentPid);Need(boundPid==pid&&currentPid==pid&&thread==boundThread&&IsWindow(boundRoot)&&GetAncestor(boundRoot,2)==boundRoot&&ClassName(boundRoot)=="Chrome_WidgetWin_1"&&IsWindowVisible(boundRoot),"BOUND_BROWSER_ROOT_CHANGED");return boundRoot;
    }
    static void SourceForeground(IntPtr root){Need(GetForegroundWindow()==root,"SOURCE_BROWSER_FOREGROUND_CHANGED");}
    static void InputsReleased(){foreach(int key in new int[]{1,2,0x10,0x11,0x12,0x5B,0x5C})Need((GetAsyncKeyState(key)&0x8000)==0,"INPUT_ALREADY_HELD");}
    static POINT Point(Dictionary<string,object> command,string x,string y){POINT p=new POINT();p.x=Convert.ToInt32(command[x]);p.y=Convert.ToInt32(command[y]);int l=GetSystemMetrics(76),t=GetSystemMetrics(77),w=GetSystemMetrics(78),h=GetSystemMetrics(79);Need(w>1&&h>1&&p.x>=l&&p.x<l+w&&p.y>=t&&p.y<t+h,"GENERATED_POINT_OUTSIDE_VIRTUAL_DESKTOP");return p;}
    static void PointHitsRoot(POINT p,IntPtr root){Need(GetAncestor(WindowFromPoint(p),2)==root,"GENERATED_POINT_NOT_BOUND_BROWSER");}
    static Dictionary<string,object> MousePoint(Dictionary<string,object> command){IntPtr root=BrowserRoot(Convert.ToInt32(command["browserPid"]));SourceForeground(root);InputsReleased();POINT p=Point(command,"x","y");Need(SetCursorPos(p.x+1,p.y)&&SetCursorPos(p.x,p.y),"NATIVE_POINTER_MOVE_FAILED");PointHitsRoot(p,root);return new Dictionary<string,object>{{"ok",true},{"sourceRoot",NativeIdentity(root)},{"sourceUiaCalls",0},{"nativePointerMoved",true}};}
    static uint ParentProcess(uint pid){IntPtr snapshot=CreateToolhelp32Snapshot(2,0);Need(snapshot!=new IntPtr(-1),"PROCESS_SNAPSHOT_FAILED");try{PROCESSENTRY e=new PROCESSENTRY();e.size=(uint)Marshal.SizeOf(typeof(PROCESSENTRY));if(Process32First(snapshot,ref e))do{if(e.pid==pid)return e.parent;}while(Process32Next(snapshot,ref e));return 0;}finally{CloseHandle(snapshot);}}
    static INPUT Key(ushort key,bool up){INPUT i=new INPUT();i.type=1;i.data.key.key=key;i.data.key.flags=up?2U:0U;return i;}
    static INPUT Mouse(uint flags){INPUT i=new INPUT();i.type=0;i.data.mouse.flags=flags;return i;}
    static void Wait(Func<bool> condition,int ms,string error){Stopwatch watch=Stopwatch.StartNew();while(watch.ElapsedMilliseconds<ms){if(condition())return;Application.DoEvents();Thread.Sleep(10);}throw new InvalidOperationException(error);}
    sealed class AppSession {
        const string Identifier="io.github.blueeeecho.echolingo",Marker=".echolingo-browser-ocr-app-owned";
        readonly string token=Guid.NewGuid().ToString("N"),provider;readonly List<string> owned=new List<string>();
        readonly AutoResetEvent wake=new AutoResetEvent(false);readonly object uiGate=new object();Thread uiThread;Action pending;volatile bool uiStop,uiPoisoned;bool closed;
        Process app;IntPtr main;string history;Dictionary<string,object> cleanup;
        public readonly Dictionary<string,object> Identity;
        static string Folder(string id){Guid guid=new Guid(id);IntPtr p;Need(SHGetKnownFolderPath(ref guid,0,IntPtr.Zero,out p)==0,"APP_KNOWN_FOLDER_FAILED");try{return Marshal.PtrToStringUni(p);}finally{CoTaskMemFree(p);}}
        void Claim(string p){Need(CreateDirectory(p,IntPtr.Zero),"EXISTING_APP_DATA_REFUSED");owned.Add(p);File.WriteAllText(Path.Combine(p,Marker),token,new UTF8Encoding(false));}
        void CheckRoot(string p){Need(Directory.Exists(p)&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(p,Marker))==token,"APP_DIRECTORY_OWNERSHIP_CHANGED");}
        void NoLinks(string p){Need((File.GetAttributes(p)&FileAttributes.ReparsePoint)==0,"APP_DATA_REPARSE_POINT");foreach(string child in Directory.GetFileSystemEntries(p)){try{Need((File.GetAttributes(child)&FileAttributes.ReparsePoint)==0,"APP_DATA_REPARSE_POINT");if(Directory.Exists(child))NoLinks(child);}catch(FileNotFoundException){if(File.Exists(child)||Directory.Exists(child))throw;}catch(DirectoryNotFoundException){if(File.Exists(child)||Directory.Exists(child))throw;}}}
        void DeleteOwn(string p){if(!Directory.Exists(p))return;CheckRoot(p);Stopwatch elapsed=Stopwatch.StartNew();bool deleting=false;while(true){try{Need((File.GetAttributes(p)&FileAttributes.ReparsePoint)==0,"APP_ROOT_REPARSE_POINT");NoLinks(p);deleting=true;Directory.Delete(p,true);return;}catch(IOException){if(!Directory.Exists(p))return;if(elapsed.ElapsedMilliseconds>=5000)throw;}catch(UnauthorizedAccessException){if(elapsed.ElapsedMilliseconds>=5000)throw;}if(!deleting)CheckRoot(p);Thread.Sleep((int)Math.Min(20,Math.Max(1,5000-elapsed.ElapsedMilliseconds)));}}
        IntPtr OwnMain(){List<IntPtr> found=new List<IntPtr>();EnumWindows(delegate(IntPtr w,IntPtr ignored){uint pid;GetWindowThreadProcessId(w,out pid);if(pid==app.Id&&GetAncestor(w,2)==w){StringBuilder c=new StringBuilder(128);GetClassName(w,c,c.Capacity);if(c.ToString()=="Tauri Window")found.Add(w);}return true;},IntPtr.Zero);Need(found.Count<=1,"APP_MAIN_NOT_UNIQUE");return found.Count==1?found[0]:IntPtr.Zero;}
        bool NativeReady(){int hotkeys=0,trays=0;EnumWindows(delegate(IntPtr w,IntPtr ignored){uint pid;GetWindowThreadProcessId(w,out pid);if(pid==app.Id){StringBuilder c=new StringBuilder(128);GetClassName(w,c,c.Capacity);if(c.ToString()=="global_hotkey_app")hotkeys++;if(c.ToString()=="tray_icon_app")trays++;}return true;},IntPtr.Zero);return hotkeys>0&&trays>0;}
        static void WaitNative(Func<bool> condition,int ms,string error){Stopwatch s=Stopwatch.StartNew();while(s.ElapsedMilliseconds<ms){if(condition())return;Thread.Sleep(10);}throw new InvalidOperationException(error);}
        public AppSession(string executable,string mockUrl,string providerId,string hash,long bytes){
            provider=providerId;Need(provider.StartsWith("generated-browser-",StringComparison.Ordinal)&&provider.Length<=100,"APP_PROVIDER_NOT_GENERATED");Uri endpoint;Need(Uri.TryCreate(mockUrl,UriKind.Absolute,out endpoint)&&endpoint.Scheme=="http"&&endpoint.Host=="127.0.0.1"&&endpoint.Port>1024&&endpoint.AbsolutePath=="/","APP_MOCK_NOT_LOOPBACK");
            Need(new FileInfo(executable).Length==bytes,"APP_BYTES_CHANGED_BEFORE_START");
            using(var input=File.OpenRead(executable))using(var sha=System.Security.Cryptography.SHA256.Create())Need(BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant()==hash,"APP_HASH_CHANGED_BEFORE_START");
            Identity=new Dictionary<string,object>{{"applicationSha256",hash},{"applicationBytes",bytes},{"actualApplicationTested",true},{"shortcutUnderTest","Alt+S"},{"fakeIpcUsed",false},{"translationBackend","generated-loopback-mock"},{"credentialScope","One random absent provider ID only; no existing credential account"},{"nativeReadinessIsOsRegistrationProof",false},{"fixedFrontendWarmupMilliseconds",0},{"preHotkeyAppUiaCalls",0}};
            try{
                foreach(Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))using(p)Need(p.HasExited,"EXISTING_APP_PROCESS_REFUSED");
                string roaming=Path.Combine(Folder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"),Identifier),local=Path.Combine(Folder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"),Identifier),root=Path.Combine(Path.GetTempPath(),"echolingo-browser-ocr-app-"+token);
                Claim(roaming);Claim(local);Claim(root);history=Path.Combine(roaming,"history.json");
                var settings=new Dictionary<string,object>{{"providers",new object[]{new Dictionary<string,object>{{"id",provider},{"name","Generated browser loopback mock"},{"kind","libretranslate"},{"baseUrl",mockUrl},{"requiresApiKey",false},{"enabled",true},{"model",""},{"prompt",""}}}},{"ocrProviders",new object[0]},{"activeOcrProviderId",null},{"sourceLanguage","auto"},{"targetLanguage","auto"},{"languageDirectionVersion",1},{"shortcutDefaultsVersion",1},{"saveHistory",true},{"maxHistory",100},{"theme","light"},{"autoHideSeconds",0},{"shortcuts",new Dictionary<string,object>{{"selection",""},{"silentOcr","Alt+S"},{"ocr",""},{"capture",""},{"input",""}}}};
                File.WriteAllText(Path.Combine(roaming,"settings.json"),Json.Serialize(settings),new UTF8Encoding(false));
                ProcessStartInfo start=new ProcessStartInfo(executable);start.UseShellExecute=false;start.CreateNoWindow=true;string temp=Path.Combine(root,"Temp");Directory.CreateDirectory(temp);start.EnvironmentVariables["TEMP"]=temp;start.EnvironmentVariables["TMP"]=temp;start.EnvironmentVariables["LOCALAPPDATA"]=local;start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"]=Path.Combine(local,"webview-browser-ocr-fixture");app=Process.Start(start);Need(app.WaitForInputIdle(15000),"APP_NATIVE_INPUT_IDLE_DEADLINE");
                WaitNative(delegate{Need(!app.HasExited,"APP_EXITED_BEFORE_NATIVE_MAIN");main=OwnMain();return main!=IntPtr.Zero;},20000,"APP_NATIVE_MAIN_DEADLINE");WaitNative(NativeReady,15000,"APP_HOTKEY_HOST_AND_TRAY_DEADLINE");Need(!IsWindowVisible(main),"APP_DID_NOT_START_SILENTLY");Identity["applicationProcessId"]=app.Id;Identity["mainHwnd"]=WindowId(main);
                uiThread=new Thread(delegate(){while(true){wake.WaitOne();Action next;lock(uiGate){next=pending;pending=null;}if(next!=null)next();if(uiStop)return;}});uiThread.IsBackground=true;uiThread.SetApartmentState(ApartmentState.MTA);uiThread.Start();
            }catch{Close();throw;}
        }
        public IntPtr Main {get{Need(OwnMain()==main,"APP_MAIN_IDENTITY_CHANGED");return main;}}
        public bool Visible {get{return IsWindowVisible(Main);}}
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
        public int HistoryCount(string expected,string translation){CheckRoot(Path.GetDirectoryName(history));if(!File.Exists(history))return 0;Need(new FileInfo(history).Length<=1048576,"APP_HISTORY_BOUND");try{object[] rows=Json.Deserialize<object[]>(File.ReadAllText(history));Need(rows.Length<=100,"APP_HISTORY_COUNT_BOUND");int count=0;foreach(object item in rows){var row=(Dictionary<string,object>)item;if(!String.Equals(Convert.ToString(row["text"]),expected,StringComparison.OrdinalIgnoreCase))continue;foreach(object raw in (IEnumerable)row["results"]){var r=(Dictionary<string,object>)raw;if(Convert.ToString(r["providerId"])==provider&&!r.ContainsKey("error")&&Convert.ToString(r["text"])==translation){count++;break;}}}return count;}catch(IOException){return 0;}catch(ArgumentException){return 0;}}
        public Dictionary<string,object> Close(){
            if(closed)return cleanup;closed=true;cleanup=new Dictionary<string,object>{{"ok",false},{"method","owned-process-tree-termination"},{"completeDescendantEnumeration",false}};List<string> errors=new List<string>();
            try{if(app!=null){if(!app.HasExited){ProcessStartInfo start=new ProcessStartInfo("taskkill.exe","/PID "+app.Id+" /T /F");start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;using(Process p=Process.Start(start)){Task<string> o=p.StandardOutput.ReadToEndAsync(),e=p.StandardError.ReadToEndAsync();Need(p.WaitForExit(5000),"OWN_APP_TREE_KILL_DEADLINE");Need(Task.WaitAll(new Task[]{o,e},1000),"OWN_APP_KILL_PIPE_DEADLINE");}}Need(app.WaitForExit(5000),"OWN_APP_NOT_EXITED");cleanup["ownAppExited"]=true;app.Dispose();}}catch(Exception e){errors.Add(e.GetType().Name+":"+e.Message);}
            try{uiStop=true;wake.Set();if(uiThread!=null)Need(uiThread.Join(2000),"OWN_APP_UIA_WORKER_NOT_STOPPED");}catch(Exception e){errors.Add(e.GetType().Name+":"+e.Message);}
            for(int i=owned.Count-1;i>=0;i--)try{DeleteOwn(owned[i]);}catch(Exception e){errors.Add(e.GetType().Name+":"+e.Message);}
            cleanup["errors"]=errors;cleanup["ownedDirectoriesRemoved"]=errors.Count==0;cleanup["ok"]=errors.Count==0;return cleanup;
        }
    }
    static Dictionary<string,object> OcrCase(Dictionary<string,object> command){
        Need(!caseAttempted,"ONE_OCR_CASE_ONLY");caseAttempted=true;Current=new Dictionary<string,object>{{"ok",false},{"actualShortcutPresses",0},{"dragPairsSent",0},{"outsideClickPairsSent",0},{"sourceUiaCalls",0},{"preHotkeyAppUiaCalls",0},{"fakeIpcUsed",false},{"ocrBackend","actual packaged WinRT local OCR"}};
        Stage="roi-preparation";IntPtr root=BrowserRoot(Convert.ToInt32(command["browserPid"]));SourceForeground(root);InputsReleased();Need(!HostedApplication.Visible,"POPUP_NOT_HIDDEN_BASELINE");POINT first=Point(command,"x","y"),last=Point(command,"endX","endY");PointHitsRoot(first,root);PointHitsRoot(last,root);Need(last.x-first.x>=300&&last.x-first.x<=1400&&last.y-first.y>=70&&last.y-first.y<=250,"GENERATED_ROI_SIZE_BOUND");for(int row=0;row<=3;row++)for(int column=0;column<=3;column++){POINT sample=new POINT();sample.x=first.x+(last.x-first.x)*column/3;sample.y=first.y+(last.y-first.y)*row/3;PointHitsRoot(sample,root);}Need(SetCursorPos(first.x,first.y),"OCR_START_POINTER_FAILED");
        string translation=Convert.ToString(command["expectedTranslation"]);Need(translation.StartsWith("Generated OCR mock ",StringComparison.Ordinal)&&translation.Length<=150,"GENERATED_TRANSLATION_REQUIRED");int before=HostedApplication.HistoryCount(ExpectedSource,translation);Need(before==0,"NEW_HISTORY_BASELINE_REQUIRED");Current["historyExactCountBefore"]=before;Current["sourceRoot"]=NativeIdentity(root);
        Stage="actual-alt-s-once";Stopwatch hotkey=Stopwatch.StartNew();Current["actualShortcutPresses"]=1;uint inserted=SendInput(4,new INPUT[]{Key(0x12,false),Key(0x53,false),Key(0x53,true),Key(0x12,true)},Marshal.SizeOf(typeof(INPUT)));Current["insertedHotkeyEvents"]=inserted;if(inserted!=4){SendInput(2,new INPUT[]{Key(0x53,true),Key(0x12,true)},Marshal.SizeOf(typeof(INPUT)));throw new InvalidOperationException("ALT_S_INPUT_REJECTED_NO_RETRY");}
        Stage="actual-ocr-input-plane";IntPtr plane=IntPtr.Zero;uint helper=0;Wait(delegate{SourceForeground(root);IntPtr candidate=WindowFromPoint(first);uint owner;GetWindowThreadProcessId(candidate,out owner);if(ClassName(candidate)!="EchoLingoCaptureInputPlane-"+owner)return false;Need(owner!=HostedApplication.Pid&&ParentProcess(owner)==HostedApplication.Pid,"OCR_PLANE_NOT_DIRECT_CHILD_OF_STARTED_APP");plane=candidate;helper=owner;return true;},25000,"ALT_S_INPUT_PLANE_DEADLINE");
        Current["inputPlane"]=NativeIdentity(plane);Current["helperProcessId"]=helper;Current["helperParentProcessId"]=HostedApplication.Pid;Current["inputPlaneDirectChildVerified"]=true;Current["hotkeyToInputPlaneMilliseconds"]=hotkey.Elapsed.TotalMilliseconds;SourceForeground(root);Need(GetAncestor(WindowFromPoint(last),2)==GetAncestor(plane,2),"ROI_END_NOT_SAME_INPUT_PLANE");
        Stage="actual-left-roi-drag-release";INPUT down=Mouse(2),up=Mouse(4);bool held=false;try{uint sent=SendInput(1,new INPUT[]{down},Marshal.SizeOf(typeof(INPUT)));Need(sent==1,"ROI_LEFT_DOWN_REJECTED");held=true;Current["dragPairsSent"]=1;for(int step=1;step<=8;step++){SourceForeground(root);Need(SetCursorPos(first.x+(last.x-first.x)*step/8,first.y+(last.y-first.y)*step/8),"ROI_NATIVE_MOVE_FAILED");Thread.Sleep(15);}INPUT move=Mouse(0x8000|0x4000|1);move.data.mouse.x=(int)Math.Round((last.x-GetSystemMetrics(76))*65535.0/(GetSystemMetrics(78)-1));move.data.mouse.y=(int)Math.Round((last.y-GetSystemMetrics(77))*65535.0/(GetSystemMetrics(79)-1));uint final=SendInput(2,new INPUT[]{move,up},Marshal.SizeOf(typeof(INPUT)));Need(final==2,"ROI_FINAL_MOVE_UP_REJECTED_NO_RETRY");held=false;}finally{if(held)SendInput(1,new INPUT[]{up},Marshal.SizeOf(typeof(INPUT)));}
        Wait(delegate{return (GetAsyncKeyState(1)&0x8000)==0;},1000,"ROI_LEFT_RELEASE_NOT_OBSERVED");Current["nativeLeftReleased"]=true;Current["sourceForegroundPreservedThroughRoi"]=GetForegroundWindow()==root;
        Stage="actual-winrt-source-new-history";Stopwatch completion=Stopwatch.StartNew();bool exact=false;while(completion.ElapsedMilliseconds<50000){SourceForeground(root);Current["popupNativeVisible"]=HostedApplication.Visible;if(HostedApplication.Visible){try{var source=HostedApplication.ReadSource((int)Math.Max(1,50000-completion.ElapsedMilliseconds));string value=source["value"] as string;Current["sourceEditorVisibleCount"]=source["sourceEditorVisibleCount"];Current["actualSourceLength"]=value==null?-1:value.Length;bool match=String.Equals(value,ExpectedSource,StringComparison.OrdinalIgnoreCase);Current["actualWinRtSourceMatched"]=match;int after=HostedApplication.HistoryCount(ExpectedSource,translation);Current["historyExactCountAfter"]=after;if(match&&after==before+1){exact=true;break;}}catch(ElementNotAvailableException){Current["staleAppReadObserved"]=true;}}Application.DoEvents();Thread.Sleep(10);}
        Need(exact,"WINRT_EXACT_SOURCE_AND_NEW_HISTORY_DEADLINE");Need(!IsWindowVisible(plane),"OCR_INPUT_PLANE_STILL_VISIBLE");InputsReleased();SourceForeground(root);Need(BrowserRoot(Convert.ToInt32(command["browserPid"]))==root,"SOURCE_ROOT_CHANGED");Current["ocrCompletedMilliseconds"]=completion.Elapsed.TotalMilliseconds;Current["sourceForegroundPreserved"]=true;ocrCompleted=true;Current["ok"]=true;Current["ocrCompleted"]=true;Current["pinWasNeverToggled"]=true;Current["freshDefaultPinStateUnderTest"]="unpinned";return Current;
    }
    static Dictionary<string,object> OutsideClick(Dictionary<string,object> command){
        Need(caseAttempted&&!clickAttempted&&ocrCompleted,"OUTSIDE_CLICK_REQUIRES_COMPLETED_OCR");clickAttempted=true;Current=new Dictionary<string,object>{{"ok",false},{"outsideClickPairsSent",0},{"actualShortcutPresses",0},{"ocrAlreadyCompleted",true}};Stage="same-source-click-preparation";IntPtr root=BrowserRoot(Convert.ToInt32(command["browserPid"]));SourceForeground(root);InputsReleased();Need(HostedApplication.Visible,"POPUP_ALREADY_HIDDEN_BEFORE_CLICK");POINT p=Point(command,"x","y");Need(SetCursorPos(p.x,p.y),"OUTSIDE_CLICK_POINTER_FAILED");PointHitsRoot(p,root);RECT bounds;Need(GetWindowRect(HostedApplication.Main,out bounds),"POPUP_BOUNDS_UNAVAILABLE");Need(p.x<bounds.Left||p.x>=bounds.Right||p.y<bounds.Top||p.y>=bounds.Bottom,"BLANK_POINT_INSIDE_POPUP");Current["sourceRoot"]=NativeIdentity(root);Current["popupVisibleBeforeClick"]=true;
        Stage="same-source-one-blank-click";Stopwatch elapsed=Stopwatch.StartNew();Current["outsideClickPairsSent"]=1;uint sent=SendInput(2,new INPUT[]{Mouse(2),Mouse(4)},Marshal.SizeOf(typeof(INPUT)));if(sent!=2){if(sent>0)SendInput(1,new INPUT[]{Mouse(4)},Marshal.SizeOf(typeof(INPUT)));throw new InvalidOperationException("OUTSIDE_CLICK_INPUT_REJECTED_NO_RETRY");}
        Wait(delegate{SourceForeground(root);return !HostedApplication.Visible;},2000,"ONE_SAME_BROWSER_BLANK_CLICK_DID_NOT_HIDE_POPUP");InputsReleased();Need(BrowserRoot(Convert.ToInt32(command["browserPid"]))==root,"SOURCE_ROOT_CHANGED_AFTER_CLICK");Current["hideObservedMilliseconds"]=elapsed.Elapsed.TotalMilliseconds;Current["popupHidden"]=true;Current["sourceForegroundPreserved"]=true;Current["ok"]=true;return Current;
    }
    public static void Run(string browser,string application,string mockUrl,string provider,string hash,long bytes){
        Browser=Path.GetFullPath(browser);try{SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"PHYSICAL_MOUSE_COORDINATES_REQUIRED");HostedApplication=new AppSession(application,mockUrl,provider,hash,bytes);Reply(new Dictionary<string,object>{{"ready",true},{"bridgeProcessId",Process.GetCurrentProcess().Id},{"application",HostedApplication.Identity},{"sourceUiaCalls",0},{"clipboardReads",0}});string line;while((line=Console.ReadLine())!=null){Need(line.Length<=4096,"BRIDGE_COMMAND_BOUND");var command=Json.Deserialize<Dictionary<string,object>>(line.TrimStart('\ufeff'));string op=Convert.ToString(command["op"]);if(op=="close"){var cleanup=HostedApplication.Close();Reply(new Dictionary<string,object>{{"ok",cleanup["ok"]},{"closing",true},{"applicationCleanup",cleanup}});return;}try{if(op=="mouse-point"){Stage="native-pointer-preparation";Reply(MousePoint(command));}else if(op=="ocr-case")Reply(OcrCase(command));else if(op=="outside-click")Reply(OutsideClick(command));else throw new InvalidOperationException("UNSUPPORTED_BRIDGE_COMMAND");}catch(Exception e){while(e.InnerException!=null)e=e.InnerException;var fail=Current==null?new Dictionary<string,object>():new Dictionary<string,object>(Current);fail["ok"]=false;fail["error"]=e.Message;fail["errorType"]=e.GetType().Name;fail["stage"]=Stage;fail["sourceForegroundNow"]=NativeIdentity(GetForegroundWindow());int shortcuts=fail.ContainsKey("actualShortcutPresses")?Convert.ToInt32(fail["actualShortcutPresses"]):0;bool clicked=fail.ContainsKey("outsideClickPairsSent")&&Convert.ToInt32(fail["outsideClickPairsSent"])>0;fail["failureClassification"]=clicked?"product-same-source-click":op=="outside-click"||(op=="mouse-point"&&ocrCompleted)?"outside-click-preparation":shortcuts==0?"roi-preparation-inconclusive":"product-ocr-path";fail["setupInconclusive"]=shortcuts==0&&!clicked&&op!="outside-click";Reply(fail);}}}finally{if(HostedApplication!=null)HostedApplication.Close();}
    }
}
