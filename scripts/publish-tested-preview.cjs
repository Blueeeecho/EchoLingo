const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const SOURCE = '4ea25907fdaf4477f3aaf92b41973668b507f528';
const TREE = '87825bd8b1bfdb304ca9e21857d5a09769327932';
const BUILD = '8b8cfcf6abee1297f5ef220154a0a28fb18cb63c';
const MERGE = '06b4f9820e20f15fdedf8d86e875505ff95b956d';
const LATER_RUN = 41056149811;
const RUN = 41053405841;
const ARTIFACTS = [
  { id:12976667329, name:'EchoLingo-Windows', size:75445810, digest:'sha256:cb6405255d570fc31dec7a125921518126dbb709960bc4361f24b51622e4a3cd' },
  { id:12975917340, name:'EchoLingo-macOS', size:4916850, digest:'sha256:8e980f9c4ccf37b72cecd551205c1d822962d789391446bb357d876572d8ec47' },
  { id:12976667318, name:'EchoLingo-Windows-offline-evidence', size:18088658, digest:'sha256:8a77e655aa802067c080473f7715a1e075317a79b97dfb87e5862f82687aae20' },
];
const JOBS = [[124054803658,'desktop (macos-latest)'], [124054804159,'desktop (windows-latest)'], [124054803992,'frontend-interactions']];
const sha256 = b => crypto.createHash('sha256').update(b).digest('hex');
function validateEvidence(run, jobs, artifacts) {
  if (run.id !== RUN || run.head_sha !== SOURCE || run.head_branch !== 'integrate/all-reviewed-fixes' || run.event !== 'pull_request' || run.status !== 'completed' || run.conclusion !== 'success' || run.run_attempt !== 1 || run.repository?.full_name !== 'Blueeeecho/EchoLingo') throw new Error('Unexpected source run');
  for (const [id, name] of JOBS) {
    const job = jobs.find(j => j.id === id);
    if (!job || job.name !== name || job.run_id !== RUN || job.head_sha !== SOURCE || job.status !== 'completed' || job.conclusion !== 'success') throw new Error('Required source job did not pass');
  }
  if (artifacts.length !== ARTIFACTS.length) throw new Error('Artifact count mismatch');
  for (const expected of ARTIFACTS) {
    const artifact = artifacts.find(a => a.id === expected.id);
    if (!artifact || artifact.name !== expected.name || artifact.expired !== false || artifact.digest !== expected.digest || artifact.size_in_bytes !== expected.size || artifact.workflow_run?.id !== RUN || artifact.workflow_run?.head_sha !== SOURCE || artifact.workflow_run?.head_repository_id !== 1432139657) throw new Error('Unexpected source artifact');
  }
}
async function publish({ github, context, core }, io = { fs, execFileSync, sha256 }) {
  const { owner, repo } = context.repo;
  if (`${owner}/${repo}` !== 'Blueeeecho/EchoLingo' || context.ref !== 'refs/heads/main') throw new Error('Publication is main-only in the original repository');
  const ensureMain = async () => { const { data } = await github.rest.git.getRef({ owner, repo, ref: 'heads/main' }); if (data.object.sha !== context.sha) throw new Error('Publisher main moved'); };
  await ensureMain();
  try { await github.rest.repos.getReleaseByTag({ owner, repo, tag: '0.2.2' }); throw new Error('Release exists; no overwrite'); } catch(e) { if (e.status !== 404) throw e; }
  const { data: run } = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: RUN });
  const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, { owner, repo, run_id: RUN, per_page: 100 });
  const artifacts = [];
  for (const item of ARTIFACTS) { const { data } = await github.rest.actions.getArtifact({ owner, repo, artifact_id: item.id }); artifacts.push(data); }
  validateEvidence(run, jobs, artifacts);
  for (const sha of [SOURCE, BUILD, MERGE]) {
    const { data } = await github.rest.git.getCommit({ owner, repo, commit_sha: sha });
    if (data.sha !== sha || data.tree?.sha !== TREE) throw new Error('Tested source and merged tree differ');
  }
  const { data: later } = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: LATER_RUN });
  if (later.id !== LATER_RUN || later.head_sha !== MERGE || later.status !== 'completed' || later.conclusion !== 'failure' || later.run_attempt !== 1 || later.repository?.full_name !== 'Blueeeecho/EchoLingo') throw new Error('Later failure disclosure does not match evidence');
  io.fs.mkdirSync('tested-preview-inputs');
  for (const item of ARTIFACTS) {
    const { data: archive } = await github.rest.actions.downloadArtifact({ owner, repo, artifact_id: item.id, archive_format: 'zip' });
    const bytes = Buffer.from(archive);
    if (bytes.length !== item.size || `sha256:${io.sha256(bytes)}` !== item.digest) throw new Error('Downloaded archive digest/size mismatch');
    io.fs.writeFileSync(`tested-preview-inputs/${item.name}.zip`, bytes);
  }
  io.execFileSync('python3', ['scripts/prepare-tested-preview.py', 'tested-preview-inputs', 'tested-preview-assets', context.sha], { stdio: 'inherit' });
  const directory = 'tested-preview-assets';
  const manifest = JSON.parse(io.fs.readFileSync(`${directory}/RELEASE-MANIFEST.json`, 'utf8'));
  if (manifest.version !== '0.2.2' || manifest.commit !== SOURCE || manifest.sourceCommit !== SOURCE || manifest.publisherCommit !== context.sha || manifest.sourceTree !== TREE || manifest.buildCheckoutCommit !== BUILD || manifest.validationRun !== `https://github.com/Blueeeecho/EchoLingo/actions/runs/${RUN}` || manifest.windowsInstalledAcceptanceVerified !== true || manifest.rebuiltAfterValidation !== false || manifest.laterValidation?.runId !== LATER_RUN || manifest.laterValidation?.conclusion !== 'failure') throw new Error('Manifest provenance mismatch');
  const names = io.fs.readdirSync(directory).sort();
  const expected = ['EchoLingo_0.2.2_windows_x64-setup.exe', 'EchoLingo_0.2.2_macos_arm64.dmg', 'EchoLingo-offline-engine-source.zip', 'RELEASE-MANIFEST.json', 'SHA256SUMS.txt'].sort();
  if (JSON.stringify(names) !== JSON.stringify(expected)) throw new Error('Unexpected public asset inventory');
  await ensureMain();
  try { const { data } = await github.rest.git.getRef({ owner, repo, ref: 'tags/0.2.2' }); if (data.object.type !== 'commit' || data.object.sha !== SOURCE) throw new Error('Existing tag/source mismatch'); }
  catch(e) { if (e.status !== 404) throw e; await github.rest.git.createRef({ owner, repo, ref: 'refs/tags/0.2.2', sha: SOURCE }); }
  const body = io.fs.readFileSync('docs/releases/0.2.2.zh-CN.md', 'utf8') + `\n\n## 验收记录与实测限制\n\n本次直接发布完整全绿 CI [${RUN}](https://github.com/Blueeeecho/EchoLingo/actions/runs/${RUN}) 的原始 Windows/macOS 0.2.2 安装包（未重编译、未改名旧版本）。源码/tag：\`${SOURCE}\`；发布工具提交：\`${context.sha}\`。\n\n随后同一源码树的发布验证 [${LATER_RUN}](https://github.com/Blueeeecho/EchoLingo/actions/runs/${LATER_RUN}) 并非全绿：Windows 18 项中 17 项通过，rapid A→B 并发用例发生 MOCK_CONTROLLED_REPLY_NOT_RELEASED；B 已返回且原文正确，但历史未确认写入。此问题尚未定位，不能宣称已修复或最终发布验证全绿。用户已授权内测自测；保留全部原始门禁和失败记录，不覆盖旧版本。Mac 物理外沿/首帧及偶发 HTML 剪贴板恢复仍需实机测试。\n\n请核对 RELEASE-MANIFEST.json 的 source/publisher、原始产物摘要、成功与后续失败记录及 SHA256SUMS.txt。`;
  const { data: release } = await github.rest.repos.createRelease({ owner, repo, tag_name: '0.2.2', target_commitish: SOURCE, name: '0.2.2 内测版', body, draft: true, prerelease: true, make_latest: 'false' });
  for (const name of names) {
    const data = io.fs.readFileSync(`${directory}/${name}`);
    const { data: asset } = await github.rest.repos.uploadReleaseAsset({ owner, repo, release_id: release.id, name, data });
    if (asset.state !== 'uploaded' || asset.size !== data.length || asset.digest !== `sha256:${io.sha256(data)}`) throw new Error(`Upload verification failed: ${name}; left draft`);
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, { owner, repo, release_id: release.id, per_page: 100 });
  if (JSON.stringify(assets.map(a => a.name).sort()) !== JSON.stringify(names)) throw new Error('Public inventory mismatch');
  const { data: tag } = await github.rest.git.getRef({ owner, repo, ref: 'tags/0.2.2' });
  if (tag.object.type !== 'commit' || tag.object.sha !== SOURCE) throw new Error('Tag changed during upload');
  await ensureMain();
  const { data: published } = await github.rest.repos.updateRelease({ owner, repo, release_id: release.id, draft: false, prerelease: true, make_latest: 'false' });
  if (published.draft || !published.prerelease || published.tag_name !== '0.2.2') throw new Error('Publication metadata mismatch');
  await core.summary.addLink('0.2.2 内测版', published.html_url).write();
}
module.exports = { publish, validateEvidence, SOURCE, TREE, BUILD, MERGE, RUN, LATER_RUN, ARTIFACTS, JOBS };
