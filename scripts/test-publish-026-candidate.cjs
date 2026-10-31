'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const P = require('./publish-026-candidate.cjs');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
function pins() {
  return { ...structuredClone(P.PIN), ready: true, jobs:P.PIN.jobs.map((j,i)=>({...j,id:i+1})), macOSReinspection:{...structuredClone(P.PIN.macOSReinspection),runId:12345,commit:'c'.repeat(40),tree:'d'.repeat(40),job:{...P.PIN.macOSReinspection.job,id:5}}, windowsReinspection:{...structuredClone(P.PIN.windowsReinspection),runId:67890,commit:'e'.repeat(40),tree:'f'.repeat(40),job:{...P.PIN.windowsReinspection.job,id:6}}, artifacts: [
    { platform:'Windows',id:1,name:'EchoLingo-0.2.6-candidate-Windows-reinspected',size:4,sha256:hash(Buffer.alloc(4)),installer:'EchoLingo_0.2.6_x64-setup.exe' },
    { platform:'macOS',id:2,name:'EchoLingo-0.2.6-candidate-macOS-reinspected',size:5,sha256:hash(Buffer.alloc(5)),installer:'EchoLingo_0.2.6_aarch64.dmg' },
  ] };
}
function evidence(pin = pins()) {
  const r=pin.macOSReinspection,w=pin.windowsReinspection;
  const run=(id,commit,branch,conclusion)=>({id,head_sha:commit,head_branch:branch,event:'push',status:'completed',conclusion,run_attempt:1,repository:{id:1432139657,full_name:'Blueeeecho/EchoLingo'},head_repository:{id:1432139657}});
  const artifact=(a,run,commit,branch)=>({id:a.id,name:a.name,digest:`sha256:${a.sha256}`,size_in_bytes:a.size,expired:false,workflow_run:{id:run,head_sha:commit,head_branch:branch,repository_id:1432139657,head_repository_id:1432139657}});
  return [run(P.RUN,P.SOURCE,pin.sourceBranch,'failure'),
    pin.jobs.map(j=>({...j,run_id:P.RUN,head_sha:P.SOURCE,status:'completed',conclusion:j.name.includes('candidate (')?'failure':'success',steps:j.name.includes('candidate (')?[
      {name:'Build fresh application and installer with locked dependencies',status:'completed',conclusion:'success'},
      {name:'Inspect fresh installer bytes without installing or launching the application',status:'completed',conclusion:'failure'},
      {name:'Upload unverified build diagnosis separately from candidates',status:'completed',conclusion:'success'},
    ]:[]})),
    pin.artifacts.map(a=>artifact(a,a.platform==='Windows'?w.runId:r.runId,a.platform==='Windows'?w.commit:r.commit,a.platform==='Windows'?w.branch:r.branch)),
    {...run(r.runId,r.commit,r.branch,'success'),path:r.workflowPath},
    [{...r.job,run_id:r.runId,head_sha:r.commit,status:'completed',conclusion:'success'}],
    artifact(r.inputArtifact,P.RUN,P.SOURCE,pin.sourceBranch),
    {...run(w.runId,w.commit,w.branch,'success'),path:w.workflowPath},
    [{...w.job,run_id:w.runId,head_sha:w.commit,status:'completed',conclusion:'success'}],
    artifact(w.inputArtifact,P.RUN,P.SOURCE,pin.sourceBranch),
  ];
}
test('incomplete checked-in evidence cannot publish', () => {
  assert.throws(() => P.validatePins({...pins(),ready:false}));
  if (P.PIN.ready) assert.doesNotThrow(() => P.validatePins(P.PIN));
  else assert.throws(() => P.validatePins(P.PIN));
});
test('original failure and exact successful same-byte reinspection are both required', () => {
  assert.doesNotThrow(() => P.validateEvidence(...evidence(),pins()));
});
for (const field of ['id','head_sha','head_branch','event','status','conclusion','run_attempt','repository','head_repository']) {
  test(`reject mismatched run ${field}`, () => { const e=evidence(); e[0][field]='wrong'; assert.throws(() => P.validateEvidence(...e,pins())); });
}
for (let index=0; index<4; index++) test(`job ${index} cannot be skipped or failed`, () => {
  for (const value of ['skipped',index>=2?'success':'failure','cancelled',null]) { const e=evidence(); e[1][index].conclusion=value; assert.throws(() => P.validateEvidence(...e,pins())); }
});
for (const field of ['id','name','size_in_bytes','digest','expired','workflow_run']) test(`reject altered artifact ${field}`, () => {
  const e=evidence(); e[2][0][field]='wrong'; assert.throws(() => P.validateEvidence(...e,pins()));
});
test('extra jobs, duplicate identities and incomplete artifact pins rejected', () => {
  const e=evidence(); e[1].push(e[1][0]); assert.throws(() => P.validateEvidence(...e,pins()));
  for (const field of ['sourceCommit','sourceTree','runId','repositoryId','version']) assert.throws(() => P.validatePins({...pins(),[field]:'wrong'}));
  const p=pins();p.artifacts.pop();assert.throws(() => P.validatePins(p));
});
function lifecycle(failure) {
  const pin=pins(), e=evidence(pin), calls=[], names=P.assetNames(pin);
  const context={repo:{owner:'Blueeeecho',repo:'EchoLingo'},payload:{repository:{id:1432139657}},eventName:'push',ref:`refs/heads/${P.BRANCH}`,sha:'a'.repeat(40)};
  const manifest={version:'0.2.6',sourceCommit:P.SOURCE,sourceTree:P.TREE,publisherCommit:context.sha,validationRun:`https://github.com/Blueeeecho/EchoLingo/actions/runs/${P.RUN}`,rebuiltAfterValidation:false,installedApplicationAcceptance:false,interactiveSelectionAcceptance:false,buildRunConclusion:'failure',reinspectionRunConclusion:'success',reinspectionRunUrl:`https://github.com/Blueeeecho/EchoLingo/actions/runs/${pin.macOSReinspection.runId}`,reinspectionCommit:pin.macOSReinspection.commit,windowsReinspectionRunUrl:`https://github.com/Blueeeecho/EchoLingo/actions/runs/${pin.windowsReinspection.runId}`,windowsReinspectionCommit:pin.windowsReinspection.commit,windowsReinspectionRunConclusion:'success'};
  const content=name => Buffer.from(name==='RELEASE-MANIFEST.json'?JSON.stringify(manifest):`synthetic ${name}`);
  const assets=names.map(name=>({name,state:'uploaded',size:content(name).length,digest:`sha256:${hash(content(name))}`}));
  const draft={id:27,draft:true,prerelease:true,tag_name:'0.2.6'};
  let branchReads=0, tagCreated=false, evidenceReads=0;
  const github={rest:{git:{
    getRef:async({ref})=>{
      if(ref.startsWith('heads/')) { branchReads++;return {data:{object:{type:'commit',sha:failure==='branch'||(failure==='moved'&&branchReads>=3)?'bad':context.sha}}}; }
      if(failure==='tag-api')throw Object.assign(new Error('unavailable'),{status:503});
      if(failure==='new-tag'&&!tagCreated)throw Object.assign(new Error('missing'),{status:404});
      return {data:{object:{type:'commit',sha:failure==='tag'?'bad':P.SOURCE}}};
    },
    getCommit:async({commit_sha})=>({data:{sha:commit_sha,tree:{sha:failure==='tree'?'bad':commit_sha===P.SOURCE?P.TREE:commit_sha===pin.macOSReinspection.commit?pin.macOSReinspection.tree:pin.windowsReinspection.tree}}}),
    createRef:async(a)=>{assert.equal(a.ref,'refs/tags/0.2.6');assert.equal(a.sha,P.SOURCE);tagCreated=true;calls.push(['tag',a]);},
  },actions:{
    getWorkflowRun:async({run_id})=>{if(run_id!==P.RUN)return {data:run_id===pin.macOSReinspection.runId?e[3]:e[6]};evidenceReads++;return {data:failure==='run-changed'&&evidenceReads>1?{...e[0],run_attempt:2}:e[0]};},
    listJobsForWorkflowRun:'jobs',getArtifact:async({artifact_id})=>({data:[...e[2],e[5],e[8]].find(a=>a.id===artifact_id)}),
    downloadArtifact:async({artifact_id})=>({data:Buffer.alloc(pin.artifacts.find(a=>a.id===artifact_id).size,failure==='download'?1:0)}),
  },repos:{
    getReleaseByTag:async()=>{if(failure==='exists')return {data:draft};throw Object.assign(new Error('not available'),{status:failure==='release-api'?403:404});},
    createRelease:async(a)=>{calls.push(['draft',a]);return {data:draft};},
    uploadReleaseAsset:async({name,data})=>{calls.push(['upload',name]);return {data:{name,state:'uploaded',size:data.length,digest:failure==='upload'?'bad':`sha256:${hash(data)}`}};},
    listReleaseAssets:'assets',getRelease:async()=>({data:{...draft,draft:failure!=='draft-changed'}}),
    updateRelease:async(a)=>{calls.push(['publish',a]);return {data:{...draft,draft:false,html_url:'https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.6'}};},
  }},paginate:async(api,options)=>api==='jobs'?(options.run_id===P.RUN?e[1]:options.run_id===pin.macOSReinspection.runId?e[4]:e[7]):failure==='inventory'?assets.slice(1):failure==='asset-digest'?assets.map(a=>({...a,digest:'bad'})):assets};
  const io={sha256:hash,execFileSync:(command,args)=>{
    if(command==='python3'){calls.push(['prepare',args]);if(failure==='prepare')throw new Error('unsafe archive');return '';}
    if(args[0]==='status')return failure==='dirty'?' M package.json':'';
    if(args[0]==='diff')return failure==='product-diff'?'M\tsrc/main.ts':args.at(-1)===pin.macOSReinspection.commit?P.INSPECTION_CHANGES.join('\n'):args.at(-1)===pin.windowsReinspection.commit?P.WINDOWS_INSPECTION_CHANGES.join('\n'):P.ALLOWED.map(p=>`A\t${p}`).join('\n');
    return args[1]==='HEAD'?context.sha:args[1]===`${pin.macOSReinspection.commit}^{tree}`?pin.macOSReinspection.tree:args[1]===`${pin.windowsReinspection.commit}^{tree}`?pin.windowsReinspection.tree:P.TREE;
  },fs:{mkdirSync:()=>{},writeFileSync:()=>{},readdirSync:()=>names,readFileSync:(path,encoding)=>{
    const name=path.split('/').at(-1);const bytes=content(name);return encoding?(path.endsWith('.md')?'Known acceptance limits':bytes.toString()):bytes;
  }}};
  const core={summary:{addLink(){return this;},write:async()=>{}}};
  return {run:()=>P.publish({github,context,core},io,pin),calls,context};
}
for(const f of ['exists','release-api','branch','tree','dirty','product-diff','download','prepare','tag','tag-api','upload','inventory','asset-digest','moved','run-changed','draft-changed'])test(`lifecycle ${f} fails closed`,async()=>{
  const l=lifecycle(f);await assert.rejects(l.run());assert.equal(l.calls.some(c=>c[0]==='publish'),false);
  if(!['upload','inventory','asset-digest','moved','run-changed','draft-changed'].includes(f))assert.equal(l.calls.some(c=>c[0]==='draft'),false);
});
test('tag points at tested source, then draft, nine verified assets, prerelease not latest',async()=>{
  const l=lifecycle('new-tag');await l.run();const events=l.calls.map(c=>c[0]);
  assert(events.indexOf('tag')<events.indexOf('draft'));assert.equal(events.filter(e=>e==='upload').length,9);
  const created=l.calls.find(c=>c[0]==='draft')[1];assert.equal(created.target_commitish,P.SOURCE);assert.equal(created.draft,true);assert.equal(created.prerelease,true);assert.equal(created.make_latest,'false');
  assert.equal(l.calls.at(-1)[0],'publish');assert.equal(l.calls.at(-1)[1].make_latest,'false');
});
test('wrong repository, ref or event cannot publish',async()=>{
  for(const mutate of [c=>c.payload.repository.id=1,c=>c.ref='refs/heads/main',c=>c.eventName='workflow_dispatch']) {
    const l=lifecycle();mutate(l.context);await assert.rejects(l.run());assert.equal(l.calls.length,0);
  }
});
test('workflow is release-only, source-bound, read-default, no rebuild or arbitrary inputs',()=>{
  const w=fs.readFileSync('.github/workflows/publish-026-candidate.yml','utf8');
  assert.match(w,/branches: \[release\/026-verified-candidate\]/);assert.match(w,/paths: \[.github\/workflows\/publish-026-candidate.yml\]/);
  assert.match(w,/permissions:\n  contents: read\n  actions: read/);assert.match(w,/needs: policy-tests/);
  assert.equal((w.match(/contents: write/g)||[]).length,1);assert.equal((w.match(/ref: \$\{\{ github.sha \}\}/g)||[]).length,2);
  assert.equal((w.match(/persist-credentials: false/g)||[]).length,2);assert.match(w,/retries: 0/);
  assert.doesNotMatch(w,/workflow_dispatch|pull_request|continue-on-error|npm |cargo |secrets\.|gh release|git push/);
  assert.match(w,/checkout@[a-f0-9]{40}/);assert.match(w,/github-script@[a-f0-9]{40}/);
});

