// Disposable generated-source peer; RegisterHotKey and the later active hooks
// belong to another process. All input is synthetic SendInput on isolated CI.
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
        X1DoubleDown=28,X2DoubleDown=29,LateMode=30,LateDown=31,LateUp=32,
        LateSwallowedDown=33,LateSwallowedUp=34,LateActions=35,DecoyWindow=36,
        DecoyEditor=37,DecoyForeground=38,DecoyFocus=39,DecoySelectionStart=40,
        DecoySelectionLength=41,CommandError=42,LateInstalled=43,
        LastSuffixKey=44,LastSuffixFlags=45,LastSuffixScan=46,LastSuffixLeftAlt=47,
        LastSuffixRightAlt=48,LastSuffixAlt=49,LastSuffixControl=50,LastSuffixShift=51,
        LastSuffixLeftWin=52,LastSuffixRightWin=53,LastAltKey=54,LastAltFlags=55,
        LastAltScan=56,LastSuffixGuiSucceeded=57,LastSuffixGuiFlags=58,LastSuffixFocusIsEditor=59,Revision=63;
    const uint RecoverySuccesses=0,RecoveryRequests=1,RecoveryAttempts=2,RecoveryPending=3,
        RecoveryDeferred=4,RecoveryFailures=5,ObservedDown=6,ObservedUp=7,
        AcceptedPairs=8,DiscardedPairs=9,BlockedPairs=10,Enqueued=11,StaleEvents=12;
    const int QuietObservationMilliseconds=150;
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll",CharSet=CharSet.Ansi,SetLastError=true)] static extern IntPtr GetProcAddress(IntPtr module,string name);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookExW(int kind,Hook callback,IntPtr module,uint thread);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr word,IntPtr parameter);
    [DllImport("user32.dll",SetLastError=true)] static extern bool UnhookWindowsHookEx(IntPtr hook);
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
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate int Recover();
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate ulong Diagnostic(uint key);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Stop();
    static Poll poll;
    static Recover recover;
    static Diagnostic diagnostic;
    static MemoryMappedViewAccessor map;
    static Process peer;
    static long request;
    static bool nativeStarted;
    static bool ownedHeldKeys;
    static Dictionary<string,object> pendingCase;
    static void Need(bool condition,string reason) { if(!condition)throw new InvalidOperationException(reason); }
    static T Function<T>(IntPtr module,string name) where T:class {
        IntPtr address=GetProcAddress(module,name);Need(address!=IntPtr.Zero,"NATIVE_EXPORT_MISSING:"+name);
        return Marshal.GetDelegateForFunctionPointer(address,typeof(T)) as T;
    }
    static INPUT Key(ushort key,bool up) { INPUT value=new INPUT();value.type=1;value.data.keyboard.key=key;value.data.keyboard.flags=up?2U:0U;return value; }
    static INPUT AltKey(bool right,bool up) { INPUT value=Key(right?(ushort)0xa5:(ushort)0xa4,up);if(right)value.data.keyboard.flags|=1;return value; }
    static INPUT ScanKey(ushort scan,bool extended,bool up) { INPUT value=Key(0,up);value.data.keyboard.scan=scan;value.data.keyboard.flags|=8U|(extended?1U:0U);return value; }
    static INPUT Side(uint button,bool up) { INPUT value=new INPUT();value.data.mouse.data=button;value.data.mouse.flags=up?0x100U:0x80U;return value; }
    static void Send(params INPUT[] values) { Need(SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)))==(uint)values.Length,"OWN_SENDINPUT_REJECTED"); }
    static void Wait(Func<bool> predicate,int milliseconds,string reason) {
        Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<milliseconds) { if(predicate())return;if(peer!=null&&peer.HasExited)throw new InvalidOperationException("OWN_PEER_EXITED");Application.DoEvents();Thread.Sleep(1); }
        throw new InvalidOperationException("TIMEOUT:"+reason);
    }
    static bool Released() { foreach(int key in new int[]{0x10,0x11,0x12,0x44,0x53,0x73,5,6})if((GetAsyncKeyState(key)&0x8000)!=0)return false;return true; }
    static long[] Snapshot() {
        long[] values=new long[64];Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<2000) { long before=map.ReadInt64(Revision*8);if((before&1)!=0){Thread.Sleep(1);continue;}map.ReadArray<long>(0,values,0,values.Length);if(before==map.ReadInt64(Revision*8))return values; }
        throw new InvalidOperationException("OWN_PEER_SNAPSHOT_NOT_STABLE");
    }
    static void Ask(int command) { map.Write(Command*8,(long)command);map.Write(Request*8,++request);Wait(delegate{return map.ReadInt64(Ack*8)==request;},2000,"OWN_PEER_COMMAND");Need(Snapshot()[CommandError]==0,"OWN_PEER_COMMAND_FAILED:"+command); }
    static long[] Prepare(bool pointer) {
        Ask(1);long[] data=Snapshot();uint pid;IntPtr window=new IntPtr(data[Window]);GetWindowThreadProcessId(window,out pid);
        Need(pid==(uint)peer.Id&&data[PeerPid]==peer.Id,"OWN_PEER_WINDOW_OWNER_MISMATCH");uint decoyPid;GetWindowThreadProcessId(new IntPtr(data[DecoyWindow]),out decoyPid);Need(decoyPid==(uint)peer.Id&&data[DecoyWindow]!=data[Window]&&data[DecoyEditor]!=data[Editor]&&data[SelectionLength]>0&&data[DecoySelectionLength]>0,"OWN_DISTINCT_SOURCE_SELECTIONS_NOT_READY");SetForegroundWindow(window);
        Wait(delegate { uint process;uint thread=GetWindowThreadProcessId(window,out process);GUI gui=new GUI();gui.size=(uint)Marshal.SizeOf(typeof(GUI));return process==(uint)peer.Id&&GetForegroundWindow()==window&&GetGUIThreadInfo(thread,ref gui)&&gui.focus==new IntPtr(data[Editor])&&Released(); },2500,"OWN_PEER_FOCUS_AND_RELEASE");
        if(pointer) { RECT bounds;Need(GetWindowRect(new IntPtr(data[Editor]),out bounds),"OWN_EDITOR_BOUNDS_FAILED");POINT point=new POINT();point.x=(bounds.l+bounds.r)/2;point.y=(bounds.t+bounds.b)/2;Need(SetCursorPos(point.x,point.y)&&GetAncestor(WindowFromPoint(point),2)==window,"OWN_POINTER_TARGET_REJECTED"); }
        Wait(delegate{long[] now=Snapshot();return now[Foreground]==1&&now[FocusFlag]==1;},2000,"OWN_PEER_READY_METADATA");return Snapshot();
    }
    static List<ulong[]> Drain() {
        List<ulong[]> events=new List<ulong[]>();if(!nativeStarted)return events;
        for(int index=0;index<100;index++) { ulong[] fields=new ulong[8];int result=poll(fields,8);Need(result>=0,"NATIVE_POLL_FAILED");if(result==0)return events;events.Add(fields); }
        throw new InvalidOperationException("NATIVE_EVENT_FLOOD");
    }
    static Dictionary<string,object> RunCase(string name,INPUT[] inputs,uint expectedId,int peerHotkey,int sourceSuffix,int side,uint expectedLease,int closeRequests) {
        pendingCase=new Dictionary<string,object>{{"name",name},{"expectedNativeId",expectedId},{"expectedPeerHotkey",peerHotkey},{"expectedRecordingLease",expectedLease}};
        bool pointer=side!=0;long[] before=Prepare(pointer);Need(Drain().Count==0,"UNEXPECTED_PENDING_NATIVE_EVENT");
        List<ulong[]> events=new List<ulong[]>();pendingCase["peerBefore"]=before;pendingCase["nativeEvents"]=events;ownedHeldKeys=true;Send(inputs);
        Wait(delegate {
            events.AddRange(Drain());long[] now=Snapshot();bool peerDone=side==0?now[AltUp]>before[AltUp]:expectedId!=0||now[side==1?X1Up:X2Up]>before[side==1?X1Up:X2Up];
            return Released()&&peerDone&&(expectedId==0||events.Count>0)&&(peerHotkey==0||now[peerHotkey==1?HotD:HotS]>before[peerHotkey==1?HotD:HotS])&&(closeRequests==0||now[CloseRequest]>before[CloseRequest]);
        },2500,"OWN_INPUT_COMPLETION:"+name);
        ownedHeldKeys=false;
        // A bounded negative observation, never a product preparation delay.
        Stopwatch quiet=Stopwatch.StartNew();while(quiet.ElapsedMilliseconds<QuietObservationMilliseconds) {events.AddRange(Drain());Application.DoEvents();Thread.Sleep(1);}
        long[] after=Snapshot();Need(events.Count==(expectedId==0?0:1),"WRONG_NATIVE_EVENT_COUNT:"+name);
        if(expectedId!=0)Need(events[0][0]==expectedId&&events[0][1]==1&&events[0][3]==0&&events[0][4]==expectedLease&&events[0][5]==0&&events[0][6]==(ulong)before[Window]&&events[0][7]==(ulong)before[Editor],"WRONG_NATIVE_EVENT_CONTEXT:"+name);
        Need(after[HotD]-before[HotD]==(peerHotkey==1?1:0)&&after[HotS]-before[HotS]==(peerHotkey==2?1:0),"COMPETING_HOTKEY_DELIVERY_WRONG:"+name);
        if(sourceSuffix>=0)Need(sourceSuffix==0?after[SuffixDown]==before[SuffixDown]&&after[SuffixUp]==before[SuffixUp]:after[SuffixDown]>before[SuffixDown],"SOURCE_KEY_PASSTHROUGH_WRONG:"+name);
        if(expectedId!=0)Need(after[KeyMenu]==before[KeyMenu]&&after[MenuLoop]==before[MenuLoop]&&after[AppCommand]==before[AppCommand]&&after[Foreground]==1&&after[FocusFlag]==1&&after[SelectionStart]==before[SelectionStart]&&after[SelectionLength]==before[SelectionLength],"BOUND_INPUT_CHANGED_SOURCE_OR_MENU:"+name);
        if(side!=0) {int down=side==1?X1Down:X2Down,up=side==1?X1Up:X2Up;Need(expectedId==0?after[down]-before[down]==1&&after[up]-before[up]==1:after[down]==before[down]&&after[up]==before[up],"SOURCE_MOUSE_PASSTHROUGH_WRONG:"+name);}
        if(closeRequests>0)Need(after[CloseRequest]-before[CloseRequest]==closeRequests,"UNRELATED_ALT_F4_WAS_SWALLOWED");
        return new Dictionary<string,object>{{"name",name},{"ok",true},{"inputEventCount",inputs.Length},{"nativeEvents",events},{"peerAltD",after[HotD]-before[HotD]},{"peerAltS",after[HotS]-before[HotS]},{"sourceSuffixDowns",after[SuffixDown]-before[SuffixDown]},{"sourceSuffixUps",after[SuffixUp]-before[SuffixUp]},{"sourceMouseDowns",side==0?0:after[side==1?X1Down:X2Down]-before[side==1?X1Down:X2Down]},{"sourceMouseUps",side==0?0:after[side==1?X1Up:X2Up]-before[side==1?X1Up:X2Up]},{"sourceMouseDoubleClickDowns",side==0?0:after[side==1?X1DoubleDown:X2DoubleDown]-before[side==1?X1DoubleDown:X2DoubleDown]},{"scKeyMenu",after[KeyMenu]-before[KeyMenu]},{"menuLoops",after[MenuLoop]-before[MenuLoop]},{"sourceCloseRequests",after[CloseRequest]-before[CloseRequest]},{"sourceStillForeground",after[Foreground]==1},{"sourceFocusIsEditor",after[FocusFlag]==1}};
    }
    static INPUT[] Chord(ushort key) { return new INPUT[]{Key(0x12,false),Key(key,false),Key(key,true),Key(0x12,true)}; }

    static ulong Diag(uint key) { ulong value=diagnostic(key);Need(value!=UInt64.MaxValue,"NATIVE_DIAGNOSTIC_MISSING:"+key);return value; }
    static ulong[] Diagnostics() { ulong[] values=new ulong[13];for(uint index=0;index<values.Length;index++)values[index]=Diag(index);return values; }
    static void Quiet(List<ulong[]> events) {
        // Only a bounded negative observation after input completion. Recovery
        // readiness and held-pair transitions are awaited through real counters.
        Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<QuietObservationMilliseconds){events.AddRange(Drain());Application.DoEvents();Thread.Sleep(1);}
    }
    static bool SameSelection(long[] before,long[] after) {
        return after[SelectionStart]==before[SelectionStart]&&after[SelectionLength]==before[SelectionLength]&&after[DecoySelectionStart]==before[DecoySelectionStart]&&after[DecoySelectionLength]==before[DecoySelectionLength];
    }
    static Dictionary<string,object> ObserveBothAltScanComparison() {
        // This runs only after the unchanged virtual-key case has already failed.
        // Preserve that failure; compare physical scan-code semantics without
        // presuming either an action or pass-through is the expected outcome.
        long[] before=Prepare(false);Need(Drain().Count==0,"SCAN_COMPARISON_PENDING_EVENT");ulong[] diagBefore=Diagnostics();List<ulong[]> events=new List<ulong[]>();
        ownedHeldKeys=true;Send(ScanKey(0x38,false,false),ScanKey(0x38,true,false),ScanKey(0x38,false,true),ScanKey(0x20,false,false),ScanKey(0x20,false,true),ScanKey(0x38,true,true));
        Wait(delegate{events.AddRange(Drain());return Released()&&Snapshot()[AltUp]-before[AltUp]==2;},2500,"SCAN_COMPARISON_INPUT_RELEASED");ownedHeldKeys=false;Quiet(events);long[] after=Snapshot();
        return new Dictionary<string,object>{{"diagnosticOnly",true},{"changesOriginalGateResult",false},{"inputEventCount",6},{"inputRepresentation","KEYEVENTF_SCANCODE; Alt=0x38; right Alt extended; D=0x20"},{"nativeEvents",events},{"peerBefore",before},{"peerAfter",after},{"unconsumedSuffixObserved",after[SuffixDown]>before[SuffixDown]},{"diagnosticsBefore",diagBefore},{"diagnosticsAfter",Diagnostics()},{"sourceSelectionPreserved",SameSelection(before,after)},{"sourceStillForeground",after[Foreground]==1},{"sourceFocusIsEditor",after[FocusFlag]==1},{"scKeyMenu",after[KeyMenu]-before[KeyMenu]},{"menuLoops",after[MenuLoop]-before[MenuLoop]},{"keysReleased",Released()}};
    }
    static Dictionary<string,object> RunBothAltCase() {
        const string name="both-alt-release-left-keeps-right-anchor";
        pendingCase=new Dictionary<string,object>{{"name",name},{"expectedNativeId",1},{"expectedPeerHotkey",0},{"expectedRecordingLease",0},{"inputPhases","ordinary Alt prelude, then priority suffix"}};
        // The first release precedes any priority intent. Keep all six original
        // inputs, but assert ordinary Alt behavior and owned suffix separately.
        long[] beforePrelude=Prepare(false);Need(Drain().Count==0,"PHASE_COMPARISON_PENDING_EVENT");ulong[] diagBefore=Diagnostics();List<ulong[]> preludeEvents=new List<ulong[]>();
        pendingCase["beforePrelude"]=beforePrelude;pendingCase["preludeEvents"]=preludeEvents;
        ownedHeldKeys=true;Send(AltKey(false,false),AltKey(true,false),AltKey(false,true));
        Wait(delegate{long[] now=Snapshot();return now[AltDown]-beforePrelude[AltDown]==2&&now[AltUp]-beforePrelude[AltUp]==1&&(GetAsyncKeyState(0xa4)&0x8000)==0&&(GetAsyncKeyState(0xa5)&0x8000)!=0;},2500,"PHASE_COMPARISON_PRELUDE_RELEASED");
        // Command 7 only acknowledges and publishes on the owned source UI
        // thread. Keep the bounded zero-action observation; an acknowledgement
        // alone is not a promise that all asynchronous menu work has finished.
        Ask(7);Quiet(preludeEvents);long[] afterPrelude=Snapshot();ulong[] diagAfterPrelude=Diagnostics();long[] beforeSuffix=Snapshot();List<ulong[]> suffixEvents=new List<ulong[]>();
        pendingCase["afterPrelude"]=afterPrelude;pendingCase["beforeSuffix"]=beforeSuffix;pendingCase["nativeEvents"]=suffixEvents;
        uint sourcePid;uint sourceThread=GetWindowThreadProcessId(new IntPtr(beforePrelude[Window]),out sourcePid);GUI sourceGui=new GUI();sourceGui.size=(uint)Marshal.SizeOf(typeof(GUI));bool sourceGuiKnown=sourcePid==(uint)peer.Id&&sourceThread!=0&&GetGUIThreadInfo(sourceThread,ref sourceGui);
        pendingCase["beforeSuffixGuiMetadataAvailable"]=sourceGuiKnown;pendingCase["beforeSuffixGuiFlags"]=sourceGui.flags;
        Need(sourceGuiKnown&&sourceGui.focus==new IntPtr(beforePrelude[Editor])&&(sourceGui.flags&0x1c)==0&&afterPrelude[KeyMenu]==beforeSuffix[KeyMenu]&&afterPrelude[MenuLoop]==beforeSuffix[MenuLoop],"TWO_ALT_PRELUDE_MENU_NOT_SETTLED");
        Need(preludeEvents.Count==0&&afterPrelude[MaskDown]==beforePrelude[MaskDown]&&afterPrelude[MaskUp]==beforePrelude[MaskUp]&&diagAfterPrelude[ObservedDown]==diagBefore[ObservedDown]&&diagAfterPrelude[ObservedUp]==diagBefore[ObservedUp]&&diagAfterPrelude[AcceptedPairs]==diagBefore[AcceptedPairs]&&diagAfterPrelude[Enqueued]==diagBefore[Enqueued],"ORDINARY_ALT_PRELUDE_CLAIMED_OR_MASKED");
        Need(afterPrelude[SuffixDown]==beforePrelude[SuffixDown]&&afterPrelude[SuffixUp]==beforePrelude[SuffixUp]&&afterPrelude[HotD]==beforePrelude[HotD]&&afterPrelude[HotS]==beforePrelude[HotS]&&SameSelection(beforePrelude,beforeSuffix)&&beforeSuffix[Foreground]==1&&beforeSuffix[FocusFlag]==1,"ORDINARY_ALT_PRELUDE_CHANGED_SOURCE");
        Send(Key(0x44,false),Key(0x44,true),AltKey(true,true));
        Wait(delegate{suffixEvents.AddRange(Drain());return Released()&&Snapshot()[AltUp]-beforePrelude[AltUp]==2;},2500,"PHASE_COMPARISON_SUFFIX_RELEASED");ownedHeldKeys=false;Quiet(suffixEvents);long[] afterSuffix=Snapshot();
        pendingCase["afterSuffix"]=afterSuffix;ulong[] diagAfterSuffix=Diagnostics();OwnSourceEvent(suffixEvents,1,beforePrelude,name);
        Need(afterSuffix[SuffixDown]==beforeSuffix[SuffixDown]&&afterSuffix[SuffixUp]==beforeSuffix[SuffixUp]&&afterSuffix[HotD]==beforeSuffix[HotD]&&afterSuffix[HotS]==beforeSuffix[HotS],"TWO_ALT_SUFFIX_LEAKED_TO_SOURCE_OR_PEER");
        Need(afterSuffix[KeyMenu]==beforeSuffix[KeyMenu]&&afterSuffix[MenuLoop]==beforeSuffix[MenuLoop]&&afterSuffix[AppCommand]==beforeSuffix[AppCommand]&&afterSuffix[MaskDown]-beforeSuffix[MaskDown]==1&&afterSuffix[MaskUp]-beforeSuffix[MaskUp]==1,"TWO_ALT_PRIORITY_SUFFIX_CHANGED_MENU");
        Need(SameSelection(beforePrelude,afterSuffix)&&afterSuffix[Foreground]==1&&afterSuffix[FocusFlag]==1&&diagAfterSuffix[ObservedDown]-diagAfterPrelude[ObservedDown]==1&&diagAfterSuffix[ObservedUp]-diagAfterPrelude[ObservedUp]==1&&diagAfterSuffix[AcceptedPairs]-diagAfterPrelude[AcceptedPairs]==1&&diagAfterSuffix[Enqueued]-diagAfterPrelude[Enqueued]==1,"TWO_ALT_SUFFIX_LOST_OR_RETARGETED_SOURCE_ACTION");
        return new Dictionary<string,object>{{"name",name},{"ok",true},{"inputEventCount",6},{"inputPhases","ordinary Alt prelude, then priority suffix"},{"beforePrelude",beforePrelude},{"afterPrelude",afterPrelude},{"beforeSuffix",beforeSuffix},{"afterSuffix",afterSuffix},{"beforeSuffixGuiMetadataAvailable",sourceGuiKnown},{"beforeSuffixGuiFlags",sourceGui.flags},{"preludeEvents",preludeEvents},{"nativeEvents",suffixEvents},{"diagnosticsBefore",diagBefore},{"diagnosticsAfterPrelude",diagAfterPrelude},{"diagnosticsAfterSuffix",diagAfterSuffix},{"preludeScKeyMenu",afterPrelude[KeyMenu]-beforePrelude[KeyMenu]},{"preludeMenuLoops",afterPrelude[MenuLoop]-beforePrelude[MenuLoop]},{"suffixScKeyMenu",afterSuffix[KeyMenu]-beforeSuffix[KeyMenu]},{"suffixMenuLoops",afterSuffix[MenuLoop]-beforeSuffix[MenuLoop]},{"ordinaryAltPreludePassedWithoutMask",true},{"prioritySuffixHadNoMenuSideEffect",true},{"sourceSelectionPreserved",true},{"sourceStillForeground",true},{"sourceFocusIsEditor",true},{"keysReleased",Released()}};
    }
    static void OwnSourceEvent(List<ulong[]> events,uint expected,long[] source,string name) {
        Need(events.Count==1&&events[0][0]==expected&&events[0][1]==1&&events[0][3]==0&&events[0][4]==0&&events[0][5]==0&&events[0][6]==(ulong)source[Window]&&events[0][7]==(ulong)source[Editor],"RECOVERY_WRONG_OR_DUPLICATED_SOURCE_EVENT:"+name);
    }
    static Dictionary<string,object> RunLateHookCase(string name,ushort key,int mode,bool restored,bool legacy) {
        pendingCase=new Dictionary<string,object>{{"name",name},{"latePeerMode",mode},{"recoveryRequested",restored},{"historicalSourceControl",legacy}};
        Prepare(false);if(!legacy){ulong ready=Diag(RecoverySuccesses);Need(recover()==1,"PRE_CONTROL_RECOVERY_REQUEST_REJECTED");Wait(delegate{return Diag(RecoverySuccesses)>ready&&Diag(RecoveryPending)==0;},2500,"PRE_CONTROL_HOOK_READY");}Ask(mode==1?3:4);long[] before=Snapshot();Need(before[LateInstalled]==1&&before[LateMode]==mode,"LATER_ACTIVE_HOOK_NOT_INSTALLED");Need(Drain().Count==0,"LATE_HOOK_PENDING_EVENT");
        ulong[] diagBefore=legacy?null:Diagnostics();pendingCase["peerBefore"]=before;if(diagBefore!=null)pendingCase["diagnosticsBefore"]=diagBefore;
        if(restored){ulong successes=Diag(RecoverySuccesses),requests=Diag(RecoveryRequests);Need(recover()==1,"KEYBOARD_RECOVERY_REQUEST_REJECTED");Wait(delegate{return Diag(RecoveryRequests)>requests&&Diag(RecoverySuccesses)>successes&&Diag(RecoveryPending)==0;},2500,"REAL_KEYBOARD_RECOVERY_COMPLETED");Need(Diag(RecoveryFailures)==diagBefore[RecoveryFailures],"KEYBOARD_RECOVERY_FAILED");}
        List<ulong[]> events=new List<ulong[]>();pendingCase["nativeEvents"]=events;ownedHeldKeys=true;Send(Chord(key));
        Wait(delegate{events.AddRange(Drain());long[] now=Snapshot();return Released()&&now[AltUp]>before[AltUp]&&(restored?events.Count>0:now[LateUp]>before[LateUp]);},2500,"LATER_ACTIVE_INPUT_COMPLETED:"+name);ownedHeldKeys=false;Quiet(events);long[] after=Snapshot();
        Need(after[HotD]==before[HotD]&&after[HotS]==before[HotS],"LATER_ACTIVE_REGISTERHOTKEY_UNEXPECTED_DELIVERY:"+name);
        Need(SameSelection(before,after),"LATER_ACTIVE_SELECTION_CHANGED:"+name);
        int originalEvents=0;foreach(ulong[] value in events)if(value[6]==(ulong)before[Window]&&value[7]==(ulong)before[Editor])originalEvents++;
        if(restored){
            OwnSourceEvent(events,key==0x44?1U:2U,before,name);
            Need(after[LateDown]==before[LateDown]&&after[LateUp]==before[LateUp]&&after[LateActions]==before[LateActions]&&after[LateSwallowedDown]==before[LateSwallowedDown]&&after[LateSwallowedUp]==before[LateSwallowedUp],"RECOVERY_DID_NOT_EXCLUDE_LATER_ACTIVE_PEER:"+name);
            Need(after[SuffixDown]==before[SuffixDown]&&after[SuffixUp]==before[SuffixUp]&&after[Foreground]==1&&after[FocusFlag]==1&&after[KeyMenu]==before[KeyMenu]&&after[MenuLoop]==before[MenuLoop]&&after[AppCommand]==before[AppCommand],"RECOVERY_CHANGED_OR_DELIVERED_TO_SOURCE:"+name);
        }else{
            // The fixed historical module must actually enqueue the decoy
            // context. Current production must discard that changed-source
            // pair; only the later consumer remains a priority-loss control.
            Need(after[LateDown]-before[LateDown]==1&&after[LateUp]-before[LateUp]==1&&after[LateActions]-before[LateActions]==1,"LATER_ACTIVE_HYPOTHESIS_NOT_REPRODUCED:"+name);
            Need(originalEvents==0,"UNRECOVERED_EVENT_MISIDENTIFIED_AS_ORIGINAL_SOURCE:"+name);
            if(mode==1)Need(events.Count==0&&after[LateSwallowedDown]-before[LateSwallowedDown]==1&&after[LateSwallowedUp]-before[LateSwallowedUp]==1,"LATE_CONSUMER_DID_NOT_REPRODUCE_OLD_FAILURE:"+name);
            else{
                Need(after[DecoyForeground]==1&&after[DecoyFocus]==1,"LATE_ACTIVATION_DID_NOT_REPRODUCE_SOURCE_CHANGE:"+name);
                if(legacy)Need(events.Count==1&&events[0][0]==(key==0x44?1U:2U)&&events[0][6]==(ulong)before[DecoyWindow]&&events[0][7]==(ulong)before[DecoyEditor],"HISTORICAL_ACTIVATION_RETARGET_NOT_REPRODUCED:"+name);
                else Need(events.Count==0&&Diag(DiscardedPairs)==diagBefore[DiscardedPairs]+1&&Diag(AcceptedPairs)==diagBefore[AcceptedPairs]&&Diag(Enqueued)==diagBefore[Enqueued]&&Diag(ObservedDown)==diagBefore[ObservedDown]+1&&Diag(ObservedUp)==diagBefore[ObservedUp]+1,"ALT_ANCHOR_DID_NOT_DISCARD_CHANGED_SOURCE:"+name);
            }
        }
        Dictionary<string,object> result=new Dictionary<string,object>{{"name",name},{"ok",true},{"controlOnly",legacy||(!restored&&mode==1)},{"sourceAnchorSafetyAcceptance",!legacy&&!restored&&mode==2},{"historicalSourceControl",legacy},{"lateHookInstalledAfterNative",true},{"latePeerMode",mode},{"recoveryRequested",restored},{"nativeEvents",events},{"originalSourceEventCount",originalEvents},{"peerActionCount",after[LateActions]-before[LateActions]},{"peerSuffixDowns",after[LateDown]-before[LateDown]},{"peerSuffixUps",after[LateUp]-before[LateUp]},{"peerSwallowedDowns",after[LateSwallowedDown]-before[LateSwallowedDown]},{"peerSwallowedUps",after[LateSwallowedUp]-before[LateSwallowedUp]},{"sourceSelectionPreserved",SameSelection(before,after)},{"sourceStillForeground",after[Foreground]==1},{"sourceFocusIsEditor",after[FocusFlag]==1},{"sourceScKeyMenu",after[KeyMenu]-before[KeyMenu]},{"sourceMenuLoops",after[MenuLoop]-before[MenuLoop]},{"generatedDecoyIsForeground",after[DecoyForeground]==1},{"queuedGeneratedDecoyEventCount",events.Count-originalEvents},{"nativeCaptureOrCopyInvoked",false}};
        if(!legacy){result["diagnosticsBefore"]=diagBefore;result["diagnosticsAfter"]=Diagnostics();}Ask(5);return result;
    }
    // change: 0=ordinary held pair, 1=disable binding while held,
    // 2=move to the other owned window, 3=later peer consumes only our key-up,
    // 4=release Alt first while the owned suffix is still physically held.
    static Dictionary<string,object> RunHeldRecoveryCase(string name,ushort key,int change,Configure configure) {
        pendingCase=new Dictionary<string,object>{{"name",name},{"heldChange",change}};Ask(5);Need(configure(3)==1,"HELD_BINDING_SETUP_FAILED");long[] before=Prepare(false);Need(Drain().Count==0,"HELD_PENDING_EVENT");ulong[] diagBefore=Diagnostics();pendingCase["peerBefore"]=before;pendingCase["diagnosticsBefore"]=diagBefore;
        List<ulong[]> events=new List<ulong[]>();pendingCase["nativeEvents"]=events;ownedHeldKeys=true;Send(Key(0x12,false),Key(key,false));Wait(delegate{return Diag(ObservedDown)>diagBefore[ObservedDown]&&Snapshot()[AltDown]>before[AltDown];},2500,"NATIVE_OBSERVED_OWNED_DOWN");Need(Drain().Count==0,"ACTION_FIRED_BEFORE_KEY_UP");
        if(change==1)Need(configure(2)==1,"HELD_BINDING_DISABLE_FAILED");if(change==2){Ask(6);Wait(delegate{long[] now=Snapshot();return now[DecoyForeground]==1&&now[DecoyFocus]==1;},2000,"OWNED_DECOY_ACTIVATION");}
        ulong successes=Diag(RecoverySuccesses),deferred=Diag(RecoveryDeferred),blocked=Diag(BlockedPairs);
        if(change==3){Ask(3);Send(Key(key,true),Key(0x12,true));ownedHeldKeys=false;Wait(delegate{return Released()&&Snapshot()[LateSwallowedUp]>before[LateSwallowedUp]&&Snapshot()[AltUp]>before[AltUp];},2500,"PEER_CONSUMED_KEY_UP");}
        Need(recover()==1,"HELD_RECOVERY_REQUEST_REJECTED");
        Wait(delegate{return Diag(RecoveryPending)!=0&&Diag(RecoveryDeferred)>deferred;},2500,"RECOVERY_DEFERRED_UNTIL_OWNED_KEY_UP");Need(Diag(RecoverySuccesses)==successes,"HOOK_REINSTALLED_INSIDE_HELD_PAIR");
        if(change==4){Send(Key(0x12,true));Wait(delegate{return Snapshot()[AltUp]>before[AltUp]&&Diag(RecoveryPending)!=0;},2500,"ALT_RELEASED_WITH_SUFFIX_STILL_OWNED");Need(Diag(RecoverySuccesses)==successes&&Diag(ObservedUp)==diagBefore[ObservedUp]&&Drain().Count==0,"ALT_UP_PREMATURELY_REINSTALLED_OR_FIRED");Send(Key(key,true));ownedHeldKeys=false;}
        else if(change!=3){Send(Key(key,true),Key(0x12,true));ownedHeldKeys=false;}
        Wait(delegate{events.AddRange(Drain());long[] now=Snapshot();return Released()&&now[AltUp]>before[AltUp]&&(change==3?Diag(RecoveryPending)!=0:Diag(RecoverySuccesses)>successes&&Diag(RecoveryPending)==0&&Diag(ObservedUp)>diagBefore[ObservedUp]);},2500,change==3?"UNOBSERVABLE_RELEASE_SAFELY_STAYS_DEFERRED":"HELD_RELEASE_AND_RECOVERY_COMPLETED");Quiet(events);long[] after=Snapshot();
        if(change==0||change==4)OwnSourceEvent(events,key==0x44?1U:2U,before,name);else Need(events.Count==0,"HELD_OLD_INTENT_CAPTURED_NEW_CONTEXT:"+name);
        Need(SameSelection(before,after)&&after[HotD]==before[HotD]&&after[HotS]==before[HotS]&&after[SuffixDown]==before[SuffixDown]&&after[SuffixUp]==before[SuffixUp],"HELD_RELEASE_OR_SELECTION_LEAKED:"+name);
        Need(change==2?after[DecoyForeground]==1&&after[DecoyFocus]==1:after[Foreground]==1&&after[FocusFlag]==1,"HELD_RECOVERY_ACTIVATED_WRONG_WINDOW:"+name);
        Need(Diag(RecoveryFailures)==diagBefore[RecoveryFailures],"HELD_RECOVERY_FAILED");if(change==3)Need(Diag(ObservedUp)==diagBefore[ObservedUp]&&Diag(RecoverySuccesses)==successes&&Diag(BlockedPairs)>blocked&&after[LateSwallowedUp]-before[LateSwallowedUp]==1,"UNOBSERVABLE_RELEASE_WAS_UNSAFELY_REARMED");
        Dictionary<string,object> result=new Dictionary<string,object>{{"name",name},{"ok",true},{"heldChange",change},{"nativeEvents",events},{"recoveryDeferredWhileHeld",true},{"recoveryCompleted",change!=3},{"altReleasedBeforeSuffix",change==4},{"ownedKeyUpObservedByNative",change!=3},{"peerConsumedKeyUp",change==3},{"unobservableReleaseRecoveryRemainsDeferred",change==3},{"restartRequiredForUnobservableOwnedRelease",change==3},{"sourceSelectionPreserved",SameSelection(before,after)},{"newForegroundEventDiscarded",change==2},{"nativeCaptureOrCopyInvoked",false},{"diagnosticsBefore",diagBefore},{"diagnosticsAfter",Diagnostics()}};Ask(5);return result;
    }

    sealed class PeerEditor:TextBox {
        readonly PeerForm owner;public PeerEditor(PeerForm owner){this.owner=owner;}
        protected override void WndProc(ref Message message) {
            // Windows replaces the second DOWN with DBLCLK within its native
            // double-click interval; that is still exactly one button down.
            if(message.Msg==0x20b||message.Msg==0x20c||message.Msg==0x20d){int button=(int)((message.WParam.ToInt64()>>16)&0xffff);if(button==1||button==2){bool down=message.Msg!=0x20c;owner.counts[button==1?(down?X1Down:X1Up):(down?X2Down:X2Up)]++;if(message.Msg==0x20d)owner.counts[button==1?X1DoubleDown:X2DoubleDown]++;}}base.WndProc(ref message);
        }
    }
    sealed class PeerForm:Form {
        public readonly long[] counts=new long[64];readonly PeerEditor editor;readonly TextBox decoyEditor;readonly Form decoy;readonly MemoryMappedViewAccessor shared;readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();readonly Hook observe,compete;IntPtr hook,lateHook,registeredWindow;bool d,s,closing,disposed;readonly bool[] lateHeld=new bool[2];long revision;
        public PeerForm(MemoryMappedViewAccessor shared) {
            this.shared=shared;observe=Observe;compete=Compete;Text="Generated priority input peer";KeyPreview=true;StartPosition=FormStartPosition.Manual;Bounds=new Rectangle(45,50,700,250);
            editor=new PeerEditor(this);editor.Multiline=true;editor.SetBounds(20,55,640,115);editor.Text="Generated selected source 41729";Controls.Add(editor);
            decoy=new Form();decoy.Text="Generated competing activation target";decoy.StartPosition=FormStartPosition.Manual;decoy.Bounds=new Rectangle(95,340,650,200);decoy.ShowInTaskbar=false;
            decoyEditor=new TextBox();decoyEditor.Multiline=true;decoyEditor.SetBounds(20,35,590,110);decoyEditor.Text="Generated distinct decoy source 82651";decoy.Controls.Add(decoyEditor);
            MainMenu menu=new MainMenu();menu.MenuItems.Add(new MenuItem("&Generated",new MenuItem[]{new MenuItem("Generated entry")}));Menu=menu;
            timer.Interval=10;timer.Tick+=delegate{long next=shared.ReadInt64(Request*8);if(next!=counts[Ack]){int command=(int)shared.ReadInt64(Command*8);counts[CommandError]=0;if(command==1){Activate();SetForegroundWindow(Handle);editor.Focus();editor.SelectAll();}if(command==2){closing=true;Close();return;}if(command==3||command==4)InstallLate(command==3?1:2);if(command==5)RemoveLate();if(command==6)ActivateDecoy();counts[Ack]=next;}Publish();};
        }
        protected override void OnShown(EventArgs args) {
            base.OnShown(args);decoy.Show();decoyEditor.SelectAll();Activate();SetForegroundWindow(Handle);editor.Focus();editor.SelectAll();registeredWindow=Handle;d=RegisterHotKey(registeredWindow,101,0x4001,0x44);int error=d?0:Marshal.GetLastWin32Error();s=RegisterHotKey(registeredWindow,102,0x4001,0x53);if(!s&&error==0)error=Marshal.GetLastWin32Error();hook=SetWindowsHookExW(13,observe,GetModuleHandleW(null),0);if(hook==IntPtr.Zero&&error==0)error=Marshal.GetLastWin32Error();counts[Status]=d&&s&&hook!=IntPtr.Zero?1:-1;counts[Error]=error;timer.Start();Publish();
        }
        void Publish() {
            counts[PeerPid]=Process.GetCurrentProcess().Id;counts[Window]=Handle.ToInt64();counts[Editor]=editor.Handle.ToInt64();counts[Foreground]=GetForegroundWindow()==Handle?1:0;counts[FocusFlag]=editor.Focused?1:0;counts[SelectionStart]=editor.SelectionStart;counts[SelectionLength]=editor.SelectionLength;
            counts[DecoyWindow]=decoy.Handle.ToInt64();counts[DecoyEditor]=decoyEditor.Handle.ToInt64();counts[DecoyForeground]=GetForegroundWindow()==decoy.Handle?1:0;counts[DecoyFocus]=decoyEditor.Focused?1:0;counts[DecoySelectionStart]=decoyEditor.SelectionStart;counts[DecoySelectionLength]=decoyEditor.SelectionLength;
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
                if(key.key==0x12||key.key==0xa4||key.key==0xa5){counts[LastAltKey]=key.key;counts[LastAltFlags]=key.flags;counts[LastAltScan]=key.scan;if(down)counts[AltDown]++;if(up)counts[AltUp]++;}
                if(key.key==0x44||key.key==0x53){
                    if(down){
                        counts[SuffixDown]++;counts[LastSuffixKey]=key.key;counts[LastSuffixFlags]=key.flags;counts[LastSuffixScan]=key.scan;
                        int[] keys=new int[]{0xa4,0xa5,0x12,0x11,0x10,0x5b,0x5c};
                        for(int i=0;i<keys.Length;i++)counts[LastSuffixLeftAlt+i]=(GetAsyncKeyState(keys[i])&0x8000)!=0?1:0;
                        uint process;uint thread=GetWindowThreadProcessId(GetForegroundWindow(),out process);GUI gui=new GUI();gui.size=(uint)Marshal.SizeOf(typeof(GUI));
                        bool known=process==(uint)Process.GetCurrentProcess().Id&&thread!=0&&GetGUIThreadInfo(thread,ref gui);
                        counts[LastSuffixGuiSucceeded]=known?1:0;counts[LastSuffixGuiFlags]=known?gui.flags:0;counts[LastSuffixFocusIsEditor]=known&&gui.focus==editor.Handle?1:0;
                    }
                    if(up)counts[SuffixUp]++;
                }
                if(key.key==0xe8){if(down)counts[MaskDown]++;if(up)counts[MaskUp]++;}}
            return CallNextHookEx(hook,code,word,parameter);
        }
        void RemoveLate() {
            if(lateHook!=IntPtr.Zero){if(!UnhookWindowsHookEx(lateHook))counts[CommandError]=Marshal.GetLastWin32Error();lateHook=IntPtr.Zero;}counts[LateInstalled]=0;counts[LateMode]=0;lateHeld[0]=false;lateHeld[1]=false;
        }
        void InstallLate(int mode) {
            RemoveLate();if(counts[CommandError]!=0)return;lateHook=SetWindowsHookExW(13,compete,GetModuleHandleW(null),0);if(lateHook==IntPtr.Zero){counts[CommandError]=Marshal.GetLastWin32Error();return;}counts[LateInstalled]=1;counts[LateMode]=mode;
        }
        void ActivateDecoy() { decoy.Activate();SetForegroundWindow(decoy.Handle);decoyEditor.Focus(); }
        IntPtr Compete(int code,IntPtr word,IntPtr parameter) {
            // Installed only by an acknowledged command after production starts.
            // Mode 1 owns exact Alt+D/S and returns nonzero. Mode 2 changes the
            // foreground synchronously, then calls the next production hook.
            if(code==0&&parameter!=IntPtr.Zero){KEYBOARD key=(KEYBOARD)Marshal.PtrToStructure(parameter,typeof(KEYBOARD));int message=word.ToInt32(),slot=key.key==0x44?0:key.key==0x53?1:-1;bool down=message==0x100||message==0x104,up=message==0x101||message==0x105;
                if(slot>=0&&(down||up)){bool exact=(key.flags&0x20)!=0;foreach(int modifier in new int[]{0x10,0x11,0x5b,0x5c})if((GetAsyncKeyState(modifier)&0x8000)!=0)exact=false;if(exact||lateHeld[slot]){if(down){counts[LateDown]++;if(!lateHeld[slot]){counts[LateActions]++;if(counts[LateMode]==2)ActivateDecoy();}lateHeld[slot]=true;}if(up){counts[LateUp]++;lateHeld[slot]=false;}if(counts[LateMode]==1){if(down)counts[LateSwallowedDown]++;if(up)counts[LateSwallowedUp]++;return new IntPtr(1);}}}
            }
            return CallNextHookEx(lateHook,code,word,parameter);
        }
        protected override void OnFormClosing(FormClosingEventArgs args) { if(!closing){counts[CloseRequest]++;args.Cancel=true;}base.OnFormClosing(args); }
        protected override void Dispose(bool disposing) {
            // Close() already disposes a modeless form; the enclosing using
            // disposes it again. Never recreate/read Handle during cleanup.
            if(disposing&&!disposed){disposed=true;timer.Stop();timer.Dispose();RemoveLate();decoy.Dispose();if(hook!=IntPtr.Zero){UnhookWindowsHookEx(hook);hook=IntPtr.Zero;}if(d){d=false;UnregisterHotKey(registeredWindow,101);}if(s){s=false;UnregisterHotKey(registeredWindow,102);}}base.Dispose(disposing);
        }
    }
    static int Owner(string name) {
        using(MemoryMappedFile memory=MemoryMappedFile.OpenExisting(name))using(MemoryMappedViewAccessor shared=memory.CreateViewAccessor())using(PeerForm form=new PeerForm(shared))Application.Run(form);return 0;
    }
    static Dictionary<string,object> Run(string library,bool legacy) {
        int required=legacy?9:35;List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();Dictionary<string,object> result=new Dictionary<string,object>{{"ok",false},{"cases",cases},{"requiredCases",required},{"historicalSourceControl",legacy},{"productRecoveryAcceptance",!legacy},{"actualWindowsInputTested",true},{"syntheticSendInputOnly",true},{"physicalInputTested",false},{"actualApplicationTested",false},{"actualWpsTested",false},{"actualDoubaoTested",false},{"actualBrowserTested",false},{"externalOwnedRegisterHotKeyProcess",true},{"laterActiveHookProcess",true},{"peerPassThroughObservation","earlier-passive-hook-and-later-owned-active-hook-and-owned-window-messages"},{"userContentRead",false},{"clipboardRead",false},{"fixedPreparationSleepMilliseconds",0},{"negativeObservationMilliseconds",QuietObservationMilliseconds},{"heldContextRaceTested",!legacy},{"recordingLeaseExpiryClockTested",false},{"diagnosticFieldOrder",new string[]{"recoverySuccesses","recoveryRequests","recoveryAttempts","recoveryPending","recoveryDeferred","recoveryFailures","priorityKeyDownObserved","priorityKeyUpObserved","priorityPairsAccepted","priorityPairsDiscarded","recoveryOwnedPairsBlocked","eventsEnqueued","eventsStaleContext"}}};
        result["futureCompetingHookPriorityGuaranteed"]=false;result["ownedKeyUpMustBeObservedBeforeReinstall"]=true;result["knownRecoveryBoundary"]="If a later hook consumes an already-owned key-up, remain safely deferred until restart; never infer its release from asynchronous key state.";
        Stop stop=null;POINT pointer;bool pointerSaved=GetCursorPos(out pointer);IntPtr module=IntPtr.Zero;
        string name="Local\\EchoLingoPriority-"+Guid.NewGuid().ToString("N");
        using(MemoryMappedFile memory=MemoryMappedFile.CreateNew(name,512))using(MemoryMappedViewAccessor view=memory.CreateViewAccessor()) {
            map=view;try {
                ProcessStartInfo launch=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"--source-owner "+name);launch.UseShellExecute=false;peer=Process.Start(launch);Need(peer!=null,"OWN_PEER_START_FAILED");
                Wait(delegate{return map.ReadInt64(Status*8)!=0;},5000,"OWN_REGISTERHOTKEY_PEER_READY");Need(map.ReadInt64(Status*8)==1,"OWN_PEER_DEFAULT_REGISTRATION_FAILED:"+map.ReadInt64(Error*8));
                bool stolen=RegisterHotKey(IntPtr.Zero,901,0x4001,0x44);int conflict=Marshal.GetLastWin32Error();if(stolen)UnregisterHotKey(IntPtr.Zero,901);Need(!stolen&&conflict==1409,"INDEPENDENT_PROCESS_ALT_D_OWNERSHIP_NOT_PROVEN");result["independentConflictError"]=conflict;
                cases.Add(RunCase("baseline-peer-owns-alt-d",Chord(0x44),0,1,-1,0,0,0));cases.Add(RunCase("baseline-peer-owns-alt-s",Chord(0x53),0,2,-1,0,0,0));
                module=LoadLibraryW(library);Need(module!=IntPtr.Zero,"NATIVE_FIXTURE_LOAD_FAILED");Start start=Function<Start>(module,"EchoLingoPriorityStart");Configure configure=Function<Configure>(module,"EchoLingoPriorityConfigure");Context context=Function<Context>(module,"EchoLingoPriorityContext");Recording recording=Function<Recording>(module,"EchoLingoPriorityRecording");Token capture=Function<Token>(module,"EchoLingoPriorityCapture");poll=Function<Poll>(module,"EchoLingoPriorityPoll");LastCurrent current=Function<LastCurrent>(module,"EchoLingoPriorityLastCurrent");recover=Function<Recover>(module,"EchoLingoPriorityRecover");diagnostic=Function<Diagnostic>(module,"EchoLingoPriorityDiagnostic");stop=Function<Stop>(module,"EchoLingoPriorityStop");
                Need(start()==1,"EXACT_NATIVE_HOOK_START_FAILED");nativeStarted=true;Need(configure(3)==1,"PRIORITY_BINDINGS_FAILED");
                if(legacy){
                    cases.Add(RunCase("historical-priority-d-beats-earlier-peer",Chord(0x44),1,0,0,0,0,0));cases.Add(RunCase("historical-priority-s-beats-earlier-peer",Chord(0x53),2,0,0,0,0,0));
                }else{
                capture(41);cases.Add(RunCase("priority-alt-d-beats-peer-with-old-capture",Chord(0x44),1,0,0,0,0,0));capture(0);Need(current()==1,"OLDER_CAPTURE_END_INVALIDATED_NEW_KEYBOARD_INTENT");result["oldCaptureEndingDoesNotInvalidatePriorityEvent"]=true;Need(configure(3)==1&&current()==0,"QUEUED_OLD_CONTEXT_REMAINED_CURRENT");result["queuedEventInvalidatedByBindingRevision"]=true;
                cases.Add(RunCase("priority-alt-s-beats-peer",Chord(0x53),2,0,0,0,0,0));
                cases.Add(RunCase("repeat-still-one-paired-action",new INPUT[]{Key(0x12,false),Key(0x44,false),Key(0x44,false),Key(0x44,true),Key(0x12,true)},1,0,0,0,0,0));
                cases.Add(RunCase("left-alt-repeat-still-one-source-action",new INPUT[]{AltKey(false,false),AltKey(false,false),Key(0x44,false),Key(0x44,true),AltKey(false,true)},1,0,0,0,0,0));
                cases.Add(RunCase("right-alt-s-anchors-original-source",new INPUT[]{AltKey(true,false),Key(0x53,false),Key(0x53,true),AltKey(true,true)},2,0,0,0,0,0));
                cases.Add(RunBothAltCase());
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
                cases.Add(RunCase("capture-context-does-not-consume-x1",new INPUT[]{Side(1,false),Side(1,true)},0,0,-1,1,0,0));capture(0);Need(configure(3)==1,"RECOVERY_MATRIX_BINDINGS_FAILED");
                }
                foreach(int mode in new int[]{1,2})foreach(ushort key in new ushort[]{0x44,0x53})cases.Add(RunLateHookCase((legacy?"historical":"current")+"-unrecovered-later-"+(mode==1?"consumer":"activate-and-chain")+"-alt-"+(key==0x44?"d":"s"),key,mode,false,legacy));
                result["laterHookOldPriorityFailureReproduced"]=true;
                result["historicalActivationRetargetReproduced"]=legacy;
                result["changedSourceAltAnchorDiscardVerified"]=!legacy;
                if(!legacy){
                    foreach(int mode in new int[]{1,2})foreach(ushort key in new ushort[]{0x44,0x53})cases.Add(RunLateHookCase("recovered-later-"+(mode==1?"consumer":"activate-and-chain")+"-alt-"+(key==0x44?"d":"s"),key,mode,true,false));
                    cases.Add(RunHeldRecoveryCase("held-alt-d-defers-recovery-and-keeps-one-source-action",0x44,0,configure));cases.Add(RunHeldRecoveryCase("held-alt-s-defers-recovery-and-keeps-one-source-action",0x53,0,configure));
                    cases.Add(RunHeldRecoveryCase("alt-up-before-held-d-up-does-not-reinstall-or-leak",0x44,4,configure));
                    cases.Add(RunHeldRecoveryCase("held-binding-change-consumes-up-and-discards-old-action",0x44,1,configure));cases.Add(RunCase("disabled-alt-d-restores-peer-after-recovery",Chord(0x44),0,1,-1,0,0,0));Need(configure(3)==1,"RESTORE_AFTER_HELD_DISABLE_FAILED");
                    cases.Add(RunHeldRecoveryCase("held-source-change-discards-event-for-new-window",0x44,2,configure));cases.Add(RunHeldRecoveryCase("peer-swallowed-owned-up-safely-defers-until-restart",0x44,3,configure));result["diagnosticsAtCompletion"]=Diagnostics();
                }
                stop();nativeStarted=false;Need(current()==0,"STOPPED_NATIVE_EVENT_REMAINED_CURRENT");result["nativeHookStopped"]=true;
                cases.Add(RunCase("stopping-hook-restores-peer",Chord(0x44),0,1,-1,0,0,0));Need(cases.Count==required,"FIXTURE_CASE_COUNT_CHANGED");result["ok"]=true;
            }catch(Exception error){result["error"]=error.Message;result["failedCase"]=pendingCase;try{long[] failed=Snapshot();result["failedCasePeerAfter"]=failed;result["unconsumedSuffixMetadata"]=new Dictionary<string,object>{{"virtualKey",failed[LastSuffixKey]},{"lowLevelFlags",failed[LastSuffixFlags]},{"scanCode",failed[LastSuffixScan]},{"leftAltAsync",failed[LastSuffixLeftAlt]},{"rightAltAsync",failed[LastSuffixRightAlt]},{"genericAltAsync",failed[LastSuffixAlt]},{"controlAsync",failed[LastSuffixControl]},{"shiftAsync",failed[LastSuffixShift]},{"leftWinAsync",failed[LastSuffixLeftWin]},{"rightWinAsync",failed[LastSuffixRightWin]},{"lastAltVirtualKey",failed[LastAltKey]},{"lastAltFlags",failed[LastAltFlags]},{"lastAltScanCode",failed[LastAltScan]},{"ownGuiMetadataAvailable",failed[LastSuffixGuiSucceeded]},{"ownGuiFlags",failed[LastSuffixGuiFlags]},{"ownFocusWasSourceEditor",failed[LastSuffixFocusIsEditor]}};result["keysReleasedAtFailure"]=Released();}catch{result["failedCaseMetadataUnavailable"]=true;}}
            finally {
                if(!legacy&&nativeStarted&&pendingCase!=null&&result.ContainsKey("error")&&Convert.ToString(pendingCase["name"])=="both-alt-release-left-keeps-right-anchor") {
                    try{result["scanCodeComparison"]=ObserveBothAltScanComparison();}catch(Exception comparisonError){result["scanCodeComparisonError"]=comparisonError.Message;}
                }
                if(ownedHeldKeys){try{Send(Key(0x44,true),Key(0x53,true),Key(0x12,true),AltKey(false,true),AltKey(true,true));ownedHeldKeys=false;result["ownedHeldInputReleasedDuringCleanup"]=true;}catch{result["ownedHeldInputReleasedDuringCleanup"]=false;}}
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
        if(args.Length!=2&&(args.Length!=3||args[2]!="--historical-control"))return 2;Dictionary<string,object> report=Run(args[0],args.Length==3);string json=new JavaScriptSerializer().Serialize(report);File.WriteAllText(args[1],json,new System.Text.UTF8Encoding(false));Console.WriteLine(json);return Convert.ToBoolean(report["ok"])?0:1;
    }
}
