# Exact production query worker, scalar callbacks only; no UIA provider warm-up.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$NativeAssemblyPath,[switch]$IsolatedTestSession)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
try {
    if (-not $IsolatedTestSession -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'ISOLATION_REQUIRED: Ephemeral GitHub Windows test only.' }
    $assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $NativeAssemblyPath).Path)
    $native = $assembly.GetType('EchoLingoNative',$true)
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Threading;
public static class SelectionQueryFixture {
    static void Need(bool value,string reason){if(!value)throw new InvalidOperationException(reason);}
    public static Dictionary<string,object> Run(Type native){
        MethodInfo query=native.GetMethod("SelectionQuery",BindingFlags.NonPublic|BindingFlags.Static).MakeGenericMethod(typeof(int));
        Func<Func<int>,int> invoke=delegate(Func<int> call){try{return (int)query.Invoke(null,new object[]{call});}catch(TargetInvocationException e){throw e.InnerException;}};
        int first=0;for(int i=0;i<200;i++){int id=invoke(delegate{Need(Thread.CurrentThread.GetApartmentState()==ApartmentState.MTA,"NOT_MTA");return Thread.CurrentThread.ManagedThreadId;});if(i==0)first=id;Need(first==id,"UIA_WORKER_THREAD_CHANGED");}
        ManualResetEvent release=new ManualResetEvent(false),entered=new ManualResetEvent(false);int forbidden=0;double elapsed;
        try{
            Stopwatch clock=Stopwatch.StartNew();bool timedOut=false;try{invoke(delegate{entered.Set();release.WaitOne();return 1;});}catch(InvalidOperationException e){timedOut=e.Message.StartsWith("SELECTION:")&&e.Message.Contains("did not answer in time");}elapsed=clock.Elapsed.TotalMilliseconds;
            Need(entered.WaitOne(0)&&timedOut,"PRODUCTION_DEADLINE_NOT_ENFORCED");Need(elapsed>=2000&&elapsed<3000,"SCALAR_TIMEOUT_CALLER_NOT_BOUNDED");
            for(int phase=0;phase<2;phase++){
                if(phase==1){release.Set();Thread worker=(Thread)native.GetNestedType("SelectionAutomationWorker",BindingFlags.NonPublic).GetField("thread",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(native.GetField("selectionWorker",BindingFlags.NonPublic|BindingFlags.Static).GetValue(null));Need(worker.Join(1000),"ABANDONED_WORKER_NOT_DRAINED");}
                bool rejected=false;try{invoke(delegate{return Interlocked.Increment(ref forbidden);});}catch(InvalidOperationException e){rejected=e.Message.Contains("worker is unavailable");}Need(rejected&&forbidden==0,"QUERY_QUEUED_AFTER_TIMEOUT");
            }
        }finally{release.Set();/* A failed assertion must not abort a provider thread. */}
        release.Dispose();entered.Dispose();return new Dictionary<string,object>{{"ok",true},{"sameMtaThreadCalls",200},{"deadlineMilliseconds",2000},{"observedTimeoutMilliseconds",elapsed},{"rejectedBeforeAndAfterDrain",true},{"forbiddenCallbacksExecuted",forbidden},{"actualUiaProviderTested",false},{"desktopInputSent",false},{"productionQueryImported",true}};
    }
}
'@
    Add-Type -TypeDefinition $source
    [SelectionQueryFixture]::Run($native) | ConvertTo-Json -Compress
} catch { [ordered]@{ok=$false;error=$_.Exception.Message;actualUiaProviderTested=$false;desktopInputSent=$false} | ConvertTo-Json -Compress; exit 1 }
