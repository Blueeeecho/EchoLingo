import type { OverlayRect } from './screenshot-overlay-layout';
export type SelectionHandle = 'move' | 'n' | 'ne' | 'e' | 'se' | 's' | 'sw' | 'w' | 'nw';
/** Selection coordinates are local to the desktop-union viewport, not primary-screen coordinates. */
export function adjustSelection(rect: OverlayRect, handle: SelectionHandle, dx: number, dy: number, bounds: OverlayRect): OverlayRect {
  if (![...Object.values(rect), ...Object.values(bounds), dx, dy].every(Number.isFinite) || bounds.width < 2 || bounds.height < 2) throw new Error('截图范围无效');
  const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
  const minX = bounds.x, minY = bounds.y, maxX = minX + bounds.width, maxY = minY + bounds.height;
  const width = Math.min(Math.max(2, rect.width), bounds.width), height = Math.min(Math.max(2, rect.height), bounds.height);
  let left = clamp(rect.x, minX, maxX - width), top = clamp(rect.y, minY, maxY - height), right = left + width, bottom = top + height;
  if (handle === 'move') return { x: clamp(left + dx, minX, maxX - width), y: clamp(top + dy, minY, maxY - height), width, height };
  if (handle.includes('w')) left = clamp(left + dx, minX, right - 2);
  if (handle.includes('e')) right = clamp(right + dx, left + 2, maxX);
  if (handle.includes('n')) top = clamp(top + dy, minY, bottom - 2);
  if (handle.includes('s')) bottom = clamp(bottom + dy, top + 2, maxY);
  return { x: left, y: top, width: right - left, height: bottom - top };
}

/** Pending capture/geometry changes can be cancelled; committed exports and
 * owned native save dialogs remain mutually exclusive with cancellation. */
export function selectionCancelDisabled(busy: boolean, capturing: boolean, updating: boolean, nativeDialog: boolean): boolean {
  return nativeDialog || (busy && !capturing && !updating);
}
