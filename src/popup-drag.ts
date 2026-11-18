// Only this measured blank-header rectangle is registered with AppKit.
// WebView events never start, sample, or end the native gesture.
export function popupHeaderRegion(rect: { x: number; y: number; width: number; height: number } | null,
  viewportWidth: number, viewportHeight: number, enabled: boolean) {
  const valid = enabled && rect && [rect.x, rect.y, rect.width, rect.height, viewportWidth, viewportHeight].every(Number.isFinite)
    && rect.x >= 0 && rect.y >= 0 && rect.width > 0 && rect.height > 0
    && rect.x + rect.width <= viewportWidth && rect.y + rect.height <= 32;
  return { x: valid ? rect.x : 0, y: valid ? rect.y : 0,
    width: valid ? rect.width : 0, height: valid ? rect.height : 0,
    viewportWidth: Math.max(1, viewportWidth), viewportHeight: Math.max(1, viewportHeight) };
}
