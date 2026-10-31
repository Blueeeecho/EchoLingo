// Native geometry and the WebView viewport are acknowledged independently.
// This is not a promise that the OS compositor has painted a sharp frame.
export interface LayoutViewport { width: number; height: number; scaleFactor: number; presentationEpoch: number }
export interface WebViewport { width: number; height: number; scaleFactor: number }

export function layoutViewport(value: unknown): LayoutViewport | null {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as LayoutViewport;
  return [candidate.width, candidate.height, candidate.scaleFactor].every(n => Number.isFinite(n) && n > 0 && n <= 100_000)
    && Number.isSafeInteger(candidate.presentationEpoch) && candidate.presentationEpoch >= 0 ? candidate : null;
}
export function viewportMatches(expected: LayoutViewport, actual: WebViewport): boolean {
  // CSS viewport dimensions are integer-rounded, whereas native points can be
  // fractional on mixed-DPI displays. A different backing scale still waits.
  return Math.abs(expected.width - actual.width) <= 1 && Math.abs(expected.height - actual.height) <= 1
    && Math.abs(expected.scaleFactor - actual.scaleFactor) < 0.01;
}

export function waitForViewport(options: {
  ready: () => boolean;
  current: () => boolean;
  subscribe: (check: () => void) => () => void;
  signal: AbortSignal;
  timeoutMs?: number;
}): Promise<boolean> {
  if (options.signal.aborted || !options.current()) return Promise.resolve(false);
  if (options.ready()) return Promise.resolve(true);
  return new Promise((resolve, reject) => {
    let unsubscribe = () => {}, settled = false;
    const cleanup = (): void => { clearTimeout(timeout); unsubscribe(); options.signal.removeEventListener('abort', aborted); };
    const finish = (value: boolean): void => { if (!settled) { settled = true; cleanup(); resolve(value); } };
    const check = (): void => {
      if (options.signal.aborted || !options.current()) finish(false);
      else if (options.ready()) finish(true);
    };
    const aborted = (): void => finish(false);
    // A failure deadline, not a delay before showing. Normal resize feedback
    // resolves immediately; a lost/stalled viewport cannot hang source delivery.
    const timeout = setTimeout(() => {
      if (options.signal.aborted || !options.current()) finish(false);
      else if (options.ready()) finish(true);
      else { settled = true; cleanup(); reject(new Error('WINDOW_LAYOUT: 窗口内容尺寸尚未就绪，请重新打开翻译窗口。')); }
    }, options.timeoutMs ?? 1500);
    options.signal.addEventListener('abort', aborted, { once: true });
    unsubscribe = options.subscribe(check);
    if (settled) unsubscribe(); else check();
  });
}
