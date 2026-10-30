// Real layout/scroll geometry only; native gesture origin is covered separately.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage();
  await page.route(`${origin}/__manual_height`, route => route.fulfill({ contentType: 'text/html', body: `<!doctype html><link rel="stylesheet" href="/src/styles.css"><body data-view="translate"><div class="app-shell"><div class="main-shell"><header class="popup-toolbar"><button id="pin-button">Pin</button></header><main><section class="view"><div style="height:85px">明白</div><div class="language-bar">自动中英互译</div><div class="result-card"><div class="result-text" style="height:100px">Clear</div><button id="result-end">Copy result</button></div></section></main></div></div></body>` }));
  await page.goto(`${origin}/__manual_height`);
  for (const platform of ['macos', 'windows']) {
    await page.evaluate(value => document.documentElement.dataset.platform = value, platform);
    for (const height of [469, 160, 300, 160]) {
      await page.setViewportSize({ width: 713, height });
      const geometry = await page.evaluate(() => {
        const view = document.querySelector('.view'); view.scrollTop = view.scrollHeight;
        const end = document.querySelector('#result-end').getBoundingClientRect();
        const box = view.getBoundingClientRect();
        return { viewport: innerHeight, bottom: box.bottom, resultBottom: end.bottom, resultTop: end.top, viewTop: box.top };
      });
      assert.ok(geometry.bottom <= height, `${platform}: scroll viewport must fit inside native window`);
      assert.ok(geometry.resultBottom <= height && geometry.resultTop >= geometry.viewTop, `${platform}: result actions must remain reachable at ${height}px`);
      await page.locator('#pin-button').evaluate(button => button.setAttribute('aria-pressed', 'true'));
      assert.equal(await page.evaluate(() => innerHeight), height, 'Pin does not alter user viewport');
    }
  }
  console.log('PASS: 160px and expanded popup retain reachable result actions on both platform styles');
} finally { await browser.close(); }
