import { describe, expect, it } from 'vitest';
import { popupHeaderRegion } from '../src/popup-drag';
const header = { x: 37, y: 0, width: 400, height: 28 };
describe('AppKit blank-header registration', () => {
  it('registers only the measured blank space, retaining both control exclusions', () => {
    expect(popupHeaderRegion(header, 520, 400, true)).toEqual({ ...header, viewportWidth: 520, viewportHeight: 400 });
  });
  it.each([false, true])('never registers absent header (enabled=%s)', enabled => {
    expect(popupHeaderRegion(null, 520, 400, enabled).width).toBe(0);
  });
  it('modal, disposal and management disable the area', () => {
    expect(popupHeaderRegion(header, 520, 400, false).width).toBe(0);
  });
  it.each([{ ...header, y: 40 }, { ...header, x: -1 }, { ...header, height: 33 },
    { ...header, width: 600 }, { ...header, x: NaN }])('rejects content/outside/nonfinite rectangles', rect => {
      expect(popupHeaderRegion(rect, 520, 400, true).width).toBe(0);
  });
});
