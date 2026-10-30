export interface SourceDeliveryIdentity { deliveryId: number; presentationEpoch: number }
export interface QueuedDelivery<T> { payload: T; intentRevision: number }

/** One local copy until settings are ready. Events and startup pulls share IDs. */
export class SourceDeliveryInbox<T extends SourceDeliveryIdentity> {
  private latestId = 0;
  private pending: QueuedDelivery<T> | null = null;

  offer(payload: T, intentRevision: number): boolean {
    if (!Number.isSafeInteger(payload.deliveryId) || payload.deliveryId <= 0
      || !Number.isSafeInteger(payload.presentationEpoch) || payload.presentationEpoch < 0
      || payload.deliveryId <= this.latestId) return false;
    this.latestId = payload.deliveryId;
    this.pending = { payload, intentRevision };
    return true;
  }

  peek(): QueuedDelivery<T> | null { return this.pending; }
  isLatest(id: number): boolean { return id === this.latestId; }
  discard(id: number): void { if (this.pending?.payload.deliveryId === id) this.pending = null; }

  take(epoch: number, intentRevision: number, ready: boolean): (QueuedDelivery<T> & { apply: boolean }) | null {
    const item = this.pending;
    if (!ready || !item) return null;
    // Edits/navigation invalidate even a future-epoch result, without retaining
    // its text until another native event happens to arrive.
    if (item.intentRevision === intentRevision && item.payload.presentationEpoch > epoch) return null;
    this.pending = null;
    return { ...item, apply: item.intentRevision === intentRevision && item.payload.presentationEpoch === epoch };
  }
}

/** Late transport retries and failure feedback require an already-known
 * request boundary. They must not manufacture new intent over later edits. */
export function hasCurrentPresentationIntent(epoch: number | undefined, currentEpoch: number,
  bound: { epoch: number; intentRevision: number } | null, intentRevision: number): boolean {
  return epoch === currentEpoch && bound?.epoch === epoch && bound.intentRevision === intentRevision;
}
