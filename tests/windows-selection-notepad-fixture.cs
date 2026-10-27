// Classic system Notepad is a distinct source process. No existing document,
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
    [StructLayout(LayoutKind.Sequential)] struct GUITHREADINFO {public uint size,flags;public IntPtr active,focus,capture,menuOwner,moveSize,caret;public RECT caretRect;}
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public UNION data;}
    [StructLayout(LayoutKind.Explicit)] struct UNION {[FieldOffset(0)]public MOUSE mouse;[FieldOffset(0)]public KEY keyboard;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
    sealed class Unavailable:Exception {public Unavailable(string message):base(message){}}
    static Process App,Notepad;static IntPtr Main,Source,Editor;static uint SourceThread;
    static string History,Provider,EditorClass;static Mock Server;static uint OwnedClipboard;static DataObject Seed;static bool Seeded;
    static Dictionary<string,object> Report;
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
        readonly TcpListener listener=new TcpListener(IPAddress.Loopback,0);readonly Thread thread;volatile bool stop;public volatile string Error;int count;
        public Mock(){listener.Start();thread=new Thread(Loop);thread.IsBackground=true;thread.Start();}
        public string Url {get{return "http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port;}}
        public int Count {get{return Interlocked.CompareExchange(ref count,0,0);}}
        void Loop(){while(!stop){try{using(TcpClient client=listener.AcceptTcpClient()){
            client.ReceiveTimeout=5000;client.SendTimeout=5000;NetworkStream stream=client.GetStream();List<byte> headers=new List<byte>();bool complete=false;while(headers.Count<16384){int b=stream.ReadByte();Need(b>=0,"MOCK_TRUNCATED_HEADERS");headers.Add((byte)b);int n=headers.Count;if(n>=4&&headers[n-4]==13&&headers[n-3]==10&&headers[n-2]==13&&headers[n-1]==10){complete=true;break;}}Need(complete,"MOCK_HEADER_BOUND");string head=Encoding.ASCII.GetString(headers.ToArray());Need(head.StartsWith("POST /translate HTTP/1.1\r\n",StringComparison.Ordinal),"MOCK_ROUTE");int length=-1;foreach(string line in head.Split(new string[]{"\r\n"},StringSplitOptions.None)){Need(!line.StartsWith("Authorization:",StringComparison.OrdinalIgnoreCase),"MOCK_CREDENTIAL_FORBIDDEN");if(line.StartsWith("Content-Length:",StringComparison.OrdinalIgnoreCase))length=Int32.Parse(line.Substring(15).Trim());}Need(length>=0&&length<=65536,"MOCK_BODY_BOUND");byte[] bytes=new byte[length];int offset=0;while(offset<length){int n=stream.Read(bytes,offset,length-offset);Need(n>0,"MOCK_TRUNCATED_BODY");offset+=n;}Dictionary<string,object> body=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));Need((string)body["q"]==Expected&&(string)body["target"]=="zh","NON_GENERATED_REQUEST_REJECTED");Need(!body.ContainsKey("api_key")||String.IsNullOrEmpty(body["api_key"] as string),"MOCK_KEY_FORBIDDEN");Interlocked.Increment(ref count);byte[] reply=Encoding.UTF8.GetBytes("{\"translatedText\":\""+Result+"\"}");byte[] prefix=Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+reply.Length+"\r\n\r\n");stream.Write(prefix,0,prefix.Length);stream.Write(reply,0,reply.Length);stream.Flush();
        }}catch(Exception e){if(!stop)Error="MOCK_FAILURE:"+e.GetType().Name+":"+e.Message;}}}
        public void Dispose(){stop=true;listener.Stop();Need(thread.Join(6000),"MOCK_THREAD_NOT_STOPPED");}
    }
    public static Dictionary<string,object> Run(string executable){
        Report=new Dictionary<string,object>{{"ok",false},{"inconclusive",false},{"requiredCases",1},{"executedCases",0},{"passedCases",0},{"actualApplicationTested",false},{"actualNotepadTested",false},{"actualHotkeysSent",0},{"sameActionRetries",0},{"sourceProcessIndependent",false},{"fakeIpcUsed",false},{"directHelperInvoked",false},{"translationBackend","loopback-mock"},{"userContentRead",false},{"browserTested",false},{"physicalWindows11Tested",false},{"credentialsCreated",false},{"selectionMethod","actual-SendInput-Ctrl+A"},{"notepadScope","Classic System32 Notepad only; Store/launcher PID transfer is inconclusive"}};
        string token=Guid.NewGuid().ToString("N"),root=Path.Combine(Path.GetTempPath(),"echolingo-notepad-"+token),roaming=Path.Combine(KnownFolder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"),Identifier),local=Path.Combine(KnownFolder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"),Identifier);List<string> owned=new List<string>();
        try {
            string notepadPath=Path.Combine(Environment.SystemDirectory,"notepad.exe");Available(File.Exists(notepadPath),"NOTEPAD_UNAVAILABLE");Report["notepadFileVersion"]=FileVersionInfo.GetVersionInfo(notepadPath).FileVersion;
            foreach(Process p in Process.GetProcessesByName("notepad"))using(p)Available(p.HasExited,"EXISTING_NOTEPAD_REFUSED");foreach(Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))using(p)Need(p.HasExited,"EXISTING_APPLICATION_REFUSED");
            IDataObject old=Clipboard.GetDataObject();Need(old==null||old.GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");Claim(roaming,token,owned);Claim(local,token,owned);Claim(root,token,owned);History=Path.Combine(roaming,"history.json");Provider="generated-notepad-"+token;
            string document=Path.Combine(root,"generated-selection.txt");File.WriteAllText(document,Expected,new UTF8Encoding(true));string originalHash=Hash(File.ReadAllBytes(document));Report["generatedDocumentSha256"]=originalHash;
            using(Server=new Mock()){
                Dictionary<string,object> settings=new Dictionary<string,object>{{"providers",new object[]{new Dictionary<string,object>{{"id",Provider},{"name","Generated Notepad loopback mock"},{"kind","libretranslate"},{"baseUrl",Server.Url},{"enabled",true},{"model",""},{"prompt",""}}}},{"ocrProviders",new object[0]},{"sourceLanguage","auto"},{"targetLanguage","auto"},{"languageDirectionVersion",1},{"shortcutDefaultsVersion",1},{"saveHistory",true},{"maxHistory",20},{"theme","light"},{"autoHideSeconds",0},{"shortcuts",new Dictionary<string,object>{{"selection","Alt+D"},{"silentOcr","Alt+S"},{"ocr",""},{"capture",""},{"input",""}}}};
                File.WriteAllText(Path.Combine(roaming,"settings.json"),Json.Serialize(settings),new UTF8Encoding(false));
                ProcessStartInfo start=new ProcessStartInfo(executable);start.UseShellExecute=false;start.CreateNoWindow=true;string childLocal=Path.Combine(root,"Local"),childTemp=Path.Combine(root,"Temp");Directory.CreateDirectory(childLocal);Directory.CreateDirectory(childTemp);start.EnvironmentVariables["LOCALAPPDATA"]=childLocal;start.EnvironmentVariables["TEMP"]=childTemp;start.EnvironmentVariables["TMP"]=childTemp;start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"]=Path.Combine(local,"webview-notepad-fixture");App=Process.Start(start);Report["applicationProcessId"]=App.Id;Report["actualApplicationTested"]=true;Need(App.WaitForInputIdle(15000),"APP_INPUT_IDLE");Wait(delegate{return (Main=UniqueRoot(App.Id,"Tauri Window",false))!=IntPtr.Zero;},20000,"UNIQUE_ACTUAL_TAURI_WINDOW");Dictionary<string,object> ready=null;Wait(delegate{ready=NativeReady();return Convert.ToInt32(ready["globalHotkeyWindowCount"])>0&&Convert.ToInt32(ready["trayWindowCount"])>0;},15000,"NATIVE_REGISTRATION_HOST_AND_TRAY");Report["beforeFirstHotkeyReadiness"]=ready;
                ProcessStartInfo sourceStart=new ProcessStartInfo(notepadPath,"\""+document+"\"");sourceStart.UseShellExecute=false;Notepad=Process.Start(sourceStart);Report["notepadLaunchedProcessId"]=Notepad.Id;
                bool idle=false;try{idle=Notepad.WaitForInputIdle(10000);}catch(InvalidOperationException){}Available(!Notepad.HasExited&&idle,"NOTEPAD_LAUNCHER_EXITED_OR_INPUT_IDLE_UNAVAILABLE");string launchedImage=null;try{launchedImage=Notepad.MainModule.FileName;}catch(System.ComponentModel.Win32Exception){throw new Unavailable("NOTEPAD_EXECUTABLE_IDENTITY_INACCESSIBLE");}catch(InvalidOperationException){throw new Unavailable("NOTEPAD_LAUNCHER_EXITED_DURING_IDENTITY_CHECK");}Available(String.Equals(Path.GetFullPath(launchedImage),Path.GetFullPath(notepadPath),StringComparison.OrdinalIgnoreCase),"NOTEPAD_EXECUTABLE_IDENTITY_UNVERIFIED");
                Source=UniqueRoot(Notepad.Id,"Notepad",true);Available(Source!=IntPtr.Zero,"NOTEPAD_CLASSIC_ROOT_NOT_UNIQUE");List<IntPtr> editors=new List<IntPtr>();EnumChildWindows(Source,delegate(IntPtr w,IntPtr unused){string kind=Class(w);if(Pid(w)==Notepad.Id&&IsWindowVisible(w)&&(kind=="Edit"||kind=="RichEditD2DPT"||kind=="RICHEDIT50W"))editors.Add(w);return true;},IntPtr.Zero);Available(editors.Count==1,"NOTEPAD_CLASSIC_EDITOR_NOT_UNIQUE");Editor=editors[0];EditorClass=Class(Editor);uint sourcePid;SourceThread=GetWindowThreadProcessId(Source,out sourcePid);Need(sourcePid!=App.Id&&sourcePid!=Process.GetCurrentProcess().Id,"SOURCE_NOT_INDEPENDENT_PROCESS");Report["sourceProcessIndependent"]=true;Report["notepadRootHwnd"]=Hwnd(Source);Report["notepadEditorHwnd"]=Hwnd(Editor);Report["notepadEditorClass"]=EditorClass;Report["notepadSourceProcessId"]=sourcePid;Report["notepadSourceThreadId"]=SourceThread;
                SetForegroundWindow(Source);Wait(delegate{return GetForegroundWindow()==Source;},2000,"OWN_NOTEPAD_FOREGROUND");SourceFocus();Need(EditorText()==Expected,"GENERATED_NOTEPAD_CONTENT_NOT_EXACT");Need(Message(0xB8).ToUInt64()==0,"GENERATED_NOTEPAD_DOCUMENT_ALREADY_MODIFIED");Keys(new INPUT[]{Key(0x11,false),Key(0x41,false),Key(0x41,true),Key(0x11,true)});
                Wait(delegate{SourceFocus();uint selection=checked((uint)Message(0xB0).ToUInt64());return (selection&65535)==0&&(selection>>16)==Expected.Length;},2000,"ACTUAL_NOTEPAD_KEYBOARD_SELECTION_NOT_EXACT");
                Report["actualNotepadTested"]=true;Report["expectedSourceSha256"]=Hash(Encoding.UTF8.GetBytes(Expected));SeedClipboard();SourceFocus();Report["executedCases"]=1;Stopwatch capture=Stopwatch.StartNew();Keys(new INPUT[]{Key(0x12,false),Key(0x44,false),Key(0x44,true),Key(0x12,true)});Report["actualHotkeysSent"]=1;
                Wait(delegate{return Server.Count==1&&HistoryExact()&&AppSource()==Expected;},30000,"SINGLE_ALTD_EXACT_NOTEPAD_SOURCE_AND_HISTORY");Report["hotkeyToHistoryMilliseconds"]=capture.Elapsed.TotalMilliseconds;SourceFocus();Need(EditorText()==Expected,"SOURCE_DOCUMENT_CHANGED");Need(Message(0xB8).ToUInt64()==0,"SOURCE_DOCUMENT_MODIFIED_DURING_ACQUISITION");Need(Hash(File.ReadAllBytes(document))==originalHash,"GENERATED_DOCUMENT_FILE_CHANGED");Need(Server.Count==1,"DUPLICATE_TRANSLATION_FOR_ONE_ALTD");CheckClipboard();Report["sourceForegroundPreserved"]=true;Report["sourceEditorUnchangedAndUnmodified"]=true;Report["generatedDocumentFileUnchanged"]=true;Report["richClipboardRestored"]=true;Report["historyExactSourceVerified"]=true;Report["mockRequestCount"]=Server.Count;Report["passedCases"]=1;Report["ok"]=true;
            }
        } catch(Unavailable e){Report["inconclusive"]=true;Report["error"]=e.Message;}catch(Exception e){Report["error"]=e.Message;Report["errorType"]=e.GetType().Name;}
        finally {
            // Release only keys emitted by this fixture, while one of its two
            // known windows still owns the foreground. Never touch another app.
            IntPtr foreground=GetForegroundWindow();if(foreground==Source||(Main!=IntPtr.Zero&&foreground==Main))SendInput(4,new INPUT[]{Key(0x12,true),Key(0x44,true),Key(0x11,true),Key(0x41,true)},Marshal.SizeOf(typeof(INPUT)));
            try{StopApp();Report["ownAppTreeStopped"]=true;}catch(Exception e){Report["ok"]=false;Report["cleanupError"]=e.Message;}
            try{StopNotepad();Report["ownLaunchedNotepadStopped"]=Notepad==null||Notepad.HasExited;Report["storeRetargetedProcessFollowed"]=false;}catch(Exception e){Report["ok"]=false;Report["notepadCleanupError"]=e.Message;}
            if(Seeded){if(GetClipboardSequenceNumber()==OwnedClipboard){Clipboard.Clear();Report["ownedClipboardCleared"]=true;}else{Report["ownedClipboardCleared"]=false;Report["ok"]=false;Report["clipboardCleanupError"]="CLIPBOARD_GENERATION_CHANGED_PRESERVED";}}
            for(int i=owned.Count-1;i>=0;i--)try{Remove(owned[i],token);}catch(Exception e){Report["ok"]=false;Report["directoryCleanupError"]=e.Message;}Report["ownedDirectoriesRemoved"]=owned.TrueForAll(delegate(string s){return !Directory.Exists(s);});if(App!=null)App.Dispose();if(Notepad!=null)Notepad.Dispose();
        }
        return Report;
    }
}
