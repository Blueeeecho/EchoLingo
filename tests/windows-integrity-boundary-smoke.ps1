# Synthetic same-user MIC/UIPI boundary: own HIGH generated source against a
# verified MEDIUM self-restricted helper. Never elevates or changes security policy.
[CmdletBinding()]
param([string]$HelperPath='', [Parameter(Mandatory=$true)][string]$NativeAssemblyPath,
      [switch]$IsolatedTestSession)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -and -not $env:GITHUB_ACTIONS) { throw 'ISOLATION_REQUIRED: Use an explicitly isolated generated-window session.' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) { throw 'DESKTOP_UNAVAILABLE: An unlocked Windows desktop is required.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) { throw 'TEST_APARTMENT: Use powershell.exe -STA.' }
    if (-not $HelperPath) { $HelperPath=Join-Path $PSScriptRoot '..\src-tauri\native\windows.ps1' }
    $HelperPath=(Resolve-Path -LiteralPath $HelperPath).Path
    $NativeAssemblyPath=(Resolve-Path -LiteralPath $NativeAssemblyPath).Path
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Web.Extensions
    $source = @'
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
public static class EchoLingoIntegrityBoundarySmoke {
    delegate bool EnumWindow(IntPtr window,IntPtr parameter);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left,top,right,bottom; }
    [StructLayout(LayoutKind.Sequential)] struct GUI { public uint size,flags; public IntPtr active,focus,capture,menuOwner,moveSize,caret; public RECT caretRect; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public Union data; }
    [StructLayout(LayoutKind.Explicit)] struct Union { [FieldOffset(0)] public MOUSE mouse; [FieldOffset(0)] public KEY key; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEY { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window,uint relation);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out RECT bounds);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window,ref Point point);
    [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr window,Point point,uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder value,int count);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetCapture(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetCapture();
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUI value);
    [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] values,int size);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window,uint attribute,out RECT bounds,int size);
    sealed class WindowInfo { public IntPtr Handle; public Rectangle Bounds; }
    sealed class EnvironmentInconclusive : Exception { public EnvironmentInconclusive(string message):base(message){} }
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
    static void Capability(bool value,string stage) { if(!value)throw new EnvironmentInconclusive(stage+" Win32="+Marshal.GetLastWin32Error()); }
    static IntPtr TokenBuffer(IntPtr token,int kind) {
        uint length;GetTokenInformation(token,kind,IntPtr.Zero,0,out length);
        Capability(length>0&&length<=65536,"GetTokenInformation size");IntPtr buffer=Marshal.AllocHGlobal((int)length);
        if(!GetTokenInformation(token,kind,buffer,length,out length)){int error=Marshal.GetLastWin32Error();Marshal.FreeHGlobal(buffer);throw new EnvironmentInconclusive("GetTokenInformation kind="+kind+" Win32="+error);}
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
    sealed class RestrictedChild : IDisposable {
        IntPtr handle;readonly StreamReader stdout,stderr;public readonly Task<string> Output,Error;public readonly int Id;public readonly TokenState Token;
        public bool HasExited { get { return WaitForSingleObject(handle,0)==0; } }
        public int ExitCode { get { uint value;Need(GetExitCodeProcess(handle,out value),"Cannot read own restricted child exit.");return unchecked((int)value); } }
        public bool WaitForExit(int milliseconds) { return WaitForSingleObject(handle,(uint)milliseconds)==0; }
        public void Kill() { Need(TerminateProcess(handle,1),"Cannot stop owned restricted helper."); }
        public RestrictedChild(PROCESSINFO child,IntPtr output,IntPtr error) {
            handle=child.process;Id=(int)child.pid;CloseHandle(child.thread);
            try {
                stdout=new StreamReader(new FileStream(new Microsoft.Win32.SafeHandles.SafeFileHandle(output,true),FileAccess.Read),Encoding.UTF8);
                stderr=new StreamReader(new FileStream(new Microsoft.Win32.SafeHandles.SafeFileHandle(error,true),FileAccess.Read),Encoding.UTF8);
                Output=stdout.ReadToEndAsync();Error=stderr.ReadToEndAsync();
                Token=ProcessToken(handle);Capability(Token.Integrity==8192&&Token.UIAccess==0&&Token.Session==ownToken.Session&&SameUser(Token.User,ownToken.User),"Actual child medium/same-user/session/UIAccess verification");
            } catch {
                if(!HasExited)Kill();WaitForExit(3000);
                if(stdout==null)CloseHandle(output);if(stderr==null)CloseHandle(error);Dispose();throw;
            }
        }
        public void Dispose() { if(stdout!=null)stdout.Dispose();if(stderr!=null)stderr.Dispose();if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;} }
    }
    static RestrictedChild StartRestricted(string helper,string assembly,string backend) {
        IntPtr source=IntPtr.Zero,restricted=IntPtr.Zero,readOut=IntPtr.Zero,writeOut=IntPtr.Zero,readError=IntPtr.Zero,writeError=IntPtr.Zero,nul=IntPtr.Zero;
        IntPtr attributes=IntPtr.Zero,list=IntPtr.Zero,environment=IntPtr.Zero;bool initialized=false,transferred=false;PROCESSINFO child=new PROCESSINFO();
        try {
            Capability(OpenProcessToken(GetCurrentProcess(),0x1|0x2|0x8|0x80,out source),"Open own primary token for restriction");
            Capability(CreateRestrictedToken(source,1,0,IntPtr.Zero,0,IntPtr.Zero,0,IntPtr.Zero,out restricted),"Create own DISABLE_MAX_PRIVILEGE restricted token");
            LowerIntegrity(restricted);TokenState prepared=ReadToken(restricted);Capability(prepared.Integrity==8192&&prepared.UIAccess==0&&SameUser(prepared.User,ownToken.User),"Prepared medium self token verification");
            SECURITY security=new SECURITY { length=Marshal.SizeOf(typeof(SECURITY)),inherit=true };
            Capability(CreatePipe(out readOut,out writeOut,ref security,0),"Create owned stdout pipe");Capability(SetHandleInformation(readOut,1,0),"Exclude stdout read handle from inheritance");
            Capability(CreatePipe(out readError,out writeError,ref security,0),"Create owned stderr pipe");Capability(SetHandleInformation(readError,1,0),"Exclude stderr read handle from inheritance");
            nul=CreateFile("NUL",0x80000000,3,ref security,3,0x80,IntPtr.Zero);Capability(nul!=IntPtr.Zero&&nul!=new IntPtr(-1),"Open owned NUL stdin");
            IntPtr size=IntPtr.Zero;InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size);Capability(size.ToInt64()>0&&size.ToInt64()<=65536,"Measure handle inheritance attribute");
            attributes=Marshal.AllocHGlobal(size);Capability(InitializeProcThreadAttributeList(attributes,1,0,ref size),"Initialize restricted handle inheritance");initialized=true;
            list=Marshal.AllocHGlobal(IntPtr.Size*3);Marshal.Copy(new IntPtr[] { nul,writeOut,writeError },0,list,3);
            Capability(UpdateProcThreadAttribute(attributes,0,new IntPtr(0x20002),list,new IntPtr(IntPtr.Size*3),IntPtr.Zero,IntPtr.Zero),"Restrict inherited handles to owned NUL/stdout/stderr only");
            string windows=Environment.GetEnvironmentVariable("SystemRoot");Need(Path.IsPathRooted(windows),"SystemRoot is not absolute.");string executable=Path.Combine(windows,"System32\\WindowsPowerShell\\v1.0\\powershell.exe");
            // Minimal allowlisted environment, never pass CI/service credentials.
            SortedDictionary<string,string> variables=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            variables["SystemRoot"]=windows;variables["WINDIR"]=windows;variables["TEMP"]=Path.GetTempPath();variables["TMP"]=Path.GetTempPath();
            variables["PATH"]=Path.Combine(windows,"System32")+";"+windows+";"+Path.Combine(windows,"System32\\Wbem");StringBuilder block=new StringBuilder();
            foreach(KeyValuePair<string,string> variable in variables)block.Append(variable.Key).Append('=').Append(variable.Value).Append('\0');block.Append('\0');environment=Marshal.StringToHGlobalUni(block.ToString());
            STARTUPEX startup=new STARTUPEX();startup.startup.size=Marshal.SizeOf(typeof(STARTUPEX));startup.startup.desktop="winsta0\\default";startup.startup.flags=0x100;startup.startup.input=nul;startup.startup.output=writeOut;startup.startup.error=writeError;startup.attributes=attributes;
            StringBuilder command=new StringBuilder("\""+executable+"\" -NoProfile -STA -ExecutionPolicy Bypass -File \""+helper+"\" -Mode capture-image -NativeAssemblyPath \""+assembly+"\" -InputBackend "+backend+" -PerformanceDiagnostics");
            // No explicit privilege adjustment, alternate credentials, UAC or ACL change.
            Capability(CreateProcessAsUser(restricted,executable,command,IntPtr.Zero,IntPtr.Zero,true,0x08000000|0x00080000|0x00000400,environment,Path.GetDirectoryName(helper),ref startup,out child),"CreateProcessAsUser own medium restricted helper");
            CloseHandle(writeOut);writeOut=IntPtr.Zero;CloseHandle(writeError);writeError=IntPtr.Zero;
            transferred=true;return new RestrictedChild(child,readOut,readError);
        }finally {
            if(initialized)DeleteProcThreadAttributeList(attributes);if(attributes!=IntPtr.Zero)Marshal.FreeHGlobal(attributes);if(list!=IntPtr.Zero)Marshal.FreeHGlobal(list);if(environment!=IntPtr.Zero)Marshal.FreeHGlobal(environment);
            foreach(IntPtr handle in new IntPtr[] { source,restricted,writeOut,writeError,nul })if(handle!=IntPtr.Zero&&handle!=new IntPtr(-1))CloseHandle(handle);
            if(!transferred){if(readOut!=IntPtr.Zero)CloseHandle(readOut);if(readError!=IntPtr.Zero)CloseHandle(readError);}
        }
    }

    static readonly JavaScriptSerializer json=new JavaScriptSerializer { MaxJsonLength=16*1024*1024 };
    static void Need(bool value,string message) { if (!value) throw new InvalidOperationException(message); }
    static string Id(IntPtr value) { return "0x"+value.ToInt64().ToString("X"); }
    static int[] Rect(Rectangle value) { return new int[] { value.X,value.Y,value.Width,value.Height }; }
    static Rectangle Bounds(IntPtr window) { RECT value; Need(GetWindowRect(window,out value),"Cannot read owned window bounds.");return Rectangle.FromLTRB(value.left,value.top,value.right,value.bottom); }
    static Rectangle Frame(IntPtr window) { RECT value;Need(DwmGetWindowAttribute(window,9,out value,Marshal.SizeOf(typeof(RECT)))==0,"Cannot read source DWM frame.");return Rectangle.FromLTRB(value.left,value.top,value.right,value.bottom); }
    static string Class(IntPtr window) { StringBuilder value=new StringBuilder(256);GetClassName(window,value,value.Capacity);return value.ToString(); }
    static bool Plane(IntPtr window,int pid) { return Class(window)=="EchoLingoCaptureInputPlane-"+pid; }
    static INPUT Move(Point point) {
        Rectangle desktop=SystemInformation.VirtualScreen;INPUT value=new INPUT();
        value.data.mouse.x=(int)Math.Round((point.X-desktop.X)*65535.0/(desktop.Width-1));
        value.data.mouse.y=(int)Math.Round((point.Y-desktop.Y)*65535.0/(desktop.Height-1));value.data.mouse.flags=0x8000|0x4000|1;return value;
    }
    static INPUT Mouse(uint flags) { INPUT value=new INPUT();value.data.mouse.flags=flags;return value; }
    static void Send(INPUT[] values) { Need(SendInput((uint)values.Length,values,Marshal.SizeOf(typeof(INPUT)))==values.Length,"Windows rejected owned generated input."); }
    static void Escape(IntPtr source) { Need(GetForegroundWindow()==source,"Source foreground changed; no key sent elsewhere.");INPUT down=new INPUT();down.type=1;down.data.key.vk=0x1b;INPUT up=down;up.data.key.flags=2;Send(new INPUT[] { down,up }); }
    static List<Rectangle> Perimeter(Rectangle frame) {
        return new List<Rectangle> { new Rectangle(frame.X,frame.Y,frame.Width,2),new Rectangle(frame.X,frame.Bottom-2,frame.Width,2),
            new Rectangle(frame.X,frame.Y+2,2,frame.Height-4),new Rectangle(frame.Right-2,frame.Y+2,2,frame.Height-4) };
    }
    static bool Ready(int helper,IntPtr source,Rectangle frame,Rectangle display,Point point,Dictionary<string,object> observed) {
        Need(GetForegroundWindow()==source && Frame(source)==frame,"Source foreground/DWM changed before adversarial action.");
        List<WindowInfo> thin=new List<WindowInfo>(),planes=new List<WindowInfo>();int allocated=0;
        EnumWindows(delegate(IntPtr window,IntPtr unused) {
            uint pid;GetWindowThreadProcessId(window,out pid);if (pid!=helper) return true;
            long style=GetWindowLongPtr(window,-20).ToInt64();
            if (Plane(window,helper)) {
                if (!IsWindowVisible(window)) return true;
                const long required=0x00200000L|0x08000000L|0x80L|8;
                Need((style&required)==required&&(style&(0x80000L|0x20L))==0,"Input plane styles invalid.");
                planes.Add(new WindowInfo { Handle=window,Bounds=Bounds(window) });return true;
            }
            long edges=0x08000000L|0x80000L|0x20L;
            if ((style&edges)==edges) allocated++;
            if (!IsWindowVisible(window)) return true;
            Rectangle r=Bounds(window);Need((style&(edges|8))==(edges|8)&&Math.Min(r.Width,r.Height)<=2,"Unknown visible helper surface.");
            thin.Add(new WindowInfo { Handle=window,Bounds=r });return true;
        },IntPtr.Zero);
        List<Rectangle> wanted=Perimeter(display);wanted.AddRange(Perimeter(frame));
        bool exact=thin.Count==8 && allocated==12*Screen.AllScreens.Length;
        foreach (WindowInfo edge in thin) { int index=wanted.IndexOf(edge.Bounds);if (index<0) exact=false;else wanted.RemoveAt(index); }
        List<Rectangle> monitors=new List<Rectangle>();foreach (Screen screen in Screen.AllScreens) monitors.Add(screen.Bounds);
        bool planeGeometry=planes.Count==monitors.Count;
        foreach (WindowInfo plane in planes) {int index=monitors.IndexOf(plane.Bounds);if(index<0)planeGeometry=false;else monitors.RemoveAt(index);}
        IntPtr raw=GetAncestor(WindowFromPoint(point),2);Point client=point;IntPtr desktop=GetDesktopWindow();
        IntPtr through=ScreenToClient(desktop,ref client)?GetAncestor(ChildWindowFromPointEx(desktop,client,5),2):IntPtr.Zero;
        bool hit=planes.Exists(delegate(WindowInfo p){return p.Handle==through&&p.Bounds.Contains(point);})
            && (planes.Exists(delegate(WindowInfo p){return p.Handle==raw;})||thin.Exists(delegate(WindowInfo e){return e.Handle==raw&&e.Bounds.Contains(point);}));
        observed["thinVisibleCount"]=thin.Count;observed["thinAllocatedCount"]=allocated;observed["planeVisibleCount"]=planes.Count;
        observed["rawPointerRootHwnd"]=Id(raw);observed["transparentSkippingRootHwnd"]=Id(through);
        observed["exactPlanePointerHit"]=hit;return exact&&wanted.Count==0&&planeGeometry&&monitors.Count==0&&hit;
    }
    static Dictionary<string,object> SafeReply(Dictionary<string,object> reply) {
        Dictionary<string,object> safe=new Dictionary<string,object>();
        foreach(string key in new string[] { "ok","nativeBackend" }) if(reply.ContainsKey(key))safe[key]=reply[key];
        if(reply.ContainsKey("error")) { string error=Convert.ToString(reply["error"]);safe["error"]=error.Substring(0,Math.Min(error.Length,600)); }
        foreach(string key in new string[] { "captureHealth","capturePerformance","helperPerformance" }) {
            object raw; if(!reply.TryGetValue(key,out raw))continue;Dictionary<string,object> values=raw as Dictionary<string,object>;
            if(values==null||values.Count>128)continue;Dictionary<string,object> numbers=new Dictionary<string,object>();
            foreach(KeyValuePair<string,object> field in values)if(field.Value is int||field.Value is long||field.Value is double||field.Value is decimal)numbers[field.Key]=field.Value;
            safe[key]=numbers;
        }
        return safe;
    }
    static Dictionary<string,object> Case(string helper,string assembly,string backend,string kind) {
        Dictionary<string,object> report=new Dictionary<string,object> { { "mode",kind },{ "ok",false } };
        Form source=null;IntPtr hwnd=IntPtr.Zero;uint sourceThread=0;int downs=0,ups=0,clicks=0;
        Rectangle frame=Rectangle.Empty,display=Rectangle.Empty;Point first=Point.Empty,last=Point.Empty;
        ManualResetEvent ready=new ManualResetEvent(false);string setupError=null;
        Thread ui=new Thread(delegate() {
            try {
                Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Source DPI context failed.");
                using(Form form=new Form())using(Button button=new Button()) {
                    source=form;form.Text="EchoLingo controlled input ownership source";form.AutoScaleMode=AutoScaleMode.None;
                    form.FormBorderStyle=FormBorderStyle.None;form.StartPosition=FormStartPosition.Manual;form.ShowInTaskbar=true;form.Owner=null;form.TopMost=kind=="high-topmost-source";
                    Rectangle work=Screen.PrimaryScreen.WorkingArea;display=Screen.PrimaryScreen.Bounds;
                    Need(work.Width>=640&&work.Height>=440,"Generated adversarial fixture requires640x440 work area.");
                    form.Bounds=new Rectangle(work.X+60,work.Y+50,520,340);form.BackColor=Color.FromArgb(40,180,90);
                    button.Bounds=new Rectangle(40,50,240,75);button.Text="Generated button";button.FlatStyle=FlatStyle.Flat;button.UseVisualStyleBackColor=false;button.BackColor=Color.FromArgb(230,150,40);
                    button.MouseDown+=delegate { Interlocked.Increment(ref downs); };button.MouseUp+=delegate { Interlocked.Increment(ref ups); };button.Click+=delegate { Interlocked.Increment(ref clicks); };
                    form.MouseDown+=delegate { Interlocked.Increment(ref downs); };form.MouseUp+=delegate { Interlocked.Increment(ref ups); };form.Controls.Add(button);
                    form.Shown+=delegate { try { form.Activate();SetForegroundWindow(form.Handle);hwnd=form.Handle;sourceThread=GetCurrentThreadId();frame=Frame(hwnd);first=form.PointToScreen(new Point(65,70));last=new Point(first.X+35,first.Y+15); }catch(Exception error){setupError=error.Message;}finally{ready.Set();} };
                    Application.Run(form);
                }
            }catch(Exception error){setupError=error.Message;ready.Set();}
        });ui.IsBackground=true;ui.SetApartmentState(ApartmentState.STA);ui.Start();
        RestrictedChild process=null;Task<string> output=null;bool partialInput=false;
        try {
            Need(ready.WaitOne(10000)&&setupError==null,"Source setup failed: "+setupError);
            Need(sourceThread!=GetCurrentThreadId()&&GetForegroundWindow()==hwnd,"Source is not on its independent foreground UI thread.");
            uint sourcePid;Need(GetWindowThreadProcessId(hwnd,out sourcePid)==sourceThread&&sourcePid==Process.GetCurrentProcess().Id,"Source identity changed.");
            Need(GetWindow(hwnd,4)==IntPtr.Zero&&GetParent(hwnd)==IntPtr.Zero&&frame!=display&&display.Contains(frame),"Source is not an ordinary ownerless non-fullscreen window.");
            Need(GetAncestor(WindowFromPoint(first),2)==hwnd,"Generated source endpoint is initially obscured; no input sent.");
            Send(new INPUT[] { Move(first) });Thread.Sleep(80);
            process=StartRestricted(helper,assembly,backend);output=process.Output;
            report["sourceToken"]=ownToken.Public();report["actualHelperToken"]=process.Token.Public();report["sameUserVerified"]=SameUser(ownToken.User,process.Token.User);
            report["syntheticSelfRestrictedToken"]=true;report["sourceTopmost"]=kind=="high-topmost-source";
            Dictionary<string,object> observed=new Dictionary<string,object>();report["readyObservation"]=observed;Stopwatch clock=Stopwatch.StartNew();bool pickerReady=false;
            while(clock.ElapsedMilliseconds<25000&&!process.HasExited) {if(Ready(process.Id,hwnd,frame,display,first,observed)){pickerReady=true;break;}Thread.Sleep(10);}
            Need(pickerReady,"Exact production input plane/screen+hover readiness was not observed.");
            report["helperReadyMilliseconds"]=clock.Elapsed.TotalMilliseconds;report["helperProcessId"]=process.Id;report["sourceHwnd"]=Id(hwnd);report["sourceProcessId"]=sourcePid;
            report["sourceUiThreadId"]=sourceThread;report["controllerThreadId"]=GetCurrentThreadId();report["sourcePhysicalDwmBounds"]=Rect(frame);report["sourceNotFullscreen"]=true;
            source.Invoke((Action)delegate {
                Need(GetForegroundWindow()==hwnd,"HIGH source foreground changed; no input sent elsewhere.");
                Dictionary<string,object> atInput=new Dictionary<string,object>();report["mediumPlaneObservationBeforeInput"]=atInput;
                Need(Ready(process.Id,hwnd,frame,display,first,atInput),"Verified medium input plane no longer covers the high generated source.");
                partialInput=true;Send(new INPUT[] { Move(first),Mouse(2),Move(last),Mouse(4) });partialInput=false;
            });
            Thread.Sleep(180);
            // Drain this generated source thread's own queue before claiming
            // that no native button messages reached its controls.
            source.Invoke((Action)delegate { Application.DoEvents(); });
            report["underlyingMouseDowns"]=Interlocked.CompareExchange(ref downs,0,0);report["underlyingMouseUps"]=Interlocked.CompareExchange(ref ups,0,0);report["underlyingButtonClicks"]=Interlocked.CompareExchange(ref clicks,0,0);
            bool leak=downs!=0||ups!=0||clicks!=0;report["zeroUnderlyingInput"]=!leak;report["foregroundPreserved"]=GetForegroundWindow()==hwnd;
            source.Invoke((Action)delegate { if(GetCapture()==hwnd)ReleaseCapture(); });
            if(leak&&!process.HasExited)Escape(hwnd);
            Need(process.WaitForExit(10000),"Production picker did not finish after owned input/cancellation.");
            Need(output.Wait(3000),"Owned helper JSON output did not finish within the drain budget.");
            Dictionary<string,object> reply=json.Deserialize<Dictionary<string,object>>(output.GetAwaiter().GetResult());report["helperDiagnostics"]=SafeReply(reply);report["helperExitCode"]=process.ExitCode;
            Need(reply.ContainsKey("nativeBackend")&&(string)reply["nativeBackend"]=="precompiled-framework-dll","Actual restricted helper did not use the exact explicit precompiled native DLL path.");
            Dictionary<string,object> health=(Dictionary<string,object>)reply["captureHealth"];
            Need(Convert.ToInt64(health["inputBackend"])==(backend=="planeOnly"?2:1),"Actual helper input backend differs from requested mode.");
            if(backend=="planeOnly")Need(Convert.ToInt64(health["mouseHookInstalled"])==0&&Convert.ToInt64(health["hookMouseDowns"])==0&&Convert.ToInt64(health["hookMouseUps"])==0,"Forced no-hook test did not actually disable mouse hooks.");
            source.Invoke((Action)delegate { Application.DoEvents(); });
            report["underlyingMouseDowns"]=downs;report["underlyingMouseUps"]=ups;report["underlyingButtonClicks"]=clicks;
            leak=downs!=0||ups!=0||clicks!=0;report["zeroUnderlyingInput"]=!leak;report["underlyingQueueDrainedAfterHelperExit"]=true;
            Need(!leak,"UNDERLYING_INPUT: A generated HIGH source received actual input while the verified MEDIUM picker was ready.");
            Need((bool)reply["ok"]&&process.ExitCode==0,"Production picker failed to return a valid region.");
            if(backend=="planeOnly")Need(Convert.ToInt64(health["inputPlaneDowns"])>0&&Convert.ToInt64(health["inputPlaneUps"])>0,"No actual input plane down/up delivery was proven.");
            using(MemoryStream bytes=new MemoryStream(Convert.FromBase64String((string)reply["imageBase64"])))using(Bitmap image=new Bitmap(bytes)) {
                Need(image.Width==last.X-first.X&&image.Height==last.Y-first.Y,"Free ROI dimensions changed.");
                for(int y=0;y<image.Height;y++)for(int x=0;x<image.Width;x++){Color c=image.GetPixel(x,y);Need(!(Math.Abs(c.R-45)<=2&&Math.Abs(c.G-145)<=2&&Math.Abs(c.B-255)<=2),"Production hint pixels entered the generated ROI.");}
                report["capturedPhysicalSize"]=new int[] { image.Width,image.Height };report["blueHintPixelsInCapture"]=0;
            }
            Need(GetForegroundWindow()==hwnd&&Convert.ToInt64(health["inputPlaneRemainingAfterCleanup"])==0,"Source foreground or input plane cleanup failed.");report["ok"]=true;report["status"]="pass";
        }catch(EnvironmentInconclusive error){report["error"]=error.Message;report["inconclusive"]=true;report["status"]="inconclusive";}catch(Exception error){report["error"]=error.Message;report["status"]="failure";}
        finally {
            if(source!=null&&!source.IsDisposed)try{source.Invoke((Action)delegate { if(GetCapture()==hwnd)ReleaseCapture(); });}catch{}
            if(partialInput&&GetForegroundWindow()==hwnd)try{Send(new INPUT[] { Mouse(4) });}catch{}
            if(process!=null) {
                if(!process.HasExited&&GetForegroundWindow()==hwnd)try{Escape(hwnd);process.WaitForExit(3000);}catch{}
                if(!process.HasExited){process.Kill();process.WaitForExit(3000);}
                if(output!=null&&output.IsCompleted)try{report["helperDiagnostics"]=SafeReply(json.Deserialize<Dictionary<string,object>>(output.GetAwaiter().GetResult()));}catch{}
                process.Dispose();
            }
            if(source!=null&&!source.IsDisposed)try{source.Invoke((Action)delegate { source.Close(); });}catch{}
            if(!ui.Join(5000)){report["ok"]=false;report["cleanupError"]="Own generated source UI thread did not stop.";}ready.Dispose();
        }
        return report;
    }
    public static Dictionary<string,object> Run(string helper,string assembly) {
        List<Dictionary<string,object>> cases=new List<Dictionary<string,object>>();Dictionary<string,object> report=new Dictionary<string,object> {
            { "ok",false },{ "status","inconclusive" },{ "cases",cases },{ "syntheticIntegrityBoundary",true },{ "userContentCaptured",false },{ "clipboardAccessed",false },
            { "scope","Same-user self-restricted medium helper versus generated high ordinary non-fullscreen windows only. No elevation, credentials, UAC, security policy, desktop ACL or production change; not a normal filtered-token or physical owner-app acceptance claim." }
        };
        try {
            Need(!helper.Contains("\"")&&!assembly.Contains("\""),"Invalid helper path.");ownToken=ProcessToken(GetCurrentProcess());report["ownSourceToken"]=ownToken.Public();
            if(ownToken.Integrity!=12288||ownToken.UIAccess!=0){report["reason"]="This existing fixture process is not HIGH with UIAccess0. It will not elevate to manufacture the boundary.";return report;}
            SetProcessDpiAwarenessContext(new IntPtr(-4));Need(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero,"Controller physical DPI context failed.");
            bool ok=true,inconclusive=false;
            foreach(string backend in new string[] { "hybrid","planeOnly" })foreach(string kind in new string[] { "high-ordinary-source","high-topmost-source" }) {
                Dictionary<string,object> result=Case(helper,assembly,backend,kind);result["requestedInputBackend"]=backend;cases.Add(result);ok=ok&&(bool)result["ok"];inconclusive=inconclusive||result.ContainsKey("inconclusive");
            }
            report["ok"]=ok;report["status"]=ok?"pass":inconclusive?"incomplete":"failure";
        }catch(EnvironmentInconclusive error){report["reason"]=error.Message;}catch(Exception error){report["error"]=error.Message;report["status"]="failure";}
        return report;
    }
}
'@
    Add-Type -TypeDefinition $source -ReferencedAssemblies @([System.Windows.Forms.Form].Assembly.Location,[System.Drawing.Bitmap].Assembly.Location,[System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    $result=[EchoLingoIntegrityBoundarySmoke]::Run($HelperPath,$NativeAssemblyPath)
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 12 -Compress))
    if(-not $result.ok){exit 1}
} catch {
    [Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message;syntheticIntegrityBoundary=$true;userContentCaptured=$false;clipboardAccessed=$false}|ConvertTo-Json -Compress));exit 1
}
