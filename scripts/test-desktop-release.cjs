'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const path = require('node:path');
const {publish, validateInputs, NAMES, PAYLOADS, MODE} = require('./publish-desktop-release.cjs');
const sha = 'a'.repeat(40), pin = 'b'.repeat(40);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function fixture(change = {}) {
  const context = {repo:{owner:'Blueeeecho',repo:'EchoLingo'}, ref:'refs/heads/main', sha, runId:123};
  const data = new Map(PAYLOADS.map(name => [name, Buffer.from(`payload ${name}`)]));
  const manifest = {version:'0.2.16', commit:sha, reviewedSourceCommit:pin, validationRun:'https://github.com/Blueeeecho/EchoLingo/actions/runs/123', validationMode:MODE, scope:{fullRegression:false,installerExecuted:false,macOSRuntimeAcceptance:true,windowsZipRuntimeAcceptance:true,interactiveCaptureAcceptance:false,networkIsolationAcceptance:false}, files:PAYLOADS.map(name => ({name,size:data.get(name).length,sha256:hash(data.get(name))}))};
  const zipName='EchoLingo_0.2.16_windows_x64-unpack.zip';
  const portable={version:'0.2.16',commit:sha,userDataPortable:false,
    archives:[zipName,'EchoLingo-offline-engine-source.zip'].map(name=>({name,size:data.get(name).length,sha256:hash(data.get(name))}))};
  const runtime={version:'0.2.16',applicationSha256:'e'.repeat(64),archiveSha256:hash(data.get(zipName)),interactiveCaptureTested:false,networkIsolationTested:false};
  for(const flag of ['ok','windowsRuntimeExecuted','settingsWebViewReady','expectedLocalWebViewProfileCreated','roamingDirectoryAvailable','packageUnchangedAfterRun','realTranslationBothDirections','embeddedCaptureMemorySelfTest','peDependencyChecks','launcherMissingZeroPresentMocks']) runtime[flag]=true;
  change.portable?.(portable);change.runtime?.(runtime);
  data.set('WINDOWS-ZIP-MANIFEST.json',Buffer.from(JSON.stringify(portable)));
  manifest.windowsZipRuntime=runtime;
  manifest.files=PAYLOADS.map(name=>({name,size:data.get(name).length,sha256:hash(data.get(name))}));
  manifest.windowsSettingsAcceptance={actualSettingsUiTested:true,fakeIpcUsed:false,applicationSha256:'e'.repeat(64),evidence:{name:'windows-settings.json',size:100,sha256:'d'.repeat(64)}};
  manifest.windowsGeneratedFocusAcceptance={generatedSourceOnly:true,actualApplicationTested:false,passedCases:2,nativeAssemblySha256:'f'.repeat(64),evidence:{name:'windows-native-focus.json',size:100,sha256:'d'.repeat(64)}};
  manifest.tree='c'.repeat(40);
  manifest.nativePackageInspection={macOS:{source:{commit:sha,tree:manifest.tree},runUrl:manifest.validationRun,application:{sha256:'a'.repeat(64)},installer:{sha256:hash(data.get('EchoLingo_0.2.16_macos_arm64.dmg'))}}};
  manifest.macOSRuntimeAcceptance={version:'0.2.16',commit:sha,tree:manifest.tree,runUrl:manifest.validationRun,applicationSha256:'a'.repeat(64),installerSha256:manifest.nativePackageInspection.macOS.installer.sha256,fakeIpcUsed:false,userContentRead:false,codexInteractiveSelectionTested:false};
  for(const flag of ['ok','extractedBundleLaunched','restartPassed','secondInstancePassed','frontendWebViewReady','settingsWindowShown','nativeSelfTestsPassed','nativeWindowResizeFixturePassed','packageUnchangedAfterRun','cleanupComplete']) manifest.macOSRuntimeAcceptance[flag]=true;
  change.manifest?.(manifest);
  data.set('RELEASE-MANIFEST.json', Buffer.from(JSON.stringify(manifest)));
  data.set('SHA256SUMS.txt', Buffer.from([...data].map(([name, bytes]) => `${hash(bytes)}  ${name}\n`).sort().join('')));
  change.data?.(data);
  const io = {fs:{readdirSync:() => [...data.keys()], lstatSync:filename => ({isFile:()=>true,isSymbolicLink:()=>false,size:data.get(path.basename(filename)).length}), readFileSync:(filename, encoding) => filename.replaceAll('\\', '/').startsWith('docs/') ? 'Public release notes' : encoding ? data.get(path.basename(filename)).toString(encoding) : data.get(path.basename(filename))}, execFileSync:(cmd,args) => {if(cmd==='python3') return pin+'\n'; if(change.ancestorFails) throw new Error('Not ancestor'); return '';}};
  let mainCalls = 0, tagExists = !!change.existingTag;
  const writes = [], uploaded = [];
  const missing = () => {throw Object.assign(new Error('Missing'), {status:404});};
  const github = {rest:{actions:{listWorkflowRuns:async args=>{assert.equal(args.head_sha,sha);assert.equal(args.event,'push');return {data:{workflow_runs:change.runs??[{id:10,head_sha:sha,event:'push',path:'.github/workflows/ci.yml',status:'completed',conclusion:'success'}]}};}},git:{getRef:async ({ref}) => {
    if(ref === 'heads/main') return {data:{object:{type:'commit',sha:change.mainMoves && ++mainCalls >= 3 ? 'c'.repeat(40):sha}}};
    if(change.badTag) return {data:{object:{type:'commit',sha:pin}}};
    if(!tagExists) missing();
    return {data:{object:{type:'commit',sha}}};
  },createRef:async args => {writes.push(['tag',args]);tagExists=true;}},repos:{getReleaseByTag:async()=>{if(change.existing) return {data:{id:3}};missing();},createRelease:async args=>{writes.push(['draft',args]);return {data:{id:12}};},uploadReleaseAsset:async args=>{const asset={name:args.name,state:'uploaded',size:args.data.length,digest:`sha256:${hash(args.data)}`};uploaded.push(asset);return {data:change.badUpload ? {...asset,digest:'sha256:bad'} : asset};},listReleaseAssets:()=>{},updateRelease:async args=>{writes.push(['publish',args]);return {data:{draft:false,prerelease:true,tag_name:'0.2.16',html_url:'https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.16'}};}}},paginate:async()=>change.badInventory ? uploaded.slice(1) : change.extraUploaded ? [...uploaded,{name:'private.txt'}] : uploaded};
  const core={summary:{addLink(){return this;},async write(){}}};
  return {context,io,github,core,writes,data};
}
test('publishes exact fresh inventory through draft and verifies all hashes',async()=>{const f=fixture();await publish(f,f.io);assert.deepEqual(f.writes.map(x=>x[0]),['tag','draft','publish']);assert.equal(f.writes[1][1].draft,true);assert.equal(f.writes[2][1].make_latest,'false');assert.equal(f.writes[2][1].prerelease,true);});
for(const [name,change,pattern] of [
  ['existing release',{existing:true},/exists/],['wrong existing tag',{badTag:true},/Tag/],['matching existing tag',{existingTag:true},/Tag/],
  ['moved main',{mainMoves:true},/Main moved/],['bad upload digest',{badUpload:true},/Upload verification/],
  ['missing uploaded asset',{badInventory:true},/inventory/],['not reviewed ancestor',{ancestorFails:true},/ancestor/],
  ['unresolved pin',{manifest:m=>m.reviewedSourceCommit='REPLACE_WITH_VERIFIED_COMMIT'},/source pin/],
  ['wrong source commit',{manifest:m=>m.commit=pin},/provenance/],['wrong run',{manifest:m=>m.validationRun+='4'},/provenance/],
  ['false full regression claim',{manifest:m=>m.scope.fullRegression=true},/scope/],
  ['false install acceptance claim',{manifest:m=>m.scope.installerExecuted=true},/scope/],
  ['payload changed',{data:d=>d.set(PAYLOADS[0],Buffer.from('different'))},/hash\/size/],
  ['missing checksum line',{data:d=>d.set('SHA256SUMS.txt',Buffer.from('wrong\n'))},/Checksum/],
  ['extra public file',{data:d=>d.set('private.txt',Buffer.from('never publish'))},/inventory/]
]) test(`refuses ${name}`,async()=>{const f=fixture(change);await assert.rejects(publish(f,f.io),pattern);assert.equal(f.writes.some(w=>w[0]==='publish'),false);});
test('refuses non-main or wrong repository before external actions',()=>{for(const modify of [c=>c.ref='refs/heads/topic',c=>c.repo.owner='other']){const f=fixture();modify(f.context);assert.throws(()=>validateInputs(f.context,f.io),/original repository main/);assert.equal(f.writes.length,0);}});
test('refuses duplicate payload entries in manifest',()=>{const f=fixture({manifest:m=>m.files.push(m.files[0])});assert.throws(()=>validateInputs(f.context,f.io),/inventory/);});
test('refuses pin different from preparation script',()=>{const f=fixture({manifest:m=>m.reviewedSourceCommit='c'.repeat(40)});assert.throws(()=>validateInputs(f.context,f.io),/pin mismatch/);});

