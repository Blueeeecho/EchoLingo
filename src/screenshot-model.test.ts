import { describe, expect, it } from 'vitest';
import { ScreenshotDocument, translateOperation, operationBounds, imagePoint, selectionRect, validateSize, validateOperation, mosaicPixels, wrapText, MAX_UNDO, MAX_OPERATIONS, type EditOperation, strokePathsIntersect, MAX_STROKE_POINTS } from './screenshot-model';
const rectangle = (): EditOperation => ({ kind: 'rectangle', rect: { x: 1, y: 1, width: 6, height: 4 }, color: '#123456', width: 2, solid: true });
describe('isolated screenshot image-pixel model', () => {
  it('maps actual display bounds into pixels independent of zoom/DPR and clips outside drags', () => {
    for (const scale of [.1, .5, 1, 1.25, 2, 4]) {
      expect(imagePoint({ x: 13 + 400 * scale, y: 29 + 200 * scale }, { x: 13, y: 29, width: 800 * scale, height: 600 * scale }, { width: 800, height: 600 })).toEqual({ x: 400, y: 200 });
    }
    expect(imagePoint({ x: -100, y: 900 }, { x: 5, y: 5, width: 400, height: 300 }, { width: 800, height: 600 })).toEqual({ x: 0, y: 600 });
    expect(selectionRect({ x: 8.7, y: 9.1 }, { x: -4, y: 3.2 }, { width: 10, height: 10 })).toEqual({ x: 0, y: 3, width: 9, height: 7 });
  });
  it('retains an immutable original and operations; true crop dimensions undo and redo exactly', () => {
    const size = { width: 80, height: 60 }, model = new ScreenshotDocument(size); size.width = 1;
    const operation = rectangle(); model.append(operation);
    if (operation.kind === 'rectangle') operation.rect.x = 99;
    expect(model.original).toEqual({ width: 80, height: 60 });
    const extra = { width: 2, height: 2, pngBase64: 'must not enter the operation model', id: 7 };
    expect(new ScreenshotDocument(extra).original).toEqual({ width: 2, height: 2 });
    expect(model.operations[0]).toEqual(rectangle());
    expect(Object.isFrozen(model.operations[0])).toBe(true);
    const arrow: EditOperation = { kind: 'arrow', start: { x: 1, y: 1 }, end: { x: 8, y: 8 }, color: '#000000', width: 2 };
    const arrows = new ScreenshotDocument({ width: 10, height: 10 }); arrows.append(arrow); arrow.start.x = 9;
    expect(arrows.operations[0]).toMatchObject({ start: { x: 1, y: 1 } });
    const originalState = model.stateId;
    model.append({ kind: 'crop', rect: { x: 10, y: 20, width: 25, height: 30 } });
    expect(model.size).toEqual({ width: 25, height: 30 }); expect(model.undo()).toBe(true);
    expect(model.size).toEqual({ width: 80, height: 60 }); expect(model.stateId).toBe(originalState);
    expect(model.redo()).toBe(true); expect(model.size).toEqual({ width: 25, height: 30 });
    expect(() => model.append({ kind: 'crop', rect: { x: 0, y: 0, width: 26, height: 30 } })).toThrow();
  });
  it('drops the redo branch, bounds undo history and caps total typed operations without bitmap snapshots', () => {
    const model = new ScreenshotDocument({ width: 10, height: 10 });
    model.append(rectangle()); const state = model.stateId; model.undo(); model.append(rectangle());
    expect(model.canRedo).toBe(false); expect(model.stateId).not.toBe(state);
    for (let i = 1; i < MAX_OPERATIONS; i++) model.append(rectangle());
    expect(() => model.append(rectangle())).toThrow('500');
    let undone = 0; while (model.undo()) undone++;
    expect(undone).toBe(MAX_UNDO); expect(model.operations).toHaveLength(MAX_OPERATIONS - MAX_UNDO);
    while (model.redo()) { /* Restore bounded typed history. */ }
    expect(model.operations).toHaveLength(MAX_OPERATIONS);
    expect(JSON.stringify(model.operations).length).toBeLessThan(100_000);
  });
  it('bounds large-image replay work before accepting more expensive pixel operations', () => {
    const model = new ScreenshotDocument({ width: 8000, height: 4000 });
    const mosaic: EditOperation = { kind: 'mosaic', rect: { x: 0, y: 0, width: 8000, height: 4000 }, blockSize: 16 };
    model.append(mosaic); const state = model.stateId;
    expect(() => model.append(mosaic)).toThrow('安全上限');
    expect(model.stateId).toBe(state); expect(model.operations).toHaveLength(1);
    model.undo(); model.append({ kind: 'crop', rect: { x: 0, y: 0, width: 100, height: 100 } });
    for (let i = 0; i < 50; i++) model.append({ ...mosaic, rect: { x: 0, y: 0, width: 100, height: 100 } });
    expect(model.operations).toHaveLength(51);
  });
  it('rejects invalid/huge images and edit parameters before allocating canvases', () => {
    for (const size of [{ width: 0, height: 10 }, { width: 16_385, height: 1 }, { width: 8_000, height: 8_000 }, { width: NaN, height: 10 }, { width: 10.5, height: 10 }]) expect(() => validateSize(size)).toThrow();
    validateSize({ width: 8_000, height: 4_000 });
    const size = { width: 20, height: 20 };
    expect(() => validateOperation({ kind: 'text', point: { x: 0, y: 0 }, text: '字'.repeat(2001), size: 12, color: '#000000', maxWidth: 20 }, size)).toThrow();
    expect(() => validateOperation({ kind: 'mosaic', rect: { x: 0, y: 0, width: 2, height: 2 }, blockSize: 0 }, size)).toThrow();
    expect(() => validateOperation({ ...rectangle(), color: 'url(https://example.invalid)' } as EditOperation, size)).toThrow();
  });
  it('replaces every mosaic pixel with an opaque block mean, including partial and transparent blocks', () => {
    const pixels = new Uint8ClampedArray([255,0,0,255, 0,0,255,255, 0,255,0,255, 255,255,255,255, 0,0,0,255, 123,99,88,0]);
    mosaicPixels(pixels, 3, 2, 2);
    expect([...pixels]).toEqual([128,64,128,255, 128,64,128,255, 0,255,0,255, 128,64,128,255, 128,64,128,255, 0,255,0,255]);
    const hidden = new Uint8ClampedArray([100, 200, 30, 0]); mosaicPixels(hidden, 1, 1, 8);
    expect([...hidden]).toEqual([0,0,0,255]);
  });
  it('wraps Chinese, line breaks, long tokens and emoji without dropping or splitting surrogate pairs', () => {
    const measure = (value: string) => [...value].length;
    expect(wrapText('中文标注\r\nA😀BC\n', 2, measure)).toEqual(['中文', '标注', 'A😀', 'BC', '']);
    expect(wrapText('abcdef', .5, measure)).toEqual(['a','b','c','d','e','f']);
    expect(wrapText('字'.repeat(2000), 20, measure)).toHaveLength(100);
  });
});

