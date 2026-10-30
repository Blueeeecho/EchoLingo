import { afterEach, describe, expect, it, vi } from 'vitest';
import { installPopupFocusRing } from './popup-focus';

class FakeElement {
  readonly attributes = new Map<string, string>();
  constructor(readonly toolbar = true) {}
  matches(): boolean { return this.toolbar; }
  setAttribute(name: string, value: string): void { this.attributes.set(name, value); }
  removeAttribute(name: string): void { this.attributes.delete(name); }
}
function fixture() {
  vi.useFakeTimers();
  const document = Object.assign(new EventTarget(), { activeElement: new FakeElement(), body: { dataset: {} as Record<string, string> } });
  const window = new EventTarget();
  vi.stubGlobal('HTMLElement', FakeElement); vi.stubGlobal('document', document); vi.stubGlobal('window', window);
  const dispose = installPopupFocusRing();
  const dispatch = (type: string, target: FakeElement, fields = {}) => {
    const event = Object.assign(new Event(type), fields);
    Object.defineProperty(event, 'target', { value: target }); document.dispatchEvent(event);
  };
  const focus = (target: FakeElement) => {
    dispatch('focusout', document.activeElement); document.activeElement = target; dispatch('focusin', target);
  };
  const key = (key: string, fields = {}) => dispatch('keydown', document.activeElement, { key, ...fields });
  const ring = (target = document.activeElement) => target.attributes.has('data-keyboard-focus');
  return { document, window, dispatch, dispose, focus, key, ring };
}
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
describe('popup toolbar focus origin', () => {
  it('keeps automatic/pointer focus quiet without moving focus and preserves keyboard navigation', () => {
    const f = fixture(), pin = f.document.activeElement, more = new FakeElement();
    f.focus(pin); expect(f.ring()).toBe(false);
    f.key('Tab'); f.focus(more); expect(f.ring(more)).toBe(true); expect(f.ring(pin)).toBe(false);
    f.key('Tab', { shiftKey: true }); f.focus(pin); expect(f.ring(pin)).toBe(true);
    f.dispatch('pointerdown', pin); expect(f.ring(pin)).toBe(false); expect(f.document.activeElement).toBe(pin);
    f.key(' '); expect(f.ring(pin)).toBe(true);
    f.window.dispatchEvent(new Event('blur')); expect(f.ring(pin)).toBe(false); expect(f.document.activeElement).toBe(pin);
    f.dispose(); expect(f.document.body.dataset.popupFocusManaged).toBeUndefined();
  });
  it('does not inherit old keyboard intent or affect source/management controls; teardown removes listeners', () => {
    const f = fixture(), pin = f.document.activeElement, source = new FakeElement(false);
    f.key('Tab'); vi.runAllTimers(); f.focus(new FakeElement()); expect(f.ring()).toBe(false);
    f.key('Tab'); f.focus(source); expect(f.ring(source)).toBe(false);
    f.focus(pin); f.key('Tab', { altKey: true }); expect(f.ring(pin)).toBe(false);
    vi.runAllTimers(); f.dispose(); f.key('Tab'); f.focus(pin); expect(f.ring(pin)).toBe(false);
  });
});
