import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

export interface TranslationPresentation { epoch: number; presented: boolean }

// Read intrinsic content rather than viewport height, so a short translation
// can shrink again after a long result. Requests are coalesced and serialized.
export function installPanelLayout(desktop: boolean, getPresentation: () => TranslationPresentation): { dispose: () => void; presentPopup: (presentationEpoch: number, focusInput?: boolean, reuseVisiblePopup?: boolean) => Promise<TranslationPresentation | null>; presentManagement: (presentationEpoch: number) => Promise<TranslationPresentation | null> } {
  if (!desktop) return { dispose: () => {}, presentPopup: async () => null, presentManagement: async () => null };
  let frame = 0, pending = false, disposed = false, last = '';
  let inFlight: Promise<void> | null = null;
  let nativeSizingRevision: number | null = null, completedSizingRevision = 0;
  let unlistenSizing: UnlistenFn | null = null;
  const nativeSizingSupported = /Win/.test(navigator.platform);
  const shell = document.querySelector<HTMLElement>('.app-shell');
  const boundedSize = (value: number): number => Math.min(100_000, Math.max(1, Math.ceil(Number.isFinite(value) ? value : 1)));
  const measure = (): { presentation: string; contentHeight: number; contentWidth: number } => {
    const management = document.body.dataset.view !== 'translate';
    const main = document.querySelector('main');
    const view = document.querySelector<HTMLElement>('.view:not([hidden])');
    const header = document.querySelector<HTMLElement>(management ? '.management-header' : '.popup-toolbar');
    const padding = main ? getComputedStyle(main) : null;
    const natural = (header?.getBoundingClientRect().height ?? 0) + (view?.getBoundingClientRect().height ?? 0)
      + (parseFloat(padding?.paddingTop ?? '0') || 0) + (parseFloat(padding?.paddingBottom ?? '0') || 0);
    const minimum = shell ? parseFloat(getComputedStyle(shell).minHeight) || 0 : 0;
    return { presentation: management ? 'management' : 'popup', contentHeight: boundedSize(Math.max(natural, minimum) + 2), contentWidth: boundedSize(window.innerWidth) };
  };
  const drain = (): Promise<void> => {
    if (inFlight) return inFlight;
    if (disposed) return Promise.resolve();
    inFlight = (async () => {
      while (pending && !disposed) {
        if (nativeSizingRevision !== null) break;
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
    pending = true;
    if (nativeSizingRevision !== null) return;
    if (disposed || frame) return;
    frame = requestAnimationFrame(() => { frame = 0; pending = true; void drain(); });
  };
  if (nativeSizingSupported) void listen<unknown>('popup-native-sizing', ({ payload: value }) => {
    if (disposed || !value || typeof value !== 'object') return;
    const payload = value as { revision: number; active: boolean; presentationEpoch: number };
    if (typeof payload.revision !== 'number' || !Number.isSafeInteger(payload.revision) || payload.revision <= 0
      || typeof payload.active !== 'boolean' || typeof payload.presentationEpoch !== 'number'
      || !Number.isSafeInteger(payload.presentationEpoch) || payload.presentationEpoch < 0) return;
    if (payload.active) {
      if (payload.revision <= completedSizingRevision || (nativeSizingRevision !== null && payload.revision < nativeSizingRevision)) return;
      nativeSizingRevision = payload.revision;
      cancelAnimationFrame(frame); frame = 0; pending = true;
    } else {
      if (payload.revision <= completedSizingRevision || (nativeSizingRevision !== null && payload.revision < nativeSizingRevision)) return;
      completedSizingRevision = payload.revision; nativeSizingRevision = null;
      // Read the current DOM again. Never reuse a former gesture's dimensions
      // or presentation; fitting cannot show or focus a newer popup.
      last = ''; schedule();
    }
  }).then((unlisten) => { if (disposed) unlisten(); else unlistenSizing = unlisten; }).catch(() => {});
  const observer = new ResizeObserver(schedule);
  if (shell) observer.observe(shell);
  document.querySelectorAll('.view').forEach((view) => observer.observe(view));
  window.addEventListener('echolingo:layout', schedule);
  window.addEventListener('resize', schedule);
  type ResizeDirection = 'west' | 'east';
  interface WidthRequest { width: number; direction: ResizeDirection; presentationEpoch: number }
  interface ResizeGesture { edge: HTMLElement; pointerId: number; startX: number; startWidth: number; direction: ResizeDirection; presentationEpoch: number }
  let gesture: ResizeGesture | null = null;
  let widthFrame = 0, nextWidth: WidthRequest | null = null;
  let widthInFlight: Promise<void> | null = null;
  let lastWidth = '';
  const currentPopup = (epoch: number): boolean => {
    const presentation = getPresentation();
    return !disposed && document.body.dataset.view === 'translate' && !document.body.classList.contains('modal-open')
      && !document.hidden && presentation.presented && presentation.epoch === epoch;
  };
  const drainWidth = (): Promise<void> => {
    if (widthInFlight) return widthInFlight;
    widthInFlight = (async () => {
      while (nextWidth && !disposed) {
        const payload = nextWidth; nextWidth = null;
        if (!currentPopup(payload.presentationEpoch)) continue;
        const key = JSON.stringify(payload);
        if (key === lastWidth) continue;
        try { await invoke('resize_popup_width', { ...payload }); lastWidth = key; }
        catch { /* A hidden/superseded popup must not be resized or reopened. */ }
      }
    })().finally(() => { widthInFlight = null; });
    return widthInFlight;
  };
  const clearGesture = (discardPending = true): void => {
    const previous = gesture; gesture = null;
    document.body.classList.remove('popup-resizing');
    if (discardPending) { nextWidth = null; cancelAnimationFrame(widthFrame); widthFrame = 0; }
    if (previous?.edge.hasPointerCapture(previous.pointerId)) previous.edge.releasePointerCapture(previous.pointerId);
  };
  const queueWidth = (event: PointerEvent): void => {
    if (!gesture || event.pointerId !== gesture.pointerId) return;
    if (!currentPopup(gesture.presentationEpoch)) { clearGesture(); return; }
    const delta = (event.screenX - gesture.startX) * (gesture.direction === 'east' ? 1 : -1);
    nextWidth = { width: boundedSize(gesture.startWidth + delta), direction: gesture.direction, presentationEpoch: gesture.presentationEpoch };
    if (!widthFrame) widthFrame = requestAnimationFrame(() => { widthFrame = 0; void drainWidth(); });
  };
  const endWidth = (event: PointerEvent): void => {
    if (!gesture || event.pointerId !== gesture.pointerId) return;
    queueWidth(event); clearGesture(false);
    cancelAnimationFrame(widthFrame); widthFrame = 0;
    void drainWidth();
  };
  const cancelWidth = (event?: Event): void => {
    if (event instanceof PointerEvent && (!gesture || event.pointerId !== gesture.pointerId)) return;
    clearGesture();
  };
  const checkWidthPresentation = (): void => { if (gesture && !currentPopup(gesture.presentationEpoch)) clearGesture(); };
  const widthViewObserver = new MutationObserver(checkWidthPresentation);
  widthViewObserver.observe(document.body, { attributes: true, attributeFilter: ['data-view', 'class'] });
  document.body.classList.add('popup-resize-enabled');
  const drag = (event: PointerEvent): void => {
    if (event.button !== 0 || !(event.target instanceof Element)) return;
    const edge = event.target.closest<HTMLElement>('[data-window-resize]');
    if (edge) {
      const direction = edge.dataset.windowResize;
      const presentation = getPresentation();
      if ((direction !== 'west' && direction !== 'east') || !currentPopup(presentation.epoch) || getComputedStyle(edge).display === 'none') return;
      event.preventDefault();
      if (/Mac/.test(navigator.platform)) {
        clearGesture();
        // screenX stays stable when dragging the west edge moves the window;
        // clientX would feed that movement back into the next width request.
        try { edge.setPointerCapture(event.pointerId); } catch { return; }
        gesture = { edge, pointerId: event.pointerId, startX: event.screenX, startWidth: boundedSize(window.innerWidth), direction, presentationEpoch: presentation.epoch };
        lastWidth = '';
        document.body.classList.add('popup-resizing');
      } else {
        void invoke('start_window_resize', { direction, presentationEpoch: presentation.epoch }).catch(() => {});
      }
      return;
    }
    if (!event.target.closest('[data-window-drag]') || event.target.closest('button, a, input, textarea, select, [role="menu"]')) return;
    event.preventDefault();
    void invoke('start_window_drag').catch(() => {});
  };
  // A custom command avoids granting unrelated window-control capabilities.
  document.addEventListener('pointerdown', drag);
  document.addEventListener('pointermove', queueWidth);
  document.addEventListener('pointerup', endWidth);
  document.addEventListener('pointercancel', cancelWidth);
  document.addEventListener('lostpointercapture', cancelWidth);
  document.addEventListener('visibilitychange', checkWidthPresentation);
  window.addEventListener('blur', cancelWidth);
  window.addEventListener('echolingo:layout', checkWidthPresentation);
  schedule();
  const dispose = (): void => {
    disposed = true; clearGesture(); widthViewObserver.disconnect(); observer.disconnect(); cancelAnimationFrame(frame);
    unlistenSizing?.(); unlistenSizing = null;
    document.body.classList.remove('popup-resize-enabled');
    window.removeEventListener('echolingo:layout', schedule);
    window.removeEventListener('resize', schedule);
    window.removeEventListener('blur', cancelWidth);
    window.removeEventListener('echolingo:layout', checkWidthPresentation);
    document.removeEventListener('pointerdown', drag);
    document.removeEventListener('pointermove', queueWidth);
    document.removeEventListener('pointerup', endWidth);
    document.removeEventListener('pointercancel', cancelWidth);
    document.removeEventListener('lostpointercapture', cancelWidth);
    document.removeEventListener('visibilitychange', checkWidthPresentation);
  };
  const preparePresentation = async (): Promise<boolean> => {
    do {
      if (nativeSizingSupported) {
        let completed: number;
        try { completed = await invoke<number>('wait_for_window_sizing'); } catch { return false; }
        if (disposed || !Number.isSafeInteger(completed) || completed < 0) return false;
        completedSizingRevision = Math.max(completedSizingRevision, completed);
        // Events only reduce live-layout traffic. This native acknowledgement
        // is authoritative even if the corresponding end event was not delivered.
        if (nativeSizingRevision !== null && nativeSizingRevision <= completed) { nativeSizingRevision = null; last = ''; }
        if (nativeSizingRevision !== null) continue;
      }
      cancelAnimationFrame(frame); frame = 0; pending = true;
      await drain();
    } while (nativeSizingRevision !== null && !disposed);
    return !disposed;
  };
  const presentPopup = async (presentationEpoch: number, focusInput = false, reuseVisiblePopup = false): Promise<TranslationPresentation | null> => {
    if (!await preparePresentation()) return null;
    // The source event has switched the DOM and fitted its content before the
    // native window is shown, so a previous settings page cannot flash first.
    if (!disposed && document.body.dataset.view === 'translate' && presentationEpoch >= getPresentation().epoch) return invoke<TranslationPresentation>('show_popup', { presentationEpoch, focusInput, reuseVisiblePopup });
    return null;
  };
  const presentManagement = async (presentationEpoch: number): Promise<TranslationPresentation | null> => {
    if (!await preparePresentation()) return null;
    // A tray/Dock/menu Settings action is explicit: prepare management first,
    // then allow the native command to activate only this requested view.
    if (!disposed && document.body.dataset.view === 'settings' && presentationEpoch >= getPresentation().epoch) return invoke<TranslationPresentation>('show_management', { presentationEpoch });
    return null;
  };
  return { dispose, presentPopup, presentManagement };
}
