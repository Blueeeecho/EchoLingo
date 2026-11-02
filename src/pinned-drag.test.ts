import { describe, it, expect } from 'vitest';
import { PinnedDragIntent } from './pinned-drag';
describe('pinned image drag intent', () => {
  it('never drags clicks, jitter, release or cancelled gestures', () => {
    const d = new PinnedDragIntent();
    d.begin(1, 100, 90, true, 0);
    expect(d.move(1, 100, 90, 1)).toBe(false);
    expect(d.move(1, 102, 91, 1)).toBe(false);
    d.end(1); expect(d.move(1, 120, 90, 1)).toBe(false);
    d.begin(1, 100, 90, true, 0); d.end();
    expect(d.move(1, 120, 90, 1)).toBe(false);
    d.begin(1, 100, 90, true, 0);
    expect(d.move(1, 120, 90, 0)).toBe(false);
    expect(d.move(1, 120, 90, 1)).toBe(false);
  });
  it('keeps original pointer ownership and requests at most one drag', () => {
    const d = new PinnedDragIntent();
    d.begin(1, 20, 30, true, 0); d.begin(2, 0, 0, true, 0); d.end(2);
    expect(d.move(2, 100, 100, 1)).toBe(false);
    expect(d.move(1, 24, 30, 1)).toBe(true);
    expect(d.move(1, 50, 30, 1)).toBe(false);
  });
  it('rejects secondary buttons/nonprimary and uses local points independent of display origin/DPR', () => {
    const d = new PinnedDragIntent();
    d.begin(1, 0, 0, false, 0); expect(d.move(1, 10, 10, 1)).toBe(false);
    d.begin(1, 0, 0, true, 2); expect(d.move(1, 10, 10, 1)).toBe(false);
    for (const origin of [0, -1440, 3024]) {
      d.begin(1, origin + 20, 30, true, 0);
      expect(d.move(1, origin + 24, 30, 1)).toBe(true);
    }
  });
});
