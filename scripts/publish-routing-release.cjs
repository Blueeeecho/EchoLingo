'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const VERSION = '0.2.13';
const MODE = 'automatic-direction-targeted-v1';
const PAYLOADS = [`EchoLingo_${VERSION}_windows_x64-setup.exe`, `EchoLingo_${VERSION}_macos_arm64.dmg`, 'EchoLingo-offline-engine-source.zip'].sort();
const NAMES = [...PAYLOADS, 'RELEASE-MANIFEST.json', 'SHA256SUMS.txt'].sort();
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const requireThat = (condition, message) => { if (!condition) throw new Error(message); };
function validateInputs(context, io) {
  requireThat(context.repo.owner === 'Blueeeecho' && context.repo.repo === 'EchoLingo' && context.ref === 'refs/heads/main', 'Publication requires original repository main');
  requireThat(/^[a-f0-9]{40}$/.test(context.sha), 'Invalid source commit');
  const names = io.fs.readdirSync('release-assets').sort();
  requireThat(equal(names, NAMES), 'Unexpected public asset inventory');
  const bytes = new Map(names.map(name => {
    const file = path.join('release-assets', name);
    const stat = io.fs.lstatSync(file);
    requireThat(stat.isFile() && !stat.isSymbolicLink() && stat.size > 0, `Not a nonempty regular asset: ${name}`);
    return [name, io.fs.readFileSync(file)];
  }));
  const manifest = JSON.parse(bytes.get('RELEASE-MANIFEST.json').toString('utf8'));
  const runUrl = `https://github.com/Blueeeecho/EchoLingo/actions/runs/${context.runId}`;
  requireThat(manifest.version === VERSION && manifest.commit === context.sha && manifest.validationRun === runUrl && manifest.validationMode === MODE, 'Manifest provenance mismatch');
  requireThat(/^[a-f0-9]{40}$/.test(manifest.reviewedSourceCommit), 'Unresolved reviewed source pin');
  const pin = io.execFileSync('python3', ['-c', 'import runpy, sys; sys.path.insert(0, "scripts"); print(runpy.run_path("scripts/prepare-routing-release.py")["REVIEWED_SOURCE"])'], {encoding:'utf8'}).trim();
  requireThat(pin === manifest.reviewedSourceCommit, 'Reviewed source pin mismatch');
  io.execFileSync('git', ['merge-base', '--is-ancestor', pin, context.sha]);
  requireThat(manifest.scope?.fullRegression === false && manifest.scope?.installerExecuted === false && manifest.scope?.visualAcceptance === false, 'Targeted evidence scope must not claim full or installed acceptance');
  requireThat(Array.isArray(manifest.files) && equal(manifest.files.map(f => f.name).sort(), PAYLOADS), 'Manifest payload inventory mismatch');
  for (const entry of manifest.files) {
    const data = bytes.get(entry.name);
    requireThat(Number.isSafeInteger(entry.size) && entry.size === data.length && /^[a-f0-9]{64}$/.test(entry.sha256) && entry.sha256 === hash(data), `Payload hash/size mismatch: ${entry.name}`);
  }
  const expectedSums = names.filter(name => name !== 'SHA256SUMS.txt').map(name => `${hash(bytes.get(name))}  ${name}`).sort();
  const sums = bytes.get('SHA256SUMS.txt').toString('utf8').trimEnd().split('\n').sort();
  requireThat(equal(sums, expectedSums), 'Checksum inventory or hash mismatch');
  const notes = io.fs.readFileSync(`docs/releases/${VERSION}.zh-CN.md`, 'utf8');
  requireThat(notes.trim().length > 0, 'Release notes missing');
  return {manifest, bytes, notes, runUrl};
}
async function publish({github, context, core}, io = {fs, execFileSync}) {
  const {manifest, bytes, notes, runUrl} = validateInputs(context, io);
  const {owner, repo} = context.repo;
  const ensureMain = async () => {
    const {data} = await github.rest.git.getRef({owner, repo, ref:'heads/main'});
    requireThat(data.object.type === 'commit' && data.object.sha === context.sha, 'Main moved; publication stopped');
  };
  const noExistingRelease = async () => {
    try { await github.rest.repos.getReleaseByTag({owner, repo, tag:VERSION}); }
    catch (error) { if (error.status === 404) return; throw error; }
    throw new Error('Release already exists; no overwrite');
  };
  const verifyTag = async () => {
    const {data} = await github.rest.git.getRef({owner, repo, ref:`tags/${VERSION}`});
    requireThat(data.object.type === 'commit' && data.object.sha === context.sha, 'Tag/source mismatch');
  };
  await ensureMain();
  await noExistingRelease();
  try { await verifyTag(); }
  catch(error) {
    if (error.status !== 404) throw error;
    await github.rest.git.createRef({owner, repo, ref:`refs/tags/${VERSION}`, sha:context.sha});
  }
  await ensureMain();
  await noExistingRelease();
  const body = notes + `\n\n源码提交：\`${context.sha}\`\n\n已审查的路由源码：\`${manifest.reviewedSourceCommit}\`\n\n[定向测试、全新构建与静态安装包检查](${runUrl})\n\n本次未重复完整回归、安装后运行验收或视觉验收。\n`;
  const {data: release} = await github.rest.repos.createRelease({owner, repo, tag_name:VERSION, target_commitish:context.sha, name:`${VERSION} 内测版`, body, draft:true, prerelease:true, make_latest:'false'});
  for (const [name, data] of bytes) {
    const {data: asset} = await github.rest.repos.uploadReleaseAsset({owner, repo, release_id:release.id, name, data});
    requireThat(asset.state === 'uploaded' && asset.size === data.length && asset.digest === `sha256:${hash(data)}`, `Upload verification failed: ${name}; release remains draft`);
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, {owner, repo, release_id:release.id, per_page:100});
  requireThat(equal(assets.map(a => a.name).sort(), NAMES), 'Uploaded inventory mismatch; release remains draft');
  for (const asset of assets) {
    const data = bytes.get(asset.name);
    requireThat(asset.state === 'uploaded' && asset.size === data.length && asset.digest === `sha256:${hash(data)}`, 'Uploaded asset changed; release remains draft');
  }
  await verifyTag();
  await ensureMain();
  const {data: result} = await github.rest.repos.updateRelease({owner, repo, release_id:release.id, draft:false, prerelease:true, make_latest:'false'});
  requireThat(result.draft === false && result.prerelease === true && result.tag_name === VERSION, 'Published metadata mismatch');
  await core.summary.addLink(`${VERSION} 内测版`, result.html_url).write();
  return result;
}
module.exports = {publish, validateInputs, VERSION, MODE, NAMES, PAYLOADS};
