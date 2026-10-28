// Generated-data counterexample: clipboard owner PID is not a copy-operation ID.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Provider;
using System.Windows.Forms;
using System.Web.Script.Serialization;

public static class WindowsSelectionClipboardRace {
    const string Original="Generated original clipboard 24680";
    const string Selected="Generated requested CtrlC selection 13579";
    const string Independent="Generated independent newer copy 97531";
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=1048576 };
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] inputs,int size);
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public InputUnion data;}
    [StructLayout(LayoutKind.Explicit)] struct InputUnion {[FieldOffset(0)] public MOUSEINPUT mouse;[FieldOffset(0)] public KEYBDINPUT keyboard;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT {public int dx,dy;public uint mouseData,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT {public ushort key,scan;public uint flags,time;public UIntPtr extra;}
    [DllImport("user32.dll",SetLastError=true)] static extern bool OpenClipboard(IntPtr window);
    [DllImport("user32.dll",SetLastError=true)] static extern bool EmptyClipboard();
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetClipboardData(uint format,IntPtr memory);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr GlobalAlloc(uint flags,UIntPtr size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr memory);
    static void Need(bool condition,string error){if(!condition)throw new InvalidOperationException(error);}
    static string WindowId(IntPtr window){return "0x"+window.ToInt64().ToString("X");}
    static string Kind(string text){return text==Original?"original":text==Selected?"requested-selection":text==Independent?"independent-new-copy":String.IsNullOrEmpty(text)?"empty":"unexpected";}
    static INPUT Key(ushort code,bool up){INPUT input=new INPUT();input.type=1;input.data.keyboard.key=code;input.data.keyboard.flags=up?2U:0U;return input;}
    static void Publish(IntPtr owner,string text){
        byte[] bytes=Encoding.Unicode.GetBytes(text+'\0');IntPtr memory=GlobalAlloc(2,(UIntPtr)bytes.Length);Need(memory!=IntPtr.Zero,"PUBLICATION_ALLOC_FAILED");bool transferred=false,opened=false;
        try{IntPtr pointer=GlobalLock(memory);Need(pointer!=IntPtr.Zero,"PUBLICATION_LOCK_FAILED");try{Marshal.Copy(bytes,0,pointer,bytes.Length);}finally{GlobalUnlock(memory);}
            Need(OpenClipboard(owner),"PUBLICATION_CLIPBOARD_BUSY");opened=true;Need(EmptyClipboard(),"PUBLICATION_EMPTY_FAILED");Need(SetClipboardData(13,memory)!=IntPtr.Zero,"PUBLICATION_DATA_FAILED");transferred=true;
        }finally{if(opened)CloseClipboard();if(!transferred)GlobalFree(memory);}
    }
    internal sealed class Source : Form {
        internal readonly Provider Root,Leaf;internal IntPtr Native;internal Rect Physical;internal bool Race,SecondKeyCopy,FixtureCopySent;
        internal int Copies,PatternQueries,ProviderFocusCalls;internal string Failure;internal bool OriginalOverNewCopy;
        internal uint LastOwnedSequence;internal double OriginalRestoreObservedAt=-1;internal bool ClipboardCleared;
        internal uint OriginalRestoreSequence,OriginalRestoreOwnerPid;internal IntPtr OriginalRestoreOwner;
        internal readonly List<Dictionary<string,object>> Publications=new List<Dictionary<string,object>>();
        readonly List<System.Windows.Forms.Timer> timers=new List<System.Windows.Forms.Timer>();readonly Stopwatch clock=new Stopwatch();
        internal void RecordPattern(){Interlocked.Increment(ref PatternQueries);}
        internal void RecordProviderFocus(){Interlocked.Increment(ref ProviderFocusCalls);}
        internal Source(){Text="EchoLingo generated same-process copy race";StartPosition=FormStartPosition.CenterScreen;ClientSize=new System.Drawing.Size(620,280);Root=new Provider(this,false);Leaf=new Provider(this,true);}
        protected override void WndProc(ref Message message){if(message.Msg==0x003d&&message.LParam.ToInt64()==AutomationInteropProvider.RootObjectId){message.Result=AutomationInteropProvider.ReturnRawElementProvider(Handle,message.WParam,message.LParam,Root);return;}base.WndProc(ref message);}
        void Schedule(int delay,Action action,bool repeat){System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();timer.Interval=delay;timer.Tick+=delegate{if(!repeat)timer.Stop();try{action();}catch(Exception error){Failure=error.GetType().Name+": "+error.Message;timer.Stop();}};timers.Add(timer);timer.Start();}
        void WriteOperation(string operation,string text){
            uint before=GetClipboardSequenceNumber();Publish(Native,text);uint after=GetClipboardSequenceNumber();IntPtr owner=GetClipboardOwner();uint pid;GetWindowThreadProcessId(owner,out pid);
            Need(after!=before&&owner==Native&&pid==Process.GetCurrentProcess().Id,"PUBLICATION_OWNER_OR_SEQUENCE_NOT_EXACT_SOURCE");
            LastOwnedSequence=after;Publications.Add(new Dictionary<string,object>{{"logicalOperation",operation},{"textKind",Kind(text)},{"millisecondsAfterCtrlC",clock.Elapsed.TotalMilliseconds},{"beforeSequence",before},{"afterSequence",after},{"ownerHwnd",WindowId(owner)},{"ownerPid",pid}});
        }
        void Observe(){
            if(!Race||Publications.Count!=1)return; // Only the interval100ms ->250ms matters.
            try{uint before=GetClipboardSequenceNumber();bool original=Clipboard.ContainsText()&&Clipboard.GetText(TextDataFormat.UnicodeText)==Original;uint after=GetClipboardSequenceNumber();if(original&&before==after){OriginalOverNewCopy=true;if(OriginalRestoreObservedAt<0){OriginalRestoreObservedAt=clock.Elapsed.TotalMilliseconds;OriginalRestoreSequence=after;OriginalRestoreOwner=GetClipboardOwner();uint pid;GetWindowThreadProcessId(OriginalRestoreOwner,out pid);OriginalRestoreOwnerPid=pid;}}}
            catch(ExternalException error){if(unchecked((uint)error.HResult)!=0x800401D0u)throw;} // Observe again next tick; never resend a copy.
        }
        internal void ObserveAfterReply(){Observe();}
        internal double SinceCtrlC {get{return clock.Elapsed.TotalMilliseconds;}}
        protected override bool ProcessCmdKey(ref Message message,Keys key){
            if(key==(Keys.Control|Keys.C)){
                Copies++;
                if(Copies==2&&SecondKeyCopy&&FixtureCopySent){try{WriteOperation("operation2-independent-copy-request",Independent);}catch(Exception error){Failure=error.Message;}return true;}
                if(Copies!=1){Failure="UNEXPECTED_COPY_INPUT_COUNT";return true;}clock.Start();
                // Operation1 was requested by native CtrlC now, but publishes later.
                // Operation2 is an independent newer copy intent, not a fragment
                // or empty/materialization phase of operation1.
                if(Race)Schedule(100,delegate{
                    if(!SecondKeyCopy)WriteOperation("operation2-independent-copy-request",Independent);
                    else{Need(GetForegroundWindow()==Native,"SECOND_COPY_SOURCE_NOT_FOREGROUND");FixtureCopySent=true;INPUT[] input={Key(0x11,false),Key(0x43,false),Key(0x43,true),Key(0x11,true)};Need(SendInput(4,input,Marshal.SizeOf(typeof(INPUT)))==4,"FIXTURE_SECOND_COPY_INPUT_REJECTED");}
                },false);
                Schedule(250,delegate{WriteOperation("operation1-delayed-CtrlC-request",Selected);},false);
                Schedule(5,Observe,true);return true;
            }return base.ProcessCmdKey(ref message,key);
        }
        internal DataObject Prepare(bool race,bool secondKeyCopy){
            foreach(System.Windows.Forms.Timer timer in timers){timer.Stop();timer.Dispose();}timers.Clear();Race=race;SecondKeyCopy=secondKeyCopy;FixtureCopySent=false;Copies=0;PatternQueries=0;ProviderFocusCalls=0;Failure=null;OriginalOverNewCopy=false;OriginalRestoreObservedAt=-1;OriginalRestoreSequence=0;OriginalRestoreOwnerPid=0;OriginalRestoreOwner=IntPtr.Zero;Publications.Clear();clock.Reset();
            Native=Handle;Rectangle bounds=Bounds;Physical=new Rect(bounds.X,bounds.Y,bounds.Width,bounds.Height);Activate();SetForegroundWindow(Native);SetFocus(Native);
            AutomationInteropProvider.RaiseAutomationEvent(AutomationElementIdentifiers.AutomationFocusChangedEvent,Leaf,new AutomationEventArgs(AutomationElementIdentifiers.AutomationFocusChangedEvent));
            DataObject seed=new DataObject();seed.SetData(DataFormats.UnicodeText,false,Original);seed.SetData(DataFormats.Html,false,"<p>Generated original rich clipboard</p>");seed.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated original rich clipboard}");Clipboard.SetDataObject(seed,true);LastOwnedSequence=GetClipboardSequenceNumber();return seed;
        }
        protected override void Dispose(bool disposing){if(disposing){foreach(System.Windows.Forms.Timer timer in timers){timer.Stop();timer.Dispose();}timers.Clear();}base.Dispose(disposing);}
    }
    [ComVisible(true),ClassInterface(ClassInterfaceType.None)]
    public sealed class Provider : IRawElementProviderSimple,IRawElementProviderFragment,IRawElementProviderFragmentRoot {
        readonly Source source;readonly bool leaf;internal Provider(Source owner,bool isLeaf){source=owner;leaf=isLeaf;}
        public ProviderOptions ProviderOptions {get{return ProviderOptions.ServerSideProvider;}}
        public IRawElementProviderSimple HostRawElementProvider {get{return leaf?null:AutomationInteropProvider.HostProviderFromHandle(source.Native);}}
        public object GetPatternProvider(int id){source.RecordPattern();return null;}
        public object GetPropertyValue(int id){
            if(id==AutomationElementIdentifiers.ControlTypeProperty.Id)return leaf?ControlType.Custom.Id:ControlType.Window.Id;
            if(id==AutomationElementIdentifiers.NativeWindowHandleProperty.Id){IntPtr native=source.Native;return leaf?0:native.ToInt32();}
            if(id==AutomationElementIdentifiers.ProcessIdProperty.Id)return Process.GetCurrentProcess().Id;
            if(id==AutomationElementIdentifiers.NameProperty.Id)return "Generated unsupported copy source";
            if(id==AutomationElementIdentifiers.AutomationIdProperty.Id)return leaf?"generated-clipboard-race-leaf":"generated-clipboard-race-root";
            if(id==AutomationElementIdentifiers.IsPasswordProperty.Id||id==AutomationElementIdentifiers.IsOffscreenProperty.Id||id==AutomationElementIdentifiers.IsTextPatternAvailableProperty.Id)return false;
            if(id==AutomationElementIdentifiers.HasKeyboardFocusProperty.Id)return leaf&&GetForegroundWindow()==source.Native;
            if(id==AutomationElementIdentifiers.IsKeyboardFocusableProperty.Id)return leaf;
            if(id==AutomationElementIdentifiers.IsEnabledProperty.Id||id==AutomationElementIdentifiers.IsControlElementProperty.Id||id==AutomationElementIdentifiers.IsContentElementProperty.Id)return true;
            return null;
        }
        public IRawElementProviderFragment Navigate(NavigateDirection direction){if(direction==NavigateDirection.Parent)return leaf?source.Root:null;if(!leaf&&(direction==NavigateDirection.FirstChild||direction==NavigateDirection.LastChild))return source.Leaf;return null;}
        public int[] GetRuntimeId(){return leaf?new int[]{AutomationInteropProvider.AppendRuntimeId,9173}:null;}
        public Rect BoundingRectangle {get{return source.Physical;}}
        public IRawElementProviderSimple[] GetEmbeddedFragmentRoots(){return null;}
        public void SetFocus(){source.RecordProviderFocus();throw new InvalidOperationException("ACQUISITION_MUST_NOT_CHANGE_PROVIDER_FOCUS");}
        public IRawElementProviderFragmentRoot FragmentRoot {get{return source.Root;}}
        public IRawElementProviderFragment ElementProviderFromPoint(double x,double y){return source.Leaf;}
        public IRawElementProviderFragment GetFocus(){return source.Leaf;}
    }
    static Dictionary<string,object> Call(string helper,string assembly,EventWaitHandle cancel,string eventName){
        ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell/v1.0/powershell.exe"));
        start.Arguments="-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \""+helper+"\" -Mode selected-text -NativeAssemblyPath \""+assembly+"\" -NativeCancellationEvent \""+eventName+"\"";
        start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=new UTF8Encoding(false);
        using(Process process=Process.Start(start)){Task<string> stdout=process.StandardOutput.ReadToEndAsync(),stderr=process.StandardError.ReadToEndAsync();try{
            Need(process.WaitForExit(12000),"HELPER_DEADLINE");Need(Task.WaitAll(new Task[]{stdout,stderr},2000),"HELPER_PIPE_DEADLINE");Need(stdout.Result.Length<262144&&stderr.Result.Length<65536,"HELPER_OUTPUT_BOUND");
            Dictionary<string,object> reply=Json.Deserialize<Dictionary<string,object>>(stdout.Result.Trim('\ufeff',' ','\r','\n'));Need(Convert.ToString(reply["nativeBackend"])=="precompiled-framework-dll","EXACT_DLL_BACKEND_REQUIRED");Need(process.ExitCode==(Convert.ToBoolean(reply["ok"])?0:1),"HELPER_EXIT_PROTOCOL_MISMATCH");reply["fixtureHelperProcessId"]=process.Id;return reply;
        }finally{if(!process.HasExited){cancel.Set();if(!process.WaitForExit(2000)){process.Kill();Need(process.WaitForExit(2000),"OWN_HELPER_CLEANUP_FAILED");}}}}
    }
    static bool RichMatches(DataObject seed){IDataObject actual=Clipboard.GetDataObject();if(actual==null)return false;foreach(string format in seed.GetFormats(false))if(!Object.Equals(seed.GetData(format,false),actual.GetData(format,false)))return false;return true;}
    public static Dictionary<string,object> Run(string helper,string assembly){
        Need(!helper.Contains("\"")&&!assembly.Contains("\""),"INVALID_FIXTURE_PATH");IDataObject existing=Clipboard.GetDataObject();Need(existing==null||existing.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();Dictionary<string,object> report=new Dictionary<string,object>{{"ok",false},{"cases",cases},{"requiredCases",3},{"actualApplicationTested",false},{"realBrowserTested",false},{"generatedDataOnly",true},{"helperRetries",0},{"counterexampleObserved",false}};
        using(Source source=new Source()){Thread worker=null;source.Shown+=delegate{source.Native=source.Handle;worker=new Thread((ThreadStart)delegate{try{
            foreach(int mode in new int[]{0,1,2}){bool race=mode!=0,secondKeyCopy=mode==2;
                Dictionary<string,object> row=new Dictionary<string,object>{{"kind",mode==0?"delayed-copy-baseline":mode==1?"same-owner-background-publication":"same-owner-second-real-copy"},{"ok",false},{"setupInconclusive",true}};cases.Add(row);DataObject seed=null;
                source.Invoke((Action)delegate{seed=source.Prepare(race,secondKeyCopy);});Need(GetForegroundWindow()==source.Native,"GENERATED_SOURCE_NOT_FOREGROUND");
                AutomationElement focus=AutomationElement.FocusedElement;object pattern;Need(focus!=null&&focus.Current.ProcessId==Process.GetCurrentProcess().Id&&focus.Current.ControlType==ControlType.Custom&&!focus.TryGetCurrentPattern(TextPattern.Pattern,out pattern),"REAL_UNSUPPORTED_UIA_SOURCE_REQUIRED");
                Need(GetAncestor(new IntPtr(TreeWalker.RawViewWalker.GetParent(focus).Current.NativeWindowHandle),2)==source.Native,"REAL_UIA_SOURCE_ROOT_REQUIRED");row["setupInconclusive"]=false;
                string eventName="Local\\EchoLingo-cancel-"+Guid.NewGuid().ToString("N");Dictionary<string,object> reply;using(EventWaitHandle cancel=new EventWaitHandle(false,EventResetMode.ManualReset,eventName)){reply=Call(helper,assembly,cancel,eventName);}
                bool helperOk=Convert.ToBoolean(reply["ok"]);string returned=helperOk?Kind(Convert.ToString(reply["text"])):"none";row["helperOk"]=helperOk;row["returnedTextKind"]=returned;row["helperInvocations"]=1;row["helperProcessId"]=reply["fixtureHelperProcessId"];source.Invoke((Action)delegate{row["helperReplyObservedAfterCtrlCMilliseconds"]=source.SinceCtrlC;source.ObserveAfterReply();});
                if(reply.ContainsKey("error")){string error=Convert.ToString(reply["error"]);int separator=error.IndexOf(':');row["helperErrorPrefix"]=separator<0?"UNCLASSIFIED":error.Substring(0,Math.Min(separator,64));}
                Stopwatch publicationWait=Stopwatch.StartNew();bool published=false;while(!published&&publicationWait.ElapsedMilliseconds<2000){source.Invoke((Action)delegate{Need(source.Failure==null,"SOURCE_PUBLICATION_FAILED: "+source.Failure);published=source.Publications.Count==(race?2:1);});if(!published)Thread.Sleep(5);}Need(published,"SOURCE_LOGICAL_PUBLICATIONS_NOT_COMPLETED");
                source.Invoke((Action)delegate{
                    row["publications"]=new List<Dictionary<string,object>>(source.Publications);row["actualCtrlCCount"]=source.Copies;row["echoCtrlCCount"]=source.Copies-(source.FixtureCopySent?1:0);row["fixtureCtrlCCount"]=source.FixtureCopySent?1:0;row["providerFocusCalls"]=source.ProviderFocusCalls;row["originalRestoredOverIndependentBeforeTrueCopy"]=source.OriginalOverNewCopy;row["originalRestoreObservedAfterCtrlCMilliseconds"]=source.OriginalRestoreObservedAt;row["originalRestoreSequence"]=source.OriginalRestoreSequence;row["originalRestoreOwnerPid"]=source.OriginalRestoreOwnerPid;row["originalRestoreOwnerHwnd"]=WindowId(source.OriginalRestoreOwner);row["clipboardObservationPollMilliseconds"]=5;
                    Need(source.Copies==(secondKeyCopy?2:1)&&source.ProviderFocusCalls==0,"NATIVE_INPUT_COUNT_OR_FOCUS_CHANGED");Need(GetForegroundWindow()==source.Native,"SOURCE_FOREGROUND_CHANGED");
                    bool accepted=true;
                    if(!race){Need(helperOk&&returned=="requested-selection"&&RichMatches(seed),"DELAYED_COPY_BASELINE_FAILED");source.LastOwnedSequence=GetClipboardSequenceNumber();row["richClipboardRestored"]=true;}
                    else{
                        Dictionary<string,object> independent=source.Publications[0],selected=source.Publications[1];Need(Convert.ToString(independent["logicalOperation"])=="operation2-independent-copy-request"&&Convert.ToString(selected["logicalOperation"])=="operation1-delayed-CtrlC-request","LOGICAL_OPERATION_ORDER_NOT_ESTABLISHED");
                        Need(Convert.ToDouble(selected["millisecondsAfterCtrlC"])-Convert.ToDouble(independent["millisecondsAfterCtrlC"])>=40,"PUBLICATIONS_COALESCED_SCENARIO_INCONCLUSIVE");
                        Need(Convert.ToString(independent["ownerHwnd"])==Convert.ToString(selected["ownerHwnd"])&&Convert.ToUInt32(independent["ownerPid"])==Convert.ToUInt32(selected["ownerPid"]),"SAME_OWNER_COUNTEREXAMPLE_NOT_ESTABLISHED");
                        row["sameOwnerHwndAndPid"]=true;bool wrongReturn=helperOk&&returned!="requested-selection",wrong=wrongReturn||source.OriginalOverNewCopy;report["counterexampleObserved"]=Convert.ToBoolean(report["counterexampleObserved"])||wrong;row["counterexampleObserved"]=wrong;row["wrongSuccessfulSource"]=wrongReturn;
                        accepted=!wrong;if(wrong){row["error"]="SAME_PID_CLIPBOARD_RACE: Wrong source was accepted as selection or new copy overwritten before the delayed source publication.";report["error"]=row["error"];}
                    }
                    row["ok"]=accepted;
                });
            }report["ok"]=cases.Count==3&&cases.TrueForAll(delegate(Dictionary<string,object> row){return Convert.ToBoolean(row["ok"]);});
        }catch(Exception error){while(error.InnerException!=null)error=error.InnerException;report["error"]=error.Message;report["errorType"]=error.GetType().Name;}
        finally{report["executedCases"]=cases.Count;report["passedCases"]=cases.FindAll(delegate(Dictionary<string,object> row){return Convert.ToBoolean(row["ok"]);}).Count;source.BeginInvoke((Action)delegate{if(GetClipboardSequenceNumber()==source.LastOwnedSequence){Clipboard.Clear();source.ClipboardCleared=true;}report["ownedClipboardCleared"]=source.ClipboardCleared;source.Close();});}
        });worker.SetApartmentState(ApartmentState.MTA);worker.Start();};Application.Run(source);if(worker!=null)Need(worker.Join(5000),"OWN_FIXTURE_WORKER_DID_NOT_STOP");}
        return report;
    }
}
