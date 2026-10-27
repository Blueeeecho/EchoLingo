// Real installed Chromium, fresh owned profile and generated loopback page.
// Tests native selected-text acquisition; it does not launch EchoLingo/Tauri.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, readFile, lstat, realpath, rm, stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';
import { chromium } from '@playwright/test';
const here=path.dirname(fileURLToPath(import.meta.url));
const flags=new Map();
for(let i=2;i<process.argv.length;i+=2) flags.set(process.argv[i],process.argv[i+1]);
const report={ok:false,actualBrowserTested:false,actualApplicationTested:false,generatedLocalPageOnly:true,existingProfileAccessed:false,userContentRead:false,helperRetries:0,requiredCases:4,cases:[],externalPageRequests:0};
let root,profile,marker,browserProcess,bridgeProcess,browser,server,lineBridge;
const digest=async file=>createHash('sha256').update(await readFile(file)).digest('hex');
const bounded=(promise,ms,reason)=>new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error(reason)),ms);promise.then(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
class Lines {
  constructor(child){
    this.lines=[];this.waiters=[];this.closed=false;this.failure=null;
    const fail=reason=>{this.failure=new Error(reason);for(const next of this.waiters.splice(0)){clearTimeout(next.timer);next.reject(this.failure);}};
    child.once('error',()=>fail('BRIDGE_PROCESS_START_FAILED'));
    createInterface({input:child.stdout}).on('line',line=>{
      let item;try{item=JSON.parse(line.replace(/^\uFEFF/,''));}catch{fail('BRIDGE_NON_JSON_REPLY');return;}
      const next=this.waiters.shift();if(next){clearTimeout(next.timer);next.resolve(item);}else this.lines.push(item);
    }).on('close',()=>{this.closed=true;fail('BRIDGE_EOF');});
  }
  next(ms){if(this.lines.length)return Promise.resolve(this.lines.shift());if(this.failure)return Promise.reject(this.failure);return new Promise((resolve,reject)=>{const entry={resolve,reject};entry.timer=setTimeout(()=>{this.waiters=this.waiters.filter(value=>value!==entry);reject(new Error('BRIDGE_REPLY_DEADLINE'));},ms);this.waiters.push(entry);});}
  async request(command,ms=20000){bridgeProcess.stdin.write(JSON.stringify(command)+'\n');return this.next(ms);}
}
async function installedBrowser(){
  const candidates=[process.env['ProgramFiles(x86)']&&path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),process.env.ProgramFiles&&path.join(process.env.ProgramFiles,'Microsoft/Edge/Application/msedge.exe'),process.env.ProgramFiles&&path.join(process.env.ProgramFiles,'Google/Chrome/Application/chrome.exe')].filter(Boolean);
  for(const candidate of candidates){try{if((await stat(candidate)).isFile())return await realpath(candidate);}catch{}}
  throw new Error('INSTALLED_EDGE_OR_CHROME_UNAVAILABLE');
}
async function stopOwned(child){
  if(!child||child.exitCode!==null||child.signalCode!==null)return;
  const stop=spawn('taskkill.exe',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
  await bounded(new Promise((resolve,reject)=>{stop.once('error',reject);stop.once('exit',resolve);}),5000,'OWN_TREE_CLEANUP_DEADLINE');
  await bounded(new Promise(resolve=>{if(child.exitCode!==null||child.signalCode!==null)resolve();else child.once('exit',resolve);}),3000,'OWN_PROCESS_DID_NOT_EXIT');
}
try {
  assert.equal(process.platform,'win32','WINDOWS_REQUIRED');
  assert.equal(process.env.GITHUB_ACTIONS,'true','EPHEMERAL_GITHUB_REQUIRED');
  assert.equal(process.env.RUNNER_ENVIRONMENT,'github-hosted','GITHUB_HOSTED_REQUIRED');
  assert.ok(flags.has('--native-assembly'),'NATIVE_ASSEMBLY_REQUIRED');
  const helper=await realpath(flags.get('--helper')??path.join(here,'../src-tauri/native/windows.ps1'));
  const assembly=await realpath(flags.get('--native-assembly')??'');assert.equal(path.extname(assembly).toLowerCase(),'.dll');
  const executable=await installedBrowser();report.browserExecutableName=path.basename(executable);report.helperSha256=await digest(helper);report.nativeAssemblySha256=await digest(assembly);
  root=await mkdtemp(path.join(tmpdir(),'echolingo-browser-selection-'));marker=randomUUID();await writeFile(path.join(root,'.echolingo-owned'),marker,{flag:'wx'});profile=path.join(root,'profile');await mkdir(profile);
  const bodyText='EchoLingo generated browser body selection 13579 中文';
  const linkText='EchoLingo generated browser link selection 97531 中文';
  const areaText='EchoLingo generated textarea selection 58246 中文';
  const html='<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; connect-src \'none\'"><title>EchoLingo generated browser selection fixture</title><style>body{font:24px Segoe UI;padding:50px}textarea{display:block;width:650px;height:120px}</style><body tabindex="0"><p id="body-text">'+bodyText+'</p><a id="link" href="#generated">Generated focused link</a><p id="link-text">'+linkText+'</p><textarea id="area"></textarea><script>window.__copyCount=0;document.addEventListener("copy",()=>window.__copyCount++);</script>';
  server=createServer((request,response)=>{if(request.url!='/source'){response.writeHead(404);response.end();return;}response.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});response.end(html);});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const origin='http://127.0.0.1:'+server.address().port;const sourceUrl=origin+'/source';
  bridgeProcess=spawn(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',path.join(here,'windows-browser-selection-bridge.ps1'),'-HelperPath',helper,'-NativeAssemblyPath',assembly,'-BrowserExecutable',executable],{windowsHide:true,stdio:['pipe','pipe','pipe']});
  bridgeProcess.once('error',()=>{});bridgeProcess.stderr.on('data',data=>{report.bridgeStderrBytes=(report.bridgeStderrBytes??0)+data.length;});lineBridge=new Lines(bridgeProcess);const greeting=await lineBridge.next(10000);assert.equal(greeting.ready,true,'BRIDGE_STARTUP_FAILED');report.bridgeProcessId=greeting.bridgeProcessId;
  browserProcess=spawn(executable,['--user-data-dir='+profile,'--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-sync','--disable-extensions','--disable-quic','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--force-renderer-accessibility','--force-device-scale-factor=1','--enable-automation','--new-window','about:blank'],{windowsHide:false,stdio:'ignore'});
  browserProcess.once('error',()=>{});assert.ok(browserProcess.pid>0,'BROWSER_SPAWN_FAILED');report.browserRootProcessId=browserProcess.pid;
  const active=path.join(profile,'DevToolsActivePort');let port,endpoint;const deadline=Date.now()+10000;
  while(Date.now()<deadline){assert.equal(browserProcess.exitCode,null,'OWN_BROWSER_EXITED_BEFORE_DEBUG_READY');try{assert.equal((await lstat(active)).isSymbolicLink(),false);const fields=(await readFile(active,'utf8')).trim().split(/\r?\n/);port=Number(fields[0]);assert.ok(Number.isInteger(port)&&port>1024&&port<65536);assert.match(fields[1],/^\/devtools\/browser\/[a-zA-Z0-9-]+$/);endpoint='ws://127.0.0.1:'+port+fields[1];break;}catch{await sleep(50);}}
  assert.ok(endpoint,'OWN_PROFILE_DEBUG_ENDPOINT_NOT_CREATED');browser=await chromium.connectOverCDP(endpoint,{timeout:10000});
  const session=await browser.newBrowserCDPSession();const processes=await session.send('SystemInfo.getProcessInfo');const roots=processes.processInfo.filter(value=>value.type==='browser');assert.equal(roots.length,1);assert.equal(roots[0].id,browserProcess.pid,'CDP_BROWSER_PID_NOT_OWN_SPAWN');report.cdpRootProcessVerified=true;
  const commandLine=await session.send('Browser.getBrowserCommandLine');assert.ok(commandLine.arguments.includes('--user-data-dir='+profile),'CDP_PROFILE_NOT_OWN_FRESH_PROFILE');report.freshProfileCommandLineVerified=true;report.browserVersion=browser.version();
  const contexts=browser.contexts();assert.equal(contexts.length,1,'FRESH_CONTEXT_COUNT');const context=contexts[0];
  await context.route('**/*',route=>{if(route.request().url().startsWith(origin+'/'))return route.continue();report.externalPageRequests++;return route.abort();});
  const page=context.pages()[0]??await context.newPage();await page.goto(sourceUrl,{waitUntil:'load',timeout:10000});assert.equal(page.url(),sourceUrl);report.actualBrowserTested=true;
  const cases=[{name:'document-body',expected:bodyText,requiredRole:''},{name:'focused-link-document',expected:linkText,requiredRole:'ControlType.Hyperlink'},{name:'textarea-empty',expected:'',empty:true,requiredRole:'ControlType.Edit'},{name:'textarea-selection',expected:areaText,requiredRole:'ControlType.Edit'}];
  for(const test of cases){
    const row={name:test.name,ok:false};report.cases.push(row);await page.bringToFront();
    const prepared=await page.evaluate(({name,expected})=>{
      window.__copyCount=0;window.getSelection().removeAllRanges();const area=document.getElementById('area');area.value='';
      if(name==='textarea-empty'||name==='textarea-selection'){area.value=name==='textarea-empty'?'Generated unselected textarea original':expected;area.focus();area.setSelectionRange(0,name==='textarea-empty'?0:area.value.length);return {selection:area.value.slice(area.selectionStart,area.selectionEnd),active:document.activeElement.id,hasFocus:document.hasFocus()};}
      const node=document.getElementById(name==='document-body'?'body-text':'link-text');(name==='document-body'?document.body:document.getElementById('link')).focus();const range=document.createRange();range.selectNodeContents(node);window.getSelection().addRange(range);return {selection:window.getSelection().toString(),active:document.activeElement.id,hasFocus:document.hasFocus()};
    },{name:test.name,expected:test.expected});assert.equal(prepared.selection,test.expected);assert.equal(prepared.hasFocus,true,'GENERATED_DOM_NOT_FOCUSED');if(test.name==='focused-link-document')assert.equal(prepared.active,'link');
    const reply=await lineBridge.request({op:'case',browserPid:browserProcess.pid,expected:test.expected,empty:!!test.empty,requiredRole:test.requiredRole});Object.assign(row,reply);row.helperReportedOk=reply.ok;row.ok=false;assert.equal(reply.ok,true,'NATIVE_BROWSER_CASE_FAILED:'+test.name+':'+(reply.error??'unknown'));
    row.domCopyEvents=await page.evaluate(()=>window.__copyCount);assert.ok(row.domCopyEvents<=1,'COPY_RETRIED');if(test.empty)assert.equal(row.domCopyEvents,0,'EMPTY_TEXTAREA_COPIED');row.nativeClipboardCopyExercised=row.domCopyEvents===1;row.ok=true;
  }
  assert.equal(report.externalPageRequests,0,'GENERATED_PAGE_REQUESTED_EXTERNAL_RESOURCE');report.ok=true;
}catch(error){report.error=String(error.message).replace(/wss?:\/\/[^\s]+/g,'[owned-debug-endpoint]').slice(0,1024);report.setupInconclusive=report.cases.length===0||report.cases.at(-1)?.setupInconclusive===true;}
finally {
  try{if(lineBridge&&!lineBridge.closed)await lineBridge.request({op:'close'},3000);}catch{report.bridgeCloseIncomplete=true;}
  try{await stopOwned(bridgeProcess);report.ownBridgeStopped=true;}catch(error){report.ok=false;report.bridgeCleanupError=error.message;}
  try{if(browser)await bounded(browser.close(),3000,'CDP_DISCONNECT_DEADLINE');}catch{report.cdpDisconnectIncomplete=true;}
  try{await stopOwned(browserProcess);report.ownBrowserStopped=true;}catch(error){report.ok=false;report.browserCleanupError=error.message;}
  if(server){try{server.closeAllConnections();await bounded(new Promise(resolve=>server.close(resolve)),2000,'OWN_LOOPBACK_SERVER_CLEANUP_DEADLINE');report.ownLoopbackServerStopped=true;}catch(error){report.ok=false;report.serverCleanupError=error.message;}}
  if(root){try{assert.equal((await lstat(root)).isSymbolicLink(),false);assert.equal(await readFile(path.join(root,'.echolingo-owned'),'utf8'),marker);await rm(root,{recursive:true,maxRetries:10,retryDelay:100});report.ownedProfileRemoved=true;}catch(error){report.ok=false;report.profileCleanupError=error.message;}}
  report.executedCases=report.cases.length;report.passedCases=report.cases.filter(value=>value.ok).length;console.log(JSON.stringify(report));process.exitCode=report.ok?0:1;
}