for(const flag of ['ok','windowsRuntimeExecuted','settingsWebViewReady','expectedLocalWebViewProfileCreated','roamingDirectoryAvailable','packageUnchangedAfterRun','realTranslationBothDirections','embeddedCaptureMemorySelfTest','peDependencyChecks','launcherMissingZeroPresentMocks']) {
  test(`refuses missing ZIP runtime flag ${flag}`,()=>{const f=fixture({runtime:r=>delete r[flag]});assert.throws(()=>validateInputs(f.context,f.io),/runtime evidence/);});
}
for(const [name,change,pattern] of [
 ['missing exact-source CI',{runs:[]},/exact-source CI/],
 ['wrong-source CI',{runs:[{id:10,head_sha:pin,event:'push',path:'.github/workflows/ci.yml',status:'completed',conclusion:'success'}]},/exact-source CI/],
 ['pull-request CI',{runs:[{id:10,head_sha:sha,event:'pull_request',path:'.github/workflows/ci.yml',status:'completed',conclusion:'success'}]},/exact-source CI/],
 ['different workflow CI',{runs:[{id:10,head_sha:sha,event:'push',path:'.github/workflows/other.yml',status:'completed',conclusion:'success'}]},/exact-source CI/],
 ['latest CI still running',{runs:[{id:10,head_sha:sha,event:'push',path:'.github/workflows/ci.yml',status:'completed',conclusion:'success'},{id:11,head_sha:sha,event:'push',path:'.github/workflows/ci.yml',status:'in_progress',conclusion:null}]},/exact-source CI/],
 ['failed exact-source CI',{runs:[{id:10,head_sha:sha,event:'push',path:'.github/workflows/ci.yml',status:'completed',conclusion:'failure'}]},/exact-source CI/],
 ['extra uploaded asset',{extraUploaded:true},/inventory/],
 ['ZIP wrong source',{portable:p=>p.commit=pin},/ZIP source/],
 ['ZIP wrong version',{portable:p=>p.version='0.2.13'},/ZIP source/],
 ['ZIP portable-data overclaim',{portable:p=>p.userDataPortable=true},/ZIP source/],
 ['ZIP wrong runtime hash',{runtime:r=>r.archiveSha256='f'.repeat(64)},/runtime evidence/],
 ['ZIP wrong archive hash',{portable:p=>p.archives[0].sha256='f'.repeat(64)},/archive identity/],
 ['ZIP wrong source archive hash',{portable:p=>p.archives[1].sha256='f'.repeat(64)},/archive identity/],
 ['ZIP failed cleanup',{runtime:r=>r.cleanupComplete=false},/scope or cleanup/],
 ['ZIP capture overclaim',{runtime:r=>r.interactiveCaptureTested=true},/scope or cleanup/],
 ['ZIP network overclaim',{runtime:r=>r.networkIsolationTested=true},/scope or cleanup/]
]) test(`refuses ${name}`,async()=>{const f=fixture(change);await assert.rejects(publish(f,f.io),pattern);assert.equal(f.writes.some(w=>w[0]==='publish'),false);if(name.includes('CI'))assert.equal(f.writes.length,0);});

