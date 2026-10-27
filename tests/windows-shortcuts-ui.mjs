// Actual packaged WebView + backend + Windows RegisterHotKey/SendInput. CDP is
// enabled only in this disposable test process, never in the shipped app.
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { chromium } from '@playwright/test';
const [appArgument, isolation] = process.argv.slice(2);
assert.equal(process.platform, 'win32');
assert.equal(isolation, '--isolated-test-session');
const executable = path.resolve(appArgument);
const ps = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
const shell = (code) => execFileSync(ps, ['-NoProfile', '-Command', code], { encoding: 'utf8', timeout: 15000 }).trim();
const roaming = shell("[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)");
const local = shell("[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)");
const identifier = 'io.github.blueeeecho.echolingo';
const roots = [path.join(roaming, identifier), path.join(local, identifier)];
const token = `shortcut-ui-${process.pid}-${Date.now()}`;
const owned = [];
let app, browser, holder;
const cases = [];
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(condition, description, milliseconds = 15000) {
  const end = Date.now() + milliseconds;
  do { if (await condition()) return; await sleep(50); } while (Date.now() < end);
  throw new Error(description);
}
async function nativeKey(modifiers, key) {
  await new Promise((resolve, reject) => {
    const child = spawn(ps, ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', 'tests/windows-shortcut-input.ps1', '-Mode', 'send', '-ApplicationProcessId', String(app.pid), '-Modifiers', String(modifiers), '-Key', String(key)], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let errors = ''; child.stderr.on('data', (data) => { errors += data; });
    child.once('error', reject); child.once('exit', (code) => code === 0 ? resolve() : reject(new Error(`Native generated key failed: ${errors}`)));
  });
}
function actualAvailability(modifiers, key) {
  return execFileSync(ps, ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', 'tests/windows-shortcut-input.ps1', '-Mode', 'probe', '-Modifiers', String(modifiers), '-Key', String(key)], { windowsHide: true, encoding: 'utf8', timeout: 15000 }).trim();
}
try {
  // Refuse existing settings or processes; never repoint/overwrite daily data.
  const processName = path.basename(executable, '.exe').replaceAll("'", "''");
  assert.equal(shell(`@(Get-Process -Name '${processName}' -ErrorAction SilentlyContinue).Count`), '0');
  for (const root of roots) {
    await fs.mkdir(root); owned.push(root);
    await fs.writeFile(path.join(root, '.shortcut-ui-owned'), token);
  }
  const settingsPath = path.join(roots[0], 'settings.json');
  await fs.writeFile(settingsPath, JSON.stringify({ shortcutDefaultsVersion: 1, shortcuts: { selection: 'Alt+D', silentOcr: 'Alt+S', capture: '', ocr: '', input: '' }, providers: [], ocrProviders: [], sourceLanguage: 'auto', targetLanguage: 'auto', languageDirectionVersion: 1 }));
  const socket = net.createServer(); await new Promise((resolve) => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port; await new Promise((resolve) => socket.close(resolve));
  app = spawn(executable, ['--configure-shortcuts'], { stdio: 'ignore', env: { ...process.env, WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1`, WEBVIEW2_USER_DATA_FOLDER: path.join(roots[1], 'webview-shortcut-fixture') } });
  await until(async () => { try { browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { timeout: 1000 }); return true; } catch { return false; } }, 'Actual packaged WebView CDP was not ready.', 30000);
  let page;
  await until(async () => { page = browser.contexts().flatMap((context) => context.pages()).find((candidate) => !candidate.url().startsWith('devtools:')); return page && await page.locator('#shortcut-selection').isVisible().catch(() => false); }, 'Explicit configure route did not show shortcut settings.', 25000);
  assert.match(await page.locator('#shortcut-selection').inputValue(), /Alt\+D/);
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').filter({ hasText: '请按快捷键' }).waitFor();
  await nativeKey(1, 0x44); // OS-registered Alt+D, not a fake DOM event.
  await until(async () => (await page.locator('#shortcut-feedback').textContent()).includes('已录入'), 'Current registered Alt+D could not be recorded.');
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Alt+D');
  assert.equal(await page.locator('#view-settings').isVisible(), true);
  cases.push('Actual OS-registered Alt+D records through the lease bridge without executing selection');
  await page.locator('#shortcut-selection').fill('Ctrl+Alt+Shift+F9');
  await page.locator('#shortcut-silentOcr').fill('Ctrl+Alt+Shift+F10');
  await page.locator('#save-shortcuts').click();
  await until(async () => JSON.parse(await fs.readFile(settingsPath, 'utf8')).shortcuts.selection === 'Ctrl+Alt+Shift+F9', 'Live shortcut save did not persist.');
  const previous = await fs.readFile(settingsPath, 'utf8');
  assert.equal(actualAvailability(7, 0x78), 'CONFLICT');
  assert.equal(actualAvailability(7, 0x79), 'CONFLICT');
  assert.equal(actualAvailability(1, 0x44), 'AVAILABLE');
  assert.equal(actualAvailability(1, 0x53), 'AVAILABLE');
  cases.push('Independent process confirms both new native registrations and both old combinations released');
  holder = spawn(ps, ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', 'tests/windows-shortcut-input.ps1', '-Mode', 'hold', '-Modifiers', '7', '-Key', '119'], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] }); // F8
  let ready = '', holderErrors = '';
  holder.stdout.on('data', (data) => { ready += data; }); holder.stderr.on('data', (data) => { holderErrors += data; });
  await until(() => { if (holder.exitCode !== null) throw new Error(holderErrors); return ready.includes('READY'); }, 'Fixture did not own the conflicting combination.');
  await page.locator('#shortcut-selection').fill('Ctrl+Alt+Shift+F8');
  await page.locator('#save-shortcuts').click();
  await until(async () => (await page.locator('#shortcut-feedback').textContent()).includes('未完成保存'), 'Occupied shortcut save did not report a conflict.');
  assert.equal(await fs.readFile(settingsPath, 'utf8'), previous);
  assert.equal(actualAvailability(7, 0x78), 'CONFLICT');
  assert.equal(actualAvailability(7, 0x79), 'CONFLICT');
  cases.push('Real occupied-key save rejects the change and leaves durable prior bindings intact');
  // Native ownership is independently checked above; now recheck recording.
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').filter({ hasText: '请按快捷键' }).waitFor();
  await nativeKey(7, 0x78); // F9 remains registered after failed save.
  await until(async () => (await page.locator('#shortcut-feedback').textContent()).includes('已录入'), 'Prior registration was lost after failed conflict save.');
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Alt+Shift+F9');
  cases.push('Prior live binding remains registered after conflict rollback');
  console.log(JSON.stringify({ ok: true, cases, actualPackagedWebView: true, actualWindowsSendInput: true, fakeIpcUsed: false, externalTranslation: false, scope: 'Disposable Server desktop and generated keys only; physical Windows11/IME remains unverified.' }));
} finally {
  if (holder && holder.exitCode === null) { holder.stdin.end('\n'); await until(() => holder.exitCode !== null, 'Conflict owner did not release.').catch(() => holder.kill()); }
  await browser?.close().catch(() => {});
  if (app && app.exitCode === null) { execFileSync('taskkill.exe', ['/PID', String(app.pid), '/T', '/F'], { stdio: 'ignore' }); await until(() => app.exitCode !== null, 'Own app did not stop.'); }
  for (const root of owned.reverse()) {
    assert.equal(await fs.readFile(path.join(root, '.shortcut-ui-owned'), 'utf8'), token);
    await fs.rm(root, { recursive: true, force: true });
  }
}
