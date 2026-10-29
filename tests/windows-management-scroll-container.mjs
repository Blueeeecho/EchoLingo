// Real Chromium production-DOM geometry with classic scrollbars. Native IPC is
// explicitly mocked: these checks are not a physical Windows resize acceptance.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from '@playwright/test';

const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const evidence = process.env.ECHOLINGO_SCROLL_EVIDENCE;
if (evidence) fs.mkdirSync(evidence, { recursive: true });
const report = { scope: 'production DOM/CSS in Chromium with classic scrollbars and mocked IPC', nativeAcceptance: false, snapshots: [], checks: [] };
const browser = await chromium.launch({ headless: true, ignoreDefaultArgs: ['--hide-scrollbars'],
  args: ['--disable-features=OverlayScrollbar,FluentOverlayScrollbar'],
  ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 640, height: 652 } });
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    window.isTauri = true;
    window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener() {} };
    Object.defineProperty(navigator, 'platform', { configurable: true, get: () => 'Win32' });
    const q = window.__scrollQA = { commands: [], fits: [], copies: [], wheels: [], presentation: { epoch: 1, presented: true },
      settings: { appVersion: '0.1.0-test', providers: [], sourceLanguage: 'auto', targetLanguage: 'auto',
        shortcuts: { selection: 'Alt+D', capture: '', ocr: '', silentOcr: 'Alt+S', input: 'Alt+A' },
        saveHistory: true, theme: 'light', maxHistory: 20, autoHideSeconds: 0, ocrProviders: [], activeOcrProviderId: null,
        windowsSelectionStrategy: 'copy', windowsShortcutPolicy: 'priority' } };
    document.addEventListener('wheel', event => {
      const sample = { target: event.target.tagName, deltaY: event.deltaY, defaultPrevented: event.defaultPrevented };
      q.wheels.push(sample); queueMicrotask(() => { sample.defaultPrevented = event.defaultPrevented; });
    }, { capture: true, passive: true });
    let callback = 0;
    window.__TAURI_INTERNALS__ = { transformCallback: () => ++callback, unregisterCallback() {}, invoke: async (command, args) => {
      q.commands.push(command);
      if (command === 'plugin:event|listen') return ++callback;
      if (command === 'plugin:event|unlisten') return;
      if (command === 'get_settings') return structuredClone(q.settings);
      if (command === 'get_translation_presentation') return structuredClone(q.presentation);
      if (command === 'get_pending_settings' || command === 'get_pending_source') return null;
      if (command === 'get_history') return [];
      if (command === 'fit_window') { q.fits.push(structuredClone(args)); return; }
      if (command === 'get_system_translation_status') return { supported: false, ready: false, requiresSetup: false, message: 'Windows 本机离线翻译可用。' };
      if (command === 'diagnostics') return { platform: 'windows', warnings: [], fixture: '本地多行\n诊断记录' };
      if (command === 'copy_text') { q.copies.push(args.text); return; }
      if (command === 'hide_window' || command === 'start_window_resize') return;
      throw new Error(`Unexpected mocked IPC: ${command}`);
    } };
  });
  const frames = () => page.evaluate(async () => { for (let i = 0; i < 8; i++) await new Promise(requestAnimationFrame); });
  const snapshot = async label => {
    const value = await page.evaluate(() => {
      const root = document.documentElement, main = document.querySelector('main');
      const rect = element => { const r = element.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; };
      const hit = (x, y) => document.elementFromPoint(x, y)?.closest('[data-window-resize]')?.getAttribute('data-window-resize') ?? null;
      return { viewport: { width: innerWidth, height: innerHeight }, root: { clientWidth: root.clientWidth, scrollWidth: root.scrollWidth, scrollHeight: root.scrollHeight, scrollTop: root.scrollTop },
        body: { scrollWidth: document.body.scrollWidth, scrollHeight: document.body.scrollHeight, rect: rect(document.body) },
        main: { clientWidth: main.clientWidth, offsetWidth: main.offsetWidth, clientHeight: main.clientHeight, scrollHeight: main.scrollHeight, scrollWidth: main.scrollWidth, scrollTop: main.scrollTop, rect: rect(main) },
        hits: { east: hit(innerWidth - 8, innerHeight / 2), south: hit(innerWidth / 2, innerHeight - 8), southEast: hit(innerWidth - 8, innerHeight - 8) },
        edges: Object.fromEntries([...document.querySelectorAll('[data-window-resize]')].map(element => [element.dataset.windowResize, rect(element)])),
        windowScrollY: scrollY, fits: window.__scrollQA.fits.length };
    });
    report.snapshots.push({ label, ...value });
    if (evidence) fs.writeFileSync(path.join(evidence, 'geometry.json'), JSON.stringify(report, null, 2));
    return value;
  };
  const visibleHit = async selector => {
    const element = page.locator(selector); await element.scrollIntoViewIfNeeded(); await frames();
    const hit = await element.evaluate(target => {
      const r = target.getBoundingClientRect(), actual = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
      return { visible: r.top >= 0 && r.bottom <= innerHeight && target.contains(actual), rect: { x: r.x, y: r.y, width: r.width, height: r.height }, actualTag: actual?.tagName, actualId: actual?.id };
    });
    assert.equal(hit.visible, true, `${selector} must remain reachable: ${JSON.stringify(hit)}`);
  };
  for (const width of [640, 420]) {
    // Each viewport is an independent document, so prior focus/scroll gestures
    // cannot carry a latched browser scroll target into the next width case.
    await page.setViewportSize({ width, height: 652 }); await page.goto(origin);
    await page.waitForFunction(() => document.querySelector('#footer-status').textContent === '准备就绪');
    await page.locator('#more-toggle').click(); await page.locator('#popup-more-menu button[data-view="settings"]').click();
    await frames();
    const geometry = await snapshot(`management-${width}`);
    // Native fixtures enter eight client pixels from the physical window edge.
    // A viewport scrollbar used to occupy that point before the internal scroll fix.
    assert.equal(geometry.hits.east, 'east', `native clientRight-8 at width ${width}`);
    assert.equal(geometry.hits.south, 'south', `native clientBottom-8 at width ${width}`);
    assert.equal(geometry.hits.southEast, 'south-east', `native client corner-8 at width ${width}`);
    assert.equal(geometry.root.clientWidth, width); assert.equal(geometry.root.scrollWidth, width);
    assert.equal(geometry.root.scrollHeight, 652); assert.equal(geometry.windowScrollY, 0);
    assert.ok(geometry.main.offsetWidth > geometry.main.clientWidth, 'Classic internal scrollbar must occupy real pixels');
    assert.ok(geometry.main.scrollHeight > geometry.main.clientHeight);
    assert.equal(geometry.main.scrollWidth, geometry.main.clientWidth, 'Management content must not overflow horizontally');
    await visibleHit('#close-management'); await visibleHit('.management-header button[data-view="translate"]');
    await page.locator('#add-provider').focus(); await page.keyboard.press('PageDown');
    await page.waitForFunction(() => document.querySelector('main').scrollTop > 0);
    await page.keyboard.press('End');
    await page.waitForFunction(() => { const main = document.querySelector('main'); return main.scrollTop + main.clientHeight >= main.scrollHeight - 1; });
    await visibleHit('#save-shortcuts');
    await page.locator('.diagnostics-details summary').click();
    await page.locator('#run-diagnostics').click();
    await page.waitForFunction(() => !document.querySelector('#copy-diagnostics').disabled);
    const copyCount = await page.evaluate(() => window.__scrollQA.copies.length);
    await visibleHit('#copy-diagnostics'); await page.locator('#copy-diagnostics').click();
    await page.waitForFunction(count => window.__scrollQA.copies.length === count + 1, copyCount);
    const mainBox = await page.locator('main').boundingBox();
    const wheelPoint = { x: mainBox.x + 4, y: mainBox.y + mainBox.height - 30 };
    (report.wheelChecks ??= []).push(await page.evaluate(point => {
      const hit = document.elementFromPoint(point.x, point.y), main = document.querySelector('main');
      return { point, hit: hit?.tagName, hitId: hit?.id, className: hit?.className, scrollTop: main.scrollTop, clientHeight: main.clientHeight, scrollHeight: main.scrollHeight };
    }, wheelPoint));
    await page.mouse.move(wheelPoint.x, wheelPoint.y);
    await page.waitForFunction(() => document.querySelector('main').matches(':hover')); await frames();
    await page.mouse.wheel(0, 10000);
    try {
      await page.waitForFunction(() => { const main = document.querySelector('main'); return main.scrollTop + main.clientHeight >= main.scrollHeight - 1; }, null, { timeout: 5000 });
    } catch (error) { report.wheelEvents = await page.evaluate(() => window.__scrollQA.wheels); await snapshot(`management-${width}-wheel-failure`); if(evidence) await page.screenshot({path:path.join(evidence,`wheel-failure-${width}.png`)}); throw error; }
    const bottom = await snapshot(`management-${width}-bottom`);
    assert.equal(bottom.root.scrollTop, 0); assert.equal(bottom.windowScrollY, 0);
    await visibleHit('#close-management');
    // Focus-driven scrolling must move the inner content, not the root page.
    await page.locator('#max-history').focus(); await page.keyboard.press('Tab'); await frames();
    assert.equal(await page.evaluate(() => scrollY), 0);
    await page.locator('.diagnostics-details summary').click();
    // Copy feedback is a real timed overlay. Let it disappear through the
    // application before checking controls at the same viewport coordinates.
    await page.locator('#toast').waitFor({ state: 'hidden' });
    await visibleHit('#add-provider'); await page.locator('#add-provider').click();
    await page.locator('#provider-preset').selectOption('openai'); await frames();
    const modal = await page.locator('#provider-form').evaluate(element => {
      const style = getComputedStyle(element);
      return { scrollbar: element.offsetWidth - element.clientWidth - parseFloat(style.borderLeftWidth) - parseFloat(style.borderRightWidth), scrollHeight: element.scrollHeight, clientHeight: element.clientHeight };
    });
    (report.modalChecks ??= []).push({ width, ...modal });
    assert.ok(modal.scrollbar > 0 && modal.scrollHeight > modal.clientHeight, 'Add service uses its own classic scrollbar');
    await visibleHit('#provider-name'); await visibleHit('#save-provider'); await visibleHit('#close-provider-dialog');
    const modalGeometry = await snapshot(`management-${width}-modal`);
    assert.equal(modalGeometry.root.clientWidth, width); assert.equal(modalGeometry.windowScrollY, 0);
    await page.locator('#close-provider-dialog').click(); await frames();
    const closed = await snapshot(`management-${width}-modal-closed`);
    assert.equal(closed.hits.east, 'east'); assert.equal(closed.root.scrollTop, 0); assert.equal(closed.windowScrollY, 0);
    const fitCount = await page.evaluate(() => window.__scrollQA.fits.length); await frames(); await frames();
    assert.equal(await page.evaluate(() => window.__scrollQA.fits.length), fitCount, 'ResizeObserver must settle rather than repeatedly fit');
    assert.equal(await page.locator('body').evaluate(element => element.classList.contains('modal-open')), false);
    if (evidence) await page.screenshot({ path: path.join(evidence, `management-${width}.png`) });
    report.checks.push({ width, passed: true });
  }
  await page.locator('.management-header button[data-view="translate"]').click(); await frames();
  const popup = await snapshot('popup-after-management');
  assert.equal(await page.locator('main').evaluate(element => getComputedStyle(element).overflowY), 'visible');
  assert.ok(popup.main.rect.height < 652, 'Popup must retain intrinsic content height');
  assert.equal(await page.locator('[data-window-resize="south"]').isVisible(), false);
  assert.equal(await page.locator('[data-window-resize="east"]').isVisible(), true);
  assert.deepEqual(errors, []); report.ok = true;
  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  report.ok = false; report.error = error.stack; throw error;
} finally {
  if (evidence) fs.writeFileSync(path.join(evidence, 'validation.json'), JSON.stringify(report, null, 2));
  await browser.close();
}
