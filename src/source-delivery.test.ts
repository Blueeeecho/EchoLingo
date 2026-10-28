import { describe, expect, it } from 'vitest';
import { SourceDeliveryInbox } from './source-delivery';

const source = (deliveryId: number, presentationEpoch = 1) => ({ deliveryId, presentationEpoch, text: 'generated source' });

describe('native source delivery inbox', () => {
  it('retains an event before readiness and translates an event plus pull only once', () => {
    const inbox = new SourceDeliveryInbox<ReturnType<typeof source>>();
    const payload = source(1);
    expect(inbox.offer(payload, 0)).toBe(true);
    expect(inbox.take(1, 0, false)).toBeNull();
    expect(inbox.offer(payload, 0)).toBe(false);
    let translations = 0;
    if (inbox.take(1, 0, true)?.apply) translations++;
    expect(inbox.offer(payload, 0)).toBe(false);
    if (inbox.take(1, 0, true)?.apply) translations++;
    expect(translations).toBe(1);
  });

  it('retrieves a result produced before a listener without a live event', () => {
    const inbox = new SourceDeliveryInbox<ReturnType<typeof source>>();
    expect(inbox.offer(source(7), 0)).toBe(true);
    expect(inbox.take(1, 0, true)?.payload.deliveryId).toBe(7);
  });

  it('rejects replay after an edit or management navigation and after a new epoch', () => {
    for (const current of [{ epoch: 1, intent: 1 }, { epoch: 2, intent: 0 }]) {
      const inbox = new SourceDeliveryInbox<ReturnType<typeof source>>();
      inbox.offer(source(1), 0);
      expect(inbox.take(current.epoch, current.intent, true)?.apply).toBe(false);
      expect(inbox.take(current.epoch, current.intent, true)).toBeNull();
    }
  });

  it('keeps only the latest result and rejects an older in-flight delivery', () => {
    const inbox = new SourceDeliveryInbox<ReturnType<typeof source>>();
    inbox.offer(source(1), 0);
    const first = inbox.take(1, 0, true)!;
    inbox.offer(source(2, 2), 0);
    expect(inbox.isLatest(first.payload.deliveryId)).toBe(false);
    expect(inbox.take(1, 0, true)).toBeNull();
    expect(inbox.take(2, 0, true)?.apply).toBe(true);
    expect(inbox.offer(source(1), 0)).toBe(false);
  });

  it('does not admit malformed or unsafe delivery identities', () => {
    const inbox = new SourceDeliveryInbox<ReturnType<typeof source>>();
    for (const id of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, NaN]) expect(inbox.offer(source(id), 0)).toBe(false);
    expect(inbox.offer(source(1, -1), 0)).toBe(false);
    expect(inbox.peek()).toBeNull();
  });
});
