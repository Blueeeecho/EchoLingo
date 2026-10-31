// Generated clipboard data only, on a fresh hosted Windows desktop. This tests
// the production snapshot/restore representation, not keyboard or UIA behavior.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public static class WindowsClipboardMarkerFixture {
    const string SmartMarker = "WebKit Smart Paste Format";
    const string BinaryFormat = "EchoLingo.Generated.ClipboardMarkerFixture.Binary";
    const string OwnershipFormat = "EchoLingo.Generated.ClipboardMarkerFixture.Ownership";
    [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern int CountClipboardFormats();
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
    [DllImport("user32.dll")] static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint format, IntPtr data);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr memory);
    [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr memory);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);

    // Chromium intentionally leaves the smart-paste marker without a payload.
    // Model its owner, including the no-op delayed-render notifications.
    sealed class OwnerWindow : NativeWindow, IDisposable {
        public OwnerWindow() {
            CreateHandle(new CreateParams { Caption="EchoLingo generated clipboard owner", Parent=new IntPtr(-3) });
        }
        protected override void WndProc(ref Message message) {
            if(message.Msg==0x0305 || message.Msg==0x0306) { message.Result=IntPtr.Zero; return; }
            base.WndProc(ref message);
        }
        public void Dispose() { DestroyHandle(); }
    }
    static void Need(bool condition) {
        if(!condition) throw new InvalidOperationException("GENERATED_CLIPBOARD_MARKER_ASSERTION");
    }
    static uint Format(string name) { uint value=RegisterClipboardFormat(name); Need(value!=0); return value; }
    static bool Equal(byte[] left, byte[] right) {
        if(left==null || right==null || left.Length!=right.Length) return false;
        for(int i=0;i<left.Length;i++) if(left[i]!=right[i]) return false;
        return true;
    }
    static byte[] LockedBytes(uint format) {
        IntPtr handle=GetClipboardData(format); Need(handle!=IntPtr.Zero);
        ulong size=GlobalSize(handle).ToUInt64(); Need(size>0 && size<=65536);
        IntPtr memory=GlobalLock(handle); Need(memory!=IntPtr.Zero);
        try { byte[] bytes=new byte[(int)size]; Marshal.Copy(memory,bytes,0,bytes.Length); return bytes; }
        finally { GlobalUnlock(handle); }
    }
    static bool LockedOwn(byte[] nonce) {
        if(!IsClipboardFormatAvailable(Format(OwnershipFormat))) return false;
        try { return Equal(LockedBytes(Format(OwnershipFormat)),nonce); }
        catch { return false; }
    }
    static bool OwnGeneration(byte[] nonce, uint generation) {
        if(!OpenClipboard(IntPtr.Zero)) return false;
        try { return GetClipboardSequenceNumber()==generation && LockedOwn(nonce)
            && GetClipboardSequenceNumber()==generation; }
        finally { CloseClipboard(); }
    }
    static bool ClearOwn(byte[] nonce, uint generation) {
        if(!OpenClipboard(IntPtr.Zero)) return false;
        try {
            if(GetClipboardSequenceNumber()!=generation || !LockedOwn(nonce)
                || GetClipboardSequenceNumber()!=generation) return false;
            return EmptyClipboard();
        } finally { CloseClipboard(); }
    }
    static void RequireEmpty() {
        Need(OpenClipboard(IntPtr.Zero));
        try { Need(CountClipboardFormats()==0); }
        finally { CloseClipboard(); }
    }
    static void WriteBytes(uint format, byte[] bytes) {
        Need(bytes!=null && bytes.Length>0);
        IntPtr handle=GlobalAlloc(0x42,new UIntPtr((uint)bytes.Length)); Need(handle!=IntPtr.Zero);
        bool transferred=false;
        try {
            IntPtr memory=GlobalLock(handle); Need(memory!=IntPtr.Zero);
            try { Marshal.Copy(bytes,0,memory,bytes.Length); }
            finally { GlobalUnlock(handle); }
            Need(SetClipboardData(format,handle)!=IntPtr.Zero); transferred=true;
        } finally { if(!transferred) GlobalFree(handle); }
    }
    static byte[] Terminated(string value, Encoding encoding) { return encoding.GetBytes(value+"\0"); }
    static byte[] Html() {
        const string prefix="<html><body><!--StartFragment-->";
        const string fragment="<p>Generated smart-paste preservation 24680</p>";
        const string suffix="<!--EndFragment--></body></html>";
        const string template="Version:0.9\r\nStartHTML:{0:D10}\r\nEndHTML:{1:D10}\r\nStartFragment:{2:D10}\r\nEndFragment:{3:D10}\r\n";
        int start=String.Format(template,0,0,0,0).Length;
        string header=String.Format(template,start,start+prefix.Length+fragment.Length+suffix.Length,
            start+prefix.Length,start+prefix.Length+fragment.Length);
        return Terminated(header+prefix+fragment+suffix,Encoding.ASCII);
    }
    static byte[] StreamBytes(object value) {
        Stream stream=value as Stream; Need(stream!=null && stream.CanSeek);
        long position=stream.Position;
        try { stream.Position=0; using(MemoryStream copy=new MemoryStream()) { stream.CopyTo(copy); return copy.ToArray(); } }
        finally { stream.Position=position; }
    }
    static bool PayloadMatches(byte[] actual, byte[] expected, bool terminated) {
        if(!terminated) return Equal(actual,expected);
        // GlobalAlloc may reserve padding; compare the complete encoded text,
        // including its terminator, and require the remainder to stay zero.
        if(actual==null || actual.Length<expected.Length) return false;
        for(int i=0;i<expected.Length;i++) if(actual[i]!=expected[i]) return false;
        for(int i=expected.Length;i<actual.Length;i++) if(actual[i]!=0) return false;
        return true;
    }
    static void VerifyPayloads(byte[] nonce, uint generation, Dictionary<uint,byte[]> expected,
        uint binary, uint ownership) {
        Need(OpenClipboard(IntPtr.Zero));
        try {
            Need(GetClipboardSequenceNumber()==generation && LockedOwn(nonce));
            foreach(KeyValuePair<uint,byte[]> pair in expected)
                Need(PayloadMatches(LockedBytes(pair.Key),pair.Value,pair.Key!=binary && pair.Key!=ownership));
            Need(GetClipboardSequenceNumber()==generation);
        } finally { CloseClipboard(); }
    }
    static long Health(MethodInfo snapshot, string field) {
        Type health=snapshot.DeclaringType.Assembly.GetType("CaptureHealth",true);
        var values=(Dictionary<string,long>)health.GetMethod("Snapshot",BindingFlags.Public|BindingFlags.Static).Invoke(null,null);
        long value; Need(values.TryGetValue(field,out value)); return value;
    }
    static void RequireCloneRejected(MethodInfo snapshot, uint generation, bool changed) {
        MethodInfo clone=snapshot.DeclaringType.GetMethod("CloneClipboardValue",BindingFlags.NonPublic|BindingFlags.Static,
            null,new Type[]{typeof(string),typeof(object),typeof(uint)},null);
        Need(clone!=null); bool rejected=false;
        try { clone.Invoke(null,new object[]{SmartMarker,null,generation}); }
        catch(TargetInvocationException error) {
            Need(error.InnerException is InvalidOperationException);
            if(changed) Need(error.InnerException.Message.StartsWith("CLIPBOARD_CHANGED:",StringComparison.Ordinal));
            else {
                FieldInfo kind=error.InnerException.GetType().GetField("Kind",BindingFlags.Public|BindingFlags.Instance);
                Need(kind!=null && (int)kind.GetValue(error.InnerException)==10);
            }
            rejected=true;
        }
        Need(rejected);
    }
    static Dictionary<string,object> RunCase(OwnerWindow owner, MethodInfo snapshot, int kind) {
        // Cases: exact presence-only marker, unknown null, near-name null,
        // exact marker with real bytes (which must never be normalized).
        string marker=kind==2 ? "EchoLingo.Generated.UnknownNullMarker"
            : kind==3 ? SmartMarker+".GeneratedUnknown" : SmartMarker;
        uint markerId=Format(marker), binary=Format(BinaryFormat), ownership=Format(OwnershipFormat);
        byte[] nonce=Encoding.ASCII.GetBytes(Guid.NewGuid().ToString("N"));
        byte[] binaryBytes={0,1,2,3,0,255,128,127,32,0,13,10,42,43,44,45};
        byte[] markerBytes={9,0,8,0,7,0,6,0};
        Dictionary<uint,byte[]> expected=new Dictionary<uint,byte[]> {
            {ownership,nonce}, {13,Terminated("Generated clipboard text 24680 \u4e2d\u6587",Encoding.Unicode)},
            {Format(DataFormats.Html),Html()},
            {Format(DataFormats.Rtf),Terminated("{\\rtf1 Generated clipboard rich text 24680}",Encoding.ASCII)},
            {binary,binaryBytes}
        };
        List<IDisposable> resources=new List<IDisposable>();
        Dictionary<string,object> result=new Dictionary<string,object> {
            {"caseKind",kind},{"ok",false},{"stage",1},{"errorKind",0},{"cleanup",false},
            {"snapshotRejected",false},{"nullMarkerObserved",false},{"payloadsPreserved",false},
            {"generationUnchangedBeforeRestore",false},{"markerPresentAfterRestore",false}
        };
        uint generation=0; bool seeded=false;
        try {
            RequireEmpty(); Need(OpenClipboard(owner.Handle));
            try {
                Need(CountClipboardFormats()==0); Need(EmptyClipboard());
                // Ownership is first, so a later failed seed remains identifiable.
                WriteBytes(ownership,nonce); seeded=true;
                foreach(KeyValuePair<uint,byte[]> pair in expected) if(pair.Key!=ownership) WriteBytes(pair.Key,pair.Value);
                if(kind==4) WriteBytes(markerId,markerBytes);
                else {
                    // A NULL payload also yields a NULL return on success.
                    SetClipboardData(markerId,IntPtr.Zero);
                    Need(IsClipboardFormatAvailable(markerId));
                }
            } finally { CloseClipboard(); generation=GetClipboardSequenceNumber(); }
            result["stage"]=2; Need(OwnGeneration(nonce,generation));
            if(kind==4) {
                Need(OpenClipboard(IntPtr.Zero));
                try { Need(GetClipboardSequenceNumber()==generation); markerBytes=LockedBytes(markerId); }
                finally { CloseClipboard(); }
                // OLE null must never normalize a native nonempty same-name
                // payload. A stale generation must also reject before reading.
                RequireCloneRejected(snapshot,generation,false);
                Need(OwnGeneration(nonce,generation));
            }
            RequireCloneRejected(snapshot,unchecked(generation-1),true);
            Need(OwnGeneration(nonce,generation));
            IDataObject original=Clipboard.GetDataObject(); Need(original!=null);
            string[] formats=original.GetFormats(false); Need(Array.IndexOf(formats,marker)>=0);
            object originalMarker=original.GetData(marker,false);
            if(kind==4) Need(Equal(StreamBytes(originalMarker),markerBytes));
            else { Need(originalMarker==null); result["nullMarkerObserved"]=true; }
            Need(OwnGeneration(nonce,generation));
            // Preserve the full source allocation for binary and nonce data.
            Need(OpenClipboard(IntPtr.Zero));
            try { Need(GetClipboardSequenceNumber()==generation && LockedOwn(nonce));
                expected[binary]=LockedBytes(binary); expected[ownership]=LockedBytes(ownership); }
            finally { CloseClipboard(); }
            result["stage"]=3;
            DataObject saved=null; bool rejected=false;
            try { saved=(DataObject)snapshot.Invoke(null,new object[]{resources,null}); }
            catch(TargetInvocationException error) {
                Need(error.InnerException is InvalidOperationException); rejected=true;
            }
            result["snapshotRejected"]=rejected;
            Need(OwnGeneration(nonce,generation)); result["generationUnchangedBeforeRestore"]=true;
            if(kind==2 || kind==3) {
                Need(rejected && saved==null);
                Need(Health(snapshot,"copySnapshotStage")==4 && Health(snapshot,"copySnapshotFailureKind")==4
                    && Health(snapshot,"copySnapshotFormatKind")==7);
                VerifyPayloads(nonce,generation,expected,binary,ownership);
                Need(IsClipboardFormatAvailable(markerId));
                result["payloadsPreserved"]=true; result["stage"]=7;
            } else {
                Need(!rejected && saved!=null); result["stage"]=4;
                Need(Health(snapshot,"copySnapshotStage")==6 && Health(snapshot,"copySnapshotFailureKind")==0
                    && Health(snapshot,"copySnapshotEmptyMarkers")== (kind==1 ? 1 : 0));
                string[] savedFormats=saved.GetFormats(false);
                foreach(string format in formats) Need(Array.IndexOf(savedFormats,format)>=0);
                byte[] savedMarker=StreamBytes(saved.GetData(marker,false));
                Need(Equal(savedMarker,kind==4 ? markerBytes : new byte[]{0}));
                Need(OwnGeneration(nonce,generation));
                // Same single OLE restore as production. No retries or alternate
                // writer can turn a failed first restore into a fixture pass.
                Clipboard.SetDataObject(saved,true,0,0);
                generation=GetClipboardSequenceNumber(); result["stage"]=5;
                Need(OwnGeneration(nonce,generation));
                Need(IsClipboardFormatAvailable(markerId)); result["markerPresentAfterRestore"]=true;
                VerifyPayloads(nonce,generation,expected,binary,ownership);
                if(kind==4) {
                    Need(OpenClipboard(IntPtr.Zero));
                    try { Need(GetClipboardSequenceNumber()==generation && Equal(LockedBytes(markerId),markerBytes)); }
                    finally { CloseClipboard(); }
                }
                result["payloadsPreserved"]=true; result["stage"]=7;
            }
        } catch { result["errorKind"]=1; }
        finally {
            foreach(IDisposable resource in resources) {
                try { resource.Dispose(); } catch { result["errorKind"]=2; }
            }
            if(seeded) result["cleanup"]=ClearOwn(nonce,generation);
        }
        result["ok"]=Convert.ToInt32(result["stage"])==7 && Convert.ToInt32(result["errorKind"])==0
            && Convert.ToBoolean(result["cleanup"]);
        return result;
    }
    public static Dictionary<string,object> Run(string assemblyPath) {
        Need(Environment.OSVersion.Platform==PlatformID.Win32NT && Environment.UserInteractive
            && Environment.GetEnvironmentVariable("GITHUB_ACTIONS")=="true"
            && Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")=="github-hosted");
        Need(Thread.CurrentThread.GetApartmentState()==ApartmentState.STA);
        RequireEmpty();
        // Loading verified, locally built bytes avoids locking the temporary
        // DLL after the fixture returns and permits deterministic cleanup.
        Assembly assembly=Assembly.Load(File.ReadAllBytes(assemblyPath));
        Type native=assembly.GetType("EchoLingoNative",true), probe=assembly.GetType("ClipboardHtmlProbe",true);
        MethodInfo snapshot=native.GetMethod("SnapshotClipboard",BindingFlags.NonPublic|BindingFlags.Static,
            null,new Type[]{typeof(List<IDisposable>),probe.MakeByRefType()},null);
        Need(snapshot!=null && snapshot.ReturnType==typeof(DataObject));
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();
        bool passed=true;
        using(OwnerWindow owner=new OwnerWindow()) {
            for(int kind=1;kind<=4;kind++) {
                Dictionary<string,object> result=RunCase(owner,snapshot,kind); cases.Add(result);
                if(!Convert.ToBoolean(result["ok"])) { passed=false; break; }
            }
        }
        return new Dictionary<string,object> {
            {"ok",passed && cases.Count==4},{"clipboardMarkerFixture",true},{"generatedDataOnly",true},
            {"keyboardRequests",0},{"browserRequests",0},{"retryAttempts",0},{"cases",cases},
            {"actualApplicationTested",false},{"framework",Environment.Version.ToString()}
        };
    }
}
