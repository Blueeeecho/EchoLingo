// Real Chromium canvas pixels, fake in-memory image only. No desktop/native claims.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
const base = process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/';
try {
  const page = await browser.newPage();
  await page.route('**/*', route => ['127.0.0.1', 'localhost'].includes(new URL(route.request().url()).hostname) ? route.continue() : route.abort());
  await page.goto(new URL('screenshot.html', base).href);
  const result = await page.evaluate(async () => {
    const { ScreenshotDocument, translateOperation } = await import('/src/screenshot-model.ts');
    const { renderScreenshot, flattenedPng } = await import('/src/screenshot-renderer.ts');
    const source = document.createElement('canvas'); source.width = 160; source.height = 120;
    source.getContext('2d').fillStyle = '#abcdef'; source.getContext('2d').fillRect(0, 0, 160, 120);
    const canvas = document.createElement('canvas'), model = new ScreenshotDocument({ width: 160, height: 120 });
    const render = () => renderScreenshot(canvas, source, model.original, model.operations);
    const pixel = (x, y) => [...canvas.getContext('2d').getImageData(x, y, 1, 1).data];
    const raster = () => canvas.toDataURL();
    model.append({ kind: 'text', point: { x: 20, y: 20 }, text: 'A', color: '#111111', background: '#ffeedd', size: 20, maxWidth: 100 });
    render(); const noteBackground = pixel(21, 45), noteRaster = raster();
    model.update(0, { ...model.operations[0], text: '备注 ABC' }); render(); const editedRaster = raster();
    model.undo(); render(); const undoNoteExact = raster() === noteRaster;
    model.redo(); render(); const redoNoteExact = raster() === editedRaster;
    const arrow = { kind: 'numbered-arrow', start: { x: 30, y: 70 }, end: { x: 120, y: 70 }, color: '#dd2233', width: 4, number: 1, size: 28 };
    model.append(arrow); render(); const beforeMove = raster(), linePixel = pixel(80, 70), badgePixel = pixel(19, 70);
    model.update(1, translateOperation(arrow, { x: 10, y: 10 }, model.operationSize(1))); render();
    const movedLine = pixel(80, 80), oldLine = pixel(80, 70), movedBadge = pixel(29, 80), afterMove = raster();
    model.undo(); render(); const undoMoveExact = raster() === beforeMove;
    model.redo(); render(); const redoMoveExact = raster() === afterMove;
    model.remove(1); render(); const deleteRestoresNote = raster() === editedRaster;
    model.undo(); render(); const undeleteExact = raster() === afterMove;
    model.append({ kind: 'number', point: { x: 140, y: 20 }, number: model.nextNumber, size: 24, color: '#ffffff' }); render();
    const numberRaster = raster();
    // The source and every annotation under the mask are replaced, not CSS-hidden.
    model.append({ kind: 'rectangle', rect: { x: 10, y: 10, width: 140, height: 90 }, color: '#000000', width: 4, solid: true });
    model.update(0, { ...model.operations[0], text: '修改备注不能越过遮挡层' }); render();
    const covered = canvas.getContext('2d').getImageData(10, 10, 140, 90).data;
    const maskOpaque = [...covered].every((n, i) => n === (i % 4 === 3 ? 255 : 0));
    const encoded = await flattenedPng(canvas), decoded = new Image(); decoded.src = `data:image/png;base64,${encoded}`; await decoded.decode();
    const exported = document.createElement('canvas'); exported.width = decoded.width; exported.height = decoded.height; exported.getContext('2d').drawImage(decoded, 0, 0);
    const exportExact = exported.toDataURL() === canvas.toDataURL();
    model.append({ kind: 'crop', rect: { x: 10, y: 10, width: 140, height: 90 } }); render();
    const crop = { width: canvas.width, height: canvas.height, first: pixel(0, 0), last: pixel(139, 89) };
    const marks = new ScreenshotDocument({ width: 160, height: 120 });
    const redraw = () => renderScreenshot(canvas, source, marks.original, marks.operations);
    marks.append({ kind: 'pen', points: [{ x: 10, y: 20 }, { x: 150, y: 20 }], width: 8, color: '#dd2233' });
    marks.append({ kind: 'highlight', points: [{ x: 10, y: 50 }, { x: 150, y: 50 }], width: 16, color: '#ffff00' });
    marks.append({ kind: 'ellipse', rect: { x: 60, y: 75, width: 60, height: 30 }, color: '#dd2233', width: 4 }); redraw();
    const highlighted = pixel(100, 50), ellipseCenter = pixel(90, 90), ellipseTop = pixel(90, 77);
    marks.append({ kind: 'rectangle', rect: { x: 30, y: 10, width: 30, height: 60 }, color: '#000000', width: 4, solid: true }); redraw();
    const beforeErase = raster();
    marks.eraseStrokes([{ x: 100, y: 10 }, { x: 100, y: 65 }], 20); redraw();
    const erasedPen = pixel(100, 20), erasedHighlight = pixel(100, 50), keptPen = pixel(20, 20), afterErase = raster();
    // Erasing over a privacy mask never punches a hole into the actual source.
    marks.eraseStrokes([{ x: 45, y: 10 }, { x: 45, y: 65 }], 30); redraw();
    const protectedMask = [...canvas.getContext('2d').getImageData(30, 10, 30, 60).data].every((n, i) => n === (i % 4 === 3 ? 255 : 0));
    marks.undo(); redraw(); const eraseUndoExact = raster() === afterErase;
    marks.undo(); redraw(); const allEraseUndoExact = raster() === beforeErase;
    marks.redo(); redraw(); const eraseRedoExact = raster() === afterErase;
    const freehandPng = await flattenedPng(canvas), freehandImage = new Image(); freehandImage.src = `data:image/png;base64,${freehandPng}`; await freehandImage.decode();
    const freehandCanvas = document.createElement('canvas'); freehandCanvas.width = freehandImage.width; freehandCanvas.height = freehandImage.height; freehandCanvas.getContext('2d').drawImage(freehandImage, 0, 0);
    const freehandExportExact = freehandCanvas.toDataURL() === canvas.toDataURL();
    const freehand = { freehandExportExact, highlighted, ellipseCenter, ellipseTop, erasedPen, erasedHighlight, keptPen, protectedMask, eraseUndoExact, allEraseUndoExact, eraseRedoExact };
    return { freehand, noteBackground, undoNoteExact, redoNoteExact, linePixel, badgePixel, movedLine, oldLine, movedBadge, undoMoveExact, redoMoveExact,
      deleteRestoresNote, undeleteExact, numberAdded: numberRaster !== afterMove, maskOpaque, exportExact, crop };
  });
  const red = [221, 34, 51, 255], sourcePixel = [171, 205, 239, 255];
  assert.deepEqual(result.freehand.erasedPen, sourcePixel); assert.deepEqual(result.freehand.erasedHighlight, sourcePixel);
  assert.deepEqual(result.freehand.keptPen, red); assert.deepEqual(result.freehand.ellipseCenter, sourcePixel); assert.deepEqual(result.freehand.ellipseTop, red);
  assert.notDeepEqual(result.freehand.highlighted, sourcePixel); assert.notDeepEqual(result.freehand.highlighted, [255, 255, 0, 255]); assert.equal(result.freehand.highlighted[3], 255);
  for (const key of ['freehandExportExact', 'protectedMask', 'eraseUndoExact', 'allEraseUndoExact', 'eraseRedoExact']) assert.equal(result.freehand[key], true, key);
  assert.deepEqual(result.noteBackground, [255, 238, 221, 255]);
  for (const key of ['undoNoteExact', 'redoNoteExact', 'undoMoveExact', 'redoMoveExact', 'deleteRestoresNote', 'undeleteExact', 'numberAdded', 'maskOpaque', 'exportExact']) assert.equal(result[key], true, key);
  for (const key of ['linePixel', 'badgePixel', 'movedLine', 'movedBadge']) assert.deepEqual(result[key], red, key);
  assert.deepEqual(result.oldLine, [171, 205, 239, 255]);
  assert.deepEqual(result.crop, { width: 140, height: 90, first: [0, 0, 0, 255], last: [0, 0, 0, 255] });
  console.log('PASS: actual canvas note edits, atomic numbered-arrow movement/deletion, exact undo/redo rasters, ordered opaque mask, flattened PNG and crop. Browser fixture only; native acceptance separate.');
} finally { await browser.close(); }
