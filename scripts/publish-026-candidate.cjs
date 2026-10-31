'use strict';
// One-shot publication of already-tested bytes. No rebuild, install, retry or overwrite.
const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const PIN = require('./release-026-evidence.json');
const BRANCH = 'release/026-verified-candidate';
const SOURCE = 'd91b59505f81d766eca25a8cff4764c278542275';
const TREE = '2898ee1bad7f1d73d408d2ad5fc136cfc869fe3a';
const RUN = 41195400127;
const REPOSITORY = 'Blueeeecho/EchoLingo';
const REPOSITORY_ID = 1432139657;
const ALLOWED = [
  '.github/workflows/publish-026-candidate.yml',
  'scripts/publish-026-candidate.cjs', 'scripts/test-publish-026-candidate.cjs',
  'scripts/prepare-026-candidate.py', 'scripts/test_prepare_026_candidate.py',
  'scripts/release-026-evidence.json', 'docs/releases/0.2.6-candidate.md',
].sort();
const JOB_NAMES = ['native-selection-recovery',
  'Compile Windows host and focused input policies (no package output)',
  'Build and inspect 0.2.6 candidate (macos-latest)',
  'Build and inspect 0.2.6 candidate (windows-latest)'].sort();
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const requireThat = (test, message) => { if (!test) throw new Error(message); };
const INSPECTION_CHANGES = [
  'A\t.github/workflows/reinspect-026-macos-package.yml',
  'A\tscripts/reinspect-026-macos-package.py',
  'M\tscripts/inspect-candidate-package.py',
  'M\tscripts/test_inspect_candidate_package.py',
].sort();
const INPUT_ARTIFACT = {id:13041241190,name:'EchoLingo-0.2.6-UNVERIFIED-build-macOS',size:9596150,sha256:'c877dcf26a6e85d7ee8e3f7682980b20fbb68f3241065efbdb99b86d65377ba8'};
const WINDOWS_INSPECTION_CHANGES = ['A\t.github/workflows/diagnose-026-windows-package.yml','A\tscripts/diagnose-026-windows-package.py','M\tscripts/inspect-candidate-package.py','M\tscripts/test_inspect_candidate_package.py'].sort();
const WINDOWS_INPUT_ARTIFACT = {"id": 13040982741, "name": "EchoLingo-0.2.6-UNVERIFIED-build-Windows", "size": 79796541, "sha256": "4787f328c08f8b9e4afd9a2881efcac192047cc38e73c5a9ae3add1b86116618"};
const WINDOWS_APPLICATION_IDENTITY = {"schemaVersion": 1, "method": "tauri-cli-2.12.4-nsis-bundle-marker", "stageSha256": "5027e0162754b53689219b15d710680c49579fe4974bb5acf6bc2204469c03f4", "packagedSha256": "159ffa2b057b1e106d64022acd554f7cf2d75f9e4e0294b916e043f55414e653", "expectedNsisSha256": "159ffa2b057b1e106d64022acd554f7cf2d75f9e4e0294b916e043f55414e653", "markerOffset": 7402725, "stageMarker": "__TAURI_BUNDLE_TYPE_VAR_UNK", "packagedMarker": "__TAURI_BUNDLE_TYPE_VAR_NSS", "changedBytes": 3, "comparedBytes": 8223744, "actualExecutablesModified": false};
function validatePins(pin) {
  requireThat(equal(Object.keys(pin).sort(), ['schemaVersion','ready','version','repository','repositoryId','sourceCommit','sourceTree','runId','sourceBranch','jobs','artifacts','macOSReinspection','windowsReinspection'].sort()), 'Unexpected immutable evidence schema');
  requireThat(pin.schemaVersion === 1 && pin.ready === true && pin.version === '0.2.6' && pin.repository === REPOSITORY && pin.repositoryId === REPOSITORY_ID && pin.sourceCommit === SOURCE && pin.sourceTree === TREE && pin.runId === RUN && pin.sourceBranch === 'fix/025-macos-recovery-integration', 'Evidence is incomplete or not the authorized candidate');
  requireThat(Array.isArray(pin.jobs) && pin.jobs.length === 4 && equal(pin.jobs.map(j => j.name).sort(), JOB_NAMES) && new Set(pin.jobs.map(j => j.id)).size === 4 && pin.jobs.every(j => Number.isSafeInteger(j.id) && j.id > 0 && equal(Object.keys(j).sort(), ['id','name'])), 'Expected four immutable job pins');
  const r=pin.macOSReinspection;
  requireThat(r && equal(Object.keys(r).sort(), ['runId','commit','tree','branch','workflowPath','job','allowedChanges','inputArtifact','installerSha256','applicationSha256','licenseSha256'].sort()) && Number.isSafeInteger(r.runId) && r.runId > 0 && r.runId !== RUN && /^[0-9a-f]{40}$/.test(r.commit) && r.commit !== SOURCE && /^[0-9a-f]{40}$/.test(r.tree) && r.branch === 'verify/026-macos-package' && r.workflowPath === '.github/workflows/reinspect-026-macos-package.yml', 'Incomplete same-byte reinspection pins');
  requireThat(equal(Object.keys(r.job).sort(),['id','name']) && Number.isSafeInteger(r.job.id) && r.job.id>0 && r.job.name==='Reinspect the original 0.2.6 macOS bytes without rebuilding' && Array.isArray(r.allowedChanges) && equal(r.allowedChanges.map(c=>`${c.status}\t${c.path}`).sort(),INSPECTION_CHANGES), 'Unexpected inspection-only workflow delta/job');
  requireThat(equal(Object.keys(r.inputArtifact).sort(),Object.keys(INPUT_ARTIFACT).sort()) && Object.keys(INPUT_ARTIFACT).every(key=>r.inputArtifact[key]===INPUT_ARTIFACT[key]) && r.installerSha256==='441c7d00fee0701f1942b1e5fc173c79479385d71c8922507fd83163d37c26e7' && r.applicationSha256==='112c4888c2d6c3dd801f808364ccb2dc2d23ffd23219052822e0d50f6fbaaf17' && r.licenseSha256==='20ce870fd3c179bf06c2d28e32264a30e2a7b34e5d317d7aafe2ee0176849e71', 'Original macOS build bytes/license identity changed');
  const w=pin.windowsReinspection;
  requireThat(w && equal(Object.keys(w).sort(),['runId','commit','tree','branch','workflowPath','job','allowedChanges','inputArtifact','installerSha256','applicationSha256','applicationIdentity'].sort()) && Number.isSafeInteger(w.runId) && w.runId>0 && w.runId!==RUN && w.runId!==r.runId && /^[0-9a-f]{40}$/.test(w.commit) && w.commit!==SOURCE && /^[0-9a-f]{40}$/.test(w.tree) && w.branch==='verify/026-windows-package' && w.workflowPath==='.github/workflows/diagnose-026-windows-package.yml','Incomplete Windows same-byte reinspection pins');
  requireThat(equal(Object.keys(w.job).sort(),['id','name']) && Number.isSafeInteger(w.job.id) && w.job.id>0 && w.job.name==='Reinspect the original 0.2.6 Windows bytes without rebuilding' && Array.isArray(w.allowedChanges) && equal(w.allowedChanges.map(c=>`${c.status}\t${c.path}`).sort(),WINDOWS_INSPECTION_CHANGES),'Unexpected Windows tooling delta/job');
  requireThat(equal(Object.keys(w.inputArtifact).sort(),Object.keys(WINDOWS_INPUT_ARTIFACT).sort()) && Object.keys(WINDOWS_INPUT_ARTIFACT).every(key=>w.inputArtifact[key]===WINDOWS_INPUT_ARTIFACT[key]) && w.installerSha256==='d6849ba7dd241ca690b7b787cc7c50c4d1ff779100dc955ffed17ae7fb6973ae' && w.applicationSha256===WINDOWS_APPLICATION_IDENTITY.packagedSha256 && equal(Object.keys(w.applicationIdentity).sort(),Object.keys(WINDOWS_APPLICATION_IDENTITY).sort()) && Object.keys(WINDOWS_APPLICATION_IDENTITY).every(key=>w.applicationIdentity[key]===WINDOWS_APPLICATION_IDENTITY[key]),'Original Windows bytes or exact NSIS marker proof changed');
  requireThat(Array.isArray(pin.artifacts) && pin.artifacts.length === 2 && equal(pin.artifacts.map(a => a.platform).sort(), ['Windows','macOS']) && new Set(pin.artifacts.map(a => a.id)).size === 2, 'Expected two candidate artifact pins');
  for (const a of pin.artifacts) {
    const name=a.platform==='Windows'?'EchoLingo-0.2.6-candidate-Windows-reinspected':'EchoLingo-0.2.6-candidate-macOS-reinspected';
    requireThat(equal(Object.keys(a).sort(), ['platform','id','name','size','sha256','installer'].sort()) && Number.isSafeInteger(a.id) && a.id > 0 && Number.isSafeInteger(a.size) && a.size > 0 && a.size <= 512 * 1024 ** 2 && /^[0-9a-f]{64}$/.test(a.sha256) && a.name===name && a.installer===(a.platform==='Windows'?'EchoLingo_0.2.6_x64-setup.exe':'EchoLingo_0.2.6_aarch64.dmg'), 'Malformed candidate artifact pin');
  }
}
function validateRun(run,id,commit,branch,conclusion) {
  requireThat(run.id===id && run.head_sha===commit && run.head_branch===branch && run.event==='push' && run.status==='completed' && run.conclusion===conclusion && run.run_attempt===1 && run.repository?.id===REPOSITORY_ID && run.repository?.full_name===REPOSITORY && run.head_repository?.id===REPOSITORY_ID, 'Workflow run identity/outcome differs');
}
function validateArtifact(a,expected,run,commit,branch) {
  requireThat(a && a.id===expected.id && a.name===expected.name && a.expired===false && a.digest===`sha256:${expected.sha256}` && a.size_in_bytes===expected.size && a.workflow_run?.id===run && a.workflow_run?.head_sha===commit && a.workflow_run?.head_branch===branch && a.workflow_run?.repository_id===REPOSITORY_ID && a.workflow_run?.head_repository_id===REPOSITORY_ID, 'Candidate artifact identity differs');
}
function validateEvidence(run,jobs,artifacts,inspectionRun,inspectionJobs,inputArtifact,windowsRun,windowsJobs,windowsInputArtifact,pin=PIN) {
  validatePins(pin);
  validateRun(run,RUN,SOURCE,pin.sourceBranch,'failure');
  requireThat(jobs.length===4,'Unexpected original build job inventory');
  for(const expected of pin.jobs) {
    const matches=jobs.filter(j=>j.id===expected.id),j=matches[0];
    const packageJob=expected.name.startsWith('Build and inspect 0.2.6 candidate (');
    requireThat(matches.length===1 && j.name===expected.name && j.run_id===RUN && j.head_sha===SOURCE && j.status==='completed' && j.conclusion===(packageJob?'failure':'success'),'Required original job outcome differs');
    if(packageJob) {
      requireThat(Array.isArray(j.steps),'Missing original package build steps');
      for(const [name,outcome] of [['Build fresh application and installer with locked dependencies','success'],['Inspect fresh installer bytes without installing or launching the application','failure'],['Upload unverified build diagnosis separately from candidates','success']]) {
        const steps=j.steps.filter(s=>s.name===name);
        requireThat(steps.length===1 && steps[0].status==='completed' && steps[0].conclusion===outcome,'Original package build/inspection step outcome differs');
      }
      requireThat(equal(j.steps.filter(s=>s.conclusion==='failure').map(s=>s.name),['Inspect fresh installer bytes without installing or launching the application']) && !j.steps.some(s=>s.conclusion==='cancelled'),'Unexpected original package failure');
    }
  }
  const r=pin.macOSReinspection;
  validateRun(inspectionRun,r.runId,r.commit,r.branch,'success');
  requireThat(inspectionRun.path===r.workflowPath && inspectionJobs.length===1,'Unexpected reinspection workflow/job inventory');
  const j=inspectionJobs[0];
  requireThat(j.id===r.job.id && j.name===r.job.name && j.run_id===r.runId && j.head_sha===r.commit && j.status==='completed' && j.conclusion==='success','Reinspection did not pass');
  validateArtifact(inputArtifact,r.inputArtifact,RUN,SOURCE,pin.sourceBranch);
  const w=pin.windowsReinspection;
  validateRun(windowsRun,w.runId,w.commit,w.branch,'success');
  requireThat(windowsRun.path===w.workflowPath && windowsJobs.length===1,'Unexpected Windows reinspection workflow/job inventory');
  const wj=windowsJobs[0];
  requireThat(wj.id===w.job.id && wj.name===w.job.name && wj.run_id===w.runId && wj.head_sha===w.commit && wj.status==='completed' && wj.conclusion==='success','Windows reinspection did not pass');
  validateArtifact(windowsInputArtifact,w.inputArtifact,RUN,SOURCE,pin.sourceBranch);
  requireThat(artifacts.length===2,'Unexpected candidate artifact inventory');
  for(const expected of pin.artifacts) {
    const matches=artifacts.filter(a=>a.id===expected.id);requireThat(matches.length===1,'Duplicate or missing candidate artifact');
    validateArtifact(matches[0],expected,expected.platform==='Windows'?w.runId:r.runId,expected.platform==='Windows'?w.commit:r.commit,expected.platform==='Windows'?w.branch:r.branch);
  }
}
function validateCheckout(context, io, pin=PIN) {
  const git = (...args) => io.execFileSync('git', args, { encoding: 'utf8' }).trim();
  requireThat(git('rev-parse','HEAD') === context.sha && !git('status','--porcelain=v1','--untracked-files=no'), 'Publisher checkout changed');
  requireThat(git('rev-parse',`${SOURCE}^{tree}`) === TREE, 'Local tested source tree differs');
  requireThat(git('rev-parse',`${pin.macOSReinspection.commit}^{tree}`)===pin.macOSReinspection.tree,'Inspection tooling tree differs');
  const inspectionChanges=git('diff','--name-status','--no-renames',TREE,pin.macOSReinspection.commit).split('\n').sort();
  requireThat(equal(inspectionChanges,INSPECTION_CHANGES),'Inspection commit changed unreviewed product paths');
  const w=pin.windowsReinspection;
  requireThat(git('rev-parse',`${w.commit}^{tree}`)===w.tree,'Windows inspection tooling tree differs');
  requireThat(equal(git('diff','--name-status','--no-renames',TREE,w.commit).split('\n').sort(),WINDOWS_INSPECTION_CHANGES),'Windows inspection changed unreviewed product paths');
  const changes = git('diff','--name-status','--no-renames',TREE,'HEAD').split('\n');
  requireThat(equal(changes.sort(), ALLOWED.map(name => `A\t${name}`).sort()), 'Publisher may only add its exact release-only files');
}
function assetNames(pin) {
  return [...pin.artifacts.map(a => a.installer), 'CANDIDATE-MANIFEST.Windows.json', 'CANDIDATE-MANIFEST.macOS.json', 'EchoLingo-offline-engine-source.zip', 'REINSPECTION-MANIFEST.json', 'REINSPECTION-MANIFEST.Windows.json', 'RELEASE-MANIFEST.json', 'SHA256SUMS.txt'].sort();
}
async function publish({ github, context, core }, io = { fs, execFileSync, sha256 }, pin = PIN) {
  validatePins(pin);
  const { owner, repo } = context.repo;
  requireThat(`${owner}/${repo}` === REPOSITORY && context.payload?.repository?.id === REPOSITORY_ID && context.ref === `refs/heads/${BRANCH}` && context.eventName === 'push' && /^[0-9a-f]{40}$/.test(context.sha), 'Publication is restricted to the dedicated original-repository branch push');
  const ensureScope = async () => {
    validateCheckout(context, io, pin);
    const { data: head } = await github.rest.git.getRef({ owner, repo, ref: `heads/${BRANCH}` });
    requireThat(head.object?.type === 'commit' && head.object.sha === context.sha, 'Publisher branch moved');
    const { data: source } = await github.rest.git.getCommit({ owner, repo, commit_sha: SOURCE });
    requireThat(source.sha === SOURCE && source.tree?.sha === TREE, 'Tested source identity differs');
    const r=pin.macOSReinspection;
    const {data:inspection}=await github.rest.git.getCommit({owner,repo,commit_sha:r.commit});
    requireThat(inspection.sha===r.commit && inspection.tree?.sha===r.tree,'Inspection tooling identity differs');
    const w=pin.windowsReinspection;
    const {data:windowsInspection}=await github.rest.git.getCommit({owner,repo,commit_sha:w.commit});
    requireThat(windowsInspection.sha===w.commit && windowsInspection.tree?.sha===w.tree,'Windows inspection tooling identity differs');
  };
  const absentRelease = async () => {
    try { await github.rest.repos.getReleaseByTag({ owner, repo, tag: '0.2.6' }); }
    catch (error) { if (error.status === 404) return; throw error; }
    throw new Error('Release already exists; never overwrite or retry a partial draft');
  };
  const exactTag = async (allowCreate) => {
    try {
      const { data: tag } = await github.rest.git.getRef({ owner, repo, ref: 'tags/0.2.6' });
      requireThat(tag.object?.type === 'commit' && tag.object.sha === SOURCE, 'Tag is not the exact tested source');
    } catch (error) {
      if (error.status !== 404 || !allowCreate) throw error;
      await github.rest.git.createRef({ owner, repo, ref: 'refs/tags/0.2.6', sha: SOURCE });
      await exactTag(false);
    }
  };
  await ensureScope();
  await absentRelease();
  const loadEvidence = async () => {
    const { data: run } = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: RUN });
    const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, { owner, repo, run_id: RUN, filter: 'all', per_page: 100 });
    const artifacts = [];
    for (const a of pin.artifacts) artifacts.push((await github.rest.actions.getArtifact({ owner, repo, artifact_id: a.id })).data);
    const r=pin.macOSReinspection;
    const {data:inspectionRun}=await github.rest.actions.getWorkflowRun({owner,repo,run_id:r.runId});
    const inspectionJobs=await github.paginate(github.rest.actions.listJobsForWorkflowRun,{owner,repo,run_id:r.runId,filter:'all',per_page:100});
    const {data:inputArtifact}=await github.rest.actions.getArtifact({owner,repo,artifact_id:r.inputArtifact.id});
    const w=pin.windowsReinspection;
    const {data:windowsRun}=await github.rest.actions.getWorkflowRun({owner,repo,run_id:w.runId});
    const windowsJobs=await github.paginate(github.rest.actions.listJobsForWorkflowRun,{owner,repo,run_id:w.runId,filter:'all',per_page:100});
    const {data:windowsInputArtifact}=await github.rest.actions.getArtifact({owner,repo,artifact_id:w.inputArtifact.id});
    validateEvidence(run,jobs,artifacts,inspectionRun,inspectionJobs,inputArtifact,windowsRun,windowsJobs,windowsInputArtifact,pin);
  };
  await loadEvidence();
  io.fs.mkdirSync('candidate-026-inputs');
  for (const a of pin.artifacts) {
    const { data } = await github.rest.actions.downloadArtifact({ owner, repo, artifact_id: a.id, archive_format: 'zip' });
    const bytes = Buffer.from(data);
    requireThat(bytes.length === a.size && io.sha256(bytes) === a.sha256, 'Original artifact ZIP hash or size differs');
    io.fs.writeFileSync(`candidate-026-inputs/${a.name}.zip`, bytes, { flag: 'wx' });
  }
  io.execFileSync('python3', ['scripts/prepare-026-candidate.py','candidate-026-inputs','candidate-026-assets',context.sha], { stdio: 'inherit' });
  const directory = 'candidate-026-assets';
  const names = io.fs.readdirSync(directory).sort();
  requireThat(equal(names, assetNames(pin)), 'Unexpected release asset inventory');
  const manifest = JSON.parse(io.fs.readFileSync(`${directory}/RELEASE-MANIFEST.json`, 'utf8'));
  requireThat(manifest.version === '0.2.6' && manifest.sourceCommit === SOURCE && manifest.sourceTree === TREE && manifest.publisherCommit === context.sha && manifest.validationRun === `https://github.com/${REPOSITORY}/actions/runs/${RUN}` && manifest.rebuiltAfterValidation === false && manifest.installedApplicationAcceptance === false && manifest.interactiveSelectionAcceptance === false && manifest.buildRunConclusion==='failure' && manifest.reinspectionRunConclusion==='success' && manifest.reinspectionCommit===pin.macOSReinspection.commit && manifest.reinspectionRunUrl===`https://github.com/${REPOSITORY}/actions/runs/${pin.macOSReinspection.runId}` && manifest.windowsReinspectionRunConclusion==='success' && manifest.windowsReinspectionCommit===pin.windowsReinspection.commit && manifest.windowsReinspectionRunUrl===`https://github.com/${REPOSITORY}/actions/runs/${pin.windowsReinspection.runId}`, 'Aggregate provenance differs');
  const verified = names.map(name => { const bytes = io.fs.readFileSync(`${directory}/${name}`); return { name, size: bytes.length, digest: `sha256:${io.sha256(bytes)}` }; });
  await ensureScope();
  await absentRelease();
  await exactTag(true);
  const body = io.fs.readFileSync('docs/releases/0.2.6-candidate.md','utf8') + `\n\nSource: \`${SOURCE}\`; tree: \`${TREE}\`; [original build run ${RUN} — failed initial package inspections](https://github.com/${REPOSITORY}/actions/runs/${RUN}). Publisher: \`${context.sha}\`. Original installer bytes, not rebuilt. Separate [successful same-byte macOS inspection](https://github.com/${REPOSITORY}/actions/runs/${pin.macOSReinspection.runId}) at \`${pin.macOSReinspection.commit}\`; separate [successful Windows same-byte inspection](https://github.com/${REPOSITORY}/actions/runs/${pin.windowsReinspection.runId}) at \`${pin.windowsReinspection.commit}\`. The exact existing NSIS bundle-marker identity rule was verified without modifying an executable; the original overall failure is not relabeled as success.\n`;
  const { data: release } = await github.rest.repos.createRelease({ owner, repo, tag_name: '0.2.6', target_commitish: SOURCE, name: '0.2.6 测试版', body, draft: true, prerelease: true, make_latest: 'false' });
  requireThat(Number.isSafeInteger(release.id) && release.id > 0 && release.draft === true && release.prerelease === true && release.tag_name === '0.2.6', 'Unexpected new draft metadata');
  for (const expected of verified) {
    const data = io.fs.readFileSync(`${directory}/${expected.name}`);
    requireThat(data.length === expected.size && `sha256:${io.sha256(data)}` === expected.digest, 'Prepared asset changed; left draft');
    const { data: asset } = await github.rest.repos.uploadReleaseAsset({ owner, repo, release_id: release.id, name: expected.name, data });
    requireThat(asset.name === expected.name && asset.state === 'uploaded' && asset.size === expected.size && asset.digest === expected.digest, 'Upload verification failed; left draft');
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, { owner, repo, release_id: release.id, per_page: 100 });
  requireThat(assets.length === verified.length && equal(assets.map(a => a.name).sort(), names), 'Uploaded inventory differs; left draft');
  for (const expected of verified) {
    const a = assets.find(item => item.name === expected.name);
    requireThat(a.state === 'uploaded' && a.size === expected.size && a.digest === expected.digest, 'Uploaded asset bytes differ; left draft');
  }
  await loadEvidence();
  await ensureScope();
  await exactTag(false);
  const { data: draft } = await github.rest.repos.getRelease({ owner, repo, release_id: release.id });
  requireThat(draft.draft === true && draft.prerelease === true && draft.tag_name === '0.2.6', 'Draft changed during upload');
  const { data: published } = await github.rest.repos.updateRelease({ owner, repo, release_id: release.id, draft: false, prerelease: true, make_latest: 'false' });
  requireThat(published.id === release.id && published.draft === false && published.prerelease === true && published.tag_name === '0.2.6', 'Published metadata differs');
  await core.summary.addLink('0.2.6 testing prerelease', published.html_url).write();
}
module.exports = { publish, validatePins, validateEvidence, validateCheckout, assetNames, ALLOWED, BRANCH, SOURCE, TREE, RUN, PIN, INSPECTION_CHANGES, INPUT_ARTIFACT, WINDOWS_INSPECTION_CHANGES, WINDOWS_INPUT_ARTIFACT, WINDOWS_APPLICATION_IDENTITY };
