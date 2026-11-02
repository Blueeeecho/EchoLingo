/** Only a primary, held pointer that actually moves may request native dragging. */
export class PinnedDragIntent {
  private start: { id: number; x: number; y: number } | null = null;
  begin(id: number, x: number, y: number, primary: boolean, button: number): void {
    if (this.start || !primary || button !== 0 || ![id, x, y].every(Number.isFinite)) return;
    this.start = { id, x, y };
  }
  move(id: number, x: number, y: number, buttons: number): boolean {
    const start = this.start;
    if (!start || start.id !== id) return false;
    if (!(buttons & 1)) { this.start = null; return false; }
    if (![x, y].every(Number.isFinite) || Math.hypot(x - start.x, y - start.y) < 4) return false;
    this.start = null;
    return true;
  }
  owns(id: number): boolean { return this.start?.id === id; }
  end(id?: number): void { if (id === undefined || this.owns(id)) this.start = null; }
}
