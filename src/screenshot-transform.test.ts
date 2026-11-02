import { describe, expect, it } from 'vitest';
import { ScreenshotDocument, type EditOperation } from './screenshot-model';
import { resizeAnnotation, type ResizeHandle } from './screenshot-transform';

const size = { width: 100, height: 80 };
const rectangle = (): EditOperation => ({ kind: 'rectangle', rect: { x: 20, y: 20, width: 40, height: 30 }, color: '#123456', width: 4, solid: false });
const arrow = (): EditOperation => ({ kind: 'numbered-arrow', start: { x: 20, y: 20 }, end: { x: 70, y: 60 }, color: '#123456', width: 4, number: 7, size: 24 });

describe('pure screenshot annotation resize', () => {
  it.each<[ResizeHandle, number, number, number, number]>([
    ['nw', 10, 10, 50, 40], ['n', 20, 10, 40, 40], ['ne', 20, 10, 60, 40],
    ['e', 20, 20, 60, 30], ['se', 20, 20, 60, 50], ['s', 20, 20, 40, 50],
    ['sw', 10, 20, 50, 50], ['w', 10, 20, 50, 30],
  ])('resizes %s while preserving opposite edges and style', (handle, x, y, width, height) => {
    const operation = rectangle();
    const point = { x: handle.includes('w') ? 10 : 80, y: handle.includes('n') ? 10 : 70 };
    expect(resizeAnnotation(operation, handle, point, size)).toEqual({ ...operation, rect: { x, y, width, height } });
    expect(operation).toEqual(rectangle());
  });

  it.each(['rectangle', 'ellipse', 'mosaic', 'solid'] as const)('supports %s without changing semantic properties', kind => {
    const rect = { x: 20, y: 20, width: 40, height: 30 };
    const operation: EditOperation = kind === 'mosaic' ? { kind, rect, blockSize: 16 }
      : kind === 'ellipse' ? { kind, rect, color: '#123456', width: 8 }
      : { kind: 'rectangle', rect, color: '#123456', width: 8, solid: kind === 'solid' };
    const next = resizeAnnotation(operation, 'se', { x: 90.4, y: 70.2 }, size);
    expect(next).toEqual({ ...operation, rect: { x: 20, y: 20, width: 70, height: 50 } });
    expect(Object.isFrozen(next)).toBe(true);
    expect('rect' in next && Object.isFrozen(next.rect)).toBe(true);
    expect(Object.isFrozen(rect)).toBe(false);
  });

  it('clamps crossing and image edges, including minimum-sized images', () => {
    expect(resizeAnnotation(rectangle(), 'nw', { x: 900, y: 900 }, size)).toMatchObject({ rect: { x: 58, y: 48, width: 2, height: 2 } });
    expect(resizeAnnotation(rectangle(), 'se', { x: 0, y: 0 }, size)).toMatchObject({ rect: { x: 20, y: 20, width: 2, height: 2 } });
    expect(resizeAnnotation(rectangle(), 'se', { x: 900, y: 900 }, size)).toMatchObject({ rect: { x: 20, y: 20, width: 80, height: 60 } });
    const tiny: EditOperation = { kind: 'mosaic', rect: { x: 0, y: 0, width: 1, height: 1 }, blockSize: 8 };
    for (const handle of ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'] as const) {
      expect(resizeAnnotation(tiny, handle, { x: 0, y: 0 }, { width: 1, height: 1 })).toEqual(tiny);
      expect(resizeAnnotation(tiny, handle, { x: 0, y: 0 }, size)).toMatchObject({ rect: { x: 0, y: 0, width: 2, height: 2 } });
    }
  });

  it.each(['start', 'end'] as const)('moves only the %s endpoint, retaining the numbered group atomically', handle => {
    const operation = arrow();
    const next = resizeAnnotation(operation, handle, { x: 120.5, y: 35.25 }, size);
    expect(next).toEqual({ ...operation, [handle]: { x: 100, y: 35.25 } });
    expect(operation).toEqual(arrow());
    expect(Object.isFrozen(next)).toBe(true);
    expect('start' in next && Object.isFrozen(next.start) && Object.isFrozen(next.end)).toBe(true);
    const plain: EditOperation = { kind: 'arrow', start: { x: 1, y: 2 }, end: { x: 8, y: 9 }, width: 2, color: '#000000' };
    expect(resizeAnnotation(plain, handle, { x: 0, y: 0 }, size)).toEqual({ ...plain, [handle]: { x: 0, y: 0 } });
  });

  it('uses original operation coordinates after multiple crops and commits one undo step', () => {
    const model = new ScreenshotDocument(size); model.append(rectangle());
    model.append({ kind: 'crop', rect: { x: 10, y: 10, width: 80, height: 60 } });
    model.append({ kind: 'crop', rect: { x: 5, y: 5, width: 70, height: 50 } });
    const original = model.operations[0], offset = model.operationOffset(0), before = model.stateId;
    const displayed = { x: 50, y: 35 };
    const next = resizeAnnotation(original, 'se', { x: displayed.x + offset.x, y: displayed.y + offset.y }, model.operationSize(0));
    expect(next).toMatchObject({ rect: { x: 20, y: 20, width: 45, height: 30 } });
    model.update(0, next); expect(model.operations[0]).toEqual(next); expect(model.size).toEqual({ width: 70, height: 50 });
    model.undo(); expect(model.stateId).toBe(before); expect(model.operations[0]).toEqual(original);
    model.redo(); expect(model.operations[0]).toEqual(next);
  });

  it('fails closed on invalid geometry, unsupported objects, and mismatched handles', () => {
    for (const point of [{ x: -1, y: 0 }, { x: 0, y: -1 }, { x: NaN, y: 1 }, { x: 1, y: Infinity }]) expect(() => resizeAnnotation(rectangle(), 'se', point, size)).toThrow();
    for (const invalid of [{ width: -1, height: 80 }, { width: 0, height: 80 }, { width: 1.5, height: 80 }, { width: NaN, height: 80 }]) expect(() => resizeAnnotation(rectangle(), 'se', { x: 30, y: 40 }, invalid)).toThrow();
    expect(() => resizeAnnotation({ ...rectangle(), rect: { x: -1, y: 0, width: 5, height: 5 } } as EditOperation, 'se', { x: 30, y: 40 }, size)).toThrow();
    expect(() => resizeAnnotation({ kind: 'crop', rect: { x: 1, y: 1, width: 5, height: 5 } }, 'se', { x: 30, y: 40 }, size)).toThrow();
    expect(() => resizeAnnotation({ kind: 'number', number: 1, size: 24, point: { x: 10, y: 10 }, color: '#123456' }, 'se', { x: 30, y: 40 }, size)).toThrow();
    expect(() => resizeAnnotation(rectangle(), 'start', { x: 30, y: 40 }, size)).toThrow();
    expect(() => resizeAnnotation(arrow(), 'nw', { x: 30, y: 40 }, size)).toThrow();
    expect(() => resizeAnnotation(rectangle(), 'bogus' as ResizeHandle, { x: 30, y: 40 }, size)).toThrow();
  });
});