describe('editable annotation history', () => {
  const badge = (number = 1): EditOperation => ({ kind: 'number', point: { x: 30, y: 30 }, number, size: 24, color: '#dd3344' });
  it('updates, moves and deletes an atomic numbered arrow in one undo step without changing z-order', () => {
    const model = new ScreenshotDocument({ width: 100, height: 100 });
    const arrow: EditOperation = { kind: 'numbered-arrow', start: { x: 10, y: 20 }, end: { x: 60, y: 70 }, number: 1, size: 24, color: '#dd3344', width: 4 };
    model.append(arrow); model.append(rectangle()); const before = model.stateId;
    model.update(0, translateOperation(arrow, { x: 20, y: 10 }, model.operationSize(0)));
    expect(model.operations[0]).toMatchObject({ start: { x: 30, y: 30 }, end: { x: 80, y: 80 }, number: 1 });
    expect(model.operations[1]).toEqual(rectangle());
    model.undo(); expect(model.stateId).toBe(before); expect(model.operations[0]).toEqual(arrow);
    model.redo(); const moved = model.operations[0];
    model.remove(0); expect(model.operations).toEqual([rectangle()]); expect(model.nextNumber).toBe(1);
    model.undo(); expect(model.operations[0]).toBe(moved); expect(model.nextNumber).toBe(2);
    model.redo(); model.append(badge()); expect(model.canRedo).toBe(false);
  });
  it('keeps notes immutable and restores edited text/background with undo/redo', () => {
    const model = new ScreenshotDocument({ width: 100, height: 80 });
    const text: EditOperation = { kind: 'text', point: { x: 10, y: 10 }, text: '备注', size: 16, maxWidth: 80, color: '#112233', background: '#fff3aa' };
    model.append(text); model.update(0, { ...text, text: '修正后的备注' });
    expect(model.operations[0]).toMatchObject({ text: '修正后的备注', background: '#fff3aa' });
    model.undo(); expect(model.operations[0]).toEqual(text); model.redo();
    expect(Object.isFrozen(model.operations)).toBe(true); expect(Object.isFrozen(model.operations[0])).toBe(true);
    expect(() => model.update(0, { ...text, background: 'transparent' })).toThrow('底色');
  });
  it('maps pre-crop and post-crop annotations to their correct coordinate stage', () => {
    const model = new ScreenshotDocument({ width: 100, height: 100 }); model.append(badge(1));
    model.append({ kind: 'crop', rect: { x: 10, y: 20, width: 70, height: 70 } }); model.append(badge(2));
    model.append({ kind: 'crop', rect: { x: 5, y: 6, width: 50, height: 50 } });
    expect(model.operationSize(0)).toEqual({ width: 100, height: 100 });
    expect(model.operationSize(2)).toEqual({ width: 70, height: 70 });
    expect(model.operationOffset(0)).toEqual({ x: 15, y: 26 });
    expect(model.operationOffset(2)).toEqual({ x: 5, y: 6 });
    expect(model.nextNumber).toBe(3); model.remove(0); expect(model.nextNumber).toBe(3);
    model.undo(); expect(model.operationOffset(0)).toEqual({ x: 15, y: 26 });
    expect(() => model.update(1, badge())).toThrow('裁剪'); expect(() => model.remove(1)).toThrow('裁剪');
    expect(model.size).toEqual({ width: 50, height: 50 });
    model.undo(); expect(model.size).toEqual({ width: 70, height: 70 });
  });
  it('derives numbering from current history including crop-hidden numbers, with no mutable counter', () => {
    const model = new ScreenshotDocument({ width: 100, height: 100 });
    model.append(badge(model.nextNumber)); model.append(badge(model.nextNumber)); expect(model.nextNumber).toBe(3);
    model.undo(); expect(model.nextNumber).toBe(2); model.redo(); expect(model.nextNumber).toBe(3);
    model.append({ kind: 'crop', rect: { x: 80, y: 80, width: 20, height: 20 } }); expect(model.nextNumber).toBe(3);
    model.remove(1); expect(model.nextNumber).toBe(2); model.undo(); expect(model.nextNumber).toBe(3);
  });
  it('clamps a common movement delta and preserves shape size', () => {
    const arrow: EditOperation = { kind: 'numbered-arrow', start: { x: 10, y: 10 }, end: { x: 40, y: 50 }, number: 1, size: 24, color: '#123456', width: 4 };
    expect(translateOperation(arrow, { x: 200, y: -200 }, { width: 100, height: 80 })).toMatchObject({ start: { x: 70, y: 0 }, end: { x: 100, y: 40 } });
    const moved = translateOperation(rectangle(), { x: -20, y: 200 }, { width: 10, height: 10 });
    expect(moved).toMatchObject({ rect: { x: 0, y: 6, width: 6, height: 4 } });
    expect(() => translateOperation(arrow, { x: NaN, y: 0 }, { width: 100, height: 80 })).toThrow();
    expect(operationBounds(badge())).toEqual({ x: 18, y: 18, width: 24, height: 24 });
    expect(operationBounds({ kind: 'text', point: { x: 10, y: 10 }, text: 'ABCD', size: 10, maxWidth: 15, color: '#000000' }, t => t.length * 5)).toEqual({ x: 10, y: 10, width: 15, height: 27 });
  });
  it('keeps invalid edits out of history and enforces replay limits on replacements', () => {
    const model = new ScreenshotDocument({ width: 8000, height: 4000 });
    model.append({ kind: 'mosaic', rect: { x: 0, y: 0, width: 8000, height: 4000 }, blockSize: 16 });
    const smallMosaic: EditOperation = { kind: 'mosaic', rect: { x: 0, y: 0, width: 10, height: 10 }, blockSize: 16 };
    model.append(smallMosaic); const state = model.stateId;
    expect(() => model.update(1, { kind: 'mosaic', rect: { x: 0, y: 0, width: 8000, height: 4000 }, blockSize: 16 })).toThrow('安全上限');
    expect(model.stateId).toBe(state); expect(model.operations[1]).toEqual(smallMosaic);
    expect(() => model.append({ ...badge(), number: 0 } as EditOperation)).toThrow('序号');
  });
});


