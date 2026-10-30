// Generated WPF controls, not a WPS/Office/Notepad compatibility claim.
// Selection is made only by real Win32 mouse input; no UIA source warm-up.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Forms=System.Windows.Forms;

public static class WindowsSelectionWpfFixture {
    const string Identifier="io.github.blueeeecho.echolingo",Marker=".echolingo-wpf-selection-owned";
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=1048576};
    delegate bool EnumProc(IntPtr window,IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr unused);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] input,int size);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder text,int capacity);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll",SetLastError=true)] static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll",SetLastError=true)] static extern bool EmptyClipboard();
    [DllImport("user32.dll",SetLastError=true)] static extern uint EnumClipboardFormats(uint previous);
    [DllImport("kernel32.dll",EntryPoint="SetLastError")] static extern void NativeSetLastError(uint error);
    [DllImport("user32.dll")] static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr GetClipboardData(uint format);
    [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr data);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr data);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr data);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string path,IntPtr security);
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid id,uint flags,IntPtr token,out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr memory);
    [StructLayout(LayoutKind.Sequential)] struct POINT {public int x,y;}
    [StructLayout(LayoutKind.Sequential)] struct KEY {public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Explicit)] struct DATA {[FieldOffset(0)]public KEY key;[FieldOffset(0)]public MOUSE mouse;}
    [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public DATA data;}
    static void Need(bool value,string error){if(!value)throw new InvalidOperationException(error);}
    static INPUT Key(ushort vk,bool up){INPUT i=new INPUT();i.type=1;i.data.key.vk=vk;i.data.key.flags=up?2U:0U;return i;}
    static void Send(INPUT[] input){Need(SendInput((uint)input.Length,input,Marshal.SizeOf(typeof(INPUT)))==input.Length,"GENERATED_INPUT_REJECTED_NO_RETRY");}
    static string Folder(string id){Guid guid=new Guid(id);IntPtr p;Need(SHGetKnownFolderPath(ref guid,0,IntPtr.Zero,out p)==0,"KNOWN_FOLDER_FAILED");try{return Marshal.PtrToStringUni(p);}finally{CoTaskMemFree(p);}}
    // Shared by the native cleanup adapter and desktop-free policy self-tests.
    // The adapter holds OpenClipboard throughout; missing/foreign markers must
    // short-circuit before any content formats can be read or cleared.
    static string ReclaimSeed(Func<uint> sequence,Func<bool> markerPresent,Func<bool> markerMatches,Func<bool> formatsAndContentMatch,Func<bool> clear){
        uint observed=sequence();
        if(!markerPresent())return "marker-absent-preserved";
        if(!markerMatches())return "marker-mismatch-preserved";
        if(!formatsAndContentMatch())return "seed-mismatch-preserved";
        if(sequence()!=observed)return "generation-changed-preserved";
        return clear()?"verified-seed-cleared":"clear-failed-preserved";
    }
    static Dictionary<string,object> ClipboardValueObservation(int format,object value,bool equal){
        return new Dictionary<string,object>{{"formatKind",format},{"valueKind",value==null?0:value is string?1:value is Stream?2:value is byte[]?3:4},{"stringLength",value is string?((string)value).Length:-1},{"equal",equal}};
    }
    static bool SameBytes(byte[] expected,byte[] actual){if(expected.Length!=actual.Length)return false;for(int i=0;i<expected.Length;i++)if(expected[i]!=actual[i])return false;return true;}
    static bool MarkerMatches(byte[] expected,byte[] allocated){
        // Our marker has a fixed semantic length. GlobalSize is capacity and
        // may include uninitialized allocator padding beyond the nonce.
        if(allocated.Length<expected.Length)return false;for(int i=0;i<expected.Length;i++)if(expected[i]!=allocated[i])return false;return true;
    }
    static byte[] TextPayload(byte[] allocated,int unit){
        for(int i=0;i+unit<=allocated.Length;i+=unit){bool end=true;for(int j=0;j<unit;j++)end=end&&allocated[i+j]==0;if(end){byte[] payload=new byte[i+unit];Array.Copy(allocated,payload,payload.Length);return payload;}}
        throw new InvalidOperationException("GENERATED_CLIPBOARD_TEXT_TERMINATOR_MISSING");
    }
    static string UiaDeadlineCategory(int remaining){return remaining<5000?"OWN_APP_ACCEPTANCE_DEADLINE_DURING_UIA":"OWN_APP_UIA_CALL_DEADLINE";}
    public static int PolicySelfTests(){
        int tested=0,reads=0,clears=0;uint sequence=99;
        Func<bool> read=delegate{reads++;return true;},clear=delegate{clears++;return true;};
        Need(ReclaimSeed(delegate{return sequence;},delegate{return false;},read,read,clear)=="marker-absent-preserved"&&reads==0&&clears==0,"POLICY_FOREIGN_CONTENT_READ");tested++;
        Need(ReclaimSeed(delegate{return sequence;},delegate{return true;},delegate{return false;},read,clear)=="marker-mismatch-preserved"&&reads==0&&clears==0,"POLICY_FOREIGN_MARKER_CLEARED");tested++;
        Need(ReclaimSeed(delegate{return sequence;},delegate{return true;},delegate{return true;},delegate{return false;},clear)=="seed-mismatch-preserved"&&clears==0,"POLICY_CHANGED_SEED_CLEARED");tested++;
        Need(ReclaimSeed(delegate{return sequence;},delegate{return true;},delegate{return true;},delegate{sequence++;return true;},clear)=="generation-changed-preserved"&&clears==0,"POLICY_RACING_GENERATION_CLEARED");tested++;
        // Sequence need not equal the original seed: successful app restoration
        // publishes a new generation containing exactly our owned data.
        Need(ReclaimSeed(delegate{return sequence;},delegate{return true;},delegate{return true;},read,clear)=="verified-seed-cleared"&&clears==1,"POLICY_RESTORED_SEED_NOT_RECLAIMED");tested++;
        Need(ReclaimSeed(delegate{return sequence;},delegate{return true;},delegate{return true;},read,delegate{return false;})=="clear-failed-preserved","POLICY_CLEAR_FAILURE_HIDDEN");tested++;
        Need(UiaDeadlineCategory(5000)=="OWN_APP_UIA_CALL_DEADLINE"&&UiaDeadlineCategory(30000)=="OWN_APP_UIA_CALL_DEADLINE","POLICY_FULL_UIA_BUDGET_MISLABELED");tested++;
        Need(UiaDeadlineCategory(1)=="OWN_APP_ACCEPTANCE_DEADLINE_DURING_UIA"&&UiaDeadlineCategory(4999)=="OWN_APP_ACCEPTANCE_DEADLINE_DURING_UIA","POLICY_REMAINING_BUDGET_MISLABELED");tested++;
        Need(SameBytes(TextPayload(new byte[]{65,0,0,0,44,55},2),TextPayload(new byte[]{65,0,0,0},2)),"POLICY_UNICODE_CAPACITY_PADDING_COMPARED");tested++;
        Need(SameBytes(TextPayload(new byte[]{65,0,44},1),TextPayload(new byte[]{65,0},1))&&!SameBytes(TextPayload(new byte[]{65,0},1),TextPayload(new byte[]{66,0},1)),"POLICY_TEXT_PAYLOAD_COMPARISON");tested++;
        Need(MarkerMatches(new byte[]{1,2,3},new byte[]{1,2,3,99})&&!MarkerMatches(new byte[]{1,2,3},new byte[]{1,2})&&!MarkerMatches(new byte[]{1,2,3},new byte[]{1,2,4}),"POLICY_NONCE_COMPARISON");tested++;
        bool rejected=false;try{TextPayload(new byte[]{65,66},1);}catch(InvalidOperationException){rejected=true;}Need(rejected,"POLICY_UNTERMINATED_TEXT_ACCEPTED");tested++;
        var observed=ClipboardValueObservation(2,"fixture",false);
        Need((int)observed["formatKind"]==2&&(int)observed["valueKind"]==1&&(int)observed["stringLength"]==7&&!(bool)observed["equal"]&&observed.Count==4,"POLICY_OLE_OBSERVATION_CHANGED_VERDICT_OR_EXPORTED_CONTENT");tested++;
        Need((int)ClipboardValueObservation(1,null,false)["valueKind"]==0&&(int)ClipboardValueObservation(3,new byte[]{1},false)["valueKind"]==3,"POLICY_OLE_OBSERVATION_TYPE");tested++;
        return tested;
    }
    sealed class UiWorker {
        readonly AutoResetEvent wake=new AutoResetEvent(false);readonly object gate=new object();readonly Thread thread;Action pending;volatile bool poisoned,stop;
        int calls,lastRemaining,lastBudget,lastStage;long started,lastElapsed;bool observing;
        public UiWorker(){thread=new Thread(delegate(){while(true){wake.WaitOne();Action next;lock(gate){next=pending;pending=null;}if(next!=null)next();if(stop)return;}});thread.IsBackground=true;thread.SetApartmentState(ApartmentState.MTA);thread.Start();}
        public void Mark(int stage){lock(gate){lastStage=stage;}}
        public Dictionary<string,object> Observation(){lock(gate){return new Dictionary<string,object>{{"calls",calls},{"lastRequestedRemainingMilliseconds",lastRemaining},{"lastBudgetMilliseconds",lastBudget},{"lastElapsedMilliseconds",observing?(Stopwatch.GetTimestamp()-started)*1000/Stopwatch.Frequency:lastElapsed},{"lastSubstage",lastStage},{"timeoutBudgetCategory",UiaDeadlineCategory(lastRemaining)},{"poisoned",poisoned}};}}
        public T Call<T>(Func<T> action,int remaining){
            Need(!poisoned&&!stop,"OWN_APP_UIA_WORKER_UNAVAILABLE");var done=new TaskCompletionSource<T>();int timeout=Math.Max(1,Math.Min(5000,remaining));
            lock(gate){Need(pending==null,"OWN_APP_UIA_WORKER_BUSY");calls++;lastRemaining=remaining;lastBudget=timeout;lastStage=0;started=Stopwatch.GetTimestamp();observing=true;pending=delegate{try{Need(!poisoned&&!stop,"OWN_APP_UIA_WORKER_ABANDONED");done.SetResult(action());}catch(Exception e){done.SetException(e);}};}
            wake.Set();bool complete;
            try{try{complete=done.Task.Wait(timeout);}catch(AggregateException error){throw error.InnerException;}if(!complete){poisoned=true;throw new InvalidOperationException("OWN_APP_UIA_CALL_DEADLINE");}if(done.Task.IsFaulted)throw done.Task.Exception.InnerException;return done.Task.Result;}
            finally{lock(gate){lastElapsed=(Stopwatch.GetTimestamp()-started)*1000/Stopwatch.Frequency;observing=false;}}
        }
        public void Close(){stop=true;wake.Set();Need(thread.Join(2000),"OWN_APP_UIA_WORKER_NOT_STOPPED");}
    }
    sealed class Mock : IDisposable {
        readonly TcpListener listener=new TcpListener(IPAddress.Loopback,0);readonly Thread thread;readonly object gate=new object();readonly Dictionary<string,int> counts=new Dictionary<string,int>();volatile bool stop;public string Error;
        public Mock(IEnumerable<string> sources){foreach(string s in sources)counts.Add(s,0);listener.Start();thread=new Thread(delegate(){while(!stop){try{TcpClient client=listener.AcceptTcpClient();ThreadPool.QueueUserWorkItem(delegate{Handle(client);});}catch{if(!stop)Error="MOCK_ACCEPT_FAILED";}}});thread.IsBackground=true;thread.Start();}
        public string Url {get{return "http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port;}}
        public static string Result(string s){return "Generated WPF translation "+s;}
        public int Count(string s){lock(gate)return counts[s];}
        void Handle(TcpClient client){try{using(client){client.ReceiveTimeout=5000;client.SendTimeout=5000;NetworkStream stream=client.GetStream();List<byte> header=new List<byte>();while(header.Count<16384){int b=stream.ReadByte();Need(b>=0,"MOCK_HEADER_TRUNCATED");header.Add((byte)b);int n=header.Count;if(n>=4&&header[n-4]==13&&header[n-3]==10&&header[n-2]==13&&header[n-1]==10)break;}string headers=Encoding.ASCII.GetString(header.ToArray());Need(headers.StartsWith("POST /translate HTTP/1.1\r\n",StringComparison.Ordinal),"MOCK_ROUTE_REJECTED");int length=-1;foreach(string line in headers.Split(new string[]{"\r\n"},StringSplitOptions.None)){Need(!line.StartsWith("Authorization:",StringComparison.OrdinalIgnoreCase),"MOCK_AUTHORIZATION_REJECTED");if(line.StartsWith("Content-Length:",StringComparison.OrdinalIgnoreCase))length=Int32.Parse(line.Substring(15).Trim());}Need(length>=0&&length<=65536,"MOCK_BODY_BOUND");byte[] bytes=new byte[length];int offset=0;while(offset<length){int n=stream.Read(bytes,offset,length-offset);Need(n>0,"MOCK_BODY_TRUNCATED");offset+=n;}var json=new JavaScriptSerializer();var body=json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(bytes));string text=Convert.ToString(body["q"]);Need(!body.ContainsKey("api_key")||String.IsNullOrEmpty(body["api_key"] as string),"MOCK_KEY_REJECTED");lock(gate){Need(counts.ContainsKey(text),"MOCK_NON_GENERATED_SOURCE_REJECTED");counts[text]++;}byte[] response=Encoding.UTF8.GetBytes(json.Serialize(new Dictionary<string,object>{{"translatedText",Result(text)}}));byte[] prefix=Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+response.Length+"\r\n\r\n");stream.Write(prefix,0,prefix.Length);stream.Write(response,0,response.Length);stream.Flush();}}catch{if(!stop)Error="MOCK_GENERATED_REQUEST_FAILED";}}
        public void Dispose(){stop=true;listener.Stop();Need(thread.Join(2000),"MOCK_THREAD_NOT_STOPPED");}
    }
    sealed class Fixture {
        readonly string executable,token=Guid.NewGuid().ToString("N");readonly string[] texts={"Generated WPF first selection 63101","Second WPF selection: alpha_beta 63102","\u56fa\u5b9a\u540e WPF \u65b0\u9009\u533a\uff1a\u4f60\u597d\uff0c\u4e16\u754c 63103"};
        readonly List<string> owned=new List<string>();readonly List<object> cases=new List<object>();readonly List<string> cleanupErrors=new List<string>();readonly Stopwatch overall=Stopwatch.StartNew();
        readonly Dictionary<string,object> report=new Dictionary<string,object>();Window source;RichTextBox editor;Run[] runs;IntPtr sourceHwnd,main;Process app;UiWorker ui;Mock mock;string provider,history,documentBefore,stage="setup";int downs,ups,changes,hotkeys,sourceStarted;bool leftOwned,keysOwned,seeded;uint clipboardMarker;Forms.DataObject clipboard;byte[] markerBytes;HashSet<uint> seedFormats;Dictionary<uint,byte[]> seedContent;
        public Fixture(string path){executable=path;}
        void Active(){Need(overall.ElapsedMilliseconds<180000,"WPF_FIXTURE_DEADLINE_180000MS");}
        void Ui(Action action){source.Dispatcher.Invoke(action);}
        T Ui<T>(Func<T> action){return (T)source.Dispatcher.Invoke(action);}
        void Wait(Func<bool> condition,int limit,string failure){Stopwatch elapsed=Stopwatch.StartNew();while(elapsed.ElapsedMilliseconds<limit){Active();if(condition())return;Thread.Sleep((int)Math.Min(10,Math.Max(1,limit-elapsed.ElapsedMilliseconds)));}throw new InvalidOperationException(failure);}
        void Claim(string path){Need(CreateDirectory(path,IntPtr.Zero),"EXISTING_DATA_REFUSED");owned.Add(path);File.WriteAllText(Path.Combine(path,Marker),token,new UTF8Encoding(false));}
        void CheckRoot(string path){Need(Directory.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)==0&&File.ReadAllText(Path.Combine(path,Marker))==token,"OWNED_DATA_CHANGED");}
        void NoLinks(string path){Need((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"OWNED_TREE_REPARSE_POINT");foreach(string child in Directory.GetFileSystemEntries(path)){try{Need((File.GetAttributes(child)&FileAttributes.ReparsePoint)==0,"OWNED_TREE_REPARSE_POINT");if(Directory.Exists(child))NoLinks(child);}catch(FileNotFoundException){if(File.Exists(child)||Directory.Exists(child))throw;}catch(DirectoryNotFoundException){if(File.Exists(child)||Directory.Exists(child))throw;}}}
        void Remove(string path){if(!Directory.Exists(path))return;CheckRoot(path);Stopwatch time=Stopwatch.StartNew();bool deleting=false;while(true){try{Need((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"OWNED_ROOT_REPARSE_POINT");NoLinks(path);deleting=true;Directory.Delete(path,true);return;}catch(IOException){if(!Directory.Exists(path))return;if(time.ElapsedMilliseconds>=5000)throw;}catch(UnauthorizedAccessException){if(time.ElapsedMilliseconds>=5000)throw;}if(!deleting)CheckRoot(path);Thread.Sleep(20);}}
        IntPtr Main(){List<IntPtr> found=new List<IntPtr>();EnumWindows(delegate(IntPtr w,IntPtr unused){uint pid;GetWindowThreadProcessId(w,out pid);if(pid==app.Id&&GetAncestor(w,2)==w){StringBuilder name=new StringBuilder(128);GetClassName(w,name,name.Capacity);if(name.ToString()=="Tauri Window")found.Add(w);}return true;},IntPtr.Zero);Need(found.Count<=1,"ACTUAL_MAIN_NOT_UNIQUE");return found.Count==1?found[0]:IntPtr.Zero;}
        bool NativeReady(){int hotkeysCount=0,trays=0;EnumWindows(delegate(IntPtr w,IntPtr ignored){uint pid;GetWindowThreadProcessId(w,out pid);if(pid==app.Id){StringBuilder name=new StringBuilder(128);GetClassName(w,name,name.Capacity);if(name.ToString()=="global_hotkey_app")hotkeysCount++;if(name.ToString()=="tray_icon_app")trays++;}return true;},IntPtr.Zero);return hotkeysCount>0&&trays>0;}
        string SourceValue(){
            ui.Mark(1);Need(Main()==main,"ACTUAL_MAIN_IDENTITY_CHANGED");ui.Mark(2);AutomationElement root=AutomationElement.FromHandle(main);
            ui.Mark(3);Need(root.Current.ProcessId==app.Id,"ACTUAL_UIA_ROOT_PID_CHANGED");ui.Mark(4);
            var all=root.FindAll(TreeScope.Descendants,new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new OrCondition(new PropertyCondition(AutomationElement.AutomationIdProperty,"source-text"),new PropertyCondition(AutomationElement.NameProperty,"\u539f\u6587"))));
            string value=null;int count=0;foreach(AutomationElement e in all){ui.Mark(5);if(e.Current.IsOffscreen)continue;count++;object p;ui.Mark(6);Need(e.TryGetCurrentPattern(ValuePattern.Pattern,out p),"ACTUAL_SOURCE_VALUE_PATTERN_MISSING");ui.Mark(7);value=((ValuePattern)p).Current.Value;}
            ui.Mark(8);Need(count<=1,"ACTUAL_SOURCE_EDITOR_NOT_UNIQUE");return value;
        }
        int HistoryCount(string expected){CheckRoot(Path.GetDirectoryName(history));if(!File.Exists(history))return 0;Need(new FileInfo(history).Length<=1048576,"HISTORY_FILE_BOUND");try{object[] rows=Json.Deserialize<object[]>(File.ReadAllText(history));Need(rows.Length<=100,"HISTORY_COUNT_BOUND");int count=0;foreach(object item in rows){var row=(Dictionary<string,object>)item;if(Convert.ToString(row["text"])!=expected)continue;foreach(object raw in (IEnumerable)row["results"]){var result=(Dictionary<string,object>)raw;if(Convert.ToString(result["providerId"])==provider&&!result.ContainsKey("error")&&Convert.ToString(result["text"])==Mock.Result(expected)){count++;break;}}}return count;}catch(IOException){return 0;}catch(ArgumentException){return 0;}}
        static HashSet<uint> ClipboardFormats(){
            var formats=new HashSet<uint>();uint current=0;
            while(true){NativeSetLastError(0);current=EnumClipboardFormats(current);int error=Marshal.GetLastWin32Error();if(current==0){Need(error==0,"GENERATED_CLIPBOARD_FORMAT_ENUMERATION_FAILED");return formats;}Need(formats.Count<64&&formats.Add(current),"GENERATED_CLIPBOARD_FORMAT_BOUND");}
        }
        static byte[] ClipboardBytes(uint format){
            IntPtr memory=GetClipboardData(format);Need(memory!=IntPtr.Zero,"GENERATED_CLIPBOARD_DATA_UNAVAILABLE");ulong length=GlobalSize(memory).ToUInt64();Need(length>0&&length<=65536,"GENERATED_CLIPBOARD_DATA_BOUND");
            IntPtr pointer=GlobalLock(memory);Need(pointer!=IntPtr.Zero,"GENERATED_CLIPBOARD_DATA_LOCK_FAILED");try{byte[] bytes=new byte[(int)length];Marshal.Copy(pointer,bytes,0,bytes.Length);return bytes;}finally{GlobalUnlock(memory);}
        }
        void SeedClipboard(){Ui(delegate{
            clipboard=new Forms.DataObject();clipboard.SetData(Forms.DataFormats.UnicodeText,false,"Generated WPF clipboard original 7531");clipboard.SetData(Forms.DataFormats.Html,false,"<p>Generated WPF rich original 7531</p>");clipboard.SetData(Forms.DataFormats.Rtf,false,"{\\rtf1 Generated WPF rich original 7531}");
            string markerName="EchoLingo.WpfFixture.Seed."+token;clipboardMarker=RegisterClipboardFormat(markerName);Need(clipboardMarker!=0,"GENERATED_CLIPBOARD_MARKER_FORMAT_FAILED");
            markerBytes=new byte[32];using(var random=System.Security.Cryptography.RandomNumberGenerator.Create())random.GetBytes(markerBytes);
            var generated=new Forms.DataObject();foreach(string format in clipboard.GetFormats(false))generated.SetData(format,false,clipboard.GetData(format,false));
            // Publish identity with the original Forms/OLE seed, never append a
            // marker to a clipboard that could have changed in between calls.
            using(var marker=new MemoryStream(markerBytes,false)){generated.SetData(markerName,false,marker);Forms.Clipboard.SetDataObject(generated,true,0,0);}
            Need(OpenClipboard(sourceHwnd),"GENERATED_CLIPBOARD_SEED_BUSY");
            try{Need(IsClipboardFormatAvailable(clipboardMarker)&&MarkerMatches(markerBytes,ClipboardBytes(clipboardMarker)),"GENERATED_CLIPBOARD_SEED_OWNERSHIP_CHANGED");
                seedContent=new Dictionary<uint,byte[]>();
                foreach(string name in new string[]{Forms.DataFormats.UnicodeText,Forms.DataFormats.Html,Forms.DataFormats.Rtf}){
                    uint format=name==Forms.DataFormats.UnicodeText?13:RegisterClipboardFormat(name);byte[] payload=TextPayload(ClipboardBytes(format),format==13?2:1);
                    byte[] expected=(format==13?Encoding.Unicode:Encoding.UTF8).GetBytes((string)clipboard.GetData(name,false)+'\0');
                    Need(SameBytes(expected,payload),"GENERATED_CLIPBOARD_SEED_CONTENT_CHANGED");seedContent.Add(format,expected);
                }
                seedFormats=ClipboardFormats();seeded=true;
            }finally{CloseClipboard();}
        });}
        string ClearVerifiedClipboard(){
            if(!seeded)return "not-seeded";
            if(!OpenClipboard(sourceHwnd))return "clipboard-busy-preserved";
            try{return ReclaimSeed(GetClipboardSequenceNumber,delegate{return IsClipboardFormatAvailable(clipboardMarker);},
                delegate{return MarkerMatches(markerBytes,ClipboardBytes(clipboardMarker));},
                delegate{if(!seedFormats.SetEquals(ClipboardFormats()))return false;foreach(var pair in seedContent)if(!SameBytes(pair.Value,TextPayload(ClipboardBytes(pair.Key),pair.Key==13?2:1)))return false;return true;},EmptyClipboard);
            }finally{CloseClipboard();}
        }
        // Keep the original single OLE read and first-mismatch verdict. The
        // native cross-check only runs after failure; it never retries OLE or
        // changes acceptance. No clipboard content or arbitrary names escape.
        bool ClipboardMatches(Dictionary<string,object> observation){return Ui(delegate{
            Stopwatch elapsed=Stopwatch.StartNew();uint before=GetClipboardSequenceNumber();
            observation["sequenceBeforeOle"]=before;observation["oleReadRetried"]=false;
            bool matches=true;var rows=new List<Dictionary<string,object>>();observation["formats"]=rows;
            var actual=Forms.Clipboard.GetDataObject();observation["oleObjectAvailable"]=actual!=null;
            if(actual==null)matches=false;
            else foreach(string format in clipboard.GetFormats(false)){
                object expected=clipboard.GetData(format,false),value=actual.GetData(format,false);
                bool equal=Object.Equals(expected,value);
                rows.Add(ClipboardValueObservation(format==Forms.DataFormats.UnicodeText?1:format==Forms.DataFormats.Html?2:3,value,equal));
                if(!equal){matches=false;break;}
            }
            observation["sequenceAfterOle"]=GetClipboardSequenceNumber();observation["originalVerdict"]=matches;
            if(!matches){
                observation["nativeCrossCheckAfterFailure"]=true;
                bool opened=OpenClipboard(sourceHwnd);observation["nativeClipboardOpened"]=opened;
                if(opened)try{
                    observation["sequenceAtNativeRead"]=GetClipboardSequenceNumber();
                    bool marker=IsClipboardFormatAvailable(clipboardMarker)&&MarkerMatches(markerBytes,ClipboardBytes(clipboardMarker));
                    observation["nativeSeedMarkerMatches"]=marker;
                    // Only our nonce-verified generated clipboard may be read.
                    if(marker){
                        observation["nativeFormatSetMatches"]=seedFormats.SetEquals(ClipboardFormats());
                        var native=new List<Dictionary<string,object>>();observation["nativeFormats"]=native;
                        foreach(var pair in seedContent){
                            bool available=IsClipboardFormatAvailable(pair.Key);byte[] payload=available?TextPayload(ClipboardBytes(pair.Key),pair.Key==13?2:1):null;
                            native.Add(new Dictionary<string,object>{{"formatKind",pair.Key==13?1:pair.Key==RegisterClipboardFormat(Forms.DataFormats.Html)?2:3},{"available",available},{"payloadBytes",payload==null?-1:payload.Length},{"matches",payload!=null&&SameBytes(pair.Value,payload)}});
                        }
                    }
                    observation["sequenceAfterNativeRead"]=GetClipboardSequenceNumber();
                }catch{observation["nativeObservationFailed"]=true;}
                finally{CloseClipboard();}
            }
            observation["elapsedMilliseconds"]=elapsed.ElapsedMilliseconds;
            return matches;
        });}
        static long DiagnosticNumber(object value,long maximum){
            Need(value is int||value is long,"FAILURE_DIAGNOSTIC_INTEGER_REQUIRED");long number=Convert.ToInt64(value);Need(number>=0&&number<=maximum,"FAILURE_DIAGNOSTIC_NUMBER_BOUND");return number;
        }
        static string DiagnosticFailureCategory(string message){
            if(String.IsNullOrEmpty(message)||message.Length>100)return "UNCLASSIFIED_FAILURE_DIAGNOSTIC";
            foreach(char value in message)if((value<'A'||value>'Z')&&value!='_')return "UNCLASSIFIED_FAILURE_DIAGNOSTIC";return message;
        }
        static HashSet<string> FailureHealthFields(){
            var fields=new HashSet<string>(new string[]{"attemptId","attemptPhase","nativeBoundaryStage","configuredCopyStrategy","actionErrorKind","actionResultOk","actionResultNonempty","sourceSnapshotOutcome","sourceCurrentAtWorker","selectionQueryCount","helperResponseReceived","helperElapsedMilliseconds","helperResultNonempty","cancellationRequested","cancellationSignalled","cancellationSignalFailed"});
            foreach(string key in new string[]{"copyStrategy","copyPhase","copyNativeContextValid","copyNativeContextChecks","copyNativeGuardReason","copyNativeInvalidReason","copyNativeGtiSucceeded","copyNativeGtiFlags","copyNativeFocusPresent","copyNativeFocusProcessMatchesForeground","copyNativeFocusRootMatchesForeground","copyNativeActivePresent","copyNativeActiveRootMatchesForeground","copyNativeEditable","copyNativeProtection","copyNativeSelectionKnown","copyNativeSelectionNonempty","copyProtectionProbe","copyProtectionProbeMilliseconds","copyProtectionUnknown","copySnapshotOutcome","copyDispatchInserted","copyOwnInputObserved","copyOwnerOutcome","copyClipboardRestored","copyTerminalReason"})fields.Add(key);
            foreach(string suffix in new string[]{"Stage","Depth","IdentityCompared","IdentityEqual","RootWalkReason","ExceptionKind","Milliseconds"})for(int index=1;index<=16;index++)fields.Add("selectionQuery"+index+suffix);
            return fields;
        }
        // Observe only after acceptance has already failed. The existing CLI
        // exports numeric health; it does not capture, copy, retry, focus, or
        // extend the original 30-second source/history acceptance deadline.
        Dictionary<string,object> FailureSelectionHealth(){
            var result=new Dictionary<string,object>{{"takenAfterFailure",true},{"originalFailureUnchanged",true},{"budgetMilliseconds",2000},{"captureOrKeyRequests",0},{"sourceOrClipboardContentRead",false}};
            Stopwatch budget=Stopwatch.StartNew();Process secondary=null;uint clipboard=GetClipboardSequenceNumber();IntPtr foreground=GetForegroundWindow();bool visible=IsWindowVisible(main);
            try{
                Need(app!=null&&!app.HasExited&&Main()==main,"FAILURE_DIAGNOSTIC_PRIMARY_UNAVAILABLE");string roaming=Path.GetDirectoryName(history);CheckRoot(roaming);
                string executable=Path.GetFullPath(app.StartInfo.FileName);Need(String.Equals(Path.GetFullPath(app.MainModule.FileName),executable,StringComparison.OrdinalIgnoreCase),"FAILURE_DIAGNOSTIC_PRIMARY_IDENTITY");
                string file=Path.Combine(roaming,"selection-diagnostics.json");Need(!File.Exists(file)&&!Directory.Exists(file),"FAILURE_DIAGNOSTIC_FILE_ALREADY_EXISTS");
                ProcessStartInfo start=new ProcessStartInfo(executable,"--selection-diagnostics");start.UseShellExecute=false;start.CreateNoWindow=true;
                foreach(string key in new string[]{"LOCALAPPDATA","TEMP","TMP","WEBVIEW2_USER_DATA_FOLDER"})start.EnvironmentVariables[key]=app.StartInfo.EnvironmentVariables[key];
                long earliest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;secondary=Process.Start(start);Need(secondary!=null&&secondary.Id!=app.Id,"FAILURE_DIAGNOSTIC_SECONDARY_IDENTITY");
                while(budget.ElapsedMilliseconds<2000){if(secondary.HasExited&&File.Exists(file))break;Thread.Sleep((int)Math.Min(10,Math.Max(1,2000-budget.ElapsedMilliseconds)));}
                result["secondaryExitObserved"]=secondary.HasExited;Need(secondary.HasExited&&secondary.ExitCode==0&&File.Exists(file)&&budget.ElapsedMilliseconds<2000,"FAILURE_DIAGNOSTIC_EXPORT_DEADLINE");
                CheckRoot(roaming);Need((File.GetAttributes(file)&FileAttributes.ReparsePoint)==0&&new FileInfo(file).Length>0&&new FileInfo(file).Length<=16384,"FAILURE_DIAGNOSTIC_FILE_BOUND");
                var payload=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file));Need(Convert.ToString(payload["diagnostic"])=="last-selection-attempt"&&DiagnosticNumber(payload["processId"],Int32.MaxValue)==app.Id&&String.Equals(Convert.ToString(payload["executablePath"]),executable,StringComparison.OrdinalIgnoreCase),"FAILURE_DIAGNOSTIC_EXPORTED_IDENTITY");
                long recorded=DiagnosticNumber(payload["recordedAtUnixMs"],Int64.MaxValue),latest=(long)(DateTime.UtcNow-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalMilliseconds;Need(recorded>=earliest&&recorded<=latest,"FAILURE_DIAGNOSTIC_STALE_EXPORT");
                var health=payload["diagnostics"] as Dictionary<string,object>;Need(health!=null,"FAILURE_DIAGNOSTIC_HEALTH_MISSING");var numeric=new Dictionary<string,object>();var allowed=FailureHealthFields();
                foreach(var pair in health)if(allowed.Contains(pair.Key))numeric[pair.Key]=DiagnosticNumber(pair.Value,10000000);
                result["primaryIdentityVerified"]=true;result["nativeHealth"]=numeric;
            }catch(Exception error){result["observationErrorCategory"]=DiagnosticFailureCategory(error.Message);result["observationErrorType"]=error.GetType().Name;result["observationErrorHResult"]=error.HResult;}
            finally{
                if(secondary!=null){try{if(!secondary.HasExited&&secondary.Id!=app.Id){
                    // The primary could exit between verification and launch.
                    // In that race this owned secondary may have WebView children.
                    ProcessStartInfo stop=new ProcessStartInfo("taskkill.exe","/PID "+secondary.Id+" /T /F");stop.UseShellExecute=false;stop.CreateNoWindow=true;stop.RedirectStandardOutput=true;stop.RedirectStandardError=true;
                    using(Process killer=Process.Start(stop)){var output=killer.StandardOutput.ReadToEndAsync();var error=killer.StandardError.ReadToEndAsync();if(!killer.WaitForExit(1000)){killer.Kill();killer.WaitForExit(200);}result["secondaryTreeCleanupExited"]=killer.HasExited;}
                    result["timedOutSecondaryStopped"]=secondary.HasExited;
                }}catch(Exception error){result["secondaryCleanupErrorType"]=error.GetType().Name;}finally{secondary.Dispose();}}
                result["clipboardSequenceUnchanged"]=GetClipboardSequenceNumber()==clipboard;result["foregroundUnchanged"]=GetForegroundWindow()==foreground;result["popupVisibilityUnchanged"]=IsWindowVisible(main)==visible;
            }
            return result;
        }
        void SelectWithMouse(int index,Dictionary<string,object> row){
            stage="wpf-mouse-selection-setup";Point first=new Point(),last=new Point();int downBefore=0,upBefore=0;Ui(delegate{
                source.Activate();Need(SetForegroundWindow(sourceHwnd)||GetForegroundWindow()==sourceHwnd,"WPF_SOURCE_FOREGROUND_REJECTED");editor.Focus();editor.UpdateLayout();
                Need(runs[index].ContentStart.HasValidLayout&&runs[index].ContentEnd.HasValidLayout,"WPF_GENERATED_TEXT_LAYOUT_UNAVAILABLE");Rect a=runs[index].ContentStart.GetCharacterRect(LogicalDirection.Forward),b=runs[index].ContentEnd.GetCharacterRect(LogicalDirection.Backward);Need(!a.IsEmpty&&!b.IsEmpty&&a.Height>0&&b.Height>0,"WPF_GENERATED_TEXT_RECTS_UNAVAILABLE");
                first=editor.PointToScreen(new Point(a.Left+.2,a.Top+a.Height/2));last=editor.PointToScreen(new Point(b.Right-.2,b.Top+b.Height/2));downBefore=downs;upBefore=ups;row["generatedTextLayoutRects"]=new double[]{a.Left,a.Top,a.Width,a.Height,b.Left,b.Top,b.Width,b.Height};
            });Need(GetForegroundWindow()==sourceHwnd,"WPF_SOURCE_NOT_FOREGROUND");POINT p=new POINT();p.x=(int)Math.Round(first.X);p.y=(int)Math.Round(first.Y);uint pid;IntPtr hit=WindowFromPoint(p);GetWindowThreadProcessId(hit,out pid);Need(pid==Process.GetCurrentProcess().Id&&GetAncestor(hit,2)==sourceHwnd,"WPF_DRAG_START_HIT_NOT_OWN_SOURCE");Need((GetAsyncKeyState(1)&0x8000)==0,"WPF_LEFT_ALREADY_HELD");
            INPUT down=new INPUT();down.type=0;down.data.mouse.flags=2;INPUT up=down;up.data.mouse.flags=4;Need(SetCursorPos(p.x,p.y),"WPF_POINTER_POSITION_FAILED");leftOwned=true;Send(new INPUT[]{down});try{for(int step=1;step<=8;step++){Need(GetForegroundWindow()==sourceHwnd,"WPF_DRAG_SOURCE_FOREGROUND_CHANGED");Need(SetCursorPos(p.x+((int)Math.Round(last.X)-p.x)*step/8,p.y+((int)Math.Round(last.Y)-p.y)*step/8),"WPF_DRAG_MOVE_FAILED");Thread.Sleep(15);}var desktop=Forms.SystemInformation.VirtualScreen;INPUT move=new INPUT();move.type=0;move.data.mouse.flags=0x8000|0x4000|1;move.data.mouse.x=(int)Math.Round((last.X-desktop.Left)*65535.0/(desktop.Width-1));move.data.mouse.y=(int)Math.Round((last.Y-desktop.Top)*65535.0/(desktop.Height-1));Send(new INPUT[]{move,up});leftOwned=false;}finally{if(leftOwned){SendInput(1,new INPUT[]{up},Marshal.SizeOf(typeof(INPUT)));leftOwned=false;}}
            Wait(delegate{return Ui(delegate{return ups-upBefore==1;})&&(GetAsyncKeyState(1)&0x8000)==0;},2000,"WPF_MOUSE_UP_NOT_OBSERVED");
            Ui(delegate{row["sourceMouseDowns"]=downs-downBefore;row["sourceMouseUps"]=ups-upBefore;row["selectedLength"]=editor.Selection.Text.Length;Need(downs-downBefore==1&&ups-upBefore==1,"WPF_MOUSE_PAIR_COUNT_MISMATCH");Need(editor.Selection.Text==texts[index],"WPF_MOUSE_SELECTION_NOT_EXACT_NO_PROGRAMMATIC_REPAIR");Need(new TextRange(editor.Document.ContentStart,editor.Document.ContentEnd).Text==documentBefore&&changes==0,"WPF_DOCUMENT_CHANGED_DURING_SELECTION");});row["mouseReleasedBeforeAltD"]=true;row["selectionAssignedProgrammatically"]=false;
        }
        void Pin(){stage="actual-pin-once";string pattern=ui.Call(delegate{AutomationElement root=AutomationElement.FromHandle(main);var all=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.NameProperty,"\u9489\u4f4f\u7a97\u53e3"));AutomationElement button=null;int count=0;foreach(AutomationElement e in all)if(!e.Current.IsOffscreen){button=e;count++;}Need(count==1,"ACTUAL_PIN_BUTTON_NOT_UNIQUE");object p;if(button.TryGetCurrentPattern(InvokePattern.Pattern,out p)){((InvokePattern)p).Invoke();return "InvokePattern";}Need(button.TryGetCurrentPattern(TogglePattern.Pattern,out p),"ACTUAL_PIN_PATTERN_MISSING");((TogglePattern)p).Toggle();return "TogglePattern";},5000);report["pinActionPattern"]=pattern;Wait(delegate{return ui.Call(delegate{var e=AutomationElement.FromHandle(main).FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.NameProperty,"\u53d6\u6d88\u9489\u4f4f"));return e!=null&&!e.Current.IsOffscreen;},5000);},5000,"ACTUAL_PIN_STATE_NOT_OBSERVED");}
        void Case(int index,bool pinned){
            var row=new Dictionary<string,object>{{"name",index==0?"wpf-first-real-mouse-alt-d":index==1?"wpf-different-selection-next-alt-d":"wpf-pinned-new-selection-alt-d"},{"ok",false},{"hotkeysSent",0},{"preSourceUiaCalls",0},{"sourceProvider","System.Windows.Controls.RichTextBox + FlowDocument"},{"pinned",pinned}};
            cases.Add(row);SelectWithMouse(index,row);SeedClipboard();int historyBefore=HistoryCount(texts[index]),mockBefore=mock.Count(texts[index]);row["historyCountBefore"]=historyBefore;row["mockRequestsBefore"]=mockBefore;
            Need(historyBefore==0&&mockBefore==0,"UNTRIGGERED_WPF_SOURCE_ALREADY_TRANSLATED");Need(GetForegroundWindow()==sourceHwnd,"WPF_SOURCE_CHANGED_BEFORE_ALT_D");foreach(int key in new int[]{0x10,0x11,0x12,0x5B,0x5C})Need((GetAsyncKeyState(key)&0x8000)==0,"SHORTCUT_MODIFIER_ALREADY_HELD");
            stage="single-real-alt-d";Stopwatch clock=Stopwatch.StartNew();keysOwned=true;hotkeys++;row["hotkeysSent"]=1;
            try{Send(new INPUT[]{Key(0x12,false),Key(0x44,false),Key(0x44,true),Key(0x12,true)});keysOwned=false;}finally{if(keysOwned){SendInput(2,new INPUT[]{Key(0x44,true),Key(0x12,true)},Marshal.SizeOf(typeof(INPUT)));keysOwned=false;}}
            stage="actual-source-new-mock-new-history";bool exact=false,foreground=true,visibleAlways=true;
            try{
                while(clock.ElapsedMilliseconds<30000){
                    Active();foreground=foreground&&GetForegroundWindow()==sourceHwnd;visibleAlways=visibleAlways&&IsWindowVisible(main);
                    if(IsWindowVisible(main))try{
                        string value=ui.Call(SourceValue,(int)Math.Max(1,30000-clock.ElapsedMilliseconds));row["actualSourceLength"]=value==null?-1:value.Length;row["actualSourceEmpty"]=value=="";row["exactSourceMatched"]=value==texts[index];
                        if(value==texts[index]&&HistoryCount(texts[index])==historyBefore+1&&mock.Count(texts[index])==mockBefore+1){exact=true;break;}
                    }catch(ElementNotAvailableException){row["transientOwnAppElementUnavailableObserved"]=true;}
                    Thread.Sleep(10);
                }
                var clipboardObservation=new Dictionary<string,object>();row["clipboardRestorationObservation"]=clipboardObservation;row["richClipboardRestored"]=ClipboardMatches(clipboardObservation);row["documentUnchanged"]=Ui(delegate{return new TextRange(editor.Document.ContentStart,editor.Document.ContentEnd).Text==documentBefore&&changes==0&&editor.Selection.Text==texts[index];});
                Need(exact,"ACTUAL_APP_EXACT_SOURCE_NEW_HISTORY_OR_MOCK_FAILED");Need(foreground&&GetForegroundWindow()==sourceHwnd&&Convert.ToBoolean(row["richClipboardRestored"])&&Convert.ToBoolean(row["documentUnchanged"]),"WPF_SOURCE_FOREGROUND_DOCUMENT_OR_CLIPBOARD_CHANGED");
                Need(mock.Error==null,"MOCK_REQUEST_FAILURE");for(int future=index+1;future<texts.Length;future++)Need(mock.Count(texts[future])==0&&HistoryCount(texts[future])==0,"UNTRIGGERED_FUTURE_WPF_SOURCE_TRANSLATED");
                if(pinned)Need(visibleAlways&&IsWindowVisible(main),"PINNED_POPUP_HIDDEN_DURING_OR_AFTER_NEW_SELECTION");row["ok"]=true;
            }finally{
                // Preserve evidence even when one UIA call exhausts its smaller
                // remaining acceptance budget. None of these values repair or
                // retry the original failed case; take counters before export.
                row["hotkeyToSourceAndHistoryMilliseconds"]=clock.Elapsed.TotalMilliseconds;row["acceptanceDeadlineMilliseconds"]=30000;
                row["sourceForegroundPreserved"]=foreground&&GetForegroundWindow()==sourceHwnd;row["pinnedVisibilityAllSamples"]=visibleAlways;row["popupNativeVisibleAtEnd"]=IsWindowVisible(main);row["uiaObservation"]=ui.Observation();
                try{row["newMockRequests"]=mock.Count(texts[index])-mockBefore;row["newHistoryEntries"]=HistoryCount(texts[index])-historyBefore;}catch(Exception error){row["finalCounterErrorType"]=error.GetType().Name;}
                if(!Convert.ToBoolean(row["ok"]))try{row["failureOnlySelectionObservation"]=FailureSelectionHealth();}catch(Exception error){row["failureOnlySelectionObservationErrorType"]=error.GetType().Name;}
            }
        }
        void Start(string local,string root){stage="start-exact-application";ProcessStartInfo start=new ProcessStartInfo(executable);start.UseShellExecute=false;start.CreateNoWindow=true;string temp=Path.Combine(root,"Temp");Directory.CreateDirectory(temp);start.EnvironmentVariables["TEMP"]=temp;start.EnvironmentVariables["TMP"]=temp;start.EnvironmentVariables["LOCALAPPDATA"]=local;start.EnvironmentVariables["WEBVIEW2_USER_DATA_FOLDER"]=Path.Combine(local,"wpf-webview");app=Process.Start(start);report["actualApplicationTested"]=true;report["applicationProcessId"]=app.Id;Need(app.WaitForInputIdle(15000),"APP_NATIVE_INPUT_IDLE_DEADLINE");Wait(delegate{Need(!app.HasExited,"ACTUAL_APP_EXITED");main=Main();return main!=IntPtr.Zero;},20000,"ACTUAL_APP_MAIN_DEADLINE");Wait(NativeReady,15000,"ACTUAL_HOTKEY_HOST_AND_TRAY_DEADLINE");Need(!IsWindowVisible(main),"ACTUAL_APP_DID_NOT_START_SILENTLY");report["nativeReadinessDoesNotProveRegistration"]=true;report["fixedFrontendWarmupMilliseconds"]=0;ui=new UiWorker();}
        void Stop(){if(app==null)return;if(!app.HasExited){var start=new ProcessStartInfo("taskkill.exe","/PID "+app.Id+" /T /F");start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;using(Process kill=Process.Start(start)){Task<string> stdout=kill.StandardOutput.ReadToEndAsync(),stderr=kill.StandardError.ReadToEndAsync();Need(kill.WaitForExit(5000),"OWN_APP_TREE_STOP_DEADLINE");Need(Task.WaitAll(new Task[]{stdout,stderr},1000),"OWN_APP_STOP_PIPES_DEADLINE");}}Need(app.WaitForExit(5000),"OWN_APP_STILL_RUNNING");report["ownApplicationStopped"]=true;report["applicationStopMethod"]="owned-process-tree-termination";report["completeDescendantEnumeration"]=false;app.Dispose();}
        public Dictionary<string,object> Run(){
            report["policySelfTestsPassed"]=PolicySelfTests();
            report["ok"]=false;report["actualApplicationTested"]=false;report["actualRegisteredAltD"]=true;report["fakeIpcUsed"]=false;report["generatedWpfSource"]=true;report["thirdPartyApplicationTested"]=false;report["userContentRead"]=false;report["sourceUiaWarmupUsed"]=false;report["translationBackend"]="generated-loopback-mock";report["requiredCases"]=3;report["cases"]=cases;report["sameHotkeyRetries"]=0;
            Need(System.Windows.Application.Current==null,"EXISTING_WPF_APPLICATION_REFUSED");foreach(Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))using(p)Need(p.HasExited,"EXISTING_ECHOLINGO_PROCESS_REFUSED");Need(Forms.Clipboard.GetDataObject()==null||Forms.Clipboard.GetDataObject().GetFormats(false).Length==0,"FRESH_EMPTY_CLIPBOARD_REQUIRED");
            var wpf=new System.Windows.Application();wpf.ShutdownMode=ShutdownMode.OnExplicitShutdown;
            try{SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"PHYSICAL_COORDINATES_REQUIRED");Need(Forms.Screen.PrimaryScreen.Bounds.Width>=1024&&Forms.Screen.PrimaryScreen.Bounds.Height>=600,"GENERATED_SOURCE_DESKTOP_TOO_SMALL");
                string roaming=Path.Combine(Folder("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"),Identifier),local=Path.Combine(Folder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"),Identifier),root=Path.Combine(Path.GetTempPath(),"echolingo-wpf-selection-"+token);Claim(roaming);Claim(local);Claim(root);history=Path.Combine(roaming,"history.json");provider="generated-wpf-"+token;mock=new Mock(texts);
                var settings=new Dictionary<string,object>{{"providers",new object[]{new Dictionary<string,object>{{"id",provider},{"name","Generated WPF loopback mock"},{"kind","libretranslate"},{"baseUrl",mock.Url},{"enabled",true},{"model",""},{"prompt",""}}}},{"ocrProviders",new object[0]},{"sourceLanguage","auto"},{"targetLanguage","auto"},{"languageDirectionVersion",1},{"shortcutDefaultsVersion",1},{"saveHistory",true},{"maxHistory",100},{"theme","light"},{"autoHideSeconds",0},{"shortcuts",new Dictionary<string,object>{{"selection","Alt+D"},{"silentOcr",""},{"ocr",""},{"capture",""},{"input",""}}}};File.WriteAllText(Path.Combine(roaming,"settings.json"),Json.Serialize(settings),new UTF8Encoding(false));
                source=new Window {Title="Generated WPF selection source",Left=12,Top=8,Width=740,Height=230,ResizeMode=ResizeMode.NoResize,WindowStartupLocation=WindowStartupLocation.Manual};editor=new RichTextBox {IsReadOnly=true,IsDocumentEnabled=true,FontFamily=new FontFamily("Segoe UI"),FontSize=18,Padding=new Thickness(10),VerticalScrollBarVisibility=ScrollBarVisibility.Disabled};var document=new FlowDocument {PagePadding=new Thickness(0)};runs=new Run[texts.Length];for(int i=0;i<texts.Length;i++){runs[i]=new Run(texts[i]);document.Blocks.Add(new Paragraph(runs[i]) {Margin=new Thickness(0,4,0,4)});}editor.Document=document;source.Content=editor;
                editor.AddHandler(UIElement.PreviewMouseDownEvent,new MouseButtonEventHandler(delegate(object sender,MouseButtonEventArgs e){if(e.ChangedButton==MouseButton.Left)downs++;}),true);editor.AddHandler(UIElement.PreviewMouseUpEvent,new MouseButtonEventHandler(delegate(object sender,MouseButtonEventArgs e){if(e.ChangedButton==MouseButton.Left)ups++;}),true);
                source.ContentRendered+=delegate{if(Interlocked.Exchange(ref sourceStarted,1)!=0)return;sourceHwnd=new WindowInteropHelper(source).Handle;documentBefore=new TextRange(document.ContentStart,document.ContentEnd).Text;editor.TextChanged+=delegate{changes++;};Thread worker=new Thread(delegate(){try{Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"WORKER_PHYSICAL_COORDINATES_REQUIRED");Start(local,root);Case(0,false);Case(1,false);Pin();Case(2,true);string framework=ui.Call(delegate{return AutomationElement.FromHandle(sourceHwnd).Current.FrameworkId;},5000);report["postCasesSourceFrameworkId"]=framework;Need(framework=="WPF","ACTUAL_SOURCE_FRAMEWORK_NOT_WPF");report["ok"]=true;}catch(Exception e){report["failedStage"]=stage;report["errorType"]=e.GetType().Name;report["error"]=e.Message;}finally{try{if(leftOwned){INPUT up=new INPUT();up.type=0;up.data.mouse.flags=4;SendInput(1,new INPUT[]{up},Marshal.SizeOf(typeof(INPUT)));}if(keysOwned)SendInput(2,new INPUT[]{Key(0x44,true),Key(0x12,true)},Marshal.SizeOf(typeof(INPUT)));Stop();}catch(Exception e){cleanupErrors.Add(e.Message);}try{if(ui!=null)ui.Close();}catch(Exception e){cleanupErrors.Add(e.Message);}Ui(delegate{try{if(seeded){string outcome=ClearVerifiedClipboard();report["clipboardCleanupOwnershipOutcome"]=outcome;bool ours=outcome=="verified-seed-cleared";report["generatedClipboardCleanupConfirmed"]=ours;if(!ours)cleanupErrors.Add("GENERATED_CLIPBOARD_OWNERSHIP_CHANGED_PRESERVED");}}catch(Exception e){cleanupErrors.Add("CLIPBOARD_CLEANUP:"+e.GetType().Name);}finally{wpf.Shutdown();}});}});worker.IsBackground=true;worker.SetApartmentState(ApartmentState.MTA);worker.Start();};wpf.Run(source);
            }catch(Exception e){report["errorType"]=e.GetType().Name;report["error"]=e.Message;}
            finally{try{if(mock!=null)mock.Dispose();}catch(Exception e){cleanupErrors.Add(e.Message);}for(int i=owned.Count-1;i>=0;i--)try{Remove(owned[i]);}catch(Exception e){cleanupErrors.Add(e.Message);}report["cleanupErrors"]=cleanupErrors;report["ownedDirectoriesRemoved"]=cleanupErrors.Count==0;report["actualHotkeysSent"]=hotkeys;report["executedCases"]=cases.Count;int passed=0;foreach(Dictionary<string,object> row in cases)if(Convert.ToBoolean(row["ok"]))passed++;report["passedCases"]=passed;report["ok"]=Convert.ToBoolean(report["ok"])&&passed==3&&cleanupErrors.Count==0;}
            return report;
        }
    }
    public static Dictionary<string,object> Run(string executable){return new Fixture(executable).Run();}
}
