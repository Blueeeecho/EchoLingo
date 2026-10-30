import { describe, expect, it, vi } from 'vitest';
import { RELEASES_PAGE, UpdateNotice, updateStatusText, type UpdateStatus } from './update-notice';

const empty: UpdateStatus = { available: null, checkedAt: null, failed: false };
const available: UpdateStatus = { available: { version: '0.3.0', prerelease: true }, checkedAt: 10, failed: false };
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function setup() {
  const actions = { read: vi.fn(async () => empty), check: vi.fn(async (_manual: boolean) => empty), open: vi.fn(async () => {}), changed: vi.fn() };
  return { actions, notice: new UpdateNotice(actions) };
}

describe('free update notice lifecycle', () => {
  it('loads local cached notices without a network check or browser navigation', async () => {
    const { notice, actions } = setup(); actions.read.mockResolvedValue(available);
    await notice.refresh();
    expect(notice.status).toEqual(available);
    expect(actions.check).not.toHaveBeenCalled(); expect(actions.open).not.toHaveBeenCalled();
    expect(RELEASES_PAGE).toBe('https://github.com/Blueeeecho/EchoLingo/releases');
  });
  it('coalesces double-clicks and does not navigate when a result arrives', async () => {
    const { notice, actions } = setup(); const pending = deferred<UpdateStatus>();
    actions.check.mockReturnValue(pending.promise);
    const first = notice.check(true); const duplicate = notice.check(true);
    expect(first).toBe(duplicate); expect(notice.checking).toBe(true);
    await Promise.resolve(); expect(actions.check).toHaveBeenCalledTimes(1);
    pending.resolve(available); await first;
    expect(notice.checking).toBe(false); expect(notice.status).toEqual(available);
    expect(actions.open).not.toHaveBeenCalled();
  });
  it('keeps the previous notice on offline failure and always releases busy state', async () => {
    const { notice, actions } = setup(); actions.read.mockResolvedValue(available); await notice.refresh();
    actions.check.mockRejectedValue(new Error('offline internal URL detail'));
    await notice.check(true);
    expect(notice.status).toEqual({ ...available, failed: true }); expect(notice.checking).toBe(false);
    expect(updateStatusText(notice.status, false)).toContain('上次检查结果');
    expect(updateStatusText(notice.status, false)).not.toContain('internal');
  });
  it('channel change ignores an older successful request and keeps the new local snapshot', async () => {
    const { notice, actions } = setup(); const pending = deferred<UpdateStatus>();
    actions.check.mockReturnValue(pending.promise); const request = notice.check(true);
    await Promise.resolve(); notice.invalidate(); actions.read.mockResolvedValue({ ...empty, checkedAt: 20 });
    await notice.refresh(); pending.resolve(available); await request;
    expect(notice.status).toEqual({ ...empty, checkedAt: 20 }); expect(notice.checking).toBe(false);
  });
  it('ignores a stale failed request and stale cache read after a newer manual result', async () => {
    const { notice, actions } = setup(); const cached = deferred<UpdateStatus>();
    actions.read.mockReturnValue(cached.promise); const read = notice.refresh();
    actions.check.mockResolvedValue(available); await notice.check(true);
    cached.resolve(empty); await read; expect(notice.status).toEqual(available);
    const pending = deferred<UpdateStatus>(); actions.check.mockReturnValue(pending.promise);
    const request = notice.check(false); await Promise.resolve(); notice.invalidate();
    actions.read.mockResolvedValue(empty); await notice.refresh(); pending.reject('old error'); await request;
    expect(notice.status).toEqual(empty);
  });
  it('disposal never emits a late render or opens the browser', async () => {
    const { notice, actions } = setup(); const pending = deferred<UpdateStatus>();
    actions.check.mockReturnValue(pending.promise); const request = notice.check(false);
    await Promise.resolve(); notice.dispose(); actions.changed.mockClear(); pending.resolve(available); await request;
    await notice.check(true); await notice.open();
    expect(actions.changed).not.toHaveBeenCalled(); expect(actions.check).toHaveBeenCalledTimes(1);
    expect(actions.open).not.toHaveBeenCalled(); expect(notice.status).toBeNull();
  });
  it('does not dispatch a queued check after immediate disposal or invalidation', async () => {
    for (const cancel of ['dispose', 'invalidate'] as const) {
      const { notice, actions } = setup();
      const request = notice.check(false); notice[cancel](); await request;
      expect(actions.check).not.toHaveBeenCalled(); expect(notice.checking).toBe(false);
    }
  });
  it('serializes download-page clicks and allows a retry after browser failure', async () => {
    const { notice, actions } = setup(); const pending = deferred<void>();
    actions.open.mockReturnValue(pending.promise); const first = notice.open(); await notice.open();
    expect(actions.open).toHaveBeenCalledTimes(1); pending.reject(new Error('cannot open')); await first;
    expect(notice.openFailed).toBe(true); expect(notice.opening).toBe(false);
    actions.open.mockResolvedValue(); await notice.open(); expect(notice.openFailed).toBe(false);
  });
  it('has concise Chinese states without fake successful checks or invented dates', () => {
    expect(updateStatusText(null, false)).toContain('尚未检查');
    expect(updateStatusText(empty, true)).toBe('正在检查更新…');
    expect(updateStatusText({ ...empty, failed: true }, false)).toContain('不影响翻译');
    expect(updateStatusText({ ...empty, checkedAt: 1 }, false)).toContain('所选版本通道');
    expect(updateStatusText(available, false)).toContain('0.3.0（内测版）');
  });
});
