// Generated content only. Exact real Tauri executable, OS-registered Alt+D,
// WinForms source controls, real SendInput and local HTTP; never fake IPC.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

public static class WindowsSelectionApplicationFixture {
    const string Identifier="io.github.blueeeecho.echolingo", Marker=".echolingo-selection-owned";
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=1048576};
    delegate bool EnumWindow(IntPtr window,IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out RECT rectangle);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr window,uint message,IntPtr wParam,IntPtr lParam);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int size);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] input,int size);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid folder,uint flags,IntPtr token,out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr value);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string path,IntPtr security);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snapshot,ref ENTRY entry);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool Process32NextW(IntPtr snapshot,ref ENTRY entry);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] struct RECT {public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct ENTRY {public uint size,usage,pid;public UIntPtr heap;public uint module,threads,parent;public int priority;public uint flags;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]public string exe;}
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public UNION data;}
    [StructLayout(LayoutKind.Explicit)] struct UNION {[FieldOffset(0)]public MOUSE mouse;[FieldOffset(0)]public KEY keyboard;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
    static Process App;static IntPtr Main;static string History,Provider;static Mock Server;
    const string ConfiguredWindowsSelectionStrategy="auto";
    static ProcessStartInfo DiagnosticPrimaryStart;static string DiagnosticExecutable,DiagnosticRoaming,DiagnosticToken,ExpectedApplicationVersion;
    static Dictionary<string,object> Report;static readonly List<Dictionary<string,object>> Cases=new List<Dictionary<string,object>>();
    static readonly Dictionary<TextBoxBase,int> SourceVersions=new Dictionary<TextBoxBase,int>();
    static readonly Dictionary<TextBoxBase,int> MouseDownCounts=new Dictionary<TextBoxBase,int>(),MouseUpCounts=new Dictionary<TextBoxBase,int>();
    static readonly Dictionary<TextBoxBase,Point> PreviousSelectionDown=new Dictionary<TextBoxBase,Point>();
    static int MouseSelectionPlacement;
    static string ForbiddenFocusB;static int ExplicitFocusBAllowed,UnexpectedFocusB;static Dictionary<string,object> FocusRaceCase;
    static int Hotkeys;static uint OwnedClipboard;static bool Seeded;static DataObject ClipboardSeed;
    static string Hash(string value){using(SHA256 hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-","").ToLowerInvariant();}
    static void Need(bool value,string reason){if(!value)throw new InvalidOperationException(reason);}
    static void Ui(Form form,Action action){form.Invoke(action);}
    static int ForegroundPid(){uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);return (int)pid;}
    static INPUT Key(ushort value,bool up){INPUT i=new INPUT();i.type=1;i.data.keyboard.vk=value;i.data.keyboard.flags=up?2U:0U;return i;}
    static void Send(INPUT[] values){Need(SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)))==values.Length,"SENDINPUT_REJECTED");}
    static void Move(Point p){Rectangle screen=SystemInformation.VirtualScreen;INPUT i=new INPUT();i.data.mouse.x=(int)Math.Round((p.X-screen.Left)*65535.0/(screen.Width-1));i.data.mouse.y=(int)Math.Round((p.Y-screen.Top)*65535.0/(screen.Height-1));i.data.mouse.flags=0x8000|0x4000|1;Send(new INPUT[]{i});}
    static void Mouse(bool up){INPUT i=new INPUT();i.data.mouse.flags=up?4U:2U;Send(new INPUT[]{i});}
    static void Hotkey(Form form){Need(GetForegroundWindow()==form.Handle,"SOURCE_NOT_FOREGROUND_NO_HOTKEY_SENT");Send(new INPUT[]{Key(0x12,false),Key(0x44,false),Key(0x44,true),Key(0x12,true)});Hotkeys++;}
    static void Type(string text,bool submit){Need(ForegroundPid()==App.Id,"APP_NOT_FOREGROUND_NO_TEXT_SENT");List<INPUT> values=new List<INPUT>();foreach(char c in text){INPUT d=new INPUT();d.type=1;d.data.keyboard.scan=c;d.data.keyboard.flags=4;INPUT u=d;u.data.keyboard.flags|=2;values.Add(d);values.Add(u);}if(submit){values.Add(Key(13,false));values.Add(Key(13,true));}Send(values.ToArray());}
    static void Wait(Func<bool> condition,int milliseconds,string reason){Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<milliseconds){Need(App==null||!App.HasExited,"APPLICATION_EXITED");if(Server!=null&&Server.Error!=null)throw new InvalidOperationException(Server.Error);if(condition())return;Application.DoEvents();Thread.Sleep(20);}throw new InvalidOperationException("TIMEOUT:"+reason);}
    static void Observe(Func<bool> condition,int milliseconds,string reason){Stopwatch clock=Stopwatch.StartNew();while(clock.ElapsedMilliseconds<milliseconds){Need(condition(),reason);Application.DoEvents();Thread.Sleep(20);}}
    static IntPtr MainWindow(int pid){List<IntPtr> found=new List<IntPtr>();EnumWindows(delegate(IntPtr w,IntPtr unused){uint owner;GetWindowThreadProcessId(w,out owner);StringBuilder name=new StringBuilder(256);GetClassName(w,name,256);if(owner==pid&&GetAncestor(w,2)==w&&name.ToString()=="Tauri Window")found.Add(w);return true;},IntPtr.Zero);return found.Count==1?found[0]:IntPtr.Zero;}
    static Dictionary<string,object> NativeReadiness(){int hotkeys=0,trays=0;List<string> handles=new List<string>();EnumWindows(delegate(IntPtr w,IntPtr unused){uint pid;GetWindowThreadProcessId(w,out pid);if(pid!=App.Id)return true;StringBuilder name=new StringBuilder(128);GetClassName(w,name,128);if(name.ToString()=="global_hotkey_app"){hotkeys++;handles.Add("0x"+w.ToInt64().ToString("X"));}if(name.ToString()=="tray_icon_app")trays++;return true;},IntPtr.Zero);return new Dictionary<string,object>{{"ownMainHwnd","0x"+Main.ToInt64().ToString("X")},{"globalHotkeyWindowCount",hotkeys},{"globalHotkeyHwnds",handles},{"trayWindowCount",trays},{"osHotkeyRegistrationProven",false},{"registrationProbeUsed",false},{"nativeWindowIsNotFrontendReadiness",true}};}
    static AutomationElement Element(string name){return AutomationElement.FromHandle(Main).FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.NameProperty,name));}
    static AutomationElement Source(){return AutomationElement.FromHandle(Main).FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));}
    static string SourceValue(){AutomationElement e=Source();object p;return e!=null&&!e.Current.IsOffscreen&&e.TryGetCurrentPattern(ValuePattern.Pattern,out p)?((ValuePattern)p).Current.Value:null;}
    static string SourceAnyValue(){AutomationElement e=Source();object p;return e!=null&&e.TryGetCurrentPattern(ValuePattern.Pattern,out p)?((ValuePattern)p).Current.Value:null;}
    static bool SettingsVisible(){AutomationElement e=Element("\u8bbe\u7f6e");return e!=null&&!e.Current.IsOffscreen;}
    static bool SameRuntimeId(int[] first,int[] second){if(first==null||second==null)return first==second;if(first.Length!=second.Length)return false;for(int i=0;i<first.Length;i++)if(first[i]!=second[i])return false;return true;}
    static int[] FocusRuntimeId(){AutomationElement e=AutomationElement.FocusedElement;return e==null?null:e.GetRuntimeId();}
    static void ManagementPhase(Dictionary<string,object> trace,string phase){if(trace!=null)trace["managementPhase"]=phase;}
    static void Invoke(string name,Dictionary<string,object> trace=null,string phase=""){
        AutomationElement e=null;Wait(delegate{ManagementPhase(trace,phase+":find-element");e=Element(name);if(e==null)return false;ManagementPhase(trace,phase+":read-visible");return !e.Current.IsOffscreen;},5000,"CONTROL_MISSING:"+name);object p;
        ManagementPhase(trace,phase+":query-invoke-pattern");if(e.TryGetCurrentPattern(InvokePattern.Pattern,out p)){ManagementPhase(trace,phase+":invoke-once");((InvokePattern)p).Invoke();}
        else{ManagementPhase(trace,phase+":query-toggle-pattern");if(e.TryGetCurrentPattern(TogglePattern.Pattern,out p)){ManagementPhase(trace,phase+":toggle-once");((TogglePattern)p).Toggle();}
        else{ManagementPhase(trace,phase+":query-expand-pattern");if(e.TryGetCurrentPattern(ExpandCollapsePattern.Pattern,out p)){ManagementPhase(trace,phase+":expand-once");((ExpandCollapsePattern)p).Expand();}else throw new InvalidOperationException("CONTROL_ACTION_UNAVAILABLE:"+name);}}
        ManagementPhase(trace,phase+":action-returned");
    }
    static bool ReadManagementReady(Dictionary<string,object> trace){
        try{
            ManagementPhase(trace,"ready:read-settings-visible");bool visible=SettingsVisible();trace["readinessSettingsVisible"]=visible;if(!visible)return false;
            ManagementPhase(trace,"ready:read-source-hidden");bool sourceNull=SourceValue()==null;trace["readinessVisibleSourceNull"]=sourceNull;return sourceNull;
        }catch(ElementNotAvailableException){
            int count=trace.ContainsKey("managementReadinessTransientUnavailableCount")?Convert.ToInt32(trace["managementReadinessTransientUnavailableCount"]):0;trace["managementReadinessTransientUnavailableCount"]=count+1;trace["managementLastTransientReadPhase"]=trace["managementPhase"];trace["managementLastTransientException"]="ElementNotAvailableException";return false;
        }
    }
    // Copy bytes and CLOSE the reader before parsing/polling again. ShareDelete
    // permits deletion where supported; it does not promise MoveFileEx can
    // replace a still-open destination on every Windows/filesystem combination.
    static FileStream OpenHistorySnapshot(string path){return new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);}
    static string ReadHistorySnapshot(string path){using(var stream=OpenHistorySnapshot(path))using(var reader=new StreamReader(stream,Encoding.UTF8,true))return reader.ReadToEnd();}
    static object[] Histories(){if(!File.Exists(History))return new object[0];try{return Json.Deserialize<object[]>(ReadHistorySnapshot(History));}catch(IOException){return new object[0];}catch(ArgumentException){return new object[0];}}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool MoveFileEx(string from,string to,uint flags);
    static void CreateHistoryFixture(string path,string value){using(var file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)){byte[] bytes=Encoding.UTF8.GetBytes(value);file.Write(bytes,0,bytes.Length);file.Flush(true);}}
    static Dictionary<string,object> HistoryReaderLifetimeRegression(string ownedRoot){
        string file=Path.Combine(ownedRoot,"history-share-"+Guid.NewGuid().ToString("N")+".json"),pending=file+".tmp";
        var result=new Dictionary<string,object>{{"generatedFilesOnly",true},{"replacementAttempts",0},{"sameFlagsAsProduction",9},{"retryAttempts",0}};
        Report["historyReaderLifetimeRegression"]=result; // Retain metadata even if a control fails.
        try{
            CreateHistoryFixture(file,"old-generation");CreateHistoryFixture(pending,"new-generation");
            // Negative control: File.ReadAllText's Framework sharing policy.
            using(var legacy=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read)){
                bool moved=MoveFileEx(pending,file,9);int error=Marshal.GetLastWin32Error();result["replacementAttempts"]=1;result["legacyReplacementBlocked"]=!moved;result["legacyWin32Error"]=error;
                Need(!moved&&error!=0&&File.Exists(pending),"LEGACY_READER_DID_NOT_BLOCK_ATOMIC_REPLACEMENT");
                Need(legacy.ReadByte()=='o'&&ReadHistorySnapshot(file)=="old-generation","LEGACY_BLOCK_CHANGED_PUBLISHED_HISTORY");
            }
            // Positive control exercises the ACTUAL complete observer call:
            // it must return a closed snapshot, not leak a handle across writes.
            // Windows may reject replacement while even a ShareDelete reader is
            // held; that unsupported assumption is deliberately not made here.
            string oldSnapshot=ReadHistorySnapshot(file);
            result["observerReadCompletedBeforeReplacement"]=true;
            bool replaced=MoveFileEx(pending,file,9);int replaceError=Marshal.GetLastWin32Error();
            result["replacementAttempts"]=2;result["closedSnapshotReplacementSucceeded"]=replaced;
            result["closedSnapshotWin32Error"]=replaced?0:replaceError;
            result["pendingExistsAfterReplacement"]=File.Exists(pending);
            result["targetExistsAfterReplacement"]=File.Exists(file);
            Need(replaced&&!File.Exists(pending),"CLOSED_HISTORY_SNAPSHOT_BLOCKED_ATOMIC_REPLACEMENT");
            result["oldSnapshotPreserved"]=oldSnapshot=="old-generation";
            result["freshNewGenerationVisible"]=ReadHistorySnapshot(file)=="new-generation";
            Need((bool)result["oldSnapshotPreserved"]&&(bool)result["freshNewGenerationVisible"],"HISTORY_OBSERVER_GENERATION_MISMATCH");
            result["ok"]=true;return result;
        }finally{if(File.Exists(pending))File.Delete(pending);if(File.Exists(file))File.Delete(file);}
    }
    static bool HistoryHas(string source){foreach(object raw in Histories()){Dictionary<string,object> e=(Dictionary<string,object>)raw;if((string)e["text"]!=source)continue;foreach(object item in (IEnumerable)e["results"]){Dictionary<string,object> result=(Dictionary<string,object>)item;if((string)result["providerId"]==Provider&&!result.ContainsKey("error")&&(string)result["text"]==Mock.Result(source))return true;}}return false;}
    static int HistorySourceCount(string source){int count=0;foreach(object value in Histories())if((string)((Dictionary<string,object>)value)["text"]==source)count++;return count;}
    static List<string> HistorySources(){List<string> text=new List<string>();foreach(object value in Histories())text.Add((string)((Dictionary<string,object>)value)["text"]);return text;}
    static void SeedClipboard(){ClipboardSeed=new DataObject();ClipboardSeed.SetData(DataFormats.UnicodeText,false,"Generated clipboard original 24680");ClipboardSeed.SetData(DataFormats.Html,false,"<p>Generated clipboard original 24680</p>");ClipboardSeed.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated clipboard original 24680}");Clipboard.SetDataObject(ClipboardSeed,true,0,0);OwnedClipboard=GetClipboardSequenceNumber();Seeded=true;}
    static void CheckClipboard(){IDataObject actual=Clipboard.GetDataObject();Need(actual!=null,"ORIGINAL_CLIPBOARD_MISSING");foreach(string f in ClipboardSeed.GetFormats(false))Need(Object.Equals(ClipboardSeed.GetData(f,false),actual.GetData(f,false)),"RICH_CLIPBOARD_NOT_RESTORED");OwnedClipboard=GetClipboardSequenceNumber();}
    static void PutSource(Form form,TextBoxBase control,Control[] controls,string raw,bool mouse,Dictionary<string,object> setup=null){
        Ui(form,delegate{
            int clickStep=Math.Max(1,SystemInformation.DoubleClickSize.Width)+8,placement=mouse?MouseSelectionPlacement++%2:0;
            Rectangle work=Screen.PrimaryScreen.WorkingArea;Rectangle target=new Rectangle(work.Left+12+placement*clickStep,work.Top+8,Math.Min(740,work.Width-24-clickStep),150);
            if(Main!=IntPtr.Zero&&IsWindowVisible(Main)){RECT r;Need(GetWindowRect(Main,out r),"MAIN_RECT_FAILED");Rectangle popup=Rectangle.FromLTRB(r.Left,r.Top,r.Right,r.Bottom);popup.Inflate(8,8);if(target.IntersectsWith(popup)){target.Y=work.Bottom-target.Height-8;Need(!target.IntersectsWith(popup),"GENERATED_SOURCE_PLACEMENT_UNAVAILABLE");}}
            form.Bounds=target;foreach(Control c in controls)c.Visible=c==control;control.SetBounds(10,10,form.ClientSize.Width-20,control is TextBox&&!((TextBox)control).Multiline?28:85);control.Text="Prefix "+raw+" suffix";form.Activate();SetForegroundWindow(form.Handle);control.Focus();
            RichTextBox rich=control as RichTextBox;if(rich!=null){
                // The public setter's false path uses ECOOP_XOR. Force the bit on, then off,
                // after HWND creation; verify actual native state rather than its cached getter.
                // https://learn.microsoft.com/en-us/windows/win32/controls/em-getoptions
                long before=SendMessage(rich.Handle,0x044E,IntPtr.Zero,IntPtr.Zero).ToInt64();rich.AutoWordSelection=true;rich.AutoWordSelection=false;
                long after=SendMessage(rich.Handle,0x044E,IntPtr.Zero,IntPtr.Zero).ToInt64();if(setup!=null){setup["richOptionsBeforeExplicitSetter"]=before;setup["richOptionsAfterExplicitSetter"]=after;setup["richAutoWordSelectionNativeEnabled"]=(after&1)!=0;setup["richSetterSequence"]="HWND-created: true, false; EM_GETOPTIONS verified";}Need((after&1)==0,"GENERATED_RICH_AUTOWORD_NATIVE_FLAG_NOT_CLEARED");
            }
            if(setup!=null){setup["sourceWindowHorizontalPlacement"]=placement*clickStep;setup["systemDoubleClickRectangleWH"]=new int[]{SystemInformation.DoubleClickSize.Width,SystemInformation.DoubleClickSize.Height};}
        });
        if(GetForegroundWindow()!=form.Handle){Point click=Point.Empty;Ui(form,delegate{click=control.PointToScreen(new Point(4,control.Font.Height/2));});Need(WindowFromPoint(click)==control.Handle,"SETUP_CLICK_NOT_OWN_SOURCE");Move(click);Mouse(false);Mouse(true);}
        Wait(delegate{return GetForegroundWindow()==form.Handle;},2000,"SOURCE_FOREGROUND");
        if(!mouse)Ui(form,delegate{control.Focus();control.Select(7,raw.Length);});
        if(mouse){
            Point a=Point.Empty,b=Point.Empty;int downBefore=0,upBefore=0;
            Ui(form,delegate{downBefore=MouseDownCounts[control];upBefore=MouseUpCounts[control];
                Point start=control.GetPositionFromCharIndex(7),end=control.GetPositionFromCharIndex(7+raw.Length);
                Point ac=start,bc=end;ac.Offset(1,control.Font.Height/2);bc.Offset(control is RichTextBox?-1:1,control.Font.Height/2);
                a=control.PointToScreen(ac);b=control.PointToScreen(bc);
                Point previous;if(PreviousSelectionDown.TryGetValue(control,out previous)){bool separated=Math.Abs(a.X-previous.X)>SystemInformation.DoubleClickSize.Width||Math.Abs(a.Y-previous.Y)>SystemInformation.DoubleClickSize.Height;if(setup!=null){setup["previousSelectionDownPhysicalXY"]=new int[]{previous.X,previous.Y};setup["outsidePreviousDoubleClickRectangle"]=separated;}Need(separated,"GENERATED_SELECTION_WOULD_REPEAT_DOUBLE_CLICK_POSITION");}PreviousSelectionDown[control]=a;
                if(setup!=null){RECT r;bool rect=GetWindowRect(control.Handle,out r);setup["coordinateAlgorithm"]=control is RichTextBox?"firstCaret+1 to nextCaret-1 (last glyph right interior)":"firstCaret+1 to nextCaret+1 (previously observed Edit path)";setup["startPhysicalXY"]=new int[]{a.X,a.Y};setup["endPhysicalXY"]=new int[]{b.X,b.Y};setup["startCaretClientXY"]=new int[]{start.X,start.Y};setup["endCaretClientXY"]=new int[]{end.X,end.Y};setup["getCharIndexAtStart"]=control.GetCharIndexFromPosition(ac);setup["getCharIndexAtEnd"]=control.GetCharIndexFromPosition(bc);setup["fontName"]=control.Font.Name;setup["fontSizePoints"]=control.Font.SizeInPoints;setup["fontHeight"]=control.Font.Height;setup["deviceDpi"]=control.DeviceDpi;setup["rawPhysicalBounds"]=rect?(object)new int[]{r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top}:null;setup["expectedStart"]=7;setup["expectedLength"]=raw.Length;}
            });
            Need(WindowFromPoint(a)==control.Handle&&WindowFromPoint(b)==control.Handle,"MOUSE_SELECTION_NOT_GENERATED_CONTROL");Move(a);Mouse(false);for(int i=1;i<=8;i++){Move(new Point(a.X+(b.X-a.X)*i/8,a.Y+(b.Y-a.Y)*i/8));Thread.Sleep(12);}Mouse(true);Wait(delegate{bool done=false;Ui(form,delegate{done=MouseUpCounts[control]>upBefore;});return done;},2000,"ACTUAL_GENERATED_MOUSEUP_DISPATCH");Ui(form,delegate{if(setup!=null){setup["mouseDownEvents"]=MouseDownCounts[control]-downBefore;setup["mouseUpEvents"]=MouseUpCounts[control]-upBefore;if(control is RichTextBox)setup["richAutoWordSelection"]=((RichTextBox)control).AutoWordSelection;}});
        }
        Ui(form,delegate{if(setup!=null){setup["actualSelectedText"]=control.SelectedText;setup["actualSelectionStart"]=control.SelectionStart;setup["actualSelectionLength"]=control.SelectionLength;setup["sourceControlTextUnchanged"]=control.Text=="Prefix "+raw+" suffix";}Need(control.SelectedText==raw,"GENERATED_SELECTION_NOT_EXACT");});
    }

    static Dictionary<string,object> Begin(string name,string expected,string selectionMethod){Dictionary<string,object> c=new Dictionary<string,object>{{"name",name},{"ok",false},{"expectedSource",expected},{"expectedSourceSha256",Hash(expected)},{"selectionMethod",selectionMethod},{"hotkeysBefore",Hotkeys},{"nativeChildObserved",false}};Cases.Add(c);return c;}
    static void Complete(Dictionary<string,object> c,string expected,Form form,TextBoxBase source,string initial){
        Wait(delegate{if(Helpers().Count>0)c["nativeChildObserved"]=true;return HistoryHas(expected)&&SourceValue()==expected&&Server.CountFor(expected)>Convert.ToInt32(c["mockRequestsBefore"])&&HistorySourceCount(expected)>Convert.ToInt32(c["historySourceCountBefore"]);},30000,"EXACT_SOURCE_AND_HISTORY:"+c["name"]);Need(GetForegroundWindow()==form.Handle,"NONEMPTY_SELECTION_STOLE_FOCUS");Ui(form,delegate{Need(source.Text==initial,"UNINTENDED_SOURCE_EDIT");if(c.ContainsKey("sourceVersionBefore")){int changes=SourceVersions[source]-Convert.ToInt32(c["sourceVersionBefore"]);c["sourceTextChangedEventsDuringAcquisition"]=changes;Need(changes==0,"SOURCE_EDITED_AND_POSSIBLY_RESTORED");}});CheckClipboard();c["actualSourceSha256"]=Hash(SourceValue());c["historyExactSourceVerified"]=true;c["sourceForegroundPreserved"]=true;c["sourceUnchanged"]=true;c["richClipboardRestored"]=true;c["hotkeysSent"]=Hotkeys-Convert.ToInt32(c["hotkeysBefore"]);
    }
    static void FocusRaceLedger(){
        if(FocusRaceCase==null)return;int unexpected=Interlocked.CompareExchange(ref UnexpectedFocusB,0,0);
        if(Interlocked.CompareExchange(ref ExplicitFocusBAllowed,0,0)==0&&(Server.CountFor(ForbiddenFocusB)>0||HistorySourceCount(ForbiddenFocusB)>0))unexpected=Math.Max(1,unexpected);
        if(unexpected>0){FocusRaceCase["ok"]=false;FocusRaceCase["unrelatedBImported"]=true;FocusRaceCase["error"]="WRONG_POST_TRIGGER_SELECTION_B_IMPORTED_BEFORE_EXPLICIT_B_INTENT";FocusRaceCase["unauthorizedBRequests"]=unexpected;}
    }
    static void SelectionCase(string name,Form form,TextBoxBase source,Control[] controls,string raw,bool mouse){
        string expected=raw.Replace("\r\n","\n");Server.Allow(expected,false);int requestsBefore=Server.CountFor(expected);
        Dictionary<string,object> c=Begin(name,expected,mouse?"actual-SendInput-left-drag":"generated-control-Select");c["rawSelectedText"]=raw;c["rawSelectedTextSha256"]=Hash(raw);c["normalizationExpectation"]="Only CRLF to LF; explicit paragraph breaks preserved. Expected known before capture.";
        Dictionary<string,object> setup=new Dictionary<string,object>();c["generatedSelectionSetup"]=setup;
        try{PutSource(form,source,controls,raw,mouse,setup);}catch(Exception e){
            Exception actual=e;while(actual.InnerException!=null)actual=actual.InnerException;
            if(actual.Message!="GENERATED_SELECTION_NOT_EXACT")throw;
            Ui(form,delegate{Need(source.Text=="Prefix "+raw+" suffix","SETUP_CHANGED_GENERATED_SOURCE");});Need(Helpers().Count==0,"SETUP_FAILURE_WITH_PENDING_HELPER");if(Seeded)CheckClipboard();c["error"]=actual.Message;c["failureStage"]="generated-mouse-selection-before-hotkey";c["hotkeysSent"]=0;c["safeToContinue"]=true;return;
        }
        string initial="";Ui(form,delegate{initial=source.Text;c["sourceVersionBefore"]=SourceVersions[source];});SeedClipboard();c["mockRequestsBefore"]=requestsBefore;c["historySourceCountBefore"]=HistorySourceCount(expected);Stopwatch time=Stopwatch.StartNew();if(expected==ForbiddenFocusB){FocusRaceLedger();c["BRequestsImmediatelyBeforeExplicitHotkey"]=Server.CountFor(expected);c["BHistoryImmediatelyBeforeExplicitHotkey"]=HistorySourceCount(expected);Interlocked.Exchange(ref ExplicitFocusBAllowed,1);}Hotkey(form);Complete(c,expected,form,source,initial);c["hotkeyToHistoryMilliseconds"]=time.Elapsed.TotalMilliseconds;Need(Convert.ToInt32(c["hotkeysSent"])==1,"FIRST_SHORTCUT_WAS_RETRIED");Need(Server.CountFor(expected)-requestsBefore==1,"DUPLICATE_TRANSLATION_FOR_ONE_DISTINCT_ACTION");c["ok"]=true;
    }
    static long DiagnosticNumber(object value,long maximum){
        Need(value is int||value is long,"DIAGNOSTIC_INTEGER_REQUIRED");long number=Convert.ToInt64(value);Need(number>=0&&number<=maximum,"DIAGNOSTIC_NUMBER_BOUND");return number;
    }
    static HashSet<string> SelectionDiagnosticFields(){
        HashSet<string> allowed=new HashSet<string>(new string[]{"selectionQueryCount","helperResponseReceived","helperElapsedMilliseconds","helperResultNonempty","cancellationRequested","cancellationSignalled","cancellationSignalFailed","attemptId","attemptPhase","attemptStartedAtUnixMs","attemptFinishedAtUnixMs","nativeBoundaryStage","sourceSnapshotOutcome","sourceCurrentAtWorker","configuredCopyStrategy","actionResultOk","actionResultNonempty","actionErrorKind"});
        foreach(string suffix in new string[]{"Stage","Depth","IdentityCompared","IdentityEqual","RootWalkReason","ExceptionKind","Milliseconds"})for(int i=1;i<=16;i++)allowed.Add("selectionQuery"+i+suffix);
        foreach(string field in new string[]{"copyStrategy","copyPhase","copyNativeContextValid","copyNativeContextChecks","copyNativeGuardReason","copyNativeInvalidReason","copyNativeGtiSucceeded","copyNativeGtiFlags","copyNativeFocusPresent","copyNativeFocusProcessMatchesForeground","copyNativeFocusRootMatchesForeground","copyNativeActivePresent","copyNativeActiveRootMatchesForeground","copyNativeEditable","copyNativeProtection","copyNativeSelectionKnown","copyNativeSelectionNonempty","copyProtectionProbe","copyProtectionProbeMilliseconds","copyProtectionUnknown","copySnapshotOutcome","copyDispatchInserted","copyOwnInputObserved","copyOwnerOutcome","copyClipboardRestored","copyTerminalReason","copyClipboardOutcome","copyWaitElapsedMilliseconds"})allowed.Add(field);
        return allowed;
    }
    // Process timestamps have a different unit from bounded helper counters.
    // Keep the exact production key allowlist; unknown fields and non-integers
    // still fail rather than being ignored or copied into failure evidence.
    static Dictionary<string,object> ValidatedSelectionHealth(Dictionary<string,object> health,long recorded){
        Need(health!=null,"DIAGNOSTIC_LAST_SELECTION_MISSING");
        HashSet<string> allowed=SelectionDiagnosticFields();Dictionary<string,object> numeric=new Dictionary<string,object>();
        foreach(KeyValuePair<string,object> pair in health){
            Need(allowed.Contains(pair.Key),"DIAGNOSTIC_CONTENT_OR_UNKNOWN_FIELD");
            bool timestamp=pair.Key=="attemptStartedAtUnixMs"||pair.Key=="attemptFinishedAtUnixMs";
            long maximum=timestamp?recorded:10000000;
            if(pair.Key=="nativeBoundaryStage"||pair.Key=="actionErrorKind")maximum=8;
            if(pair.Key=="sourceSnapshotOutcome"||pair.Key=="sourceCurrentAtWorker")maximum=2;
            if(pair.Key=="copyNativeInvalidReason")maximum=15;
            if(pair.Key=="copyNativeGtiSucceeded"||pair.Key=="copyNativeFocusPresent"||pair.Key=="copyNativeFocusProcessMatchesForeground"||pair.Key=="copyNativeFocusRootMatchesForeground"||pair.Key=="copyNativeActivePresent"||pair.Key=="copyNativeActiveRootMatchesForeground")maximum=1;
            long number=DiagnosticNumber(pair.Value,maximum);Need(!timestamp||number>0,"DIAGNOSTIC_ATTEMPT_TIMESTAMP_REQUIRED");numeric[pair.Key]=number;
        }
        if(numeric.ContainsKey("attemptFinishedAtUnixMs"))Need(numeric.ContainsKey("attemptStartedAtUnixMs")&&(long)numeric["attemptFinishedAtUnixMs"]>=(long)numeric["attemptStartedAtUnixMs"],"DIAGNOSTIC_ATTEMPT_TIME_ORDER");
        return numeric;
    }
    static void SelectionDiagnosticsCli(string executable,ProcessStartInfo primaryStart,string roaming,string token,Form form,TextBox source){
        Dictionary<string,object> result=new Dictionary<string,object>{{"ok",false},{"attempts",1},{"newSelectionRequested",false},{"secondaryProcessExitObserved",false}};Report["selectionDiagnosticsCli"]=result;
        Need(Cases.Count==1&&Convert.ToBoolean(Cases[0]["ok"]),"DIAGNOSTICS_REQUIRES_FIRST_SUCCESSFUL_SELECTION");
        Need((File.GetAttributes(roaming)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(roaming,Marker))==token,"DIAGNOSTIC_DIRECTORY_NOT_OWNED");
        string file=Path.Combine(roaming,"selection-diagnostics.json");Need(!File.Exists(file)&&!Directory.Exists(file),"DIAGNOSTIC_FILE_ALREADY_EXISTS");
        Need(String.Equals(Path.GetFullPath(App.MainModule.FileName),Path.GetFullPath(executable),StringComparison.OrdinalIgnoreCase),"DIAGNOSTIC_PRIMARY_EXECUTABLE_MISMATCH");
        string expected=SourceValue(),sourceText="",selected="";int sourceVersion=0;Ui(form,delegate{sourceText=source.Text;selected=source.SelectedText;sourceVersion=SourceVersions[source];});
        Need(!String.IsNullOrEmpty(expected)&&GetForegroundWindow()==form.Handle&&Helpers().Count==0,"DIAGNOSTIC_BASELINE_NOT_READY");
        byte[] history=File.ReadAllBytes(History);int mockCount=Server.CountFor(expected),hotkeys=Hotkeys,primaryPid=App.Id;bool visible=IsWindowVisible(Main);uint clipboard=GetClipboardSequenceNumber();
        ProcessStartInfo start=new ProcessStartInfo(executable,"--selection-diagnostics");start.UseShellExecute=false;start.CreateNoWindow=true;
        foreach(string key in new string[]{"LOCALAPPDATA","TEMP","TMP","WEBVIEW2_USER_DATA_FOLDER"})start.EnvironmentVariables[key]=primaryStart.EnvironmentVariables[key];
        long earliest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;Stopwatch clock=Stopwatch.StartNew();Process secondary=null;
        try{
            secondary=Process.Start(start);Need(secondary!=null&&secondary.Id!=primaryPid,"DIAGNOSTIC_SECONDARY_NOT_CREATED");
            while(clock.ElapsedMilliseconds<5000){
                Need(!App.HasExited&&App.Id==primaryPid&&MainWindow(primaryPid)==Main,"DIAGNOSTIC_PRIMARY_IDENTITY_CHANGED");
                Need(GetForegroundWindow()==form.Handle&&IsWindowVisible(Main)==visible&&Helpers().Count==0,"DIAGNOSTIC_CHANGED_FOREGROUND_VISIBILITY_OR_HELPERS");
                Need(Server.Error==null&&Server.CountFor(expected)==mockCount&&Hotkeys==hotkeys,"DIAGNOSTIC_TRIGGERED_TRANSLATION_OR_INPUT");
                if(secondary.HasExited){result["secondaryProcessExitObserved"]=true;result["secondaryExitCode"]=secondary.ExitCode;Need(secondary.ExitCode==0,"DIAGNOSTIC_SECONDARY_FAILED");if(File.Exists(file))break;}
                Application.DoEvents();Thread.Sleep((int)Math.Min(20,Math.Max(1,5000-clock.ElapsedMilliseconds)));
            }
            Need(secondary.HasExited&&File.Exists(file)&&clock.ElapsedMilliseconds<5000,"DIAGNOSTIC_CLI_OR_FILE_DEADLINE");
            Need((File.GetAttributes(roaming)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(roaming,Marker))==token&&(File.GetAttributes(file)&FileAttributes.ReparsePoint)==0,"DIAGNOSTIC_FILE_OWNERSHIP_CHANGED");
            byte[] bytes=File.ReadAllBytes(file);Need(bytes.Length>0&&bytes.Length<=16384,"DIAGNOSTIC_FILE_BOUND");Dictionary<string,object> payload=Json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));
            HashSet<string> metadata=new HashSet<string>(new string[]{"diagnostic","recordedAtUnixMs","appVersion","processId","executablePath","diagnostics"});Need(payload.Count==metadata.Count,"DIAGNOSTIC_METADATA_SCHEMA");foreach(string key in payload.Keys)Need(metadata.Contains(key),"DIAGNOSTIC_METADATA_FIELD");
            Need((string)payload["diagnostic"]=="last-selection-attempt"&&(string)payload["appVersion"]==ExpectedApplicationVersion&&DiagnosticNumber(payload["processId"],Int32.MaxValue)==primaryPid,"DIAGNOSTIC_PRIMARY_METADATA_MISMATCH");
            Need(String.Equals((string)payload["executablePath"],Path.GetFullPath(executable),StringComparison.OrdinalIgnoreCase),"DIAGNOSTIC_EXPORTED_EXECUTABLE_MISMATCH");
            long recorded=DiagnosticNumber(payload["recordedAtUnixMs"],Int64.MaxValue),latest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;Need(recorded>=earliest&&recorded<=latest,"DIAGNOSTIC_TIMESTAMP_OUTSIDE_EXPLICIT_CALL");
            Dictionary<string,object> health=payload["diagnostics"] as Dictionary<string,object>;Need(health!=null,"DIAGNOSTIC_LAST_SELECTION_MISSING");
            ValidatedSelectionHealth(health,recorded);
            Need(health.ContainsKey("attemptStartedAtUnixMs")&&health.ContainsKey("attemptFinishedAtUnixMs")&&health.ContainsKey("actionErrorKind")&&DiagnosticNumber(health["actionErrorKind"],8)==0&&health.ContainsKey("nativeBoundaryStage")&&DiagnosticNumber(health["nativeBoundaryStage"],8)==8,"DIAGNOSTIC_SUCCESS_BOUNDARY_METADATA_MISMATCH");
            Need(health.ContainsKey("selectionQueryCount")&&DiagnosticNumber(health["selectionQueryCount"],16)>=2&&health.ContainsKey("helperResponseReceived")&&DiagnosticNumber(health["helperResponseReceived"],1)==1&&health.ContainsKey("selectionQuery1Stage"),"DIAGNOSTIC_COMPLETED_SELECTION_NOT_RETAINED");
            Need(health.ContainsKey("configuredCopyStrategy")&&DiagnosticNumber(health["configuredCopyStrategy"],1)==0,"DIAGNOSTIC_STRICT_AUTO_STRATEGY_NOT_APPLIED");
            foreach(string flag in new string[]{"cancellationRequested","cancellationSignalled","cancellationSignalFailed"})Need(health.ContainsKey(flag)&&DiagnosticNumber(health[flag],1)==0,"DIAGNOSTIC_SUCCESS_CANCELLATION_MISMATCH");
            Need(Convert.ToBase64String(File.ReadAllBytes(History))==Convert.ToBase64String(history)&&Server.CountFor(expected)==mockCount&&SourceValue()==expected&&GetForegroundWindow()==form.Handle&&IsWindowVisible(Main)==visible&&Helpers().Count==0,"DIAGNOSTIC_CHANGED_APPLICATION_STATE");
            Ui(form,delegate{Need(source.Text==sourceText&&source.SelectedText==selected&&SourceVersions[source]==sourceVersion,"DIAGNOSTIC_CHANGED_SOURCE_CONTROL");});CheckClipboard();Need(GetClipboardSequenceNumber()==clipboard,"DIAGNOSTIC_CHANGED_CLIPBOARD_GENERATION");
            result["primaryProcessIdentityVerified"]=true;result["exactSecondaryExecutableRequested"]=true;result["fixedOwnedFileVerified"]=true;result["strictNumericNoContentSchema"]=true;result["healthFieldCount"]=health.Count;result["selectionQueryCount"]=DiagnosticNumber(health["selectionQueryCount"],16);result["fileBytes"]=bytes.Length;result["elapsedMilliseconds"]=clock.Elapsed.TotalMilliseconds;result["foregroundSourceHistoryMockClipboardVisibilityPreserved"]=true;result["ok"]=true;
        }finally{if(secondary!=null){if(!secondary.HasExited)try{secondary.Kill();if(!secondary.WaitForExit((int)Math.Max(0,5000-clock.ElapsedMilliseconds)))result["ownSecondaryCleanupFailed"]=true;}catch{result["ownSecondaryCleanupFailed"]=true;}secondary.Dispose();}}
    }
    sealed class FailedSourceObservation { public int Complete,Available,Empty,MatchesB,Failed; }
    // Observations are made only after the original case has failed. They do not
    // retry input, release a response, change focus, or extend any case deadline.
    static void ObserveFailedRapid(Dictionary<string,object> trace,Form source,string a,string b){
        Dictionary<string,object> snapshot=new Dictionary<string,object>();trace["failureOnlyObservation"]=snapshot;
        snapshot["takenAfterCaseFailure"]=1;snapshot["budgetMilliseconds"]=2000;snapshot["captureOrKeyRequests"]=0;
        Stopwatch budget=Stopwatch.StartNew();Process secondary=null;FailedSourceObservation editor=new FailedSourceObservation();
        try{
            snapshot["foregroundIsSource"]=GetForegroundWindow()==source.Handle?1:0;snapshot["foregroundIsApp"]=App!=null&&ForegroundPid()==App.Id?1:0;
            snapshot["A"]=Server.Snapshot(a);snapshot["B"]=Server.Snapshot(b);
            snapshot["historyHasA"]=HistoryHas(a)?1:0;snapshot["historyHasB"]=HistoryHas(b)?1:0;snapshot["activeNativeHelperCount"]=Helpers().Count;
            Thread reader=new Thread(delegate(){try{
                Need(App!=null&&!App.HasExited,"FAILURE_SOURCE_PRIMARY_UNAVAILABLE");AutomationElement ownRoot=AutomationElement.FromHandle(Main);Need(ownRoot!=null&&ownRoot.Current.ProcessId==App.Id&&!App.HasExited,"FAILURE_SOURCE_ROOT_NOT_OWNED");
                AutomationElement input=ownRoot.FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));object raw;
                string value=input!=null&&!input.Current.IsOffscreen&&input.TryGetCurrentPattern(ValuePattern.Pattern,out raw)?((ValuePattern)raw).Current.Value:null;editor.Available=value==null?0:1;editor.Empty=value==""?1:0;editor.MatchesB=value==b?1:0;
            }catch{editor.Failed=1;}finally{Interlocked.Exchange(ref editor.Complete,1);}});
            reader.IsBackground=true;reader.Name="EchoLingo failed-case source observation";reader.SetApartmentState(ApartmentState.MTA);reader.Start();
            string file=Path.Combine(DiagnosticRoaming,"selection-diagnostics.json");
            Need(DiagnosticPrimaryStart!=null&&App!=null&&!App.HasExited,"FAILURE_DIAGNOSTIC_PRIMARY_UNAVAILABLE");
            Need((File.GetAttributes(DiagnosticRoaming)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(DiagnosticRoaming,Marker))==DiagnosticToken,"FAILURE_DIAGNOSTIC_DIRECTORY_NOT_OWNED");
            Need(String.Equals(Path.GetFullPath(App.MainModule.FileName),Path.GetFullPath(DiagnosticExecutable),StringComparison.OrdinalIgnoreCase),"FAILURE_DIAGNOSTIC_EXE_MISMATCH");
            ProcessStartInfo start=new ProcessStartInfo(DiagnosticExecutable,"--selection-diagnostics");start.UseShellExecute=false;start.CreateNoWindow=true;
            foreach(string key in new string[]{"LOCALAPPDATA","TEMP","TMP","WEBVIEW2_USER_DATA_FOLDER"})start.EnvironmentVariables[key]=DiagnosticPrimaryStart.EnvironmentVariables[key];
            long earliest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;
            snapshot["diagnosticExportsRequested"]=1;secondary=Process.Start(start);
            while(budget.ElapsedMilliseconds<2000){
                if(secondary.HasExited){snapshot["diagnosticExportExited"]=1;snapshot["diagnosticExportSucceeded"]=secondary.ExitCode==0?1:0;break;}
                Thread.Sleep((int)Math.Min(10,Math.Max(1,2000-budget.ElapsedMilliseconds)));
            }
            if(secondary.HasExited&&secondary.ExitCode==0&&File.Exists(file)&&budget.ElapsedMilliseconds<2000){
                Need((File.GetAttributes(file)&FileAttributes.ReparsePoint)==0,"FAILURE_DIAGNOSTIC_FILE_REPARSE");byte[] bytes=File.ReadAllBytes(file);Need(bytes.Length>0&&bytes.Length<=16384,"FAILURE_DIAGNOSTIC_FILE_BOUND");
                Dictionary<string,object> payload=Json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));
                Need((string)payload["diagnostic"]=="last-selection-attempt"&&DiagnosticNumber(payload["processId"],Int32.MaxValue)==App.Id&&String.Equals((string)payload["executablePath"],Path.GetFullPath(DiagnosticExecutable),StringComparison.OrdinalIgnoreCase),"FAILURE_DIAGNOSTIC_PRIMARY_MISMATCH");
                long recorded=DiagnosticNumber(payload["recordedAtUnixMs"],Int64.MaxValue),latest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;
                snapshot["diagnosticIsFreshAfterFailure"]=recorded>=earliest&&recorded<=latest?1:0;
                if(recorded>=earliest&&recorded<=latest){
                    Dictionary<string,object> health=payload["diagnostics"] as Dictionary<string,object>;Need(health!=null,"FAILURE_DIAGNOSTIC_HEALTH_MISSING");
                    snapshot["nativeHealth"]=ValidatedSelectionHealth(health,recorded);
                }
            }
        }catch{snapshot["observationFailed"]=1;}
        finally{
            if(secondary!=null){try{if(!secondary.HasExited){secondary.Kill();snapshot["ownDiagnosticProcessStopped"]=1;}}catch{snapshot["ownDiagnosticProcessCleanupFailed"]=1;}secondary.Dispose();}
            if(Interlocked.CompareExchange(ref editor.Complete,0,0)!=0){snapshot["sourceObservationCompleted"]=1;snapshot["sourceAvailable"]=editor.Available;snapshot["sourceEmpty"]=editor.Empty;snapshot["sourceMatchesB"]=editor.MatchesB;snapshot["sourceObservationFailed"]=editor.Failed;}else snapshot["sourceObservationCompleted"]=0;
            snapshot["elapsedMilliseconds"]=Math.Min(10000000,budget.ElapsedMilliseconds);
        }
    }
    static void RecordBlankSource(Dictionary<string,object> trace,string value,string expected){
        trace["sourceObserved"]=true;trace["sourceAvailable"]=value!=null;trace["sourceEmpty"]=value=="";trace["sourceMatchesTyped"]=value==expected;
        // Only fixture literals/prefixes may contribute lengths or hashes. Never
        // serialize an unexpected value, even from this disposable own textarea.
        bool known=value!=null&&(expected.StartsWith(value,StringComparison.Ordinal)||value=="Pinned edit exact source 54001"||value=="Unselected source 55000");
        trace["sourceIsKnownFixtureDummy"]=known;
        if(known){trace["sourceDummyLength"]=value.Length;trace["sourceDummySha256"]=Hash(value);}
        else{trace.Remove("sourceDummyLength");trace.Remove("sourceDummySha256");}
    }
    sealed class FailedBlankObservation { public Dictionary<string,object> Metadata;public int Complete; }
    static void PublishBlankObservation(FailedBlankObservation result,Dictionary<string,object> value){Interlocked.Exchange(ref result.Metadata,new Dictionary<string,object>(value));}
    static List<Dictionary<string,object>> ValidatedFrontendInputEntries(Dictionary<string,object> payload,int pid,long latest){
        Need(payload.Count==3&&DiagnosticNumber(payload["processId"],Int32.MaxValue)==pid,"INPUT_DIAGNOSTIC_PRIMARY_SCHEMA");
        long recorded=DiagnosticNumber(payload["recordedAtUnixMs"],latest);
        var entries=payload["entries"] as IEnumerable;Need(entries!=null&&!(entries is string),"INPUT_DIAGNOSTIC_ENTRIES");
        var result=new List<Dictionary<string,object>>();long previous=0;
        var stages=new HashSet<string>(new string[]{"ready","arrival","handler","translateStart","ticket","dispatch","complete","error"});
        foreach(object item in entries){
            Need(result.Count<32,"INPUT_DIAGNOSTIC_ENTRY_BOUND");var row=item as Dictionary<string,object>;Need(row!=null&&row.Count==17,"INPUT_DIAGNOSTIC_RECORD_SCHEMA");
            string stage=row["stage"] as string;Need(stage!=null&&stages.Contains(stage),"INPUT_DIAGNOSTIC_STAGE");
            var copy=new Dictionary<string,object>{{"stage",stage}};
            foreach(string key in new string[]{"sequence","timestamp","epoch","generation"})copy[key]=DiagnosticNumber(row[key],key=="timestamp"?recorded:9007199254740991L);
            foreach(string key in new string[]{"requestEpoch","requestGeneration"})copy[key]=row[key]==null?null:(object)DiagnosticNumber(row[key],9007199254740991L);
            long sequence=(long)copy["sequence"];Need(sequence>previous,"INPUT_DIAGNOSTIC_SEQUENCE");previous=sequence;
            foreach(string key in new string[]{"composing","shift","alt","ctrl","meta","repeat","translating","sourceNonempty","sourceFocused","settingsReady"}){Need(row[key] is bool,"INPUT_DIAGNOSTIC_FLAG");copy[key]=(bool)row[key];}
            result.Add(copy);
        }
        return result;
    }
    static int FrontendInputObservationSelfTests(){
        var row=new Dictionary<string,object>{{"stage","handler"},{"sequence",1},{"timestamp",100},{"epoch",2},{"generation",3},{"requestEpoch",null},{"requestGeneration",null}};
        foreach(string key in new string[]{"composing","shift","alt","ctrl","meta","repeat","translating","sourceNonempty","sourceFocused","settingsReady"})row[key]=false;
        var payload=new Dictionary<string,object>{{"processId",7},{"recordedAtUnixMs",101},{"entries",new object[]{row}}};
        Need(ValidatedFrontendInputEntries(payload,7,102).Count==1,"INPUT_DIAGNOSTIC_VALID_RECORD_REJECTED");
        row["content"]="must not escape";bool rejected=false;try{ValidatedFrontendInputEntries(payload,7,102);}catch(InvalidOperationException){rejected=true;}Need(rejected,"INPUT_DIAGNOSTIC_EXTRA_CONTENT_ACCEPTED");row.Remove("content");
        row["stage"]="arbitrary text";rejected=false;try{ValidatedFrontendInputEntries(payload,7,102);}catch(InvalidOperationException){rejected=true;}Need(rejected,"INPUT_DIAGNOSTIC_FREE_STAGE_ACCEPTED");row["stage"]="handler";
        rejected=false;try{ValidatedFrontendInputEntries(payload,8,102);}catch(InvalidOperationException){rejected=true;}Need(rejected,"INPUT_DIAGNOSTIC_WRONG_PRIMARY_ACCEPTED");
        return 4;
    }
    static void ObserveFrontendInputFailure(Dictionary<string,object> trace){
        var observation=new Dictionary<string,object>{{"failureOnly",true},{"inputRetried",false}};trace["frontendInputObservation"]=observation;
        try{
            Need(App!=null&&!App.HasExited,"INPUT_DIAGNOSTIC_PRIMARY_UNAVAILABLE");
            Need((File.GetAttributes(DiagnosticRoaming)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(DiagnosticRoaming,Marker))==DiagnosticToken,"INPUT_DIAGNOSTIC_DIRECTORY_NOT_OWNED");
            Need(String.Equals(Path.GetFullPath(App.MainModule.FileName),Path.GetFullPath(DiagnosticExecutable),StringComparison.OrdinalIgnoreCase),"INPUT_DIAGNOSTIC_EXE_MISMATCH");
            string file=Path.Combine(DiagnosticRoaming,"frontend-input-diagnostics.json");observation["fileAvailable"]=File.Exists(file);if(!File.Exists(file))return;
            Need((File.GetAttributes(file)&FileAttributes.ReparsePoint)==0,"INPUT_DIAGNOSTIC_FILE_REPARSE");
            Need(new FileInfo(file).Length>0&&new FileInfo(file).Length<=32768,"INPUT_DIAGNOSTIC_FILE_BOUND");byte[] bytes=File.ReadAllBytes(file);Need(bytes.Length>0&&bytes.Length<=32768,"INPUT_DIAGNOSTIC_FILE_BOUND");
            var payload=Json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));long latest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;
            observation["entries"]=ValidatedFrontendInputEntries(payload,App.Id,latest);observation["primaryIdentityVerified"]=true;observation["strictNoContentSchema"]=true;
        }catch{observation["observationFailed"]=true;}
    }
    static void ObserveFailedBlank(Dictionary<string,object> trace,string typed){
        // This runs only after the original failure. A background UIA call may
        // outlive the budget, but it cannot hold up the original own-app cleanup.
        Dictionary<string,object> report=new Dictionary<string,object>{{"takenAfterCaseFailure",true},{"budgetMilliseconds",2000},{"inputRetried",false},{"frontendRequestEpochExportAvailable",false}};
        trace["failureOnlyObservation"]=report;ObserveFrontendInputFailure(trace);Stopwatch budget=Stopwatch.StartNew();FailedBlankObservation observation=new FailedBlankObservation();
        Thread reader=new Thread(delegate(){Dictionary<string,object> value=new Dictionary<string,object>();try{
            Need(App!=null&&!App.HasExited&&Main!=IntPtr.Zero,"BLANK_OBSERVATION_APP_UNAVAILABLE");
            uint owner;GetWindowThreadProcessId(Main,out owner);Need(owner==App.Id&&GetAncestor(Main,2)==Main,"BLANK_OBSERVATION_MAIN_NOT_OWNED");
            value["appForeground"]=ForegroundPid()==App.Id;Dictionary<string,object> mock=Server.Snapshot(typed);value["mock"]=mock;value["mockErrorPresent"]=Server.Error!=null;value["mockTerminalWithoutReply"]=Convert.ToInt32(mock["done"])!=0&&Convert.ToInt32(mock["responseSent"])==0;
            value["historyMatchesTyped"]=HistoryHas(typed);value["lastCompletedPhase"]="native-mock-history";PublishBlankObservation(observation,value);
            AutomationElement root=AutomationElement.FromHandle(Main);Need(root!=null&&root.Current.ProcessId==App.Id&&!App.HasExited,"BLANK_OBSERVATION_UIA_ROOT_NOT_OWNED");
            AutomationElement input=root.FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));
            value["sourceElementAvailable"]=input!=null;int[] wanted=null;
            if(input!=null){
                value["sourceIsOffscreen"]=input.Current.IsOffscreen;value["sourceHasKeyboardFocus"]=input.Current.HasKeyboardFocus;wanted=input.GetRuntimeId();Need(wanted!=null&&wanted.Length<=64,"BLANK_SOURCE_RUNTIME_ID_BOUND");object raw;
                string source=!input.Current.IsOffscreen&&input.TryGetCurrentPattern(ValuePattern.Pattern,out raw)?((ValuePattern)raw).Current.Value:null;RecordBlankSource(value,source,typed);
            }
            value["lastCompletedPhase"]="own-textarea";PublishBlankObservation(observation,value);
            // The global focused element contributes only its runtime-ID equality
            // boolean. Do not read its Current properties, Name, Text or Value.
            AutomationElement focused=AutomationElement.FocusedElement;int[] actual=focused==null?null:focused.GetRuntimeId();Need(actual==null||actual.Length<=64,"BLANK_FOCUS_RUNTIME_ID_BOUND");
            value["focusedRuntimeIdObserved"]=actual!=null;value["focusedRuntimeIdMatchesTextarea"]=wanted!=null&&actual!=null&&SameRuntimeId(wanted,actual);
            value["lastCompletedPhase"]="focus-runtime-id-only";PublishBlankObservation(observation,value);
            AutomationElement button=root.FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button),new PropertyCondition(AutomationElement.AutomationIdProperty,"translate-button")));
            string label=button==null?null:button.Current.Name;value["translationBusyState"]=label=="\u505c\u6b62\u7ffb\u8bd1"?"busy":label=="\u7ffb\u8bd1"?"idle":"unknown";
            value["lastCompletedPhase"]="own-button-fixed-label";
        }catch(Exception e){value["observationExceptionType"]=e.GetType().Name;}finally{PublishBlankObservation(observation,value);Interlocked.Exchange(ref observation.Complete,1);}});
        reader.IsBackground=true;reader.Name="EchoLingo failed blank-input metadata";reader.SetApartmentState(ApartmentState.MTA);reader.Start();
        reader.Join((int)Math.Max(0,2000-budget.ElapsedMilliseconds));
        Dictionary<string,object> metadata=Interlocked.CompareExchange(ref observation.Metadata,null,null);if(metadata!=null)report["metadata"]=metadata;
        report["observationCompleted"]=Interlocked.CompareExchange(ref observation.Complete,0,0)!=0;report["elapsedMilliseconds"]=Math.Min(10000000,budget.ElapsedMilliseconds);
    }
    static void BlankCase(Form form,TextBox edit,Control[] controls){
        const string typed="Typed blank popup 55001";Server.Allow(typed,false);PutSource(form,edit,controls,"Unselected source 55000",false);Ui(form,delegate{edit.Select(0,0);});SeedClipboard();Dictionary<string,object> blank=Begin("empty-selection-first-input-enter",typed,"actual-Unicode-SendInput");Hotkey(form);
        try{Wait(delegate{return SourceValue()==""&&ForegroundPid()==App.Id;},15000,"EMPTY_SELECTION_NOT_FOCUSED_BLANK");}
        catch(InvalidOperationException e){if(e.Message!="TIMEOUT:EMPTY_SELECTION_NOT_FOCUSED_BLANK")throw;Need(Helpers().Count==0,"BLANK_FAILURE_WITH_PENDING_HELPER");CheckClipboard();blank["error"]=e.Message;blank["hotkeysSent"]=1;blank["actualSourceSha256"]=SourceValue()==null?null:Hash(SourceValue());blank["appForeground"]=ForegroundPid()==App.Id;blank["typedTextInjected"]=false;blank["safeToContinue"]=true;return;}
        Type(typed,true);blank["typedTextInjected"]=true;Stopwatch submitted=Stopwatch.StartNew();
        Dictionary<string,object> predicate=new Dictionary<string,object>{{"historyObserved",false},{"historyEverMatched",false},{"sourceObserved",false},{"sourceEverMatched",false},{"sourceSkippedOnLastPredicate",true}};blank["submissionPredicate"]=predicate;
        try{Wait(delegate{
            // Preserve the original HistoryHas && SourceValue short circuit.
            bool history=HistoryHas(typed);predicate["historyObserved"]=true;predicate["lastHistoryMatched"]=history;predicate["lastAtMilliseconds"]=submitted.ElapsedMilliseconds;predicate["sourceSkippedOnLastPredicate"]=!history;
            if(!history)return false;
            if(!Convert.ToBoolean(predicate["historyEverMatched"]))predicate["historyFirstMatchedMilliseconds"]=submitted.ElapsedMilliseconds;predicate["historyEverMatched"]=true;
            string value=SourceValue();RecordBlankSource(predicate,value,typed);
            if(value==typed){if(!Convert.ToBoolean(predicate["sourceEverMatched"]))predicate["sourceFirstMatchedMilliseconds"]=submitted.ElapsedMilliseconds;predicate["sourceEverMatched"]=true;}
            return value==typed;
        },30000,"EMPTY_FIRST_INPUT_EXACT");}
        catch{blank["failedAtMilliseconds"]=submitted.ElapsedMilliseconds;try{ObserveFailedBlank(blank,typed);}catch{blank["failureObservationFailed"]=true;}throw;}
        CheckClipboard();blank["hotkeysSent"]=1;blank["actualSourceSha256"]=Hash(SourceValue());blank["ok"]=true;
    }
    static HashSet<int> Helpers(){HashSet<int> ids=new HashSet<int>();IntPtr snapshot=CreateToolhelp32Snapshot(2,0);Need(snapshot!=new IntPtr(-1),"PROCESS_SNAPSHOT_FAILED");try{ENTRY e=new ENTRY();e.size=(uint)Marshal.SizeOf(typeof(ENTRY));if(Process32FirstW(snapshot,ref e))do{if(e.parent==App.Id&&String.Equals(e.exe,"powershell.exe",StringComparison.OrdinalIgnoreCase))ids.Add((int)e.pid);}while(Process32NextW(snapshot,ref e));}finally{CloseHandle(snapshot);}return ids;}
    static bool IsSelectedHelper(int pid){
        // Only this disposable app's known new PowerShell child is queried.
        // Keep argv transient; return a fixed mode boolean, never serialize it.
        using(ManagementObjectSearcher query=new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE ProcessId="+pid+" AND ParentProcessId="+App.Id)){
            foreach(ManagementObject item in query.Get())using(item){string command=item["CommandLine"] as string;return command!=null&&command.IndexOf("-Mode selected-text",StringComparison.OrdinalIgnoreCase)>=0;}
        }return false;
    }
    static void SameWindowFocusRace(Form form,TextBox first,TextBox second,Control[] controls){
        const string a="Focus race original A 34101",b="Focus race unrelated B 34102";Server.Allow(a,false);Server.Allow(b,false);ForbiddenFocusB=b;ExplicitFocusBAllowed=0;UnexpectedFocusB=0;PutSource(form,first,controls,a,false);Ui(form,delegate{first.SetBounds(10,8,form.ClientSize.Width-20,28);second.Visible=true;second.SetBounds(10,50,form.ClientSize.Width-20,28);second.Text=b;});
        Wait(delegate{return Helpers().Count==0;},10000,"PRIOR_HELPER_EXIT");HashSet<int> before=Helpers();SeedClipboard();Dictionary<string,object> c=Begin("same-window-focus-change-after-helper-spawn",a,"two-real-Edit-controls; one-shortcut");FocusRaceCase=c;Hotkey(form);int observed=0;Process selectedHelper=null;Stopwatch observedToFocus=null;HashSet<int> inspected=new HashSet<int>();Wait(delegate{foreach(int pid in Helpers())if(!before.Contains(pid)&&inspected.Add(pid)){try{selectedHelper=Process.GetProcessById(pid);bool exited=selectedHelper.HasExited;if(exited){selectedHelper.Dispose();selectedHelper=null;continue;}observed=pid;observedToFocus=Stopwatch.StartNew();return true;}catch(ArgumentException){}}return false;},5000,"ACTUAL_SELECTED_TEXT_CHILD_ACCEPTANCE");
        Ui(form,delegate{second.Focus();second.SelectAll();});c["childObservedToFocusSwitchMilliseconds"]=observedToFocus.Elapsed.TotalMilliseconds;Need(GetForegroundWindow()==form.Handle,"FOCUS_RACE_CHANGED_WINDOW");Need(IsSelectedHelper(observed),"BOUND_CHILD_MODE_UNVERIFIED_NO_RACE_ACCEPTANCE");c["modeVerificationAfterFocusSwitch"]=true;c["actualAcceptedHelperPid"]=observed;c["sameSourceWindowPreserved"]=true;
        Wait(delegate{return selectedHelper.HasExited;},20000,"BOUND_SELECTED_TEXT_HELPER_EXIT");selectedHelper.Dispose();c["boundSelectedTextHelperExited"]=true;c["helperModeVerified"]=true;bool wrongB=false;Observe(delegate{if(Server.CountFor(b)>0||HistoryHas(b)||SourceValue()==b)wrongB=true;return true;},1000,"RACE_OBSERVATION");CheckClipboard();c["allowedOutcome"]=wrongB?"FAILED-unrelated-B-imported":HistoryHas(a)?"trigger-A-completed":"safely-empty-cancelled-or-prior-source-retained";c["unrelatedBImported"]=wrongB;c["hotkeysSent"]=Hotkeys-Convert.ToInt32(c["hotkeysBefore"]);c["ok"]=!wrongB;if(wrongB)c["error"]="WRONG_POST_TRIGGER_SELECTION_B_WAS_IMPORTED";FocusRaceLedger();
        // A distinct explicit action is required before B may be imported.
        SelectionCase("same-window-B-explicit-next-shortcut",form,second,controls,b,false);FocusRaceLedger();c["finalBRequestCountAfterOneExplicitIntent"]=Server.CountFor(b);c["finalBHistoryCountAfterOneExplicitIntent"]=HistorySourceCount(b);if(Server.CountFor(b)!=1||HistorySourceCount(b)!=1){c["ok"]=false;c["unrelatedBImported"]=true;c["error"]="EXTRA_B_ACQUISITION_WITH_ONLY_ONE_EXPLICIT_B_INTENT";}
    }
    static void DelayedCases(Form form,Form other,TextBox edit,TextBox otherEdit,Control[] controls){
        string a="Rapid selection original 45101",b="Rapid selection newest 45102";Server.Allow(a,true);Server.Allow(b,false);PutSource(form,edit,controls,a,false);SeedClipboard();Dictionary<string,object> c=Begin("rapid-A-then-new-selection-B",b,"single-shortcut-per-distinct-intent");
        c["nativeChildObservationPerformed"]=false;c["mockHoldDeadlineMilliseconds"]=20000;c["latestBDeadlineMilliseconds"]=30000;c["failureDiagnosticsAfterFailureOnly"]=true;c["failureDiagnosticsBudgetMilliseconds"]=2000;
        Stopwatch rapid=Stopwatch.StartNew();
        try{
            c["rapidPhase"]="send-A";Hotkey(form);c["hotkeysSent"]=Hotkeys-Convert.ToInt32(c["hotkeysBefore"]);
            c["rapidPhase"]="wait-A-request";Wait(delegate{return Server.Seen(a);},15000,"RAPID_FIRST_REQUEST");c["ARequestObservedAtMilliseconds"]=rapid.ElapsedMilliseconds;
            c["rapidPhase"]="prepare-B";PutSource(form,edit,controls,b,false);
            c["rapidPhase"]="send-B";Hotkey(form);c["hotkeysSent"]=Hotkeys-Convert.ToInt32(c["hotkeysBefore"]);c["BHotkeySentAtMilliseconds"]=rapid.ElapsedMilliseconds;
            c["rapidPhase"]="wait-B-history-and-source";
            Wait(delegate{
                bool history=HistoryHas(b);c["lastPredicateBHistory"]=history;c["lastPredicateAtMilliseconds"]=rapid.ElapsedMilliseconds;
                if(!history)return false;
                string value=SourceValue();c["lastPredicateSourceObserved"]=true;c["lastPredicateSourceAvailable"]=value!=null;c["lastPredicateSourceEmpty"]=value=="";c["lastPredicateSourceMatchesB"]=value==b;
                return value==b;
            },30000,"RAPID_LATEST_B");
            c["BCompleteObservedAtMilliseconds"]=rapid.ElapsedMilliseconds;c["rapidPhase"]="release-A";Server.Release(a);c["AReleaseRequested"]=true;
            c["rapidPhase"]="wait-A-response";Wait(delegate{return Server.Handled(a);},5000,"RAPID_OLD_RESPONSE");
            c["rapidPhase"]="observe-no-old-overwrite";Observe(delegate{return SourceValue()==b&&!HistoryHas(a);},750,"OLD_RESPONSE_OVERWROTE_NEW_SELECTION");
            c["rapidPhase"]="check-clipboard-and-focus";CheckClipboard();Need(GetForegroundWindow()==form.Handle,"RAPID_SELECTION_STOLE_FOCUS");
            c["hotkeysSent"]=2;c["abandonedSourceSha256"]=Hash(a);c["actualSourceSha256"]=Hash(SourceValue());c["oldPartialNotSaved"]=true;c["rapidPhase"]="complete";c["ok"]=true;
        }catch{
            c["failedAtMilliseconds"]=rapid.ElapsedMilliseconds;c["hotkeysSent"]=Hotkeys-Convert.ToInt32(c["hotkeysBefore"]);
            ObserveFailedRapid(c,form,a,b);throw;
        }
        a="App switch old request 46101";b="App switch newest request 46102";Server.Allow(a,true);Server.Allow(b,false);PutSource(form,edit,controls,a,false);c=Begin("intentional-source-window-switch-with-new-AltD",b,"distinct-generated-foreground-window");Hotkey(form);Wait(delegate{return Server.Seen(a);},15000,"APP_SWITCH_OLD_REQUEST");PutSource(other,otherEdit,new Control[]{otherEdit},b,false);Hotkey(other);Wait(delegate{return HistoryHas(b)&&SourceValue()==b;},30000,"APP_SWITCH_LATEST_B");Server.Release(a);Wait(delegate{return Server.Handled(a);},5000,"APP_SWITCH_OLD_RESPONSE");Observe(delegate{return SourceValue()==b&&!HistoryHas(a)&&GetForegroundWindow()==other.Handle;},750,"OLD_APP_OVERWROTE_CURRENT_INTENT");CheckClipboard();c["hotkeysSent"]=2;c["sourceWindowChanged"]=true;c["sourceProcessChanged"]=false;c["actualSourceSha256"]=Hash(SourceValue());c["ok"]=true;
        a="Manual edit cancelled source 47101";string manual="Manual edited source 47102";Server.Allow(a,true);PutSource(form,edit,controls,a,false);c=Begin("manual-editor-input-cancels-old-translation",manual,"actual-app-Unicode-SendInput");Hotkey(form);Wait(delegate{return Server.Seen(a)&&SourceValue()==a;},15000,"MANUAL_OLD_REQUEST");AutomationElement input=Source();Need(input!=null,"ACTUAL_SOURCE_EDITOR_MISSING");input.SetFocus();System.Windows.Rect inputBounds=input.Current.BoundingRectangle;Point click=new Point((int)(inputBounds.Left+Math.Min(30,inputBounds.Width/2)),(int)(inputBounds.Top+Math.Min(20,inputBounds.Height/2)));Need(GetAncestor(WindowFromPoint(click),2)==Main,"MANUAL_CLICK_NOT_ACTUAL_SOURCE_ROOT");Move(click);Mouse(false);Mouse(true);Wait(delegate{if(ForegroundPid()!=App.Id)return false;AutomationElement actualFocus=AutomationElement.FocusedElement;int[] wanted=input.GetRuntimeId(),actual=actualFocus==null?null:actualFocus.GetRuntimeId();if(actual==null||actual.Length!=wanted.Length)return false;for(int i=0;i<wanted.Length;i++)if(wanted[i]!=actual[i])return false;return true;},3000,"MANUAL_SOURCE_EDITOR_ACTUAL_FOCUS");c["actualTextareaClick"]=true;c["beforeTypingSourceSha256"]=SourceValue()==null?null:Hash(SourceValue());Send(new INPUT[]{Key(0x11,false),Key(0x41,false),Key(0x41,true),Key(0x11,true)});Type(manual,false);c["typedTextInjected"]=true;try{Wait(delegate{return SourceValue()==manual;},5000,"ACTUAL_MANUAL_INPUT");}catch{c["afterTypingSourceSha256"]=SourceValue()==null?null:Hash(SourceValue());c["appForegroundAfterTyping"]=ForegroundPid()==App.Id;throw;}Server.Release(a);Wait(delegate{return Server.Handled(a);},5000,"MANUAL_OLD_RESPONSE");Observe(delegate{return SourceValue()==manual&&!HistoryHas(a)&&!HistoryHas(manual);},750,"OLD_TRANSLATION_OVERWROTE_MANUAL_EDIT");CheckClipboard();c["hotkeysSent"]=1;c["actualSourceSha256"]=Hash(SourceValue());c["manualTextNotAutoSubmitted"]=true;c["ok"]=true;
        a="Management navigation pending 48101";Server.Allow(a,true);PutSource(form,edit,controls,a,false);c=Begin("management-navigation-preserves-view-source-and-focus",a,"real-UIA-more-settings; explicitly gated response");Hotkey(form);Wait(delegate{return Server.Seen(a)&&SourceValue()==a;},15000,"MANAGEMENT_OLD_REQUEST");
        c["historyBeforeNavigation"]=HistoryHas(a);c["mockResponseSentBeforeNavigation"]=Server.ResponseSent(a);Need(!Server.ResponseSent(a),"MANAGEMENT_REPLY_WAS_NOT_GATED");Invoke("\u66f4\u591a",c,"open-more");Invoke("\u8bbe\u7f6e",c,"open-settings");c["managementReadyDeadlineMilliseconds"]=5000;Wait(delegate{return ReadManagementReady(c);},5000,"ACTUAL_MANAGEMENT_VIEW");ManagementPhase(c,"ready:complete");
        ManagementPhase(c,"snapshot:read-foreground");IntPtr managementForeground=GetForegroundWindow();ManagementPhase(c,"snapshot:read-focus-runtime-id");int[] managementFocus=FocusRuntimeId();Need(managementFocus!=null,"MANAGEMENT_FOCUS_ID_UNAVAILABLE");ManagementPhase(c,"snapshot:read-hidden-source-value");string hiddenSourceBefore=SourceAnyValue();Need(hiddenSourceBefore==null||hiddenSourceBefore==a,"MANAGEMENT_SOURCE_CHANGED_BEFORE_REPLY");
        ManagementPhase(c,"snapshot:verify-settings-and-source");c["managementVisibleBeforeRelease"]=SettingsVisible();c["visibleSourceNullBeforeRelease"]=SourceValue()==null;c["hiddenSourceValueInspectable"]=hiddenSourceBefore!=null;c["hiddenSourceSha256BeforeRelease"]=hiddenSourceBefore==null?null:Hash(hiddenSourceBefore);c["focusRuntimeIdBeforeRelease"]=managementFocus;c["foregroundHwndBeforeRelease"]="0x"+managementForeground.ToInt64().ToString("X");c["historyBeforeRelease"]=HistoryHas(a);c["mockResponseSentBeforeRelease"]=Server.ResponseSent(a);Need(!Server.ResponseSent(a),"MANAGEMENT_REPLY_PRECEDED_READY_VIEW");
        ManagementPhase(c,"response:release");Server.Release(a);c["mockResponseReleasedAfterManagementReady"]=true;Wait(delegate{return Server.Handled(a);},5000,"MANAGEMENT_OLD_RESPONSE");c["mockResponseHandled"]=true;c["mockResponseSent"]=Server.ResponseSent(a);
        Observe(delegate{
            ManagementPhase(c,"observation:read-settings-visible");bool visible=SettingsVisible();ManagementPhase(c,"observation:read-visible-source");bool sourceNull=SourceValue()==null;ManagementPhase(c,"observation:read-focus-runtime-id");int[] focus=FocusRuntimeId();bool focusSame=SameRuntimeId(managementFocus,focus),foregroundSame=GetForegroundWindow()==managementForeground;ManagementPhase(c,"observation:read-hidden-source");string hiddenSource=SourceAnyValue();
            c["managementVisibleAfterResponse"]=visible;c["visibleSourceNullAfterResponse"]=sourceNull;c["focusRuntimeIdAfterResponse"]=focus;c["focusUnchangedAfterResponse"]=focusSame;c["foregroundUnchangedAfterResponse"]=foregroundSame;c["historyAfterResponse"]=HistoryHas(a);c["hiddenSourceSha256AfterResponse"]=hiddenSource==null?null:Hash(hiddenSource);
            return visible&&sourceNull&&focusSame&&foregroundSame&&(hiddenSource==null||hiddenSource==a);
        },750,"LATE_RESPONSE_CHANGED_MANAGEMENT_VIEW_SOURCE_OR_FOCUS");
        CheckClipboard();c["managementRemainedBeforeExplicitReturn"]=true;c["historyCompletionIsNotNavigationFailure"]=true;Invoke("\u8fd4\u56de\u7ffb\u8bd1",c,"explicit-audit-return");c["explicitReturnForSourceAudit"]=true;ManagementPhase(c,"audit:return-source-value");Wait(delegate{return SourceValue()==a;},5000,"MANAGEMENT_PRESERVED_ORIGINAL_SOURCE");c["actualSourceSha256"]=Hash(SourceValue());c["sourcePreservedAfterExplicitReturn"]=true;c["hotkeysSent"]=1;ManagementPhase(c,"complete");c["ok"]=true;
    }
    sealed class Pending {public readonly ManualResetEventSlim Seen=new ManualResetEventSlim(false),Release=new ManualResetEventSlim(false),Done=new ManualResetEventSlim(false);public int Count,Sent,HoldExpired;public long HoldStartedTicks,HoldEndedTicks;}
    sealed class Mock:IDisposable {
        readonly TcpListener listener=new TcpListener(IPAddress.Loopback,0);readonly Thread thread;readonly object gate=new object();readonly Dictionary<string,Pending> allowed=new Dictionary<string,Pending>();volatile bool stop;public volatile string Error;
        public Mock(){listener.Start();thread=new Thread(Loop);thread.IsBackground=true;thread.Start();}
        public string Url{get{return "http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port;}}
        public static string Result(string source){return "GENERATED_MOCK_TRANSLATION_"+Hash(source);}
        public void Allow(string source,bool delay){lock(gate){if(allowed.ContainsKey(source)){Need(!delay,"DELAYED_SOURCE_REDECLARED");return;}Pending p=new Pending();if(!delay)p.Release.Set();allowed.Add(source,p);}}
        Pending Get(string source){lock(gate){Pending p;Need(allowed.TryGetValue(source,out p),"NON_FIXTURE_SOURCE_REJECTED_CONTENT_NOT_LOGGED");return p;}}
        public int CountFor(string s){Pending p=Get(s);return Interlocked.CompareExchange(ref p.Count,0,0);}
        public Dictionary<string,object> Snapshot(string source){
            Pending p=Get(source);long started=Interlocked.Read(ref p.HoldStartedTicks),ended=Interlocked.Read(ref p.HoldEndedTicks);
            long elapsed=started==0?0:(long)Math.Max(0,Math.Min(10000000,((ended==0?Stopwatch.GetTimestamp():ended)-started)*1000.0/Stopwatch.Frequency));
            return new Dictionary<string,object>{{"requests",CountFor(source)},{"seen",p.Seen.IsSet?1:0},{"releaseSet",p.Release.IsSet?1:0},{"done",p.Done.IsSet?1:0},{"responseSent",Interlocked.CompareExchange(ref p.Sent,0,0)},{"holdExpired",Interlocked.CompareExchange(ref p.HoldExpired,0,0)},{"holdElapsedMilliseconds",elapsed}};
        }
        public bool Seen(string s){return Get(s).Seen.IsSet;}public bool Handled(string s){return Get(s).Done.IsSet;}public bool ResponseSent(string s){return Interlocked.CompareExchange(ref Get(s).Sent,0,0)!=0;}public void Release(string s){Get(s).Release.Set();}
        void Loop(){while(!stop){try{TcpClient c=listener.AcceptTcpClient();ThreadPool.QueueUserWorkItem(delegate{Handle(c);});}catch(Exception e){if(!stop)Error="MOCK_ACCEPT:"+e.GetType().Name;}}}
        void Handle(TcpClient client){Pending pending=null;try{using(client){client.ReceiveTimeout=5000;client.SendTimeout=5000;NetworkStream stream=client.GetStream();List<byte> head=new List<byte>();while(head.Count<16384){int b=stream.ReadByte();Need(b>=0,"MOCK_TRUNCATED_HEADERS");head.Add((byte)b);int n=head.Count;if(n>=4&&head[n-4]==13&&head[n-3]==10&&head[n-2]==13&&head[n-1]==10)break;}string headers=Encoding.ASCII.GetString(head.ToArray());Need(headers.StartsWith("POST /translate HTTP/1.1\r\n",StringComparison.Ordinal),"MOCK_UNEXPECTED_ROUTE");int length=-1;foreach(string line in headers.Split(new string[]{"\r\n"},StringSplitOptions.None)){Need(!line.StartsWith("Authorization:",StringComparison.OrdinalIgnoreCase),"MOCK_CREDENTIAL_FORBIDDEN");if(line.StartsWith("Content-Length:",StringComparison.OrdinalIgnoreCase))length=Int32.Parse(line.Substring(15).Trim());}Need(length>=0&&length<=65536,"MOCK_BODY_BOUND");byte[] bytes=new byte[length];int offset=0;while(offset<length){int n=stream.Read(bytes,offset,length-offset);Need(n>0,"MOCK_TRUNCATED_BODY");offset+=n;}Dictionary<string,object> body=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));string q=(string)body["q"];pending=Get(q);if(q==ForbiddenFocusB&&Interlocked.CompareExchange(ref ExplicitFocusBAllowed,0,0)==0)Interlocked.Increment(ref UnexpectedFocusB);Need(!body.ContainsKey("api_key")||String.IsNullOrEmpty(body["api_key"] as string),"MOCK_KEY_FORBIDDEN");Need((string)body["target"]=="zh","MOCK_DIRECTION_NOT_CHINESE");Interlocked.Increment(ref pending.Count);Interlocked.Exchange(ref pending.HoldStartedTicks,Stopwatch.GetTimestamp());pending.Seen.Set();bool released=pending.Release.Wait(20000);Interlocked.Exchange(ref pending.HoldEndedTicks,Stopwatch.GetTimestamp());if(!released)Interlocked.Exchange(ref pending.HoldExpired,1);Need(released,"MOCK_CONTROLLED_REPLY_NOT_RELEASED");byte[] response=Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(new Dictionary<string,object>{{"translatedText",Result(q)}}));byte[] prefix=Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+response.Length+"\r\n\r\n");stream.Write(prefix,0,prefix.Length);stream.Write(response,0,response.Length);stream.Flush();Interlocked.Exchange(ref pending.Sent,1);}}catch(IOException){if(pending==null)Error="MOCK_UNCLASSIFIED_IO";}catch(SocketException){if(pending==null)Error="MOCK_UNCLASSIFIED_SOCKET";}catch(Exception e){if(!stop)Error="MOCK_FAILURE:"+e.GetType().Name+":"+e.Message;}finally{if(pending!=null)pending.Done.Set();}}
        public void Dispose(){stop=true;lock(gate)foreach(Pending p in allowed.Values)p.Release.Set();listener.Stop();Need(thread.Join(2000),"MOCK_THREAD_NOT_STOPPED");}
    }
    static string KnownFolder(string id){Guid folder=new Guid(id);IntPtr p;Need(SHGetKnownFolderPath(ref folder,0,IntPtr.Zero,out p)==0,"KNOWN_FOLDER_FAILED");try{return Marshal.PtrToStringUni(p);}finally{CoTaskMemFree(p);}}
    static void Claim(string path,string token,List<string> owned){Need(CreateDirectory(path,IntPtr.Zero),"EXISTING_DIRECTORY_REFUSED");File.WriteAllText(Path.Combine(path,Marker),token,new UTF8Encoding(false));owned.Add(path);}
    static void Remove(string path,string token){if(!Directory.Exists(path))return;Need((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(path,Marker))==token,"OWNERSHIP_CHANGED_DIRECTORY_PRESERVED");for(int i=0;;i++){try{Directory.Delete(path,true);return;}catch(IOException){if(i>=19)throw;}catch(UnauthorizedAccessException){if(i>=19)throw;}Thread.Sleep(100);}}
    static void KillOwn(){if(App==null||App.HasExited)return;ProcessStartInfo s=new ProcessStartInfo("taskkill.exe","/PID "+App.Id+" /T /F");s.UseShellExecute=false;s.CreateNoWindow=true;s.RedirectStandardOutput=true;s.RedirectStandardError=true;using(Process p=Process.Start(s)){p.StandardOutput.ReadToEnd();p.StandardError.ReadToEnd();Need(p.WaitForExit(10000),"OWN_TREE_KILL_TIMEOUT");}Need(App.WaitForExit(5000),"OWN_APP_REMAINED");}
    public static Dictionary<string,object> Run(string executable,string expectedApplicationVersion){
        Need(!String.IsNullOrWhiteSpace(expectedApplicationVersion)&&expectedApplicationVersion.Length<=128,"EXPECTED_APPLICATION_VERSION_REQUIRED");ExpectedApplicationVersion=expectedApplicationVersion;
        Cases.Clear();SourceVersions.Clear();MouseDownCounts.Clear();MouseUpCounts.Clear();PreviousSelectionDown.Clear();MouseSelectionPlacement=0;ForbiddenFocusB=null;FocusRaceCase=null;ExplicitFocusBAllowed=0;UnexpectedFocusB=0;Hotkeys=0;Report=new Dictionary<string,object>{{"ok",false},{"cases",Cases},{"actualApplicationTested",false},{"actualRegisteredAltD",true},{"fakeIpcUsed",false},{"translationBackend","loopback-mock"},{"userContentRead",false},{"physicalWindows11Tested",false},{"browserTested",false},{"fullscreenTested",false},{"multiMonitorTested",false},{"credentialsCreated",false},{"credentialScope","One random absent mock provider; no existing credentials"},{"sameHotkeyRetries",0}};
        Report["frontendInputObservationSelfTests"]=FrontendInputObservationSelfTests();Report["configuredWindowsSelectionStrategy"]=ConfiguredWindowsSelectionStrategy;Report["defaultWindowsSelectionStrategyUnderTest"]=false;Report["expectedApplicationVersion"]=ExpectedApplicationVersion;DiagnosticPrimaryStart=null;DiagnosticExecutable=executable;
        string token=Guid.NewGuid().ToString("N"),root=Path.Combine(Path.GetTempPath(),"echolingo-selection-app-"+token),roaming=Path.Combine(KnownFolder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"),Identifier),local=Path.Combine(KnownFolder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"),Identifier);List<string> owned=new List<string>();
        foreach(Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))using(p)Need(p.HasExited,"EXISTING_APPLICATION_REFUSED");
        try{
            IDataObject old=Clipboard.GetDataObject();Need(old==null||old.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");Claim(roaming,token,owned);Claim(local,token,owned);Claim(root,token,owned);History=Path.Combine(roaming,"history.json");Provider="generated-selection-"+token;DiagnosticRoaming=roaming;DiagnosticToken=token;
            Report["historyReaderLifetimeRegression"]=HistoryReaderLifetimeRegression(root);
            using(Server=new Mock()){
                Dictionary<string,object> settings=new Dictionary<string,object>{{"providers",new object[]{new Dictionary<string,object>{{"id",Provider},{"name","Generated loopback mock"},{"kind","libretranslate"},{"baseUrl",Server.Url},{"enabled",true},{"model",""},{"prompt",""}}}},{"ocrProviders",new object[0]},{"sourceLanguage","auto"},{"targetLanguage","auto"},{"languageDirectionVersion",1},{"shortcutDefaultsVersion",1},{"saveHistory",true},{"maxHistory",100},{"theme","light"},{"autoHideSeconds",0},{"shortcuts",new Dictionary<string,object>{{"selection","Alt+D"},{"silentOcr","Alt+S"},{"ocr",""},{"capture",""},{"input",""}}}};settings["windowsSelectionStrategy"]=ConfiguredWindowsSelectionStrategy;File.WriteAllText(Path.Combine(roaming,"settings.json"),Json.Serialize(settings),new UTF8Encoding(false));
                SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"PHYSICAL_COORDINATES_REQUIRED");
                using(Form form=new Form())using(Form other=new Form())using(TextBox edit=new TextBox())using(TextBox multi=new TextBox())using(RichTextBox rich=new RichTextBox())using(TextBox second=new TextBox())using(TextBox otherEdit=new TextBox()){
                    form.Text="Generated selection source A";form.StartPosition=FormStartPosition.Manual;form.Bounds=new Rectangle(12,8,740,150);form.FormBorderStyle=FormBorderStyle.FixedDialog;form.MaximizeBox=false;other.Text="Generated selection source B";other.StartPosition=FormStartPosition.Manual;other.FormBorderStyle=FormBorderStyle.FixedDialog;other.MaximizeBox=false;
                    multi.Multiline=true;rich.Multiline=true;multi.WordWrap=false;rich.WordWrap=false;foreach(TextBoxBase c in new TextBoxBase[]{edit,multi,rich,second,otherEdit}){c.Font=new Font("Consolas",11);TextBoxBase captured=c;SourceVersions[c]=0;MouseDownCounts[c]=0;MouseUpCounts[c]=0;c.TextChanged+=delegate{SourceVersions[captured]++;};c.MouseDown+=delegate{MouseDownCounts[captured]++;};c.MouseUp+=delegate{MouseUpCounts[captured]++;};}form.Controls.AddRange(new Control[]{edit,multi,rich,second});other.Controls.Add(otherEdit);Control[] controls=new Control[]{edit,multi,rich,second};bool finished=false;form.FormClosing+=delegate(object sender,FormClosingEventArgs e){if(!finished)e.Cancel=true;};
                    form.Shown+=delegate{Thread worker=new Thread(delegate(){try{
                        Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"WORKER_PHYSICAL_COORDINATES_REQUIRED");ProcessStartInfo start=new ProcessStartInfo(executable);start.UseShellExecute=false;start.CreateNoWindow=true;string childLocal=Path.Combine(root,"Local"),childTemp=Path.Combine(root,"Temp");Directory.CreateDirectory(childLocal);Directory.CreateDirectory(childTemp);start.EnvironmentVariables["LOCALAPPDATA"]=childLocal;start.EnvironmentVariables["TEMP"]=childTemp;start.EnvironmentVariables["TMP"]=childTemp;start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"]=Path.Combine(local,"webview-selection-fixture");start.EnvironmentVariables["ECHOLINGO_INPUT_DIAGNOSTICS"]="1";DiagnosticPrimaryStart=start;App=Process.Start(start);Report["applicationProcessId"]=App.Id;Report["actualApplicationTested"]=true;Need(App.WaitForInputIdle(15000),"APP_INPUT_IDLE");Wait(delegate{return (Main=MainWindow(App.Id))!=IntPtr.Zero;},20000,"UNIQUE_ACTUAL_TAURI_WINDOW");
                        // First shortcut follows observable native host/tray readiness, with no fixed frontend warmup.
                        // Their existence proves neither successful OS registration nor JS subscriptions.
                        Dictionary<string,object> readiness=null;Wait(delegate{readiness=NativeReadiness();return Convert.ToInt32(readiness["globalHotkeyWindowCount"])>0&&Convert.ToInt32(readiness["trayWindowCount"])>0;},15000,"NATIVE_REGISTRATION_HOST_AND_TRAY");readiness["waitForInputIdleSucceeded"]=true;readiness["fixedFrontendWarmupMilliseconds"]=0;Report["beforeFirstHotkeyReadiness"]=readiness;
                        SelectionCase("edit-mouse-round-1",form,edit,controls,"Selection Edit round 1 token 51001",true);
                        if(Convert.ToBoolean(Cases[0]["ok"]))SelectionDiagnosticsCli(executable,start,roaming,token,form,edit);
                        SameWindowFocusRace(form,edit,second,controls);
                        Invoke("\u9489\u4f4f\u7a97\u53e3");Wait(delegate{return Element("\u53d6\u6d88\u9489\u4f4f")!=null;},5000,"PIN_NOT_ENGAGED");SelectionCase("pinned-edit-update",form,edit,controls,"Pinned edit exact source 54001",false);
                        BlankCase(form,edit,controls);
                        for(int round=2;round<=3;round++)SelectionCase("edit-mouse-round-"+round,form,edit,controls,"Selection Edit round "+round+" token "+(51000+round),true);
                        SelectionCase("multiline-explicit-paragraphs",form,multi,controls,"First paragraph 53001.\r\n\r\nSecond paragraph 53002.",false);
                        for(int round=1;round<=3;round++)SelectionCase("rich-mouse-round-"+round,form,rich,controls,"Selection Rich round "+round+" token "+(52000+round),true);
                        SelectionCase("pinned-rich-update",form,rich,controls,"Pinned rich exact source 54002",true);
                        Ui(form,delegate{other.Show(form);});DelayedCases(form,other,edit,otherEdit,controls);Report["historySources"]=HistorySources();Report["historySourceSha256"]=HistorySources().ConvertAll(delegate(string s){return Hash(s);});Report["actualHotkeysSent"]=Hotkeys;Report["ok"]=true;
                    }catch(Exception e){Report["error"]=e.Message;Report["errorType"]=e.GetType().Name;if(Cases.Count>0&&!Convert.ToBoolean(Cases[Cases.Count-1]["ok"]))Cases[Cases.Count-1]["error"]=e.Message;}finally{
                        if(GetForegroundWindow()==form.Handle||GetForegroundWindow()==other.Handle||(App!=null&&ForegroundPid()==App.Id)){INPUT up=new INPUT();up.data.mouse.flags=4;SendInput(5,new INPUT[]{Key(0x12,true),Key(0x44,true),Key(0x11,true),Key(0x41,true),up},Marshal.SizeOf(typeof(INPUT)));}
                        try{KillOwn();Report["ownAppTreeStopped"]=true;}catch(Exception e){Report["ok"]=false;Report["cleanupError"]=e.Message;}Ui(form,delegate{finished=true;other.Close();form.Close();});
                    }});worker.SetApartmentState(ApartmentState.STA);worker.IsBackground=false;worker.Start();};Application.Run(form);
                }
            }
        }catch(Exception e){Report["error"]=e.Message;Report["errorType"]=e.GetType().Name;}
        finally{
            if(Seeded&&GetClipboardSequenceNumber()==OwnedClipboard)Clipboard.Clear();for(int i=owned.Count-1;i>=0;i--)try{Remove(owned[i],token);}catch(Exception e){Report["ok"]=false;Report["directoryCleanupError"]=e.Message;}Report["ownedDirectoriesRemoved"]=owned.TrueForAll(delegate(string s){return !Directory.Exists(s);});Report["executedCases"]=Cases.Count;Report["passedCases"]=Cases.FindAll(delegate(Dictionary<string,object> c){return Convert.ToBoolean(c["ok"]);}).Count;Report["requiredCases"]=16;if(App!=null)App.Dispose();
        }
        Need(Convert.ToInt32(Report["requiredCases"])==16,"FIXTURE_CASE_SPEC");if(Convert.ToInt32(Report["passedCases"])!=16)Report["ok"]=false;return Report;
    }
}
