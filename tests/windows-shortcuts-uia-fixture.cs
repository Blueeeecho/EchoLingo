// Actual packaged settings UI. No CDP, fake IPC, credentials or source capture.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;

public static class EchoLingoShortcutsUiaFixture {
    const string Identifier = "io.github.blueeeecho.echolingo", Marker = ".shortcut-uia-owned";
    const string Selection = "选词翻译快捷键", Ocr = "无感 OCR快捷键", Record = "录制选词翻译快捷键", Save = "保存并立即生效";
    const int TotalMilliseconds = 180000, UiaCallMilliseconds = 5000;
    delegate bool EnumProc(IntPtr window, IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr unused);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint kind);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll",SetLastError=true)] static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string path, IntPtr security);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref JOBINFO info, uint size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, out JOBACCOUNTING info, uint size, out uint returned);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFileAttributes(string path);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct DATA { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public DATA data; }
    [StructLayout(LayoutKind.Sequential)] struct JOBLIMIT { public long processTime,jobTime; public uint flags; public UIntPtr minimum,maximum; public uint active; public UIntPtr affinity; public uint priority,scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct IOCOUNTERS { public ulong a,b,c,d,e,f; }
    [StructLayout(LayoutKind.Sequential)] struct JOBINFO { public JOBLIMIT basic; public IOCOUNTERS io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
    [StructLayout(LayoutKind.Sequential)] struct JOBACCOUNTING { public long totalUser,totalKernel,periodUser,periodKernel; public uint faults,total,active,terminated; }

    static void Need(bool value, string error) { if (!value) throw new InvalidOperationException(error); }
    sealed class UiWorker : IDisposable {
        readonly AutoResetEvent wake = new AutoResetEvent(false);
        readonly object gate = new object(); readonly Thread thread; readonly Action active; readonly Func<int> remaining;
        Action pending; int abandoned, closed;
        public UiWorker(Action check,Func<int> budget) {
            active=check; remaining=budget; thread=new Thread(delegate() { while (true) { wake.WaitOne(); Action next; lock(gate) { next=pending; pending=null; } if(next!=null) next(); if(Volatile.Read(ref closed)!=0) return; } });
            thread.IsBackground=true; thread.SetApartmentState(ApartmentState.MTA); thread.Start();
        }
        public void Check() { active(); Need(Volatile.Read(ref abandoned)==0,"UIA_WORKER_ABANDONED"); }
        public T Call<T>(Func<T> action) {
            Check(); T result=default(T); Exception failure=null;
            ManualResetEvent done=new ManualResetEvent(false);
            lock(gate) { Need(pending==null,"UIA_WORKER_BUSY"); pending=delegate { try { Check(); result=action(); Check(); } catch(Exception e) { failure=e; } finally { done.Set(); } }; }
            wake.Set();
            int wait=Math.Min(UiaCallMilliseconds,Math.Max(1,remaining()));
            if(!done.WaitOne(wait)) { Interlocked.Exchange(ref abandoned,1); throw new InvalidOperationException(wait<UiaCallMilliseconds?"FIXTURE_DEADLINE_180000MS":"UIA_CALL_DEADLINE_5000MS"); }
            done.Dispose(); if(failure!=null) throw failure; return result;
        }
        public void Dispose() { Interlocked.Exchange(ref abandoned,1); Interlocked.Exchange(ref closed,1); wake.Set(); Need(thread.Join(2000),"UIA_WORKER_NOT_STOPPED"); wake.Dispose(); }
    }
    sealed class Fixture {
        readonly string executable, token=Guid.NewGuid().ToString("N"); readonly Stopwatch watch=Stopwatch.StartNew();
        readonly List<string> owned=new List<string>(); readonly List<object> cases=new List<object>(), probes=new List<object>();
        readonly List<object> buttonPatterns=new List<object>(),jobStops=new List<object>();
        readonly List<string> cleanupErrors=new List<string>(); readonly JavaScriptSerializer json=new JavaScriptSerializer();
        readonly Dictionary<string,object> report=new Dictionary<string,object>();
        UiWorker ui; Process app; IntPtr job,main; string settingsPath,local,stage="claim-generated-data"; int keySends,valueWrites,launches;
        public Fixture(string path) { executable=path; }
        void Active() { Need(watch.ElapsedMilliseconds<TotalMilliseconds,"FIXTURE_DEADLINE_180000MS"); }
        void Wait(Func<bool> condition, int milliseconds, string error) {
            Stopwatch t=Stopwatch.StartNew(); do { Active(); if(condition()) return; Thread.Sleep(20); } while(t.ElapsedMilliseconds<milliseconds);
            throw new InvalidOperationException(error);
        }
        void Stage(string name) { Active(); stage=name; report["stage"]=stage; }
        void Passed(string name, long started) { cases.Add(new Dictionary<string,object>{{"name",name},{"passed",true},{"elapsedMilliseconds",watch.ElapsedMilliseconds-started}}); }
        void CheckRoot(string root) {
            Need(Directory.Exists(root)&&(File.GetAttributes(root)&FileAttributes.ReparsePoint)==0,"OWNED_DIRECTORY_CHANGED");
            Need(File.ReadAllText(Path.Combine(root,Marker))==token,"OWNED_MARKER_CHANGED");
        }
        void RejectLinks(string root) {
            Need((File.GetAttributes(root)&FileAttributes.ReparsePoint)==0,"OWNED_TREE_LINK");
            foreach(string path in Directory.GetFileSystemEntries(root)) {
                try { Need((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"OWNED_TREE_LINK"); if(Directory.Exists(path)) RejectLinks(path); }
                catch(FileNotFoundException) { if(!Missing(path)) throw; }
                catch(DirectoryNotFoundException) { if(!Missing(path)) throw; }
            }
        }
        bool Missing(string path) { uint attributes=GetFileAttributes(path); int error=Marshal.GetLastWin32Error();return attributes==UInt32.MaxValue&&(error==2||error==3); }
        void Clean(string root) {
            CheckRoot(root); bool destructiveStarted=false;Stopwatch cleanup=Stopwatch.StartNew();
            while(true) {
                if(Missing(root)) return;
                // After a partial recursive delete the marker itself may be
                // gone. Ownership was verified before that first delete;
                // keep checking root/reparse identity and any surviving marker.
                Need((File.GetAttributes(root)&FileAttributes.ReparsePoint)==0,"OWNED_DIRECTORY_CHANGED");
                string marker=Path.Combine(root,Marker);
                if(!Missing(marker)) Need(File.ReadAllText(marker)==token,"OWNED_MARKER_CHANGED");
                else Need(destructiveStarted,"OWNED_MARKER_CHANGED");
                try { RejectLinks(root);destructiveStarted=true;Directory.Delete(root,true);return; }
                catch(IOException) { if(Missing(root)) return;if(cleanup.ElapsedMilliseconds>=5000) throw; }
                catch(UnauthorizedAccessException) { if(cleanup.ElapsedMilliseconds>=5000) throw; }
                Thread.Sleep(50);
            }
        }
        void Claim(string root) { Need(CreateDirectory(root,IntPtr.Zero),"EXISTING_DATA_OR_CREATE_FAILURE"); owned.Add(root); File.WriteAllText(Path.Combine(root,Marker),token,new UTF8Encoding(false)); }
        IntPtr Main() {
            Need(app!=null&&!app.HasExited,"OWN_APP_EXITED"); List<IntPtr> found=new List<IntPtr>();
            EnumWindows(delegate(IntPtr w,IntPtr unused) { uint pid; GetWindowThreadProcessId(w,out pid); StringBuilder name=new StringBuilder(256); GetClassName(w,name,name.Capacity); if(pid==app.Id&&GetAncestor(w,2)==w&&name.ToString()=="Tauri Window"&&IsWindowVisible(w)) found.Add(w); return true; },IntPtr.Zero);
            Need(found.Count<=1,"OWN_MAIN_NOT_UNIQUE"); return found.Count==1?found[0]:IntPtr.Zero;
        }
        void OwnMain() { Active(); Need(main!=IntPtr.Zero&&Main()==main,"OWN_MAIN_IDENTITY_CHANGED"); }
        AutomationElement Find(string name, ControlType type) {
            ui.Check(); OwnMain(); AutomationElement root=AutomationElement.FromHandle(main); ui.Check();
            AutomationElementCollection all=root.FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.NameProperty,name),new PropertyCondition(AutomationElement.ControlTypeProperty,type))); ui.Check();
            Need(all.Count<=16,"UIA_TARGET_NOT_BOUNDED"); AutomationElement result=null;
            for(int i=0;i<all.Count;i++) { bool offscreen=all[i].Current.IsOffscreen; ui.Check(); if(!offscreen) { Need(result==null,"UIA_TARGET_NOT_UNIQUE"); result=all[i]; } }
            return result;
        }
        string Field(string name) { return ui.Call(delegate { AutomationElement e=Find(name,ControlType.Edit); Need(e!=null,"SHORTCUT_FIELD_NOT_VISIBLE"); object p; Need(e.TryGetCurrentPattern(ValuePattern.Pattern,out p),"SHORTCUT_VALUE_PATTERN_MISSING"); ui.Check(); string v=((ValuePattern)p).Current.Value; ui.Check(); return v; }); }
        bool FieldsVisible() { return ui.Call(delegate { return Find(Selection,ControlType.Edit)!=null&&Find(Ocr,ControlType.Edit)!=null; }); }
        void Fill(string name,string value) { ui.Call(delegate { AutomationElement e=Find(name,ControlType.Edit); Need(e!=null,"SHORTCUT_FIELD_NOT_VISIBLE"); object p; Need(e.TryGetCurrentPattern(ValuePattern.Pattern,out p),"SHORTCUT_VALUE_PATTERN_MISSING"); ui.Check(); Need(!((ValuePattern)p).Current.IsReadOnly,"SHORTCUT_FIELD_READONLY"); ui.Check(); ((ValuePattern)p).SetValue(value); ui.Check(); return true; }); valueWrites++; Need(Field(name)==value,"SHORTCUT_VALUE_WRITE_NOT_APPLIED"); }
        void Invoke(string name) { ui.Call(delegate {
            AutomationElement e=Find(name,ControlType.Button);Need(e!=null,"SHORTCUT_BUTTON_NOT_VISIBLE");object invocation,toggle;
            bool supportsInvoke=e.TryGetCurrentPattern(InvokePattern.Pattern,out invocation);ui.Check();
            bool supportsToggle=e.TryGetCurrentPattern(TogglePattern.Pattern,out toggle);ui.Check();
            buttonPatterns.Add(new Dictionary<string,object>{{"target",name==Record?1:2},{"supportsInvoke",supportsInvoke?1:0},{"supportsToggle",supportsToggle?1:0}});
            if(supportsInvoke) ((InvokePattern)invocation).Invoke();
            else if(name==Record&&supportsToggle) ((TogglePattern)toggle).Toggle();
            else throw new InvalidOperationException("SHORTCUT_ACTION_PATTERN_MISSING");
            ui.Check();return true;
        }); }
        bool Status(string prefix) {
            return ui.Call(delegate { ui.Check(); OwnMain(); AutomationElement root=AutomationElement.FromHandle(main); ui.Check(); AutomationElementCollection text=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text)); ui.Check(); Need(text.Count<=512,"UIA_STATIC_TEXT_NOT_BOUNDED"); for(int i=0;i<text.Count;i++) { string value=text[i].Current.Name; ui.Check(); if(value.StartsWith(prefix,StringComparison.Ordinal)) { bool visible=!text[i].Current.IsOffscreen; ui.Check(); if(visible) return true; } } return false; });
        }
        void Availability(uint modifiers,uint key,bool available,string phase) {
            Active(); bool registered=RegisterHotKey(IntPtr.Zero,23117,modifiers,key); int error=registered?0:Marshal.GetLastWin32Error();
            if(registered) Need(UnregisterHotKey(IntPtr.Zero,23117),"HOTKEY_PROBE_RELEASE_FAILED");
            probes.Add(new Dictionary<string,object>{{"phase",phase},{"modifiers",modifiers},{"key",key},{"available",registered},{"win32Error",error}});
            Need(registered||error==1409,"HOTKEY_PROBE_UNKNOWN_ERROR"); Need(registered==available,"HOTKEY_AVAILABILITY_UNEXPECTED");
        }
        void Custom(bool available,string phase) { Availability(7,0x78,available,phase); Availability(7,0x79,available,phase); }
        void Defaults(bool available,string phase) { Availability(1,0x44,available,phase); Availability(1,0x53,available,phase); }
        static INPUT Key(ushort key,bool up) { INPUT v=new INPUT();v.type=1;v.data.key.vk=key;v.data.key.flags=up?2U:0U;return v; }
        void Send(INPUT[] input) { Active(); OwnMain(); Need(GetAncestor(GetForegroundWindow(),2)==main,"INPUT_TARGET_NOT_FOREGROUND"); Need(SendInput((uint)input.Length,input,Marshal.SizeOf(typeof(INPUT)))==input.Length,"NATIVE_KEY_REJECTED"); }
        void RecordKey(uint modifiers,ushort key,string expected) {
            OwnMain(); SetForegroundWindow(main); Wait(delegate { return GetAncestor(GetForegroundWindow(),2)==main; },2000,"OWN_APP_NOT_FOREGROUND");
            Invoke(Record); Wait(delegate { return Status("请按快捷键并松开所有按键"); },5000,"RECORDING_LEASE_NOT_READY");
            Wait(delegate { return ui.Call(delegate { AutomationElement e=Find(Selection,ControlType.Edit); Need(e!=null,"RECORD_FIELD_MISSING"); bool focused=e.Current.HasKeyboardFocus; ui.Check(); return focused; }); },5000,"RECORD_FIELD_NOT_FOCUSED");
            foreach(int vk in new int[]{0x10,0x11,0x12,0x5B,0x5C}) Need((GetAsyncKeyState(vk)&0x8000)==0,"PREHELD_MODIFIER_NO_INPUT");
            List<INPUT> down=new List<INPUT>(),up=new List<INPUT>();
            if((modifiers&2)!=0)down.Add(Key(0x11,false));if((modifiers&1)!=0)down.Add(Key(0x12,false));if((modifiers&4)!=0)down.Add(Key(0x10,false));down.Add(Key(key,false));
            up.Add(Key(key,true));if((modifiers&4)!=0)up.Add(Key(0x10,true));if((modifiers&1)!=0)up.Add(Key(0x12,true));if((modifiers&2)!=0)up.Add(Key(0x11,true));
            try { Send(down.ToArray()); Thread.Sleep(40); }
            finally { Need(SendInput((uint)up.Count,up.ToArray(),Marshal.SizeOf(typeof(INPUT)))==up.Count,"OWN_GENERATED_KEY_RELEASE_FAILED"); }
            keySends++; Wait(delegate { return Status("已录入，点击"); },5000,"REGISTERED_KEY_NOT_RECORDED");
            Need(Field(Selection)==expected&&FieldsVisible(),"RECORDING_EXECUTED_ACTION_OR_CHANGED_VIEW");
            Need(!File.Exists(Path.Combine(Path.GetDirectoryName(settingsPath),"history.json")),"RECORDING_CREATED_HISTORY");
        }
        byte[] Settings() { CheckRoot(Path.GetDirectoryName(settingsPath)); Need(File.Exists(settingsPath)&&(File.GetAttributes(settingsPath)&FileAttributes.ReparsePoint)==0,"SETTINGS_CHANGED_OR_MISSING"); Need(new FileInfo(settingsPath).Length<=1048576,"SETTINGS_OVERSIZE"); return File.ReadAllBytes(settingsPath); }
        bool Pair(string selection,string ocr) { Dictionary<string,object> root=(Dictionary<string,object>)json.DeserializeObject(Encoding.UTF8.GetString(Settings())); Dictionary<string,object> s=(Dictionary<string,object>)root["shortcuts"]; return (string)s["selection"]==selection&&(string)s["silentOcr"]==ocr; }
        void SavePair(string selection,string ocr) { Fill(Selection,selection); Fill(Ocr,ocr); Invoke(Save); Wait(delegate { return Status("快捷键已保存并立即生效"); },5000,"SAVE_SUCCESS_NOT_REPORTED"); Wait(delegate { return Pair(selection,ocr); },5000,"SAVED_BINDINGS_NOT_DURABLE"); }
        void Start() {
            Stage("start-actual-settings"); foreach(string root in owned) CheckRoot(root);
            JOBINFO info=new JOBINFO();info.basic.flags=0x2000; job=CreateJobObject(IntPtr.Zero,null); Need(job!=IntPtr.Zero,"OWN_JOB_CREATE_FAILED"); Need(SetInformationJobObject(job,9,ref info,(uint)Marshal.SizeOf(typeof(JOBINFO))),"OWN_JOB_CONFIG_FAILED");
            ProcessStartInfo start=new ProcessStartInfo(executable,"--configure-shortcuts");start.UseShellExecute=false;start.CreateNoWindow=true;
            start.EnvironmentVariables.Remove("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS");start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"]=Path.Combine(local,"shortcut-uia-webview");
            app=Process.Start(start); launches++; Need(AssignProcessToJobObject(job,app.Handle),"OWN_APP_JOB_ASSIGN_FAILED");
            Wait(delegate { main=Main();return main!=IntPtr.Zero; },20000,"OWN_MAIN_NOT_READY");
            Wait(FieldsVisible,25000,"ACTUAL_SHORTCUT_SETTINGS_NOT_READY"); report["actualSettingsUiTested"]=true;
        }
        void Stop() {
            Exception failure=null;
            if(job!=IntPtr.Zero) { IntPtr ownJob=job;job=IntPtr.Zero;try {
                Need(TerminateJobObject(ownJob,0),"OWN_APP_JOB_STOP_FAILED");Stopwatch stopped=Stopwatch.StartNew();JOBACCOUNTING accounting;uint returned;
                while(true) {
                    Need(QueryInformationJobObject(ownJob,1,out accounting,(uint)Marshal.SizeOf(typeof(JOBACCOUNTING)),out returned),"OWN_JOB_ACCOUNTING_FAILED");
                    if(accounting.active==0) { jobStops.Add(new Dictionary<string,object>{{"activeProcesses",accounting.active},{"elapsedMilliseconds",stopped.ElapsedMilliseconds}});break; }
                    Need(stopped.ElapsedMilliseconds<5000,"OWN_JOB_PROCESSES_NOT_STOPPED");Thread.Sleep(10);
                }
            } catch(Exception e) { failure=e; } finally { CloseHandle(ownJob); } }
            if(app!=null) { try { if(!app.HasExited) { app.Kill(); Need(app.WaitForExit(5000),"OWN_APP_NOT_STOPPED"); } } catch(Exception e) { if(failure==null) failure=e; } finally { app.Dispose();app=null; } }
            main=IntPtr.Zero; if(failure!=null) throw failure;
        }
        void Conflict() {
            Stage("real-external-conflict-rollback"); Availability(7,0x77,true,"conflict-baseline");
            ManualResetEvent ready=new ManualResetEvent(false),release=new ManualResetEvent(false); Exception holderError=null; bool owns=false;
            Thread holder=new Thread(delegate() { try { Need(RegisterHotKey(IntPtr.Zero,23118,7,0x77),"EXTERNAL_CONFLICT_HOLD_FAILED"); owns=true;ready.Set();release.WaitOne(); } catch(Exception e) { holderError=e;ready.Set(); } finally { if(owns&&!UnregisterHotKey(IntPtr.Zero,23118)) holderError=new InvalidOperationException("EXTERNAL_CONFLICT_RELEASE_FAILED"); } });
            holder.IsBackground=true; holder.Start();
            try {
                Need(ready.WaitOne(5000)&&holderError==null&&owns,"EXTERNAL_CONFLICT_NOT_READY");
                byte[] before=Settings(); Fill(Selection,"Ctrl+Alt+Shift+F8");Invoke(Save);
                Wait(delegate { return Status("未完成保存："); },5000,"REAL_CONFLICT_NOT_REPORTED");
                Need(Convert.ToBase64String(Settings())==Convert.ToBase64String(before),"CONFLICT_CHANGED_DURABLE_SETTINGS");
                Custom(false,"after-conflict"); Availability(7,0x77,false,"external-owner-still-holds");
                RecordKey(7,0x78,"Ctrl+Alt+Shift+F9");
            } finally { release.Set();if(holder.Join(5000)) { ready.Dispose();release.Dispose(); } else cleanupErrors.Add("EXTERNAL_CONFLICT_THREAD_NOT_STOPPED"); }
            if(holderError!=null) throw holderError;
            Availability(7,0x77,true,"external-owner-released");
        }
        public Dictionary<string,object> Run() {
            report["ok"]=false;report["actualSettingsUiTested"]=false;report["fakeIpcUsed"]=false;report["cdpUsed"]=false;report["userContentRead"]=false;
            report["credentialsCreated"]=false;report["clipboardReadOrChanged"]=false;report["actualNewShortcutTranslationWorkflowTested"]=false;
            report["restartMethod"]="owned-job-termination; settings are saved through the real UI before termination, not graceful app quit";
            report["jobAssignedAfterStart"]=true;report["completeDescendantEnumeration"]=false;
            report["scope"]="Generated ephemeral Windows Server settings UIA/SendInput/RegisterHotKey only; not physical Windows11 or translation/OCR workflow acceptance.";
            report["overallDeadlineMilliseconds"]=TotalMilliseconds;report["uiaCallDeadlineMilliseconds"]=UiaCallMilliseconds;
            try {
                foreach(Process old in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable))) using(old) { Need(old.HasExited,"EXISTING_APP_REFUSED"); }
                string roaming=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),Identifier);local=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),Identifier);
                Claim(roaming);Claim(local);settingsPath=Path.Combine(roaming,"settings.json");
                File.WriteAllText(settingsPath,"{\"shortcutDefaultsVersion\":1,\"shortcuts\":{\"selection\":\"Alt+D\",\"silentOcr\":\"Alt+S\",\"capture\":\"\",\"ocr\":\"\",\"input\":\"\"},\"providers\":[],\"ocrProviders\":[],\"sourceLanguage\":\"auto\",\"targetLanguage\":\"auto\",\"languageDirectionVersion\":1,\"saveHistory\":false}",new UTF8Encoding(false));
                ui=new UiWorker(Active,delegate { return (int)Math.Max(0,TotalMilliseconds-watch.ElapsedMilliseconds); }); Defaults(true,"before-app");Custom(true,"before-app");
                Start();long t=watch.ElapsedMilliseconds;Stage("record-registered-default");Defaults(false,"default-started");RecordKey(1,0x44,"Alt+D");Passed("Registered Alt+D records through a real lease without leaving settings",t);
                t=watch.ElapsedMilliseconds;Stage("save-custom-bindings");SavePair("Ctrl+Alt+Shift+F9","Ctrl+Alt+Shift+F10");Custom(false,"custom-saved");Defaults(true,"old-released");Passed("Real UI save owns both previously available custom keys and releases old keys",t);
                t=watch.ElapsedMilliseconds;Conflict();Passed("External F8 owner rejects save; exact prior file and F9 recording survive",t);
                t=watch.ElapsedMilliseconds;Stage("restart-custom-persistence");Stop();Custom(true,"custom-app-stopped");Start();Need(Field(Selection)=="Ctrl+Alt+Shift+F9"&&Field(Ocr)=="Ctrl+Alt+Shift+F10","RESTART_FIELDS_NOT_PERSISTED");Custom(false,"custom-restarted");Defaults(true,"old-still-released");Passed("Restart reads the saved custom fields and restores both registrations",t);
                t=watch.ElapsedMilliseconds;Stage("disable-and-restart");SavePair("","");Custom(true,"disabled-live");Defaults(true,"disabled-defaults");Stop();Start();Need(Field(Selection)==""&&Field(Ocr)==""&&Pair("",""),"DISABLED_BINDINGS_NOT_PERSISTED");Custom(true,"disabled-restarted");Defaults(true,"disabled-restarted-defaults");Passed("Empty values disable both keys immediately and remain disabled after restart",t);
                t=watch.ElapsedMilliseconds;Stage("restore-defaults-manually");SavePair("Alt+D","Alt+S");Defaults(false,"defaults-restored");Custom(true,"custom-remains-released");Passed("Manual default restoration registers Alt+D and Alt+S through the real save UI",t);
                report["ok"]=true;Stage("completed");
            } catch(Exception e) { report["ok"]=false;report["error"]=e.Message;report["exceptionType"]=e.GetType().Name;report["hresult"]=e.HResult; }
            finally {
                try { Stop(); } catch(Exception e) { cleanupErrors.Add(e.Message); }
                if(ui!=null) try { ui.Dispose(); } catch(Exception e) { cleanupErrors.Add(e.Message); }
                if((bool)report["ok"]) try { Custom(true,"final-process-release");Defaults(true,"final-process-release"); } catch(Exception e) { cleanupErrors.Add(e.Message); }
                for(int i=owned.Count-1;i>=0;i--) try { Clean(owned[i]); } catch(Exception e) { cleanupErrors.Add(e.Message); }
                if(cleanupErrors.Count!=0) report["ok"]=false;
                report["stage"]=stage;report["elapsedMilliseconds"]=watch.ElapsedMilliseconds;report["cases"]=cases;report["casesExecuted"]=cases.Count;report["casesExpected"]=6;report["nativeRegistrationProbes"]=probes;
                report["nativeKeySends"]=keySends;report["actualWindowsSendInput"]=keySends>0;report["valuePatternWrites"]=valueWrites;report["applicationLaunches"]=launches;report["cleanupErrors"]=cleanupErrors;report["ownedDataRemoved"]=cleanupErrors.Count==0;
                report["buttonPatternMetadata"]=buttonPatterns;report["ownedJobStops"]=jobStops;
            }
            return report;
        }
    }
    public static Dictionary<string,object> Run(string executable) { return new Fixture(executable).Run(); }
}
