// System32 Notepad is a distinct source process. No existing document,
// profile, user clipboard content, direct helper call or fake Tauri IPC.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

public static class WindowsSelectionNotepadFixture {
    const string Identifier="io.github.blueeeecho.echolingo", Marker=".echolingo-notepad-owned";
    const string Expected="Generated Notepad selected text 68241; punctuation: (alpha), beta!";
    const string Document="Prefix "+Expected+" suffix";
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=1048576};
    delegate bool EnumWindow(IntPtr window,IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent,EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out RECT rect);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window,out RECT rect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref POINT point);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int size);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] input,int size);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window,uint message,IntPtr wparam,IntPtr lparam,uint flags,uint timeout,out UIntPtr result);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window,uint message,IntPtr wparam,StringBuilder text,uint flags,uint timeout,out UIntPtr result);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUITHREADINFO info);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid folder,uint flags,IntPtr token,out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr value);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string path,IntPtr security);
    [StructLayout(LayoutKind.Sequential)] struct RECT {public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)] struct POINT {public int X,Y;public POINT(int x,int y){X=x;Y=y;}}
    [StructLayout(LayoutKind.Sequential)] struct GUITHREADINFO {public uint size,flags;public IntPtr active,focus,capture,menuOwner,moveSize,caret;public RECT caretRect;}
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public UNION data;}
    [StructLayout(LayoutKind.Explicit)] struct UNION {[FieldOffset(0)]public MOUSE mouse;[FieldOffset(0)]public KEY keyboard;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
    sealed class Unavailable:Exception {public Unavailable(string message):base(message){}}
    static Process App,Notepad;static IntPtr Main,Source,Editor;static uint SourceThread;
    static string History,Provider,EditorClass;static Mock Server;static uint OwnedClipboard;static DataObject Seed;static bool Seeded;
    static Dictionary<string,object> Report;
    static bool MouseDownOwned;
    static void Need(bool value,string message){if(!value)throw new InvalidOperationException(message);}
    static void Available(bool value,string message){if(!value)throw new Unavailable(message);}
    static string Class(IntPtr window){StringBuilder name=new StringBuilder(256);GetClassName(window,name,256);return name.ToString();}
    static uint Pid(IntPtr window){uint pid;GetWindowThreadProcessId(window,out pid);return pid;}
    static string Hwnd(IntPtr value){return "0x"+value.ToInt64().ToString("X");}
    static string Hash(byte[] value){using(SHA256 hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(value)).Replace("-","").ToLowerInvariant();}
    static INPUT Key(ushort value,bool up){INPUT i=new INPUT();i.type=1;i.data.keyboard.vk=value;i.data.keyboard.flags=up?2U:0U;return i;}
    static void Keys(INPUT[] values){Need(SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)))==values.Length,"SENDINPUT_REJECTED");}
    static void Wait(Func<bool> condition,int milliseconds,string reason){Stopwatch time=Stopwatch.StartNew();while(time.ElapsedMilliseconds<milliseconds){Need(App==null||!App.HasExited,"APPLICATION_EXITED");if(Server!=null&&Server.Error!=null)throw new InvalidOperationException(Server.Error);if(condition())return;Application.DoEvents();Thread.Sleep(20);}throw new InvalidOperationException("TIMEOUT:"+reason);}
    static UIntPtr Message(uint message){UIntPtr result;Need(SendMessageTimeout(Editor,message,IntPtr.Zero,IntPtr.Zero,2,1000,out result)!=IntPtr.Zero,"OWN_EDITOR_MESSAGE_TIMEOUT:"+message);return result;}
    static Dictionary<string,object> WindowMetadata(IntPtr window){
        RECT rect;bool bounds=GetWindowRect(window,out rect);uint pid;uint thread=GetWindowThreadProcessId(window,out pid);
        return new Dictionary<string,object>{{"hwnd",Hwnd(window)},{"rootHwnd",Hwnd(GetAncestor(window,2))},{"class",Class(window)},{"processId",pid},{"threadId",thread},{"visible",IsWindowVisible(window)},{"rect",bounds?(object)new int[]{rect.Left,rect.Top,rect.Right-rect.Left,rect.Bottom-rect.Top}:null}};
    }
    static Dictionary<string,object> OwnNotepadMetadata(){
        List<object> roots=new List<object>(),children=new List<object>();bool truncated=false;
        if(Notepad!=null&&!Notepad.HasExited)EnumWindows(delegate(IntPtr w,IntPtr unused){
            if(Pid(w)!=Notepad.Id)return true;
            if(roots.Count>=16){truncated=true;return false;}roots.Add(WindowMetadata(w));
            EnumChildWindows(w,delegate(IntPtr child,IntPtr ignored){if(Pid(child)!=Notepad.Id)return true;if(children.Count>=256){truncated=true;return false;}children.Add(WindowMetadata(child));return true;},IntPtr.Zero);return true;
        },IntPtr.Zero);
        return new Dictionary<string,object>{{"ownLaunchedPidOnly",true},{"rootWindows",roots},{"childWindows",children},{"metadataTruncated",truncated},{"windowTitlesRead",false},{"uiaQueries",0},{"windowTextReads",0}};
    }
    static void DiscoverEditor(){
        Report["phase"]="native-editor-discovery";
        Report["notepadInitialNativeMetadata"]=OwnNotepadMetadata();Stopwatch wait=Stopwatch.StartNew();int attempts=0,lastEditorCount=0;
        while(wait.ElapsedMilliseconds<10000){
            Available(Notepad!=null&&!Notepad.HasExited,"NOTEPAD_LAUNCHER_EXITED_DURING_NATIVE_DISCOVERY");attempts++;Source=UniqueRoot(Notepad.Id,"Notepad",true);
            if(Source!=IntPtr.Zero){List<IntPtr> editors=new List<IntPtr>();int examined=0;bool truncated=false;
                EnumChildWindows(Source,delegate(IntPtr w,IntPtr unused){if(Pid(w)!=Notepad.Id)return true;if(++examined>256){truncated=true;return false;}string kind=Class(w);if(IsWindowVisible(w)&&(String.Equals(kind,"Edit",StringComparison.OrdinalIgnoreCase)||String.Equals(kind,"RichEditD2DPT",StringComparison.OrdinalIgnoreCase)||String.Equals(kind,"RICHEDIT50W",StringComparison.OrdinalIgnoreCase)))editors.Add(w);return true;},IntPtr.Zero);
                lastEditorCount=editors.Count;if(!truncated&&editors.Count==1){Editor=editors[0];EditorClass=Class(Editor);break;}
            }
            Application.DoEvents();Thread.Sleep(20);
        }
        Report["notepadFinalNativeMetadata"]=OwnNotepadMetadata();Report["editorDiscoveryAttempts"]=attempts;Report["editorDiscoveryElapsedMilliseconds"]=wait.Elapsed.TotalMilliseconds;Report["nativeEditorCandidateCount"]=lastEditorCount;Report["nativeEditorDiscoveryBudgetMilliseconds"]=10000;Report["sourceUiaPrequeries"]=0;
        Available(Source!=IntPtr.Zero,"NOTEPAD_CLASSIC_ROOT_NOT_UNIQUE");Available(Editor!=IntPtr.Zero,"NOTEPAD_NATIVE_EDITOR_NOT_UNIQUE_OR_UNSUPPORTED_CLASS");
    }
    static POINT CharacterPosition(int index){
        // Public Edit / RichEdit2 compatibility form; no remote pointer or UIA.
        // https://learn.microsoft.com/windows/win32/controls/em-posfromchar
        SourceIdentity();UIntPtr result;Available(SendMessageTimeout(Editor,0xD6,new IntPtr(index),IntPtr.Zero,2,1000,out result)!=IntPtr.Zero,"NOTEPAD_CHARACTER_POSITION_MESSAGE_UNAVAILABLE");uint packed=unchecked((uint)result.ToUInt64());Available(packed!=UInt32.MaxValue,"NOTEPAD_CHARACTER_POSITION_UNAVAILABLE");return new POINT(unchecked((short)(packed&65535)),unchecked((short)(packed>>16)));
    }
    static void Move(POINT p){
        SourceIdentity();Need(GetForegroundWindow()==Source,"NOTEPAD_NOT_FOREGROUND_NO_MOUSE_SENT");int left=GetSystemMetrics(76),top=GetSystemMetrics(77),width=GetSystemMetrics(78),height=GetSystemMetrics(79);Need(width>1&&height>1&&p.X>=left&&p.X<left+width&&p.Y>=top&&p.Y<top+height,"OWN_EDITOR_POINT_OUTSIDE_DESKTOP");INPUT i=new INPUT();i.data.mouse.x=(int)Math.Round((p.X-left)*65535.0/(width-1));i.data.mouse.y=(int)Math.Round((p.Y-top)*65535.0/(height-1));i.data.mouse.flags=0x8000|0x4000|1;Keys(new INPUT[]{i});
    }
    static void Mouse(bool up){INPUT i=new INPUT();i.data.mouse.flags=up?4U:2U;Keys(new INPUT[]{i});MouseDownOwned=!up;}
    static void SelectGeneratedTextByMouse(){
        Report["phase"]="mouse-selection-preparation";
        const int start=7;POINT first=CharacterPosition(start),last=CharacterPosition(start+Expected.Length);RECT client;
        Available(GetClientRect(Editor,out client)&&first.Y==last.Y&&last.X>first.X,"GENERATED_NOTEPAD_TEXT_NOT_SINGLE_VISIBLE_LINE");
        first.X+=1;last.X+=String.Equals(EditorClass,"Edit",StringComparison.OrdinalIgnoreCase)?1:-1;first.Y+=6;last.Y+=6;
        Available(first.X>=client.Left&&first.X<client.Right&&last.X>=client.Left&&last.X<client.Right&&first.Y>=client.Top&&first.Y<client.Bottom,"GENERATED_NOTEPAD_CHARACTER_POINTS_OUTSIDE_EDITOR");
        Need(ClientToScreen(Editor,ref first)&&ClientToScreen(Editor,ref last),"OWN_EDITOR_COORDINATE_CONVERSION_FAILED");Need(WindowFromPoint(first)==Editor&&WindowFromPoint(last)==Editor,"OWN_EDITOR_MOUSE_POINT_OCCLUDED");
        Report["mouseStartPhysicalXY"]=new int[]{first.X,first.Y};Report["mouseEndPhysicalXY"]=new int[]{last.X,last.Y};Report["sourceMousePositionMessage"]="EM_POSFROMCHAR-0xD6-Edit-RichEdit2-compatibility";
        Move(first);SourceIdentity();Need(GetForegroundWindow()==Source&&WindowFromPoint(first)==Editor,"OWN_EDITOR_NOT_CURRENT_NO_MOUSE_DOWN");Mouse(false);Report["actualMouseDownsSent"]=1;
        for(int step=1;step<=8;step++){Move(new POINT(first.X+(last.X-first.X)*step/8,first.Y));Thread.Sleep(12);}
        SourceIdentity();Need(GetForegroundWindow()==Source&&WindowFromPoint(last)==Editor,"OWN_EDITOR_NOT_CURRENT_NO_MOUSE_UP");Mouse(true);Report["actualMouseUpsSent"]=1;
        Wait(delegate{SourceFocus();uint selection=checked((uint)Message(0xB0).ToUInt64());Report["actualSelectionStart"]=(int)(selection&65535);Report["actualSelectionEnd"]=(int)(selection>>16);return (selection&65535)==start&&(selection>>16)==start+Expected.Length;},2000,"ACTUAL_NOTEPAD_MOUSE_SELECTION_NOT_EXACT");Report["mouseReleasedBeforeHotkey"]=true;
    }
    static string EditorText(){int length=checked((int)Message(0xE).ToUInt64());Need(length>=0&&length<=4096,"OWN_EDITOR_TEXT_LENGTH");StringBuilder value=new StringBuilder(length+1);UIntPtr result;Need(SendMessageTimeout(Editor,0xD,new IntPtr(value.Capacity),value,2,1000,out result)!=IntPtr.Zero,"OWN_EDITOR_TEXT_TIMEOUT");Need(result.ToUInt64()==(ulong)length,"OWN_EDITOR_TEXT_CHANGED_DURING_READ");return value.ToString();}
    static void SourceIdentity(){uint pid;uint thread=GetWindowThreadProcessId(Source,out pid);Need(Notepad!=null&&!Notepad.HasExited&&IsWindow(Source)&&IsWindowVisible(Source)&&GetAncestor(Source,2)==Source&&pid==Notepad.Id&&thread==SourceThread&&Class(Source)=="Notepad","NOTEPAD_ROOT_IDENTITY_CHANGED");Need(IsWindow(Editor)&&IsWindowVisible(Editor)&&Pid(Editor)==Notepad.Id&&GetAncestor(Editor,2)==Source&&Class(Editor)==EditorClass,"NOTEPAD_EDITOR_IDENTITY_CHANGED");}
    static void SourceFocus(){SourceIdentity();Need(GetForegroundWindow()==Source,"NOTEPAD_NOT_FOREGROUND_NO_INPUT_SENT");GUITHREADINFO info=new GUITHREADINFO();info.size=(uint)Marshal.SizeOf(typeof(GUITHREADINFO));Need(GetGUIThreadInfo(SourceThread,ref info)&&info.focus==Editor,"NOTEPAD_EDITOR_NOT_FOCUSED_NO_INPUT_SENT");}
    static IntPtr UniqueRoot(int pid,string kind,bool visible){List<IntPtr> roots=new List<IntPtr>();EnumWindows(delegate(IntPtr w,IntPtr unused){if(Pid(w)==pid&&GetAncestor(w,2)==w&&Class(w)==kind&&(!visible||IsWindowVisible(w)))roots.Add(w);return true;},IntPtr.Zero);return roots.Count==1?roots[0]:IntPtr.Zero;}
    static Dictionary<string,object> NativeReady(){int hotkeys=0,trays=0;EnumWindows(delegate(IntPtr w,IntPtr unused){if(Pid(w)==App.Id){string kind=Class(w);if(kind=="global_hotkey_app")hotkeys++;if(kind=="tray_icon_app")trays++;}return true;},IntPtr.Zero);return new Dictionary<string,object>{{"globalHotkeyWindowCount",hotkeys},{"trayWindowCount",trays},{"osHotkeyRegistrationProven",false},{"fixedFrontendWarmupMilliseconds",0}};}
    static string AppSource(){Task<string> query=Task.Factory.StartNew(delegate{
        Need(Thread.CurrentThread.GetApartmentState()==ApartmentState.MTA,"TAURI_UIA_NOT_MTA");uint pid;GetWindowThreadProcessId(Main,out pid);Need(pid==App.Id&&Class(Main)=="Tauri Window","TAURI_ROOT_IDENTITY_CHANGED");
        AutomationElement root=AutomationElement.FromHandle(Main);AutomationElement e=root.FindFirst(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));
        object pattern;return e!=null&&!e.Current.IsOffscreen&&e.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)?((ValuePattern)pattern).Current.Value:null;
    },CancellationToken.None,TaskCreationOptions.None,TaskScheduler.Default);Stopwatch time=Stopwatch.StartNew();while(!query.IsCompleted&&time.ElapsedMilliseconds<2000){Application.DoEvents();Thread.Sleep(2);}Need(query.IsCompleted,"TAURI_UIA_VALUE_TIMEOUT");if(query.IsFaulted)throw query.Exception.InnerException;return query.Result;}
    static bool HistoryExact(){if(!File.Exists(History))return false;object[] rows;try{rows=Json.Deserialize<object[]>(File.ReadAllText(History));}catch(IOException){return false;}catch(ArgumentException){return false;}if(rows.Length!=1)return false;Dictionary<string,object> row=rows[0] as Dictionary<string,object>;if(row==null||(string)row["text"]!=Expected)return false;int exact=0;foreach(object raw in (IEnumerable)row["results"]){Dictionary<string,object> result=raw as Dictionary<string,object>;if(result!=null&&(string)result["providerId"]==Provider&&!result.ContainsKey("error")&&(string)result["text"]==Mock.Result)exact++;}return exact==1;}
    static void SeedClipboard(){Seed=new DataObject();Seed.SetData(DataFormats.UnicodeText,false,"Generated Notepad clipboard original 86420");Seed.SetData(DataFormats.Html,false,"<p>Generated Notepad clipboard original 86420</p>");Seed.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated Notepad clipboard original 86420}");Clipboard.SetDataObject(Seed,true,0,0);OwnedClipboard=GetClipboardSequenceNumber();Seeded=true;}
    static void CheckClipboard(){IDataObject actual=Clipboard.GetDataObject();Need(actual!=null,"ORIGINAL_CLIPBOARD_MISSING");foreach(string f in Seed.GetFormats(false))Need(Object.Equals(Seed.GetData(f,false),actual.GetData(f,false)),"ORIGINAL_RICH_CLIPBOARD_NOT_RESTORED");OwnedClipboard=GetClipboardSequenceNumber();}
    static string KnownFolder(string id){Guid folder=new Guid(id);IntPtr p;Need(SHGetKnownFolderPath(ref folder,0,IntPtr.Zero,out p)==0,"KNOWN_FOLDER_FAILED");try{return Marshal.PtrToStringUni(p);}finally{CoTaskMemFree(p);}}
    static void Claim(string path,string token,List<string> owned){Need(CreateDirectory(path,IntPtr.Zero),"EXISTING_DIRECTORY_REFUSED");File.WriteAllText(Path.Combine(path,Marker),token,new UTF8Encoding(false));owned.Add(path);}
    static void NoLinks(string path){Need((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"REPARSE_POINT_PRESERVED");foreach(string child in Directory.GetDirectories(path))NoLinks(child);foreach(string child in Directory.GetFiles(path))Need((File.GetAttributes(child)&FileAttributes.ReparsePoint)==0,"REPARSE_FILE_PRESERVED");}
    static void Remove(string path,string token){if(!Directory.Exists(path))return;Need(File.ReadAllText(Path.Combine(path,Marker))==token,"OWNERSHIP_MARKER_CHANGED");NoLinks(path);for(int i=0;;i++){try{Directory.Delete(path,true);return;}catch(IOException){if(i>=19)throw;}catch(UnauthorizedAccessException){if(i>=19)throw;}Application.DoEvents();Thread.Sleep(100);}}
    static void StopApp(){if(App==null||App.HasExited)return;ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.SystemDirectory,"taskkill.exe"),"/PID "+App.Id+" /T /F");start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;using(Process kill=Process.Start(start)){kill.StandardOutput.ReadToEnd();kill.StandardError.ReadToEnd();Need(kill.WaitForExit(10000),"OWN_APP_TREE_KILL_TIMEOUT");}Need(App.WaitForExit(5000),"OWN_APP_REMAINED");}
    static void StopNotepad(){if(Notepad==null||Notepad.HasExited)return;Notepad.Kill();Need(Notepad.WaitForExit(5000),"OWN_NOTEPAD_REMAINED");}
    sealed class Mock:IDisposable {
        public const string Result="GENERATED_NOTEPAD_TRANSLATION_68241";
        readonly TcpListener listener=new TcpListener(IPAddress.Loopback,0);readonly Thread thread;readonly object clientGate=new object();readonly ManualResetEvent stopEvent=new ManualResetEvent(false),acceptsDrained=new ManualResetEvent(true);TcpClient activeClient;volatile bool stop;public volatile string Error,CleanupError;int count,disposed,pendingAccepts;volatile int phase,phaseAtStop,disposePhase,threadStateAtStop,threadStateAfter;long cleanupMilliseconds;
        sealed class PendingAccept {
            readonly Mock host;readonly object gate=new object();IAsyncResult operation;WaitHandle wait;bool abandoned,claimed;
            public PendingAccept(Mock value){host=value;Interlocked.Increment(ref host.pendingAccepts);host.acceptsDrained.Reset();try{operation=host.listener.BeginAcceptTcpClient(Completed,null);wait=operation.AsyncWaitHandle;}catch{if(operation==null)Release();else Abandon();throw;}}
            public WaitHandle Handle {get{return wait;}}
            void Completed(IAsyncResult result){bool take;lock(gate){take=abandoned&&!claimed;if(take)claimed=true;}if(take)Discard(result);}
            void Release(){if(wait!=null)wait.Close();if(Interlocked.Decrement(ref host.pendingAccepts)==0)host.acceptsDrained.Set();}
            void Discard(IAsyncResult result){try{Need(result.IsCompleted,"MOCK_ACCEPT_NOT_COMPLETED");using(TcpClient client=host.listener.EndAcceptTcpClient(result)){} }catch(SocketException){if(!host.stop)host.Error="MOCK_ACCEPT_SOCKET_ERROR";}catch(ObjectDisposedException){if(!host.stop)host.Error="MOCK_ACCEPT_DISPOSED";}catch(Exception e){host.CleanupError="MOCK_ACCEPT_CLEANUP:"+e.GetType().Name;}finally{Release();}}
            public TcpClient Take(){lock(gate){Need(!claimed&&operation.IsCompleted,"MOCK_ACCEPT_NOT_READY_OR_ALREADY_CLAIMED");claimed=true;}try{return host.listener.EndAcceptTcpClient(operation);}finally{Release();}}
            public void Abandon(){bool take;lock(gate){abandoned=true;take=!claimed&&operation.IsCompleted;if(take)claimed=true;}if(take)Discard(operation);}
        }
        public Mock(){listener.Start();thread=new Thread(Loop);thread.IsBackground=true;if(Environment.OSVersion.Platform==PlatformID.Win32NT)thread.SetApartmentState(ApartmentState.MTA);thread.Start();}
        public string Url {get{return "http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port;}}
        public int Count {get{return Interlocked.CompareExchange(ref count,0,0);}}
        void Loop(){try{while(!stop){try{phase=1;PendingAccept accept=new PendingAccept(this);TcpClient next=null;try{if(WaitHandle.WaitAny(new WaitHandle[]{accept.Handle,stopEvent})==1||stop)return;next=accept.Take();}finally{accept.Abandon();}using(TcpClient client=next){phase=2;
            lock(clientGate){if(stop)return;activeClient=client;}try{
            client.ReceiveTimeout=5000;client.SendTimeout=5000;NetworkStream stream=client.GetStream();List<byte> headers=new List<byte>();bool complete=false;phase=3;while(headers.Count<16384){int b=stream.ReadByte();Need(b>=0,"MOCK_TRUNCATED_HEADERS");headers.Add((byte)b);int n=headers.Count;if(n>=4&&headers[n-4]==13&&headers[n-3]==10&&headers[n-2]==13&&headers[n-1]==10){complete=true;break;}}Need(complete,"MOCK_HEADER_BOUND");string head=Encoding.ASCII.GetString(headers.ToArray());Need(head.StartsWith("POST /translate HTTP/1.1\r\n",StringComparison.Ordinal),"MOCK_ROUTE");int length=-1;foreach(string line in head.Split(new string[]{"\r\n"},StringSplitOptions.None)){Need(!line.StartsWith("Authorization:",StringComparison.OrdinalIgnoreCase),"MOCK_CREDENTIAL_FORBIDDEN");if(line.StartsWith("Content-Length:",StringComparison.OrdinalIgnoreCase))length=Int32.Parse(line.Substring(15).Trim());}Need(length>=0&&length<=65536,"MOCK_BODY_BOUND");byte[] bytes=new byte[length];int offset=0;phase=4;while(offset<length){int n=stream.Read(bytes,offset,length-offset);Need(n>0,"MOCK_TRUNCATED_BODY");offset+=n;}Dictionary<string,object> body=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));Need((string)body["q"]==Expected&&(string)body["target"]=="zh","NON_GENERATED_REQUEST_REJECTED");Need(!body.ContainsKey("api_key")||String.IsNullOrEmpty(body["api_key"] as string),"MOCK_KEY_FORBIDDEN");Interlocked.Increment(ref count);byte[] reply=Encoding.UTF8.GetBytes("{\"translatedText\":\""+Result+"\"}");byte[] prefix=Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+reply.Length+"\r\n\r\n");phase=5;stream.Write(prefix,0,prefix.Length);stream.Write(reply,0,reply.Length);stream.Flush();
            }finally{lock(clientGate){if(Object.ReferenceEquals(activeClient,client))activeClient=null;}}
        }}catch(Exception e){if(!stop)Error="MOCK_FAILURE:"+e.GetType().Name+":"+e.Message;}}}finally{phase=8;}}
        public Dictionary<string,object> CleanupDiagnostics {get{return new Dictionary<string,object>{{"phaseAtStop",phaseAtStop},{"phaseAfterStop",phase},{"disposePhase",disposePhase},{"threadStateAtStop",threadStateAtStop},{"threadStateAfterStop",threadStateAfter},{"cleanupMilliseconds",cleanupMilliseconds},{"pendingAccepts",Interlocked.CompareExchange(ref pendingAccepts,0,0)}};}}
        public void Dispose(){if(Interlocked.Exchange(ref disposed,1)!=0)return;Stopwatch elapsed=Stopwatch.StartNew();phaseAtStop=phase;threadStateAtStop=(int)thread.ThreadState;stop=true;disposePhase=1;stopEvent.Set();try{disposePhase=2;listener.Stop();}catch(Exception e){CleanupError="MOCK_STOP:"+e.GetType().Name;}
            TcpClient current;lock(clientGate){current=activeClient;}try{disposePhase=3;if(current!=null)current.Close();}catch(Exception e){if(CleanupError==null)CleanupError="MOCK_CLIENT_STOP:"+e.GetType().Name;}
            bool joined=false,drained=false;try{disposePhase=4;joined=thread.Join((int)Math.Max(0,6000-elapsed.ElapsedMilliseconds));if(!joined)CleanupError="MOCK_THREAD_NOT_STOPPED";disposePhase=5;drained=acceptsDrained.WaitOne((int)Math.Max(0,6000-elapsed.ElapsedMilliseconds));if(!drained&&CleanupError==null)CleanupError="MOCK_ACCEPT_CLEANUP_PENDING";}catch(Exception e){if(CleanupError==null)CleanupError="MOCK_JOIN:"+e.GetType().Name;}
            threadStateAfter=(int)thread.ThreadState;cleanupMilliseconds=elapsed.ElapsedMilliseconds;disposePhase=CleanupError==null?6:7;if(joined&&drained){stopEvent.Close();acceptsDrained.Close();}/* Preserve an in-flight primary exception. */}
    }
    public static Dictionary<string,object> Run(string executable){
        Report=new Dictionary<string,object>{{"ok",false},{"inconclusive",false},{"requiredCases",1},{"executedCases",0},{"passedCases",0},{"actualApplicationTested",false},{"actualNotepadTested",false},{"actualHotkeysSent",0},{"actualMouseDownsSent",0},{"actualMouseUpsSent",0},{"sourceUiaPrequeries",0},{"sameActionRetries",0},{"sourceProcessIndependent",false},{"fakeIpcUsed",false},{"directHelperInvoked",false},{"translationBackend","loopback-mock"},{"userContentRead",false},{"browserTested",false},{"physicalWindows11Tested",false},{"credentialsCreated",false},{"selectionMethod","actual-SendInput-left-drag-release"},{"notepadScope","Owned System32 Notepad PID; fixed native editor class allowlist; unknown classes and Store/launcher PID transfer are inconclusive"}};
        IntPtr previousDpi=IntPtr.Zero;
        string token=Guid.NewGuid().ToString("N"),root=Path.Combine(Path.GetTempPath(),"echolingo-notepad-"+token),roaming=Path.Combine(KnownFolder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"),Identifier),local=Path.Combine(KnownFolder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"),Identifier);List<string> owned=new List<string>();
        try {
            try{previousDpi=SetThreadDpiAwarenessContext(new IntPtr(-4));}catch(EntryPointNotFoundException){}Report["perMonitorThreadDpiContextSet"]=previousDpi!=IntPtr.Zero;Available(previousDpi!=IntPtr.Zero,"NOTEPAD_PHYSICAL_COORDINATE_CONTEXT_UNAVAILABLE");
            string notepadPath=Path.Combine(Environment.SystemDirectory,"notepad.exe");Available(File.Exists(notepadPath),"NOTEPAD_UNAVAILABLE");Report["notepadFileVersion"]=FileVersionInfo.GetVersionInfo(notepadPath).FileVersion;
            foreach(Process p in Process.GetProcessesByName("notepad"))using(p)Available(p.HasExited,"EXISTING_NOTEPAD_REFUSED");foreach(Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))using(p)Need(p.HasExited,"EXISTING_APPLICATION_REFUSED");
            IDataObject old=Clipboard.GetDataObject();Need(old==null||old.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");Claim(roaming,token,owned);Claim(local,token,owned);Claim(root,token,owned);History=Path.Combine(roaming,"history.json");Provider="generated-notepad-"+token;
            string document=Path.Combine(root,"generated-selection.txt");File.WriteAllText(document,Document,new UTF8Encoding(true));string originalHash=Hash(File.ReadAllBytes(document));Report["generatedDocumentSha256"]=originalHash;
            using(Server=new Mock()){
                Dictionary<string,object> settings=new Dictionary<string,object>{{"providers",new object[]{new Dictionary<string,object>{{"id",Provider},{"name","Generated Notepad loopback mock"},{"kind","libretranslate"},{"baseUrl",Server.Url},{"enabled",true},{"model",""},{"prompt",""}}}},{"ocrProviders",new object[0]},{"sourceLanguage","auto"},{"targetLanguage","auto"},{"languageDirectionVersion",1},{"shortcutDefaultsVersion",1},{"saveHistory",true},{"maxHistory",20},{"theme","light"},{"autoHideSeconds",0},{"shortcuts",new Dictionary<string,object>{{"selection","Alt+D"},{"silentOcr","Alt+S"},{"ocr",""},{"capture",""},{"input",""}}}};
                File.WriteAllText(Path.Combine(roaming,"settings.json"),Json.Serialize(settings),new UTF8Encoding(false));
                ProcessStartInfo start=new ProcessStartInfo(executable);start.UseShellExecute=false;start.CreateNoWindow=true;string childLocal=Path.Combine(root,"Local"),childTemp=Path.Combine(root,"Temp");Directory.CreateDirectory(childLocal);Directory.CreateDirectory(childTemp);start.EnvironmentVariables["LOCALAPPDATA"]=childLocal;start.EnvironmentVariables["TEMP"]=childTemp;start.EnvironmentVariables["TMP"]=childTemp;start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"]=Path.Combine(local,"webview-notepad-fixture");App=Process.Start(start);Report["applicationProcessId"]=App.Id;Report["actualApplicationTested"]=true;Need(App.WaitForInputIdle(15000),"APP_INPUT_IDLE");Wait(delegate{return (Main=UniqueRoot(App.Id,"Tauri Window",false))!=IntPtr.Zero;},20000,"UNIQUE_ACTUAL_TAURI_WINDOW");Dictionary<string,object> ready=null;Wait(delegate{ready=NativeReady();return Convert.ToInt32(ready["globalHotkeyWindowCount"])>0&&Convert.ToInt32(ready["trayWindowCount"])>0;},15000,"NATIVE_REGISTRATION_HOST_AND_TRAY");Report["beforeFirstHotkeyReadiness"]=ready;
                ProcessStartInfo sourceStart=new ProcessStartInfo(notepadPath,"\""+document+"\"");sourceStart.UseShellExecute=false;Notepad=Process.Start(sourceStart);Report["notepadLaunchedProcessId"]=Notepad.Id;
                bool idle=false;try{idle=Notepad.WaitForInputIdle(10000);}catch(InvalidOperationException){}Available(!Notepad.HasExited&&idle,"NOTEPAD_LAUNCHER_EXITED_OR_INPUT_IDLE_UNAVAILABLE");string launchedImage=null;try{launchedImage=Notepad.MainModule.FileName;}catch(System.ComponentModel.Win32Exception){throw new Unavailable("NOTEPAD_EXECUTABLE_IDENTITY_INACCESSIBLE");}catch(InvalidOperationException){throw new Unavailable("NOTEPAD_LAUNCHER_EXITED_DURING_IDENTITY_CHECK");}Available(String.Equals(Path.GetFullPath(launchedImage),Path.GetFullPath(notepadPath),StringComparison.OrdinalIgnoreCase),"NOTEPAD_EXECUTABLE_IDENTITY_UNVERIFIED");
                DiscoverEditor();uint sourcePid;SourceThread=GetWindowThreadProcessId(Source,out sourcePid);Need(sourcePid!=App.Id&&sourcePid!=Process.GetCurrentProcess().Id,"SOURCE_NOT_INDEPENDENT_PROCESS");Report["sourceProcessIndependent"]=true;Report["notepadRootHwnd"]=Hwnd(Source);Report["notepadEditorHwnd"]=Hwnd(Editor);Report["notepadEditorClass"]=EditorClass;Report["notepadSourceProcessId"]=sourcePid;Report["notepadSourceThreadId"]=SourceThread;
                SetForegroundWindow(Source);Wait(delegate{return GetForegroundWindow()==Source;},2000,"OWN_NOTEPAD_FOREGROUND");Report["phase"]="generated-document-verification";SourceIdentity();Need(EditorText()==Document,"GENERATED_NOTEPAD_CONTENT_NOT_EXACT");Need(Message(0xB8).ToUInt64()==0,"GENERATED_NOTEPAD_DOCUMENT_ALREADY_MODIFIED");SelectGeneratedTextByMouse();
                Report["actualNotepadTested"]=true;Report["expectedSourceSha256"]=Hash(Encoding.UTF8.GetBytes(Expected));SeedClipboard();SourceFocus();Report["phase"]="single-altd-application-acquisition";Report["executedCases"]=1;Stopwatch capture=Stopwatch.StartNew();Keys(new INPUT[]{Key(0x12,false),Key(0x44,false),Key(0x44,true),Key(0x12,true)});Report["actualHotkeysSent"]=1;
                Wait(delegate{return Server.Count==1&&HistoryExact()&&AppSource()==Expected;},30000,"SINGLE_ALTD_EXACT_NOTEPAD_SOURCE_AND_HISTORY");Report["hotkeyToHistoryMilliseconds"]=capture.Elapsed.TotalMilliseconds;SourceFocus();Need(EditorText()==Document,"SOURCE_DOCUMENT_CHANGED");Need(Message(0xB8).ToUInt64()==0,"SOURCE_DOCUMENT_MODIFIED_DURING_ACQUISITION");Need(Hash(File.ReadAllBytes(document))==originalHash,"GENERATED_DOCUMENT_FILE_CHANGED");Need(Server.Count==1,"DUPLICATE_TRANSLATION_FOR_ONE_ALTD");CheckClipboard();Report["sourceForegroundPreserved"]=true;Report["sourceEditorUnchangedAndUnmodified"]=true;Report["generatedDocumentFileUnchanged"]=true;Report["richClipboardRestored"]=true;Report["historyExactSourceVerified"]=true;Report["mockRequestCount"]=Server.Count;Report["passedCases"]=1;Report["ok"]=true;
            }
        } catch(Unavailable e){Report["inconclusive"]=true;Report["error"]=e.Message;}catch(Exception e){Report["error"]=e.Message;Report["errorType"]=e.GetType().Name;}
        finally {
            Report["productHotkeyExercised"]=Convert.ToInt32(Report["actualHotkeysSent"])>0;Report["preparationFailedBeforeProductHotkey"]=!Convert.ToBoolean(Report["ok"])&&!Convert.ToBoolean(Report["productHotkeyExercised"]);
            if(Server!=null&&Server.CleanupError!=null){Report["ok"]=false;Report["mockCleanupError"]=Server.CleanupError;}
            if(Server!=null)Report["mockCleanupDiagnostics"]=Server.CleanupDiagnostics;
            // Release only keys emitted by this fixture, while one of its two
            // known windows still owns the foreground. Never touch another app.
            IntPtr foreground=GetForegroundWindow();if(foreground==Source||(Main!=IntPtr.Zero&&foreground==Main)){SendInput(2,new INPUT[]{Key(0x12,true),Key(0x44,true)},Marshal.SizeOf(typeof(INPUT)));if(MouseDownOwned){INPUT up=new INPUT();up.data.mouse.flags=4;SendInput(1,new INPUT[]{up},Marshal.SizeOf(typeof(INPUT)));MouseDownOwned=false;}}
            try{StopApp();Report["ownAppTreeStopped"]=true;}catch(Exception e){Report["ok"]=false;Report["cleanupError"]=e.Message;}
            try{StopNotepad();Report["ownLaunchedNotepadStopped"]=Notepad==null||Notepad.HasExited;Report["storeRetargetedProcessFollowed"]=false;}catch(Exception e){Report["ok"]=false;Report["notepadCleanupError"]=e.Message;}
            if(Seeded){if(GetClipboardSequenceNumber()==OwnedClipboard){Clipboard.Clear();Report["ownedClipboardCleared"]=true;}else{Report["ownedClipboardCleared"]=false;Report["ok"]=false;Report["clipboardCleanupError"]="CLIPBOARD_GENERATION_CHANGED_PRESERVED";}}
            for(int i=owned.Count-1;i>=0;i--)try{Remove(owned[i],token);}catch(Exception e){Report["ok"]=false;Report["directoryCleanupError"]=e.Message;}Report["ownedDirectoriesRemoved"]=owned.TrueForAll(delegate(string s){return !Directory.Exists(s);});if(App!=null)App.Dispose();if(Notepad!=null)Notepad.Dispose();
            if(previousDpi!=IntPtr.Zero)try{SetThreadDpiAwarenessContext(previousDpi);}catch(EntryPointNotFoundException){}
        }
        return Report;
    }
}
