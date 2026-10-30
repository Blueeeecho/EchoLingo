// Ephemeral generated-fixture serialization roundtrip only. Not a keyboard,
// browser, copy-owner guard, or proof that intermittent clipboard failures are fixed.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class ClipboardSnapshotSmoke {
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern int CountClipboardFormats();
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
    [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
    [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr handle);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr handle);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr handle);
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer{MaxJsonLength=65536};
    static readonly string[] Prefixes={"copyHtml","copyUnicode","copyRtf"};
    static readonly string[] Suffixes={"ProbeEnabled","SnapshotOlePresent","SnapshotOleChars","SnapshotEqual","RestoreEqual","SnapshotError","SnapshotSeedVerified","SnapshotPresent","SnapshotAllocatedBytes","SnapshotPayloadBytes","SnapshotSequenceChanged","RestoreError","RestoreSeedVerified","RestorePresent","RestoreAllocatedBytes","RestorePayloadBytes","RestoreSequenceChanged"};
    static void Need(bool condition){if(!condition)throw new InvalidOperationException("SNAPSHOT_FIXTURE_BOUNDARY");}
    static string Marker(string nonce){return "EchoLingo.ClipboardProbe."+nonce;}
    static void ValidateNonce(string nonce){Need(nonce!=null&&nonce.Length==32);foreach(char c in nonce)Need(c>='0'&&c<='9'||c>='a'&&c<='f');}
    static byte[] VerifiedDll(string path,string expected){
        Need(expected!=null&&expected.Length==64);foreach(char c in expected)Need(c>='0'&&c<='9'||c>='a'&&c<='f');
        FileInfo file=new FileInfo(path);Need(file.Exists&&file.Length>0&&file.Length<=32*1024*1024&&(file.Attributes&FileAttributes.ReparsePoint)==0);
        byte[] bytes;
        using(FileStream stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)){
            Need(stream.Length>0&&stream.Length<=32*1024*1024);bytes=new byte[(int)stream.Length];int offset=0;
            while(offset<bytes.Length){int count=stream.Read(bytes,offset,bytes.Length-offset);Need(count>0);offset+=count;}
            Need(stream.ReadByte()==-1);
        }
        using(SHA256 sha=SHA256.Create())Need(BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant()==expected);return bytes;
    }
    static byte[] LockedBytes(uint format,int maximum,out long size,out int error){
        size=-1;error=0;IntPtr handle=GetClipboardData(format);if(handle==IntPtr.Zero){error=3;return null;}
        ulong allocation=GlobalSize(handle).ToUInt64();size=(long)Math.Min(allocation,(ulong)maximum+1);
        if(allocation==0||allocation>(ulong)maximum){error=4;return null;}
        IntPtr memory=GlobalLock(handle);if(memory==IntPtr.Zero){error=5;return null;}
        try{byte[] bytes=new byte[(int)allocation];Marshal.Copy(memory,bytes,0,bytes.Length);return bytes;}finally{GlobalUnlock(handle);}
    }
    static bool LockedMarker(string nonce){
        long size;int error;byte[] bytes=LockedBytes(RegisterClipboardFormat(Marker(nonce)),256,out size,out error);
        if(bytes==null||bytes.Length<32)return false;for(int i=0;i<32;i++)if(bytes[i]!=(byte)nonce[i])return false;return true;
    }
    static int Terminated(byte[] bytes,bool unicode){
        if(bytes==null||bytes.Length>65536)return -1;
        if(unicode){for(int i=0;i+1<bytes.Length;i+=2)if(bytes[i]==0&&bytes[i+1]==0)return i+2;return -1;}
        int end=Array.IndexOf(bytes,(byte)0);return end<0?-1:end+1;
    }
    static void Format(Dictionary<string,object> result,string key,uint format,string expected,Encoding encoding,bool unicode){
        try{long size;int error;byte[] bytes=LockedBytes(format,65536,out size,out error),wanted=encoding.GetBytes(expected+"\0");
            result[key+"AllocationBytes"]=size;result[key+"Error"]=error;result[key+"ExpectedBytes"]=wanted.Length;
            int end=Terminated(bytes,unicode);result[key+"TerminatedBytes"]=end;
            if(bytes!=null&&end<0)result[key+"Error"]=6;
            bool equal=end==wanted.Length;if(equal)for(int i=0;i<end;i++)if(bytes[i]!=wanted[i]){equal=false;break;}
            result[key+"Equal"]=equal?1:0;
        }catch{result[key+"Error"]=8;}
    }
    static Dictionary<string,object> Raw(DataObject expected,string nonce){
        var result=new Dictionary<string,object>{{"lock",0},{"nonceVerified",0},{"error",0},{"sequenceBeforeLock",GetClipboardSequenceNumber()}};
        foreach(string key in new string[]{"unicode","html","rtf"}){result[key+"Equal"]=0;result[key+"Error"]=0;}
        if(!OpenClipboard(IntPtr.Zero)){result["error"]=1;return result;}
        result["lock"]=1;
        try{if(!LockedMarker(nonce)){result["error"]=2;return result;}result["nonceVerified"]=1;
            Format(result,"unicode",13,(string)expected.GetData(DataFormats.UnicodeText,false),Encoding.Unicode,true);
            Format(result,"html",RegisterClipboardFormat(DataFormats.Html),(string)expected.GetData(DataFormats.Html,false),Encoding.UTF8,false);
            // Fixed seed is ASCII; equivalent to Framework's ACP representation.
            Format(result,"rtf",RegisterClipboardFormat(DataFormats.Rtf),(string)expected.GetData(DataFormats.Rtf,false),Encoding.ASCII,false);
        }catch{result["error"]=8;}finally{result["sequenceWhileLocked"]=GetClipboardSequenceNumber();CloseClipboard();result["sequenceAfterUnlock"]=GetClipboardSequenceNumber();}return result;
    }
    static bool OwnGeneration(string nonce,uint sequence){
        if(!OpenClipboard(IntPtr.Zero))return false;
        try{return GetClipboardSequenceNumber()==sequence&&LockedMarker(nonce)&&GetClipboardSequenceNumber()==sequence;}finally{CloseClipboard();}
    }
    static bool ClearOwn(string nonce,uint sequence){
        if(!OpenClipboard(IntPtr.Zero))return false;
        try{if(GetClipboardSequenceNumber()!=sequence||!LockedMarker(nonce)||GetClipboardSequenceNumber()!=sequence)return false;return EmptyClipboard();}finally{CloseClipboard();}
    }
    static bool Empty(){if(!OpenClipboard(IntPtr.Zero))return false;try{return CountClipboardFormats()==0;}finally{CloseClipboard();}}
    static DataObject Seed(string nonce){
        Need(Empty());DataObject data=new DataObject();
        // Keep original browser fixture insertion order and exact synthetic strings.
        data.SetData(DataFormats.UnicodeText,false,"Generated browser clipboard original 24680");
        data.SetData(DataFormats.Html,false,"<p>Generated browser rich original 24680</p>");
        data.SetData(DataFormats.Rtf,false,"{\\rtf1 Generated browser rich original 24680}");
        data.SetData(Marker(nonce),false,new MemoryStream(Encoding.ASCII.GetBytes(nonce)));
        Clipboard.SetDataObject(data,true,0,0);return data;
    }
    static Dictionary<string,object> FirstOle(DataObject expected,string nonce,uint generation){
        uint before=GetClipboardSequenceNumber();Need(before==generation);IDataObject actual=Clipboard.GetDataObject();bool matches=actual!=null;
        var formats=new List<Dictionary<string,object>>();
        // Same oracle order and single actual.GetData(format,false) as browser bridge.
        foreach(string format in expected.GetFormats(false)){
            if(format==Marker(nonce))continue;
            object wanted=expected.GetData(format,false),received=actual==null?null:actual.GetData(format,false);
            bool equal=Object.Equals(wanted,received);matches=matches&&equal;
            int kind=format==DataFormats.UnicodeText?1:format==DataFormats.Html?2:format==DataFormats.Rtf?3:0;Need(kind!=0);
            formats.Add(new Dictionary<string,object>{{"formatKind",kind},{"present",received==null?0:1},{"stringType",received is string?1:0},{"expectedChars",wanted is string?((string)wanted).Length:-1},{"actualChars",received is string?((string)received).Length:-1},{"equal",equal?1:0}});
        }
        uint after=GetClipboardSequenceNumber();
        var result=new Dictionary<string,object>{{"firstVerdict",matches?1:0},{"formats",formats},{"sequenceBeforeRead",before},{"sequenceAfterRead",after},{"retryAttempts",0}};
        // Later GetClipboardData may trigger delayed rendering. It cannot prove
        // the earlier OLE representation and never upgrades the first verdict.
        bool generationValid=after==generation;result["generationValid"]=generationValid?1:0;
        if(!matches&&generationValid)result["rawAfterFirstFailure"]=Raw(expected,nonce);
        else if(!generationValid)result["rawSkippedGenerationChange"]=1;return result;
    }
    static Dictionary<string,object> Health(Assembly assembly){
        Type type=assembly.GetType("CaptureHealth",true);MethodInfo snapshot=type.GetMethod("Snapshot",BindingFlags.Public|BindingFlags.Static,null,Type.EmptyTypes,null);Need(snapshot!=null);
        var raw=(Dictionary<string,long>)snapshot.Invoke(null,null);var clean=new Dictionary<string,object>();
        foreach(string prefix in Prefixes)foreach(string suffix in Suffixes){long value;Need(raw.TryGetValue(prefix+suffix,out value)&&value>=0&&value<=10000000);clean[prefix+suffix]=value;}return clean;
    }
    // saved formatKind: 1 HTML, 2 RTF, 3 Unicode, 4 Text, 5 OEM.
    static List<Dictionary<string,object>> SavedKnownFormats(DataObject saved){
        string[] formats=saved.GetFormats(false),known={DataFormats.Html,DataFormats.Rtf,DataFormats.UnicodeText,DataFormats.Text,DataFormats.OemText};
        var result=new List<Dictionary<string,object>>();
        for(int kind=0;kind<known.Length;kind++){
            int index=Array.IndexOf(formats,known[kind]);object value=index<0?null:saved.GetData(known[kind],false);
            result.Add(new Dictionary<string,object>{{"formatKind",kind+1},{"index",index},{"present",index>=0?1:0},{"stringType",value is string?1:0},{"chars",value is string?((string)value).Length:-1}});
        }
        return result;
    }
    public static Dictionary<string,object> Child(string dll,string hash){
        var result=new Dictionary<string,object>{{"ok",0},{"stage",1},{"errorKind",0},{"processId",Process.GetCurrentProcess().Id},{"resourcesCount",0},{"resourcesDisposed",0},{"framework",Environment.Version.ToString()},{"dllSha256",hash}};
        List<IDisposable> resources=new List<IDisposable>();Assembly assembly=null;int disposed=0;Stopwatch clock=Stopwatch.StartNew();
        try{
            Need(Thread.CurrentThread.GetApartmentState()==ApartmentState.STA);
            string nonce=Environment.GetEnvironmentVariable("ECHOLINGO_CLIPBOARD_DIAGNOSTIC_NONCE");ValidateNonce(nonce);
            uint sequence;Need(UInt32.TryParse(Environment.GetEnvironmentVariable("ECHOLINGO_SNAPSHOT_SEQUENCE"),out sequence));
            assembly=Assembly.Load(VerifiedDll(dll,hash));Type native=assembly.GetType("EchoLingoNative",true),probeType=assembly.GetType("ClipboardHtmlProbe",true);
            MethodInfo method=native.GetMethod("SnapshotClipboard",BindingFlags.NonPublic|BindingFlags.Static,null,new Type[]{typeof(List<IDisposable>),probeType.MakeByRefType()},null);
            Need(method!=null&&method.ReturnType==typeof(DataObject));
            MethodInfo restored=probeType.GetMethod("Restored",BindingFlags.Public|BindingFlags.Instance,null,Type.EmptyTypes,null);Need(restored!=null&&restored.ReturnType==typeof(void));
            Need(OwnGeneration(nonce,sequence));result["stage"]=2;result["snapshotStartMilliseconds"]=clock.ElapsedMilliseconds;result["sequenceBeforeSnapshot"]=sequence;
            object[] args={resources,null};DataObject saved=(DataObject)method.Invoke(null,args);object probe=args[1];Need(saved!=null&&probe!=null);
            result["stage"]=3;result["snapshotEndMilliseconds"]=clock.ElapsedMilliseconds;result["sequenceAfterSnapshot"]=GetClipboardSequenceNumber();Need(OwnGeneration(nonce,sequence));
            // Only the snapshot-owned in-memory DataObject; no further OLE read.
            result["savedKnownFormats"]=SavedKnownFormats(saved);
            result["stage"]=4;result["restoreStartMilliseconds"]=clock.ElapsedMilliseconds;Clipboard.SetDataObject(saved,true,0,0); // exactly one production restore call
            result["restoredSequence"]=GetClipboardSequenceNumber();result["restoreEndMilliseconds"]=clock.ElapsedMilliseconds;result["stage"]=5;restored.Invoke(probe,null);
            result["stage"]=6;
        }catch{result["errorKind"]=1;}
        finally{
            result["resourcesCount"]=resources.Count;result["disposeStartMilliseconds"]=clock.ElapsedMilliseconds;
            try{foreach(IDisposable resource in resources){resource.Dispose();disposed++;}}
            catch{result["errorKind"]=2;}
            result["resourcesDisposed"]=disposed;result["disposeEndMilliseconds"]=clock.ElapsedMilliseconds;result["sequenceAfterResources"]=GetClipboardSequenceNumber();
            if(assembly!=null)try{result["probe"]=Health(assembly);}catch{result["errorKind"]=3;}
        }
        if(Convert.ToInt32(result["errorKind"])==0&&Convert.ToInt32(result["stage"])==6){result["stage"]=7;result["ok"]=1;}
        return result;
    }
    static string Quote(string value){Need(value!=null&&!value.Contains("\"")&&!value.Contains("\r")&&!value.Contains("\n"));return "\""+value+"\"";}
    static string ReadBounded(StreamReader reader){char[] chars=new char[1024];StringBuilder result=new StringBuilder();int count;while((count=reader.Read(chars,0,chars.Length))>0){Need(result.Length+count<=65536);result.Append(chars,0,count);}return result.ToString();}
    static Dictionary<string,object> RunChild(string script,string dll,string hash,string nonce,uint sequence,Dictionary<string,object> round,out bool exited){
        exited=true;Process child=null;
        try{
            string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe");Need(File.Exists(powershell));
            ProcessStartInfo start=new ProcessStartInfo(powershell,"-NoProfile -STA -ExecutionPolicy Bypass -File "+Quote(script)+" -NativeAssemblyPath "+Quote(dll)+" -ExpectedNativeSha256 "+Quote(hash)+" -Child");
            start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;start.StandardOutputEncoding=new UTF8Encoding(false);start.StandardErrorEncoding=new UTF8Encoding(false);
            start.EnvironmentVariables["ECHOLINGO_CLIPBOARD_DIAGNOSTIC_NONCE"]=nonce;start.EnvironmentVariables["ECHOLINGO_SNAPSHOT_SEQUENCE"]=sequence.ToString();start.EnvironmentVariables.Remove("ECHOLINGO_SELECTION_TRACE");
            child=Process.Start(start);exited=false;round["childProcessId"]=child.Id;Need(child.Id!=Process.GetCurrentProcess().Id);
            Task<string> stdout=Task.Factory.StartNew(()=>ReadBounded(child.StandardOutput));Task<string> stderr=Task.Factory.StartNew(()=>ReadBounded(child.StandardError));Stopwatch clock=Stopwatch.StartNew();
            while(!child.HasExited&&clock.ElapsedMilliseconds<30000&&!stdout.IsFaulted&&!stderr.IsFaulted){Application.DoEvents();Thread.Sleep(2);}
            if(!child.HasExited){round["childTerminatedByFixture"]=1;child.Kill();}
            exited=child.WaitForExit(5000);round["childExitConfirmed"]=exited?1:0;Need(exited);
            Need(Task.WaitAll(new Task[]{stdout,stderr},5000));round["childExitCode"]=child.ExitCode;round["childMilliseconds"]=clock.ElapsedMilliseconds;round["stderrChars"]=stderr.Result.Length;
            Need(stdout.Result.Length<=65536&&stderr.Result.Length==0);var result=Json.Deserialize<Dictionary<string,object>>(stdout.Result.TrimStart('\ufeff'));
            Need(result!=null&&Convert.ToInt32(result["processId"])==child.Id&&Convert.ToString(result["dllSha256"])==hash);
            return result;
        }finally{if(child!=null){if(!exited){try{if(!child.HasExited)child.Kill();exited=child.WaitForExit(5000);}catch{}}round["childExitConfirmed"]=exited?1:0;child.Dispose();}}
    }
    public static Dictionary<string,object> Parent(string script,string dll,string hash){
        Need(Thread.CurrentThread.GetApartmentState()==ApartmentState.STA);VerifiedDll(dll,hash);Need(Empty());
        var rounds=new List<Dictionary<string,object>>();var result=new Dictionary<string,object>{{"ok",0},{"roundLimit",12},{"rounds",rounds},{"framework",Environment.Version.ToString()},{"dllSha256",hash},{"parentProcessId",Process.GetCurrentProcess().Id},{"separateProcess",1},{"keyboardRequests",0},{"browserRequests",0},{"serializationRoundtripOnly",1},{"rawMayRender",1}};
        for(int index=1;index<=12;index++){
            string nonce=Guid.NewGuid().ToString("N");DataObject expected=null;uint owned=0;bool childExited=true,passed=false;
            var round=new Dictionary<string,object>{{"round",index},{"stage",1},{"ok",0},{"errorKind",0},{"childTerminatedByFixture",0},{"cleanup",0}};rounds.Add(round);
            try{
                expected=Seed(nonce);owned=GetClipboardSequenceNumber();round["stage"]=2;var seed=Raw(expected,nonce);round["seed"]=seed;
                bool seedOk=Convert.ToInt32(seed["unicodeEqual"])==1&&Convert.ToInt32(seed["htmlEqual"])==1&&Convert.ToInt32(seed["rtfEqual"])==1;round["seedIntegrity"]=seedOk?1:0;
                if(!seedOk){round["errorKind"]=2;break;}
                Need(OwnGeneration(nonce,owned));round["stage"]=3;childExited=false;var child=RunChild(script,dll,hash,nonce,owned,round,out childExited);round["child"]=child;
                if(child.ContainsKey("restoredSequence"))owned=Convert.ToUInt32(child["restoredSequence"]);
                Need(childExited&&Convert.ToInt32(round["childExitCode"])==0&&Convert.ToInt32(child["ok"])==1);round["stage"]=4;
                if(!OwnGeneration(nonce,owned)){round["errorKind"]=4;round["generationInvalidBeforeOle"]=1;break;}
                Dictionary<string,object> first;
                try{first=FirstOle(expected,nonce,owned);}
                catch{
                    bool current=OwnGeneration(nonce,owned);
                    first=new Dictionary<string,object>{{"firstVerdict",0},{"oleReadError",1},{"retryAttempts",0},{"generationValid",current?1:0}};
                    if(current)first["rawAfterFirstFailure"]=Raw(expected,nonce);else first["rawSkippedGenerationChange"]=1;
                }
                round["firstOle"]=first;passed=Convert.ToInt32(first["firstVerdict"])==1&&Convert.ToInt32(first["generationValid"])==1;round["stage"]=5;
                if(!passed)round["errorKind"]=Convert.ToInt32(first["generationValid"])==1?3:4;
            }catch{if(Convert.ToInt32(round["errorKind"])==0)round["errorKind"]=1;}
            finally{
                // Never clear an unconfirmed generation or while our child is alive.
                if(expected!=null&&childExited)round["cleanup"]=ClearOwn(nonce,owned)?1:0;
                if(expected!=null){IDisposable marker=expected.GetData(Marker(nonce),false) as IDisposable;if(marker!=null)marker.Dispose();}
            }
            passed=passed&&Convert.ToInt32(round["errorKind"])==0&&Convert.ToInt32(round["cleanup"])==1;round["ok"]=passed?1:0;if(!passed)break;
        }
        result["roundsCompleted"]=rounds.Count;result["ok"]=rounds.Count==12&&Convert.ToInt32(rounds[11]["ok"])==1?1:0;return result;
    }
}