for(const section of ['windowsSettingsAcceptance','windowsGeneratedFocusAcceptance']) {
  test(`refuses missing ${section}`,async()=>{const f=fixture({manifest:m=>delete m[section]});await assert.rejects(publish(f,f.io),/acceptance missing/);assert.equal(f.writes.length,0);});
}
for(const [name,mutate,pattern] of [
 ['settings UI false',m=>m.windowsSettingsAcceptance.actualSettingsUiTested=false,/settings acceptance/],
 ['settings fake IPC',m=>m.windowsSettingsAcceptance.fakeIpcUsed=true,/settings acceptance/],
 ['settings different app',m=>m.windowsSettingsAcceptance.applicationSha256='f'.repeat(64),/settings acceptance/],
 ['settings evidence missing',m=>delete m.windowsSettingsAcceptance.evidence,/settings acceptance/],
 ['settings evidence hash invalid',m=>m.windowsSettingsAcceptance.evidence.sha256='invalid',/settings acceptance/],
 ['settings evidence filename wrong',m=>m.windowsSettingsAcceptance.evidence.name='other.json',/settings acceptance/],
 ['focus not generated',m=>m.windowsGeneratedFocusAcceptance.generatedSourceOnly=false,/focus acceptance/],
 ['focus app overclaim',m=>m.windowsGeneratedFocusAcceptance.actualApplicationTested=true,/focus acceptance/],
 ['focus incomplete cases',m=>m.windowsGeneratedFocusAcceptance.passedCases=1,/focus acceptance/],
 ['focus string cases',m=>m.windowsGeneratedFocusAcceptance.passedCases='2',/focus acceptance/],
 ['focus assembly hash missing',m=>delete m.windowsGeneratedFocusAcceptance.nativeAssemblySha256,/focus acceptance/],
 ['focus assembly hash invalid',m=>m.windowsGeneratedFocusAcceptance.nativeAssemblySha256='invalid',/focus acceptance/],
 ['focus evidence missing',m=>delete m.windowsGeneratedFocusAcceptance.evidence,/focus acceptance/],
 ['focus evidence hash invalid',m=>m.windowsGeneratedFocusAcceptance.evidence.sha256='invalid',/focus acceptance/],
 ['focus evidence filename wrong',m=>m.windowsGeneratedFocusAcceptance.evidence.name='other.json',/focus acceptance/]
]) test(`refuses ${name}`,async()=>{const f=fixture({manifest:mutate});await assert.rejects(publish(f,f.io),pattern);assert.equal(f.writes.length,0);});
for(const invalid of [undefined,'invalid']) test(`refuses jointly invalid settings/runtime app identity ${invalid}`,async()=>{
  const f=fixture({manifest:m=>{m.windowsSettingsAcceptance.applicationSha256=invalid;m.windowsZipRuntime.applicationSha256=invalid;}});
  await assert.rejects(publish(f,f.io),/settings acceptance/);assert.equal(f.writes.length,0);
});

for(const field of ['version','commit','tree','runUrl','installerSha256','applicationSha256','ok','extractedBundleLaunched','restartPassed','secondInstancePassed','frontendWebViewReady','settingsWindowShown','nativeSelfTestsPassed','nativeWindowResizeFixturePassed','packageUnchangedAfterRun','cleanupComplete','fakeIpcUsed','userContentRead','codexInteractiveSelectionTested']) {
  for(const bad of [undefined, 'wrong']) test(`refuses macOS runtime ${field} = ${bad}`,async()=>{
    const f=fixture({manifest:m=>m.macOSRuntimeAcceptance[field]=bad});
    await assert.rejects(publish(f,f.io),/macOS runtime/);assert.equal(f.writes.length,0);
  });
}
test('refuses missing macOS runtime report',async()=>{const f=fixture({manifest:m=>delete m.macOSRuntimeAcceptance});await assert.rejects(publish(f,f.io),/macOS runtime/);assert.equal(f.writes.length,0);});