describe('freehand annotations and privacy-safe local eraser', () => {
  const pen = (): EditOperation => ({ kind: 'pen', points: [{ x: 10, y: 20 }, { x: 100, y: 20 }], color: '#aa1122', width: 4 });
  it('erases only intersecting freehand marks in one undo step and preserves masks', () => {
    const model = new ScreenshotDocument({ width: 160, height: 120 });
    model.append(pen()); model.append({ ...pen(), kind: 'highlight' } as EditOperation); model.append(rectangle());
    const before = model.operations, state = model.stateId;
    expect(model.eraseStrokes([{ x: 50, y: 10 }, { x: 50, y: 30 }], 10)).toBe(true);
    expect(model.operations[0]).toHaveProperty('erasures'); expect(model.operations[1]).toHaveProperty('erasures'); expect(model.operations[2]).toBe(before[2]);
    model.undo(); expect(model.stateId).toBe(state); expect(model.operations).toBe(before);
    model.redo(); expect(model.operations[0]).toHaveProperty('erasures');
    const changed = model.stateId; expect(model.eraseStrokes([{ x: 150, y: 100 }], 10)).toBe(false); expect(model.stateId).toBe(changed);
  });
  it('maps eraser through crop, keeps erasures attached on move, and freezes nested input', () => {
    const model = new ScreenshotDocument({ width: 160, height: 120 }); const operation = pen(); model.append(operation);
    model.append({ kind: 'crop', rect: { x: 20, y: 10, width: 100, height: 60 } });
    const path = [{ x: 30, y: 10 }]; model.eraseStrokes(path, 12); path[0].x = 99;
    const op = model.operations[0]; expect(op).toMatchObject({ erasures: [{ points: [{ x: 50, y: 20 }], width: 12 }] });
    const moved = translateOperation(op, { x: 5, y: 10 }, model.operationSize(0));
    expect(moved).toMatchObject({ points: [{ x: 15, y: 30 }, { x: 105, y: 30 }], erasures: [{ points: [{ x: 55, y: 30 }] }] });
    expect(Object.isFrozen((op as Extract<EditOperation, { kind: 'pen' }>).points[0])).toBe(true);
  });
  it('recognizes crossing and single-point paths and rejects unbounded stroke input', () => {
    expect(strokePathsIntersect([{ x: 0, y: 0 }, { x: 10, y: 10 }], [{ x: 0, y: 10 }, { x: 10, y: 0 }], 1)).toBe(true);
    expect(strokePathsIntersect([{ x: 1, y: 1 }], [{ x: 10, y: 10 }], 1)).toBe(false);
    expect(() => validateOperation({ ...pen(), points: Array(MAX_STROKE_POINTS + 1).fill({ x: 1, y: 1 }) } as EditOperation, { width: 160, height: 120 })).toThrow();
    expect(() => validateOperation({ ...pen(), points: [{ x: NaN, y: 1 }] } as EditOperation, { width: 160, height: 120 })).toThrow();
  });
  it('bounds total document ink complexity before accepting more histories', () => {
    const model = new ScreenshotDocument({ width: 160, height: 120 });
    const points = Array.from({ length: MAX_STROKE_POINTS }, (_, i) => ({ x: i % 100, y: 20 }));
    for (let i = 0; i < 16; i++) model.append({ kind: 'pen', points, color: '#111111', width: 2 });
    const state = model.stateId;
    expect(() => model.append({ kind: 'pen', points: [{ x: 1, y: 1 }], color: '#111111', width: 2 })).toThrow('复杂度');
    expect(model.stateId).toBe(state);
  });
  it('treats ellipse as a movable editable shape', () => {
    const model = new ScreenshotDocument({ width: 160, height: 120 });
    model.append({ kind: 'ellipse', rect: { x: 10, y: 20, width: 80, height: 40 }, color: '#aa1122', width: 4 });
    model.update(0, translateOperation(model.operations[0], { x: 5, y: 5 }, model.size));
    expect(model.operations[0]).toMatchObject({ rect: { x: 15, y: 25 } }); model.undo(); expect(model.operations[0]).toMatchObject({ rect: { x: 10, y: 20 } });
  });
});
