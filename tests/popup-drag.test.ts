import { describe, expect, it, vi } from 'vitest';
import { PopupDragController, type DragPress } from '../src/popup-drag';
const press: DragPress = { pointerId: 1, screenX: -1200, screenY: 240, anchorX: 130, anchorY: 18, epoch: 7 };
const tick = async () => { for (let n = 0; n < 8; n++) await Promise.resolve(); };
const deferred = <T>() => { let resolve!: (value: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; };
function fixture() {
  let epoch = 7, shown = true;
  const host = { valid: (value: number) => shown && value === epoch,
    begin: vi.fn(async (_value: DragPress) => 1), move: vi.fn(async (_id: number) => {}),
    end: vi.fn(async (_id: number) => {}), settled: vi.fn(), active: vi.fn() };
  return { host, drag: new PopupDragController(host), change: () => { epoch++; }, hide: () => { shown = false; } };
}
describe('Mac popup drag uses a real gesture rather than an asynchronous currentEvent', () => {
  it('single click and slight hand jitter never start native dragging or move a window', async () => {
    const { drag, host } = fixture(); drag.press(press); drag.move(1, -1198, 241, 1);
    expect(drag.release(1)).toBe(false); await tick();
    expect(host.begin).not.toHaveBeenCalled(); expect(host.move).not.toHaveBeenCalled();
  });
  it('threshold preserves the original local anchor, negative screen origin and epoch', async () => {
    const { drag, host } = fixture(); drag.press(press); drag.move(1, -1190, 250, 1); await tick();
    expect(host.begin).toHaveBeenCalledTimes(1);
    expect(host.begin.mock.calls[0][0]).toMatchObject(press);
    expect(host.move).toHaveBeenCalledWith(1);
    expect(drag.release(1)).toBe(true); await tick(); expect(host.end).toHaveBeenCalledWith(1); expect(host.settled).toHaveBeenCalled();
  });
  it('releasing while begin is pending ends its late token without any move', async () => {
    const { drag, host } = fixture(); const wait = deferred<number>(); host.begin.mockReturnValue(wait.promise);
    drag.press(press); drag.move(1, -1100, 250, 1); drag.release(1); wait.resolve(4); await tick();
    expect(host.move).not.toHaveBeenCalled(); expect(host.end).toHaveBeenCalledWith(4);
  });
  it.each(['hidden', 'epoch', 'cancel'] as const)('abandons pending begin on %s', async reason => {
    const { drag, host, change, hide } = fixture(); const wait = deferred<number>(); host.begin.mockReturnValue(wait.promise);
    drag.press(press); drag.move(1, -1100, 250, 1);
    if (reason === 'hidden') hide(); else if (reason === 'epoch') change(); else drag.cancel();
    drag.check(); wait.resolve(9); await tick(); expect(host.move).not.toHaveBeenCalled(); expect(host.end).toHaveBeenCalledWith(9);
  });
  it('ignores a different pointer and cancels a lost mouse-up on the next move', async () => {
    const { drag, host } = fixture(); drag.press(press); drag.move(77, -1000, 250, 1); expect(drag.release(77)).toBe(false);
    expect(host.begin).not.toHaveBeenCalled(); drag.move(1, -1000, 250, 0); await tick(); expect(host.begin).not.toHaveBeenCalled(); expect(drag.check()).toBe(false);
  });
  it('serializes moves and discards a coalesced movement when the presentation changes', async () => {
    const { drag, host, change } = fixture(); const wait = deferred<void>(); host.move.mockReturnValueOnce(wait.promise);
    drag.press(press); drag.move(1, -1100, 250, 1); await tick(); drag.move(1, -1000, 260, 1); change(); wait.resolve(); await tick();
    expect(host.move).toHaveBeenCalledTimes(1); expect(host.end).toHaveBeenCalledWith(1);
  });
  it('an old begin completing after a newer gesture cannot move or cancel the newer gesture', async () => {
    const { drag, host } = fixture(); const old = deferred<number>(); host.begin.mockReturnValueOnce(old.promise).mockResolvedValueOnce(2);
    drag.press(press); drag.move(1, -1100, 250, 1); drag.release(1);
    drag.press({ ...press, pointerId: 2 }); drag.move(2, -1100, 250, 1); await tick(); old.resolve(1); await tick();
    expect(host.end).toHaveBeenCalledWith(1); expect(host.move.mock.calls.every(([id]) => id === 2)).toBe(true); expect(drag.check()).toBe(true);
  });
  it('native rejection cancels the gesture and a later click cannot replay it', async () => {
    const { drag, host } = fixture(); host.move.mockRejectedValueOnce(new Error('stale / released'));
    drag.press(press); drag.move(1, -1100, 250, 1); await tick(); expect(drag.check()).toBe(false);
    drag.press(press); drag.release(1); await tick(); expect(host.move).toHaveBeenCalledTimes(1);
  });
});
