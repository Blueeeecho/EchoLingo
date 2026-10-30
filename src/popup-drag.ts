// macOS WebView IPC is asynchronous. Do not ask AppKit to drag using whatever
// NSApp.currentEvent happens to be when it arrives. A real drag has a threshold,
// an original toolbar-local anchor and a native current-presentation token.
export interface DragPress { pointerId: number; screenX: number; screenY: number; anchorX: number; anchorY: number; epoch: number }
interface Gesture extends DragPress { token: number | null; starting: boolean; moving: boolean; frame: number | null; crossed: boolean }
export interface PopupDragHost {
  valid(epoch: number): boolean;
  begin(press: DragPress): Promise<number>;
  move(id: number): Promise<unknown>;
  end(id: number): Promise<unknown>;
  settled(): void;
  active(value: boolean): void;
}
export interface DragFrameClock { request(callback: () => void): number; cancel(id: number): void }
export class PopupDragController {
  private gesture: Gesture | null = null;
  constructor(private host: PopupDragHost, private clock: DragFrameClock = {
    request: callback => requestAnimationFrame(callback), cancel: id => cancelAnimationFrame(id),
  }) {}
  press(press: DragPress): void {
    this.cancel();
    if (this.host.valid(press.epoch)) this.gesture = { ...press, token: null, starting: false, moving: false, frame: null, crossed: false };
  }
  move(pointerId: number, screenX: number, screenY: number, buttons: number): void {
    const gesture = this.gesture;
    if (!gesture || gesture.pointerId !== pointerId) return;
    if (!(buttons & 1) || !this.host.valid(gesture.epoch)) { this.cancel(); return; }
    if (!gesture.crossed) {
      if (Math.hypot(screenX - gesture.screenX, screenY - gesture.screenY) < 4) return;
      gesture.crossed = true;
      this.host.active(true);
    }
    if (gesture.token !== null) { this.schedule(gesture); return; }
    if (gesture.starting) return;
    gesture.starting = true;
    void this.host.begin(gesture).then(token => {
      if (!Number.isSafeInteger(token) || token <= 0) throw new Error('Invalid drag token');
      if (this.gesture !== gesture || !this.host.valid(gesture.epoch)) { void this.finish(token); return; }
      gesture.token = token;
      void this.drain(gesture);
    }).catch(() => { if (this.gesture === gesture) this.cancel(); });
  }
  private schedule(gesture: Gesture): void {
    if (this.gesture !== gesture || gesture.frame !== null || gesture.moving) return;
    gesture.frame = this.clock.request(() => {
      gesture.frame = null;
      if (this.gesture === gesture) void this.drain(gesture);
    });
  }
  private async drain(gesture: Gesture): Promise<void> {
    if (gesture.moving || gesture.token === null || this.gesture !== gesture) return;
    if (!this.host.valid(gesture.epoch)) { this.cancel(); return; }
    gesture.moving = true;
    try {
      // Once the native physical-press token exists, sample the native cursor
      // every frame. Moving a WKWebView can stop its client pointermove stream;
      // that is not evidence that the physical mouse has stopped or released.
      // Only one IPC is outstanding; native code rejects released/new presses.
      if (await this.host.move(gesture.token) === false) throw new Error('Native drag rejected');
    } catch { if (this.gesture === gesture) this.cancel(); }
    finally {
      gesture.moving = false;
      if (this.gesture === gesture) {
        if (!this.host.valid(gesture.epoch)) this.cancel(); else this.schedule(gesture);
      }
    }
  }
  retainsNativeGesture(pointerId: number): boolean {
    return this.gesture?.pointerId === pointerId && this.gesture.token !== null && this.check();
  }
  release(pointerId: number): boolean {
    if (!this.gesture || this.gesture.pointerId !== pointerId) return false;
    const crossed = this.gesture.crossed;
    this.cancel();
    return crossed;
  }
  check(): boolean { if (this.gesture && !this.host.valid(this.gesture.epoch)) this.cancel(); return this.gesture !== null; }
  cancel(): void {
    const previous = this.gesture;
    this.gesture = null;
    if (previous?.frame !== null && previous?.frame !== undefined) this.clock.cancel(previous.frame);
    this.host.active(false);
    if (previous?.token !== null && previous?.token !== undefined) void this.finish(previous.token);
  }
  private async finish(token: number): Promise<void> {
    try { await this.host.end(token); } catch { /* Native epoch/button guards also end abandoned moves. */ }
    finally { this.host.settled(); }
  }
}
