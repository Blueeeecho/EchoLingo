// Dedicated image editor, fake IPC only. No installed desktop app, OCR, network
// service, or real user image is touched. CI runs Chromium; native Win/Mac
// capture/save/clipboard acceptance remains a separate required gate.
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
const base = process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/';
const errors = [], externalRequests = [];
try {
  for (const deviceScaleFactor of [1, 2]) {
    const context = await browser.newContext({ viewport: { width: 1000, height: 760 }, deviceScaleFactor });
    const page = await context.newPage(); page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', route => {
      const url = new URL(route.request().url());
      if (!['127.0.0.1', 'localhost'].includes(url.hostname)) { externalRequests.push(url.href); return route.abort(); }
      return route.continue();
    });
    await page.addInitScript(() => {
      window.isTauri = true;
      const callbacks = new Map(), listeners = new Map(); let callbackId = 0, nextId = 0;
      const image = (width = 96, height = 64) => {
        const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
        const ctx = canvas.getContext('2d'), pixels = ctx.createImageData(width, height);
        for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
          const i = (y * width + x) * 4;
          pixels.data.set([x % 2 ? 240 : 20, y % 2 ? 180 : 40, (x + y) % 2 ? 210 : 50, x < 4 && y < 4 ? 0 : 255], i);
        }
        ctx.putImageData(pixels, 0, 0);
        return { id: ++nextId, width, height, pngBase64: canvas.toDataURL('image/png').split(',')[1], capturedAt: 1793419200000 };
      };
      const q = window.__screenshotQA = { image, calls: [], saves: [], copies: [], closed: [], ready: [], session: image(), nextOpen: null, saveCancel: false,
        holdOpen: false, holdSave: false, releaseOpen: () => {}, releaseSave: () => {}, holdExport: false, releaseExport: () => {}, exportWaits: 0,
        emit: (event, payload) => listeners.get(event)?.({ event, id: 1, payload }),
        publish(width = 96, height = 64) { this.session = image(width, height); this.emit('screenshot-session', structuredClone(this.session)); return this.session.id; },
      };
      const getImageData = CanvasRenderingContext2D.prototype.getImageData;
      CanvasRenderingContext2D.prototype.getImageData = function(...args) {
        if (q.failPixelRead && this.canvas.id === 'image-canvas') throw new Error('QA simulated pixel allocation failure');
        return getImageData.apply(this, args);
      };
      const toBlob = HTMLCanvasElement.prototype.toBlob;
      HTMLCanvasElement.prototype.toBlob = function(callback, ...args) {
        if (!q.holdExport || this.id !== 'image-canvas') return toBlob.call(this, callback, ...args);
        q.exportWaits++; return toBlob.call(this, blob => { q.releaseExport = () => callback(blob); }, ...args);
      };
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener: event => listeners.delete(event) };
      window.__TAURI_INTERNALS__ = {
        transformCallback: callback => { const id = ++callbackId; callbacks.set(id, callback); return id; },
        invoke: async (command, args = {}) => {
          if (command === 'plugin:event|listen') { listeners.set(args.event, callbacks.get(args.handler)); return 1; }
          if (command === 'plugin:event|unlisten') return;
          q.calls.push({ command, sessionId: args.sessionId });
          if (command === 'get_screenshot_session') {
            const snapshot = structuredClone(q.session), mode = new URL(location.href).searchParams.get('startup');
            if (mode === 'cleared') q.emit('screenshot-session-cleared', { id: snapshot.id });
            if (mode === 'newer') q.publish(80, 48);
            return snapshot;
          }
          if (command === 'screenshot_editor_ready') { q.ready.push(args.sessionId); return; }
          if (command === 'open_screenshot_image') {
            if (q.holdOpen) await new Promise(resolve => { q.releaseOpen = resolve; });
            if (!q.nextOpen) return null;
            q.session = q.nextOpen; q.nextOpen = null; q.emit('screenshot-session', structuredClone(q.session)); return structuredClone(q.session);
          }
          if (command === 'save_screenshot_image') {
            q.saves.push(structuredClone(args)); if (q.holdSave) await new Promise(resolve => { q.releaseSave = resolve; });
            return q.saveCancel ? null : { path: '/fixture/Desktop/EchoLingo-2026-10-31-120000.png', fileName: 'EchoLingo-2026-10-31-120000.png' };
          }
          if (command === 'copy_screenshot_image') { q.copies.push(structuredClone(args)); return; }
          if (command === 'close_screenshot_editor') { q.closed.push(args.sessionId); q.emit('screenshot-session-cleared', { id: args.sessionId }); return; }
          throw new Error(`Unexpected IPC from image editor: ${command}`);
        },
      };
    });
    await page.goto(new URL('screenshot.html', base).href);
    await page.waitForFunction(() => window.__screenshotQA.ready.length === 1);
    const pixels = async () => page.locator('#image-canvas').evaluate(canvas => ({ width: canvas.width, height: canvas.height, data: [...canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data] }));
    const fresh = async (width = 96, height = 64) => {
      const id = await page.evaluate(([w, h]) => window.__screenshotQA.publish(w, h), [width, height]);
      await page.waitForFunction(id => window.__screenshotQA.ready.includes(id), id); return id;
    };
    const drag = async (tool, start, end) => {
      await page.locator(`[data-tool="${tool}"]`).click();
      const bounds = await page.locator('#image-canvas').boundingBox();
      const size = await page.locator('#image-canvas').evaluate(c => [c.width, c.height]);
      const xy = p => [bounds.x + p[0] * bounds.width / size[0], bounds.y + p[1] * bounds.height / size[1]];
      await page.mouse.move(...xy(start)); await page.mouse.down(); await page.mouse.move(...xy(end), { steps: 3 }); await page.mouse.up();
    };
    const original = await pixels();
    assert.deepEqual([original.width, original.height], [96, 64]);
    assert.deepEqual(original.data.slice(0, 4), [0, 0, 0, 0], 'source transparency is retained');
    assert.equal(await page.locator('#save-indicator').textContent(), '未保存');
    assert.equal(await page.evaluate(() => window.__screenshotQA.saves.length), 0, 'opening a capture does not autosave');

    // Cancelled pointer gestures and Escape leave both raster and history intact.
    const cancelledBounds = await page.locator('#image-canvas').boundingBox();
    await page.mouse.move(cancelledBounds.x + 10, cancelledBounds.y + 10); await page.mouse.down();
    await page.locator('#image-canvas').dispatchEvent('pointercancel', { pointerId: 1 }); await page.mouse.up();
    assert.deepEqual(await pixels(), original);
    await drag('rectangle', [10, 10], [40, 30]); assert.notDeepEqual(await pixels(), original);
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), original);
    await page.locator('#redo-edit').click(); assert.notDeepEqual(await pixels(), original);
    await page.locator('#undo-edit').click(); await drag('arrow', [15, 15], [70, 45]);
    assert.equal(await page.locator('#redo-edit').isDisabled(), true, 'a new branch invalidates redo');

    // Native textarea handles Chinese composition; neither Enter nor Ctrl+Enter
    // may prematurely commit an active IME candidate. Text is plain, not HTML.
    await fresh(); await page.locator('[data-tool="text"]').click();
    await page.locator('#image-canvas').click({ position: { x: 5, y: 5 } });
    await page.locator('#annotation-text').fill('中文标注\n<script>alert(1)</script>');
    await page.locator('#annotation-text').dispatchEvent('compositionstart');
    await page.locator('#annotation-text').dispatchEvent('keydown', { key: 'Enter', code: 'Enter', ctrlKey: true, isComposing: true, keyCode: 229 });
    assert.equal(await page.locator('#text-dialog').evaluate(d => d.open), true);
    await page.locator('#text-dialog').dispatchEvent('cancel');
    assert.equal(await page.locator('#text-dialog').evaluate(d => d.open), true, 'IME Escape must not discard the text dialog');
    await page.locator('#annotation-text').dispatchEvent('keydown', { key: 'Escape', isComposing: true, keyCode: 229 });
    await page.locator('#annotation-text').dispatchEvent('compositionend');
    await page.locator('#text-dialog').dispatchEvent('cancel');
    assert.equal(await page.locator('#text-dialog').evaluate(d => d.open), true, 'compositionend before the Escape default must retain text');
    await page.locator('#apply-text').click(); assert.equal(await page.locator('#text-dialog').evaluate(d => d.open), false);
    assert.equal(await page.locator('#undo-edit').isEnabled(), true);
    await page.locator('[data-tool="text"]').click(); await page.locator('#image-canvas').click({ position: { x: 5, y: 5 } });
    await page.locator('#annotation-text').fill('字'.repeat(2000)); assert.equal(await page.locator('#annotation-text').inputValue().then(x => x.length), 2000);
    await page.locator('#cancel-text').click();

    // Mosaic modifies actual pixels; solid masks replace RGB and alpha fully.
    await fresh(); await drag('mosaic', [8, 8], [24, 24]);
    const mosaicked = await pixels(), at = (image, x, y) => image.data.slice((y * image.width + x) * 4, (y * image.width + x) * 4 + 4);
    assert.deepEqual(at(mosaicked, 8, 8), at(mosaicked, 23, 23));
    assert.notDeepEqual(at(mosaicked, 8, 8), at(original, 8, 8));
    assert.deepEqual(at(mosaicked, 24, 24), at(original, 24, 24));
    await page.locator('#edit-color').fill('#112233'); await drag('solid', [0, 0], [8, 8]);
    const masked = await pixels(); assert.deepEqual(at(masked, 1, 1), [17, 34, 51, 255]);

    // Crop after zoom uses image coordinates, reduces actual PNG dimensions and
    // exposes no crop-excluded pixels. DPR changes display density, not output.
    await fresh(); await page.locator('#zoom-in').click();
    await drag('crop', [10, 8], [42, 32]);
    const crop = await pixels(); assert.deepEqual([crop.width, crop.height], [32, 24]);
    assert.deepEqual(at(crop, 0, 0), at(original, 10, 8));
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), original);
    await page.locator('#redo-edit').click();
    await page.locator('#copy-image').click(); await page.waitForFunction(() => window.__screenshotQA.copies.length === 1);
    const copiedSize = await page.evaluate(async () => {
      const image = new Image(); image.src = 'data:image/png;base64,' + window.__screenshotQA.copies.at(-1).pngBase64; await image.decode(); return [image.naturalWidth, image.naturalHeight];
    }); assert.deepEqual(copiedSize, [32, 24]);
    assert.equal(await page.locator('#save-indicator').textContent(), '未保存', 'copy is not a persistent save');

    // Cancelled native Save As and Open keep editing state. Explicit Save passes
    // a flattened PNG and current session id, never original filename/path.
    await page.evaluate(() => { window.__screenshotQA.saveCancel = true; });
    await page.locator('#save-as-image').click(); await page.getByText('已取消保存，图片和编辑内容仍保留。', { exact: true }).waitFor();
    assert.equal(await page.locator('#save-indicator').textContent(), '未保存');
    await page.locator('#open-image').click(); await page.locator('#discard-confirm').click();
    await page.getByText('未选择新图片；当前图片保持不变。', { exact: true }).waitFor(); assert.deepEqual(await pixels(), crop);
    await page.evaluate(() => { window.__screenshotQA.saveCancel = false; });
    await page.locator('#save-image').click(); await page.waitForFunction(() => document.querySelector('#save-indicator').textContent === '已保存');
    const saved = await page.evaluate(() => window.__screenshotQA.saves.at(-1));
    assert.equal(saved.saveAs, false); assert.match(saved.pngBase64, /^iVBORw0KGgo/);
    assert.deepEqual(Object.keys(saved).sort(), ['pngBase64', 'saveAs', 'sessionId']);

    // Fail closed if pixel redaction/crop throws after the original was drawn.
    // Never export the unredacted/partial canvas; undo can recover safely.
    for (const tool of ['mosaic', 'crop']) {
      await fresh();
      const before = await page.evaluate(() => { const q = window.__screenshotQA; q.failPixelRead = true; return [q.saves.length, q.copies.length]; });
      await drag(tool, [8, 8], [24, 24]);
      await page.waitForFunction(() => document.querySelector('#editor-status').dataset.error === 'true');
      assert.equal(await page.locator('#save-image').isDisabled(), true);
      assert.equal(await page.locator('#copy-image').isDisabled(), true);
      assert.equal(await page.locator('#canvas-frame').isHidden(), true);
      await page.keyboard.press('Control+s'); await page.keyboard.press('Control+c');
      assert.deepEqual(await page.evaluate(() => [window.__screenshotQA.saves.length, window.__screenshotQA.copies.length]), before);
      await page.evaluate(() => { window.__screenshotQA.failPixelRead = false; });
      await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), original);
      await page.locator('#redo-edit').click(); assert.equal(await page.locator('#save-image').isEnabled(), true);
    }
    await page.locator('#image-canvas').dispatchEvent('contextlost');
    assert.equal(await page.locator('#save-image').isDisabled(), true);
    await page.locator('#image-canvas').dispatchEvent('contextrestored');
    assert.equal(await page.locator('#save-image').isEnabled(), true);
    // Generation change cancels a pending canvas export before native side
    // effects. Delayed old session/clear events cannot overwrite a newer image.
    await fresh(); const beforeSaves = await page.evaluate(() => { const q = window.__screenshotQA; q.holdExport = true; return q.saves.length; });
    await page.locator('#save-image').click(); await page.waitForFunction(() => window.__screenshotQA.exportWaits === 1);
    const oldSession = await page.evaluate(() => structuredClone(window.__screenshotQA.session));
    const currentId = await fresh(80, 48);
    await page.evaluate(old => { const q = window.__screenshotQA; q.holdExport = false; q.releaseExport(); q.emit('screenshot-session', old); q.emit('screenshot-session-cleared', { id: old.id }); }, oldSession);
    await page.waitForTimeout(30); assert.equal(await page.evaluate(() => window.__screenshotQA.saves.length), beforeSaves);
    assert.deepEqual(await page.locator('#image-canvas').evaluate(c => [c.width, c.height]), [80, 48]);
    assert.equal(await page.evaluate(() => window.__screenshotQA.ready.at(-1)), currentId);

    // Native close requests are confirmation-based. Cancel preserves document;
    // accept clears only that session. Repeated close requests do not stack.
    await page.evaluate(() => { window.__screenshotQA.emit('screenshot-close-requested', null); window.__screenshotQA.emit('screenshot-close-requested', null); });
    await page.locator('#discard-cancel').click(); assert.equal(await page.evaluate(() => window.__screenshotQA.closed.length), 0);
    await page.locator('#close-editor').click(); await page.locator('#discard-confirm').click();
    await page.waitForFunction(() => window.__screenshotQA.closed.length === 1);
    assert.equal(await page.locator('#copy-image').isDisabled(), true);

    // Closing during pre-IPC canvas export cancels the export instead of locking
    // the OS Close button behind encoding or unrelated clipboard/disk latency.
    await fresh();
    const pendingClose = await page.evaluate(() => { const q = window.__screenshotQA; q.holdExport = true; return { waits: q.exportWaits, saves: q.saves.length, closed: q.closed.length }; });
    await page.locator('#save-image').click();
    await page.waitForFunction(count => window.__screenshotQA.exportWaits > count, pendingClose.waits);
    await page.evaluate(() => window.__screenshotQA.emit('screenshot-close-requested', null));
    await page.locator('#discard-confirm').click();
    await page.waitForFunction(count => window.__screenshotQA.closed.length > count, pendingClose.closed);
    await page.evaluate(() => { const q = window.__screenshotQA; q.holdExport = false; q.releaseExport(); });
    await page.waitForTimeout(30); assert.equal(await page.evaluate(() => window.__screenshotQA.saves.length), pendingClose.saves);

    // Malformed/oversized sessions are shown as recoverable error states, without
    // decoding huge images or retaining the preceding editable raster.
    for (const bad of [{ width: 17000, height: 1 }, { width: 8000, height: 8000 }, { pngBase64: 'iVBORw0KGgoBROKEN' }]) {
      await page.evaluate(bad => { const q = window.__screenshotQA; q.session = { ...q.image(), ...bad }; q.emit('screenshot-session', structuredClone(q.session)); }, bad);
      await page.waitForFunction(() => document.querySelector('#editor-status').dataset.error === 'true');
      assert.equal(await page.locator('#save-image').isDisabled(), true);
    }
    // A clear before the durable snapshot is a tombstone. A newer event during
    // snapshot retrieval wins even though the old snapshot resolves later.
    await page.goto(new URL('screenshot.html?startup=cleared', base).href);
    await page.waitForFunction(() => window.__screenshotQA.calls.some(x => x.command === 'get_screenshot_session'));
    await page.waitForTimeout(30); assert.equal(await page.evaluate(() => window.__screenshotQA.ready.length), 0);
    assert.equal(await page.locator('#save-image').isDisabled(), true);
    await page.goto(new URL('screenshot.html?startup=newer', base).href);
    await page.waitForFunction(() => window.__screenshotQA.ready.includes(2));
    assert.deepEqual(await page.locator('#image-canvas').evaluate(c => [c.width, c.height]), [80, 48]);
    await fresh(640, 360); await mkdir('test-results', { recursive: true });
    await page.screenshot({ path: `test-results/screenshot-editor-dpr${deviceScaleFactor}.png` });
    await page.emulateMedia({ colorScheme: 'dark' }); await page.setViewportSize({ width: 600, height: 540 });
    await page.screenshot({ path: `test-results/screenshot-editor-dark-narrow-dpr${deviceScaleFactor}.png` });
    assert.equal(await page.locator('body').evaluate(b => b.scrollWidth <= innerWidth), true);
    assert.deepEqual(await page.evaluate(() => Object.keys(localStorage)), [], 'no image data persisted in web storage');
    const commands = await page.evaluate(() => window.__screenshotQA.calls.map(x => x.command));
    assert.equal(commands.some(x => /ocr|translate|history|provider/i.test(x)), false, 'F1 editor never invokes OCR, translation, providers, or history');
    await context.close();
  }
  assert.deepEqual(errors, []); assert.deepEqual(externalRequests, []);
  console.log('PASS: dedicated screenshot editor DPR1/2, all annotation tools, Chinese IME/long text, true crop, pixel mosaic/opaque redaction, undo/redo, flattened copy/save, dialog cancellation, generation races, close/new session, malformed/oversized inputs, no OCR/network/history. Fake IPC only; native acceptance is separate.');
} finally { await browser.close(); }
