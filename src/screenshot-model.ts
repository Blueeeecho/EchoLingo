/** Image-pixel coordinates only. Display zoom/DPR never enter the edit history. */
export interface Size { width: number; height: number }
export interface Point { x: number; y: number }
export interface Rect extends Point, Size {}
export type EditOperation =
  | { kind: 'rectangle'; rect: Rect; color: string; width: number; solid: boolean }
  | { kind: 'arrow'; start: Point; end: Point; color: string; width: number }
  | { kind: 'text'; point: Point; text: string; color: string; size: number; maxWidth: number }
  | { kind: 'mosaic'; rect: Rect; blockSize: number }
  | { kind: 'crop'; rect: Rect };
export const MAX_PIXELS = 32_000_000;
export const MAX_EDGE = 16_384;
export const MAX_ENCODED_BYTES = 32 * 1024 * 1024;
export const MAX_TEXT = 2_000;
export const MAX_OPERATIONS = 500;
export const MAX_UNDO = 100;
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
  if (operation.kind === 'arrow' && (!validPoint(operation.start, size) || !validPoint(operation.end, size))) throw new Error('箭头超出图片。');
  if (operation.kind === 'text' && (!validPoint(operation.point, size) || !operation.text.trim() || operation.text.length > MAX_TEXT
    || !finite(operation.size) || operation.size < 8 || operation.size > 256 || !finite(operation.maxWidth)
    || operation.maxWidth < 1 || operation.maxWidth > size.width)) throw new Error('文字或字号无效（最多 2000 字）。');
  if (operation.kind === 'mosaic' && (!Number.isSafeInteger(operation.blockSize) || operation.blockSize < 4 || operation.blockSize > 128)) throw new Error('马赛克大小无效。');
}
function immutableOperation(operation: EditOperation): EditOperation {
  const copy = structuredClone(operation);
  for (const value of Object.values(copy)) if (value && typeof value === 'object') Object.freeze(value);
  return Object.freeze(copy);
}
/** Immutable source + typed edits; at most 100 undo steps and 500 total operations.
 * No per-edit bitmap snapshots and no image bytes in settings/history/storage. */
export class ScreenshotDocument {
  readonly original: Readonly<Size>;
  private nodes: { id: number; operation: EditOperation }[] = [];
  private cursor = 0;
  private floor = 0;
  private nextId = 1;
  constructor(size: Size) { validateSize(size); this.original = Object.freeze({ width: size.width, height: size.height }); }
  get operations(): readonly EditOperation[] { return this.nodes.slice(0, this.cursor).map(node => node.operation); }
  get stateId(): number { return this.cursor ? this.nodes[this.cursor - 1].id : 0; }
  get canUndo(): boolean { return this.cursor > this.floor; }
  get canRedo(): boolean { return this.cursor < this.nodes.length; }
  get size(): Size { return this.operations.reduce((size, op) => op.kind === 'crop' ? { width: op.rect.width, height: op.rect.height } : size, { ...this.original }); }
  append(operation: EditOperation): void {
    validateOperation(operation, this.size);
    if (this.cursor >= MAX_OPERATIONS) throw new Error('已达到 500 步编辑上限。请保存图片，再打开已保存的图片继续编辑。');
    this.nodes.splice(this.cursor, this.nodes.length - this.cursor, { id: this.nextId++, operation: immutableOperation(operation) });
    this.cursor++; this.floor = Math.max(this.floor, this.cursor - MAX_UNDO);
  }
  undo(): boolean { if (!this.canUndo) return false; this.cursor--; return true; }
  redo(): boolean { if (!this.canRedo) return false; this.cursor++; return true; }
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
