/** CSS-local coordinates, never global desktop pixels. Clip optional monitor
 * bounds to the actual overlay viewport so negative origins cannot hide tools. */
export interface OverlayRect { x: number; y: number; width: number; height: number }
export function overlayToolBounds(width: number, height: number, monitor?: OverlayRect): OverlayRect {
  const viewport = { x: 0, y: 0, width: Math.max(1, width), height: Math.max(1, height) };
  if (!monitor || !Object.values(monitor).every(Number.isFinite) || monitor.width <= 0 || monitor.height <= 0) return viewport;
  const x = Math.max(0, monitor.x), y = Math.max(0, monitor.y);
  const right = Math.min(width, monitor.x + monitor.width), bottom = Math.min(height, monitor.y + monitor.height);
  return right > x && bottom > y ? { x, y, width: right - x, height: bottom - y } : viewport;
}
export function clampOverlayBox(x: number, y: number, width: number, height: number, bounds: OverlayRect): { x: number; y: number } {
  return { x: Math.max(bounds.x, Math.min(x, bounds.x + bounds.width - width)),
    y: Math.max(bounds.y, Math.min(y, bounds.y + bounds.height - height)) };
}
export function placeOverlayToolbar(selection: OverlayRect, width: number, height: number, bounds: OverlayRect): { x: number; y: number } {
  const gap = 10, below = selection.y + selection.height + gap, above = selection.y - height - gap;
  // Prefer below, then above. If neither fits, overlap is bounded by the monitor
  // rather than stranding completion controls outside it or inside a display gap.
  const y = below + height <= bounds.y + bounds.height ? below : above >= bounds.y ? above : below;
  return clampOverlayBox(selection.x + selection.width - width, y, width, height, bounds);
}
