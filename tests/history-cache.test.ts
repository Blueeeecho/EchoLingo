import { describe, expect, it, vi } from 'vitest';
import { HistoryCache } from '../src/history-cache';
import type { HistoryEntry } from '../src/types';

const entry = (id: string): HistoryEntry => ({
  id, text: id, createdAt: 1792890000000, sourceLanguage: 'en',
  targetLanguage: 'zh-Hans', results: [], favorite: false,
});
const deferred = <T>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
};

describe('lazy history cache', () => {
  it('does not read or render hidden history, including repeated mutations', async () => {
    let visible = false;
    const fetch = vi.fn(async () => [entry('latest')]);
    const render = vi.fn();
    const cache = new HistoryCache(fetch, () => visible, render);
    await cache.load(); await cache.refresh(); await cache.refresh();
    expect(fetch).not.toHaveBeenCalled(); expect(render).not.toHaveBeenCalled();
    visible = true;
    await cache.load();
    expect(fetch).toHaveBeenCalledTimes(1); expect(cache.entries[0].id).toBe('latest');
    expect(render).toHaveBeenCalledTimes(1);
    visible = false; await cache.load(); visible = true; await cache.load();
    expect(fetch).toHaveBeenCalledTimes(1); expect(render).toHaveBeenCalledTimes(2);
  });

  it('coalesces repeated opens and does not render a read completed while hidden', async () => {
    let visible = true;
    const first = deferred<HistoryEntry[]>();
    const fetch = vi.fn(() => first.promise), render = vi.fn();
    const cache = new HistoryCache(fetch, () => visible, render);
    const reads = [cache.load(), cache.load(), cache.load()];
    expect(fetch).toHaveBeenCalledTimes(1);
    visible = false; first.resolve([entry('cached')]);
    await Promise.all(reads);
    expect(render).not.toHaveBeenCalled();
    visible = true; await cache.load();
    expect(fetch).toHaveBeenCalledTimes(1); expect(render).toHaveBeenCalledTimes(1);
    expect(cache.entries[0].id).toBe('cached');
  });

  it('keeps mutations dirty when a stale in-flight read completes after hiding', async () => {
    let visible = true;
    const first = deferred<HistoryEntry[]>();
    const fetch = vi.fn().mockReturnValueOnce(first.promise).mockResolvedValue([entry('new')]);
    const render = vi.fn();
    const cache = new HistoryCache(fetch, () => visible, render);
    const read = cache.load();
    visible = false; await cache.refresh(); first.resolve([entry('old')]); await read;
    expect(cache.entries).toEqual([]); expect(render).not.toHaveBeenCalled();
    expect(fetch).toHaveBeenCalledTimes(1);
    visible = true; await cache.load();
    expect(cache.entries[0].id).toBe('new'); expect(fetch).toHaveBeenCalledTimes(2);
  });

  it('coalesces concurrent mutations and renders only their latest snapshot', async () => {
    const first = deferred<HistoryEntry[]>();
    const fetch = vi.fn().mockReturnValueOnce(first.promise).mockResolvedValue([entry('new')]);
    const render = vi.fn();
    const cache = new HistoryCache(fetch, () => true, render);
    const reads = [cache.load(), cache.refresh(), cache.refresh()];
    expect(fetch).toHaveBeenCalledTimes(1);
    first.resolve([entry('old')]); await Promise.all(reads);
    expect(fetch).toHaveBeenCalledTimes(2); expect(render).toHaveBeenCalledTimes(1);
    expect(cache.entries[0].id).toBe('new');
  });

  it('does not lose a refresh between the last revision check and promise settlement', async () => {
    const fetch = vi.fn().mockResolvedValueOnce([entry('first')]).mockResolvedValue([entry('new')]);
    let lateRefresh: Promise<void> | undefined;
    const cache = new HistoryCache(fetch, () => true, () => {
      if (cache.entries[0].id === 'first') lateRefresh = cache.refresh();
    });
    await cache.load(); await lateRefresh;
    expect(fetch).toHaveBeenCalledTimes(2); expect(cache.entries[0].id).toBe('new');
  });

  it('retries failed fetches without losing the prior snapshot or dirty revision', async () => {
    const fetch = vi.fn().mockResolvedValueOnce([entry('old')])
      .mockRejectedValueOnce(new Error('read failed')).mockResolvedValue([entry('new')]);
    const render = vi.fn();
    const cache = new HistoryCache(fetch, () => true, render);
    await cache.load();
    await expect(cache.refresh()).rejects.toThrow('read failed');
    expect(cache.entries[0].id).toBe('old'); expect(render).toHaveBeenCalledTimes(1);
    await cache.load();
    expect(cache.entries[0].id).toBe('new'); expect(fetch).toHaveBeenCalledTimes(3);
  });
});
