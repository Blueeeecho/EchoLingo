import { describe, expect, it } from 'vitest';
import { ScreenshotDocument, imagePoint, selectionRect, validateSize, validateOperation, mosaicPixels, wrapText, MAX_UNDO, MAX_OPERATIONS, type EditOperation } from './screenshot-model';
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
