const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { validateEvidence, SOURCE, RUN, ARTIFACT, DIGEST } = require('./publish-macos-first-release.cjs');
const evidence = () => [
 { id:RUN, head_sha:SOURCE, head_branch:'main', event:'push', status:'completed', conclusion:'failure', run_attempt:1, repository:{full_name:'Blueeeecho/EchoLingo'} },
 [{id:123959559790,name:'verify / desktop (macos-latest)',run_id:RUN,head_sha:SOURCE,status:'completed',conclusion:'success'}, {id:123959559755,name:'verify / frontend-interactions',run_id:RUN,head_sha:SOURCE,status:'completed',conclusion:'success'}],
 {id:ARTIFACT,name:'EchoLingo-macOS',expired:false,digest:DIGEST,size_in_bytes:4891806,workflow_run:{id:RUN,head_sha:SOURCE,head_repository_id:1432139657}}
];
test('accepts only explicitly scoped successful Mac and frontend jobs from the failed overall run',()=>assert.doesNotThrow(()=>validateEvidence(...evidence())));
for (const field of ['id','head_sha','head_branch','event','status','conclusion','run_attempt']) test(`reject changed source run ${field}`,()=>{const e=evidence(); e[0][field]='wrong'; assert.throws(()=>validateEvidence(...e));});
for(const index of [0,1]) for(const field of ['id','name','run_id','head_sha','status','conclusion']) test(`reject job ${index} ${field}`,()=>{const e=evidence();e[1][index][field]='wrong';assert.throws(()=>validateEvidence(...e));});
for(const field of ['id','name','expired','digest','size_in_bytes']) test(`reject artifact ${field}`,()=>{const e=evidence();e[2][field]='wrong';assert.throws(()=>validateEvidence(...e));});
for(const field of ['id','head_sha','head_repository_id']) test(`reject artifact run ${field}`,()=>{const e=evidence();e[2].workflow_run[field]='wrong';assert.throws(()=>validateEvidence(...e));});
test('publication remains narrow and no rebuild/Windows upload is possible',()=>{
 const workflow=fs.readFileSync('.github/workflows/release-macos-first.yml','utf8');
 assert.match(workflow,/paths: \[.github\/workflows\/release-macos-first.yml\]/);
 assert.match(workflow,/contents: write\n      actions: read/);
 assert.doesNotMatch(workflow,/npm |cargo |secrets\./);
 const script=fs.readFileSync('scripts/publish-macos-first-release.cjs','utf8');
 assert.match(script,/draft: true, prerelease: true/);
 assert.match(script,/draft: false, prerelease: true/);
 assert.match(script,/target_commitish: SOURCE/);
 assert.match(script,/asset.digest !== `sha256:/);
 assert.match(script,/Release exists; no overwrite/);
 assert.doesNotMatch(script,/\.exe['"`]/);
});
const { publish } = require('./publish-macos-first-release.cjs');
function lifecycle(failure) {
 const e=evidence(), calls=[];
 const missing = () => { throw Object.assign(new Error('not found'),{status:404}); };
 const names=['EchoLingo_0.2.1_macos_arm64.dmg','EchoLingo_0.2.1_source.zip','RELEASE-MANIFEST.json','SHA256SUMS.txt'].sort();
 const context={repo:{owner:'Blueeeecho',repo:'EchoLingo'},ref:'refs/heads/main',sha:'a'.repeat(40)};
 const github = {
   rest: {
     git: {
       getRef: async ({ref}) => {
         if (ref === 'heads/main') return {data:{object:{sha:context.sha}}};
         return {data:{object:{type:'commit',sha:failure === 'tag' ? 'b'.repeat(40) : SOURCE}}};
       }
     },
     actions: {
       getWorkflowRun: async () => ({data:e[0]}), listJobsForWorkflowRun:'jobs',
       getArtifact: async () => ({data:e[2]}), downloadArtifact:async()=>({data:Buffer.from('archive')})
     },
     repos: {
       getReleaseByTag:async()=>{if(failure==='exists')return{data:{id:1}};missing();},
       createRelease:async(args)=>{calls.push(['create',args]);return{data:{id:2}};},
       uploadReleaseAsset:async({name,data})=>{calls.push(['upload',name]);return{data:{state:'uploaded',size:data.length,digest:failure==='upload'?'bad':'sha256:asset'}};},
       listReleaseAssets:'assets',
       updateRelease:async(args)=>{calls.push(['publish',args]);return{data:{draft:false,prerelease:true,tag_name:'0.2.1',html_url:'https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.1'}};}
     }
   },
   paginate:async(api)=>api==='jobs'?e[1]:names.map(name=>({name}))
 };

 const io={sha256:bytes=>bytes.toString()==='archive'?DIGEST.slice(7):'asset',execFileSync:()=>{},fs:{writeFileSync:()=>{},readdirSync:()=>names,readFileSync:(path,encoding)=>encoding?JSON.stringify({sourceCommit:SOURCE,publisherCommit:context.sha,releaseScope:'macos-only',windows:{published:false}}):Buffer.from('asset')}};
 const core={summary:{addLink(){return this;},write:async()=>{}}};
 return { run:()=>publish({github,context,core},io),calls };
}
for(const failure of ['exists','tag','upload'])test(`lifecycle ${failure} failure never publishes`,async()=>{const l=lifecycle(failure);await assert.rejects(l.run());assert.equal(l.calls.some(c=>c[0]==='publish'),false);if(failure!=='upload')assert.equal(l.calls.some(c=>c[0]==='create'),false);});
test('lifecycle uploads four assets to draft before public prerelease',async()=>{const l=lifecycle();await l.run();assert.equal(l.calls[0][0],'create');assert.equal(l.calls[0][1].draft,true);assert.equal(l.calls.filter(c=>c[0]==='upload').length,4);assert.equal(l.calls.at(-1)[0],'publish');assert.equal(l.calls.at(-1)[1].draft,false);});
