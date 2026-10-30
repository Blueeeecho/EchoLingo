const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const SOURCE = '67672e98379408afa933cd2f62c3f006f3bec838';
const RUN = 41024566310;
const ARTIFACT = 12963525648;
const DIGEST = 'sha256:672b8f43959e5051bdbe4437b5b6bd63b13868202ed401763975cf673e5552bd';
const sha256 = b => crypto.createHash('sha256').update(b).digest('hex');
function validateEvidence(run, jobs, artifact) {
  if (run.id !== RUN || run.head_sha !== SOURCE || run.head_branch !== 'main' || run.event !== 'push' || run.status !== 'completed' || run.conclusion !== 'failure' || run.run_attempt !== 1 || run.repository?.full_name !== 'Blueeeecho/EchoLingo') throw new Error('Unexpected source run');
  for (const [id, name] of [[123959559790, 'verify / desktop (macos-latest)'], [123959559755, 'verify / frontend-interactions']]) {
    const job = jobs.find(j => j.id === id);
    if (!job || job.name !== name || job.run_id !== RUN || job.head_sha !== SOURCE || job.status !== 'completed' || job.conclusion !== 'success') throw new Error('Required source job did not pass');
  }
  if (artifact.id !== ARTIFACT || artifact.name !== 'EchoLingo-macOS' || artifact.expired !== false || artifact.digest !== DIGEST || artifact.size_in_bytes !== 4891806 || artifact.workflow_run?.id !== RUN || artifact.workflow_run?.head_sha !== SOURCE || artifact.workflow_run?.head_repository_id !== 1432139657) throw new Error('Unexpected source artifact');
}
async function publish({ github, context, core }, io = { fs, execFileSync, sha256 }) {
  const { owner, repo } = context.repo;
  if (`${owner}/${repo}` !== 'Blueeeecho/EchoLingo' || context.ref !== 'refs/heads/main') throw new Error('Publication is main-only in the original repository');
  const ensureMain = async () => { const { data } = await github.rest.git.getRef({ owner, repo, ref: 'heads/main' }); if (data.object.sha !== context.sha) throw new Error('Publisher main moved'); };
  await ensureMain();
  try { await github.rest.repos.getReleaseByTag({ owner, repo, tag: '0.2.1' }); throw new Error('Release exists; no overwrite'); } catch(e) { if (e.status !== 404) throw e; }
  const { data: run } = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: RUN });
  const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, { owner, repo, run_id: RUN, per_page: 100 });
  const { data: artifact } = await github.rest.actions.getArtifact({ owner, repo, artifact_id: ARTIFACT });
  validateEvidence(run, jobs, artifact);
  const { data: archive } = await github.rest.actions.downloadArtifact({ owner, repo, artifact_id: ARTIFACT, archive_format: 'zip' });
  const bytes = Buffer.from(archive);
  if (`sha256:${io.sha256(bytes)}` !== DIGEST) throw new Error('Downloaded archive digest mismatch');
  io.fs.writeFileSync('tested-macos.zip', bytes);
  io.execFileSync('python3', ['scripts/prepare-macos-first-release.py', 'tested-macos.zip', 'macos-release-assets', context.sha], { stdio: 'inherit' });
  const directory = 'macos-release-assets';
  const manifest = JSON.parse(io.fs.readFileSync(`${directory}/RELEASE-MANIFEST.json`, 'utf8'));
  if (manifest.sourceCommit !== SOURCE || manifest.publisherCommit !== context.sha || manifest.releaseScope !== 'macos-only' || manifest.windows.published !== false) throw new Error('Manifest scope mismatch');
  const names = io.fs.readdirSync(directory).sort();
  const expected = ['EchoLingo_0.2.1_macos_arm64.dmg', 'EchoLingo_0.2.1_source.zip', 'RELEASE-MANIFEST.json', 'SHA256SUMS.txt'].sort();
  if (JSON.stringify(names) !== JSON.stringify(expected)) throw new Error('Unexpected public asset inventory');
  await ensureMain();
  try { const { data } = await github.rest.git.getRef({ owner, repo, ref: 'tags/0.2.1' }); if (data.object.type !== 'commit' || data.object.sha !== SOURCE) throw new Error('Existing tag/source mismatch'); }
  catch(e) { if (e.status !== 404) throw e; await github.rest.git.createRef({ owner, repo, ref: 'refs/tags/0.2.1', sha: SOURCE }); }
  const body = `# 0.2.1 内测版（macOS 优先发布）\n\n本次仅发布 Apple 芯片 Mac 安装包。Windows 0.2.1 尚未通过全部缩放验收，**未发布**；Windows 请继续使用 [0.2.0](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.2.0)。\n\n包含选区兼容性、浮窗显示/拖动、翻译诊断与段距改进、仅两个可修改的默认快捷键，以及独立免费翻译/OCR 服务列表。macOS 12+；Apple 系统翻译需要 macOS 26+。使用 ad hoc 签名、未公证。真实微信/Codex 与多屏环境仍需用户复测。\n\n直接复用已测试的 Mac DMG，没有重新编译。Mac 与前端验收成功；整体工作流因 Windows 失败，不宣称 Windows 通过。源码提交：\`${SOURCE}\`。发布工作流提交：\`${context.sha}\`。\n\n[原始构建和验收记录](https://github.com/Blueeeecho/EchoLingo/actions/runs/${RUN}) · [Mac 安装与授权说明](https://github.com/Blueeeecho/EchoLingo/blob/0.2.1/docs/macos-install.zh-CN.md)\n\n请核对 SHA256SUMS.txt 和 RELEASE-MANIFEST.json；source.zip 对应上述已测源码。`;
  const { data: release } = await github.rest.repos.createRelease({ owner, repo, tag_name: '0.2.1', target_commitish: SOURCE, name: '0.2.1 内测版（macOS）', body, draft: true, prerelease: true, make_latest: 'false' });
  for (const name of names) {
    const data = io.fs.readFileSync(`${directory}/${name}`);
    const { data: asset } = await github.rest.repos.uploadReleaseAsset({ owner, repo, release_id: release.id, name, data });
    if (asset.state !== 'uploaded' || asset.size !== data.length || asset.digest !== `sha256:${io.sha256(data)}`) throw new Error(`Upload verification failed: ${name}; left draft`);
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, { owner, repo, release_id: release.id, per_page: 100 });
  if (JSON.stringify(assets.map(a => a.name).sort()) !== JSON.stringify(names)) throw new Error('Public inventory mismatch');
  const { data: tag } = await github.rest.git.getRef({ owner, repo, ref: 'tags/0.2.1' });
  if (tag.object.type !== 'commit' || tag.object.sha !== SOURCE) throw new Error('Tag changed during upload');
  await ensureMain();
  const { data: published } = await github.rest.repos.updateRelease({ owner, repo, release_id: release.id, draft: false, prerelease: true, make_latest: 'false' });
  if (published.draft || !published.prerelease || published.tag_name !== '0.2.1') throw new Error('Publication metadata mismatch');
  await core.summary.addLink('macOS 0.2.1 内测版', published.html_url).write();
}
module.exports = { publish, validateEvidence, SOURCE, RUN, ARTIFACT, DIGEST };
