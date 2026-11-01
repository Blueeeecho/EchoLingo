// Generated formats only; tests the exact private production read adapter.
// No keyboard, source-window queries, or pre-existing clipboard content reads.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public static class WindowsClipboardReadinessFixture {
    [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError=true)] static extern int CountClipboardFormats();
    [DllImport("kernel32.dll", EntryPoint="SetLastError")] static extern void SetError(uint error);
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
    [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint format, IntPtr data);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr handle);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr handle);
    [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr handle);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr handle);
    static void Need(bool ok) { if (!ok) throw new InvalidOperationException("GENERATED_READINESS_ASSERTION"); }
    static bool EmptyLocked() { SetError(0); return CountClipboardFormats()==0 && Marshal.GetLastWin32Error()==0; }
    static void Write(uint format, byte[] data) {
        IntPtr handle=GlobalAlloc(0x42,new UIntPtr((uint)data.Length)); Need(handle!=IntPtr.Zero);
        bool transferred=false;
        try {
            IntPtr memory=GlobalLock(handle); Need(memory!=IntPtr.Zero);
            try { Marshal.Copy(data,0,memory,data.Length); } finally { GlobalUnlock(handle); }
            Need(SetClipboardData(format,handle)!=IntPtr.Zero); transferred=true;
        } finally { if(!transferred) GlobalFree(handle); }
    }
    static bool OwnLocked(uint marker, byte[] nonce) {
        if(!IsClipboardFormatAvailable(marker)) return false;
        IntPtr handle=GetClipboardData(marker); if(handle==IntPtr.Zero) return false;
        ulong size=GlobalSize(handle).ToUInt64(); if(size<(ulong)nonce.Length || size>256) return false;
        IntPtr memory=GlobalLock(handle); if(memory==IntPtr.Zero) return false;
        try {
            byte[] actual=new byte[nonce.Length]; Marshal.Copy(memory,actual,0,actual.Length);
            for(int i=0;i<nonce.Length;i++) if(actual[i]!=nonce[i]) return false;
            return true;
        } finally { GlobalUnlock(handle); }
    }
    static bool Cleanup(uint marker, byte[] nonce) {
        uint generation=GetClipboardSequenceNumber();
        if(!OpenClipboard(IntPtr.Zero)) return false;
        try { return generation==GetClipboardSequenceNumber() && OwnLocked(marker,nonce)
            && generation==GetClipboardSequenceNumber() && EmptyClipboard() && EmptyLocked(); }
        finally { CloseClipboard(); }
    }
    public static Dictionary<string,object> Run(string assemblyPath) {
        var cases=new List<Dictionary<string,object>>();
        var report=new Dictionary<string,object>{{"ok",false},{"generatedDataOnly",true},{"actualApplicationTested",false},{"keyboardRequests",0},{"cases",cases}};
        string originalTrace=Environment.GetEnvironmentVariable("ECHOLINGO_SELECTION_TRACE");
        try {
            var native=Assembly.LoadFrom(assemblyPath).GetType("EchoLingoNative",true);
            var read=native.GetMethod("ReadSelectionClipboardText",BindingFlags.NonPublic|BindingFlags.Static);
            Need(read!=null);
            Need(OpenClipboard(IntPtr.Zero)); try { Need(EmptyLocked()); } finally { CloseClipboard(); }
            using(Form owner=new Form()) {
                IntPtr window=owner.Handle;
                // ASCII is intentionally invariant across ANSI/OEM codepages.
                const string expected="Generated Unicode synthesis 24680";
                foreach(uint format in new uint[]{13,1,7,0}) {
                    var row=new Dictionary<string,object>{{"formatKind",format},{"ok",false},{"cleanup",false}};
                    cases.Add(row); bool seeded=false;
                    string token=Guid.NewGuid().ToString("N"); byte[] nonce=Encoding.ASCII.GetBytes(token);
                    uint marker=RegisterClipboardFormat("EchoLingo.Readiness."+token); Need(marker!=0);
                    try {
                        Need(OpenClipboard(window));
                        try {
                            Need(EmptyLocked()); Need(EmptyClipboard());
                            Write(marker,nonce); seeded=true;
                            if(format!=0) Write(format,(format==13?Encoding.Unicode:Encoding.ASCII).GetBytes(expected+"\0"));
                        } finally { CloseClipboard(); }
                        bool ready=IsClipboardFormatAvailable(13); row["unicodeAvailable"]=ready;
                        Need(ready==(format!=0));
                        foreach(bool trace in new bool[]{false,true}) {
                            Environment.SetEnvironmentVariable("ECHOLINGO_SELECTION_TRACE",trace?"1":null);
                            uint before=GetClipboardSequenceNumber(); Stopwatch clock=Stopwatch.StartNew();
                            string actual=(string)read.Invoke(null,null);
                            row[trace?"traceElapsedMs":"productionElapsedMs"]=clock.ElapsedMilliseconds;
                            bool exact=format==0?actual==null:actual==expected;
                            row[trace?"traceExact":"productionExact"]=exact; Need(exact);
                            if(format==0) Need(GetClipboardSequenceNumber()==before);
                        }
                        row["ok"]=true;
                    } catch { row["errorKind"]=1; }
                    finally { if(seeded) row["cleanup"]=Cleanup(marker,nonce); }
                    if(!(bool)row["cleanup"]) { row["ok"]=false; break; }
                }
            }
            report["ok"]=cases.Count==4 && cases.TrueForAll(delegate(Dictionary<string,object> row){return (bool)row["ok"]&&(bool)row["cleanup"];});
        } catch { report["boundaryError"]=true; }
        finally { Environment.SetEnvironmentVariable("ECHOLINGO_SELECTION_TRACE",originalTrace); }
        return report;
    }
}
