// Disposable generated-source peer; the competing RegisterHotKey owner is a
// different process. All keyboard/mouse events below are synthetic SendInput.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class WindowsPriorityInputFixture {
    const int Status=0,Error=1,Command=2,Request=3,Ack=4,PeerPid=5,Window=6,Editor=7,
        HotD=8,HotS=9,AltDown=10,AltUp=11,SuffixDown=12,SuffixUp=13,MaskDown=14,MaskUp=15,
        KeyMenu=16,MenuLoop=17,AppCommand=18,X1Down=19,X1Up=20,X2Down=21,X2Up=22,
        CloseRequest=23,Foreground=24,FocusFlag=25,SelectionStart=26,SelectionLength=27,
        X1DoubleDown=28,X2DoubleDown=29,Revision=39;
    const int QuietObservationMilliseconds=150;
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll",CharSet=CharSet.Ansi,SetLastError=true)] static extern IntPtr GetProcAddress(IntPtr module,string name);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookExW(int kind,Hook callback,IntPtr module,uint thread);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr word,IntPtr parameter);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window,int id);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] values,int size);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUI info);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr window,uint message,IntPtr word,IntPtr parameter);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out RECT rectangle);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint flags);
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type;public UNION data; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public KEY keyboard;[FieldOffset(0)] public MOUSE mouse; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort key,scan;public uint flags,time;public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y;public uint data,flags,time;public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct GUI { public uint size,flags;public IntPtr active,focus,capture,menu,move,caret;public int l,t,r,b; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x,y; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int l,t,r,b; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBOARD { public uint key,scan,flags,time;public UIntPtr extra; }
    delegate IntPtr Hook(int code,IntPtr word,IntPtr parameter);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate int Start();
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate int Configure(uint mask);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Context(IntPtr window,int management);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Token(ulong token);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate int Recording(ulong lease);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate int Poll([Out] ulong[] values,uint count);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate int LastCurrent();
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Stop();
    static Poll poll;
    static MemoryMappedViewAccessor map;
    static Process peer;
    static long request;
    static bool nativeStarted;
    static Dictionary<string,object> pendingCase;
    static void Need(bool condition,string reason) { if(!condition)throw new InvalidOperationException(reason); }
    static T Function<T>(IntPtr module,string name) where T:class {
        IntPtr address=GetProcAddress(module,name);Need(address!=IntPtr.Zero,"NATIVE_EXPORT_MISSING:"+name);
        return Marshal.GetDelegateForFunctionPointer(address,typeof(T)) as T;
    }
    static INPUT Key(ushort key,bool up) { INPUT value=new INPUT();value.type=1;value.data.keyboard.key=key;value.data.keyboard.flags=up?2U:0U;return value; }
    static INPUT Side(uint button,bool up) { INPUT value=new INPUT();value.data.mouse.data=button;value.data.mouse.flags=up?0x100U:0x80U;return value; }
    static void Send(params INPUT[] values) { Need(SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)))==(uint)values.Length,"OWN_SENDINPUT_REJECTED"); }
    static void Wait(Func<bool> predicate,int milliseconds,string reason) {
        Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<milliseconds) { if(predicate())return;if(peer!=null&&peer.HasExited)throw new InvalidOperationException("OWN_PEER_EXITED");Application.DoEvents();Thread.Sleep(1); }
        throw new InvalidOperationException("TIMEOUT:"+reason);
    }
    static bool Released() { foreach(int key in new int[]{0x10,0x11,0x12,0x44,0x53,0x73,5,6})if((GetAsyncKeyState(key)&0x8000)!=0)return false;return true; }
    static long[] Snapshot() {
        long[] values=new long[40];Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<2000) { long before=map.ReadInt64(Revision*8);if((before&1)!=0){Thread.Sleep(1);continue;}map.ReadArray<long>(0,values,0,values.Length);if(before==map.ReadInt64(Revision*8))return values; }
        throw new InvalidOperationException("OWN_PEER_SNAPSHOT_NOT_STABLE");
    }
    static void Ask(int command) { map.Write(Command*8,(long)command);map.Write(Request*8,++request);Wait(delegate{return map.ReadInt64(Ack*8)==request;},2000,"OWN_PEER_COMMAND"); }
    static long[] Prepare(bool pointer) {
        Ask(1);long[] data=Snapshot();uint pid;IntPtr window=new IntPtr(data[Window]);GetWindowThreadProcessId(window,out pid);
        Need(pid==(uint)peer.Id&&data[PeerPid]==peer.Id,"OWN_PEER_WINDOW_OWNER_MISMATCH");SetForegroundWindow(window);
        Wait(delegate { uint process;uint thread=GetWindowThreadProcessId(window,out process);GUI gui=new GUI();gui.size=(uint)Marshal.SizeOf(typeof(GUI));return process==(uint)peer.Id&&GetForegroundWindow()==window&&GetGUIThreadInfo(thread,ref gui)&&gui.focus==new IntPtr(data[Editor])&&Released(); },2500,"OWN_PEER_FOCUS_AND_RELEASE");
        if(pointer) { RECT bounds;Need(GetWindowRect(new IntPtr(data[Editor]),out bounds),"OWN_EDITOR_BOUNDS_FAILED");POINT point=new POINT();point.x=(bounds.l+bounds.r)/2;point.y=(bounds.t+bounds.b)/2;Need(SetCursorPos(point.x,point.y)&&GetAncestor(WindowFromPoint(point),2)==window,"OWN_POINTER_TARGET_REJECTED"); }
        Wait(delegate{long[] now=Snapshot();return now[Foreground]==1&&now[FocusFlag]==1;},2000,"OWN_PEER_READY_METADATA");return Snapshot();
    }
    static List<ulong[]> Drain() {
        List<ulong[]> events=new List<ulong[]>();if(!nativeStarted)return events;
        for(int index=0;index<100;index++) { ulong[] fields=new ulong[6];int result=poll(fields,6);Need(result>=0,"NATIVE_POLL_FAILED");if(result==0)return events;events.Add(fields); }
        throw new InvalidOperationException("NATIVE_EVENT_FLOOD");
    }
    static Dictionary<string,object> RunCase(string name,INPUT[] inputs,uint expectedId,int peerHotkey,int sourceSuffix,int side,uint expectedLease,int closeRequests) {
        pendingCase=new Dictionary<string,object>{{"name",name},{"expectedNativeId",expectedId},{"expectedPeerHotkey",peerHotkey},{"expectedRecordingLease",expectedLease}};
        bool pointer=side!=0;long[] before=Prepare(pointer);Need(Drain().Count==0,"UNEXPECTED_PENDING_NATIVE_EVENT");
        List<ulong[]> events=new List<ulong[]>();pendingCase["peerBefore"]=before;pendingCase["nativeEvents"]=events;Send(inputs);
        Wait(delegate {
            events.AddRange(Drain());long[] now=Snapshot();bool peerDone=side==0?now[AltUp]>before[AltUp]:expectedId!=0||now[side==1?X1Up:X2Up]>before[side==1?X1Up:X2Up];
            return Released()&&peerDone&&(expectedId==0||events.Count>0)&&(peerHotkey==0||now[peerHotkey==1?HotD:HotS]>before[peerHotkey==1?HotD:HotS])&&(closeRequests==0||now[CloseRequest]>before[CloseRequest]);
        },2500,"OWN_INPUT_COMPLETION:"+name);
        // A bounded negative observation, never a product preparation delay.
        Stopwatch quiet=Stopwatch.StartNew();while(quiet.ElapsedMilliseconds<QuietObservationMilliseconds) {events.AddRange(Drain());Application.DoEvents();Thread.Sleep(1);}
        long[] after=Snapshot();Need(events.Count==(expectedId==0?0:1),"WRONG_NATIVE_EVENT_COUNT:"+name);
        if(expectedId!=0)Need(events[0][0]==expectedId&&events[0][1]==1&&events[0][3]==0&&events[0][4]==expectedLease&&events[0][5]==0,"WRONG_NATIVE_EVENT_CONTEXT:"+name);
        Need(after[HotD]-before[HotD]==(peerHotkey==1?1:0)&&after[HotS]-before[HotS]==(peerHotkey==2?1:0),"COMPETING_HOTKEY_DELIVERY_WRONG:"+name);
        if(sourceSuffix>=0)Need(sourceSuffix==0?after[SuffixDown]==before[SuffixDown]&&after[SuffixUp]==before[SuffixUp]:after[SuffixDown]>before[SuffixDown],"SOURCE_KEY_PASSTHROUGH_WRONG:"+name);
        if(expectedId!=0)Need(after[KeyMenu]==before[KeyMenu]&&after[MenuLoop]==before[MenuLoop]&&after[AppCommand]==before[AppCommand]&&after[Foreground]==1&&after[FocusFlag]==1&&after[SelectionStart]==before[SelectionStart]&&after[SelectionLength]==before[SelectionLength],"BOUND_INPUT_CHANGED_SOURCE_OR_MENU:"+name);
        if(side!=0) {int down=side==1?X1Down:X2Down,up=side==1?X1Up:X2Up;Need(expectedId==0?after[down]-before[down]==1&&after[up]-before[up]==1:after[down]==before[down]&&after[up]==before[up],"SOURCE_MOUSE_PASSTHROUGH_WRONG:"+name);}
        if(closeRequests>0)Need(after[CloseRequest]-before[CloseRequest]==closeRequests,"UNRELATED_ALT_F4_WAS_SWALLOWED");
        return new Dictionary<string,object>{{"name",name},{"ok",true},{"inputEventCount",inputs.Length},{"nativeEvents",events},{"peerAltD",after[HotD]-before[HotD]},{"peerAltS",after[HotS]-before[HotS]},{"sourceSuffixDowns",after[SuffixDown]-before[SuffixDown]},{"sourceSuffixUps",after[SuffixUp]-before[SuffixUp]},{"sourceMouseDowns",side==0?0:after[side==1?X1Down:X2Down]-before[side==1?X1Down:X2Down]},{"sourceMouseUps",side==0?0:after[side==1?X1Up:X2Up]-before[side==1?X1Up:X2Up]},{"sourceMouseDoubleClickDowns",side==0?0:after[side==1?X1DoubleDown:X2DoubleDown]-before[side==1?X1DoubleDown:X2DoubleDown]},{"scKeyMenu",after[KeyMenu]-before[KeyMenu]},{"menuLoops",after[MenuLoop]-before[MenuLoop]},{"sourceCloseRequests",after[CloseRequest]-before[CloseRequest]},{"sourceStillForeground",after[Foreground]==1},{"sourceFocusIsEditor",after[FocusFlag]==1}};
    }
    static INPUT[] Chord(ushort key) { return new INPUT[]{Key(0x12,false),Key(key,false),Key(key,true),Key(0x12,true)}; }

    sealed class PeerEditor:TextBox {
        readonly PeerForm owner;public PeerEditor(PeerForm owner){this.owner=owner;}
        protected override void WndProc(ref Message message) {
            // Windows replaces the second DOWN with DBLCLK within its native
            // double-click interval; that is still exactly one button down.
            if(message.Msg==0x20b||message.Msg==0x20c||message.Msg==0x20d){int button=(int)((message.WParam.ToInt64()>>16)&0xffff);if(button==1||button==2){bool down=message.Msg!=0x20c;owner.counts[button==1?(down?X1Down:X1Up):(down?X2Down:X2Up)]++;if(message.Msg==0x20d)owner.counts[button==1?X1DoubleDown:X2DoubleDown]++;}}base.WndProc(ref message);
        }
    }
    sealed class PeerForm:Form {
        public readonly long[] counts=new long[40];readonly PeerEditor editor;readonly MemoryMappedViewAccessor shared;readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();readonly Hook observe;IntPtr hook,registeredWindow;bool d,s,closing,disposed;long revision;
        public PeerForm(MemoryMappedViewAccessor shared) {
            this.shared=shared;observe=Observe;Text="Generated priority input peer";KeyPreview=true;StartPosition=FormStartPosition.Manual;Bounds=new Rectangle(45,50,700,250);
            editor=new PeerEditor(this);editor.Multiline=true;editor.SetBounds(20,55,640,115);editor.Text="Generated selected source 41729";Controls.Add(editor);
            MainMenu menu=new MainMenu();menu.MenuItems.Add(new MenuItem("&Generated",new MenuItem[]{new MenuItem("Generated entry")}));Menu=menu;
            timer.Interval=10;timer.Tick+=delegate{long next=shared.ReadInt64(Request*8);if(next!=counts[Ack]){int command=(int)shared.ReadInt64(Command*8);if(command==1){Activate();SetForegroundWindow(Handle);editor.Focus();editor.SelectAll();}if(command==2){closing=true;Close();return;}counts[Ack]=next;}Publish();};
        }
        protected override void OnShown(EventArgs args) {
            base.OnShown(args);registeredWindow=Handle;d=RegisterHotKey(registeredWindow,101,0x4001,0x44);int error=d?0:Marshal.GetLastWin32Error();s=RegisterHotKey(registeredWindow,102,0x4001,0x53);if(!s&&error==0)error=Marshal.GetLastWin32Error();hook=SetWindowsHookExW(13,observe,GetModuleHandleW(null),0);if(hook==IntPtr.Zero&&error==0)error=Marshal.GetLastWin32Error();counts[Status]=d&&s&&hook!=IntPtr.Zero?1:-1;counts[Error]=error;timer.Start();Publish();
        }
        void Publish() {
            counts[PeerPid]=Process.GetCurrentProcess().Id;counts[Window]=Handle.ToInt64();counts[Editor]=editor.Handle.ToInt64();counts[Foreground]=GetForegroundWindow()==Handle?1:0;counts[FocusFlag]=editor.Focused?1:0;counts[SelectionStart]=editor.SelectionStart;counts[SelectionLength]=editor.SelectionLength;
            shared.Write(Revision*8,++revision);for(int index=0;index<Revision;index++)if(index!=Command&&index!=Request)shared.Write(index*8,counts[index]);shared.Write(Revision*8,++revision);
        }
        protected override void WndProc(ref Message message) {
            if(message.Msg==0x312){if(message.WParam.ToInt32()==101)counts[HotD]++;if(message.WParam.ToInt32()==102)counts[HotS]++;}
            if(message.Msg==0x112){long command=message.WParam.ToInt64()&0xfff0;if(command==0xf060){counts[CloseRequest]++;return;}if(command==0xf100){counts[KeyMenu]++;PostMessageW(Handle,0x1f,IntPtr.Zero,IntPtr.Zero);}}
            if(message.Msg==0x211)counts[MenuLoop]++;if(message.Msg==0x319)counts[AppCommand]++;base.WndProc(ref message);
        }
        IntPtr Observe(int code,IntPtr word,IntPtr parameter) {
            // Installed before the production pump, so a production-consumed
            // suffix cannot reach this passive peer observer. Never suppress.
            if(code==0&&parameter!=IntPtr.Zero){KEYBOARD key=(KEYBOARD)Marshal.PtrToStructure(parameter,typeof(KEYBOARD));int message=word.ToInt32();bool down=message==0x100||message==0x104,up=message==0x101||message==0x105;
                if(key.key==0x12||key.key==0xa4||key.key==0xa5){if(down)counts[AltDown]++;if(up)counts[AltUp]++;}if(key.key==0x44||key.key==0x53){if(down)counts[SuffixDown]++;if(up)counts[SuffixUp]++;}if(key.key==0xe8){if(down)counts[MaskDown]++;if(up)counts[MaskUp]++;}}
            return CallNextHookEx(hook,code,word,parameter);
        }
        protected override void OnFormClosing(FormClosingEventArgs args) { if(!closing){counts[CloseRequest]++;args.Cancel=true;}base.OnFormClosing(args); }
        protected override void Dispose(bool disposing) {
            // Close() already disposes a modeless form; the enclosing using
            // disposes it again. Never recreate/read Handle during cleanup.
            if(disposing&&!disposed){disposed=true;timer.Stop();timer.Dispose();if(hook!=IntPtr.Zero){UnhookWindowsHookEx(hook);hook=IntPtr.Zero;}if(d){d=false;UnregisterHotKey(registeredWindow,101);}if(s){s=false;UnregisterHotKey(registeredWindow,102);}}base.Dispose(disposing);
        }
    }
    static int Owner(string name) {
        using(MemoryMappedFile memory=MemoryMappedFile.OpenExisting(name))using(MemoryMappedViewAccessor shared=memory.CreateViewAccessor())using(PeerForm form=new PeerForm(shared))Application.Run(form);return 0;
    }
    static Dictionary<string,object> Run(string library) {
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();Dictionary<string,object> result=new Dictionary<string,object>{{"ok",false},{"cases",cases},{"requiredCases",17},{"actualWindowsInputTested",true},{"syntheticSendInputOnly",true},{"physicalInputTested",false},{"actualApplicationTested",false},{"actualWpsTested",false},{"actualBrowserTested",false},{"externalOwnedRegisterHotKeyProcess",true},{"peerPassThroughObservation","earlier-passive-keyboard-hook-and-owned-window-messages"},{"userContentRead",false},{"clipboardRead",false},{"fixedPreparationSleepMilliseconds",0},{"negativeObservationMilliseconds",QuietObservationMilliseconds},{"heldContextRaceTested",false},{"recordingLeaseExpiryClockTested",false}};
        Stop stop=null;POINT pointer;bool pointerSaved=GetCursorPos(out pointer);IntPtr module=IntPtr.Zero;
        string name="Local\\EchoLingoPriority-"+Guid.NewGuid().ToString("N");
        using(MemoryMappedFile memory=MemoryMappedFile.CreateNew(name,320))using(MemoryMappedViewAccessor view=memory.CreateViewAccessor()) {
            map=view;try {
                ProcessStartInfo launch=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"--source-owner "+name);launch.UseShellExecute=false;peer=Process.Start(launch);Need(peer!=null,"OWN_PEER_START_FAILED");
                Wait(delegate{return map.ReadInt64(Status*8)!=0;},5000,"OWN_REGISTERHOTKEY_PEER_READY");Need(map.ReadInt64(Status*8)==1,"OWN_PEER_DEFAULT_REGISTRATION_FAILED:"+map.ReadInt64(Error*8));
                bool stolen=RegisterHotKey(IntPtr.Zero,901,0x4001,0x44);int conflict=Marshal.GetLastWin32Error();if(stolen)UnregisterHotKey(IntPtr.Zero,901);Need(!stolen&&conflict==1409,"INDEPENDENT_PROCESS_ALT_D_OWNERSHIP_NOT_PROVEN");result["independentConflictError"]=conflict;
                cases.Add(RunCase("baseline-peer-owns-alt-d",Chord(0x44),0,1,-1,0,0,0));cases.Add(RunCase("baseline-peer-owns-alt-s",Chord(0x53),0,2,-1,0,0,0));
                module=LoadLibraryW(library);Need(module!=IntPtr.Zero,"NATIVE_FIXTURE_LOAD_FAILED");Start start=Function<Start>(module,"EchoLingoPriorityStart");Configure configure=Function<Configure>(module,"EchoLingoPriorityConfigure");Context context=Function<Context>(module,"EchoLingoPriorityContext");Recording recording=Function<Recording>(module,"EchoLingoPriorityRecording");Token capture=Function<Token>(module,"EchoLingoPriorityCapture");poll=Function<Poll>(module,"EchoLingoPriorityPoll");LastCurrent current=Function<LastCurrent>(module,"EchoLingoPriorityLastCurrent");stop=Function<Stop>(module,"EchoLingoPriorityStop");
                Need(start()==1,"EXACT_NATIVE_HOOK_START_FAILED");nativeStarted=true;Need(configure(3)==1,"PRIORITY_BINDINGS_FAILED");
                capture(41);cases.Add(RunCase("priority-alt-d-beats-peer-with-old-capture",Chord(0x44),1,0,0,0,0,0));capture(0);Need(current()==1,"OLDER_CAPTURE_END_INVALIDATED_NEW_KEYBOARD_INTENT");result["oldCaptureEndingDoesNotInvalidatePriorityEvent"]=true;Need(configure(3)==1&&current()==0,"QUEUED_OLD_CONTEXT_REMAINED_CURRENT");result["queuedEventInvalidatedByBindingRevision"]=true;
                cases.Add(RunCase("priority-alt-s-beats-peer",Chord(0x53),2,0,0,0,0,0));
                cases.Add(RunCase("repeat-still-one-paired-action",new INPUT[]{Key(0x12,false),Key(0x44,false),Key(0x44,false),Key(0x44,true),Key(0x12,true)},1,0,0,0,0,0));
                cases.Add(RunCase("ctrl-alt-d-passes-source",new INPUT[]{Key(0x11,false),Key(0x12,false),Key(0x44,false),Key(0x44,true),Key(0x12,true),Key(0x11,true)},0,0,1,0,0,0));
                cases.Add(RunCase("unrelated-alt-f4-passes-source",Chord(0x73),0,0,-1,0,0,1));Need(configure(0)==1,"DISABLE_PRIORITY_FAILED");
                cases.Add(RunCase("removing-binding-restores-peer",Chord(0x44),0,1,-1,0,0,0));Need(configure(1)==1,"PRIORITY_D_BINDING_FAILED");context(IntPtr.Zero,1);
                cases.Add(RunCase("background-settings-still-allows-source",Chord(0x44),1,0,0,0,0,0));context(new IntPtr(Snapshot()[Window]),1);
                cases.Add(RunCase("foreground-settings-blocks-action",Chord(0x44),0,0,0,0,0,0));Need(recording(33)==1,"RECORDING_INSTALL_FAILED");
                cases.Add(RunCase("foreground-recording-context-is-tagged",Chord(0x44),1,0,0,0,33,0));Need(recording(0)==1,"RECORDING_END_FAILED");context(IntPtr.Zero,0);Need(configure(4)==1,"MOUSE_X1_BINDING_FAILED");
                cases.Add(RunCase("mapped-x1-consumed-not-back-command",new INPUT[]{Side(1,false),Side(1,true)},0x80000001U,0,-1,1,0,0));
                cases.Add(RunCase("unbound-x2-reaches-source",new INPUT[]{Side(2,false),Side(2,true)},0,0,-1,2,0,0));Need(configure(0)==1,"MOUSE_DISABLE_FAILED");context(new IntPtr(Snapshot()[Window]),1);Need(recording(44)==1,"MOUSE_RECORDING_INSTALL_FAILED");
                cases.Add(RunCase("recording-unbound-x2-is-tagged",new INPUT[]{Side(2,false),Side(2,true)},0x80000002U,0,-1,2,44,0));Need(recording(0)==1,"MOUSE_RECORDING_END_FAILED");
                cases.Add(RunCase("revoked-recording-x2-passes-source",new INPUT[]{Side(2,false),Side(2,true)},0,0,-1,2,0,0));context(IntPtr.Zero,0);Need(configure(4)==1,"MOUSE_CAPTURE_TEST_BINDING_FAILED");capture(7);
                cases.Add(RunCase("capture-context-does-not-consume-x1",new INPUT[]{Side(1,false),Side(1,true)},0,0,-1,1,0,0));capture(0);stop();nativeStarted=false;Need(current()==0,"STOPPED_NATIVE_EVENT_REMAINED_CURRENT");result["nativeHookStopped"]=true;
                cases.Add(RunCase("stopping-hook-restores-peer",Chord(0x44),0,1,-1,0,0,0));Need(cases.Count==17,"FIXTURE_CASE_COUNT_CHANGED");result["ok"]=true;
            }catch(Exception error){result["error"]=error.Message;result["failedCase"]=pendingCase;try{result["failedCasePeerAfter"]=Snapshot();result["keysReleasedAtFailure"]=Released();}catch{result["failedCaseMetadataUnavailable"]=true;}}
            finally {
                if(nativeStarted&&stop!=null){stop();nativeStarted=false;result["nativeHookStopped"]=true;}
                if(peer!=null){try{bool killed=false;if(!peer.HasExited){map.Write(Command*8,2L);map.Write(Request*8,++request);if(!peer.WaitForExit(2500)){killed=true;peer.Kill();peer.WaitForExit(2500);}}result["ownedPeerStopped"]=peer.HasExited;result["ownedPeerForcedTermination"]=killed;if(peer.HasExited){result["ownedPeerExitCode"]=peer.ExitCode;if(killed||peer.ExitCode!=0)result["ok"]=false;}}catch{result["ok"]=false;result["ownedPeerStopped"]=false;}peer.Dispose();peer=null;}
                if(pointerSaved)result["pointerRestored"]=SetCursorPos(pointer.x,pointer.y);result["executedCases"]=cases.Count;result["nativeLibraryHeldUntilProcessExit"]=module!=IntPtr.Zero;
            }
        }
        return result;
    }
    [STAThread] public static int Main(string[] args) {
        if(Environment.OSVersion.Platform!=PlatformID.Win32NT||!Environment.UserInteractive||Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true"||Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")!="github-hosted")return 2;
        if(args.Length==2&&args[0]=="--source-owner"){const string prefix="Local\\EchoLingoPriority-";Guid id;if(!args[1].StartsWith(prefix,StringComparison.Ordinal)||!Guid.TryParseExact(args[1].Substring(prefix.Length),"N",out id))return 2;}
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        if(args.Length==2&&args[0]=="--source-owner")return Owner(args[1]);
        if(args.Length!=2)return 2;Dictionary<string,object> report=Run(args[0]);string json=new JavaScriptSerializer().Serialize(report);File.WriteAllText(args[1],json,new System.Text.UTF8Encoding(false));Console.WriteLine(json);return Convert.ToBoolean(report["ok"])?0:1;
    }
}
