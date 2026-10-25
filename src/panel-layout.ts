import { invoke } from '@tauri-apps/api/core';

export interface TranslationPresentation { epoch: number; presented: boolean }

// Read intrinsic content rather than viewport height, so a short translation
// can shrink again after a long result. Requests are coalesced and serialized.
export function installPanelLayout(desktop: boolean): { dispose: () => void; presentPopup: (presentationEpoch: number) => Promise<TranslationPresentation | null> } {
  if (!desktop) return { dispose: () => {}, presentPopup: async () => null };
  let frame = 0, pending = false, disposed = false, last = '';
  let inFlight: Promise<void> | null = null;
  const shell = document.querySelector<HTMLElement>('.app-shell');
  const measure = (): { presentation: string; contentHeight: number } => {
    const management = document.body.dataset.view !== 'translate';
    const main = document.querySelector('main');
    const view = document.querySelector<HTMLElement>('.view:not([hidden])');
    const header = document.querySelector<HTMLElement>(management ? '.management-header' : '.popup-toolbar');
    const padding = main ? getComputedStyle(main) : null;
    const natural = (header?.getBoundingClientRect().height ?? 0) + (view?.getBoundingClientRect().height ?? 0)
      + (parseFloat(padding?.paddingTop ?? '0') || 0) + (parseFloat(padding?.paddingBottom ?? '0') || 0);
    const minimum = shell ? parseFloat(getComputedStyle(shell).minHeight) || 0 : 0;
    return { presentation: management ? 'management' : 'popup', contentHeight: Math.min(100_000, Math.ceil(Math.max(natural, minimum) + 2)) };
  };
  const drain = (): Promise<void> => {
    if (inFlight) return inFlight;
    if (disposed) return Promise.resolve();
    inFlight = (async () => {
      while (pending && !disposed) {
        pending = false;
        const payload = measure(), key = JSON.stringify(payload);
        if (key === last) continue;
        try { await invoke('fit_window', payload); last = key; }
        catch { /* Keep translation usable if OS window sizing is unavailable. */ }
      }
    })().finally(() => { inFlight = null; });
    return inFlight;
  };
  const schedule = (): void => {
    if (disposed || frame) return;
    frame = requestAnimationFrame(() => { frame = 0; pending = true; void drain(); });
  };
  const observer = new ResizeObserver(schedule);
  if (shell) observer.observe(shell);
  document.querySelectorAll('.view').forEach((view) => observer.observe(view));
  window.addEventListener('echolingo:layout', schedule);
  const drag = (event: PointerEvent): void => {
    if (event.button !== 0 || !(event.target instanceof Element)) return;
    if (!event.target.closest('[data-window-drag]') || event.target.closest('button, a, input, textarea, select, [role="menu"]')) return;
    event.preventDefault();
    void invoke('start_window_drag').catch(() => {});
  };
  // A custom command avoids granting unrelated window-control capabilities.
  document.addEventListener('pointerdown', drag);
  schedule();
  const dispose = (): void => {
    disposed = true; observer.disconnect(); cancelAnimationFrame(frame);
    window.removeEventListener('echolingo:layout', schedule);
    document.removeEventListener('pointerdown', drag);
  };
  const presentPopup = async (presentationEpoch: number): Promise<TranslationPresentation | null> => {
    cancelAnimationFrame(frame); frame = 0; pending = true;
    await drain();
    // The source event has switched the DOM and fitted its content before the
    // native window is shown, so a previous settings page cannot flash first.
    if (!disposed && document.body.dataset.view === 'translate') return invoke<TranslationPresentation>('show_popup', { presentationEpoch });
    return null;
  };
  return { dispose, presentPopup };
}
