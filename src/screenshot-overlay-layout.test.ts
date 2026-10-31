import { describe, expect, it } from 'vitest';
import { overlayToolBounds, placeOverlayToolbar } from './screenshot-overlay-layout';
describe('in-place toolbar monitor-local placement', () => {
  const bounds = { x: 1000, y: 100, width: 600, height: 400 };
  it('flips above bottom selections and clamps at left/right corners', () => {
    for (const x of [995, 1000, 1599]) {
      const point = placeOverlayToolbar({ x, y: 490, width: 1, height: 1 }, 280, 60, bounds);
      expect(point.y).toBe(420); expect(point.x).toBeGreaterThanOrEqual(1000); expect(point.x + 280).toBeLessThanOrEqual(1600);
    }
  });
  it('uses below at the top and bounded overlap when neither side fits', () => {
    expect(placeOverlayToolbar({ x: 1000, y: 100, width: 10, height: 1 }, 280, 60, bounds).y).toBe(111);
    const point = placeOverlayToolbar({ x: 1000, y: 100, width: 600, height: 400 }, 280, 60, bounds);
    expect(point.y).toBe(440);
  });
  it('clips negative local origins and does not spill into monitor gaps', () => {
    expect(overlayToolBounds(2400, 900, { x: -40, y: -20, width: 640, height: 500 })).toEqual({ x: 0, y: 0, width: 600, height: 480 });
    expect(overlayToolBounds(2400, 900, bounds)).toEqual(bounds);
    expect(overlayToolBounds(2400, 900, { x: 3000, y: 0, width: 200, height: 100 }).width).toBe(2400);
  });
  it('keeps tiny ROI toolbar inside narrow CSS viewport independent of DPR', () => {
    const narrow = overlayToolBounds(220, 300);
    for (const selection of [{ x: 0, y: 0, width: 1, height: 1 }, { x: 219, y: 299, width: 1, height: 1 }]) {
      const point = placeOverlayToolbar(selection, 204, 180, narrow);
      expect(point.x).toBeGreaterThanOrEqual(0); expect(point.x + 204).toBeLessThanOrEqual(220);
      expect(point.y).toBeGreaterThanOrEqual(0); expect(point.y + 180).toBeLessThanOrEqual(300);
    }
  });
});
