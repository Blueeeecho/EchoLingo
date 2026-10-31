import { afterEach, describe, expect, it, vi } from 'vitest';
import { layoutViewport, viewportMatches, waitForViewport, type LayoutViewport } from '../src/popup-viewport';
const target: LayoutViewport = { width: 680, height: 240, scaleFactor: 2, presentationEpoch: 3 };
afterEach(() => vi.useRealTimers());

describe('popup viewport acknowledgement', () => {
  it('accepts only finite native geometry with a presentation identity', () => {
    expect(layoutViewport(target)).toEqual(target);
    for (const bad of [null, undefined, {}, { ...target, width: 0 }, { ...target, height: Infinity },
      { ...target, scaleFactor: NaN }, { ...target, presentationEpoch: -1 }, { ...target, presentationEpoch: 1.5 }]) {
      expect(layoutViewport(bad)).toBeNull();
    }
  });
  it('allows point rounding, not old width, old height, or an old backing scale', () => {
    expect(viewportMatches(target, { width: 680.5, height: 239.5, scaleFactor: 2 })).toBe(true);
    for (const actual of [{ width: 640, height: 240, scaleFactor: 2 }, { width: 680, height: 720, scaleFactor: 2 },
      { width: 680, height: 240, scaleFactor: 1 }]) expect(viewportMatches(target, actual)).toBe(false);
  });
  it('does not add a frame or fixed delay when the viewport already matches', async () => {
    const subscribe = vi.fn();
    expect(await waitForViewport({ ready: () => true, current: () => true, subscribe, signal: new AbortController().signal })).toBe(true);
    expect(subscribe).not.toHaveBeenCalled();
  });
  it('waits for real viewport adoption after native geometry replied, then immediately cleans up', async () => {
    vi.useFakeTimers();
    let adopted = false, check = () => {}; const remove = vi.fn();
    const done = vi.fn();
    const pending = waitForViewport({ ready: () => adopted, current: () => true, signal: new AbortController().signal,
      subscribe: callback => { check = callback; return remove; } }).then(value => { done(); return value; });
    await Promise.resolve(); expect(done).not.toHaveBeenCalled();
    adopted = true; check();
    expect(await pending).toBe(true); expect(remove).toHaveBeenCalledTimes(1); expect(vi.getTimerCount()).toBe(0);
  });
  it('uses the latest geometry, including changes during a manual resize', async () => {
    let expected = target, actual = { width: 640, height: 720, scaleFactor: 2 }, check = () => {};
    const pending = waitForViewport({ ready: () => viewportMatches(expected, actual), current: () => true,
      signal: new AbortController().signal, subscribe: callback => { check = callback; return () => {}; } });
    expected = { ...target, width: 713, height: 469 };
    actual = { width: 713, height: 469, scaleFactor: 2 }; check();
    expect(await pending).toBe(true);
  });
  it('cancels on a newer presentation or disposal and never treats it as viewport success', async () => {
    for (const abort of [false, true]) {
      const controller = new AbortController(); let current = true, check = () => {}; const remove = vi.fn();
      const pending = waitForViewport({ ready: () => false, current: () => current, signal: controller.signal,
        subscribe: callback => { check = callback; return remove; } });
      if (abort) controller.abort(); else { current = false; check(); }
      expect(await pending).toBe(false); expect(remove).toHaveBeenCalledTimes(1);
    }
  });
  it('cleans up exactly once when subscription synchronously adopts the viewport', async () => {
    vi.useFakeTimers(); let ready = false; const remove = vi.fn();
    const pending = waitForViewport({ ready: () => ready, current: () => true, signal: new AbortController().signal,
      subscribe: check => { ready = true; check(); return remove; } });
    expect(await pending).toBe(true); expect(remove).toHaveBeenCalledTimes(1); expect(vi.getTimerCount()).toBe(0);
  });
  it('fails a stalled viewport instead of silently presenting stale geometry', async () => {
    vi.useFakeTimers(); const remove = vi.fn();
    const pending = waitForViewport({ ready: () => false, current: () => true, signal: new AbortController().signal,
      subscribe: () => remove });
    const rejection = expect(pending).rejects.toThrow('WINDOW_LAYOUT:');
    await vi.advanceTimersByTimeAsync(1500); await rejection;
    expect(remove).toHaveBeenCalledTimes(1); expect(vi.getTimerCount()).toBe(0);
  });
});
