// macOS WebView IPC is asynchronous. Do not ask AppKit to drag using whatever
// NSApp.currentEvent happens to be when it arrives. A real drag has a threshold,
// an original toolbar-local anchor and a native current-presentation token.
export interface DragPress { pointerId: number; screenX: number; screenY: number; anchorX: number; anchorY: number; epoch: number }
interface Gesture extends DragPress { token: number | null; starting: boolean; moving: boolean; pending: boolean; crossed: boolean }
export interface PopupDragHost {
  valid(epoch: number): boolean;
  begin(press: DragPress): Promise<number>;
  move(id: number): Promise<unknown>;
  end(id: number): Promise<unknown>;
  settled(): void;
  active(value: boolean): void;
}
export class PopupDragController {
  private gesture: Gesture | null = null;
  constructor(private host: PopupDragHost) {}
  press(press: DragPress): void {
    this.cancel();
    if (this.host.valid(press.epoch)) this.gesture = { ...press, token: null, starting: false, moving: false, pending: false, crossed: false };
  }
  move(pointerId: number, screenX: number, screenY: number, buttons: number): void {
    const gesture = this.gesture;
    if (!gesture || gesture.pointerId !== pointerId) return;
    if (!(buttons & 1) || !this.host.valid(gesture.epoch)) { this.cancel(); return; }
    if (!gesture.crossed && Math.hypot(screenX - gesture.screenX, screenY - gesture.screenY) < 4) return;
    gesture.crossed = true;
    gesture.pending = true;
    this.host.active(true);
    if (gesture.token !== null) { void this.drain(gesture); return; }
    if (gesture.starting) return;
    gesture.starting = true;
    void this.host.begin(gesture).then(token => {
      if (!Number.isSafeInteger(token) || token <= 0) throw new Error('Invalid drag token');
      if (this.gesture !== gesture || !this.host.valid(gesture.epoch)) { void this.finish(token); return; }
      gesture.token = token;
      void this.drain(gesture);
    }).catch(() => { if (this.gesture === gesture) this.cancel(); });
  }
  private async drain(gesture: Gesture): Promise<void> {
    if (gesture.moving || gesture.token === null) return;
    gesture.moving = true;
    try {
      while (this.gesture === gesture && gesture.pending && this.host.valid(gesture.epoch)) {
        gesture.pending = false;
        await this.host.move(gesture.token);
      }
      if (this.gesture === gesture && !this.host.valid(gesture.epoch)) this.cancel();
    } catch { if (this.gesture === gesture) this.cancel(); }
    finally { gesture.moving = false; }
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
    this.host.active(false);
    if (previous?.token !== null && previous?.token !== undefined) void this.finish(previous.token);
  }
  private async finish(token: number): Promise<void> {
    try { await this.host.end(token); } catch { /* Native epoch/button guards also end abandoned moves. */ }
    finally { this.host.settled(); }
  }
}
