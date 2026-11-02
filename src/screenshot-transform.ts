import { operationBounds, validateOperation, validateSize, type EditOperation, type Point, type Size } from './screenshot-model';

export type ResizeHandle = 'nw' | 'n' | 'ne' | 'e' | 'se' | 's' | 'sw' | 'w' | 'start' | 'end';
const rectHandles = new Set<ResizeHandle>(['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w']);
const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

function resizeAxis(start: number, length: number, target: number, extent: number, edge: 'min' | 'max' | 'none'): [number, number] {
  const minimum = Math.min(2, extent);
  if (edge === 'min') {
    // A pre-existing one-pixel shape at the image edge may need its fixed edge
    // nudged by one pixel to satisfy the minimum; ordinary opposite edges stay put.
    const end = Math.max(start + length, minimum);
    const next = clamp(target, 0, end - minimum);
    return [next, end - next];
  }
  const next = Math.min(start, extent - minimum);
  if (edge === 'max') return [next, clamp(target, next + minimum, extent) - next];
  return [next, Math.min(extent - next, Math.max(minimum, length))];
}

/** Pure resize preview in the annotation's own coordinate stage, NOT display or
 * post-crop coordinates. Add model.operationOffset(index) to a displayed pointer
 * and pass model.operationSize(index). The caller commits once on pointer-up.
 * Negative/non-finite inputs fail closed; non-negative out-of-image drags clamp.
 * Rect handles stop at the opposite edge rather than flipping their identities. */
export function resizeAnnotation(operation: EditOperation, handle: ResizeHandle, point: Point, size: Size): EditOperation {
  validateSize(size);
  validateOperation(operation, size);
  if (![point.x, point.y].every(value => Number.isFinite(value) && value >= 0)) throw new Error('调整位置无效。');
  if (operation.kind === 'arrow' || operation.kind === 'numbered-arrow') {
    if (handle !== 'start' && handle !== 'end') throw new Error('箭头只能调整端点。');
    const target = Object.freeze({ x: clamp(point.x, 0, size.width), y: clamp(point.y, 0, size.height) });
    const next = { ...operation, start: Object.freeze({ ...operation.start }), end: Object.freeze({ ...operation.end }), [handle]: target };
    validateOperation(next, size);
    return Object.freeze(next);
  }
  if (operation.kind !== 'rectangle' && operation.kind !== 'ellipse' && operation.kind !== 'mosaic') throw new Error('此标注不支持形状手柄调整。');
  if (!rectHandles.has(handle)) throw new Error('形状调整手柄无效。');
  const bounds = operationBounds(operation);
  const [x, width] = resizeAxis(bounds.x, bounds.width, Math.round(clamp(point.x, 0, size.width)), size.width,
    handle.includes('w') ? 'min' : handle.includes('e') ? 'max' : 'none');
  const [y, height] = resizeAxis(bounds.y, bounds.height, Math.round(clamp(point.y, 0, size.height)), size.height,
    handle.includes('n') ? 'min' : handle.includes('s') ? 'max' : 'none');
  const next = { ...operation, rect: Object.freeze({ x, y, width, height }) };
  validateOperation(next, size);
  return Object.freeze(next);
}
