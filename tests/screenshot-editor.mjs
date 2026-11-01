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
      Object.defineProperty(navigator, 'platform', { configurable: true, get: () => 'Win32' });
      if (new URL(location.href).searchParams.has('fallbackDialog')) for (const name of ['showModal', 'close']) Object.defineProperty(HTMLDialogElement.prototype, name, { configurable: true, value: undefined });
      const callbacks = new Map(), listeners = new Map(), consumedActions = new Set(); let callbackId = 0, nextId = 0;
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
      const q = window.__screenshotQA = { image, calls: [], saves: [], copies: [], pins: [], closed: [], ready: [], session: image(), nextOpen: null, saveCancel: false,
        holdOpen: false, holdSave: false, releaseOpen: () => {}, releaseSave: () => {}, holdExport: false, releaseExport: () => {}, exportWaits: 0,
        emit: (event, payload) => listeners.get(event)?.({ event, id: 1, payload }),
        publish(width = 96, height = 64) { this.session = image(width, height); this.emit('screenshot-session', structuredClone(this.session)); return this.session.id; },
      };
      const replayAction = new URL(location.href).searchParams.get('initialActionReload');
      if (new URL(location.href).searchParams.has('failInitialCopy')) q.copyError = true;
      if (replayAction) q.session = { ...q.session, initialAction: replayAction === 'copy-failure' ? 'copy' : replayAction, overlay: { x: 30, y: 100, width: 192, height: 128, viewportWidth: innerWidth, viewportHeight: innerHeight } };
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
          q.calls.push({ command, sessionId: args.sessionId, revision: args.revision });
          if (command === 'update_screenshot_selection') {
            if (args.sessionId !== q.session.id || args.revision !== q.session.revision) throw new Error('stale selection');
            q.session = { kind: 'selection', id: q.session.id, revision: q.session.revision + 1,
              width: Math.round(args.rect.width * 2), height: Math.round(args.rect.height * 2), overlay: { ...q.session.overlay, ...args.rect } };
            return structuredClone(q.session);
          }
          if (command === 'capture_screenshot_selection') {
            if (args.sessionId !== q.session.id || args.revision !== q.session.revision) throw new Error('stale capture');
            const selected = structuredClone(q.session);
            if (q.holdSelectionCapture) await new Promise(resolve => { q.releaseSelectionCapture = resolve; });
            const bitmap = image(selected.width, selected.height);
            const value = { ...bitmap, kind: 'image', id: selected.id, revision: selected.revision, overlay: selected.overlay };
            if (q.session?.id === selected.id) q.session = value;
            return value;
          }

          if (command === 'get_screenshot_session') {
            const snapshot = structuredClone(q.session), mode = new URL(location.href).searchParams.get('startup');
            if (mode === 'cleared') q.emit('screenshot-session-cleared', { id: snapshot.id });
            if (mode === 'newer') q.publish(80, 48);
            return snapshot;
          }
          if (command === 'focus_screenshot_overlay') {
            if (q.holdFocus) await new Promise(resolve => { q.releaseFocus = resolve; });
            if (q.focusError) throw new Error('QA focus failed'); return;
          }
          if (command === 'screenshot_editor_ready') { q.ready.push(args.sessionId); if (q.holdReady) await new Promise(resolve => { q.releaseReady = resolve; }); return; }
          if (command === 'consume_screenshot_initial_action') {
            if (args.sessionId !== q.session.id) throw new Error('stale initial action');
            if (q.claimError) throw new Error('QA claim failed');
            const replayKey = 'qa-claimed-' + replayAction;
            if (consumedActions.has(args.sessionId) || replayAction && sessionStorage.getItem(replayKey)) return null;
            consumedActions.add(args.sessionId); if (replayAction) sessionStorage.setItem(replayKey, '1');
            return q.session.initialAction ?? null;
          }
          if (command === 'restart_screenshot_capture') { if (args.sessionId !== q.session.id) throw new Error('stale restart'); q.restarted = args.sessionId; q.closed.push(args.sessionId); q.emit('screenshot-session-cleared', { id: args.sessionId }); return; }
          if (command === 'open_screenshot_image') {
            if (q.openError) throw new Error('QA damaged local image');
            if (q.holdOpen) await new Promise(resolve => { q.releaseOpen = resolve; });
            if (!q.nextOpen) return null;
            q.session = q.nextOpen; q.nextOpen = null; q.emit('screenshot-session', structuredClone(q.session)); return structuredClone(q.session);
          }
          if (command === 'save_screenshot_image') {
            if (q.saveError) throw new Error('QA save failed');
            q.saves.push(structuredClone(args)); if (q.holdSave) await new Promise(resolve => { q.releaseSave = resolve; });
            return q.saveCancel ? null : { path: '/fixture/Desktop/EchoLingo-2026-10-31-120000.png', fileName: 'EchoLingo-2026-10-31-120000.png' };
          }
          if (command === 'pin_screenshot_image') {
            if (q.pinError) throw new Error('QA pin failed');
            q.pins.push(structuredClone(args));
            if (q.holdPin) await new Promise(resolve => { q.releasePin = resolve; }); return;
          }
          if (command === 'copy_screenshot_image') { if (q.copyError) throw new Error('QA copy failed'); q.copies.push(structuredClone(args)); return; }
          if (command === 'close_screenshot_editor') { if (q.closeError) throw new Error('QA close failed'); q.closed.push(args.sessionId); q.emit('screenshot-session-cleared', { id: args.sessionId }); return; }
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
      await page.locator(`.editor-toolbar button[data-tool="${tool}"]`).click();
      const bounds = await page.locator('#image-canvas').boundingBox();
      const size = await page.locator('#image-canvas').evaluate(c => [c.width, c.height]);
      const xy = p => [bounds.x + p[0] * bounds.width / size[0], bounds.y + p[1] * bounds.height / size[1]];
      await page.mouse.move(...xy(start)); await page.mouse.down(); await page.mouse.move(...xy(end), { steps: 3 }); await page.mouse.up();
    };
    // Opened files share the capture-style toolbar, without pretending to be a
    // native capture: keep file commands and their existing save/close lifecycle.
    assert.equal(await page.locator('body').getAttribute('data-compact-editor'), 'true');
    assert.equal(await page.locator('body').getAttribute('data-inplace'), 'false');
    assert.equal(await page.locator('.editor-header').isVisible(), false);
    assert.equal(await page.locator('.editor-footer').isVisible(), false);
    for (const id of ['open-image', 'pin-image', 'copy-image', 'save-image', 'save-as-image', 'close-editor']) {
      assert.equal(await page.locator(`.editor-toolbar #${id}`).isVisible(), true, `${id} remains in the one shared toolbar`);
    }
    assert.equal(await page.locator('#overlay-copy').isVisible(), false, 'file session does not gain capture completion semantics');
    assert.equal(await page.locator('#restart-selection').isVisible(), false);
    assert.equal(await page.locator('.tool-options').isVisible(), false, 'selection has no irrelevant style controls');
    assert.equal(await page.locator('#zoom-fit').isVisible(), false, 'zoom controls are secondary, not always expanded');
    await page.locator('#zoom-menu summary').click();
    assert.equal(await page.locator('#zoom-fit').isVisible(), true);
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#zoom-menu').getAttribute('open'), null);
    assert.equal(await page.locator('#discard-dialog').isVisible(), false, 'Escape closes zoom options, not the image');
    assert.equal(await page.locator('.editor-toolbar button[data-tool] svg.toolbar-icon').count(), 11, 'all primary tools use the same SVG icon family');
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
    await fresh(); await page.locator('.editor-toolbar button[data-tool="text"]').click();
    await page.locator('#image-canvas').click({ position: { x: 5, y: 5 } });
    assert.equal(await page.locator('#annotation-text').evaluate(input => document.activeElement === input && !input.closest('[hidden]')), true, 'the canvas click retains direct-input focus after native pointer defaults');
    await page.locator('#annotation-text').fill('中文标注\n<script>alert(1)</script>');
    await page.locator('#annotation-text').dispatchEvent('compositionstart');
    await page.locator('#annotation-text').dispatchEvent('keydown', { key: 'Enter', code: 'Enter', ctrlKey: true, isComposing: true, keyCode: 229 });
    assert.equal(await page.locator('#text-dialog').evaluate(d => !d.hidden), true);
    await page.locator('#annotation-text').dispatchEvent('keydown', { key: 'Escape', isComposing: true, keyCode: 229 });
    assert.equal(await page.locator('#text-dialog').evaluate(d => !d.hidden), true, 'IME Escape must not discard the text dialog');
    await page.locator('#annotation-text').dispatchEvent('keydown', { key: 'Escape', isComposing: true, keyCode: 229 });
    await page.locator('#annotation-text').dispatchEvent('compositionend');
    await page.locator('#annotation-text').dispatchEvent('keydown', { key: 'Escape' });
    assert.equal(await page.locator('#text-dialog').evaluate(d => !d.hidden), true, 'compositionend before the Escape default must retain text');
    await page.locator('#annotation-text').press('Control+Enter'); assert.equal(await page.locator('#text-dialog').evaluate(d => !d.hidden), false);
    assert.equal(await page.locator('#undo-edit').isEnabled(), true);
    await page.locator('.editor-toolbar button[data-tool="text"]').click(); await page.locator('#image-canvas').click({ position: { x: 5, y: 5 } });
    await page.locator('#annotation-text').fill('字'.repeat(2000)); assert.equal(await page.locator('#annotation-text').inputValue().then(x => x.length), 2000);
    await page.locator('#annotation-text').press('Escape');

    // Direct text lives at its image coordinate, without a separate form panel.
    await fresh(320, 240); const beforeDirectText = await pixels();
    await page.locator('[data-tool=text]').click();
    const directCanvas = await page.locator('#image-canvas').boundingBox();
    await page.locator('#image-canvas').click({ position: { x: 30, y: 40 } });
    const directInput = await page.locator('#annotation-text').boundingBox();
    assert.ok(Math.abs(directInput.x - directCanvas.x - 30) < 1 && Math.abs(directInput.y - directCanvas.y - 40) < 1, 'typing starts exactly at the clicked image point');
    assert.equal(await page.locator('#text-dialog button, #text-dialog small, #text-count').count(), 0, 'no popup-form actions, counter, or persistent instructions');
    assert.equal(await page.locator('#annotation-text').evaluate(input => getComputedStyle(input).backgroundColor), 'rgba(0, 0, 0, 0)');
    await page.locator('#annotation-text').fill('Direct typing');
    await page.locator('#annotation-text').press('Enter');
    await page.locator('#annotation-text').pressSequentially('Second line');
    assert.equal(await page.locator('#annotation-text').inputValue(), 'Direct typing\nSecond line');
    assert.deepEqual(await page.locator('#annotation-text').evaluate(input => ({ top: input.scrollTop, fits: input.scrollHeight <= input.clientHeight })), { top: 0, fits: true }, 'both direct-input lines are visible without a scrollbar shrinking the typing area');
    assert.equal(await page.locator('#annotation-text').evaluate(input => input.clientHeight <= Math.ceil(parseFloat(getComputedStyle(input).lineHeight) * 2) + 2), true, 'two short explicit lines do not acquire a spurious third line from a too-narrow auto width');
    const copiesDuringIME = await page.evaluate(() => window.__screenshotQA.copies.length);
    await page.locator('#annotation-text').dispatchEvent('compositionstart');
    await page.locator('#copy-image').click();
    assert.equal(await page.evaluate(() => window.__screenshotQA.copies.length), copiesDuringIME, 'outside copy cannot commit an active IME candidate');
    assert.equal(await page.locator('#annotation-text').isVisible(), true);
    await page.locator('#annotation-text').dispatchEvent('compositionend');
    await mkdir('test-results', { recursive: true });
    await page.screenshot({ path: `test-results/screenshot-editor-direct-text-dpr${deviceScaleFactor}.png` });
    await page.mouse.click(10, 10);
    assert.equal(await page.locator('#annotation-text').isVisible(), false, 'outside click naturally commits without an extra confirmation');
    assert.notDeepEqual(await pixels(), beforeDirectText);
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), beforeDirectText);

    // Delete while a drag is held must cancel the draft movement before index
    // removal; otherwise pointerup could overwrite the following annotation.
    await fresh(320, 240);
    await drag('rectangle', [20, 20], [70, 50]);
    const firstRectangle = await pixels();
    await drag('rectangle', [150, 100], [200, 140]);
    const bothRectangles = await pixels();
    await page.locator('[data-tool="select"]').click();
    const movingBounds = await page.locator('#image-canvas').boundingBox();
    const moveXY = (x, y) => [movingBounds.x + x * movingBounds.width / 320, movingBounds.y + y * movingBounds.height / 240];
    await page.mouse.move(...moveXY(25, 25)); await page.mouse.down(); await page.mouse.move(...moveXY(35, 35));
    await page.keyboard.press('Delete'); const deletionRaster = await pixels();
    await page.mouse.move(...moveXY(45, 45)); await page.mouse.up();
    assert.deepEqual(await pixels(), deletionRaster, 'late drag events cannot mutate the next object after deletion');
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), bothRectangles, 'one undo restores only the deleted object');
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), firstRectangle);

    // Freehand/highlight and ellipse use source pixels; one eraser gesture
    // changes only ink. Existing masks remain opaque in the final raster.
    await fresh(320, 240); const unmarked = await pixels();
    await page.locator('[data-tool=pen]').click(); await page.locator('#edit-color').fill('#dd2233');
    await drag('pen', [10, 40], [280, 40]); const painted = await pixels(); assert.notDeepEqual(painted, unmarked);
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), unmarked);
    await page.locator('#redo-edit').click(); assert.deepEqual(await pixels(), painted);
    const cancelInkBounds = await page.locator('#image-canvas').boundingBox();
    await page.mouse.move(cancelInkBounds.x + 20, cancelInkBounds.y + 100); await page.mouse.down(); await page.mouse.move(cancelInkBounds.x + 80, cancelInkBounds.y + 100);
    await page.keyboard.press('Escape'); await page.mouse.up(); assert.deepEqual(await pixels(), painted, 'cancelled ink preview never enters history or export');
    await page.mouse.move(cancelInkBounds.x + 20, cancelInkBounds.y + 100); await page.mouse.down(); await page.mouse.move(cancelInkBounds.x + 80, cancelInkBounds.y + 100);
    await page.locator('#image-canvas').dispatchEvent('contextlost');
    for (const button of ['#copy-image', '#save-image', '#pin-image']) assert.equal(await page.locator(button).isDisabled(), true, 'lost context cannot export an in-flight ink preview');
    await page.mouse.up();
    await page.locator('#undo-edit').click();
    assert.equal(await page.locator('#copy-image').isDisabled(), true, 'history navigation cannot rearm export before context restoration');
    await page.locator('#image-canvas').dispatchEvent('contextrestored');
    assert.deepEqual(await pixels(), unmarked, 'restoration replays committed history, never the interrupted ink');
    await page.locator('#redo-edit').click(); assert.deepEqual(await pixels(), painted);
    await drag('highlight', [10, 80], [280, 80]);
    await page.locator('[data-tool="rectangle"]').click(); await page.locator('#shape-style').selectOption('ellipse');
    await drag('rectangle', [50, 130], [150, 190]);
    await page.locator('#shape-style').selectOption('rectangle');
    await page.locator('[data-tool=solid]').click(); await page.locator('#edit-color').fill('#112233'); await drag('solid', [30, 20], [60, 100]);
    const inkAndMask = await pixels();
    await drag('eraser', [100, 20], [100, 100]); const erasedInk = await pixels(); assert.notDeepEqual(erasedInk, inkAndMask);
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), inkAndMask);
    await page.locator('#redo-edit').click(); assert.deepEqual(await pixels(), erasedInk);
    await drag('eraser', [45, 20], [45, 100]);
    const privacyPixel = await page.locator('#image-canvas').evaluate(c => [...c.getContext('2d').getImageData(45, 40, 1, 1).data]);
    assert.deepEqual(privacyPixel, [17, 34, 51, 255], 'local ink eraser never removes privacy mask');

    // New annotation interactions use a nonmodal inline editor and one shared
    // history. Coordinates are source pixels at both DPRs, not CSS pixel guesses.
    await fresh(320, 240);
    const clickImage = async (x, y, count = 1) => {
      const b = await page.locator('#image-canvas').boundingBox();
      const [w, h] = await page.locator('#image-canvas').evaluate(c => [c.width, c.height]);
      await page.mouse.click(b.x + x * b.width / w, b.y + y * b.height / h, { clickCount: count });
    };
    await page.locator('[data-tool="text"]').click();
    await page.locator('#edit-font-size').selectOption('16');
    await page.locator('#note-style').selectOption('#fff3b0');
    await clickImage(20, 20); await page.locator('#annotation-text').fill('说明 A');
    assert.equal(await page.locator('.screenshot-modal-backdrop').count(), 0);
    await page.keyboard.press('Control+Enter');
    const notePixels = await pixels();
    await drag('select', [25, 25], [75, 65]);
    const movedNote = await pixels(); assert.notDeepEqual(movedNote, notePixels, 'move changes the existing note');
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), notePixels, 'move is one undo step');
    await page.locator('#redo-edit').click(); assert.deepEqual(await pixels(), movedNote);
    await clickImage(75, 65, 2);
    assert.equal(await page.locator('#annotation-text').inputValue(), '说明 A');
    await page.locator('#annotation-text').fill('说明 B'); await page.keyboard.press('Control+Enter');
    const editedNote = await pixels(); assert.notDeepEqual(editedNote, movedNote);
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), movedNote, 'text edit replaces instead of painting a second layer');
    await page.locator('#redo-edit').click(); assert.deepEqual(await pixels(), editedNote);
    await page.locator('[data-tool="select"]').click(); await clickImage(75, 65);
    await page.keyboard.press('Delete'); assert.notDeepEqual(await pixels(), editedNote);
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), editedNote, 'delete is reversible');

    await page.locator('[data-tool="number"]').click();
    await page.locator('#edit-font-size').selectOption('32');
    await clickImage(45, 150); const oneStep = await pixels();
    await clickImage(95, 150); const twoSteps = await pixels();
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), oneStep);
    await page.locator('#redo-edit').click(); assert.deepEqual(await pixels(), twoSteps);
    await page.locator('#step-style').selectOption('numbered-arrow');
    await drag('number', [170, 100], [250, 170]);
    const stepArrow = await pixels();
    await drag('select', [170, 100], [190, 115]);
    const movedArrow = await pixels(); assert.notDeepEqual(movedArrow, stepArrow);
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), stepArrow, 'badge and arrow move atomically');
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), twoSteps, 'badge and arrow creation is one undo step');
    await page.locator('#redo-edit').click();
    await drag('crop', [10, 10], [300, 220]);
    const afterCrop = await pixels(); assert.deepEqual([afterCrop.width, afterCrop.height], [290, 210]);
    await drag('select', [160, 90], [170, 95]);
    assert.notDeepEqual(await pixels(), afterCrop, 'annotations remain selectable in crop-adjusted coordinates');
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), afterCrop);
    await page.locator('[data-tool=solid]').click(); await page.locator('#edit-color').fill('#112233'); await drag('solid', [0, 0], [25, 25]);
    const finalAnnotations = await pixels();
    for (const [button, collection] of [['#copy-image', 'copies'], ['#save-image', 'saves'], ['#pin-image', 'pins']]) {
      const before = await page.evaluate(collection => window.__screenshotQA[collection].length, collection);
      await page.locator(button).click();
      await page.waitForFunction(([collection, before]) => window.__screenshotQA[collection].length > before, [collection, before]);
      const raster = await page.evaluate(async collection => {
        const image = new Image(); image.src = 'data:image/png;base64,' + window.__screenshotQA[collection].at(-1).pngBase64; await image.decode();
        const c = document.createElement('canvas'); c.width = image.width; c.height = image.height; const ctx = c.getContext('2d'); ctx.drawImage(image, 0, 0);
        return { width: c.width, height: c.height, data: [...ctx.getImageData(0, 0, c.width, c.height).data] };
      }, collection);
      assert.deepEqual(raster, finalAnnotations, collection + ' contains the same flattened annotations/crop/mask');
    }

    // Clicking outside text commits it; cancelling Close retains that unsaved annotation.
    await page.locator('[data-tool="text"]').click(); await clickImage(100, 30);
    await page.locator('#annotation-text').fill('尚未提交的备注');
    assert.equal(await page.locator('#save-indicator').textContent(), '未保存');
    const closeBeforeCommit = await page.locator('#close-editor').boundingBox();
    await page.mouse.move(closeBeforeCommit.x + closeBeforeCommit.width / 2, closeBeforeCommit.y + closeBeforeCommit.height / 2);
    await page.mouse.down();
    assert.deepEqual(await page.locator('#close-editor').boundingBox(), closeBeforeCommit, 'outside text commit cannot move the intended action before pointerup');
    await page.mouse.up();
    assert.equal(await page.locator('#discard-dialog').isVisible(), true);
    await page.locator('#discard-cancel').click();
    assert.equal(await page.locator('#annotation-text').isVisible(), false);
    assert.notDeepEqual(await pixels(), finalAnnotations, 'cancelling Close retains the text committed by its outside click');
    assert.equal(await page.locator('#save-indicator').textContent(), '未保存');
    await page.locator('#undo-edit').click();
    assert.deepEqual(await pixels(), finalAnnotations, 'one undo returns to the exact previously saved raster');
    assert.equal(await page.locator('#save-indicator').textContent(), '已保存');

    // Mosaic modifies actual pixels; solid masks replace RGB and alpha fully.
    await fresh(); await drag('mosaic', [8, 8], [24, 24]);
    const mosaicked = await pixels(), at = (image, x, y) => image.data.slice((y * image.width + x) * 4, (y * image.width + x) * 4 + 4);
    assert.deepEqual(at(mosaicked, 8, 8), at(mosaicked, 23, 23));
    assert.notDeepEqual(at(mosaicked, 8, 8), at(original, 8, 8));
    assert.deepEqual(at(mosaicked, 24, 24), at(original, 24, 24));
    await page.locator('[data-tool=solid]').click(); await page.locator('#edit-color').fill('#112233'); await drag('solid', [0, 0], [8, 8]);
    const masked = await pixels(); assert.deepEqual(at(masked, 1, 1), [17, 34, 51, 255]);

    // Crop after zoom uses image coordinates, reduces actual PNG dimensions and
    // exposes no crop-excluded pixels. DPR changes display density, not output.
    const cropSessionId = await fresh(); await page.locator('#zoom-menu summary').click(); await page.locator('#zoom-in').click();
    await drag('crop', [10, 8], [42, 32]);
    const crop = await pixels(); assert.deepEqual([crop.width, crop.height], [32, 24]);
    assert.deepEqual(at(crop, 0, 0), at(original, 10, 8));
    await page.locator('#undo-edit').click(); assert.deepEqual(await pixels(), original);
    await page.locator('#redo-edit').click();
    const copiesBeforeCrop = await page.evaluate(() => window.__screenshotQA.copies.length);
    await page.locator('#copy-image').click();
    await page.waitForFunction(([count, id]) => window.__screenshotQA.copies.length === count + 1 && window.__screenshotQA.copies.at(-1).sessionId === id, [copiesBeforeCrop, cropSessionId]);
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
    assert.deepEqual(Object.keys(saved).sort(), ['pngBase64', 'revision', 'saveAs', 'sessionId']);
    assert.equal(saved.revision, 0, 'ordinary file export carries the initial revision without exposing source paths');

    // Backend-normalized local image delivery may arrive both as an event and
    // the Open return value; install only once, reset history, retain on failure.
    const importedId = await page.evaluate(() => { const q = window.__screenshotQA; q.nextOpen = { ...q.image(40, 30), sourceName: 'generated-local.jpg' }; return q.nextOpen.id; });
    await page.locator('#open-image').click();
    await page.waitForFunction(id => window.__screenshotQA.ready.includes(id), importedId);
    assert.deepEqual(await page.locator('#image-canvas').evaluate(c => [c.width, c.height]), [40, 30]);
    assert.equal(await page.evaluate(id => window.__screenshotQA.ready.filter(value => value === id).length, importedId), 1);
    assert.equal(await page.locator('#undo-edit').isDisabled(), true);
    const importedPixels = await pixels();
    await page.evaluate(() => { window.__screenshotQA.openError = true; });
    await page.locator('#open-image').click(); await page.locator('#discard-confirm').click();
    await page.getByText('无法打开图片：QA damaged local image', { exact: true }).waitFor();
    assert.deepEqual(await pixels(), importedPixels);
    await page.evaluate(() => { window.__screenshotQA.openError = false; });

    // Fail closed if pixel redaction/crop throws after the original was drawn.
    // Never export the unredacted/partial canvas; undo can recover safely.
    for (const tool of ['mosaic', 'crop']) {
      await fresh();
      const before = await page.evaluate(() => { const q = window.__screenshotQA; q.failPixelRead = true; return [q.saves.length, q.copies.length]; });
      await drag(tool, [8, 8], [24, 24]);
      await page.waitForFunction(() => document.querySelector('#editor-status').dataset.error === 'true');
      assert.equal(await page.locator('#save-image').isDisabled(), true);
      assert.equal(await page.locator('#copy-image').isDisabled(), true);
      assert.equal(await page.locator('#pin-image').isDisabled(), true);
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
      assert.equal(await page.locator('#pin-image').isDisabled(), true);

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
    // The shipped minimum OS predates native <dialog> support in WebKit.
    // Exercise the fallback, including focus containment and Escape cancellation.
    await page.goto(new URL('screenshot.html?fallbackDialog=1', base).href);
    await page.waitForFunction(() => window.__screenshotQA.ready.length === 1);
    await page.locator('.editor-toolbar button[data-tool="text"]').click(); await page.locator('#image-canvas').click({ position: { x: 5, y: 5 } });
    await page.locator('#annotation-text').fill('兼容旧版系统 WebView');
    assert.equal(await page.locator('.screenshot-modal-backdrop').count(), 0, 'inline annotation does not create a modal backdrop');
    await page.locator('#annotation-text').press('Escape'); assert.equal(await page.locator('#text-dialog').isVisible(), false);
    await page.locator('#close-editor').click(); await page.keyboard.press('Escape');
    assert.equal(await page.evaluate(() => window.__screenshotQA.closed.length), 0);
    await page.locator('#close-editor').click(); await page.locator('#discard-confirm').click();
    await page.waitForFunction(() => window.__screenshotQA.closed.length === 1);

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
    assert.deepEqual(await page.locator('.tool-group button').evaluateAll(buttons => buttons.filter(button => {
      const rect = button.getBoundingClientRect();
      return rect.left < 0 || rect.right > innerWidth;
    }).map(button => button.dataset.tool)), [], 'all annotation tools remain within the narrow editor, not merely clipped');
    assert.deepEqual(await page.evaluate(() => Object.keys(localStorage)), [], 'no image data persisted in web storage');
    const commands = await page.evaluate(() => window.__screenshotQA.calls.map(x => x.command));
    assert.equal(commands.some(x => /ocr|translate|history|provider/i.test(x)), false, 'F1 editor never invokes OCR, translation, providers, or history');
    // F1 in-place presentation reuses the renderer without an activation or
    // clipboard side effect. Coordinates are CSS/logical; output stays pixels.
    const overlayFresh = async (geometry = { x: 24, y: 100, width: 192, height: 128, viewportWidth: 600, viewportHeight: 540 }) => {
      const id = await page.evaluate(overlay => {
        const q = window.__screenshotQA;
        q.copyError = q.saveError = q.saveCancel = q.closeError = false;
        q.session = { ...q.image(), overlay };
        q.emit('screenshot-session', structuredClone(q.session)); return q.session.id;
      }, geometry);
      await page.waitForFunction(id => window.__screenshotQA.ready.includes(id), id);
      return id;
    };
    const beforeOverlay = await page.evaluate(() => ({ copies: window.__screenshotQA.copies.length, saves: window.__screenshotQA.saves.length }));
    let overlayId = await overlayFresh();
    assert.equal(await page.evaluate(() => window.__screenshotQA.calls.filter(call => call.command === 'focus_screenshot_overlay').length), 0, 'capture ready never requests activation');
    await page.evaluate(() => { window.__screenshotQA.holdFocus = true; });
    const beforeFocus = await page.evaluate(() => window.__screenshotQA.calls.length);
    await page.locator('.editor-toolbar button[data-tool="rectangle"]').click();
    const initialOverlay = await pixels();
    await drag('rectangle', [5, 5], [25, 20]);
    assert.notDeepEqual(await pixels(), initialOverlay, 'pending focus never delays pointer drawing');
    assert.equal(await page.evaluate(start => window.__screenshotQA.calls.slice(start).filter(call => call.command === 'focus_screenshot_overlay').length, beforeFocus), 1, 'tool and canvas clicks share one pending focus');
    await page.evaluate(() => { window.__screenshotQA.holdFocus = false; window.__screenshotQA.releaseFocus(); });
    await page.locator('#undo-edit').click();
    await page.locator('.editor-toolbar button[data-tool="select"]').click();
    assert.equal(await page.locator('.editor-toolbar button[data-tool="select"]').getAttribute('aria-pressed'), 'true', 'capture starts without an annotation tool');
    await drag('crop', [10, 8], [42, 32]);
    assert.deepEqual(await page.locator('#image-canvas').boundingBox().then(({ x, y, width, height }) => [x, y, width, height]), [44, 116, 64, 48], 'cropped bitmap retains original screen-local origin and scale');
    await page.locator('#undo-edit').click();
    await page.locator('.editor-toolbar button[data-tool="select"]').click();
    await page.locator('#image-canvas').focus(); await page.keyboard.press('Control+Shift+s');
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent === '原地截图使用设置中的保存目录；请在设置修改目录');
    assert.equal(await page.evaluate(() => window.__screenshotQA.saves.length), beforeOverlay.saves, 'in-place Save As cannot open a separate native sheet');
    const overlayPixels = await pixels();
    assert.equal(await page.locator('.editor-header').isVisible(), false);
    assert.equal(await page.locator('.editor-toolbar button[data-tool="select"]').getAttribute('aria-pressed'), 'true');
    assert.deepEqual(await page.locator('#image-canvas').boundingBox().then(({ x, y, width, height }) => [x, y, width, height]), [24, 100, 192, 128]);
    await page.locator('#image-canvas').click({ position: { x: 30, y: 30 } });
    assert.deepEqual(await pixels(), overlayPixels, 'default selection tool never annotates');
    assert.deepEqual(await page.evaluate(() => ({ copies: window.__screenshotQA.copies.length, saves: window.__screenshotQA.saves.length })), beforeOverlay);
    await drag('solid', [8, 8], [24, 24]);
    const editedOverlay = await pixels();
    await page.evaluate(() => { window.__screenshotQA.copyError = true; });
    await page.locator('#overlay-copy').click();
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('QA copy failed'));
    assert.deepEqual(await pixels(), editedOverlay, 'copy failure retains edits');
    assert.equal(await page.locator('#overlay-copy').isEnabled(), true);
    await page.evaluate(() => { window.__screenshotQA.copyError = false; window.__screenshotQA.closeError = true; });
    await page.locator('#image-canvas').focus(); await page.keyboard.press('Enter');
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('图片已复制到剪贴板；退出失败'));
    assert.deepEqual(await pixels(), editedOverlay, 'dismissal failure retains the edited document');
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), overlayId), false);
    await page.evaluate(() => { window.__screenshotQA.closeError = false; });
    await page.locator('#overlay-cancel').click();
    await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    assert.equal(await page.evaluate(() => window.__screenshotQA.copies.length), beforeOverlay.copies + 1);
    const exported = await page.evaluate(async () => {
      const q = window.__screenshotQA, image = new Image(); image.src = 'data:image/png;base64,' + q.copies.at(-1).pngBase64; await image.decode();
      const canvas = document.createElement('canvas'); canvas.width = image.width; canvas.height = image.height; const ctx = canvas.getContext('2d'); ctx.drawImage(image, 0, 0);
      return [...ctx.getImageData(0, 0, canvas.width, canvas.height).data];
    });
    assert.deepEqual(exported, editedOverlay.data, 'completion exports only flattened edited pixels');
    overlayId = await overlayFresh();
    await page.locator('.editor-toolbar button[data-tool="text"]').click(); await page.locator('#image-canvas').click({ position: { x: 8, y: 8 } });
    await page.locator('#annotation-text').fill('中文');
    await page.locator('#annotation-text').dispatchEvent('compositionstart');
    await page.evaluate(id => { const q = window.__screenshotQA; q.emit('screenshot-overlay-key', { sessionId: id, key: 'Enter' }); q.emit('screenshot-overlay-key', { sessionId: id, key: 'Escape' }); }, overlayId);
    assert.equal(await page.locator('#text-dialog').isVisible(), true);
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), overlayId), false);
    assert.equal(await page.evaluate(id => window.__screenshotQA.calls.filter(call => call.command === 'focus_screenshot_overlay' && call.sessionId === id).length, overlayId), 1, 'text awaits the session focus without duplicate IPC');
    await page.locator('#annotation-text').dispatchEvent('compositionend');
    await page.keyboard.press('Enter'); assert.equal(await page.locator('#text-dialog').isVisible(), true, 'textarea Enter is a newline, not completion');
    await page.locator('#annotation-text').press('Escape');
    await page.evaluate(() => { window.__screenshotQA.saveError = true; });
    await page.locator('#overlay-save').click();
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('QA save failed'));
    assert.equal(await page.locator('#canvas-frame').isVisible(), true);
    await page.evaluate(() => { window.__screenshotQA.saveError = false; window.__screenshotQA.saveCancel = true; });
    await page.locator('#overlay-save').click();
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('已取消保存'));
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), overlayId), false);
    await page.evaluate(() => { window.__screenshotQA.saveCancel = false; window.__screenshotQA.closeError = true; });
    await page.locator('#overlay-save').click();
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('图片已保存：') && document.querySelector('#editor-status').textContent.includes('退出失败'));
    assert.equal(await page.locator('#save-indicator').textContent(), '已保存');
    assert.equal(await page.locator('#canvas-frame').isVisible(), true);
    const savedOnce = await page.evaluate(() => window.__screenshotQA.saves.length);
    await page.evaluate(() => { window.__screenshotQA.closeError = false; });
    await page.locator('#overlay-cancel').click(); await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    assert.equal(await page.evaluate(() => window.__screenshotQA.saves.length), savedOnce, 'retrying close never repeats the completed save');
    overlayId = await overlayFresh({ x: 398, y: 402, width: 192, height: 128, viewportWidth: 600, viewportHeight: 540 });
    const toolbarBox = await page.locator('.editor-toolbar').boundingBox();
    assert.ok(toolbarBox.x >= 0 && toolbarBox.y >= 0 && toolbarBox.x + toolbarBox.width <= 600 && toolbarBox.y + toolbarBox.height <= 540, JSON.stringify(toolbarBox));
    const beforeDiscard = await page.evaluate(() => [window.__screenshotQA.copies.length, window.__screenshotQA.saves.length]);
    await page.evaluate(id => window.__screenshotQA.emit('screenshot-overlay-key', { sessionId: id - 1, key: 'Escape' }), overlayId);
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), overlayId), false, 'stale native keys cannot close a newer capture');
    await page.locator('#overlay-cancel').click(); await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    assert.equal(await page.locator('#discard-dialog').isVisible(), false, 'explicit X discards without a second prompt');
    assert.deepEqual(await page.evaluate(() => [window.__screenshotQA.copies.length, window.__screenshotQA.saves.length]), beforeDiscard, 'discard never copies or writes/deletes a file');
    overlayId = await overlayFresh();
    await page.locator('#image-canvas').focus(); await page.keyboard.press('Escape');
    await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    assert.deepEqual(await page.evaluate(() => [window.__screenshotQA.copies.length, window.__screenshotQA.saves.length]), beforeDiscard);
    overlayId = await overlayFresh();
    await page.evaluate(id => window.__screenshotQA.emit('screenshot-overlay-key', { sessionId: id, key: 'Enter' }), overlayId);
    await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    overlayId = await overlayFresh();
    await page.evaluate(() => { window.__screenshotQA.focusError = true; });
    const focusPixels = await pixels();
    await page.locator('.editor-toolbar button[data-tool="rectangle"]').click();
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('QA focus failed'));
    assert.deepEqual(await pixels(), focusPixels);
    await page.evaluate(() => { window.__screenshotQA.focusError = false; });
    await page.locator('.editor-toolbar button[data-tool="select"]').click();
    assert.equal(await page.evaluate(id => window.__screenshotQA.calls.filter(call => call.command === 'focus_screenshot_overlay' && call.sessionId === id).length, overlayId), 2, 'failed explicit focus can retry');
    await page.locator('#overlay-cancel').click(); await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    // Pin exports only the rendered/redacted bitmap, never copies/saves, and
    // must not dismiss until the independent window has acknowledged readiness.
    overlayId = await overlayFresh();
    await page.locator('[data-tool=solid]').click(); await page.locator('#edit-color').fill('#112233');
    await drag('solid', [0, 0], [32, 24]);
    const pinPixels = await pixels();
    const beforePin = await page.evaluate(() => [window.__screenshotQA.copies.length, window.__screenshotQA.saves.length]);
    await page.evaluate(() => { window.__screenshotQA.pinError = true; });
    await page.locator('#overlay-pin').click();
    await page.getByText(/QA pin failed/).waitFor();
    assert.deepEqual(await pixels(), pinPixels, 'failed pin preserves edits');
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), overlayId), false);
    await page.evaluate(() => { window.__screenshotQA.pinError = false; window.__screenshotQA.holdPin = true; });
    const pinsBefore = await page.evaluate(() => window.__screenshotQA.pins.length);
    await page.locator('#overlay-pin').click();
    await page.waitForFunction(n => window.__screenshotQA.pins.length === n + 1, pinsBefore);
    assert.equal(await page.locator('#overlay-pin').isDisabled(), true);
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), overlayId), false, 'pending ready keeps editor');
    const exportedPin = await page.evaluate(async () => {
      const img = new Image(); img.src = 'data:image/png;base64,' + window.__screenshotQA.pins.at(-1).pngBase64; await img.decode();
      const canvas = document.createElement('canvas'); canvas.width = img.naturalWidth; canvas.height = img.naturalHeight;
      const ctx = canvas.getContext('2d'); ctx.drawImage(img, 0, 0);
      return { width: canvas.width, height: canvas.height, data: [...ctx.getImageData(0, 0, canvas.width, canvas.height).data] };
    });
    assert.deepEqual(exportedPin, pinPixels);
    await page.evaluate(() => { window.__screenshotQA.holdPin = false; window.__screenshotQA.releasePin(); });
    await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    assert.deepEqual(await page.evaluate(() => [window.__screenshotQA.copies.length, window.__screenshotQA.saves.length]), beforePin);
    // A superseded pin completion may never dismiss the new capture.
    overlayId = await overlayFresh();
    await page.evaluate(() => { window.__screenshotQA.holdPin = true; });
    await page.locator('#overlay-pin').click();
    await page.waitForFunction(id => window.__screenshotQA.pins.at(-1)?.sessionId === id, overlayId);
    const newerPinId = await overlayFresh();
    await page.evaluate(() => { window.__screenshotQA.holdPin = false; window.__screenshotQA.releasePin(); });
    await page.waitForTimeout(40);
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), newerPinId), false);
    await page.locator('#overlay-cancel').click();
    for (const action of ['#overlay-copy', '#overlay-cancel', '#overlay-save', '#overlay-pin']) {
      overlayId = await overlayFresh(); await page.locator(action).click();
      await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
      assert.equal(await page.evaluate(id => window.__screenshotQA.calls.filter(call => call.command === 'focus_screenshot_overlay' && call.sessionId === id).length, overlayId), 0, `${action} must not activate before completion`);
    }
    // Monitor-local edges/corners, tiny selections and compact wrapping. DPR
    // coverage comes from this suite's outer 1x/2x loop; no pixel screenshots.
    const placementCases = [
      { viewport: [600, 540], roi: { x: 300, y: 530, width: 1, height: 1 }, monitor: { x: 300, y: 0, width: 300, height: 540 } },
      { viewport: [600, 540], roi: { x: 599, y: 0, width: 1, height: 1 }, monitor: { x: 300, y: 0, width: 300, height: 540 } },
      { viewport: [600, 540], roi: { x: 0, y: 0, width: 1, height: 1 }, monitor: { x: -40, y: -20, width: 340, height: 560 } },
      { viewport: [220, 340], roi: { x: 219, y: 339, width: 1, height: 1 } },
      { viewport: [220, 340], roi: { x: 0, y: 0, width: 220, height: 340 } },
    ];
    for (const fixture of placementCases) {
      const [width, height] = fixture.viewport; await page.setViewportSize({ width, height });
      overlayId = await overlayFresh({ ...fixture.roi, viewportWidth: width, viewportHeight: height, ...(fixture.monitor ? { toolbarBounds: fixture.monitor } : {}) });
      await page.locator('.editor-toolbar button[data-tool="text"]').click(); // reveal the variable-size options
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const layout = await page.evaluate(() => {
        const rect = element => { const r = element.getBoundingClientRect(); return { x: r.x, y: r.y, right: r.right, bottom: r.bottom }; };
        return { boxes: ['.editor-toolbar', '#overlay-info', '#editor-status'].map(selector => document.querySelector(selector)).filter(element => !element.hidden).map(rect),
          actions: ['#overlay-copy', '#overlay-cancel', '#overlay-save', '#overlay-pin'].map(selector => {
            const button = document.querySelector(selector), r = button.getBoundingClientRect(), hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
            return { selector, ...rect(button), clickable: !button.disabled && (hit === button || button.contains(hit)) };
          }) };
      });
      const monitor = fixture.monitor ?? { x: 0, y: 0, width, height };
      const left = Math.max(0, monitor.x), top = Math.max(0, monitor.y), right = Math.min(width, monitor.x + monitor.width), bottom = Math.min(height, monitor.y + monitor.height);
      for (const box of [...layout.boxes, ...layout.actions]) {
        assert.ok(box.x >= left - 1 && box.y >= top - 1 && box.right <= right + 1 && box.bottom <= bottom + 1, JSON.stringify({ fixture, layout }));
      }
      assert.ok(layout.actions.every(action => action.clickable), JSON.stringify({ fixture, layout }));
      if (fixture.roi.y >= height - 10) assert.ok(layout.boxes[0].bottom < fixture.roi.y, 'bottom-edge toolbar flips above');
      await page.locator('#overlay-cancel').click(); await page.waitForFunction(id => window.__screenshotQA.closed.includes(id), overlayId);
    }
    // Restore the regular monitor after the 220px edge-placement fixtures.
    // The following native intents use a 192px selection at x=30; carrying the
    // tiny viewport forward correctly fails the production geometry guard.
    await page.setViewportSize({ width: 600, height: 540 });
    // Native adjusted selection transfers an intent, never an extra confirm step.
    // A duplicate durable snapshot/event cannot copy/save/pin twice.
    for (const [initialAction, collection] of [['copy', 'copies'], ['save', 'saves'], ['pin', 'pins']]) {
      const before = await page.evaluate(collection => window.__screenshotQA[collection].length, collection);
      const id = await page.evaluate(initialAction => {
        const q = window.__screenshotQA; q.copyError = q.saveError = q.pinError = q.closeError = q.saveCancel = false;
        q.session = { ...q.image(), overlay: { x: 30, y: 100, width: 192, height: 128, viewportWidth: innerWidth, viewportHeight: innerHeight }, initialAction };
        q.emit('screenshot-session', structuredClone(q.session)); q.emit('screenshot-session', structuredClone(q.session)); return q.session.id;
      }, initialAction);
      await page.waitForFunction(([id, collection, before]) => window.__screenshotQA.closed.includes(id) && window.__screenshotQA[collection].length === before + 1, [id, collection, before]);
    }
    const beforeStale = await page.evaluate(() => window.__screenshotQA.copies.length);
    const heldId = await page.evaluate(() => {
      const q = window.__screenshotQA; q.holdReady = true;
      q.session = { ...q.image(), overlay: { x: 30, y: 100, width: 192, height: 128, viewportWidth: innerWidth, viewportHeight: innerHeight }, initialAction: 'copy' };
      q.emit('screenshot-session', structuredClone(q.session)); return q.session.id;
    });
    await page.waitForFunction(id => window.__screenshotQA.ready.includes(id), heldId);
    await page.evaluate(() => { window.__screenshotQA.holdReady = false; });
    await fresh(); await page.evaluate(() => window.__screenshotQA.releaseReady());
    await page.waitForTimeout(30); assert.equal(await page.evaluate(() => window.__screenshotQA.copies.length), beforeStale, 'stale initial intent never exports a replacement session');
    overlayId = await page.evaluate(() => {
      const q = window.__screenshotQA; q.session = { ...q.image(), overlay: { x: 30, y: 100, width: 192, height: 128, viewportWidth: innerWidth, viewportHeight: innerHeight }, initialAction: 'pen' };
      q.emit('screenshot-session', structuredClone(q.session)); return q.session.id;
    });
    await page.waitForFunction(id => window.__screenshotQA.ready.includes(id), overlayId);
    await page.waitForFunction(() => document.querySelector('[data-tool="pen"]').getAttribute('aria-pressed') === 'true');
    assert.equal(await page.locator('#overlay-info').textContent(), '96 × 64');
    assert.equal(await page.locator('#editor-status').isVisible(), false, 'no permanent annotation-stage hint or empty status bubble');
    await drag('pen', [10, 20], [80, 20]);
    await page.locator('#restart-selection').click(); await page.locator('#discard-cancel').click();
    assert.equal(await page.evaluate(() => window.__screenshotQA.restarted), undefined, 'cancel reselect keeps image');
    await page.locator('#restart-selection').click(); await page.locator('#discard-confirm').click();
    await page.waitForFunction(id => window.__screenshotQA.restarted === id, overlayId);
    assert.equal(await page.evaluate(() => window.__screenshotQA.copies.length), beforeStale, 'reselect never copies');
    const failedClaimId = await page.evaluate(() => {
      const q = window.__screenshotQA; q.claimError = true;
      q.session = { ...q.image(), overlay: { x: 30, y: 100, width: 192, height: 128, viewportWidth: innerWidth, viewportHeight: innerHeight }, initialAction: 'copy' };
      q.emit('screenshot-session', structuredClone(q.session)); return q.session.id;
    });
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('QA claim failed'));
    assert.equal(await page.locator('#canvas-frame').isVisible(), true, 'claim failure retains an editable image');
    assert.equal(await page.locator('#overlay-copy').isEnabled(), true, 'claim failure offers explicit manual completion');
    assert.equal(await page.evaluate(id => window.__screenshotQA.closed.includes(id), failedClaimId), false);
    await page.evaluate(() => { window.__screenshotQA.claimError = false; });
    await page.locator('#overlay-cancel').click();
    await page.goto(new URL('screenshot.html?initialActionReload=copy-failure&failInitialCopy=1', base).href);
    await page.waitForFunction(() => document.querySelector('#editor-status').textContent.includes('QA copy failed'));
    await page.reload();
    await page.waitForFunction(() => window.__screenshotQA.calls.some(x => x.command === 'consume_screenshot_initial_action'));
    await page.waitForTimeout(30);
    assert.equal(await page.evaluate(() => window.__screenshotQA.calls.filter(x => x.command === 'copy_screenshot_image').length), 0, 'failed claimed export is not automatically retried by reload');
    await page.goto(new URL('screenshot.html?initialActionReload=copy', base).href);
    await page.waitForFunction(() => window.__screenshotQA.copies.length === 1);
    await page.reload();
    await page.waitForFunction(() => window.__screenshotQA.calls.some(x => x.command === 'consume_screenshot_initial_action'));
    await page.waitForTimeout(30); assert.equal(await page.evaluate(() => window.__screenshotQA.copies.length), 0, 'backend consumed action is not repeated after WebView reload');
    // Geometry-only capture uses the exact same toolbar DOM before and after
    // first paint. Tool choice never captures or removes adjustment handles.
    await page.evaluate(() => {
      const q = window.__screenshotQA;
      q.publishSelection = () => {
        const next = q.image(400, 240);
        q.session = { kind: 'selection', id: next.id, revision: 0, width: 400, height: 240,
          overlay: { x: 120, y: 150, width: 200, height: 120, viewportWidth: innerWidth, viewportHeight: innerHeight } };
        q.emit('screenshot-session', structuredClone(q.session));
      };
      q.publishSelection(); window.__sameToolbar = document.querySelector('.editor-toolbar');
    });
    await page.waitForFunction(() => !document.querySelector('#selection-handles').hidden);
    const geometryCalls = () => page.evaluate(() => window.__screenshotQA.calls.filter(x => x.command === 'capture_screenshot_selection').length);
    const beforeGeometry = await geometryCalls();
    await page.locator('[data-tool="pen"]').click();
    assert.equal(await geometryCalls(), beforeGeometry, 'selecting a tool does not freeze/capture the selection');
    assert.equal(await page.locator('#selection-handles').isVisible(), true);
    let handle = await page.locator('[data-resize="se"]').boundingBox();
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2); await page.mouse.down();
    await page.mouse.move(handle.x + handle.width / 2 + 60, handle.y + handle.height / 2 + 30);
    await page.keyboard.press('Enter');
    assert.equal(await geometryCalls(), beforeGeometry, 'Enter during held selection resize cannot capture backend old bounds');
    await page.mouse.up();
    await page.waitForFunction(() => window.__screenshotQA.session.revision === 1 && !document.querySelector('[data-tool="pen"]').disabled);
    assert.equal(await page.evaluate(() => window.__screenshotQA.session.overlay.width), 260);
    await page.locator('[data-tool="select"]').click();
    let box = await page.locator('#canvas-frame').boundingBox();
    await page.mouse.move(box.x + 40, box.y + 40); await page.mouse.down(); await page.mouse.move(box.x + 20, box.y + 60); await page.mouse.up();
    await page.waitForFunction(() => window.__screenshotQA.session.revision === 2 && !document.querySelector('[data-tool="pen"]').disabled);
    assert.equal(await page.evaluate(() => window.__screenshotQA.session.overlay.x), 100);
    await page.locator('[data-tool="pen"]').click();
    await page.evaluate(() => { window.__screenshotQA.holdSelectionCapture = true; });
    box = await page.locator('#canvas-frame').boundingBox();
    await page.mouse.move(box.x + 25, box.y + 25); await page.mouse.down(); await page.mouse.move(box.x + 80, box.y + 40, { steps: 4 });
    assert.equal(await geometryCalls(), beforeGeometry, 'held first stroke previews without hiding the native host');
    assert.notEqual(await page.locator('#pending-ink').getAttribute('points'), '', 'first ink has same-surface vector preview');
    const heldPreview = await page.locator('#pending-ink').getAttribute('points');
    await page.evaluate(() => {
      const canvas = document.querySelector('#image-canvas');
      for (const type of ['pointerdown','pointercancel','lostpointercapture']) canvas.dispatchEvent(new PointerEvent(type, { pointerId: 991, isPrimary: false, pointerType: 'touch', button: 0, buttons: 1, clientX: 500, clientY: 400, bubbles: true }));
    });
    assert.equal(await page.locator('#pending-ink').getAttribute('points'), heldPreview, 'foreign down/cancel cannot replace or cancel held first stroke');
    await page.mouse.up();
    await page.waitForFunction(() => !!window.__screenshotQA.releaseSelectionCapture);
    assert.equal(await geometryCalls(), beforeGeometry + 1);
    assert.equal(await page.locator('#overlay-cancel').isEnabled(), true, 'capture waiting remains cancellable by the visible x');
    assert.equal(await page.locator('#edit-width').isDisabled(), true, 'pending stroke style cannot change mid-capture');
    await page.evaluate(() => {
      const canvas = document.querySelector('#image-canvas');
      canvas.dispatchEvent(new PointerEvent('pointermove', { pointerId: 991, clientX: 500, clientY: 400, bubbles: true }));
      canvas.dispatchEvent(new PointerEvent('pointerup', { pointerId: 991, clientX: 500, clientY: 400, bubbles: true }));
      window.__screenshotQA.releaseSelectionCapture();
    });
    await page.waitForFunction(() => !document.querySelector('#undo-edit').disabled);
    assert.equal(await page.evaluate(() => window.__sameToolbar === document.querySelector('.editor-toolbar')), true, 'first annotation binds pixels without replacing toolbar');
    assert.deepEqual(await page.locator('#image-canvas').evaluate(c => [...c.getContext('2d').getImageData(400, 200, 1, 1).data]), [20,40,50,255], 'foreign pointer cannot extend buffered ink');
    assert.equal(await page.locator('#selection-handles').isVisible(), false, 'annotated pixels use safe crop/reselect rather than silent live recapture');
    await page.locator('#undo-edit').click();
    assert.equal(await page.locator('#selection-handles').isVisible(), true, 'undo to no annotations permits full adjustment again');
    await page.locator('#overlay-cancel').click();
    // A late capture must not annotate/export/reopen after cancellation.
    await page.evaluate(() => { window.__screenshotQA.releaseSelectionCapture = null; window.__screenshotQA.publishSelection(); });
    await page.waitForFunction(() => !document.querySelector('#selection-handles').hidden);
    await page.locator('[data-tool="rectangle"]').click(); box = await page.locator('#canvas-frame').boundingBox();
    await page.mouse.move(box.x + 20, box.y + 20); await page.mouse.down(); await page.mouse.move(box.x + 80, box.y + 70); await page.mouse.up();
    await page.waitForFunction(() => !document.querySelector('#overlay-cancel').disabled && !!window.__screenshotQA.releaseSelectionCapture);
    const copiesBeforeCancel = await page.evaluate(() => window.__screenshotQA.copies.length);
    await page.locator('#overlay-cancel').click();
    await page.evaluate(() => window.__screenshotQA.releaseSelectionCapture());
    await page.waitForTimeout(40);
    assert.equal(await page.locator('#canvas-frame').isVisible(), false);
    assert.equal(await page.evaluate(() => window.__screenshotQA.copies.length), copiesBeforeCancel);
    // Explicit completion captures once and exports once, even under repeated Enter.
    await page.evaluate(() => { const q = window.__screenshotQA; q.holdSelectionCapture = true; q.releaseSelectionCapture = null; q.publishSelection(); });
    await page.waitForFunction(() => !document.querySelector('#selection-handles').hidden);
    const beforeCopyCapture = await geometryCalls();
    await page.locator('#overlay-copy').click();
    await page.waitForFunction(() => !!window.__screenshotQA.releaseSelectionCapture);
    await page.keyboard.press('Enter'); await page.keyboard.press('Enter');
    await page.locator('#overlay-copy').dispatchEvent('click');
    assert.equal(await geometryCalls(), beforeCopyCapture + 1, 'repeated completion during capture shares no second side effect');
    await page.evaluate(() => { window.__screenshotQA.releaseSelectionCapture(); });
    await page.waitForFunction(n => window.__screenshotQA.copies.length === n + 1, copiesBeforeCancel);
    assert.equal(await page.evaluate(() => window.__screenshotQA.copies.at(-1).revision), 0, 'completion carries the exact captured revision');
    assert.equal(await page.evaluate(() => window.__screenshotQA.calls.filter(c => c.command === 'close_screenshot_editor').at(-1).revision), 0, 'export dismissal is also revision-bound');
    assert.equal(await geometryCalls(), beforeCopyCapture + 1);

    await context.close();
  }
  assert.deepEqual(errors, []); assert.deepEqual(externalRequests, []);
  console.log('PASS: dedicated screenshot editor DPR1/2, all annotation tools, Chinese IME/long text, true crop, pixel mosaic/opaque redaction, undo/redo, flattened copy/save, dialog cancellation, generation races, close/new session, malformed/oversized inputs, no OCR/network/history. Fake IPC only; native acceptance is separate.');
} finally { await browser.close(); }
