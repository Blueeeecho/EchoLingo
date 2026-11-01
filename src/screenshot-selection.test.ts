import { describe, expect, it } from 'vitest';
import { adjustSelection, selectionCancelDisabled, type SelectionHandle } from './screenshot-selection';
const bounds = { x: 0, y: 0, width: 3000, height: 1200 }, rect = { x: 1500, y: 100, width: 400, height: 300 };
describe('persistent screenshot selection', () => {
  it('expands, shrinks and moves without requiring a bitmap or tool transition', () => {
    expect(adjustSelection(rect, 'nw', -100, -50, bounds)).toEqual({ x: 1400, y: 50, width: 500, height: 350 });
    expect(adjustSelection(rect, 'se', -100, -50, bounds)).toEqual({ ...rect, width: 300, height: 250 });
    expect(adjustSelection(rect, 'move', -1400, 30, bounds)).toEqual({ ...rect, x: 100, y: 130 });
  });
  it('bounds every corner/edge and retains a two-logical-pixel minimum', () => {
    for (const handle of ['n','ne','e','se','s','sw','w','nw','move'] as SelectionHandle[]) for (const d of [-99999,99999]) {
      const r = adjustSelection(rect, handle, d, d, bounds);
      expect(r.width).toBeGreaterThanOrEqual(2); expect(r.height).toBeGreaterThanOrEqual(2);
      expect(r.x).toBeGreaterThanOrEqual(0); expect(r.y).toBeGreaterThanOrEqual(0);
      expect(r.x+r.width).toBeLessThanOrEqual(bounds.width); expect(r.y+r.height).toBeLessThanOrEqual(bounds.height);
    }
  });
  it('does not assume positive global monitor origins or integral scale', () => {
    const b = { x:-1920,y:-180,width:4480,height:1620 };
    expect(adjustSelection({x:-100,y:0,width:120.5,height:90.25},'move',-200,10,b)).toEqual({x:-300,y:10,width:120.5,height:90.25});
  });
  it('rejects nonfinite geometry', () => { expect(()=>adjustSelection(rect,'move',NaN,0,bounds)).toThrow(); });
});

it('only permits busy cancellation for capture or geometry update, never export/dialog', () => {
  expect(selectionCancelDisabled(true,true,false,false)).toBe(false);
  expect(selectionCancelDisabled(true,false,true,false)).toBe(false);
  expect(selectionCancelDisabled(true,false,false,false)).toBe(true);
  expect(selectionCancelDisabled(true,true,false,true)).toBe(true);
  expect(selectionCancelDisabled(false,false,false,false)).toBe(false);
});
