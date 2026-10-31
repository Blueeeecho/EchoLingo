// Real installed Chromium, fresh owned profile and generated loopback page.
// Native mode calls the helper; --application exercises the actual registered Alt+D.
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
const browserOrder=flags.has('--browser-order')?flags.get('--browser-order'):'edge-first';
const selectionSuite=flags.get('--selection-suite')??'original';
const applicationMode=flags.has('--application');
const coldEdgeCases=Number(flags.get('--cold-edge-cases')??0);
const noClipboardProbe=flags.get('--clipboard-probe')==='off';
const shortcutGesture=flags.get('--shortcut-gesture')??'instant';
const report={ok:false,clipboardProbeEnabled:!noClipboardProbe,actualBrowserTested:false,actualApplicationTested:false,actualRegisteredAltD:applicationMode,generatedLocalPageOnly:true,existingProfileAccessed:false,userContentRead:false,helperRetries:0,shortcutGesture,gesturePacingIsTestOnly:true,roundsPerBrowser:coldEdgeCases||3,casesPerRound:coldEdgeCases?1:8,freshBrowserProfilePerRound:true,osColdBootTested:false,requestedBrowserOrder:browserOrder??null,selectionSuite,coldEdgeDiagnosticProfiles:coldEdgeCases,actualBrowserOrder:[],rounds:[],cases:[]};
const digest=async file=>createHash('sha256').update(await readFile(file)).digest('hex');
const bounded=(promise,ms,reason)=>new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error(reason)),ms);promise.then(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
class Lines {
  constructor(child){
    this.child=child;this.lines=[];this.waiters=[];this.closed=false;this.failure=null;
    const fail=reason=>{this.failure=new Error(reason);for(const next of this.waiters.splice(0)){clearTimeout(next.timer);next.reject(this.failure);}};
    child.once('error',()=>fail('BRIDGE_PROCESS_START_FAILED'));
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
function casesFor(tag){return [
  {name:'body-mouse-en',expected:'Browser mouse EN, punctuation! '+tag,method:'actual-mouse-drag',target:'body-text',requiredRole:''},
  {name:'body-zh-punctuation',expected:'中文选词：你好，世界！“标点” '+tag,method:'dom-range',target:'body-text',requiredRole:''},
  {name:'focused-link-document',expected:'Link “Hello，世界！” (alpha_beta); '+tag,method:'dom-range-with-link-focus',target:'link-text',requiredRole:'ControlType.Hyperlink'},
  {name:'textarea-selection',expected:'Mixed textarea “你好”, alpha_beta; '+tag,method:'dom-textarea-selection',target:'area',requiredRole:'ControlType.Edit'},
  {name:'contenteditable-en',expected:'Editable English: beta_gamma (123)! '+tag,method:'dom-contenteditable-range',target:'editable',requiredRole:''},
  {name:'contenteditable-zh',expected:'可编辑中文：甲乙，丙丁。“你好！” '+tag,method:'dom-contenteditable-range',target:'editable',requiredRole:''},
  {name:'textarea-empty',expected:'',outcome:'empty',method:'dom-textarea-empty',target:'area',requiredRole:'ControlType.Edit'},
  {name:'password-protected',expected:'',outcome:'protected',method:'dom-generated-password-selection',target:'protected',requiredRole:'ControlType.Edit'}
];}
function mouseCasesFor(tag){
  const texts=['First mouse selection, alpha_beta!','第二次拖选：你好，世界！','Third selection: (gamma), 2468.','第四段正文：“不同选区”！','Fifth selection; distinct words.','第六次选择，中文与 English。','Seventh line: left to right.','第八次反向拖选：末尾。'];
  return texts.map((text,index)=>({name:'same-page-mouse-'+(index+1),target:'repeat-'+index,expected:text+' '+tag,method:index===7?'actual-mouse-drag-reverse':'actual-mouse-drag',requiredRole:''}));
}
// Pure mapping math; the initial frame estimate only places a no-button probe.
function contentOriginFromProbe(physical,event,viewport){
  assert.ok([physical.x,physical.y,event?.screenX,event?.screenY,event?.clientX,event?.clientY,viewport.width,viewport.height,viewport.dpr].every(Number.isFinite),'NATIVE_MAPPING_NUMBERS_INVALID');
  assert.equal(viewport.dpr,1,'NATIVE_MAPPING_DPI_NOT_ONE');assert.ok(viewport.width>0&&viewport.height>0,'NATIVE_MAPPING_VIEWPORT_INVALID');
  assert.ok(Math.abs(event.screenX-physical.x)<=1&&Math.abs(event.screenY-physical.y)<=1,'NATIVE_PHYSICAL_SCREEN_PROBE_MISMATCH');
  assert.ok(event.clientX>=0&&event.clientX<viewport.width&&event.clientY>=0&&event.clientY<viewport.height,'NATIVE_PROBE_NOT_CONTENT');assert.equal(event.buttons,0,'NATIVE_PROBE_MOUSE_HELD');
  return {x:event.screenX-event.clientX,y:event.screenY-event.clientY};
}
function physicalPointFromClient(origin,client,viewport){
  assert.ok([origin.x,origin.y,client.x,client.y,viewport.width,viewport.height].every(Number.isFinite),'NATIVE_MAPPING_NUMBERS_INVALID');
  assert.ok(client.x>=0&&client.x<viewport.width&&client.y>=0&&client.y<viewport.height,'NATIVE_TARGET_NOT_CONTENT');
  const point={x:Math.round(origin.x+client.x),y:Math.round(origin.y+client.y)};
  assert.ok(Number.isSafeInteger(point.x)&&Number.isSafeInteger(point.y)&&Math.abs(point.x)<=32767&&Math.abs(point.y)<=32767,'NATIVE_MAPPED_POINT_BOUND');return point;
}
function requireMouseEndpoint(event,client,physical,buttons){
  assert.ok(event&&[event.clientX,event.clientY,event.screenX,event.screenY].every(Number.isFinite),'GENERATED_MOUSE_ENDPOINT_MISSING');
  assert.ok(Math.abs(event.clientX-client.x)<=1&&Math.abs(event.clientY-client.y)<=1,'GENERATED_MOUSE_CLIENT_ENDPOINT_MISMATCH');
  if(physical)assert.ok(Math.abs(event.screenX-physical.x)<=1&&Math.abs(event.screenY-physical.y)<=1,'GENERATED_MOUSE_SCREEN_ENDPOINT_MISMATCH');
  assert.equal(event.button,0,'GENERATED_MOUSE_NOT_LEFT');assert.equal(event.buttons,buttons,'GENERATED_MOUSE_ENDPOINT_BUTTONS');
}
function requireStablePointer(before,after){
  assert.ok(after&&['screenX','screenY','clientX','clientY'].every(key=>Number.isFinite(after[key])&&Math.abs(after[key]-before[key])<=1),'OUTSIDE_CLICK_POINTER_CHANGED');
}
async function mouseLayout(page,test,reset){
  return page.evaluate(({target,expected,reset})=>{
    if(reset){window.__copyCount=0;window.__altKeyDowns=0;window.__altKeyUps=0;window.__mouseDowns=0;window.__mouseUps=0;window.__lastMouseUpButtons=null;window.__lastMouseDown=null;window.__lastMouseUp=null;window.getSelection().removeAllRanges();document.body.focus();}
    const element=document.getElementById(target);if(!element||element.textContent!==expected)throw new Error('GENERATED_STATIC_BODY_CHANGED');if(reset)element.scrollIntoView({block:'nearest'});
    const text=element.firstChild,first=document.createRange(),last=document.createRange();first.setStart(text,0);first.setEnd(text,1);last.setStart(text,text.length-1);last.setEnd(text,text.length);const a=first.getBoundingClientRect(),b=last.getBoundingClientRect(),border=(outerWidth-innerWidth)/2;
    return {mouse:{x1:a.left+.5,y1:a.top+a.height/2,x2:b.right-.5,y2:b.top+b.height/2},viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},windowPosition:[screenX,screenY],scroll:[scrollX,scrollY],approximateOrigin:{x:screenX+border,y:screenY+outerHeight-innerHeight-border},hasFocus:document.hasFocus(),textUnchanged:element.textContent===expected};
  },{...test,reset});
}
function requireStableMouseLayout(before,after){
  assert.equal(after.hasFocus,true,'GENERATED_DOM_NOT_FOCUSED');assert.equal(after.textUnchanged,true,'GENERATED_STATIC_BODY_CHANGED');
  for(const key of ['mouse','viewport','windowPosition','scroll'])assert.deepEqual(after[key],before[key],'GENERATED_MOUSE_LAYOUT_CHANGED');
}
async function prepareMouseRepeat(page,test,lines,browserPid,row){
  const diagnostic={stage:'layout',probeCount:0,dragRequests:0};row.mousePreparation=diagnostic;await page.bringToFront();
  const state=await mouseLayout(page,test,true);diagnostic.initialLayout=state;requireStableMouseLayout(state,state);
  const m=state.mouse;assert.ok(Object.values(m).every(Number.isFinite),'GENERATED_MOUSE_COORDINATES_INVALID');const reverse=test.method==='actual-mouse-drag-reverse';
  const startCss={x:reverse?m.x2:m.x1,y:reverse?m.y2:m.y1},endCss={x:reverse?m.x1:m.x2,y:reverse?m.y1:m.y2};diagnostic.expectedStartClient=startCss;diagnostic.expectedEndClient=endCss;
  let nativeGuard=null,startPhysical=null,endPhysical=null;
  if(lines){
    diagnostic.stage='probe';const probe={x:Math.round(state.approximateOrigin.x+startCss.x),y:Math.round(state.approximateOrigin.y+startCss.y)};diagnostic.physicalProbe=probe;
    await page.evaluate(()=>{window.__lastNativePointer=null;});diagnostic.probeCount=1;nativeGuard=await lines.request({op:'mouse-point',browserPid,...probe},5000);diagnostic.nativeProbeAccepted=nativeGuard.ok;assert.equal(nativeGuard.ok,true,'GENERATED_MOUSE_START_NOT_OWN_BROWSER');
    await page.waitForFunction(({x,y})=>window.__lastNativePointer&&Math.abs(window.__lastNativePointer.screenX-x)<=1&&Math.abs(window.__lastNativePointer.screenY-y)<=1,probe,{timeout:2000});
    const actual=await page.evaluate(()=>window.__lastNativePointer);diagnostic.observedProbe=actual;const origin=contentOriginFromProbe(probe,actual,state.viewport);diagnostic.observedContentOrigin=origin;
    const beforeDrag=await mouseLayout(page,test,false);diagnostic.beforeDragLayout=beforeDrag;requireStableMouseLayout(state,beforeDrag);
    startPhysical=physicalPointFromClient(origin,startCss,state.viewport);endPhysical=physicalPointFromClient(origin,endCss,state.viewport);diagnostic.actualStartPhysical=startPhysical;diagnostic.actualEndPhysical=endPhysical;
    diagnostic.stage='drag';diagnostic.dragRequests=1;const drag=await lines.request({op:'mouse-drag',browserPid,...startPhysical,endX:endPhysical.x,endY:endPhysical.y},5000);diagnostic.nativeDrag=drag;assert.equal(drag.ok,true,'NATIVE_MOUSE_DRAG_FAILED');nativeGuard={...nativeGuard,...drag,screenToViewportMappingVerified:true};row.mouseStartNativeGuard=nativeGuard;
    await page.waitForFunction(()=>window.__mouseUps===1&&window.__lastMouseUpButtons===0,null,{timeout:2000});
  }else{diagnostic.stage='drag';diagnostic.dragRequests=1;await page.mouse.move(startCss.x,startCss.y);await page.mouse.down();await page.mouse.move(endCss.x,endCss.y,{steps:8});await page.mouse.up();}
  diagnostic.stage='events';const selected=await page.evaluate(target=>({text:window.getSelection().toString(),hasFocus:document.hasFocus(),bodyText:document.getElementById(target).textContent,mouseDowns:window.__mouseDowns,mouseUps:window.__mouseUps,mouseUpButtons:window.__lastMouseUpButtons,down:window.__lastMouseDown,up:window.__lastMouseUp}),test.target);
  diagnostic.actualMouseDown=selected.down;diagnostic.actualMouseUp=selected.up;diagnostic.mouseDownCount=selected.mouseDowns;diagnostic.mouseUpCount=selected.mouseUps;diagnostic.selectedLength=selected.text.length;diagnostic.selectionExact=selected.text===test.expected;
  assert.equal(selected.hasFocus,true,'GENERATED_DOM_LOST_FOCUS');assert.equal(selected.mouseDowns,1,'GENERATED_MOUSE_DOWN_COUNT');assert.equal(selected.mouseUps,1,'GENERATED_MOUSE_UP_COUNT');assert.equal(selected.mouseUpButtons,0,'GENERATED_MOUSE_STILL_HELD');
  requireMouseEndpoint(selected.down,startCss,startPhysical,1);requireMouseEndpoint(selected.up,endCss,endPhysical,0);
  const afterDrag=await mouseLayout(page,test,false);diagnostic.afterDragLayout=afterDrag;requireStableMouseLayout(state,afterDrag);
  assert.equal(selected.text,test.expected,'GENERATED_SELECTION_SETUP_MISMATCH');assert.equal(selected.bodyText,test.expected,'GENERATED_STATIC_BODY_CHANGED');diagnostic.stage='complete';
  // A failed selection remains a setup failure. No range assignment or retry.
  return {domSelectionVerified:true,method:test.method,samePage:true,bodyMutationAfterLoad:false,generatedMouseDowns:selected.mouseDowns,generatedMouseUps:selected.mouseUps,generatedMouseUpButtons:selected.mouseUpButtons,mouseStartNativeGuard:nativeGuard};
}
async function dismissPreviousPopupByClick(page,lines,browserPid,row){
  const diagnostic={stage:'layout',probeCount:0,clickRequests:0};row.outsideClickPreparation=diagnostic;
  const before=await page.evaluate(()=>{window.__mouseDowns=0;window.__mouseUps=0;window.__lastMouseUpButtons=null;window.__lastNativePointer=null;window.__lastMouseDown=null;window.__lastMouseUp=null;window.__lastDownWasBlank=false;const border=(outerWidth-innerWidth)/2;return {viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},windowPosition:[screenX,screenY],scroll:[scrollX,scrollY],approximateOrigin:{x:screenX+border,y:screenY+outerHeight-innerHeight-border},hasFocus:document.hasFocus()};});
  diagnostic.initialLayout=before;assert.equal(before.hasFocus,true,'OUTSIDE_CLICK_BROWSER_DOCUMENT_NOT_FOCUSED');const probe={x:Math.round(before.approximateOrigin.x+6),y:Math.round(before.approximateOrigin.y+before.viewport.height-8)};diagnostic.physicalProbe=probe;diagnostic.stage='probe';diagnostic.probeCount=1;
  const guard=await lines.request({op:'mouse-point',browserPid,...probe},5000);diagnostic.nativeProbeAccepted=guard.ok;assert.equal(guard.ok,true,'OUTSIDE_CLICK_NOT_BOUND_BROWSER');
  await page.waitForFunction(({x,y})=>window.__lastNativePointer&&Math.abs(window.__lastNativePointer.screenX-x)<=1&&Math.abs(window.__lastNativePointer.screenY-y)<=1,probe,{timeout:2000});const observed=await page.evaluate(()=>window.__lastNativePointer);diagnostic.observedProbe=observed;diagnostic.observedContentOrigin=contentOriginFromProbe(probe,observed,before.viewport);
  // The bridge clicks at the unchanged physical probe. Verify that actual
  // observed content point is blank before committing the one click.
  const expectedClient={x:observed.clientX,y:observed.clientY};diagnostic.verifiedBlankClient=expectedClient;
  const ready=await page.evaluate(({x,y})=>{const hit=document.elementFromPoint(x,y);return {viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},windowPosition:[screenX,screenY],scroll:[scrollX,scrollY],hasFocus:document.hasFocus(),blank:hit===document.body||hit===document.documentElement,pointer:window.__lastNativePointer};},expectedClient);diagnostic.beforeClick=ready;
  for(const key of ['viewport','windowPosition','scroll'])assert.deepEqual(ready[key],before[key],'OUTSIDE_CLICK_LAYOUT_CHANGED');requireStablePointer(observed,ready.pointer);assert.equal(ready.pointer.buttons,0,'OUTSIDE_CLICK_MOUSE_HELD_BEFORE_ACTION');assert.equal(ready.hasFocus,true,'OUTSIDE_CLICK_BROWSER_DOCUMENT_NOT_FOCUSED');assert.equal(ready.blank,true,'GENERATED_OBSERVED_BROWSER_POINT_NOT_BLANK');
  diagnostic.stage='click';diagnostic.clickRequests=1;const reply=await lines.request({op:'outside-click',browserPid,...probe},5000);diagnostic.nativeClick=reply;assert.equal(reply.ok,true,'SAME_BROWSER_OUTSIDE_CLICK_DID_NOT_HIDE_POPUP');
  await page.waitForFunction(()=>window.__mouseDowns===1&&window.__mouseUps===1&&window.__lastMouseUpButtons===0&&window.__lastDownWasBlank,null,{timeout:2000});const after=await page.evaluate(()=>({viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},windowPosition:[screenX,screenY],scroll:[scrollX,scrollY],down:window.__lastMouseDown,up:window.__lastMouseUp,pointer:window.__lastNativePointer,hasFocus:document.hasFocus(),downs:window.__mouseDowns,ups:window.__mouseUps,upButtons:window.__lastMouseUpButtons,blank:window.__lastDownWasBlank}));diagnostic.afterClick=after;
  for(const key of ['viewport','windowPosition','scroll'])assert.deepEqual(after[key],before[key],'OUTSIDE_CLICK_LAYOUT_CHANGED');requireStablePointer(observed,after.pointer);assert.equal(after.hasFocus,true,'OUTSIDE_CLICK_BROWSER_DOCUMENT_NOT_FOCUSED');assert.equal(after.downs,1,'OUTSIDE_CLICK_DOWN_COUNT');assert.equal(after.ups,1,'OUTSIDE_CLICK_UP_COUNT');assert.equal(after.upButtons,0,'OUTSIDE_CLICK_STILL_HELD');assert.equal(after.blank,true,'OUTSIDE_CLICK_NOT_ACTUAL_BLANK');requireMouseEndpoint(after.down,expectedClient,probe,1);requireMouseEndpoint(after.up,expectedClient,probe,0);diagnostic.stage='complete';
  return {...reply,generatedBrowserBlankClickVerified:true};
}
async function prepare(page,test,tag){
  await page.bringToFront();
  const state=await page.evaluate(({test,tag})=>{
    window.__copyCount=0;window.__altKeyDowns=0;window.__altKeyUps=0;window.getSelection().removeAllRanges();const area=document.getElementById('area'),edit=document.getElementById('editable'),password=document.getElementById('protected');area.value='';edit.textContent='';password.value='';
    if(test.target==='area'){area.value=test.outcome==='empty'?'Generated unselected textarea '+tag:test.expected;area.focus();area.setSelectionRange(0,test.outcome==='empty'?0:area.value.length);}
    else if(test.target==='protected'){password.value='Generated password sample '+tag;password.focus();password.setSelectionRange(0,password.value.length);}
    else {
      const target=document.getElementById(test.target);target.textContent=test.expected;
      if(test.target==='editable')target.focus();else if(test.name==='focused-link-document')document.getElementById('link').focus();else document.body.focus();
      const range=document.createRange();range.selectNodeContents(target);
      if(test.method==='actual-mouse-drag'){
        const text=target.firstChild,first=document.createRange(),last=document.createRange();first.setStart(text,0);first.setEnd(text,1);last.setStart(text,text.length-1);last.setEnd(text,text.length);const a=first.getBoundingClientRect(),b=last.getBoundingClientRect();return {mouse:{x1:a.left+.5,y1:a.top+a.height/2,x2:b.right-.5,y2:b.top+b.height/2},hasFocus:document.hasFocus()};
      }
      // Focusing an editable host can create a collapsed caret range. Replace
      // that setup range explicitly; Chromium only supports one DOM range.
      // This is the declared programmatic setup, never a mouse-selection fix.
      window.getSelection().removeAllRanges();window.getSelection().addRange(range);
    }
    return {hasFocus:document.hasFocus()};
  },{test,tag});
  assert.equal(state.hasFocus,true,'GENERATED_DOM_NOT_FOCUSED');
  if(state.mouse){
    const m=state.mouse;assert.ok([m.x1,m.y1,m.x2,m.y2].every(Number.isFinite));
    await page.mouse.move(m.x1,m.y1);await page.mouse.down();await page.mouse.move(m.x2,m.y2,{steps:8});await page.mouse.up();
    // Never repair a failed mouse selection by assigning a DOM range.
  }
  const prepared=await page.evaluate(({target,outcome})=>{
    const element=document.getElementById(target);return {selection:target==='area'?element.value.slice(element.selectionStart,element.selectionEnd):target==='protected'?null:window.getSelection().toString(),active:document.activeElement.id,hasFocus:document.hasFocus(),protectedSelected:target==='protected'?element.selectionEnd>element.selectionStart:false};
  },test);
  assert.equal(prepared.hasFocus,true,'GENERATED_DOM_LOST_FOCUS');
  if(test.outcome==='protected')assert.equal(prepared.protectedSelected,true,'GENERATED_PASSWORD_NOT_SELECTED');else assert.equal(prepared.selection,test.expected,'GENERATED_SELECTION_SETUP_MISMATCH');
  if(test.name==='focused-link-document')assert.equal(prepared.active,'link');
  return {domSelectionVerified:true,method:test.method};
}
async function runRound(candidate,round,helper,assembly,application){
  const result={browserKind:candidate.kind,round,ok:false,requiredCases:coldEdgeCases?1:8,cases:[],externalPageRequests:0,freshProcessAndProfile:true,forcedRendererAccessibility:false};
  let root,profile,marker,browserProcess,bridgeProcess,browser,server,lines;
  try{
    root=await mkdtemp(path.join(tmpdir(),'echolingo-browser-selection-'));marker=randomUUID();await writeFile(path.join(root,'.echolingo-owned'),marker,{flag:'wx'});profile=path.join(root,'profile');await mkdir(profile);
    const tag=candidate.kind+'-r'+round,tests=selectionSuite==='same-page-mouse'?mouseCasesFor(tag):casesFor(tag);
    const repeatBody=selectionSuite==='same-page-mouse'?tests.map(test=>'<p><span id="'+test.target+'">'+test.expected+'</span></p>').join(''):'';
    const html='<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; connect-src \'none\'"><title>EchoLingo generated browser selection fixture</title><style>body{font:18px Segoe UI;padding:35px}span{white-space:pre}textarea,[contenteditable],input{display:block;width:700px;height:55px;margin:12px 0}p{margin:10px 0}</style><body tabindex="0">'+repeatBody+'<p><span id="body-text"></span></p><a id="link" href="#generated">Generated focused link</a><p><span id="link-text"></span></p><textarea id="area"></textarea><div id="editable" contenteditable="true"></div><input id="protected" type="password"><script>window.__copyCount=0;window.__altKeyDowns=0;window.__altKeyUps=0;document.addEventListener("copy",()=>window.__copyCount++);document.addEventListener("keydown",event=>{if(event.code==="AltLeft"||event.code==="AltRight")window.__altKeyDowns++;});document.addEventListener("keyup",event=>{if(event.code==="AltLeft"||event.code==="AltRight")window.__altKeyUps++;});document.addEventListener("mousedown",event=>{window.__mouseDowns++;window.__lastMouseDown={screenX:event.screenX,screenY:event.screenY,clientX:event.clientX,clientY:event.clientY,button:event.button,buttons:event.buttons};window.__lastDownWasBlank=event.target===document.body||event.target===document.documentElement;});document.addEventListener("mouseup",event=>{window.__mouseUps++;window.__lastMouseUp={screenX:event.screenX,screenY:event.screenY,clientX:event.clientX,clientY:event.clientY,button:event.button,buttons:event.buttons};window.__lastMouseUpButtons=event.buttons;});document.addEventListener("mousemove",event=>{window.__lastNativePointer={screenX:event.screenX,screenY:event.screenY,clientX:event.clientX,clientY:event.clientY,buttons:event.buttons};});</script>';
    const translations=new Map(tests.map((test,index)=>[test.expected,{result:'Generated mock translation '+tag+'-'+index,count:0}]));let mockError=null;
    server=createServer(async(request,response)=>{
      if(request.url==='/translate'&&application){
        try{assert.equal(request.method,'POST','MOCK_METHOD');assert.equal(request.headers.authorization,undefined,'MOCK_AUTHORIZATION_FORBIDDEN');let size=0,chunks=[];for await(const chunk of request){size+=chunk.length;assert.ok(size<=65536,'MOCK_BODY_BOUND');chunks.push(chunk);}const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));assert.ok(!body.api_key,'MOCK_CREDENTIAL_FORBIDDEN');const item=translations.get(body.q);assert.ok(item,'MOCK_NON_GENERATED_SOURCE');assert.equal(body.format,'text');item.count++;response.writeHead(200,{'Content-Type':'application/json'});response.end(JSON.stringify({translatedText:item.result}));}
        catch{mockError='MOCK_REQUEST_REJECTED';response.writeHead(400);response.end('{}');}return;
      }
      if(request.url!='/source'){response.writeHead(404);response.end();return;}response.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});response.end(html);
    });
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});const origin='http://127.0.0.1:'+server.address().port,sourceUrl=origin+'/source';
    const bridgeArgs=['-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',path.join(here,'windows-browser-selection-bridge.ps1'),'-BrowserExecutable',candidate.executable];
    if(!application)bridgeArgs.push('-HelperPath',helper,'-NativeAssemblyPath',assembly);
    if(application)bridgeArgs.push('-ApplicationPath',application.path,'-ExpectedApplicationSha256',application.sha256,'-ExpectedApplicationBytes',String(application.bytes),'-MockBaseUrl',origin,'-ProviderId','generated-browser-'+marker,'-ShortcutGesture',shortcutGesture);
    if(coldEdgeCases)bridgeArgs.push('-ColdEdgeDiagnostics');
    if(noClipboardProbe)bridgeArgs.push('-NoClipboardProbe');
    bridgeProcess=spawn(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),bridgeArgs,{windowsHide:true,stdio:['pipe','pipe','pipe']});
    bridgeProcess.stderr.on('data',data=>{result.bridgeStderrBytes=(result.bridgeStderrBytes??0)+data.length;});lines=new Lines(bridgeProcess);const greeting=await lines.next(application?65000:10000);
    if(greeting.ready!==true)result.bridgeStartupFailure={reported:greeting.bridgeStartupFailure===true,category:typeof greeting.error==='string'&&/^[A-Z_]{1,100}$/.test(greeting.error)?greeting.error:'UNCLASSIFIED_BRIDGE_STARTUP_FAILURE'};
    assert.equal(greeting.ready,true,'BRIDGE_STARTUP_FAILED');result.bridgeProcessId=greeting.bridgeProcessId;if(application){result.applicationIdentity=greeting.application;result.actualApplicationTested=true;report.actualApplicationTested=true;if(noClipboardProbe){assert.equal(greeting.application.clipboardProbeEnabled,false,'APP_PROBE_ENV_NOT_DISABLED');assert.equal(greeting.application.selectionTraceEnvironmentRemoved,true,'APP_TRACE_ENV_NOT_REMOVED');}}
    browserProcess=spawn(candidate.executable,['--user-data-dir='+profile,'--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-sync','--disable-extensions','--disable-quic','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--force-device-scale-factor=1','--enable-automation','--new-window','about:blank'],{windowsHide:false,stdio:'ignore'});
    browserProcess.once('error',()=>{});assert.ok(browserProcess.pid>0,'BROWSER_SPAWN_FAILED');result.browserRootProcessId=browserProcess.pid;
    const active=path.join(profile,'DevToolsActivePort');let endpoint;const deadline=Date.now()+10000;
    while(Date.now()<deadline){assert.equal(browserProcess.exitCode,null,'OWN_BROWSER_EXITED_BEFORE_DEBUG_READY');try{assert.equal((await lstat(active)).isSymbolicLink(),false);const fields=(await readFile(active,'utf8')).trim().split(/\r?\n/),port=Number(fields[0]);assert.ok(Number.isInteger(port)&&port>1024&&port<65536);assert.match(fields[1],/^\/devtools\/browser\/[a-zA-Z0-9-]+$/);endpoint='ws://127.0.0.1:'+port+fields[1];break;}catch{await sleep(50);}}
    assert.ok(endpoint,'OWN_PROFILE_DEBUG_ENDPOINT_NOT_CREATED');browser=await chromium.connectOverCDP(endpoint,{timeout:10000});
    const session=await browser.newBrowserCDPSession(),processes=await session.send('SystemInfo.getProcessInfo'),roots=processes.processInfo.filter(value=>value.type==='browser');assert.equal(roots.length,1);assert.equal(roots[0].id,browserProcess.pid,'CDP_BROWSER_PID_NOT_OWN_SPAWN');result.cdpRootProcessVerified=true;
    const commandLine=await session.send('Browser.getBrowserCommandLine');assert.ok(commandLine.arguments.includes('--user-data-dir='+profile),'CDP_PROFILE_NOT_OWN_FRESH_PROFILE');assert.ok(!commandLine.arguments.some(value=>value.startsWith('--force-renderer-accessibility')));result.freshProfileCommandLineVerified=true;result.browserVersion=browser.version();
    const contexts=browser.contexts();assert.equal(contexts.length,1,'FRESH_CONTEXT_COUNT');const context=contexts[0];await context.route('**/*',route=>{if(route.request().url().startsWith(origin+'/'))return route.continue();result.externalPageRequests++;return route.abort();});
    const page=context.pages()[0]??await context.newPage();await page.goto(sourceUrl,{waitUntil:'load',timeout:10000});assert.equal(page.url(),sourceUrl);result.actualBrowserTested=true;
    let invoked=0,shortcutPresses=0;
    for(const test of coldEdgeCases?tests.slice(0,1):tests){
      const row={browserKind:candidate.kind,round,name:test.name,ok:false,helperInvocations:0,setupMethod:test.method,shortcutGesture};result.cases.push(row);report.cases.push(row);
      try{
        if(application&&shortcutPresses>0)row.previousPopupOutsideClick=await dismissPreviousPopupByClick(page,lines,browserProcess.pid,row);
        Object.assign(row,selectionSuite==='same-page-mouse'?await prepareMouseRepeat(page,test,application?lines:null,browserProcess.pid,row):await prepare(page,test,tag));if(application)row.firstActualAltDInFreshBrowser=shortcutPresses===0;else row.firstHelperInFreshBrowser=invoked===0;
        const mock=translations.get(test.expected),mockBefore=mock.count;
        const reply=await lines.request({op:'case',browserPid:browserProcess.pid,expected:test.expected,outcome:test.outcome??'selection',requiredRole:test.requiredRole,requireMouseReleased:selectionSuite==='same-page-mouse',expectedTranslation:mock.result},coldEdgeCases?50000:application?40000:20000);Object.assign(row,reply);row.bridgeExpectationPassed=reply.ok;row.ok=false;invoked+=reply.helperInvocations??0;shortcutPresses+=reply.actualShortcutPresses??0;
        if(application){row.newMockRequests=mock.count-mockBefore;row.mockError=mockError;assert.equal(mockError,null,'MOCK_REQUEST_REJECTED');assert.ok(row.newMockRequests>=0&&row.newMockRequests<=1,'ACTUAL_APP_DUPLICATE_MOCK_REQUEST');if(reply.ok)assert.equal(row.newMockRequests,1,'ACTUAL_APP_NEW_MOCK_REQUEST_MISSING');if(noClipboardProbe){assert.equal(reply.clipboardProbeEnabled,false,'CLIPBOARD_PROBE_UNEXPECTEDLY_ENABLED');assert.equal(reply.seedPublicationObservation,undefined);assert.equal(reply.clipboardRestorationObservation?.rawFormatsAfterOleFailure,undefined);}const after=await page.evaluate(target=>({selected:window.getSelection().toString(),body:document.getElementById(target).textContent,hasFocus:document.hasFocus(),altKeyDowns:window.__altKeyDowns,altKeyUps:window.__altKeyUps}),test.target);row.generatedDomAltKeyDowns=after.altKeyDowns;row.generatedDomAltKeyUps=after.altKeyUps;row.domSelectionUnchangedAfterHotkey=after.selected===test.expected;row.generatedBodyUnchangedAfterHotkey=after.body===test.expected;row.browserDocumentFocusedAfterHotkey=after.hasFocus;if(reply.ok){assert.equal(reply.actualShortcutPresses,1,'ACTUAL_APP_SINGLE_SHORTCUT_REQUIRED');assert.equal(reply.shortcutGesture,shortcutGesture,'ACTUAL_APP_SHORTCUT_GESTURE_MISMATCH');assert.equal(row.domSelectionUnchangedAfterHotkey,true,'ACTUAL_ALT_D_CHANGED_BROWSER_SELECTION');assert.equal(row.generatedBodyUnchangedAfterHotkey,true,'ACTUAL_ALT_D_EDITED_BROWSER');assert.equal(after.hasFocus,true,'ACTUAL_ALT_D_FOCUSED_BROWSER_CHROME');}}
        row.domCopyEvents=await page.evaluate(()=>window.__copyCount);assert.ok(row.domCopyEvents<=1,'COPY_RETRIED');if(test.outcome==='empty'||test.outcome==='protected')assert.equal(row.domCopyEvents,0,'NEGATIVE_CONTROL_RECEIVED_COPY');row.nativeClipboardCopyExercised=row.domCopyEvents===1;
        row.ok=reply.ok===true;if(!row.ok&&!reply.safeToContinue){result.remainingCasesUnexecuted=true;break;}
      }catch(error){row.error=String(error.message).replace(/wss?:\/\/[^\s]+/g,'[owned-debug-endpoint]').slice(0,1024);row.setupInconclusive=application?(row.actualShortcutPresses??0)===0:(row.helperInvocations??0)===0;
        if(row.setupInconclusive&&selectionSuite==='same-page-mouse')try{row.preparationFailureObservation=await bounded(page.evaluate(()=>({pointer:window.__lastNativePointer,down:window.__lastMouseDown,up:window.__lastMouseUp,mouseDowns:window.__mouseDowns,mouseUps:window.__mouseUps,upButtons:window.__lastMouseUpButtons,viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},windowPosition:[screenX,screenY],scroll:[scrollX,scrollY],hasFocus:document.hasFocus()})),2000,'GENERATED_NUMERIC_FAILURE_OBSERVATION_DEADLINE');}catch{row.preparationFailureObservationUnavailable=true;}
        result.remainingCasesUnexecuted=true;break;}
    }
    result.helperInvocations=invoked;result.actualShortcutPresses=shortcutPresses;result.ok=result.cases.length===result.requiredCases&&result.cases.every(value=>value.ok)&&result.externalPageRequests===0;
  }catch(error){result.error=String(error.message).replace(/wss?:\/\/[^\s]+/g,'[owned-debug-endpoint]').slice(0,1024);result.setupInconclusive=result.cases.every(value=>(value.helperInvocations??0)===0);}
  finally{
    try{if(lines&&!lines.closed){const closing=await lines.request({op:'close'},application?30000:3000);assert.equal(closing.ok,true);assert.equal(closing.closing,true);assert.equal(closing.clipboardCleanupComplete,true);result.generatedClipboardCleanupConfirmed=true;if(application){assert.equal(closing.applicationCleanup.ok,true,'OWN_APPLICATION_CLEANUP_FAILED');result.applicationCleanup=closing.applicationCleanup;}}}catch{result.ok=false;result.bridgeCloseIncomplete=true;}
    try{await stopOwned(bridgeProcess);result.ownBridgeStopped=true;}catch(error){result.ok=false;result.bridgeCleanupError=error.message;}
    try{if(browser)await bounded(browser.close(),3000,'CDP_DISCONNECT_DEADLINE');}catch{result.cdpDisconnectIncomplete=true;}
    try{await stopOwned(browserProcess);result.ownBrowserStopped=true;}catch(error){result.ok=false;result.browserCleanupError=error.message;}
    if(server){try{server.closeAllConnections();await bounded(new Promise(resolve=>server.close(resolve)),2000,'OWN_LOOPBACK_SERVER_CLEANUP_DEADLINE');result.ownLoopbackServerStopped=true;}catch(error){result.ok=false;result.serverCleanupError=error.message;}}
    if(root){try{assert.equal((await lstat(root)).isSymbolicLink(),false);assert.equal(await readFile(path.join(root,'.echolingo-owned'),'utf8'),marker);await rm(root,{recursive:true,maxRetries:10,retryDelay:100});result.ownedProfileRemoved=true;}catch(error){result.ok=false;result.profileCleanupError=error.message;}}
    result.executedCases=result.cases.length;result.passedCases=result.cases.filter(value=>value.ok).length;
  }
  return result;
}
try{
  assert.ok(browserOrder==='edge-first'||browserOrder==='chrome-first','BROWSER_ORDER_INVALID');
  assert.ok(selectionSuite==='original'||selectionSuite==='same-page-mouse','SELECTION_SUITE_INVALID');
  assert.ok(!flags.has('--clipboard-probe')||['on','off'].includes(flags.get('--clipboard-probe')),'CLIPBOARD_PROBE_FLAG_INVALID');
  if(noClipboardProbe){assert.equal(applicationMode,true,'NO_PROBE_REQUIRES_APPLICATION');assert.equal(coldEdgeCases,0,'NO_PROBE_REQUIRES_ORDINARY_MATRIX');}
  assert.ok(shortcutGesture==='instant'||shortcutGesture==='paced','SHORTCUT_GESTURE_INVALID');if(shortcutGesture==='paced')assert.equal(applicationMode,true,'PACED_GESTURE_REQUIRES_APPLICATION');
  assert.ok(Number.isInteger(coldEdgeCases)&&coldEdgeCases>=0&&coldEdgeCases<=2,'COLD_EDGE_PROFILE_COUNT_INVALID');if(coldEdgeCases){assert.equal(applicationMode,true,'COLD_EDGE_REQUIRES_APPLICATION');assert.equal(browserOrder,'edge-first','COLD_EDGE_REQUIRES_EDGE_FIRST');}
  assert.equal(process.platform,'win32','WINDOWS_REQUIRED');assert.equal(process.env.GITHUB_ACTIONS,'true','EPHEMERAL_GITHUB_REQUIRED');assert.equal(process.env.RUNNER_ENVIRONMENT,'github-hosted','GITHUB_HOSTED_REQUIRED');
  let helper=null,assembly=null,application=null;
  if(applicationMode){assert.equal(selectionSuite,'same-page-mouse','APPLICATION_MODE_REQUIRES_REAL_MOUSE_SUITE');const executable=await realpath(flags.get('--application')),expected=flags.get('--expected-application-sha256')??'8490a973c9e4f4568b851f61524a4ef8f554d8b3a506b12dd19ba34f0dd22a4b',bytes=Number(flags.get('--expected-application-bytes')??5825536);assert.match(expected,/^[a-f0-9]{64}$/);assert.ok(Number.isSafeInteger(bytes)&&bytes>0);assert.equal((await stat(executable)).size,bytes,'EXACT_APPLICATION_BYTES');assert.equal(await digest(executable),expected,'EXACT_APPLICATION_SHA256');application={path:executable,sha256:expected,bytes};report.applicationSha256=expected;report.applicationBytes=bytes;report.translationBackend='generated-loopback-mock';}
  else{assert.ok(flags.has('--native-assembly'),'NATIVE_ASSEMBLY_REQUIRED');helper=await realpath(flags.get('--helper')??path.join(here,'../src-tauri/native/windows.ps1'));assembly=await realpath(flags.get('--native-assembly'));assert.equal(path.extname(assembly).toLowerCase(),'.dll');report.helperSha256=await digest(helper);report.nativeAssemblySha256=await digest(assembly);}
  const installed=await installedBrowsers();report.availableBrowserKinds=installed.map(value=>value.kind);report.unavailableBrowserKinds=['edge','chrome'].filter(kind=>!installed.some(value=>value.kind===kind));if(coldEdgeCases)assert.ok(installed.some(value=>value.kind==='edge'),'EDGE_REQUIRED');else assert.ok(installed.length===2,'EDGE_AND_CHROME_REQUIRED');
  const priority=browserOrder==='edge-first'?['edge','chrome']:['chrome','edge'];
  const candidates=(coldEdgeCases?installed.filter(value=>value.kind==='edge'):[...installed]).sort((first,second)=>priority.indexOf(first.kind)-priority.indexOf(second.kind));report.requiredCases=candidates.length*(coldEdgeCases||3)*(coldEdgeCases?1:8);report.requiredFreshBrowserRounds=candidates.length*(coldEdgeCases||3);
  for(const candidate of candidates){
    report.actualBrowserOrder.push(candidate.kind);
    for(let round=1;round<=(coldEdgeCases||3);round++){const result=await runRound(candidate,round,helper,assembly,application);report.rounds.push(result);report.actualBrowserTested||=result.actualBrowserTested===true;}
  }
  report.ok=report.rounds.length===report.requiredFreshBrowserRounds&&report.rounds.every(value=>value.ok);
}catch(error){report.error=String(error.message).replace(/wss?:\/\/[^\s]+/g,'[owned-debug-endpoint]').slice(0,1024);report.setupInconclusive=report.cases.length===0;}
finally{report.executedCases=report.cases.length;report.passedCases=report.cases.filter(value=>value.ok).length;report.helperInvocations=report.cases.reduce((total,value)=>total+(value.helperInvocations??0),0);report.actualShortcutPresses=report.cases.reduce((total,value)=>total+(value.actualShortcutPresses??0),0);report.externalPageRequests=report.rounds.reduce((total,value)=>total+value.externalPageRequests,0);console.log(JSON.stringify(report));process.exitCode=report.ok?0:1;}
