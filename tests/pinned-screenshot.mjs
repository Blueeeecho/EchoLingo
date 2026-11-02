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
        if (command === 'start_pinned_screenshot_drag' && args.prepareOnly) {
          if (qa.holdPrepare) await new Promise(resolve => { qa.releasePrepare = resolve; });
          return '4294967296';
        }
        if (['pinned_screenshot_ready', 'close_pinned_screenshot', 'start_pinned_screenshot_drag', 'resize_pinned_screenshot'].includes(command)) return;
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
      assert.equal(await page.locator('header, #image-info, #pin-label').count(), 0, 'no title/dimensions/pin caption');
      assert.equal(await page.locator('button').count(), 2, 'only pin and close controls');
      assert.equal(await page.locator('.actions').textContent(), '', 'icons contain no persistent labels');
      assert.equal(await page.locator('#pinned-image').evaluate(image => getComputedStyle(image).objectFit), 'contain');
      const dragCount = () => page.evaluate(() => window.__pinQA.calls.filter(c => c.command === 'start_pinned_screenshot_drag' && !c.prepareOnly).length);
      await page.mouse.move(100, 90); await page.mouse.down(); await page.mouse.up();
      assert.equal(await dragCount(), 0, 'a stationary click never starts native dragging');
      await page.mouse.down(); await page.mouse.move(102, 91); await page.mouse.up();
      assert.equal(await dragCount(), 0, 'small click jitter does not move the window');
      await page.mouse.move(100, 90); await page.mouse.down();
      await page.locator('main').dispatchEvent('pointermove', { pointerId: 99, isPrimary: false, buttons: 1, clientX: 200, clientY: 140 });
      await page.locator('main').dispatchEvent('pointercancel', { pointerId: 99 });
      assert.equal(await dragCount(), 0, 'foreign pointers cannot start or cancel this drag');
      await page.mouse.move(110, 95); await page.mouse.move(120, 100); await page.mouse.up();
      assert.equal(await dragCount(), 1, 'a held movement starts native dragging once');
      await page.mouse.down(); await page.evaluate(() => window.dispatchEvent(new Event('blur')));
      await page.mouse.move(140, 110); await page.mouse.up();
      assert.equal(await dragCount(), 1, 'blur cancels a pending movement intent');
      await page.mouse.down();
      await page.locator('main').dispatchEvent('pointercancel', { pointerId: 1 });
      await page.mouse.move(160, 120); await page.mouse.up();
      assert.equal(await dragCount(), 1, 'cancel cannot resume native dragging');
      await page.evaluate(() => { window.__pinQA.holdPrepare = true; });
      await page.mouse.move(100, 90); await page.mouse.down(); await page.mouse.move(110, 95);
      await page.waitForFunction(() => !!window.__pinQA.releasePrepare);
      await page.mouse.up();
      await page.locator('#toggle-pin').click();
      await page.waitForFunction(() => document.querySelector('#toggle-pin').getAttribute('aria-pressed') === 'false');
      await page.locator('#toggle-pin').click();
      await page.waitForFunction(() => document.querySelector('#toggle-pin').getAttribute('aria-pressed') === 'true');
      await page.evaluate(() => { window.__pinQA.holdPrepare = false; window.__pinQA.releasePrepare(); });
      await page.waitForTimeout(20);
      assert.equal(await dragCount(), 1, 'late preparation after release and a new control press cannot drag');
      for (const direction of ['North','NorthEast','East','SouthEast','South','SouthWest','West','NorthWest']) {
        await page.locator(`[data-direction=${direction}]`).click();
        assert.equal(await page.evaluate(() => window.__pinQA.calls.filter(c => c.command === 'resize_pinned_screenshot').at(-1).direction), direction.toLowerCase());
      }
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
      assert.deepEqual(imageBox, { x: 0, y: 0, width: 240, height: 160 }, 'image area uses full window without header reservation');
      assert.equal(await page.evaluate(() => window.__pinQA.calls.filter(c => c.command === 'start_pinned_screenshot_drag' && !c.prepareOnly).length), 1, 'buttons and resize edges never drag');
    }
    await page.locator('#close-pin').click();
    await page.waitForFunction(() => window.__pinQA.calls.some(call => call.command === 'close_pinned_screenshot'));
    assert.deepEqual(errors, []);
    await page.close();
  }
  // Small landscape/portrait pins use image-shaped native viewports, not a
  // 240x160 canvas. Tiny images scale uniformly for controls without changing pixels.
  for (const [width, height, imageWidth = width, imageHeight = height] of [[200, 40], [40, 200], [76, 76, 10, 10], [720, 40, 1000, 10], [40, 520, 10, 1000]]) {
    const page = await browser.newPage({ viewport: { width, height } });
    await page.addInitScript(({ width: imageWidth, height: imageHeight }) => {
      window.isTauri = true;
      window.__TAURI_INTERNALS__ = { invoke: async command => {
        if (command === 'get_pinned_screenshot') {
          const c = document.createElement('canvas'); c.width = imageWidth; c.height = imageHeight;
          const ctx = c.getContext('2d'); ctx.fillStyle = '#123456'; ctx.fillRect(0, 0, imageWidth, imageHeight);
          return { width: imageWidth, height: imageHeight, pngBase64: c.toDataURL().split(',')[1] };
        }
      } };
    }, { width: imageWidth, height: imageHeight });
    await page.goto(new URL('pinned-screenshot.html', base).href);
    await page.locator('#pinned-image').waitFor({ state: 'visible' });
    assert.deepEqual(await page.locator('#pinned-image').boundingBox(), { x: 0, y: 0, width, height });
    assert.deepEqual(await page.locator('#pinned-image').evaluate(i => [i.naturalWidth, i.naturalHeight]), [imageWidth, imageHeight]);
    for (const selector of ['#toggle-pin', '#close-pin']) {
      const b = await page.locator(selector).boundingBox();
      assert.ok(b.x >= 0 && b.y >= 0 && b.x + b.width <= width && b.y + b.height <= height, 'both icons stay inside small image viewport');
    }
    await page.close();
  }

  console.log('PASS: reference image decode, click/drag intent, small/tiny layouts, unpin/re-pin, errors and close; fake IPC only.');
} finally { await browser.close(); }
