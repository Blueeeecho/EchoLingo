/** Image-pixel coordinates only. Display zoom/DPR never enter the edit history. */
export interface Size { width: number; height: number }
export interface Point { x: number; y: number }
export interface Rect extends Point, Size {}
export type EditOperation =
  | { kind: 'rectangle'; rect: Rect; color: string; width: number; solid: boolean }
  | { kind: 'arrow'; start: Point; end: Point; color: string; width: number }
  | { kind: 'text'; point: Point; text: string; color: string; size: number; maxWidth: number; background?: string }
  | { kind: 'number'; point: Point; number: number; size: number; color: string }
  | { kind: 'numbered-arrow'; start: Point; end: Point; number: number; size: number; color: string; width: number }
  | { kind: 'mosaic'; rect: Rect; blockSize: number }
  | { kind: 'crop'; rect: Rect };
export const MAX_PIXELS = 32_000_000;
export const MAX_EDGE = 16_384;
export const MAX_ENCODED_BYTES = 32 * 1024 * 1024;
export const MAX_TEXT = 2_000;
export const MAX_OPERATIONS = 500;
export const MAX_UNDO = 100;
// Bound a single replay as well as history size. Large-image pixel operations
// otherwise multiply 500 steps into billions of synchronous pixel visits.
export const MAX_REPLAY_PIXELS = 256_000_000;
function operationCost(operation: EditOperation, size: Size): number {
  if (operation.kind === 'mosaic') return operation.rect.width * operation.rect.height * 4;
  if (operation.kind === 'crop') return operation.rect.width * operation.rect.height * 2;
  if (operation.kind === 'rectangle') return operation.solid ? operation.rect.width * operation.rect.height
    : Math.min(operation.rect.width * operation.rect.height, (operation.rect.width + operation.rect.height) * operation.width * 2);
  if (operation.kind === 'number') return operation.size ** 2;
  if (operation.kind === 'arrow' || operation.kind === 'numbered-arrow') return Math.hypot(operation.end.x - operation.start.x, operation.end.y - operation.start.y) * operation.width * 6 + operation.width ** 2 * 32 + (operation.kind === 'numbered-arrow' ? operation.size ** 2 : 0);
  const lines = operation.text.split('\n').reduce((sum, line) => sum + Math.max(1, Math.ceil([...line].length / Math.max(1, Math.floor(operation.maxWidth / operation.size)))), 0);
  return operation.maxWidth * Math.min(size.height - operation.point.y, lines * operation.size * 1.35);
}
function replayCost(original: Size, operations: readonly EditOperation[]): number {
  let cost = original.width * original.height, size = original;
  for (const operation of operations) { cost += operationCost(operation, size); if (operation.kind === 'crop') size = operation.rect; }
  return cost;
}
const finite = (n: number) => Number.isFinite(n);
const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(n, hi));
export function validateSize(size: Size): void {
  if (![size.width, size.height].every(n => Number.isSafeInteger(n) && n > 0 && n <= MAX_EDGE)
    || size.width * size.height > MAX_PIXELS) throw new Error('图片过大或尺寸无效：最多 3200 万像素，单边不超过 16384 像素。');
}
export function imagePoint(client: Point, bounds: Rect, size: Size): Point {
  if (bounds.width <= 0 || bounds.height <= 0) return { x: 0, y: 0 };
  return { x: clamp((client.x - bounds.x) * size.width / bounds.width, 0, size.width),
    y: clamp((client.y - bounds.y) * size.height / bounds.height, 0, size.height) };
}
export function selectionRect(start: Point, end: Point, size: Size): Rect {
  const x = clamp(Math.floor(Math.min(start.x, end.x)), 0, size.width);
  const y = clamp(Math.floor(Math.min(start.y, end.y)), 0, size.height);
  return { x, y, width: Math.max(0, clamp(Math.ceil(Math.max(start.x, end.x)), 0, size.width) - x),
    height: Math.max(0, clamp(Math.ceil(Math.max(start.y, end.y)), 0, size.height) - y) };
}
function validRect(rect: Rect, size: Size): boolean {
  return [rect.x, rect.y, rect.width, rect.height].every(Number.isSafeInteger)
    && rect.x >= 0 && rect.y >= 0 && rect.width > 0 && rect.height > 0
    && rect.x + rect.width <= size.width && rect.y + rect.height <= size.height;
}
function validPoint(point: Point, size: Size): boolean {
  return finite(point.x) && finite(point.y) && point.x >= 0 && point.y >= 0 && point.x <= size.width && point.y <= size.height;
}
export function validateOperation(operation: EditOperation, size: Size): void {
  if ('rect' in operation && !validRect(operation.rect, size)) throw new Error('请在图片内选择有效区域。');
  if ('color' in operation && !/^#[0-9a-f]{6}$/i.test(operation.color)) throw new Error('颜色无效。');
  if ('width' in operation && (!finite(operation.width) || operation.width < 1 || operation.width > 64)) throw new Error('线宽无效。');
  if ((operation.kind === 'arrow' || operation.kind === 'numbered-arrow') && (!validPoint(operation.start, size) || !validPoint(operation.end, size))) throw new Error('箭头超出图片。');
  if (operation.kind === 'text' && (!validPoint(operation.point, size) || !operation.text.trim() || operation.text.length > MAX_TEXT
    || !finite(operation.size) || operation.size < 8 || operation.size > 256 || !finite(operation.maxWidth)
    || operation.maxWidth < 1 || operation.maxWidth > size.width)) throw new Error('文字或字号无效（最多 2000 字）。');
  if (operation.kind === 'text' && operation.background !== undefined && !/^#[0-9a-f]{6}$/i.test(operation.background)) throw new Error('备注底色无效。');
  if ((operation.kind === 'number' || operation.kind === 'numbered-arrow') && (!Number.isSafeInteger(operation.number) || operation.number < 1 || operation.number > 9999
    || !finite(operation.size) || operation.size < 12 || operation.size > 256 || (operation.kind === 'number' && !validPoint(operation.point, size)))) throw new Error('序号或大小无效。');
  if (operation.kind === 'mosaic' && (!Number.isSafeInteger(operation.blockSize) || operation.blockSize < 4 || operation.blockSize > 128)) throw new Error('马赛克大小无效。');
}
function immutableOperation(operation: EditOperation): EditOperation {
  const copy = { ...operation };
  if ('rect' in copy) copy.rect = { ...copy.rect };
  if ('point' in copy) copy.point = { ...copy.point };
  if ('start' in copy) { copy.start = { ...copy.start }; copy.end = { ...copy.end }; }
  for (const value of Object.values(copy)) if (value && typeof value === 'object') Object.freeze(value);
  return Object.freeze(copy);
}
/** Bounded structural snapshots: each state shares immutable operations, never pixels.
 * Editing an older annotation preserves its z-order, including later redactions. */
export class ScreenshotDocument {
  readonly original: Readonly<Size>;
  private states: { id: number; operations: readonly EditOperation[] }[] = [{ id: 0, operations: Object.freeze([]) }];
  private cursor = 0;
  private nextId = 1;
  constructor(size: Size) { validateSize(size); this.original = Object.freeze({ width: size.width, height: size.height }); }
  get operations(): readonly EditOperation[] { return this.states[this.cursor].operations; }
  get stateId(): number { return this.states[this.cursor].id; }
  get canUndo(): boolean { return this.cursor > 0; }
  get canRedo(): boolean { return this.cursor < this.states.length - 1; }
  get size(): Size { return this.operationSize(this.operations.length); }
  // Count even crop-hidden numbers: undoing a crop must not reveal duplicates.
  get nextNumber(): number { return this.operations.reduce((n, op) => 'number' in op ? Math.max(n, op.number + 1) : n, 1); }
  operationSize(index: number): Size {
    if (!Number.isSafeInteger(index) || index < 0 || index > this.operations.length) throw new Error('标注位置无效。');
    return this.operations.slice(0, index).reduce((size, op) => op.kind === 'crop' ? { width: op.rect.width, height: op.rect.height } : size, { ...this.original });
  }
  operationOffset(index: number): Point {
    this.operationSize(index);
    return this.operations.slice(index + 1).reduce((offset, op) => op.kind === 'crop' ? { x: offset.x + op.rect.x, y: offset.y + op.rect.y } : offset, { x: 0, y: 0 });
  }
  private commit(operations: readonly EditOperation[]): void {
    if (operations.length > MAX_OPERATIONS) throw new Error('已达到 500 步编辑上限。请保存图片，再打开已保存的图片继续编辑。');
    let size: Size = this.original;
    for (const operation of operations) { validateOperation(operation, size); if (operation.kind === 'crop') size = operation.rect; }
    if (replayCost(this.original, operations) > MAX_REPLAY_PIXELS) throw new Error('这张大图的编辑量已达到安全上限。请保存图片，再打开保存结果继续编辑。');
    this.states.splice(this.cursor + 1, this.states.length, { id: this.nextId++, operations: Object.freeze([...operations]) });
    this.cursor++;
    if (this.states.length > MAX_UNDO + 1) { this.states.shift(); this.cursor--; }
  }
  append(operation: EditOperation): void { this.commit([...this.operations, immutableOperation(operation)]); }
  update(index: number, operation: EditOperation): void {
    const previous = this.operations[index];
    if (!previous || previous.kind === 'crop' || operation.kind === 'crop' || previous.kind !== operation.kind) throw new Error('不能修改裁剪或不存在的标注。');
    const operations = [...this.operations]; operations[index] = immutableOperation(operation); this.commit(operations);
  }
  remove(index: number): void {
    const previous = this.operations[index];
    if (!previous || previous.kind === 'crop') throw new Error('不能删除裁剪或不存在的标注。');
    this.commit(this.operations.filter((_, i) => i !== index));
  }
  undo(): boolean { if (!this.canUndo) return false; this.cursor--; return true; }
  redo(): boolean { if (!this.canRedo) return false; this.cursor++; return true; }
}

export type TextMeasure = (text: string) => number;
/** Geometry is in the operation's original coordinate stage, before later crops.
 * Pass a measure function using screenshotTextFont(op.size) for exact text bounds. */
export function operationBounds(operation: EditOperation, measure?: TextMeasure): Rect {
  if ('rect' in operation) return { ...operation.rect };
  if (operation.kind === 'text') {
    const textMeasure = measure ?? ((text: string) => [...text].length * operation.size);
    const lines = wrapText(operation.text, operation.maxWidth, textMeasure);
    return { x: operation.point.x, y: operation.point.y, width: Math.max(1, ...lines.map(textMeasure)), height: lines.length * operation.size * 1.35 };
  }
  if (operation.kind === 'number') return { x: operation.point.x - operation.size / 2, y: operation.point.y - operation.size / 2, width: operation.size, height: operation.size };
  const padding = operation.kind === 'numbered-arrow' ? Math.max(operation.size / 2, operation.width * 4, 10) : Math.max(operation.width * 4, 10);
  return { x: Math.min(operation.start.x, operation.end.x) - padding, y: Math.min(operation.start.y, operation.end.y) - padding,
    width: Math.abs(operation.end.x - operation.start.x) + padding * 2, height: Math.abs(operation.end.y - operation.start.y) + padding * 2 };
}
/** Clamp one common delta, so number+arrow cannot split or distort during a drag.
 * Text may already wrap/clip; keep its wrapping width when moving its anchor. */
export function translateOperation(operation: EditOperation, delta: Point, size: Size): EditOperation {
  if (!finite(delta.x) || !finite(delta.y)) throw new Error('移动位置无效。');
  if (operation.kind === 'crop') throw new Error('裁剪不能作为标注移动。');
  let anchors: Point[];
  if ('rect' in operation) anchors = [{ x: operation.rect.x, y: operation.rect.y }, { x: operation.rect.x + operation.rect.width, y: operation.rect.y + operation.rect.height }];
  else if ('start' in operation) anchors = [operation.start, operation.end];
  else anchors = [operation.point];
  let dx = clamp(delta.x, -Math.min(...anchors.map(p => p.x)), size.width - Math.max(...anchors.map(p => p.x)));
  let dy = clamp(delta.y, -Math.min(...anchors.map(p => p.y)), size.height - Math.max(...anchors.map(p => p.y)));
  if ('rect' in operation) { dx = Math.round(dx); dy = Math.round(dy); return { ...operation, rect: { ...operation.rect, x: operation.rect.x + dx, y: operation.rect.y + dy } }; }
  if ('start' in operation) return { ...operation, start: { x: operation.start.x + dx, y: operation.start.y + dy }, end: { x: operation.end.x + dx, y: operation.end.y + dy } };
  return { ...operation, point: { x: operation.point.x + dx, y: operation.point.y + dy } };
}
export function screenshotTextFont(size: number): string {
  return `${size}px -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif`;
}
/** Real pixel replacement (not a reversible CSS blur). Transparent samples are
 * alpha-weighted; the mosaic is opaque so hidden RGB cannot survive redaction. */
export function mosaicPixels(pixels: Uint8ClampedArray, width: number, height: number, blockSize: number): void {
  if (pixels.length !== width * height * 4 || !Number.isSafeInteger(blockSize) || blockSize < 1) throw new Error('无效的像素缓冲区。');
  for (let y = 0; y < height; y += blockSize) for (let x = 0; x < width; x += blockSize) {
    const right = Math.min(width, x + blockSize), bottom = Math.min(height, y + blockSize);
    let r = 0, g = 0, b = 0, alpha = 0;
    for (let yy = y; yy < bottom; yy++) for (let xx = x; xx < right; xx++) {
      const i = (yy * width + xx) * 4, a = pixels[i + 3]; alpha += a;
      r += pixels[i] * a; g += pixels[i + 1] * a; b += pixels[i + 2] * a;
    }
    for (let yy = y; yy < bottom; yy++) for (let xx = x; xx < right; xx++) {
      const i = (yy * width + xx) * 4;
      pixels[i] = alpha ? Math.round(r / alpha) : 0; pixels[i + 1] = alpha ? Math.round(g / alpha) : 0;
      pixels[i + 2] = alpha ? Math.round(b / alpha) : 0; pixels[i + 3] = 255;
    }
  }
}
export function wrapText(text: string, maxWidth: number, measure: (text: string) => number): string[] {
  const lines: string[] = [];
  for (const paragraph of text.replace(/\r\n?/g, '\n').split('\n')) {
    let line = '';
    for (const character of paragraph) {
      if (line && measure(line + character) > maxWidth) { lines.push(line); line = ''; }
      line += character;
    }
    lines.push(line);
  }
  return lines;
}
