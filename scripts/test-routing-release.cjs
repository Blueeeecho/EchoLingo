'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const path = require('node:path');
const {publish, validateInputs, NAMES, PAYLOADS, MODE} = require('./publish-routing-release.cjs');
const sha = 'a'.repeat(40), pin = 'b'.repeat(40);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function fixture(change = {}) {
  const context = {repo:{owner:'Blueeeecho',repo:'EchoLingo'}, ref:'refs/heads/main', sha, runId:123};
  const data = new Map(PAYLOADS.map(name => [name, Buffer.from(`payload ${name}`)]));
  const manifest = {version:'0.2.13', commit:sha, reviewedSourceCommit:pin, validationRun:'https://github.com/Blueeeecho/EchoLingo/actions/runs/123', validationMode:MODE, scope:{fullRegression:false,installerExecuted:false,visualAcceptance:false}, files:PAYLOADS.map(name => ({name,size:data.get(name).length,sha256:hash(data.get(name))}))};
  change.manifest?.(manifest);
  data.set('RELEASE-MANIFEST.json', Buffer.from(JSON.stringify(manifest)));
  data.set('SHA256SUMS.txt', Buffer.from([...data].map(([name, bytes]) => `${hash(bytes)}  ${name}\n`).sort().join('')));
  change.data?.(data);
  const io = {fs:{readdirSync:() => [...data.keys()], lstatSync:filename => ({isFile:()=>true,isSymbolicLink:()=>false,size:data.get(path.basename(filename)).length}), readFileSync:(filename, encoding) => filename.replaceAll('\\', '/').startsWith('docs/') ? 'Public release notes' : encoding ? data.get(path.basename(filename)).toString(encoding) : data.get(path.basename(filename))}, execFileSync:(cmd,args) => {if(cmd==='python3') return pin+'\n'; if(change.ancestorFails) throw new Error('Not ancestor'); return '';}};
  let mainCalls = 0, tagExists = false;
  const writes = [], uploaded = [];
  const missing = () => {throw Object.assign(new Error('Missing'), {status:404});};
  const github = {rest:{git:{getRef:async ({ref}) => {
    if(ref === 'heads/main') return {data:{object:{type:'commit',sha:change.mainMoves && ++mainCalls >= 3 ? 'c'.repeat(40):sha}}};
    if(change.badTag) return {data:{object:{type:'commit',sha:pin}}};
    if(!tagExists) missing();
    return {data:{object:{type:'commit',sha}}};
  },createRef:async args => {writes.push(['tag',args]);tagExists=true;}},repos:{getReleaseByTag:async()=>{if(change.existing) return {data:{id:3}};missing();},createRelease:async args=>{writes.push(['draft',args]);return {data:{id:12}};},uploadReleaseAsset:async args=>{const asset={name:args.name,state:'uploaded',size:args.data.length,digest:`sha256:${hash(args.data)}`};uploaded.push(asset);return {data:change.badUpload ? {...asset,digest:'sha256:bad'} : asset};},listReleaseAssets:()=>{},updateRelease:async args=>{writes.push(['publish',args]);return {data:{draft:false,prerelease:true,tag_name:'0.2.13',html_url:'https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.13'}};}}},paginate:async()=>change.badInventory ? uploaded.slice(1) : uploaded};
  const core={summary:{addLink(){return this;},async write(){}}};
  return {context,io,github,core,writes,data};
}
test('publishes exact fresh inventory through draft and verifies all hashes',async()=>{const f=fixture();await publish(f,f.io);assert.deepEqual(f.writes.map(x=>x[0]),['tag','draft','publish']);assert.equal(f.writes[1][1].draft,true);assert.equal(f.writes[2][1].make_latest,'false');assert.equal(f.writes[2][1].prerelease,true);});
for(const [name,change,pattern] of [
  ['existing release',{existing:true},/exists/],['wrong existing tag',{badTag:true},/Tag/],
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
