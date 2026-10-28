// Actual proprietary WPS application, generated RTF only. This fixture neither
// redistributes WPS nor substitutes a UIA provider/clipboard implementation.
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

public static class WindowsWpsSelectionFixture {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetLastActivePopup(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint kind);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread, ref GUI info);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int maximum);
    delegate bool EnumWindow(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] input, int size);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [StructLayout(LayoutKind.Sequential)] struct GUI { public uint size,flags; public IntPtr active,focus,capture,menu,move,caret; public int l,t,r,b; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION data; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public KEY keyboard; [FieldOffset(0)] public MOUSE mouse; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort key,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength=262144 };
    static void Need(bool condition, string category) { if(!condition) throw new InvalidOperationException(category); }
    static void Wait(Func<bool> predicate, int deadline, string category) {
        Stopwatch elapsed=Stopwatch.StartNew(); while(elapsed.ElapsedMilliseconds<deadline) { if(predicate()) return; Thread.Sleep(5); }
        throw new InvalidOperationException(category);
    }
    static T Ui<T>(Form pump, Func<T> action) { return (T)pump.Invoke(action); }
    static INPUT Key(ushort key, bool up) { INPUT value=new INPUT(); value.type=1; value.data.keyboard.key=key; value.data.keyboard.flags=up?2U:0U; return value; }
    static void Send(params INPUT[] keys) { Need(SendInput((uint)keys.Length,keys,Marshal.SizeOf(typeof(INPUT)))==keys.Length,"GENERATED_INPUT_REJECTED"); }
    static string ExactText(string text) { return text==null?null:text.TrimEnd('\r','\n'); }
    static bool OwnedProcess(Process process, string executable, DateTime earliest) {
        try { return !process.HasExited && process.StartTime.ToUniversalTime()>=earliest && String.Equals(process.MainModule.FileName,executable,StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }
    static HashSet<int> OwnProcesses(string executable, DateTime earliest) {
        HashSet<int> ids=new HashSet<int>(); foreach(Process process in Process.GetProcessesByName("wps")) using(process) if(OwnedProcess(process,executable,earliest)) ids.Add(process.Id); return ids;
    }
    static IntPtr FindDocument(HashSet<int> owned, string generatedName, Dictionary<string,object> report) {
        IntPtr found=IntPtr.Zero; int count=0,visible=0,matched=0;
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            uint pid; GetWindowThreadProcessId(window,out pid); if(!owned.Contains(unchecked((int)pid))) return true;
            count++; if(!IsWindowVisible(window)) return true; visible++;
            // Titles are read only after exact executable/time ownership proof,
            // only to match our random generated document, and never reported.
            StringBuilder title=new StringBuilder(1024); GetWindowText(window,title,title.Capacity);
            if(title.ToString().IndexOf(generatedName,StringComparison.OrdinalIgnoreCase)>=0) { matched++; found=window; }
            return true;
        },IntPtr.Zero);
        report["ownedTopLevelWindowCount"]=count; report["ownedVisibleWindowCount"]=visible; report["generatedDocumentWindowMatches"]=matched;
        return matched==1?found:IntPtr.Zero;
    }
    static Dictionary<string,object> Context(IntPtr document) {
        uint pid; uint thread=GetWindowThreadProcessId(document,out pid); GUI gui=new GUI(); gui.size=(uint)Marshal.SizeOf(typeof(GUI));
        bool available=GetGUIThreadInfo(thread,ref gui); uint focusPid=0,focusThread=gui.focus==IntPtr.Zero?0:GetWindowThreadProcessId(gui.focus,out focusPid);
        return new Dictionary<string,object> {
            {"foregroundIsGeneratedDocument",GetForegroundWindow()==document},{"gtiSucceeded",available},{"gtiFlags",gui.flags},
            {"focusPresent",gui.focus!=IntPtr.Zero},{"focusRootMatchesDocument",gui.focus!=IntPtr.Zero&&GetAncestor(gui.focus,2)==GetAncestor(document,2)},
            {"focusProcessMatchesDocument",focusPid!=0&&focusPid==pid},{"focusThreadDiffersFromDocument",focusThread!=0&&focusThread!=thread},
            {"activeRootMatchesDocument",gui.active!=IntPtr.Zero&&GetAncestor(gui.active,2)==GetAncestor(document,2)},
            {"documentEnabled",IsWindowEnabled(document)},{"visibleBlockingPopup",BlockingPopup(document)} };
    }
    static bool BlockingPopup(IntPtr document) { IntPtr popup=GetLastActivePopup(document); return !IsWindowEnabled(document)||(popup!=IntPtr.Zero&&popup!=document&&IsWindowVisible(popup)); }
    static void CurrentDocument(IntPtr document) {
        Dictionary<string,object> current=Context(document);
        Need(Convert.ToBoolean(current["foregroundIsGeneratedDocument"])&&Convert.ToBoolean(current["gtiSucceeded"])&&Convert.ToBoolean(current["focusRootMatchesDocument"]),"GENERATED_DOCUMENT_FOCUS_UNAVAILABLE");
        Need(!Convert.ToBoolean(current["visibleBlockingPopup"]),"FIRST_RUN_OR_MODAL_DIALOG_BLOCKED_DOCUMENT");
        foreach(int key in new int[]{1,2,4,5,6,0x10,0x11,0x12,0x5b,0x5c}) Need((GetAsyncKeyState(key)&0x8000)==0,"UNEXPECTED_HELD_INPUT");
    }
    static bool GeneratedKeysReleased() {
        foreach(int key in new int[]{0x11,0x24,0x41,0x43}) if((GetAsyncKeyState(key)&0x8000)!=0) return false;
        return true;
    }
    sealed class Seed { public DataObject data; public string[] formats; }
    static Seed SetSeed() {
        DataObject data=new DataObject(); data.SetData(DataFormats.UnicodeText,false,"EchoLingo generated WPS previous clipboard");
        data.SetData(DataFormats.Html,false,"<p>EchoLingo generated WPS previous clipboard</p>"); data.SetData(DataFormats.Rtf,false,"{\\rtf1 EchoLingo generated WPS previous clipboard}");
        Clipboard.SetDataObject(data,true,0,0); IDataObject published=Clipboard.GetDataObject(); Need(published!=null,"CLIPBOARD_SEED_UNAVAILABLE");
        string[] formats=published.GetFormats(false); Array.Sort(formats,StringComparer.Ordinal); return new Seed { data=data,formats=formats };
    }
    static void CheckSeed(Seed seed) {
        IDataObject actual=Clipboard.GetDataObject(); Need(actual!=null,"RESTORED_CLIPBOARD_UNAVAILABLE"); string[] formats=actual.GetFormats(false); Array.Sort(formats,StringComparer.Ordinal);
        Need(formats.Length==seed.formats.Length,"RICH_CLIPBOARD_FORMATS_CHANGED"); for(int i=0;i<formats.Length;i++) Need(formats[i]==seed.formats[i],"RICH_CLIPBOARD_FORMATS_CHANGED");
        foreach(string format in seed.data.GetFormats(false)) Need(Object.Equals(actual.GetData(format,false),seed.data.GetData(format,false)),"RICH_CLIPBOARD_VALUE_CHANGED");
    }
    static Dictionary<string,object> CopyOnce(string helper, string assembly) {
        string name="Local\\EchoLingo-cancel-"+Guid.NewGuid().ToString("N");
        using(EventWaitHandle cancel=new EventWaitHandle(false,EventResetMode.ManualReset,name)) {
            ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell/v1.0/powershell.exe"));
            start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+helper+"\" -Mode selected-text -SelectionStrategy copy -NativeAssemblyPath \""+assembly+"\" -NativeCancellationEvent \""+name+"\"";
            start.UseShellExecute=false; start.CreateNoWindow=true; start.RedirectStandardOutput=true; start.RedirectStandardError=true; start.StandardOutputEncoding=new UTF8Encoding(false);
            using(Process process=Process.Start(start)) {
                Task<string> output=process.StandardOutput.ReadToEndAsync(),error=process.StandardError.ReadToEndAsync();
                try {
                    Need(process.WaitForExit(12000),"HELPER_DEADLINE"); Need(Task.WaitAll(new Task[]{output,error},2000),"HELPER_PIPE_DEADLINE");
                    Need(output.Result.Length<=262144&&error.Result.Length<=65536,"HELPER_OUTPUT_LIMIT");
                    return Json.Deserialize<Dictionary<string,object>>(output.Result.Trim('\ufeff',' ','\r','\n'));
                } finally { if(!process.HasExited) { cancel.Set(); if(!process.WaitForExit(2000)) { process.Kill(); Need(process.WaitForExit(2000),"OWN_HELPER_STOP_FAILED"); } } }
            }
        }
    }
    static Dictionary<string,object> NumericHealth(Dictionary<string,object> reply) {
        Need(reply.ContainsKey("captureHealth")&&reply["captureHealth"] is Dictionary<string,object>,"HELPER_HEALTH_MISSING");
        Dictionary<string,object> raw=(Dictionary<string,object>)reply["captureHealth"],safe=new Dictionary<string,object>();
        string[] allowed={"selectionQueryCount","copyStrategy","copyPhase","copyNativeContextValid","copyNativeContextChecks","copyNativeGuardReason","copyNativeEditable","copyNativeProtection","copyNativeSelectionKnown","copyNativeSelectionNonempty","copyProtectionProbe","copyProtectionProbeMilliseconds","copyProtectionUnknown","copySnapshotOutcome","copyDispatchInserted","copyOwnInputObserved","copyOwnerOutcome","copyClipboardRestored","copyTerminalReason","copyNativeInvalidReason","copyNativeGtiSucceeded","copyNativeGtiFlags","copyNativeFocusPresent","copyNativeFocusProcessMatchesForeground","copyNativeFocusRootMatchesForeground","copyNativeActivePresent","copyNativeActiveRootMatchesForeground"};
        foreach(string key in allowed) if(raw.ContainsKey(key)) { object value=raw[key]; Need(value is int||value is long||value is uint||value is ulong,"HELPER_HEALTH_NOT_INTEGER"); long number=Convert.ToInt64(value); Need(number>=0,"HELPER_HEALTH_NEGATIVE"); safe[key]=number; }
        return safe;
    }
    public static Dictionary<string,object> Run(string executable, string helper, string assembly, string temporary, long installStartedTicks) {
        Need(!executable.Contains("\"")&&!helper.Contains("\"")&&!assembly.Contains("\""),"INVALID_TEST_PATH");
        DateTime earliest=new DateTime(installStartedTicks,DateTimeKind.Utc); string token="echolingo-generated-wps-"+Guid.NewGuid().ToString("N");
        string expected="EchoLingo generated WPS selection "+Guid.NewGuid().ToString("N")+". Only this disposable document may be copied.";
        string documentPath=Path.Combine(temporary,token+".rtf"); File.WriteAllText(documentPath,"{\\rtf1\\ansi\\deff0 "+expected+"}",new UTF8Encoding(false));
        var report=new Dictionary<string,object>{{"ok",false},{"actualWpsTested",false},{"actualWpsLaunched",false},{"actualWpsHelperCalled",false},
            {"registeredShortcutTested",false},{"generatedDocumentOnly",true},{"userContentRead",false},{"clipboardOwnerUsesLiveUiPump",true},{"manualCopyDispatches",0},{"helperCalls",0}};
        uint ownedClipboard=0; bool ownsClipboard=false; string stage="empty-runner-clipboard";
        IDataObject previous=Clipboard.GetDataObject(); Need(previous==null||previous.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");
        using(Form pump=new Form()) {
            pump.Text="EchoLingo generated clipboard pump"; pump.ShowInTaskbar=false; pump.Opacity=0; pump.StartPosition=FormStartPosition.Manual; pump.Bounds=new Rectangle(0,0,1,1);
            bool finished=false; Thread worker=null; Process launched=null; pump.FormClosing+=delegate(object sender,FormClosingEventArgs args){if(!finished)args.Cancel=true;};
            pump.Shown+=delegate { worker=new Thread(delegate() {
                try {
                    stage="launch-generated-document"; ProcessStartInfo start=new ProcessStartInfo(executable,"\""+documentPath+"\""); start.UseShellExecute=false;
                    start.CreateNoWindow=true; start.RedirectStandardOutput=true; start.RedirectStandardError=true;
                    launched=Process.Start(start); launched.StandardOutput.BaseStream.CopyToAsync(Stream.Null); launched.StandardError.BaseStream.CopyToAsync(Stream.Null);
                    report["actualWpsLaunched"]=true;
                    IntPtr document=IntPtr.Zero;
                    Wait(delegate { document=FindDocument(OwnProcesses(executable,earliest),token,report); return document!=IntPtr.Zero; },30000,"FIRST_RUN_OR_DOCUMENT_WINDOW_UNAVAILABLE");
                    stage="generated-document-focus";
                    Need(!BlockingPopup(document),"FIRST_RUN_OR_MODAL_DIALOG_BLOCKED_DOCUMENT"); Need(SetForegroundWindow(document),"GENERATED_DOCUMENT_ACTIVATION_REJECTED");
                    Wait(delegate { return GetForegroundWindow()==document; },3000,"GENERATED_DOCUMENT_DID_NOT_FOREGROUND"); CurrentDocument(document);
                    // Opening our sole RTF leaves its document editor focused.
                    // One Ctrl+Home/Ctrl+A selects that document only; no text is
                    // typed, no dialog buttons are invoked, and no retry occurs.
                    stage="select-generated-document";
                    Send(Key(0x11,false),Key(0x24,false),Key(0x24,true),Key(0x41,false),Key(0x41,true),Key(0x11,true));
                    report["generatedSelectionDispatches"]=1;
                    Wait(GeneratedKeysReleased,1500,"GENERATED_SELECTION_KEYS_NOT_RELEASED");
                    Ui(pump,delegate { SetSeed(); return true; }); ownedClipboard=GetClipboardSequenceNumber(); ownsClipboard=true;
                    stage="manual-single-copy"; CurrentDocument(document); report["contextBeforeManualCopy"]=Context(document);
                    uint before=ownedClipboard; Send(Key(0x11,false),Key(0x43,false),Key(0x43,true),Key(0x11,true)); report["manualCopyDispatches"]=1;
                    Wait(delegate { return Ui(pump,delegate { return GetClipboardSequenceNumber()!=before&&Clipboard.ContainsText()&&ExactText(Clipboard.GetText(TextDataFormat.UnicodeText))==expected; }); },2500,"MANUAL_SINGLE_COPY_NOT_EXACT_GENERATED_SELECTION");
                    ownedClipboard=GetClipboardSequenceNumber(); report["manualCopyExactSelection"]=true;
                    Wait(GeneratedKeysReleased,1500,"GENERATED_MANUAL_COPY_KEYS_NOT_RELEASED");
                    Seed seed=Ui(pump,delegate { return SetSeed(); }); ownedClipboard=GetClipboardSequenceNumber();
                    stage="single-production-helper-copy"; CurrentDocument(document); report["contextBeforeHelper"]=Context(document);
                    Stopwatch elapsed=Stopwatch.StartNew(); report["helperCalls"]=1; report["actualWpsHelperCalled"]=true;
                    Dictionary<string,object> reply=CopyOnce(helper,assembly); report["helperElapsedMilliseconds"]=elapsed.ElapsedMilliseconds;
                    Dictionary<string,object> health=NumericHealth(reply); report["nativeHealth"]=health;
                    bool success=reply.ContainsKey("ok")&&reply["ok"] is bool&&(bool)reply["ok"]; report["helperOk"]=success;
                    bool backend=reply.ContainsKey("nativeBackend")&&Convert.ToString(reply["nativeBackend"])=="precompiled-framework-dll"; report["precompiledNativeBackend"]=backend;
                    if(reply.ContainsKey("error")) { string error=Convert.ToString(reply["error"]); int colon=error.IndexOf(':'); string prefix=colon<0?"OTHER":error.Substring(0,colon);
                        report["helperErrorCategory"]=Array.IndexOf(new string[]{"CANCELLED","NO_SELECTION","PROTECTED","CLIPBOARD","CLIPBOARD_CHANGED","CLIPBOARD_RESTORE_FAILED","SELECTION","NATIVE_CANCEL"},prefix)>=0?prefix:"OTHER"; }
                    report["contextAfterHelper"]=Context(document);
                    Ui(pump,delegate { CheckSeed(seed); return true; }); ownedClipboard=GetClipboardSequenceNumber(); report["richClipboardPreserved"]=true;
                    Need(backend,"PRECOMPILED_NATIVE_BACKEND_REQUIRED"); Need(success,"PRODUCTION_HELPER_SELECTION_FAILED");
                    Need(reply.ContainsKey("text")&&ExactText(Convert.ToString(reply["text"]))==expected,"PRODUCTION_HELPER_SELECTION_NOT_EXACT");
                    Need(health.ContainsKey("copyDispatchInserted")&&Convert.ToInt64(health["copyDispatchInserted"])==4,"EXACT_SINGLE_HELPER_COPY_REQUIRED");
                    Need(health.ContainsKey("copyOwnInputObserved")&&Convert.ToInt64(health["copyOwnInputObserved"])==1&&health.ContainsKey("copyClipboardRestored")&&Convert.ToInt64(health["copyClipboardRestored"])==1,"HELPER_COPY_OBSERVATION_OR_RESTORE_MISSING");
                    CurrentDocument(document); report["sourceFocusPreserved"]=true; report["actualWpsTested"]=true; report["ok"]=true;
                } catch(Exception error) {
                    report["failedStage"]=stage; string message=error.Message; bool fixedToken=message.Length>0&&message.Length<=96;
                    foreach(char character in message) if(!((character>='A'&&character<='Z')||(character>='0'&&character<='9')||character=='_')) fixedToken=false;
                    report["failureCategory"]=fixedToken?message:"FIXTURE_OR_VENDOR_SETUP_EXCEPTION"; report["exceptionType"]=error.GetType().Name;
                } finally {
                    // All modifiers were released before this fixture's input;
                    // undo a partial own injection without another copy chord.
                    if((GetAsyncKeyState(0x11)&0x8000)!=0) SendInput(1,new INPUT[]{Key(0x11,true)},Marshal.SizeOf(typeof(INPUT)));
                    // Only exact image/time-owned processes from this install.
                    bool clean=true; try { foreach(int id in OwnProcesses(executable,earliest)) try { using(Process process=Process.GetProcessById(id)) { if(OwnedProcess(process,executable,earliest)) { process.Kill(); if(!process.WaitForExit(5000)) clean=false; } } } catch { clean=false; } } catch { clean=false; }
                    report["ownedWpsProcessesStopped"]=clean; if(!clean)report["ok"]=false;
                    if(launched!=null)launched.Dispose();
                    Ui(pump,delegate { try { if(ownsClipboard&&GetClipboardSequenceNumber()==ownedClipboard) Clipboard.Clear(); }
                        catch { report["clipboardCleanupFailed"]=true; report["ok"]=false; } finally { finished=true; pump.Close(); } return true; });
                }
            }); worker.SetApartmentState(ApartmentState.STA); worker.Start(); };
            Application.Run(pump); if(worker!=null)Need(worker.Join(5000),"FIXTURE_WORKER_REMAINED");
        }
        return report;
    }
}
