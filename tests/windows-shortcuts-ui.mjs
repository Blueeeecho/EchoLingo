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
const powerShellOperations = [];
function shell(operation, code) {
  const started = Date.now();
  try {
    const output = execFileSync(ps, ['-NoProfile', '-Command', code], { encoding: 'utf8', timeout: 15000, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    powerShellOperations.push({ operation, elapsedMilliseconds: Date.now() - started, status: 'completed' });
    return output.trim();
  } catch (error) {
    const timedOut = error.code === 'ETIMEDOUT';
    const record = { operation, elapsedMilliseconds: Date.now() - started, status: timedOut ? 'timed-out' : 'failed', exitCode: Number.isInteger(error.status) ? error.status : null, signal: error.signal ?? null, stdoutCharacters: String(error.stdout ?? '').length, stderrCharacters: String(error.stderr ?? '').length };
    powerShellOperations.push(record);
    // Do not let execFileSync's default error serialize the PowerShell source.
    throw new Error(`PowerShell operation ${operation} ${record.status} (budgetMilliseconds=15000, exitCode=${record.exitCode}, signal=${record.signal}).`);
  }
}
const roaming = shell('known-folder-roaming', "[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)");
const local = shell('known-folder-local', "[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)");
const identifier = 'io.github.blueeeecho.echolingo';
const roots = [path.join(roaming, identifier), path.join(local, identifier)];
const token = `shortcut-ui-${process.pid}-${Date.now()}`;
const owned = [];
let app, browser, holder, port, page, appSpawnError;
let stage = 'owned-fixture-setup', lastCdpError;
const started = Date.now(), stages = [];
const appOutput = { stdout: '', stderr: '' }, cleanupErrors = [];
let failure, diagnostics, actualApplicationToken, nativeKeySends = 0;
const bounded = (value, limit = 8192) => String(value ?? '').slice(-limit);
function enter(value) { stage = value; stages.push({ stage, elapsedMilliseconds: Date.now() - started }); }
function requireAppRunning() {
  if (appSpawnError) throw appSpawnError;
  if (app && (app.exitCode !== null || app.signalCode !== null)) throw new Error(`Actual app exited during ${stage}: exit=${app.exitCode}, signal=${app.signalCode}`);
}
// Query only this fixture's actual app token. Never serialize a SID, process
// command line, environment or user content. Comparison stays inside Win32.
function applicationToken(pid) {
  assert.ok(Number.isSafeInteger(pid) && pid > 0);
  return JSON.parse(shell('actual-application-token', `Add-Type -TypeDefinition @'
using System;using System.Diagnostics;using System.Runtime.InteropServices;using System.Security.Principal;
public static class EchoLingoUiToken {
[DllImport("advapi32.dll",SetLastError=true)]static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
[DllImport("advapi32.dll",SetLastError=true)]static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,uint size,out uint length);
[DllImport("advapi32.dll")]static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
[DllImport("advapi32.dll")]static extern IntPtr GetSidSubAuthority(IntPtr sid,uint index);
[DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
static IntPtr Read(IntPtr token,int kind){uint size;GetTokenInformation(token,kind,IntPtr.Zero,0,out size);if(size==0||size>65536)throw new Exception("TOKEN_SIZE");IntPtr p=Marshal.AllocHGlobal((int)size);if(!GetTokenInformation(token,kind,p,size,out size)){Marshal.FreeHGlobal(p);throw new Exception("TOKEN_READ");}return p;}
static int Number(IntPtr token,int kind){IntPtr p=Read(token,kind);try{return Marshal.ReadInt32(p);}finally{Marshal.FreeHGlobal(p);}}
public static object Query(int pid){using(Process process=Process.GetProcessById(pid))using(WindowsIdentity own=WindowsIdentity.GetCurrent()){IntPtr token;if(!OpenProcessToken(process.Handle,8,out token))throw new Exception("TOKEN_OPEN");try{IntPtr p=Read(token,25);int integrity;try{IntPtr sid=Marshal.ReadIntPtr(p);byte n=Marshal.ReadByte(GetSidSubAuthorityCount(sid));if(n==0)throw new Exception("TOKEN_IL");integrity=Marshal.ReadInt32(GetSidSubAuthority(sid,(uint)(n-1)));}finally{Marshal.FreeHGlobal(p);}p=Read(token,1);bool same;try{same=own.User.Equals(new SecurityIdentifier(Marshal.ReadIntPtr(p)));}finally{Marshal.FreeHGlobal(p);}return new {integrityRid=integrity,uiAccess=Number(token,26),elevated=Number(token,20),elevationType=Number(token,18),sessionId=Number(token,12),sameSession=Number(token,12)==Process.GetCurrentProcess().SessionId,sameUser=same};}finally{CloseHandle(token);}}}
}
'@
[EchoLingoUiToken]::Query(${pid}) | ConvertTo-Json -Compress`));
}
const cases = [];
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(condition, description, milliseconds = 15000) {
  const end = Date.now() + milliseconds;
  do { if (await condition()) return; await sleep(50); } while (Date.now() < end);
  throw new Error(`${description} (stage=${stage}, budgetMilliseconds=${milliseconds})`);
}
async function nativeKey(modifiers, key) {
  await new Promise((resolve, reject) => {
    const child = spawn(ps, ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', 'tests/windows-shortcut-input.ps1', '-Mode', 'send', '-ApplicationProcessId', String(app.pid), '-Modifiers', String(modifiers), '-Key', String(key)], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let errors = ''; child.stderr.on('data', (data) => { errors = bounded(errors + data, 4000); });
    const timer = setTimeout(() => { child.kill(); reject(new Error(`Native generated key exceeded 15000ms: ${errors}`)); }, 15000);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
    child.once('exit', (code) => { clearTimeout(timer); code === 0 ? resolve() : reject(new Error(`Native generated key failed: ${errors}`)); });
  });
  nativeKeySends++;
}
function actualAvailability(modifiers, key) {
  return execFileSync(ps, ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', 'tests/windows-shortcut-input.ps1', '-Mode', 'probe', '-Modifiers', String(modifiers), '-Key', String(key)], { windowsHide: true, encoding: 'utf8', timeout: 15000 }).trim();
}
try {
  // Refuse existing settings or processes; never repoint/overwrite daily data.
  const processName = path.basename(executable, '.exe').replaceAll("'", "''");
  // The recorded medium-token failure was Get-Process cmdlet execution before
  // app launch. Keep the same name guard without depending on cmdlet discovery.
  assert.equal(shell('existing-process-name-guard', `$ErrorActionPreference='Stop'; $ownedNameProcesses = @([System.Diagnostics.Process]::GetProcessesByName('${processName}')); try { [Console]::Out.WriteLine($ownedNameProcesses.Length) } finally { foreach ($ownedNameProcess in $ownedNameProcesses) { $ownedNameProcess.Dispose() } }`), '0');
  for (const root of roots) {
    await fs.mkdir(root); owned.push(root);
    await fs.writeFile(path.join(root, '.shortcut-ui-owned'), token);
  }
  const settingsPath = path.join(roots[0], 'settings.json');
  await fs.writeFile(settingsPath, JSON.stringify({ shortcutDefaultsVersion: 1, shortcuts: { selection: 'Alt+D', silentOcr: 'Alt+S', capture: '', ocr: '', input: '' }, providers: [], ocrProviders: [], sourceLanguage: 'auto', targetLanguage: 'auto', languageDirectionVersion: 1 }));
  const socket = net.createServer(); await new Promise((resolve) => socket.listen(0, '127.0.0.1', resolve));
  port = socket.address().port; await new Promise((resolve) => socket.close(resolve));
  app = spawn(executable, ['--configure-shortcuts'], { stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1`, WEBVIEW2_USER_DATA_FOLDER: path.join(roots[1], 'webview-shortcut-fixture') } });
  app.once('error', (error) => { appSpawnError = error; });
  for (const channel of ['stdout', 'stderr']) app[channel].on('data', (data) => { appOutput[channel] = bounded(appOutput[channel] + data); });
  actualApplicationToken = applicationToken(app.pid);
  if (process.env.ECHOLINGO_TEST_EXPECT_MEDIUM === '1') {
    assert.equal(actualApplicationToken.integrityRid, 8192); assert.equal(actualApplicationToken.uiAccess, 0); assert.equal(actualApplicationToken.sameUser, true); assert.equal(actualApplicationToken.sameSession, true);
  }
  enter('actual-packaged-webview-cdp-readiness');
  await until(async () => {
    requireAppRunning();
    try { browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { timeout: 1000 }); return true; }
    catch (error) { lastCdpError = bounded(error.stack ?? error, 6000); return false; }
  }, 'Actual packaged WebView CDP was not ready.', 30000);
  enter('explicit-shortcut-settings-route');
  await until(async () => { requireAppRunning(); page = browser.contexts().flatMap((context) => context.pages()).find((candidate) => !candidate.url().startsWith('devtools:')); return page && await page.locator('#shortcut-selection').isVisible().catch(() => false); }, 'Explicit configure route did not show shortcut settings.', 25000);
  assert.match(await page.locator('#shortcut-selection').inputValue(), /Alt\+D/);
  enter('record-current-registered-key');
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').filter({ hasText: '请按快捷键' }).waitFor();
  await nativeKey(1, 0x44); // Native priority Alt+D, not a fake DOM event.
  await until(async () => (await page.locator('#shortcut-feedback').textContent()).includes('快捷键已保存并立即生效'), 'Current registered Alt+D could not be recorded.');
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Alt+D');
  assert.equal(await page.locator('#view-settings').isVisible(), true);
  cases.push('Actual priority Alt+D records and autosaves through the lease bridge without executing selection');
  enter('record-new-key-and-autosave-without-save-click');
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').filter({ hasText: '请按快捷键' }).waitFor();
  await nativeKey(7, 0x78);
  await until(async () => JSON.parse(await fs.readFile(settingsPath, 'utf8')).shortcuts.selection === 'Ctrl+Alt+Shift+F9', 'Recorded new key did not autosave without a save-button click.');
  await until(async () => (await page.locator('#shortcut-feedback').textContent()).includes('快捷键已保存并立即生效'), 'Recorded key did not finish automatic registration.');
  assert.equal(actualAvailability(7, 0x78), 'CONFLICT');
  cases.push('A new native chord records, persists and registers without a second save action');
  enter('save-and-independently-probe-new-bindings');
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
  enter('real-occupied-combination-rollback');
  holder = spawn(ps, ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', 'tests/windows-shortcut-input.ps1', '-Mode', 'hold', '-Modifiers', '7', '-Key', '119'], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] }); // F8
  let ready = '', holderErrors = '', holderSpawnError;
  holder.once('error', (error) => { holderSpawnError = error; });
  holder.stdout.on('data', (data) => { ready = bounded(ready + data, 2000); }); holder.stderr.on('data', (data) => { holderErrors = bounded(holderErrors + data, 4000); });
  await until(() => { if (holderSpawnError) throw holderSpawnError; if (holder.exitCode !== null) throw new Error(holderErrors); return ready.includes('READY'); }, 'Fixture did not own the conflicting combination.');
  await page.locator('#shortcut-selection').fill('Ctrl+Alt+Shift+F8');
  await page.locator('#save-shortcuts').click();
  await until(async () => (await page.locator('#shortcut-feedback').textContent()).includes('未完成保存'), 'Occupied shortcut save did not report a conflict.');
  assert.equal(await fs.readFile(settingsPath, 'utf8'), previous);
  assert.equal(actualAvailability(7, 0x78), 'CONFLICT');
  assert.equal(actualAvailability(7, 0x79), 'CONFLICT');
  cases.push('Real occupied-key save rejects the change and leaves durable prior bindings intact');
  enter('record-prior-binding-after-conflict');
  // Native ownership is independently checked above; now recheck recording.
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').filter({ hasText: '请按快捷键' }).waitFor();
  await nativeKey(7, 0x78); // F9 remains registered after failed save.
  await until(async () => (await page.locator('#shortcut-feedback').textContent()).includes('快捷键已保存并立即生效'), 'Prior registration was lost after failed conflict save.');
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Alt+Shift+F9');
  cases.push('Prior live binding remains registered after conflict rollback');
  enter('completed');
} catch (error) {
  failure = error;
  // All diagnostics are bounded and restricted to this fixture's process,
  // loopback debugging endpoint and freshly generated WebView. Never dump DOM,
  // settings, screenshots, process command lines or another browser's state.
  diagnostics = {
    stage, elapsedMilliseconds: Date.now() - started,
    app: app ? { pid: app.pid, exitCode: app.exitCode, signalCode: app.signalCode, spawnError: bounded(appSpawnError?.stack, 4000) } : null,
    lastCdpError, appOutput, actualApplicationToken, powerShellOperations,
  };
  if (Number.isInteger(port)) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/version`, { signal: AbortSignal.timeout(1500) });
      diagnostics.cdpEndpoint = { httpStatus: response.status, contentType: response.headers.get('content-type') };
      // Version metadata alone: do not serialize websocket URLs or page content.
      const declared = Number(response.headers.get('content-length'));
      if (response.ok && declared > 0 && declared <= 16384) {
        const metadata = await response.json();
        diagnostics.cdpEndpoint.browserVersion = bounded(metadata.Browser, 160);
        diagnostics.cdpEndpoint.protocolVersion = bounded(metadata['Protocol-Version'], 80);
      }
    } catch (probeError) { diagnostics.cdpEndpoint = { error: bounded(probeError.message, 1000) }; }
  }
  if (app?.pid) {
    try {
      const code = `$children = @(Get-CimInstance Win32_Process -Filter 'ParentProcessId=${app.pid}' | Select-Object -First 16 ProcessId,ParentProcessId,Name); ConvertTo-Json -InputObject $children -Compress`;
      diagnostics.directChildProcesses = JSON.parse(shell('failure-child-process-metadata', code));
      for (const child of diagnostics.directChildProcesses) {
        if (child.Name?.toLowerCase() !== 'msedgewebview2.exe') continue;
        try { child.fileVersion = bounded(shell('failure-webview-version', `(Get-Process -Id ${Number(child.ProcessId)} -ErrorAction Stop).MainModule.FileVersionInfo.FileVersion`), 80); }
        catch (error) { child.versionReadError = bounded(error.message, 300); }
      }
    } catch (probeError) { diagnostics.processMetadataError = bounded(probeError.message, 1000); }
  }
  if (browser) {
    try {
      diagnostics.pages = [];
      for (const candidate of browser.contexts().flatMap((context) => context.pages()).slice(0, 8)) {
        const url = new URL(candidate.url());
        const visible = {};
        for (const selector of ['#view-settings', '#view-translate', '#shortcut-selection', '#shortcut-feedback', '#save-shortcuts']) {
          visible[selector] = await candidate.locator(selector).isVisible().catch(() => false);
        }
        diagnostics.pages.push({ protocol: url.protocol, host: url.host, pathname: url.pathname, visible });
      }
    } catch (probeError) { diagnostics.pageMetadataError = bounded(probeError.message, 1000); }
  }
} finally {
  if (holder && holder.exitCode === null) {
    try { holder.stdin.end('\n'); await until(() => holder.exitCode !== null, 'Conflict owner did not release.'); }
    catch (error) { holder.kill(); cleanupErrors.push(bounded(error.message, 1000)); }
  }
  try { await Promise.race([browser?.close(), sleep(3000)]); } catch (error) { cleanupErrors.push(bounded(error.message, 1000)); }
  if (app && app.exitCode === null && app.pid) {
    try { execFileSync('taskkill.exe', ['/PID', String(app.pid), '/T', '/F'], { stdio: 'ignore', timeout: 10000 }); await until(() => app.exitCode !== null, 'Own app did not stop.'); }
    catch (error) { cleanupErrors.push(bounded(error.message, 1000)); }
  }
  for (const root of owned.reverse()) {
    try {
      assert.equal(await fs.readFile(path.join(root, '.shortcut-ui-owned'), 'utf8'), token);
      await fs.rm(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
    } catch (error) { cleanupErrors.push(bounded(error.message, 1000)); }
  }
}
const report = {
  ok: !failure && cleanupErrors.length === 0, stage, stages, elapsedMilliseconds: Date.now() - started, cases,
  actualApplicationToken, powerShellOperations, webViewBrowserVersion: browser ? bounded(browser.version(), 120) : undefined, actualPackagedWebView: Boolean(browser), actualWindowsSendInput: nativeKeySends > 0, nativeKeySends, fakeIpcUsed: false, externalTranslation: false,
  scope: 'Disposable Server desktop and generated keys only; physical Windows11/IME remains unverified.',
};
if (failure) { report.error = bounded(failure.message, 4000); report.stack = bounded(failure.stack, 12000); report.diagnostics = diagnostics; }
if (cleanupErrors.length) report.cleanupErrors = cleanupErrors;
console.log(JSON.stringify(report));
if (!report.ok) process.exitCode = 1;
