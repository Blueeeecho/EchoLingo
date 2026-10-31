// Reference-window UI only: synthetic image and fake IPC; no native acceptance.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
const base = process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/';
try {
  for (const broken of [false, true]) {
    const page = await browser.newPage({ viewport: { width: 240, height: 160 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(({ broken }) => {
      window.isTauri = true;
      const qa = window.__pinQA = { calls: [], failToggle: false, holdToggle: false, release: () => {} };
      window.__TAURI_INTERNALS__ = { invoke: async (command, args = {}) => {
        qa.calls.push({ command, ...args });
        if (command === 'get_pinned_screenshot') {
          const canvas = document.createElement('canvas'); canvas.width = 96; canvas.height = 64;
          const ctx = canvas.getContext('2d'); ctx.fillStyle = '#112233'; ctx.fillRect(0, 0, 96, 64);
          return { width: broken ? 95 : 96, height: 64, pngBase64: canvas.toDataURL('image/png').split(',')[1] };
        }
        if (command === 'set_screenshot_pinned') {
          if (qa.holdToggle) await new Promise(resolve => { qa.release = resolve; });
          if (qa.failToggle) throw new Error('fixture toggle failure');
          return;
        }
        if (['pinned_screenshot_ready', 'close_pinned_screenshot'].includes(command)) return;
        throw new Error('Unexpected IPC: ' + command);
      } };
    }, { broken });
    await page.goto(new URL('pinned-screenshot.html', base).href);
    await page.waitForFunction(() => window.__pinQA.calls.some(call => call.command === 'pinned_screenshot_ready'));
    const readiness = await page.evaluate(() => window.__pinQA.calls.filter(call => call.command === 'pinned_screenshot_ready'));
    assert.deepEqual(readiness.map(call => call.success), [!broken]);
    if (broken) {
      assert.equal(await page.locator('#pinned-image').isVisible(), false);
      assert.equal(await page.locator('#toggle-pin').isDisabled(), true);
    } else {
      assert.equal(await page.locator('#pinned-image').isVisible(), true);
      assert.equal(await page.locator('#image-info').textContent(), '96 × 64');
      await page.locator('#toggle-pin').click();
      await page.waitForFunction(() => document.querySelector('#toggle-pin').getAttribute('aria-pressed') === 'false');
      await page.evaluate(() => { window.__pinQA.failToggle = true; });
      await page.locator('#toggle-pin').click();
      await page.getByText(/fixture toggle failure/).waitFor();
      assert.equal(await page.locator('#toggle-pin').getAttribute('aria-pressed'), 'false', 'failure does not lie about state');
      await page.evaluate(() => { window.__pinQA.failToggle = false; window.__pinQA.holdToggle = true; });
      await page.locator('#toggle-pin').click();
      assert.equal(await page.locator('#toggle-pin').isDisabled(), true);
      await page.evaluate(() => { window.__pinQA.holdToggle = false; window.__pinQA.release(); });
      await page.waitForFunction(() => document.querySelector('#toggle-pin').getAttribute('aria-pressed') === 'true');
      const imageBox = await page.locator('#pinned-image').boundingBox();
      assert.ok(imageBox.width <= 240 && imageBox.height < 160);
    }
    await page.locator('#close-pin').click();
    await page.waitForFunction(() => window.__pinQA.calls.some(call => call.command === 'close_pinned_screenshot'));
    assert.deepEqual(errors, []);
    await page.close();
  }
  console.log('PASS: reference image decode readiness/failure, bounded layout, unpin/re-pin, errors and close; fake IPC only.');
} finally { await browser.close(); }
