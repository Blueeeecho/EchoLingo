[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][int]$ApplicationProcessId,
    [Parameter(Mandatory=$true)][long]$ApplicationStartTimeUtcTicks,
    [Parameter(Mandatory=$true)][string]$ApplicationPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ApplicationSha256,
    [Parameter(Mandatory=$true)][long]$MainHwnd,
    [Parameter(Mandatory=$true)][ValidateRange(1024,65535)][int]$DebugPort,
    [Parameter(Mandatory=$true)][int]$TargetPhysicalX,
    [Parameter(Mandatory=$true)][int]$TargetPhysicalY,
    [switch]$IsolatedTestSession
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
# Isolated, geometry-only diagnostic. The original resize result is separate.
# Caller contract: the exact hash-pinned stage app was launched by the isolated
# fixture with its existing fresh WEBVIEW2_USER_DATA_FOLDER and a process-local
# WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=<unused-port>.
# Do not change registry/global environment, permissions, app code or point.
# The caller owns launch and MUST stop its own process tree in its existing
# finally, then verify this listener PID/port is gone and remove its own UDF.
# This helper creates no process and closes only its own CDP connection.

function Get-EchoLingoOwnedWebViewGeometry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][int]$ApplicationProcessId,
        [Parameter(Mandatory=$true)][long]$ApplicationStartTimeUtcTicks,
        [Parameter(Mandatory=$true)][string]$ApplicationPath,
        [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ApplicationSha256,
        [Parameter(Mandatory=$true)][long]$MainHwnd,
        [Parameter(Mandatory=$true)][ValidateRange(1024,65535)][int]$DebugPort,
        [Parameter(Mandatory=$true)][int]$TargetPhysicalX,
        [Parameter(Mandatory=$true)][int]$TargetPhysicalY
    )
    $phase = 'isolation'; $socket = $null
    $report = [ordered]@{ ok=$false; readOnlyGeometryProbe=$true; applicationProcessId=$ApplicationProcessId; port=$DebugPort }
    try {
        if (-not $script:IsolatedTestSession -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
            [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::UserInteractive) { throw 'ISOLATION_REQUIRED' }
        $phase = 'exact-app-identity'
        $app = [Diagnostics.Process]::GetProcessById($ApplicationProcessId)
        if ($app.StartTime.ToUniversalTime().Ticks -ne $ApplicationStartTimeUtcTicks -or
            $app.MainModule.FileName -ne (Resolve-Path -LiteralPath $ApplicationPath).Path -or
            (Get-FileHash -LiteralPath $ApplicationPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ApplicationSha256) { throw 'APP_IDENTITY_CHANGED' }

        function Test-GeometryProcessDescendant([int]$Child, [int]$Ancestor) {
            for ($depth=0; $Child -gt 0 -and $depth -lt 32; $depth++) {
                if ($Child -eq $Ancestor) { return $true }
                $row = Get-CimInstance Win32_Process -Filter ('ProcessId='+$Child) -Property ProcessId,ParentProcessId,Name
                if ($null -eq $row -or [int]$row.ParentProcessId -eq $Child) { return $false }
                $Child = [int]$row.ParentProcessId
            }
            return $false
        }
        $phase = 'native-snapshot-before'
        Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
        if ($null -eq ('EchoLingoOwnedGeometryNative' -as [type])) {
            $native = @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text; using System.Windows.Automation;
public static class EchoLingoOwnedGeometryNative {
    delegate bool EnumWindow(IntPtr window,IntPtr unused);
    [StructLayout(LayoutKind.Sequential)] struct R { public int l,t,r,b; }
    [StructLayout(LayoutKind.Sequential)] struct P { public int x,y; }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent,EnumWindow callback,IntPtr unused);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint owner);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint kind);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsChild(IntPtr parent,IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out R bounds);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window,out R bounds);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref P point);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int count);
    static string WindowClass(IntPtr w){var s=new StringBuilder(64);GetClassName(w,s,s.Capacity);return s.ToString();}
    static int[] Rect(IntPtr w,bool client){R r;bool ok=client?GetClientRect(w,out r):GetWindowRect(w,out r);if(!ok)return null;if(client){P a=new P{x=r.l,y=r.t},b=new P{x=r.r,y=r.b};if(!ClientToScreen(w,ref a)||!ClientToScreen(w,ref b))return null;r.l=a.x;r.t=a.y;r.r=b.x;r.b=b.y;}return new int[]{r.l,r.t,r.r,r.b};}
    static bool MainDocument(AutomationElement e,AutomationElement root){var p=TreeWalker.RawViewWalker.GetParent(e);for(int n=0;p!=null&&n<16;n++){if(Automation.Compare(p,root))return true;if(p.Current.ControlType==ControlType.Document)return false;p=TreeWalker.RawViewWalker.GetParent(p);}return false;}
    public static Dictionary<string,object> Capture(int process,long handle){
        IntPtr main=new IntPtr(handle);uint owner;GetWindowThreadProcessId(main,out owner);int count=0;
        EnumWindows(delegate(IntPtr w,IntPtr unused){uint p;GetWindowThreadProcessId(w,out p);if(p==process&&GetAncestor(w,2)==w&&WindowClass(w)=="Tauri Window")count++;return true;},IntPtr.Zero);
        if(owner!=process||count!=1||GetAncestor(main,2)!=main||WindowClass(main)!="Tauri Window"||!IsWindowVisible(main)||GetForegroundWindow()!=main)throw new InvalidOperationException("OWN_MAIN_NOT_UNIQUE_VISIBLE_FOREGROUND");
        var children=new List<object>();bool truncated=false;
        EnumChildWindows(main,delegate(IntPtr w,IntPtr unused){if(children.Count>=64){truncated=true;return false;}if(GetAncestor(w,2)!=main||!IsChild(main,w))return true;uint p;GetWindowThreadProcessId(w,out p);children.Add(new Dictionary<string,object>{{"hwnd",w.ToInt64()},{"ownerProcessId",p},{"rootIsMain",true},{"isChild",true},{"visible",IsWindowVisible(w)},{"isWryContainer",WindowClass(w)=="WRY_WEBVIEW"},{"outerPhysicalBounds",Rect(w,false)},{"clientPhysicalBounds",Rect(w,true)}});return true;},IntPtr.Zero);
        var documents=new List<object>();int docCount=-1;string docError=null;
        try{var root=AutomationElement.FromHandle(main);var docs=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document));docCount=docs.Count;
        for(int i=0;i<docs.Count&&i<16;i++){var e=docs[i];var v=e.Current;var b=v.BoundingRectangle;bool valid=!b.IsEmpty&&!double.IsInfinity(b.Left)&&!double.IsInfinity(b.Top)&&!double.IsInfinity(b.Right)&&!double.IsInfinity(b.Bottom)&&!double.IsNaN(b.Left)&&!double.IsNaN(b.Top)&&!double.IsNaN(b.Right)&&!double.IsNaN(b.Bottom);documents.Add(new Dictionary<string,object>{{"controlType",v.ControlType.Id},{"orientation",(int)v.Orientation},{"isOffscreen",v.IsOffscreen},{"mainDocumentVerified",MainDocument(e,root)},{"physicalBounds",valid?(object)new double[]{b.Left,b.Top,b.Right,b.Bottom}:null}});}}catch(Exception e){docError=e.GetType().FullName;}
        return new Dictionary<string,object>{{"mainHwnd",handle},{"mainOwnerProcessId",owner},{"mainCandidateCount",count},{"dpi",GetDpiForWindow(main)},{"outerPhysicalBounds",Rect(main,false)},{"clientPhysicalBounds",Rect(main,true)},{"children",children},{"childrenTruncated",truncated},{"documents",documents},{"documentCount",docCount},{"documentsTruncated",docCount>16},{"documentExceptionType",docError}};
    }
}
'@
            $refs = @([Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ControlType].Assembly.Location,[Windows.Rect].Assembly.Location) | Select-Object -Unique
            Add-Type -TypeDefinition $native -ReferencedAssemblies $refs -Language CSharp
        }
        $before = [EchoLingoOwnedGeometryNative]::Capture($ApplicationProcessId,$MainHwnd)
        $report['nativeBefore'] = $before
        if ($before.childrenTruncated -or $before.documentsTruncated) { throw 'NATIVE_GEOMETRY_TRUNCATED' }
        $viewHosts = @($before.children | Where-Object { $_.visible -and $_.isWryContainer })
        if ($viewHosts.Count -ne 1 -or $null -eq $viewHosts[0].clientPhysicalBounds) { throw 'OWN_WRY_CONTAINER_NOT_UNIQUE' }
        $phase = 'loopback-listener-ownership'
        $listeners = @(Get-NetTCPConnection -LocalPort $DebugPort -State Listen -ErrorAction Stop)
        $owners = @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)
        if ($listeners.Count -eq 0 -or $owners.Count -ne 1 -or
            @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1','::1') }).Count -ne 0) { throw 'NO_UNIQUE_LOOPBACK_LISTENER' }
        $browserId = [int]$owners[0]
        $browser = Get-CimInstance Win32_Process -Filter ('ProcessId='+$browserId) -Property ProcessId,ParentProcessId,Name
        if ($null -eq $browser -or $browser.Name -ne 'msedgewebview2.exe' -or
            -not (Test-GeometryProcessDescendant $browserId $ApplicationProcessId)) { throw 'LISTENER_NOT_OWN_WEBVIEW' }
        $report['listenerProcessId'] = $browserId
        $report['listenerStartTimeUtcTicks'] = ([Diagnostics.Process]::GetProcessById($browserId)).StartTime.ToUniversalTime().Ticks
        $linked = @($before.children | Where-Object { $_.visible -and (Test-GeometryProcessDescendant ([int]$_.ownerProcessId) $browserId) })
        if ($linked.Count -eq 0) { throw 'LISTENER_NOT_LINKED_TO_OWN_MAIN_CHILDREN' }

        $phase = 'unique-own-page'
        $request = [Net.HttpWebRequest]::Create(('http://127.0.0.1:'+ $DebugPort + '/json/list'))
        $request.Proxy=$null; $request.Timeout=3000; $request.ReadWriteTimeout=3000; $request.AllowAutoRedirect=$false; $response=$request.GetResponse()
        try { $reader=[IO.StreamReader]::new($response.GetResponseStream());try{$text=[Text.StringBuilder]::new();$chars=New-Object char[] 4096;while(($count=$reader.Read($chars,0,$chars.Length)) -gt 0){if($text.Length+$count -gt 65536){throw 'TARGET_METADATA_LIMIT'};[void]$text.Append($chars,0,$count)};$metadata=$text.ToString()}finally{$reader.Dispose()} } finally { $response.Dispose() }
        # Never log target titles/full URLs. Keep only the unique app-origin page.
        $pages = @((ConvertFrom-Json $metadata) | Where-Object { $_.type -eq 'page' -and ([Uri]$_.url).Scheme -in @('http','https') -and ([Uri]$_.url).Host -eq 'tauri.localhost' })
        if ($pages.Count -ne 1) { throw 'OWN_APP_PAGE_NOT_UNIQUE' }
        $endpoint = [Uri]$pages[0].webSocketDebuggerUrl
        if ($endpoint.Scheme -ne 'ws' -or $endpoint.Host -notin @('127.0.0.1','localhost','::1') -or $endpoint.Port -ne $DebugPort -or -not $endpoint.AbsolutePath.StartsWith('/devtools/page/')) { throw 'UNEXPECTED_CDP_ENDPOINT' }
        $socket=[Net.WebSockets.ClientWebSocket]::new();$socket.Options.Proxy=$null
        $connect=[Threading.CancellationTokenSource]::new(5000)
        try{$socket.ConnectAsync($endpoint,$connect.Token).GetAwaiter().GetResult()}finally{$connect.Dispose()}
        function Invoke-GeometryCdp([int]$Id,[string]$Method,$Params) {
            $token=[Threading.CancellationTokenSource]::new(5000)
            try {
                $bytes=[Text.Encoding]::UTF8.GetBytes((@{id=$Id;method=$Method;params=$Params}|ConvertTo-Json -Depth 8 -Compress))
                $socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$token.Token).GetAwaiter().GetResult()
                for($messages=0;$messages -lt 32;$messages++){
                    $buffer=New-Object byte[] 8192;$memory=[IO.MemoryStream]::new()
                    try{do{$read=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$token.Token).GetAwaiter().GetResult();if($read.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text){throw 'UNEXPECTED_CDP_MESSAGE'};$memory.Write($buffer,0,$read.Count);if($memory.Length -gt 65536){throw 'CDP_RESPONSE_LIMIT'}}while(-not $read.EndOfMessage);$message=ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($memory.ToArray()))}finally{$memory.Dispose()}
                    if($message.id -eq $Id){if($null -ne $message.error){throw 'CDP_COMMAND_FAILED'};return $message.result}
                }
                throw 'CDP_RESPONSE_NOT_FOUND'
            } finally { $token.Dispose() }
        }
        $phase = 'read-only-layout-metrics'
        $metrics=Invoke-GeometryCdp 1 'Page.getLayoutMetrics' @{}
        $client=$viewHosts[0].clientPhysicalBounds
        # Fixed numeric inputs only. No app function, IPC, DOM mutation, storage,
        # network instrumentation, Text/Value/HTML, screenshot or clipboard reads.
        $expression=@'
