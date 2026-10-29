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
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUITHREADINFO info);
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string path, IntPtr security);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref JOBINFO info, uint size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, out JOBACCOUNTING info, uint size, out uint returned);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFileAttributes(string path);
    [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct DATA { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public DATA data; }
    [StructLayout(LayoutKind.Sequential)] struct JOBLIMIT { public long processTime,jobTime; public uint flags; public UIntPtr minimum,maximum; public uint active; public UIntPtr affinity; public uint priority,scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct IOCOUNTERS { public ulong a,b,c,d,e,f; }
    [StructLayout(LayoutKind.Sequential)] struct JOBINFO { public JOBLIMIT basic; public IOCOUNTERS io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
    [StructLayout(LayoutKind.Sequential)] struct JOBACCOUNTING { public long totalUser,totalKernel,periodUser,periodKernel; public uint faults,total,active,terminated; }
    [StructLayout(LayoutKind.Sequential)] struct GUITHREADINFO { public uint cbSize,flags;public IntPtr active,focus,capture,menuOwner,moveSize,caret;public int left,top,right,bottom; }

    static void Need(bool value, string error) { if (!value) throw new InvalidOperationException(error); }
    sealed class UiWorker : IDisposable {
        readonly AutoResetEvent wake = new AutoResetEvent(false);
        readonly object gate = new object(); readonly Thread thread; readonly Action active; readonly Func<int> remaining;
        readonly List<object> failures=new List<object>();
        Action pending; int abandoned, closed,exceptionCount; string operation="none";
        public UiWorker(Action check,Func<int> budget) {
            active=check; remaining=budget; thread=new Thread(delegate() { while (true) { wake.WaitOne(); Action next; lock(gate) { next=pending; pending=null; } if(next!=null) next(); if(Volatile.Read(ref closed)!=0) return; } });
            thread.IsBackground=true; thread.SetApartmentState(ApartmentState.MTA); thread.Start();
        }
        public void Check() { active(); Need(Volatile.Read(ref abandoned)==0,"UIA_WORKER_ABANDONED"); }
        public void Rpc(string name) { Check();operation=name; }
        public int ExceptionCount { get { return Volatile.Read(ref exceptionCount); } }
        public bool Unavailable { get { return Volatile.Read(ref abandoned)!=0; } }
        public object[] Failures { get { lock(gate) return failures.ToArray(); } }
        void Failure(Exception error) {
            Interlocked.Increment(ref exceptionCount);string stack=error.StackTrace??"";if(stack.Length>4096)stack=stack.Substring(0,4096);
            lock(gate) if(failures.Count<16) failures.Add(new Dictionary<string,object>{{"operation",operation},{"exceptionType",error.GetType().Name},{"hresult",error.HResult},{"stack",stack}});
        }
        public T Call<T>(Func<T> action) {
            Check(); T result=default(T); Exception failure=null;
            ManualResetEvent done=new ManualResetEvent(false);
            lock(gate) { Need(pending==null,"UIA_WORKER_BUSY"); pending=delegate { try { operation="task-entry";Check();result=action();Check(); } catch(Exception e) { Failure(e);failure=e; } finally { done.Set(); } }; }
            wake.Set();
            int wait=Math.Min(UiaCallMilliseconds,Math.Max(1,remaining()));
            if(!done.WaitOne(wait)) { Interlocked.Exchange(ref abandoned,1); throw new InvalidOperationException(wait<UiaCallMilliseconds?"UIA_REMAINING_BUDGET_DEADLINE":"UIA_CALL_DEADLINE_5000MS"); }
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
        UiWorker ui; Process app; IntPtr job,main; string settingsPath,local,stage="claim-generated-data"; int keySends,valueWrites,launches,staleReadObservations;
        long observationDeadline=Int64.MaxValue;
        Dictionary<string,object> recordingObservation;
        string recordingStatusPrefix;int recordingStatusLength;long recordingStatusAt;
        public Fixture(string path) { executable=path; }
        void Active() { Need(watch.ElapsedMilliseconds<TotalMilliseconds,"FIXTURE_DEADLINE_180000MS"); }
        void Wait(Func<bool> condition, int milliseconds, string error) {
            long end=Math.Min(Interlocked.Read(ref observationDeadline),watch.ElapsedMilliseconds+milliseconds);
            long previous=Interlocked.Exchange(ref observationDeadline,end);
            try {
                while(watch.ElapsedMilliseconds<end) {
                    Active();try { if(condition()) return; } catch(ElementNotAvailableException) { staleReadObservations++; }
                    long remaining=Math.Min(end-watch.ElapsedMilliseconds,TotalMilliseconds-watch.ElapsedMilliseconds);
                    if(remaining>0) Thread.Sleep((int)Math.Min(20,remaining));
                }
            } finally { Interlocked.Exchange(ref observationDeadline,previous); }
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
            ui.Check();OwnMain();ui.Rpc("own-root-from-handle");AutomationElement root=AutomationElement.FromHandle(main);ui.Check();
            ui.Rpc("find-named-control");AutomationElementCollection all=root.FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.NameProperty,name),new PropertyCondition(AutomationElement.ControlTypeProperty,type)));ui.Check();
            Need(all.Count<=16,"UIA_TARGET_NOT_BOUNDED"); AutomationElement result=null;
            for(int i=0;i<all.Count;i++) { ui.Rpc("read-control-offscreen");bool offscreen=all[i].Current.IsOffscreen;ui.Check();if(!offscreen) { Need(result==null,"UIA_TARGET_NOT_UNIQUE"); result=all[i]; } }
            return result;
        }
        string Field(string name) { return ui.Call(delegate { AutomationElement e=Find(name,ControlType.Edit);Need(e!=null,"SHORTCUT_FIELD_NOT_VISIBLE");object p;ui.Rpc("query-value-pattern");Need(e.TryGetCurrentPattern(ValuePattern.Pattern,out p),"SHORTCUT_VALUE_PATTERN_MISSING");ui.Check();ui.Rpc("read-shortcut-value");string v=((ValuePattern)p).Current.Value;ui.Check();return v; }); }
        bool FieldsVisible() { return ui.Call(delegate { return Find(Selection,ControlType.Edit)!=null&&Find(Ocr,ControlType.Edit)!=null; }); }
        void Fill(string name,string value) { ui.Call(delegate { AutomationElement e=Find(name,ControlType.Edit);Need(e!=null,"SHORTCUT_FIELD_NOT_VISIBLE");object p;ui.Rpc("query-value-pattern");Need(e.TryGetCurrentPattern(ValuePattern.Pattern,out p),"SHORTCUT_VALUE_PATTERN_MISSING");ui.Check();ui.Rpc("read-shortcut-readonly");Need(!((ValuePattern)p).Current.IsReadOnly,"SHORTCUT_FIELD_READONLY");ui.Check();ui.Rpc("set-shortcut-value");((ValuePattern)p).SetValue(value);ui.Check();return true; });valueWrites++;Wait(delegate { return FieldsVisible()&&Field(name)==value; },5000,"SHORTCUT_VALUE_WRITE_NOT_APPLIED"); }
        void Invoke(string name) { ui.Call(delegate {
            AutomationElement e=Find(name,ControlType.Button);Need(e!=null,"SHORTCUT_BUTTON_NOT_VISIBLE");object invocation,toggle;
            ui.Rpc("query-invoke-pattern");bool supportsInvoke=e.TryGetCurrentPattern(InvokePattern.Pattern,out invocation);ui.Check();
            ui.Rpc("query-toggle-pattern");bool supportsToggle=e.TryGetCurrentPattern(TogglePattern.Pattern,out toggle);ui.Check();
            buttonPatterns.Add(new Dictionary<string,object>{{"target",name==Record?1:2},{"supportsInvoke",supportsInvoke?1:0},{"supportsToggle",supportsToggle?1:0}});
            if(supportsInvoke) { ui.Rpc("invoke-shortcut-button");((InvokePattern)invocation).Invoke(); }
            else if(name==Record&&supportsToggle) { ui.Rpc("toggle-record-button");((TogglePattern)toggle).Toggle(); }
            else throw new InvalidOperationException("SHORTCUT_ACTION_PATTERN_MISSING");
            ui.Check();return true;
        }); }
        bool Status(string prefix) {
            return ui.Call(delegate { ui.Check();OwnMain();ui.Rpc("status-root-from-handle");AutomationElement root=AutomationElement.FromHandle(main);ui.Check();ui.Rpc("find-status-text");AutomationElementCollection text=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));ui.Check();Need(text.Count<=512,"UIA_STATIC_TEXT_NOT_BOUNDED");for(int i=0;i<text.Count;i++) { ui.Rpc("read-static-status-name");string value=text[i].Current.Name;ui.Check();CacheRecordingStatus(value);if(value.StartsWith(prefix,StringComparison.Ordinal)) { ui.Rpc("read-status-offscreen");bool visible=!text[i].Current.IsOffscreen;ui.Check();if(visible) return true; } }return false; });
        }
        void CacheRecordingStatus(string value) {
            if(recordingObservation==null)return;
            foreach(string known in new string[]{"已录入，点击","已记录 ","请按快捷键并松开所有按键","继续按一个普通按键","录制结束失败：","无法开始录制：","录制已取消，原输入未更改。","已取消，请松开按键。","录制准备已超时","正在准备录制","未完成保存：","快捷键已保存并立即生效"})if(value.StartsWith(known,StringComparison.Ordinal)){Volatile.Write(ref recordingStatusLength,value.Length);Interlocked.Exchange(ref recordingStatusAt,watch.ElapsedMilliseconds);Volatile.Write(ref recordingStatusPrefix,known);return;}
        }
        static string GeneratedBinding(string value) { return value==""||value=="Alt+D"||value=="Alt+S"||value=="Ctrl+Alt+Shift+F8"||value=="Ctrl+Alt+Shift+F9"||value=="Ctrl+Alt+Shift+F10"?value:"[unrecognized-test-binding]"; }
        Dictionary<string,object> RecordingNativeState(ushort key) {
            Dictionary<string,object> state=new Dictionary<string,object>();IntPtr foreground=GetForegroundWindow();uint pid;uint thread=GetWindowThreadProcessId(foreground,out pid);state["foregroundIsOwnMain"]=app!=null&&pid==app.Id&&GetAncestor(foreground,2)==main;state["foregroundThreadId"]=pid==(app==null?0:app.Id)?thread:0;
            int mask=0;foreach(int vk in new int[]{0x11,0x12,0x10,0x5B,0x5C})if((GetAsyncKeyState(vk)&0x8000)!=0)mask|=vk==0x11?1:vk==0x12?2:vk==0x10?4:8;state["physicalModifierMask"]=mask;state["recordedMainKeyPhysicallyHeld"]=(GetAsyncKeyState(key)&0x8000)!=0;
            GUITHREADINFO info=new GUITHREADINFO();info.cbSize=(uint)Marshal.SizeOf(typeof(GUITHREADINFO));bool ok=pid==(app==null?0:app.Id)&&thread!=0&&GetGUIThreadInfo(thread,ref info);state["guiThreadInfoSucceeded"]=ok;
            if(ok){uint focusPid;uint focusThread=GetWindowThreadProcessId(info.focus,out focusPid);bool own=app!=null&&focusPid==app.Id&&GetAncestor(info.focus,2)==main;state["nativeFocusWithinOwnMain"]=own;state["nativeFocusThreadId"]=own?focusThread:0;if(own){StringBuilder name=new StringBuilder(128);GetClassName(info.focus,name,name.Capacity);state["nativeFocusClass"]=name.ToString();}}
            state["nativeHotkeyOwnerQueried"]=false;state["newRegistrationProbePerformed"]=false;return state;
        }
        void RecordingSnapshot(List<object> snapshots) {
            Dictionary<string,object> snapshot=new Dictionary<string,object>{{"remainingOriginalObservationMilliseconds",Math.Max(0,Interlocked.Read(ref observationDeadline)-watch.ElapsedMilliseconds)},{"elapsedMilliseconds",watch.ElapsedMilliseconds},{"backendLeaseQueried",false}};snapshots.Add(snapshot);
            try{Dictionary<string,object> values=ui.Call(delegate {Dictionary<string,object> fields=new Dictionary<string,object>();foreach(string name in new string[]{Selection,Ocr}){AutomationElement e=Find(name,ControlType.Edit);string kind=name==Selection?"selection":"ocr";fields[kind+"Visible"]=e!=null;if(e==null)continue;object raw;ui.Rpc("diagnostic-query-shortcut-value-pattern");if(e.TryGetCurrentPattern(ValuePattern.Pattern,out raw)){ui.Check();ValuePattern p=(ValuePattern)raw;ui.Rpc("diagnostic-read-generated-shortcut-value");fields[kind+"GeneratedValue"]=GeneratedBinding(p.Current.Value);ui.Check();ui.Rpc("diagnostic-read-shortcut-readonly");fields[kind+"ReadOnly"]=p.Current.IsReadOnly;ui.Check();}ui.Rpc("diagnostic-read-shortcut-focus");fields[kind+"HasKeyboardFocus"]=e.Current.HasKeyboardFocus;ui.Check();}
                AutomationElement record=Find(Record,ControlType.Button);if(record!=null){object toggle;ui.Rpc("diagnostic-query-record-toggle");if(record.TryGetCurrentPattern(TogglePattern.Pattern,out toggle)){ui.Check();ui.Rpc("diagnostic-read-record-toggle");fields["recordToggleState"]=(int)((TogglePattern)toggle).Current.ToggleState;ui.Check();}}
                AutomationElement save=Find(Save,ControlType.Button);if(save!=null){ui.Rpc("diagnostic-read-save-enabled");fields["saveEnabled"]=save.Current.IsEnabled;ui.Check();}return fields;});foreach(KeyValuePair<string,object> pair in values)snapshot[pair.Key]=pair.Value;}
            catch(Exception error){snapshot["exceptionType"]=error.GetType().Name;snapshot["hresult"]=error.HResult;snapshot["workerUnavailable"]=ui.Unavailable;}
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
            Dictionary<string,object> observation=new Dictionary<string,object>{{"recordAttempt",keySends+1},{"expectedGeneratedBinding",GeneratedBinding(expected)},{"originalRecordedStatusBudgetMilliseconds",5000},{"backendLeaseQueried",false}};Volatile.Write(ref recordingStatusPrefix,null);Volatile.Write(ref recordingStatusLength,0);Interlocked.Exchange(ref recordingStatusAt,0);recordingObservation=observation;List<object> snapshots=new List<object>();observation["boundedReadonlySnapshots"]=snapshots;
            try {
            OwnMain(); SetForegroundWindow(main); Wait(delegate { return GetAncestor(GetForegroundWindow(),2)==main; },2000,"OWN_APP_NOT_FOREGROUND");
            Invoke(Record); Wait(delegate { return Status("请按快捷键并松开所有按键"); },5000,"RECORDING_LEASE_NOT_READY");
            Wait(delegate { return ui.Call(delegate { AutomationElement e=Find(Selection,ControlType.Edit);Need(e!=null,"RECORD_FIELD_MISSING");ui.Rpc("read-recording-field-focus");bool focused=e.Current.HasKeyboardFocus;ui.Check();observation["fieldHadKeyboardFocusBeforeInput"]=focused;return focused; }); },5000,"RECORD_FIELD_NOT_FOCUSED");
            foreach(int vk in new int[]{0x10,0x11,0x12,0x5B,0x5C}) Need((GetAsyncKeyState(vk)&0x8000)==0,"PREHELD_MODIFIER_NO_INPUT");
            List<INPUT> down=new List<INPUT>(),up=new List<INPUT>();
            if((modifiers&2)!=0)down.Add(Key(0x11,false));if((modifiers&1)!=0)down.Add(Key(0x12,false));if((modifiers&4)!=0)down.Add(Key(0x10,false));down.Add(Key(key,false));
            up.Add(Key(key,true));if((modifiers&4)!=0)up.Add(Key(0x10,true));if((modifiers&1)!=0)up.Add(Key(0x12,true));if((modifiers&2)!=0)up.Add(Key(0x11,true));
            observation["nativeBeforeInput"]=RecordingNativeState(key);try { Send(down.ToArray());observation["downInputInserted"]=down.Count;Thread.Sleep(40); }
            finally { uint inserted=SendInput((uint)up.Count,up.ToArray(),Marshal.SizeOf(typeof(INPUT)));observation["upInputInserted"]=inserted;Need(inserted==up.Count,"OWN_GENERATED_KEY_RELEASE_FAILED"); }
            keySends++; Wait(delegate { if(ui.Unavailable)return false;bool recorded=Status("快捷键已保存并立即生效");if(!recorded&&snapshots.Count<2&&(snapshots.Count==0||Interlocked.Read(ref observationDeadline)-watch.ElapsedMilliseconds<1000))RecordingSnapshot(snapshots);return recorded; },5000,"REGISTERED_KEY_NOT_RECORDED");
            Wait(delegate { return FieldsVisible()&&Field(Selection)==expected; },5000,"RECORDING_EXECUTED_ACTION_OR_CHANGED_VIEW");
            Wait(delegate { Dictionary<string,object> root=(Dictionary<string,object>)json.DeserializeObject(Encoding.UTF8.GetString(Settings())); Dictionary<string,object> values=(Dictionary<string,object>)root["shortcuts"]; return (string)values["selection"]==expected; },5000,"RECORDING_DID_NOT_AUTOSAVE");
            Need(!File.Exists(Path.Combine(Path.GetDirectoryName(settingsPath),"history.json")),"RECORDING_CREATED_HISTORY");
            } catch { observation["lastObservedStatusPrefix"]=Volatile.Read(ref recordingStatusPrefix);observation["lastObservedStatusLength"]=Volatile.Read(ref recordingStatusLength);observation["lastStatusObservationMilliseconds"]=Interlocked.Read(ref recordingStatusAt);observation["cachedStatusVisibilityIndependentlyQueried"]=false;observation["nativeAtFailure"]=RecordingNativeState(key);observation["existingProbeCount"]=probes.Count;observation["capturedAfterFailureWithoutNewUiRpc"]=true;report["recordingFailureObservation"]=observation;throw; }
            finally { recordingObservation=null; }
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
            if(job==IntPtr.Zero&&app==null) { main=IntPtr.Zero;return; }
            Exception failure=null;IntPtr ownJob=job,appHandle=IntPtr.Zero;job=IntPtr.Zero;
            uint thread=GetCurrentThreadId(),lastWait=UInt32.MaxValue;int polls=0;
            uint[] modifiers=new uint[]{7,7,1,1},keys=new uint[]{0x78,0x79,0x44,0x53};
            int[] attempts=new int[4],unregistered=new int[4],lastErrors=new int[]{-1,-1,-1,-1};
            long[] firstConflicts=new long[]{-1,-1,-1,-1};bool completed=false,allAvailable=false;
            Dictionary<string,object> stoppedState=new Dictionary<string,object>{{"budgetMilliseconds",5000},{"applicationHandleRequired",app!=null},{"nativeProbeThreadId",thread},{"activeProcesses",null}};
            Stopwatch stopped=Stopwatch.StartNew();
            try {
                if(app!=null) appHandle=app.Handle;
                Need(ownJob!=IntPtr.Zero,"OWN_APP_JOB_MISSING");
                Need(TerminateJobObject(ownJob,0),"OWN_APP_JOB_STOP_FAILED");
                while(stopped.ElapsedMilliseconds<5000) {
                    polls++;JOBACCOUNTING accounting;uint returned;
                    Need(QueryInformationJobObject(ownJob,1,out accounting,(uint)Marshal.SizeOf(typeof(JOBACCOUNTING)),out returned),"OWN_JOB_ACCOUNTING_FAILED");
                    stoppedState["activeProcesses"]=accounting.active;
                    lastWait=appHandle==IntPtr.Zero?0:WaitForSingleObject(appHandle,0);
                    int waitError=lastWait==UInt32.MaxValue?Marshal.GetLastWin32Error():0;
                    stoppedState["processWaitWin32Error"]=waitError;
                    if(polls==1) stoppedState["firstProcessWaitResult"]=lastWait;
                    Need(lastWait==0||lastWait==258,"OWN_PROCESS_WAIT_FAILED");
                    allAvailable=false;
                    if(lastWait==0&&accounting.active==0) {
                        allAvailable=true;
                        for(int i=0;i<keys.Length;i++) {
                            Need(stopped.ElapsedMilliseconds<5000,"OWN_STOP_RESOURCE_DEADLINE");
                            Need(GetCurrentThreadId()==thread,"STOP_PROBE_THREAD_CHANGED");attempts[i]++;
                            bool registered=RegisterHotKey(IntPtr.Zero,23117,modifiers[i],keys[i]);int error=registered?0:Marshal.GetLastWin32Error();lastErrors[i]=error;
                            if(registered) {
                                uint releaseThread=GetCurrentThreadId();
                                bool released=UnregisterHotKey(IntPtr.Zero,23117);int releaseError=released?0:Marshal.GetLastWin32Error();
                                stoppedState["probeUnregisterWin32Error"]=releaseError;
                                Need(released,"STOP_PROBE_RELEASE_FAILED");unregistered[i]++;
                                Need(releaseThread==thread&&GetCurrentThreadId()==thread,"STOP_PROBE_THREAD_CHANGED");
                            } else {
                                Need(error==1409,"STOP_PROBE_UNKNOWN_ERROR");allAvailable=false;
                                if(firstConflicts[i]<0) firstConflicts[i]=stopped.ElapsedMilliseconds;
                            }
                        }
                        if(allAvailable&&stopped.ElapsedMilliseconds<5000) { completed=true;break; }
                    }
                    long remaining=5000-stopped.ElapsedMilliseconds;if(remaining>0) Thread.Sleep((int)Math.Min(10,remaining));
                }
                Need(completed,"OWN_STOP_RESOURCE_DEADLINE");
            } catch(Exception e) { failure=e; }
            finally {
                stoppedState["resourceObservationElapsedMilliseconds"]=stopped.ElapsedMilliseconds;stoppedState["processWaitResult"]=lastWait;
                stoppedState["processSignaled"]=lastWait==0;stoppedState["polls"]=polls;stoppedState["allCoreKeysAvailable"]=allAvailable;stoppedState["completed"]=completed;
                stoppedState["coreModifiers"]=modifiers;stoppedState["coreKeys"]=keys;stoppedState["probeAttempts"]=attempts;
                stoppedState["successfulProbeUnregistrations"]=unregistered;stoppedState["lastProbeErrors"]=lastErrors;stoppedState["firstConflictElapsedMilliseconds"]=firstConflicts;
                stoppedState["failureCleanupKillUsed"]=false;jobStops.Add(stoppedState);if(ownJob!=IntPtr.Zero) CloseHandle(ownJob);
                if(app!=null) {
                    try {
                        // Only failure cleanup may need this existing owned-app
                        // fallback. It cannot turn a failed Stop into success.
                        if(!completed&&WaitForSingleObject(appHandle,0)==258) {
                            stoppedState["failureCleanupKillUsed"]=true;app.Kill();long remaining=5000-stopped.ElapsedMilliseconds;
                            if(remaining>0) WaitForSingleObject(appHandle,(uint)remaining);
                        }
                    } catch(Exception e) { if(failure==null) failure=e; }
                    finally { app.Dispose();app=null; }
                }
                stoppedState["elapsedMilliseconds"]=stopped.ElapsedMilliseconds;main=IntPtr.Zero;
            }
            if(failure!=null) throw failure;
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
                ui=new UiWorker(delegate { Active();Need(watch.ElapsedMilliseconds<Interlocked.Read(ref observationDeadline),"UIA_OBSERVATION_DEADLINE"); },delegate { return (int)Math.Max(0,Math.Min(TotalMilliseconds-watch.ElapsedMilliseconds,Interlocked.Read(ref observationDeadline)-watch.ElapsedMilliseconds)); });Defaults(true,"before-app");Custom(true,"before-app");
                Start();long t=watch.ElapsedMilliseconds;Stage("record-registered-default");Defaults(true,"priority-default-does-not-registerhotkey");RecordKey(1,0x44,"Alt+D");Passed("Priority Alt+D records and autosaves through a real lease without leaving settings; RegisterHotKey remains independently available",t);
                t=watch.ElapsedMilliseconds;Stage("save-custom-bindings");SavePair("Ctrl+Alt+Shift+F9","Ctrl+Alt+Shift+F10");Custom(false,"custom-saved");Defaults(true,"old-released");Passed("Real UI save owns both previously available custom keys and releases old keys",t);
                t=watch.ElapsedMilliseconds;Conflict();Passed("External F8 owner rejects save; exact prior file and F9 recording survive",t);
                t=watch.ElapsedMilliseconds;Stage("restart-custom-persistence");Stop();Custom(true,"custom-app-stopped");Start();Need(Field(Selection)=="Ctrl+Alt+Shift+F9"&&Field(Ocr)=="Ctrl+Alt+Shift+F10","RESTART_FIELDS_NOT_PERSISTED");Custom(false,"custom-restarted");Defaults(true,"old-still-released");Passed("Restart reads the saved custom fields and restores both registrations",t);
                t=watch.ElapsedMilliseconds;Stage("disable-and-restart");SavePair("","");Custom(true,"disabled-live");Defaults(true,"disabled-defaults");Stop();Start();Need(Field(Selection)==""&&Field(Ocr)==""&&Pair("",""),"DISABLED_BINDINGS_NOT_PERSISTED");Custom(true,"disabled-restarted");Defaults(true,"disabled-restarted-defaults");Passed("Empty values disable both keys immediately and remain disabled after restart",t);
                t=watch.ElapsedMilliseconds;Stage("restore-defaults-manually");SavePair("Alt+D","Alt+S");Defaults(true,"priority-defaults-restored-without-registerhotkey");Custom(true,"custom-remains-released");Passed("Manual default restoration saves Alt+D and Alt+S without reserving RegisterHotKey; native-hook behavior is checked by its separate fixture",t);
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
                report["staleReadObservations"]=staleReadObservations;report["uiaExceptionCount"]=ui==null?0:ui.ExceptionCount;report["uiaExceptionMetadata"]=ui==null?new object[0]:ui.Failures;
            }
            return report;
        }
    }
    public static Dictionary<string,object> Run(string executable) { return new Fixture(executable).Run(); }
}
