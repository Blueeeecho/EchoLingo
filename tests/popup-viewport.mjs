// Production DOM/layout module + generated content, mocked IPC. This does not
// replace the hidden WKWebView native gate or physical Mac visual acceptance.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const browser = await chromium.launch({ headless: true, ignoreDefaultArgs: ['--hide-scrollbars'],
  ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 640, height: 720 }, deviceScaleFactor: 2 });
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.route(`${origin}/__popup_viewport`, route => route.fulfill({ contentType: 'text/html', body: `<!doctype html>
    <link rel="stylesheet" href="/src/styles.css"><style>::-webkit-scrollbar{width:15px}</style>
    <body data-view="translate"><div class="app-shell"><div class="main-shell"><header class="popup-toolbar"></header><main>
    <section class="view"><div class="source-column" style="height:80px">Generated source</div><div class="language-bar">auto</div>
    <div class="result-card"><header class="result-card-header">Provider</header><p class="result-text">Generated result</p><div class="result-actions">Copy</div></div>
    </section></main></div></div></body>` }));
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'platform', { configurable: true, get: () => 'MacIntel' });
    const q = window.__viewportQA = { presentation: { epoch: 1, presented: false }, target: null, fits: [], shows: [], preparations: [], scale: 2, scaleQueries: [] };
    Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: () => q.scale });
    const matchMedia = window.matchMedia.bind(window);
    window.matchMedia = query => {
      if (!query.includes('resolution:')) return matchMedia(query);
      const media = new EventTarget(); q.scaleQueries.push(media); return media;
    };
    window.__TAURI_INTERNALS__ = { invoke: async (command, args) => {
      if (command === 'fit_window') {
        q.fits.push(structuredClone(args));
        if (q.failFit) throw new Error('WINDOW_LAYOUT: generated sizing failure');
        return q.target ? { ...q.target, presentationEpoch: q.presentation.epoch } : null;
      }
      if (command === 'show_popup' || command === 'show_management') {
        q.shows.push({ command, viewport: { width: innerWidth, height: innerHeight, scaleFactor: devicePixelRatio }, ...args });
        return structuredClone(q.presentation);
      }
      throw new Error(`Unexpected IPC ${command}`);
    } };
  });
  const load = async () => {
    await page.goto(`${origin}/__popup_viewport`);
    await page.evaluate(async () => {
      document.documentElement.dataset.platform = 'macos';
      const q = window.__viewportQA;
      const { installPanelLayout } = await import('/src/panel-layout.ts');
      q.layout = installPanelLayout(true, () => q.presentation, () => q.preparations.push(innerWidth));
    });
    await page.waitForFunction(() => window.__viewportQA.fits.length > 0);
  };
  await load();
  await page.evaluate(() => {
    const q = window.__viewportQA; q.target = { width: 680, height: 300, scaleFactor: 2 };
    q.pending = q.layout.presentPopup(1);
  });
  await page.waitForFunction(() => window.__viewportQA.fits.length > 1);
  assert.equal(await page.evaluate(() => window.__viewportQA.shows.length), 0, 'Native ACK alone must not reveal old management viewport');
  await page.setViewportSize({ width: 680, height: 300 });
  await page.evaluate(() => window.__viewportQA.pending);
  assert.deepEqual(await page.evaluate(() => window.__viewportQA.shows[0].viewport), { width: 680, height: 300, scaleFactor: 2 });
  assert.equal(await page.evaluate(() => window.__viewportQA.preparations.at(-1)), 680, 'Source auto-height is remeasured at adopted width before reveal');
  assert.equal(await page.evaluate(() => window.__viewportQA.fits.at(-1).contentWidth), 680);

  // Latest intent and disposal cannot revive an old wait when resize arrives.
  for (const dispose of [false, true]) {
    await load();
    await page.evaluate(() => {
      const q = window.__viewportQA; q.target = { width: 713, height: 469, scaleFactor: 2 };
      q.pending = q.layout.presentPopup(1);
    });
    await page.waitForFunction(() => window.__viewportQA.fits.length > 1);
    await page.evaluate(dispose => {
      const q = window.__viewportQA;
      if (dispose) q.layout.dispose(); else q.presentation = { epoch: 2, presented: false };
    }, dispose);
    await page.setViewportSize({ width: 713, height: 469 });
    assert.equal(await page.evaluate(() => window.__viewportQA.pending), null);
    assert.equal(await page.evaluate(() => window.__viewportQA.shows.length), 0);
    await page.setViewportSize({ width: 680, height: 300 });
  }

  await load();
  await page.evaluate(() => {
    const q = window.__viewportQA; q.target = { width: 713, height: 469, scaleFactor: 2 };
    q.pending = q.layout.presentPopup(1);
  });
  await page.waitForFunction(() => window.__viewportQA.fits.length > 1);
  await page.evaluate(() => {
    const q = window.__viewportQA; q.presentation = { epoch: 2, presented: false };
    q.target = { width: 680, height: 400, scaleFactor: 2 };
    q.newPending = q.layout.presentPopup(2);
  });
  assert.equal(await page.evaluate(() => window.__viewportQA.pending), null, 'A newer presentation cancels an old viewport wait');
  await page.setViewportSize({ width: 680, height: 400 });
  await page.evaluate(() => window.__viewportQA.newPending);
  assert.deepEqual(await page.evaluate(() => window.__viewportQA.shows.map(show => show.presentationEpoch)), [2]);

  await load();
  await page.evaluate(async () => {
    const q = window.__viewportQA;
    document.body.dataset.view = 'settings';
    q.target = { width: innerWidth, height: innerHeight, scaleFactor: 2 };
    await q.layout.presentManagement(1);
    q.presentation = { epoch: 2, presented: false };
    await q.layout.presentManagement(2);
  });
  assert.deepEqual(await page.evaluate(() => window.__viewportQA.shows.map(show => show.presentationEpoch)), [1, 2], 'Same-size settings reopen must acquire a new-epoch ACK');
  for (const scale of [1, 2]) {
    const before = await page.evaluate(scale => {
      const q = window.__viewportQA, before = q.fits.length;
      q.scale = scale; q.target.scaleFactor = scale;
      q.scaleQueries.at(-1).dispatchEvent(new Event('change')); return before;
    }, scale);
    await page.waitForFunction(before => window.__viewportQA.fits.length > before, before);
  }
  assert.equal(await page.evaluate(() => window.__viewportQA.shows.length), 2, 'Backing scale changes refit without show/focus');
  await page.evaluate(async () => {
    const q = window.__viewportQA; q.presentation = { epoch: 3, presented: false }; q.failFit = true;
    try { await q.layout.presentManagement(3); } catch (error) { q.failure = error.message; }
  });
  assert.match(await page.evaluate(() => window.__viewportQA.failure), /generated sizing failure/);
  assert.equal(await page.evaluate(() => window.__viewportQA.shows.length), 2, 'Failed new-epoch fit must not reuse an old successful geometry ACK');

  await load();
  // Keep native automatic height out of this CSS-only phase. Compare exactly
  // the same text at an overflowing old viewport and an expanded one.
  await page.evaluate(() => window.__viewportQA.layout.dispose());
  for (const width of [420, 680, 713]) {
    for (const font of [14, 22]) {
      await page.evaluate(font => {
        const result = document.querySelector('.result-text');
        result.style.fontSize = `${font}px`;
        result.textContent = 'Generated streamed words 中文 '.repeat(8);
      }, font);
      const metrics = async height => {
        await page.setViewportSize({ width, height });
        return page.locator('.result-text').evaluate(result => ({ width: result.getBoundingClientRect().width,
          height: result.getBoundingClientRect().height, natural: document.querySelector('.view').scrollHeight }));
      };
      const short = await metrics(160), tall = await metrics(1400);
      assert.equal(short.width, tall.width, `classic scrollbar width remains stable at ${width}px/font ${font}`);
      assert.equal(short.height, tall.height, 'Native height adoption must not rewrap the same text');
      assert.equal(short.natural, tall.natural, 'Measured intrinsic content must not oscillate after height fit');
    }
  }
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ ok: true, scope: 'generated DOM + mock IPC, not physical Mac clarity', cases: 14 }));
} finally { await browser.close(); }