(()=>{const ratio=window.devicePixelRatio||1;const x=(__PX__-__CX__)/ratio,y=(__PY__-__CY__)/ratio;const e=document.querySelector('.popup-resize-edge[data-window-resize="east"]');const b=e?e.getBoundingClientRect():null,s=e?getComputedStyle(e):null;const box=r=>r?{left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:r.width,height:r.height}:null;const hit=(a,z)=>{const h=document.elementFromPoint(a,z),v=h?h.closest('[data-window-resize]'):null,d=v?v.getAttribute('data-window-resize'):null;return{isNull:h===null,isEast:h===e,insideEast:!!(e&&h&&e.contains(h)),resizeDirection:['east','west','north','south','north-east','north-west','south-east','south-west'].includes(d)?d:null}};const view=document.body.dataset.view;return{innerWidth:innerWidth,innerHeight:innerHeight,documentClientWidth:document.documentElement.clientWidth,documentClientHeight:document.documentElement.clientHeight,bodyClientWidth:document.body.clientWidth,bodyClientHeight:document.body.clientHeight,devicePixelRatio:ratio,view:['translate','settings','history'].includes(view)?view:'other',east:{present:!!e,rect:box(b),display:s?s.display:null,visibility:s?s.visibility:null,pointerEvents:s?s.pointerEvents:null},originalPoint:{x,y,hit:hit(x,y)},eastCenter:b?{x:(b.left+b.right)/2,y:(b.top+b.bottom)/2,hit:hit((b.left+b.right)/2,(b.top+b.bottom)/2)}:null}})()
'@
        $expression=$expression.Replace('__PX__',[string]$TargetPhysicalX).Replace('__PY__',[string]$TargetPhysicalY).Replace('__CX__',[string]$client[0]).Replace('__CY__',[string]$client[1])
        $value=Invoke-GeometryCdp 2 'Runtime.evaluate' @{expression=$expression;returnByValue=$true;awaitPromise=$false;userGesture=$false}
        if($null -ne $value.exceptionDetails -or $null -eq $value.result.value){throw 'READ_ONLY_GEOMETRY_EVALUATION_FAILED'}
        $report['dom']=$value.result.value
        $report['cdpLayoutViewport']=$metrics.cssLayoutViewport
        $report['cdpVisualViewport']=$metrics.cssVisualViewport
        $phase='native-snapshot-after';$report['nativeAfter']=[EchoLingoOwnedGeometryNative]::Capture($ApplicationProcessId,$MainHwnd)
        $report['nativeMainBoundsStable']=([string]::Join(',',$before.clientPhysicalBounds) -eq [string]::Join(',',$report.nativeAfter.clientPhysicalBounds))
        $report['ok']=$true
    } catch { $report['failedPhase']=$phase; $report['exceptionType']=$_.Exception.GetType().FullName }
    finally {
        if($null -ne $socket){$socket.Dispose()}
        $report['cdpConnectionDisposed']=$true
        $report['callerMustStopOwnTreeAndVerifyPortClosed']=$true
    }
    return $report
}

try {
    $result=Get-EchoLingoOwnedWebViewGeometry -ApplicationProcessId $ApplicationProcessId -ApplicationStartTimeUtcTicks $ApplicationStartTimeUtcTicks -ApplicationPath $ApplicationPath -ApplicationSha256 $ApplicationSha256 -MainHwnd $MainHwnd -DebugPort $DebugPort -TargetPhysicalX $TargetPhysicalX -TargetPhysicalY $TargetPhysicalY
    $result | ConvertTo-Json -Depth 14 -Compress
    if (-not $result.ok) { exit 2 }
} catch { [ordered]@{ok=$false;readOnlyGeometryProbe=$true;failedPhase='helper-entry';exceptionType=$_.Exception.GetType().FullName}|ConvertTo-Json -Compress; exit 2 }
