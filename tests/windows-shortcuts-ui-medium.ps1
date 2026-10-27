# Disposable same-user self-restricted MEDIUM chain for actual packaged UI.
# No UAC, privilege enabling, registry/policy/ACL changes or production devtools.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ApplicationPath,[string]$NodePath='', [switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -and -not $env:GITHUB_ACTIONS) { throw 'ISOLATION_REQUIRED' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive -or [IntPtr]::Size -ne 8) { throw 'WINDOWS_X64_INTERACTIVE_REQUIRED' }
    $ApplicationPath=(Resolve-Path -LiteralPath $ApplicationPath).Path
    if (-not $NodePath) { $NodePath=(Get-Command node.exe -CommandType Application -ErrorAction Stop).Source }
    $NodePath=(Resolve-Path -LiteralPath $NodePath).Path
    $FixturePath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'windows-shortcuts-ui.mjs')).Path
    Add-Type -AssemblyName System.Web.Extensions
    $source=@'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
public static class EchoLingoShortcutMedium {
    [StructLayout(LayoutKind.Sequential)] struct SIDATTR { public IntPtr sid; public uint attributes; }
    [StructLayout(LayoutKind.Sequential)] struct SECURITY { public int length; public IntPtr descriptor; [MarshalAs(UnmanagedType.Bool)] public bool inherit; }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct STARTUP {
        public int size; public string reserved,desktop,title; public uint x,y,width,height,charsX,charsY,fill,flags;
        public ushort show,reservedBytes; public IntPtr reservedData,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)] struct STARTUPEX { public STARTUP startup; public IntPtr attributes; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESSINFO { public IntPtr process,thread; public uint pid,tid; }
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint code);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,uint length,out uint required);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool CreateRestrictedToken(IntPtr source,uint flags,uint disableCount,IntPtr disable,uint deleteCount,IntPtr delete,uint restrictCount,IntPtr restrict,out IntPtr token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetTokenInformation(IntPtr token,int kind,IntPtr data,uint length);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSidToSid(string value,out IntPtr sid);
    [DllImport("advapi32.dll")] static extern uint GetLengthSid(IntPtr sid);
    [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
    [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr sid,uint index);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref SECURITY security,uint size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFile(string name,uint access,uint share,ref SECURITY security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,int flags,ref IntPtr size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr kind,IntPtr value,IntPtr size,IntPtr previous,IntPtr returned);
    [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessAsUser(IntPtr token,string application,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,ref STARTUPEX startup,out PROCESSINFO info);
    sealed class TokenState {
        public int Integrity,ElevationType,Elevated,UIAccess,Session; public byte[] User;
        public Dictionary<string,object> Public() { return new Dictionary<string,object> { {"integrityRid",Integrity},{"elevationType",ElevationType},{"elevated",Elevated},{"uiAccess",UIAccess},{"sessionId",Session} }; }
    }
    static TokenState ownToken;
    static void Need(bool value,string message) { if(!value)throw new InvalidOperationException(message); }
    static void Capability(bool value,string stage) { if(!value)throw new InvalidOperationException(stage+" Win32="+Marshal.GetLastWin32Error()); }
    static IntPtr TokenBuffer(IntPtr token,int kind) {
        uint length;GetTokenInformation(token,kind,IntPtr.Zero,0,out length);
        Capability(length>0&&length<=65536,"GetTokenInformation size");IntPtr buffer=Marshal.AllocHGlobal((int)length);
        if(!GetTokenInformation(token,kind,buffer,length,out length)){int error=Marshal.GetLastWin32Error();Marshal.FreeHGlobal(buffer);throw new InvalidOperationException("GetTokenInformation kind="+kind+" Win32="+error);}
        return buffer;
    }
    static int TokenNumber(IntPtr token,int kind) { IntPtr data=TokenBuffer(token,kind);try{return Marshal.ReadInt32(data);}finally{Marshal.FreeHGlobal(data);} }
    static TokenState ReadToken(IntPtr token) {
        TokenState result=new TokenState();IntPtr data=TokenBuffer(token,25);
        try { IntPtr sid=Marshal.ReadIntPtr(data);byte count=Marshal.ReadByte(GetSidSubAuthorityCount(sid));Capability(count>0,"Integrity SID");result.Integrity=Marshal.ReadInt32(GetSidSubAuthority(sid,(uint)(count-1))); }finally{Marshal.FreeHGlobal(data);}
        data=TokenBuffer(token,1);try{IntPtr sid=Marshal.ReadIntPtr(data);uint length=GetLengthSid(sid);Capability(length>0&&length<=256,"Own user SID length");result.User=new byte[length];Marshal.Copy(sid,result.User,0,(int)length);}finally{Marshal.FreeHGlobal(data);}
        result.ElevationType=TokenNumber(token,18);result.Elevated=TokenNumber(token,20);result.UIAccess=TokenNumber(token,26);result.Session=TokenNumber(token,12);return result;
    }
    static TokenState ProcessToken(IntPtr process) { IntPtr token;Capability(OpenProcessToken(process,8,out token),"Open own process token query");try{return ReadToken(token);}finally{CloseHandle(token);} }
    static bool SameUser(byte[] a,byte[] b) { if(a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true; }
    static void LowerIntegrity(IntPtr token) {
        IntPtr sid=IntPtr.Zero,data=IntPtr.Zero;
        try {
            Capability(ConvertStringSidToSid("S-1-16-8192",out sid),"Create public medium integrity SID");int sidLength=(int)GetLengthSid(sid),size=Marshal.SizeOf(typeof(SIDATTR));
            data=Marshal.AllocHGlobal(size+sidLength);byte[] bytes=new byte[sidLength];Marshal.Copy(sid,bytes,0,sidLength);Marshal.Copy(bytes,0,IntPtr.Add(data,size),sidLength);
            SIDATTR label=new SIDATTR { sid=IntPtr.Add(data,size),attributes=0x20 };Marshal.StructureToPtr(label,data,false);
            Capability(SetTokenInformation(token,25,data,(uint)(size+sidLength)),"Lower self-restricted token integrity to medium");
        }finally{if(data!=IntPtr.Zero)Marshal.FreeHGlobal(data);if(sid!=IntPtr.Zero)LocalFree(sid);}
    }
    [StructLayout(LayoutKind.Sequential)] struct BASIC { public long processTime,jobTime;public uint flags;public UIntPtr minimum,maximum;public uint active;public UIntPtr affinity;public uint priority,scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct LIMITS { public BASIC basic; public ulong readOps,writeOps,otherOps,readBytes,writeBytes,otherBytes; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security,string name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref LIMITS info,uint length);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
    [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
    sealed class Drain { public string Text;public bool Overflow; }
    static Drain ReadBounded(StreamReader reader) {
        StringBuilder text=new StringBuilder();char[] block=new char[4096];bool overflow=false;int count;
        while((count=reader.Read(block,0,block.Length))>0){int keep=Math.Min(count,2*1024*1024-text.Length);if(keep>0)text.Append(block,0,keep);if(keep<count)overflow=true;}
        return new Drain { Text=text.ToString(),Overflow=overflow };
    }
    static string Quote(string value) { Need(!String.IsNullOrWhiteSpace(value)&&Path.IsPathRooted(value)&&File.Exists(value)&&value.IndexOf('"')<0&&value.IndexOf('\r')<0&&value.IndexOf('\n')<0&&value.IndexOf('\0')<0,"Invalid absolute fixture file path.");return "\""+value+"\""; }
    public static int Run(string node,string fixture,string app) {
        Dictionary<string,object> report=new Dictionary<string,object>{{"ok",false},{"status","inconclusive"},{"sameUserSelfRestrictedMedium",true},{"normalUacFilteredToken",false},{"productionModified",false},{"existingCdpDeadlineMilliseconds",30000}};
        IntPtr source=IntPtr.Zero,restricted=IntPtr.Zero,readOut=IntPtr.Zero,writeOut=IntPtr.Zero,readError=IntPtr.Zero,writeError=IntPtr.Zero,nul=IntPtr.Zero,job=IntPtr.Zero;
        IntPtr attributes=IntPtr.Zero,list=IntPtr.Zero,environment=IntPtr.Zero;bool initialized=false,resumed=false,done=false;PROCESSINFO child=new PROCESSINFO();
        StreamReader stdout=null,stderr=null;Task<Drain> output=null,error=null;int exit=3;
        try {
            string command=Quote(node)+" "+Quote(fixture)+" "+Quote(app)+" --isolated-test-session";
            ownToken=ProcessToken(GetCurrentProcess());report["launcherToken"]=ownToken.Public();
            Need((ownToken.Integrity==8192||ownToken.Integrity==12288)&&ownToken.UIAccess==0,"Existing launcher must be MEDIUM or HIGH with UIAccess0; no elevation/fallback.");
            Capability(OpenProcessToken(GetCurrentProcess(),0x1|0x2|0x8|0x80,out source),"Open own primary token");
            Capability(CreateRestrictedToken(source,1,0,IntPtr.Zero,0,IntPtr.Zero,0,IntPtr.Zero,out restricted),"Restrict own primary token DISABLE_MAX_PRIVILEGE");LowerIntegrity(restricted);
            TokenState prepared=ReadToken(restricted);Need(prepared.Integrity==8192&&prepared.UIAccess==0&&prepared.Session==ownToken.Session&&SameUser(prepared.User,ownToken.User),"Prepared token identity mismatch.");
            job=CreateJobObject(IntPtr.Zero,null);Capability(job!=IntPtr.Zero,"Create private unnamed job");LIMITS limits=new LIMITS();limits.basic.flags=0x2000;
            Need(Marshal.SizeOf(typeof(BASIC))==64&&Marshal.SizeOf(typeof(LIMITS))==144,"Unexpected Windows x64 job ABI.");
            Capability(SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(LIMITS))),"Set owned job kill-on-close");
            SECURITY security=new SECURITY { length=Marshal.SizeOf(typeof(SECURITY)),inherit=true };
            Capability(CreatePipe(out readOut,out writeOut,ref security,0),"Create stdout pipe");Capability(SetHandleInformation(readOut,1,0),"Exclude read stdout inheritance");
            Capability(CreatePipe(out readError,out writeError,ref security,0),"Create stderr pipe");Capability(SetHandleInformation(readError,1,0),"Exclude read stderr inheritance");
            nul=CreateFile("NUL",0x80000000,3,ref security,3,0x80,IntPtr.Zero);Capability(nul!=IntPtr.Zero&&nul!=new IntPtr(-1),"Open NUL stdin");
            IntPtr size=IntPtr.Zero;InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size);Need(size.ToInt64()>0&&size.ToInt64()<=65536,"Invalid attribute size.");
            attributes=Marshal.AllocHGlobal(size);Capability(InitializeProcThreadAttributeList(attributes,1,0,ref size),"Initialize exact inheritance list");initialized=true;
            list=Marshal.AllocHGlobal(IntPtr.Size*3);Marshal.Copy(new IntPtr[]{nul,writeOut,writeError},0,list,3);
            Capability(UpdateProcThreadAttribute(attributes,0,new IntPtr(0x20002),list,new IntPtr(IntPtr.Size*3),IntPtr.Zero,IntPtr.Zero),"Whitelist only three owned standard handles");
            string windows=Environment.GetEnvironmentVariable("SystemRoot");Need(Path.IsPathRooted(windows),"SystemRoot missing.");
            SortedDictionary<string,string> vars=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            vars["SystemRoot"]=windows;vars["WINDIR"]=windows;vars["TEMP"]=Path.GetTempPath();vars["TMP"]=Path.GetTempPath();vars["PATH"]=Path.Combine(windows,"System32")+";"+windows+";"+Path.Combine(windows,"System32\\Wbem");vars["ECHOLINGO_TEST_EXPECT_MEDIUM"]="1";
            StringBuilder block=new StringBuilder();foreach(KeyValuePair<string,string> variable in vars)block.Append(variable.Key).Append('=').Append(variable.Value).Append('\0');block.Append('\0');environment=Marshal.StringToHGlobalUni(block.ToString());
            STARTUPEX startup=new STARTUPEX();startup.startup.size=Marshal.SizeOf(typeof(STARTUPEX));startup.startup.desktop="winsta0\\default";startup.startup.flags=0x100;startup.startup.input=nul;startup.startup.output=writeOut;startup.startup.error=writeError;startup.attributes=attributes;
            Capability(CreateProcessAsUser(restricted,node,new StringBuilder(command),IntPtr.Zero,IntPtr.Zero,true,0x08000000|0x00080000|0x00000400|0x4,environment,Path.GetDirectoryName(Path.GetDirectoryName(fixture)),ref startup,out child),"Create suspended own MEDIUM Node");
            Capability(AssignProcessToJobObject(job,child.process),"Assign suspended Node to private owned job");
            TokenState actual=ProcessToken(child.process);report["actualNodeProcessId"]=child.pid;report["actualNodeToken"]=actual.Public();
            bool same=SameUser(actual.User,ownToken.User);report["sameUserVerified"]=same;Need(actual.Integrity==8192&&actual.UIAccess==0&&actual.Session==ownToken.Session&&same,"Actual Node token identity mismatch.");
            stdout=new StreamReader(new FileStream(new Microsoft.Win32.SafeHandles.SafeFileHandle(readOut,true),FileAccess.Read),Encoding.UTF8);readOut=IntPtr.Zero;
            stderr=new StreamReader(new FileStream(new Microsoft.Win32.SafeHandles.SafeFileHandle(readError,true),FileAccess.Read),Encoding.UTF8);readError=IntPtr.Zero;
            output=Task.Factory.StartNew(()=>ReadBounded(stdout));error=Task.Factory.StartNew(()=>ReadBounded(stderr));
            CloseHandle(writeOut);writeOut=IntPtr.Zero;CloseHandle(writeError);writeError=IntPtr.Zero;
            Capability(ResumeThread(child.thread)!=UInt32.MaxValue,"Resume verified MEDIUM Node");resumed=true;
            if(WaitForSingleObject(child.process,180000)!=0){report["nodeDeadlineExceeded"]=true;exit=1;throw new InvalidOperationException("Owned Node exceeded180000ms total fixture budget; CDP budget remains30000ms.");}
            uint code;Capability(GetExitCodeProcess(child.process,out code),"Read actual Node exit");exit=unchecked((int)code);done=true;report["nodeExitCode"]=exit;
            // Close the job after Node exit to terminate any owned descendant that
            // escaped its normal cleanup; pipe EOF must complete before success.
            Capability(TerminateJobObject(job,1),"Drain owned descendant processes");
            Need(output.Wait(3000)&&error.Wait(3000),"Owned output drain did not finish.");
            Drain result=output.Result,errors=error.Result;Need(!result.Overflow&&!errors.Overflow,"Owned fixture output exceeded2MiB per stream.");
            Console.Out.Write(result.Text);Console.Error.Write(errors.Text);report["stdoutCharacters"]=result.Text.Length;report["stderrCharacters"]=errors.Text.Length;
            report["ok"]=exit==0;report["status"]=exit==0?"pass":"failure";
        }catch(Exception failure){report["error"]=failure.Message;report["nodeWasResumed"]=resumed;if(done||resumed){report["status"]="failure";if(exit==0)exit=1;}}
        finally {
            if(child.process!=IntPtr.Zero&&WaitForSingleObject(child.process,0)!=0){if(job!=IntPtr.Zero)TerminateJobObject(job,1);TerminateProcess(child.process,1);WaitForSingleObject(child.process,3000);}
            if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}
            if(stdout!=null)stdout.Dispose();if(stderr!=null)stderr.Dispose();
            if(initialized)DeleteProcThreadAttributeList(attributes);if(attributes!=IntPtr.Zero)Marshal.FreeHGlobal(attributes);if(list!=IntPtr.Zero)Marshal.FreeHGlobal(list);if(environment!=IntPtr.Zero)Marshal.FreeHGlobal(environment);
            foreach(IntPtr handle in new IntPtr[]{source,restricted,readOut,writeOut,readError,writeError,nul,child.thread,child.process})if(handle!=IntPtr.Zero&&handle!=new IntPtr(-1))CloseHandle(handle);
        }
        Console.Out.WriteLine(new JavaScriptSerializer().Serialize(report));return exit;
    }
}
'@
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    $fixtureExit=[EchoLingoShortcutMedium]::Run($NodePath,$FixturePath,$ApplicationPath)
    exit $fixtureExit
} catch {
    [Console]::Out.WriteLine((@{ok=$false;status='inconclusive';error=$_.Exception.Message;productionModified=$false;scope='Same-user self-restricted MEDIUM fixture only; no elevated fallback.'}|ConvertTo-Json -Compress));exit 3
}
