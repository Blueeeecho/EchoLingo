// One actual installed browser, fresh owned profile, one real Alt+S and ROI drag.
// Translation is the sole mocked service; OCR is the packaged local WinRT path.
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
import { startupObservation } from './browser-startup-observation.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const flags=new Map();
for(let i=2;i<process.argv.length;i+=2) flags.set(process.argv[i],process.argv[i+1]);
const digest=async file=>createHash('sha256').update(await readFile(file)).digest('hex');
const bounded=(promise,ms,reason)=>new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error(reason)),ms);promise.then(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
class Lines {
  constructor(child){
    this.child=child;this.lines=[];this.waiters=[];this.closed=false;this.failure=null;
    const fail=reason=>{this.failure=new Error(reason);for(const next of this.waiters.splice(0)){clearTimeout(next.timer);next.reject(this.failure);}};
    child.once('error',()=>fail('BRIDGE_PROCESS_START_FAILED'));
    child.stdin.on('error',()=>fail('BRIDGE_STDIN_CLOSED'));
    createInterface({input:child.stdout}).on('line',line=>{
      let item;try{item=JSON.parse(line.replace(/^\uFEFF/,''));}catch{fail('BRIDGE_NON_JSON_REPLY');return;}
      const next=this.waiters.shift();if(next){clearTimeout(next.timer);next.resolve(item);}else this.lines.push(item);
    }).on('close',()=>{this.closed=true;fail('BRIDGE_EOF');});
  }
  next(ms){if(this.lines.length)return Promise.resolve(this.lines.shift());if(this.failure)return Promise.reject(this.failure);return new Promise((resolve,reject)=>{const entry={resolve,reject};entry.timer=setTimeout(()=>{this.waiters=this.waiters.filter(value=>value!==entry);reject(new Error('BRIDGE_REPLY_DEADLINE'));},ms);this.waiters.push(entry);});}
  async request(command,ms=20000){this.child.stdin.write(JSON.stringify(command)+'\n');return this.next(ms);}
}
async function installedBrowsers(){
  const roots=[process.env['ProgramFiles(x86)'],process.env.ProgramFiles].filter(Boolean);const found=[];
  for(const [kind,relative] of [['edge','Microsoft/Edge/Application/msedge.exe'],['chrome','Google/Chrome/Application/chrome.exe']]){
    for(const base of roots){try{const executable=await realpath(path.join(base,relative));if((await stat(executable)).isFile()){found.push({kind,executable});break;}}catch{}}
  }
  return found;
}
async function stopOwned(child){
  if(!child||child.exitCode!==null||child.signalCode!==null)return;
  const stop=spawn('taskkill.exe',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
  await bounded(new Promise((resolve,reject)=>{stop.once('error',reject);stop.once('exit',resolve);}),5000,'OWN_TREE_CLEANUP_DEADLINE');
  await bounded(new Promise(resolve=>{if(child.exitCode!==null||child.signalCode!==null)resolve();else child.once('exit',resolve);}),3000,'OWN_PROCESS_DID_NOT_EXIT');
}
const source='EchoLingo OCR visibility 2468';
const report={ok:false,test:'browser-ocr-same-source-visibility',requiredCases:1,actualShortcutPresses:0,actualBrowserTested:false,actualApplicationTested:false,generatedLocalPageOnly:true,existingProfileAccessed:false,userContentRead:false,sourceUiaCalls:0,preHotkeyAppUiaCalls:0,fixedFrontendWarmupMilliseconds:0,forcedRendererAccessibility:false,helperRetries:0,fakeIpcUsed:false,ocrBackend:'actual packaged WinRT local OCR',translationBackend:'generated-loopback-mock',osColdBootTested:false,externalPageRequests:0};
let root,marker,browserProcess,bridgeProcess,browser,server,lines,phase='host-preparation';
let mockCount=0,mockError=null;
async function nativePoint(page,pid,point){
  await page.evaluate(()=>{window.__lastNativePointer=null;});
  const guard=await lines.request({op:'mouse-point',browserPid:pid,x:point.x,y:point.y},5000);assert.equal(guard.ok,true,'NATIVE_POINTER_GUARD_FAILED');
  await page.waitForFunction(({x,y})=>window.__lastNativePointer&&Math.abs(window.__lastNativePointer.screenX-x)<=1&&Math.abs(window.__lastNativePointer.screenY-y)<=1,{x:point.x,y:point.y},{timeout:2000});
  const actual=await page.evaluate(()=>window.__lastNativePointer);assert.ok(Math.abs(actual.clientX-point.clientX)<=1&&Math.abs(actual.clientY-point.clientY)<=1,'NATIVE_SCREEN_VIEWPORT_MAPPING_MISMATCH');
  return {...guard,screenToViewportMappingVerified:true};
}
try{
  assert.equal(process.platform,'win32','WINDOWS_REQUIRED');assert.equal(process.env.GITHUB_ACTIONS,'true','EPHEMERAL_GITHUB_REQUIRED');assert.equal(process.env.RUNNER_ENVIRONMENT,'github-hosted','GITHUB_HOSTED_REQUIRED');
  const kind=flags.get('--browser');assert.ok(kind==='edge'||kind==='chrome','EXPLICIT_SINGLE_BROWSER_REQUIRED');report.browserKind=kind;
  const installed=await installedBrowsers(),candidate=installed.find(item=>item.kind===kind);assert.ok(candidate,'REQUESTED_INSTALLED_BROWSER_REQUIRED');
  assert.ok(flags.has('--application'),'PACKAGED_APPLICATION_REQUIRED');const application=await realpath(flags.get('--application'));
  const sha256=flags.get('--expected-application-sha256')??'8490a973c9e4f4568b851f61524a4ef8f554d8b3a506b12dd19ba34f0dd22a4b',bytes=Number(flags.get('--expected-application-bytes')??5825536);assert.match(sha256,/^[a-f0-9]{64}$/);assert.ok(Number.isSafeInteger(bytes)&&bytes>0);assert.equal((await stat(application)).size,bytes,'EXACT_APPLICATION_BYTES');assert.equal(await digest(application),sha256,'EXACT_APPLICATION_SHA256');report.applicationSha256=sha256;report.applicationBytes=bytes;
  root=await mkdtemp(path.join(tmpdir(),'echolingo-browser-ocr-visibility-'));marker=randomUUID();await writeFile(path.join(root,'.echolingo-owned'),marker,{flag:'wx'});const profile=path.join(root,'profile');await mkdir(profile);
  const translation='Generated OCR mock '+kind+' '+marker;
  const html='<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; connect-src \'none\'"><title>EchoLingo generated OCR visibility fixture</title><style>html,body{margin:0;min-height:100%;background:white}body{min-height:100vh;outline:0}#roi{position:absolute;left:24px;top:70px;width:calc(100vw - 48px);max-width:1000px;height:140px;box-sizing:border-box;background:white;color:black;display:flex;align-items:center;padding-left:20px;font:34px Segoe UI,sans-serif;white-space:nowrap;user-select:none}</style><body tabindex="0"><div id="roi">'+source+'</div><script>window.__copyCount=0;window.__mouseDowns=0;window.__mouseUps=0;window.__lastUpButtons=null;window.__lastDownWasBlank=false;document.addEventListener("copy",()=>window.__copyCount++);document.addEventListener("mousedown",e=>{window.__mouseDowns++;window.__lastDownWasBlank=e.target===document.body||e.target===document.documentElement;});document.addEventListener("mouseup",e=>{window.__mouseUps++;window.__lastUpButtons=e.buttons;});document.addEventListener("mousemove",e=>{window.__lastNativePointer={screenX:e.screenX,screenY:e.screenY,clientX:e.clientX,clientY:e.clientY};});</script>';
  server=createServer(async(request,response)=>{
    if(request.url==='/translate'){
      try{assert.equal(request.method,'POST','MOCK_METHOD');assert.equal(request.headers.authorization,undefined,'MOCK_AUTHORIZATION_FORBIDDEN');let size=0,chunks=[];for await(const chunk of request){size+=chunk.length;assert.ok(size<=65536,'MOCK_BODY_BOUND');chunks.push(chunk);}const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));assert.equal(typeof body.q,'string');assert.equal(body.q.toLowerCase(),source.toLowerCase(),'MOCK_NON_GENERATED_SOURCE');assert.ok(!body.api_key,'MOCK_CREDENTIAL_FORBIDDEN');assert.equal(body.format,'text');mockCount++;response.writeHead(200,{'Content-Type':'application/json'});response.end(JSON.stringify({translatedText:translation}));}
      catch{mockError='MOCK_REQUEST_REJECTED';response.writeHead(400);response.end('{}');}return;
    }
    if(request.url!='/source'){response.writeHead(404);response.end();return;}response.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});response.end(html);
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});const origin='http://127.0.0.1:'+server.address().port,sourceUrl=origin+'/source';
  phase='app-isolated-startup';bridgeProcess=spawn(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',path.join(here,'windows-browser-ocr-visibility-bridge.ps1'),'-BrowserExecutable',candidate.executable,'-ApplicationPath',application,'-MockBaseUrl',origin,'-ProviderId','generated-browser-'+marker,'-ExpectedApplicationSha256',sha256,'-ExpectedApplicationBytes',String(bytes),...(flags.get('--legacy-capture')==='true'?['-LegacyCapture']:['-NativeCapturePath',flags.get('--native-capture')??''])],{windowsHide:true,stdio:['pipe','pipe','pipe']});bridgeProcess.stderr.on('data',data=>{report.bridgeStderrBytes=(report.bridgeStderrBytes??0)+data.length;});lines=new Lines(bridgeProcess);const greeting=await lines.next(65000);report.bridgeStartup=greeting;assert.equal(greeting.ready,true,'BRIDGE_STARTUP_FAILED');report.actualApplicationTested=true;assert.equal(greeting.application.captureBackendEnvironmentAbsent,flags.get('--legacy-capture')!=='true','CAPTURE_DEFAULT_ENVIRONMENT_MISMATCH');
  phase='fresh-browser-preparation';const startup=startupObservation();const startupStarted=Date.now();browserProcess=spawn(candidate.executable,['--user-data-dir='+profile,'--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-sync','--disable-extensions','--disable-quic','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--force-device-scale-factor=1','--enable-automation','--start-maximized','--new-window','about:blank'],{windowsHide:false,stdio:['ignore','ignore','pipe']});browserProcess.once('error',error=>startup.spawnedError(error));browserProcess.once('exit',(code,signal)=>startup.exited(code,signal));browserProcess.stderr.on('data',data=>startup.stderr(data));report.browserRootProcessId=browserProcess.pid;
  const active=path.join(profile,'DevToolsActivePort');let endpoint;const deadline=Date.now()+10000;
  try {
    assert.ok(browserProcess.pid>0,'BROWSER_SPAWN_FAILED');
    while(Date.now()<deadline){
      startup.state.pollCount=Math.min(startup.state.pollCount+1,10000);
      assert.equal(browserProcess.exitCode,null,'OWN_BROWSER_EXITED_BEFORE_DEBUG_READY');
      try {
        startup.stage('stat');const metadata=await lstat(active);startup.file(metadata);
        startup.stage('file-type');assert.equal(metadata.isSymbolicLink(),false);
        startup.stage('read');const fields=(await readFile(active,'utf8')).trim().split(/\r?\n/);
        startup.stage('port');const port=Number(fields[0]);assert.ok(Number.isInteger(port)&&port>1024&&port<65536);
        startup.stage('path');assert.match(fields[1],/^\/devtools\/browser\/[a-zA-Z0-9-]+$/);
        endpoint='ws://127.0.0.1:'+port+fields[1];startup.state.formatValid=true;startup.stage('ready');break;
      }catch(error){startup.error(error);await sleep(50);}
    }
    assert.ok(endpoint,'OWN_DEBUG_ENDPOINT_NOT_CREATED');
  } finally {report.browserStartupObservation=startup.snapshot(browserProcess,Date.now()-startupStarted);}
  browser=await chromium.connectOverCDP(endpoint,{timeout:10000});
  const session=await browser.newBrowserCDPSession(),processes=await session.send('SystemInfo.getProcessInfo'),roots=processes.processInfo.filter(item=>item.type==='browser');assert.equal(roots.length,1);assert.equal(roots[0].id,browserProcess.pid,'CDP_BROWSER_NOT_OWN_SPAWN');report.cdpRootProcessVerified=true;const commandLine=await session.send('Browser.getBrowserCommandLine');assert.ok(commandLine.arguments.includes('--user-data-dir='+profile),'CDP_PROFILE_NOT_FRESH_OWN_PROFILE');assert.ok(!commandLine.arguments.some(value=>value.startsWith('--force-renderer-accessibility')));report.freshProfileCommandLineVerified=true;report.browserVersion=browser.version();
  const contexts=browser.contexts();assert.equal(contexts.length,1,'FRESH_CONTEXT_COUNT');const context=contexts[0];await context.route('**/*',route=>{if(route.request().url().startsWith(origin+'/'))return route.continue();report.externalPageRequests++;return route.abort();});const page=context.pages()[0]??await context.newPage();await page.goto(sourceUrl,{waitUntil:'load',timeout:10000});await page.bringToFront();assert.equal(page.url(),sourceUrl);report.actualBrowserTested=true;
  phase='roi-preparation';const prepared=await page.evaluate(expected=>{
    document.body.focus();const element=document.getElementById('roi'),r=element.getBoundingClientRect(),border=(outerWidth-innerWidth)/2;
    if(element.textContent!==expected||!document.hasFocus()||devicePixelRatio!==1||r.left<1||r.top<1||r.right>innerWidth-1||r.bottom>innerHeight-1||element.scrollWidth>element.clientWidth)throw new Error('GENERATED_ROI_NOT_READY');
    return {origin:{x:screenX+border,y:screenY+outerHeight-innerHeight-border},roi:{left:r.left+2,top:r.top+2,right:r.right-2,bottom:r.bottom-2},viewport:[innerWidth,innerHeight],hasFocus:document.hasFocus(),initialMouseDowns:window.__mouseDowns,initialMouseUps:window.__mouseUps};
  },source);assert.equal(prepared.initialMouseDowns,0);assert.equal(prepared.initialMouseUps,0);const start={x:Math.round(prepared.origin.x+prepared.roi.left),y:Math.round(prepared.origin.y+prepared.roi.top),clientX:prepared.roi.left,clientY:prepared.roi.top},end={x:Math.round(prepared.origin.x+prepared.roi.right),y:Math.round(prepared.origin.y+prepared.roi.bottom)};report.roiPreparation={...prepared,nativeStartGuard:await nativePoint(page,browserProcess.pid,start)};
  phase='product-ocr-path';report.productOcrInvocationRequested=true;const ocr=await lines.request({op:'ocr-case',browserPid:browserProcess.pid,x:start.x,y:start.y,endX:end.x,endY:end.y,expectedTranslation:translation},90000);report.ocr=ocr;report.actualShortcutPresses=ocr.actualShortcutPresses??0;assert.equal(ocr.ok,true,'ACTUAL_OCR_CASE_FAILED');if(flags.get('--legacy-capture')!=='true'){assert.equal(ocr.nativeCaptureBackendByVerifiedExecutable,1,'NATIVE_EXECUTABLE_BACKEND_NOT_VERIFIED');assert.equal(ocr.exactNativeChildBytesVerified,true);assert.equal(ocr.defaultCaptureEnvironmentAbsent,true);}assert.equal(mockError,null,'MOCK_REQUEST_REJECTED');assert.equal(mockCount,1,'OCR_MUST_MAKE_ONE_NEW_MOCK_REQUEST');
  const afterOcr=await page.evaluate(()=>({text:document.getElementById('roi').textContent,hasFocus:document.hasFocus(),mouseDowns:window.__mouseDowns,mouseUps:window.__mouseUps,copyEvents:window.__copyCount}));report.generatedPageAfterOcr=afterOcr;assert.equal(afterOcr.text,source);assert.equal(afterOcr.hasFocus,true,'OCR_CHANGED_BROWSER_DOCUMENT_FOCUS');assert.equal(afterOcr.mouseDowns,0,'OCR_ROI_DOWN_LEAKED_TO_BROWSER');assert.equal(afterOcr.mouseUps,0,'OCR_ROI_UP_LEAKED_TO_BROWSER');assert.equal(afterOcr.copyEvents,0,'OCR_UNEXPECTED_SOURCE_COPY');
  phase='outside-click-preparation';const blank=await page.evaluate(()=>{const clientX=6,clientY=innerHeight-8,border=(outerWidth-innerWidth)/2,hit=document.elementFromPoint(clientX,clientY);if((hit!==document.body&&hit!==document.documentElement)||!document.hasFocus())throw new Error('GENERATED_BLANK_NOT_READY');return {x:Math.round(screenX+border+clientX),y:Math.round(screenY+outerHeight-innerHeight-border+clientY),clientX,clientY};});report.blankPointerGuard=await nativePoint(page,browserProcess.pid,blank);
  phase='product-same-source-click';const click=await lines.request({op:'outside-click',browserPid:browserProcess.pid,x:blank.x,y:blank.y},6000);report.sameSourceClick=click;
  await page.waitForFunction(()=>window.__mouseUps===1&&window.__lastUpButtons===0,null,{timeout:2000});const final=await page.evaluate(()=>({mouseDowns:window.__mouseDowns,mouseUps:window.__mouseUps,upButtons:window.__lastUpButtons,lastDownWasBlank:window.__lastDownWasBlank,copyEvents:window.__copyCount,hasFocus:document.hasFocus(),text:document.getElementById('roi').textContent}));report.generatedPageAfterClick=final;assert.equal(final.mouseDowns,1,'EXACTLY_ONE_BROWSER_BLANK_DOWN_REQUIRED');assert.equal(final.mouseUps,1,'EXACTLY_ONE_BROWSER_BLANK_UP_REQUIRED');assert.equal(final.lastDownWasBlank,true);assert.equal(final.copyEvents,0);assert.equal(final.hasFocus,true);assert.equal(final.text,source);assert.equal(click.ok,true,'SAME_SOURCE_CLICK_DID_NOT_HIDE_POPUP');assert.equal(click.outsideClickPairsSent,1);assert.equal(mockCount,1,'CLICK_MUST_NOT_TRANSLATE_AGAIN');assert.equal(report.externalPageRequests,0,'EXTERNAL_PAGE_REQUESTS');report.ok=true;report.executedCases=1;report.passedCases=1;
}catch(error){report.error=String(error.message).replace(/wss?:\/\/[^\s]+/g,'[owned-debug-endpoint]').slice(0,1024);report.phase=phase;report.actualShortcutCountKnown=!report.productOcrInvocationRequested||!!report.ocr;report.setupInconclusive=report.actualShortcutCountKnown&&(report.actualShortcutPresses??0)===0;if(!report.actualShortcutCountKnown)report.actualShortcutPresses=null;report.failureClassification=report.sameSourceClick?.failureClassification??report.ocr?.failureClassification??(phase==='product-same-source-click'?'product-same-source-click':phase==='outside-click-preparation'?'outside-click-preparation':!report.actualShortcutCountKnown?'product-ocr-observation-incomplete':report.setupInconclusive?'roi-preparation-inconclusive':'product-ocr-path');}
finally{
  report.newMockRequests=mockCount;report.mockError=mockError;
  try{if(lines&&!lines.closed){const closing=await lines.request({op:'close'},30000);report.applicationCleanup=closing.applicationCleanup;assert.equal(closing.ok,true,'OWN_APPLICATION_CLEANUP_FAILED');}}catch{report.ok=false;report.bridgeCloseIncomplete=true;}
  try{if(bridgeProcess){await stopOwned(bridgeProcess);report.ownBridgeStopped=true;}}catch(error){report.ok=false;report.bridgeCleanupError=error.message;}
  try{if(browser)await bounded(browser.close(),3000,'CDP_CLOSE_DEADLINE');}catch{report.cdpDisconnectIncomplete=true;}
  try{if(browserProcess){await stopOwned(browserProcess);report.ownBrowserStopped=true;}}catch(error){report.ok=false;report.browserCleanupError=error.message;}
  if(server)try{server.closeAllConnections();await bounded(new Promise(resolve=>server.close(resolve)),2000,'OWN_LOOPBACK_CLEANUP_DEADLINE');report.ownLoopbackServerStopped=true;}catch(error){report.ok=false;report.serverCleanupError=error.message;}
  if(root)try{assert.equal((await lstat(root)).isSymbolicLink(),false);assert.equal(await readFile(path.join(root,'.echolingo-owned'),'utf8'),marker);await rm(root,{recursive:true,maxRetries:10,retryDelay:100});report.ownedProfileRemoved=true;}catch(error){report.ok=false;report.profileCleanupError=error.message;}
  console.log(JSON.stringify(report));process.exitCode=report.ok?0:1;
}
