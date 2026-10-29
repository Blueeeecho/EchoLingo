// Isolated browser/IPC scheduling checks. This does not claim physical Windows
// live-resize or DWM rendering acceptance and never controls an installed app.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';

const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 700 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.route(`${origin}/__layout_performance`, (route) => route.fulfill({ contentType: 'text/html', body: `<!doctype html><style>
    body { margin: 0 } .app-shell { min-height: 0 } .popup-toolbar { height: 36px }
    main { padding: 0 } .view { height: 200px }
  </style><body data-view="translate"><div class="app-shell"><header class="popup-toolbar"></header><main><div class="view"></div></main></div></body>` }));
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'platform', { configurable: true, get: () => 'Win32' });
    const callbacks = new Map(), listeners = new Map(); let serial = 0;
    let nativeRevision = 0, nativeActive = false; const nativeWaiters = [];
    const nativeState = (payload) => {
      if (!payload || !Number.isSafeInteger(payload.revision) || payload.revision <= 0 || typeof payload.active !== 'boolean') return;
      if (payload.active && payload.revision > nativeRevision) { nativeRevision = payload.revision; nativeActive = true; }
      else if (!payload.active && payload.revision === nativeRevision) {
        nativeActive = false; for (const complete of nativeWaiters.splice(0)) complete(nativeRevision);
      }
    };
    window.__layoutQA = { fits: [], commands: [], presentation: { epoch: 1, presented: true },
      nativeState,
      emit: (payload) => { nativeState(payload); const id = listeners.get('popup-native-sizing'); callbacks.get(id)?.({ event: 'popup-native-sizing', payload, id: 1 }); },
      frames: async (count = 3) => { for (let at = 0; at < count; at++) await new Promise(requestAnimationFrame); },
      listenerCount: () => listeners.size,
    };
    window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener: (event) => listeners.delete(event) };
    window.__TAURI_INTERNALS__ = {
      transformCallback: (callback) => { const id = ++serial; callbacks.set(id, callback); return id; },
      unregisterCallback: (id) => callbacks.delete(id),
      invoke: async (command, args) => {
        window.__layoutQA.commands.push(command);
        if (command === 'plugin:event|listen') { listeners.set(args.event, args.handler); return 1; }
        if (command === 'plugin:event|unlisten') return null;
        if (command === 'wait_for_window_sizing') return nativeActive ? new Promise((resolve) => nativeWaiters.push(resolve)) : nativeRevision;
        if (command === 'fit_window') { window.__layoutQA.fits.push(structuredClone(args)); return null; }
        if (command === 'show_management' || command === 'show_popup') return structuredClone(window.__layoutQA.presentation);
        throw new Error(`Unexpected fixture command ${command}`);
      },
    };
  });
  await page.goto(`${origin}/__layout_performance`);
  await page.evaluate(async () => {
    const { installPanelLayout } = await import('/src/panel-layout.ts');
    window.__layoutQA.layout = installPanelLayout(true, () => window.__layoutQA.presentation);
    await window.__layoutQA.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.listenerCount()), 1);
  await page.waitForFunction(() => window.__layoutQA.fits.length > 0);
  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    q.emit({ revision: 1, active: true, presentationEpoch: 1 });
    for (let height = 210; height <= 280; height += 10) {
      document.querySelector('.view').style.height = `${height}px`;
      window.dispatchEvent(new Event('resize'));
    }
    await q.frames();
  });
  await page.setViewportSize({ width: 880, height: 700 });
  await page.evaluate(() => window.__layoutQA.frames());
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 0, 'Native sizing must suppress layout IPC, not merely delay geometry after each pixel.');
  await page.evaluate(async () => { window.__layoutQA.emit({ revision: 1, active: false, presentationEpoch: 1 }); await window.__layoutQA.frames(); });
  assert.deepEqual(await page.evaluate(() => window.__layoutQA.fits), [{ presentation: 'popup', contentHeight: 318, contentWidth: 880 }]);

  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    q.emit({ revision: 2, active: true, presentationEpoch: 1 });
    q.emit({ revision: 3, active: true, presentationEpoch: 1 });
    q.emit({ revision: 2, active: false, presentationEpoch: 1 });
    document.querySelector('.view').style.height = '300px';
    window.dispatchEvent(new Event('resize')); await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 0, 'An older end must not release a newer gesture.');
  await page.evaluate(async () => { window.__layoutQA.emit({ revision: 3, active: false, presentationEpoch: 1 }); await window.__layoutQA.frames(); });
  assert.deepEqual(await page.evaluate(() => window.__layoutQA.fits), [{ presentation: 'popup', contentHeight: 338, contentWidth: 880 }]);

  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    q.emit({ revision: 2, active: true, presentationEpoch: 1 }); // Already finished: cannot pause again.
    for (const malformed of [null, '', {}, { revision: -1, active: true, presentationEpoch: 1 }]) q.emit(malformed);
    document.querySelector('.view').style.height = '310px';
    window.dispatchEvent(new Event('resize')); await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 1);

  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    q.emit({ revision: 4, active: true, presentationEpoch: 1 });
    q.presentation = { epoch: 2, presented: true };
    document.querySelector('.view').style.height = '320px';
    window.dispatchEvent(new Event('resize')); await q.frames();
    q.emit({ revision: 4, active: false, presentationEpoch: 1 }); await q.frames();
  });
  assert.deepEqual(await page.evaluate(() => window.__layoutQA.fits), [{ presentation: 'popup', contentHeight: 358, contentWidth: 880 }], 'A new presentation is remeasured; no old gesture dimensions are replayed.');
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => /show|focus|resize_popup_width/.test(name)).length), 0);

  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    q.emit({ revision: 5, active: true, presentationEpoch: 2 });
    document.body.dataset.view = 'settings';
    q.pendingPresentation = q.layout.presentManagement(2);
    await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 0, 'An explicit management action must not change native geometry inside the sizing loop.');
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_management').length), 0);
  await page.evaluate(async () => {
    const q = window.__layoutQA;
    q.emit({ revision: 5, active: false, presentationEpoch: 2 });
    await q.pendingPresentation; await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 1);
  assert.equal(await page.evaluate(() => window.__layoutQA.fits[0].presentation), 'management');
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_management').length), 1);

  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    q.emit({ revision: 6, active: true, presentationEpoch: 2 });
    q.pendingPresentation = q.layout.presentManagement(2);
    await q.frames();
    q.nativeState({ revision: 6, active: false }); // Native end acknowledgement; advisory event deliberately lost.
    await q.pendingPresentation; await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 1, 'A missing end event must not permanently block explicit presentations.');
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_management').length), 2);

  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    q.emit({ revision: 7, active: true, presentationEpoch: 2 });
    q.pendingPresentation = q.layout.presentManagement(2);
    q.nativeState({ revision: 7, active: false });
    q.emit({ revision: 8, active: true, presentationEpoch: 2 });
    await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_management').length), 2, 'A newer native loop wins over an already resolved older acknowledgement.');
  await page.evaluate(async () => {
    const q = window.__layoutQA;
    q.nativeState({ revision: 8, active: false });
    await q.pendingPresentation; await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_management').length), 3);

  // Management content may become much taller than its viewport (expanded
  // service editors/permission help). It must scroll without negotiating a new
  // HWND height; an actual viewport resize is measured independently.
  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    document.querySelector('.view').style.height = '2200px';
    window.dispatchEvent(new Event('echolingo:layout')); await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 0, 'Growing settings content must not trigger a native size change.');
  await page.setViewportSize({ width: 940, height: 820 });
  await page.evaluate(() => window.__layoutQA.frames());
  assert.deepEqual(await page.evaluate(() => window.__layoutQA.fits), [{ presentation: 'management', contentHeight: 820, contentWidth: 940 }]);
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_management').length), 3, 'Resizing settings must not show or activate a window.');

  await page.evaluate(async () => {
    const q = window.__layoutQA;
    document.body.dataset.view = 'translate';
    q.emit({ revision: 9, active: true, presentationEpoch: 2 });
    q.pendingPresentation = q.layout.presentPopup(2);
    q.presentation = { epoch: 3, presented: true };
    q.nativeState({ revision: 9, active: false });
    q.stalePresentation = await q.pendingPresentation;
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.stalePresentation), null);
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_popup').length), 0, 'A superseded epoch cannot show after the native completion acknowledgement.');

  await page.evaluate(async () => {
    const q = window.__layoutQA; q.fits.length = 0;
    document.body.dataset.view = 'translate';
    q.presentation = { epoch: 3, presented: true };
    q.emit({ revision: 10, active: true, presentationEpoch: 3 });
    q.pendingPresentation = q.layout.presentPopup(3);
    q.layout.dispose();
    q.nativeState({ revision: 10, active: false });
    q.disposedPresentation = await q.pendingPresentation;
    q.emit({ revision: 10, active: false, presentationEpoch: 3 });
    window.dispatchEvent(new Event('resize')); await q.frames();
  });
  assert.equal(await page.evaluate(() => window.__layoutQA.disposedPresentation), null);
  assert.equal(await page.evaluate(() => window.__layoutQA.commands.filter((name) => name === 'show_popup').length), 0, 'Disposing a presentation while sizing cannot reopen it later.');
  assert.equal(await page.evaluate(() => window.__layoutQA.fits.length), 0);
  assert.equal(await page.evaluate(() => window.__layoutQA.listenerCount()), 0);
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ ok: true, scope: 'isolated browser DOM + mocked IPC; no Windows/DWM claim', cases: 12 }));
} finally { await browser.close(); }
