import { selectionRect, type EditOperation, type Point, type Size } from './screenshot-model';
export interface DraftStyle { color: string; width: number; fontSize: number; blockSize: number; ellipse: boolean; numberThreshold: number }
/** The preview and commit share an operation; creating it never advances history or numbering. */
export function draftAnnotation(tool: string, start: Point, end: Point, size: Size, style: DraftStyle, nextNumber: number, points?: Point[]): EditOperation | null {
  const { color, width } = style;
  const distance = Math.hypot(end.x - start.x, end.y - start.y);
  if (tool === 'number') return distance < style.numberThreshold
    ? { kind: 'number', point: start, number: nextNumber, size: style.fontSize, color }
    : { kind: 'numbered-arrow', start, end, number: nextNumber, size: style.fontSize, color, width };
  if ((tool === 'pen' || tool === 'highlight') && points) return { kind: tool, points, color, width: width * (tool === 'highlight' ? 4 : 1) };
  if (distance < 1) return null;
  if (tool === 'arrow') return { kind: 'arrow', start, end, color, width };
  const rect = selectionRect(start, end, size);
  if (!rect.width || !rect.height) return null;
  if (tool === 'mosaic') return { kind: 'mosaic', rect, blockSize: style.blockSize };
  if (tool === 'rectangle') return style.ellipse ? { kind: 'ellipse', rect, color, width } : { kind: 'rectangle', rect, color, width, solid: false };
  if (tool === 'solid') return { kind: 'rectangle', rect, color, width, solid: true };
  return null;
}