for(const field of ['id','head_sha','head_branch','event','status','conclusion','run_attempt','path'])test(`reinspection run ${field} cannot change`,()=>{
  const e=evidence();e[3][field]='wrong';assert.throws(()=>P.validateEvidence(...e,pins()));
});
test('original overall failure cannot be relabeled green and Mac build must pass',()=>{
  let e=evidence();e[0].conclusion='success';assert.throws(()=>P.validateEvidence(...e,pins()));
  e=evidence();e[1][2].steps[0].conclusion='failure';assert.throws(()=>P.validateEvidence(...e,pins()));
  e=evidence();e[1][2].steps.push({name:'Unrelated failure',status:'completed',conclusion:'failure'});assert.throws(()=>P.validateEvidence(...e,pins()));
});
test('original unverified bytes and successful inspection job are mandatory',()=>{
  for(const index of [4,5]) {const e=evidence();if(index===4)e[4][0].conclusion='failure';else e[5].digest='bad';assert.throws(()=>P.validateEvidence(...e,pins()));}
  const p=pins();p.macOSReinspection.allowedChanges.push({status:'M',path:'src/main.ts'});assert.throws(()=>P.validatePins(p));
});

test('original Windows failure cannot be relabeled success',()=>{const e=evidence();e[1][3].conclusion='success';assert.throws(()=>P.validateEvidence(...e,pins()));});

for(const field of ['id','head_sha','head_branch','event','status','conclusion','run_attempt','path'])test(`Windows reinspection ${field} must match`,()=>{const e=evidence();e[6][field]='wrong';assert.throws(()=>P.validateEvidence(...e,pins()));});
test('Windows exact marker proof and successful separate job are required',()=>{
  const e=evidence();e[7][0].conclusion='failure';assert.throws(()=>P.validateEvidence(...e,pins()));
  for(const [field,value] of [['changedBytes',4],['markerOffset',0],['expectedNsisSha256','0'.repeat(64)],['actualExecutablesModified',true]]) {const p=pins();p.windowsReinspection.applicationIdentity[field]=value;assert.throws(()=>P.validatePins(p));}
  const p=pins();p.windowsReinspection.allowedChanges.push({status:'M',path:'src/main.ts'});assert.throws(()=>P.validatePins(p));
});
