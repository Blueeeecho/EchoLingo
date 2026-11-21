import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { nextPopupContentHeight } from './popup-growth';
import { popupHeaderRegion } from './popup-drag';
import { installPopupScrollbar } from './popup-scrollbar';
import { installPopupFocusRing } from './popup-focus';
import { layoutViewport, viewportMatches, waitForViewport, type LayoutViewport } from './popup-viewport';

export interface TranslationPresentation { epoch: number; presented: boolean; languageSession?: number }

// Read intrinsic content rather than viewport height, so a short translation
// can shrink again after a long result. Requests are coalesced and serialized.
export function installPanelLayout(desktop: boolean, getPresentation: () => TranslationPresentation, preparePopupContent: () => void = () => {}): { dispose: () => void; presentPopup: (presentationEpoch: number, focusInput?: boolean, reuseVisiblePopup?: boolean) => Promise<TranslationPresentation | null>; presentManagement: (presentationEpoch: number) => Promise<TranslationPresentation | null> } {
  if (!desktop) return { dispose: () => {}, presentPopup: async () => null, presentManagement: async () => null };
  // Local opt-in sends only fixed state names. Never text, geometry or app identity.
  let diagnosticsEnabled = false;
  const diagnosticToggle = (event: Event): void => { diagnosticsEnabled = (event as CustomEvent).detail === true; };
  const trace = (stage: string): void => { if (diagnosticsEnabled) void invoke('record_popup_drag_event', { stage }).catch(() => {}); };
  const diagnosticDown = (event: PointerEvent): void => {
    if (!(event.target instanceof Element)) return;
    if (event.target.closest('.popup-drag-space')) trace('domHeaderDown');
    else if (event.target.closest('#source-text')) trace('domSourceDown');
    else if (event.target.closest('#results')) trace('domResultDown');
  };
  const diagnosticBlur = (): void => trace('domBlur');
  window.addEventListener('echolingo:drag-diagnostics', diagnosticToggle);
  window.addEventListener('blur', diagnosticBlur);
  document.addEventListener('pointerdown', diagnosticDown, true);
  const disposeFocusRing = installPopupFocusRing();
  const disposeScrollbar = installPopupScrollbar();
  let frame = 0, pending = false, disposed = false, last = '';
  let invalidation = 0;
  let unlistenUserResize: UnlistenFn | null = null;
  let committedPopupHeight = 0;
  let fittedPopupEpoch: number | null = null;
  let inFlight: Promise<void> | null = null;
  let nativeViewport: LayoutViewport | null = null;
  let lastFitError: unknown = null;
  let presentationWait: AbortController | null = null;
  let revealRevision = 0;
  const viewportChecks = new Set<() => void>();
  const checkViewport = (): void => { for (const check of [...viewportChecks]) check(); };
  let nativeSizingRevision: number | null = null, completedSizingRevision = 0;
  let unlistenSizing: UnlistenFn | null = null;
  const nativeSizingSupported = /Win/.test(navigator.platform);
  const shell = document.querySelector<HTMLElement>('.app-shell');
  const legacyScrollbar = !CSS.supports('scrollbar-gutter', 'stable both-edges');
  let mirroredScrollbar: number | undefined;
  const boundedSize = (value: number): number => Math.min(100_000, Math.max(1, Math.ceil(Number.isFinite(value) ? value : 1)));
  const measure = (): { presentation: string; contentHeight: number; contentWidth: number } => {
    syncModalResizeInset();
    const management = document.body.dataset.view !== 'translate';
    const main = document.querySelector('main');
    const view = document.querySelector<HTMLElement>('.view:not([hidden])');
    if (!management && view && legacyScrollbar && view.offsetWidth > 0) {
      // clientWidth includes padding but excludes the classic scrollbar.
      const width = Math.max(0, view.offsetWidth - view.clientWidth);
      if (width !== mirroredScrollbar) {
        view.style.setProperty('--popup-classic-scrollbar', `${width}px`);
        mirroredScrollbar = width;
      }
    }
    const header = document.querySelector<HTMLElement>(management ? '.management-header' : '.popup-toolbar');
    const padding = main ? getComputedStyle(main) : null;
    const viewHeight = view ? Math.max(view.getBoundingClientRect().height, view.scrollHeight) : 0;
    const natural = (header?.getBoundingClientRect().height ?? 0) + viewHeight
      + (parseFloat(padding?.paddingTop ?? '0') || 0) + (parseFloat(padding?.paddingBottom ?? '0') || 0);
    const minimum = shell ? parseFloat(getComputedStyle(shell).minHeight) || 0 : 0;
    // Settings/history use the native viewport chosen by the user. Growing
    // form content should scroll, not keep negotiating a different HWND size.
    const raw = Math.max(natural, minimum) + 2;
    const height = management ? window.innerHeight : nextPopupContentHeight(raw, committedPopupHeight);
    if (!management) committedPopupHeight = height;
    return { presentation: management ? 'management' : 'popup', contentHeight: boundedSize(height), contentWidth: boundedSize(window.innerWidth) };
  };
  const drain = (): Promise<void> => {
    if (inFlight) return inFlight;
    if (disposed) return Promise.resolve();
    inFlight = (async () => {
      while (pending && !disposed) {
        if (nativeSizingRevision !== null) break;
        pending = false;
        const payload = measure(), key = JSON.stringify({ ...payload, scaleFactor: window.devicePixelRatio, presentationEpoch: getPresentation().epoch });
        if (key === last) continue;
        const measuredRevision = invalidation;
        try {
          const geometry = await invoke<unknown>('fit_window', payload);
          if (measuredRevision === invalidation) { last = key; lastFitError = null; nativeViewport = layoutViewport(geometry); checkViewport(); }
        }
        catch (error) {
          if (measuredRevision === invalidation) { lastFitError = error; nativeViewport = null; }
          // Background layout failures do not discard the visible translation.
          // Explicit presentation below reports the error instead of claiming
          // an old geometry acknowledgement belongs to the new source.
        }
      }
    })().finally(() => { inFlight = null; });
    return inFlight;
  };
  const schedule = (): void => {
    checkViewport();
    pending = true;
    if (nativeSizingRevision !== null) return;
    if (disposed || frame) return;
    frame = requestAnimationFrame(() => { frame = 0; syncNativeHeaderDrag(); pending = true; void drain(); });
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
  if (/Mac/.test(navigator.platform)) void listen<unknown>('popup-user-resize-ended', ({ payload }) => {
    if (disposed || payload !== getPresentation().epoch) return;
    invalidation++; last = ''; schedule();
  }).then((unlisten) => { if (disposed) unlisten(); else unlistenUserResize = unlisten; }).catch(() => {});
  const observer = new ResizeObserver(schedule);
  if (shell) observer.observe(shell);
  document.querySelectorAll('.view').forEach((view) => observer.observe(view));
  window.addEventListener('echolingo:layout', schedule);
  window.addEventListener('resize', schedule);
  // A same-point-size move between 1x/2x displays need not resize the CSS
  // viewport. Re-arm the resolution query so native constraints/ACK refresh.
  const scaleMedia = (): MediaQueryList => matchMedia(`(resolution: ${window.devicePixelRatio}dppx), (-webkit-device-pixel-ratio: ${window.devicePixelRatio})`);
  let scaleQuery = scaleMedia();
  const changedScale = (): void => {
    scaleQuery.removeEventListener('change', changedScale);
    scaleQuery = scaleMedia();
    scaleQuery.addEventListener('change', changedScale);
    schedule();
  };
  scaleQuery.addEventListener('change', changedScale);
  type ResizeDirection = 'west' | 'east' | 'north' | 'south' | 'north-west' | 'north-east' | 'south-west' | 'south-east';
  interface ResizeRequest { width: number; height: number; direction: ResizeDirection; presentationEpoch: number; management: boolean; modalOpen: boolean }
  interface ResizeGesture extends ResizeRequest { edge: HTMLElement; pointerId: number; startX: number; startY: number }
  let gesture: ResizeGesture | null = null;
  let widthFrame = 0, nextWidth: ResizeRequest | null = null;
  let widthInFlight: Promise<void> | null = null;
  let lastWidth = '';
  const currentResizePresentation = (epoch: number, management: boolean, expectedModalOpen?: boolean): boolean => {
    const presentation = getPresentation(), modalOpen = document.body.classList.contains('modal-open');
    return !disposed && (document.body.dataset.view !== 'translate') === management && (management || !modalOpen)
      && (expectedModalOpen === undefined || modalOpen === expectedModalOpen)
      && !document.hidden && presentation.presented && presentation.epoch === epoch;
  };
  const drainWidth = (): Promise<void> => {
    if (widthInFlight) return widthInFlight;
    widthInFlight = (async () => {
      while (nextWidth && !disposed) {
        const payload = nextWidth; nextWidth = null;
        if (!currentResizePresentation(payload.presentationEpoch, payload.management, payload.modalOpen)) continue;
        const key = JSON.stringify(payload);
        if (key === lastWidth) continue;
        try {
          trace('resizeRequest');
          if (payload.management) await invoke('resize_management_window', { width: payload.width, height: payload.height, direction: payload.direction, presentationEpoch: payload.presentationEpoch });
          else await invoke('resize_popup_width', { width: payload.width, direction: payload.direction, presentationEpoch: payload.presentationEpoch });
          lastWidth = key;
        } catch { /* A hidden/superseded presentation must not resize or reopen. */ }
      }
    })().finally(() => { widthInFlight = null; });
    return widthInFlight;
  };
  const clearGesture = (discardPending = true): void => {
    const previous = gesture; gesture = null;
    document.body.classList.remove('popup-resizing'); delete document.body.dataset.resizeDirection;
    if (discardPending) { nextWidth = null; cancelAnimationFrame(widthFrame); widthFrame = 0; }
    if (previous?.edge.hasPointerCapture(previous.pointerId)) previous.edge.releasePointerCapture(previous.pointerId);
  };
  const queueWidth = (event: PointerEvent, final = false): void => {
    if (!gesture || event.pointerId !== gesture.pointerId) return;
    if (!currentResizePresentation(gesture.presentationEpoch, gesture.management, gesture.modalOpen)) { clearGesture(); return; }
    if (!final && !(event.buttons & 1)) { trace('resizeButtonsZero'); clearGesture(); return; }
    const horizontal = gesture.direction.includes('west') ? -1 : gesture.direction.includes('east') ? 1 : 0;
    const vertical = gesture.direction.includes('north') ? -1 : gesture.direction.includes('south') ? 1 : 0;
    nextWidth = { width: boundedSize(gesture.width + (event.screenX - gesture.startX) * horizontal),
      height: boundedSize(gesture.height + (event.screenY - gesture.startY) * vertical), direction: gesture.direction,
      presentationEpoch: gesture.presentationEpoch, management: gesture.management, modalOpen: gesture.modalOpen };
    if (!widthFrame) widthFrame = requestAnimationFrame(() => { widthFrame = 0; void drainWidth(); });
  };
  const moveWidth = (event: PointerEvent): void => queueWidth(event);
  const endWidth = (event: PointerEvent): void => {
    if (!gesture || event.pointerId !== gesture.pointerId) return;
    queueWidth(event, true); clearGesture(false);
    cancelAnimationFrame(widthFrame); widthFrame = 0;
    void drainWidth();
  };
  const cancelWidth = (event?: Event): void => {
    if (event instanceof PointerEvent && (!gesture || event.pointerId !== gesture.pointerId)) return;
    if (gesture) {
      if (event?.type === 'blur') trace('resizeBlur');
      else if (event?.type === 'pointercancel') trace('resizePointerCancel');
      else if (event?.type === 'lostpointercapture') trace('resizeCaptureLost');
    }
    clearGesture();
  };
  let lastResizeInset: number | undefined;
  function syncModalResizeInset(): void {
    const modal = document.querySelector<HTMLElement>('.modal-overlay:not([hidden])');
    const inset = document.body.dataset.view !== 'translate' && document.body.classList.contains('modal-open') && modal
      ? Math.max(0, modal.offsetWidth - modal.clientWidth) : 0;
    if (inset === lastResizeInset) return;
    lastResizeInset = inset;
    // A classic Windows scrollbar occupies real client pixels. Place the
    // narrow east hit strip beside it, never over its thumb or track.
    document.body.style.setProperty('--resize-scrollbar-inset', `${inset}px`);
  }
  const checkWidthPresentation = (): void => {
    if (gesture && !currentResizePresentation(gesture.presentationEpoch, gesture.management, gesture.modalOpen)) clearGesture();
    syncModalResizeInset();
  };
  let headerRevision = Date.now() * 1000, headerSignature = '';
  let unlistenHeader: UnlistenFn | null = null;
  function syncNativeHeaderDrag(): void {
    if (!/Mac/.test(navigator.platform)) return;
    const region = document.querySelector<HTMLElement>('.popup-drag-space')?.getBoundingClientRect() ?? null;
    const geometry = popupHeaderRegion(region, innerWidth, innerHeight, !disposed
      && document.body.dataset.view === 'translate' && !document.body.classList.contains('modal-open'));
    const payload = { presentationEpoch: getPresentation().epoch, ...geometry };
    const signature = JSON.stringify(payload);
    if (signature === headerSignature) return;
    headerSignature = signature;
    void invoke('configure_popup_header_drag', { revision: ++headerRevision, ...payload }).catch(() => {
      if (headerSignature === signature) headerSignature = '';
    });
  }
  const checkDragPresentation = syncNativeHeaderDrag;
  if (/Mac/.test(navigator.platform)) void listen<number>('popup-native-drag-ended', ({ payload }) => {
    // A late old completion only requests a current measurement. Rust still
    // suppresses fitting while a newer native token is held, even in this epoch.
    if (!disposed && payload === getPresentation().epoch && document.body.dataset.view === 'translate') {
      last = ''; schedule();
    }
  }).then(unlisten => { if (disposed) unlisten(); else unlistenHeader = unlisten; }).catch(() => {});
  const widthViewObserver = new MutationObserver(() => { checkWidthPresentation(); checkDragPresentation(); });
  widthViewObserver.observe(document.body, { attributes: true, attributeFilter: ['data-view', 'class'] });
  document.body.classList.add('popup-resize-enabled');
  const drag = (event: PointerEvent): void => {
    if (event.button !== 0 || !event.isPrimary || !(event.target instanceof Element)) return;
    const edge = event.target.closest<HTMLElement>('[data-window-resize]');
    if (edge) {
      const direction = edge.dataset.windowResize as ResizeDirection;
      const management = document.body.dataset.view !== 'translate';
      const presentation = getPresentation();
      if (!['west', 'east', 'north', 'south', 'north-west', 'north-east', 'south-west', 'south-east'].includes(direction)
        || (!management && direction !== 'west' && direction !== 'east')
        || !currentResizePresentation(presentation.epoch, management) || getComputedStyle(edge).display === 'none') return;
      event.preventDefault();
      if (/Mac/.test(navigator.platform)) {
        clearGesture();
        if (direction === 'west') trace('resizeWestDown');
        if (direction === 'east') trace('resizeEastDown');
        // Global screen coordinates remain stable when north/west edges move
        // the window; client coordinates would feed that movement back in.
        try { edge.setPointerCapture(event.pointerId); } catch { return; }
        gesture = { edge, pointerId: event.pointerId, startX: event.screenX, startY: event.screenY,
          width: boundedSize(window.innerWidth), height: boundedSize(window.innerHeight), direction,
          presentationEpoch: presentation.epoch, management, modalOpen: document.body.classList.contains('modal-open') };
        lastWidth = ''; document.body.dataset.resizeDirection = direction;
        document.body.classList.add('popup-resizing');
      } else {
        const payload = { direction, presentationEpoch: presentation.epoch };
        void invoke('start_window_resize', management ? { ...payload, management: true } : payload).catch(() => {});
      }
      return;
    }
    const dragTarget = event.target.closest<HTMLElement>('[data-window-drag]');
    if (!dragTarget || event.target.closest('button, a, input, textarea, select, [role="menu"], [contenteditable="true"]')) return;
    if (/Mac/.test(navigator.platform)) return; // AppKit consumes only real blank-header down events.
    event.preventDefault();
    void invoke('start_window_drag').catch(() => {});
  };
  // Custom commands avoid granting unrelated general window-control powers.
  document.addEventListener('pointerdown', drag);
  document.addEventListener('pointermove', moveWidth);
  document.addEventListener('visibilitychange', checkDragPresentation);
  document.addEventListener('pointerup', endWidth);
  document.addEventListener('pointercancel', cancelWidth);
  document.addEventListener('lostpointercapture', cancelWidth);
  document.addEventListener('visibilitychange', checkWidthPresentation);
  window.addEventListener('blur', cancelWidth);
  window.addEventListener('echolingo:layout', checkWidthPresentation);
  schedule();
  const dispose = (): void => {
    window.removeEventListener('echolingo:drag-diagnostics', diagnosticToggle);
    window.removeEventListener('blur', diagnosticBlur);
    document.removeEventListener('pointerdown', diagnosticDown, true);
    disposeFocusRing(); disposeScrollbar();
    disposed = true; presentationWait?.abort(); syncNativeHeaderDrag(); unlistenHeader?.(); clearGesture(); widthViewObserver.disconnect(); observer.disconnect(); cancelAnimationFrame(frame);
    unlistenSizing?.(); unlistenSizing = null;
    unlistenUserResize?.(); unlistenUserResize = null;
    document.body.classList.remove('popup-resize-enabled');
    window.removeEventListener('echolingo:layout', schedule);
    window.removeEventListener('resize', schedule);
    scaleQuery.removeEventListener('change', changedScale);
    window.removeEventListener('blur', cancelWidth);
    window.removeEventListener('echolingo:layout', checkWidthPresentation);
    document.removeEventListener('pointerdown', drag);
    document.removeEventListener('pointermove', moveWidth);
    document.removeEventListener('visibilitychange', checkDragPresentation);
    document.removeEventListener('pointerup', endWidth);
    document.removeEventListener('pointercancel', cancelWidth);
    document.removeEventListener('lostpointercapture', cancelWidth);
    document.removeEventListener('visibilitychange', checkWidthPresentation);
  };
  const preparePresentation = async (epoch: number, management: boolean): Promise<boolean> => {
    presentationWait?.abort();
    if (nativeViewport && nativeViewport.presentationEpoch !== epoch) {
      invalidation++; last = ''; nativeViewport = null;
    }
    const waiter = new AbortController(); presentationWait = waiter;
    const current = (): boolean => !disposed && !waiter.signal.aborted && epoch >= getPresentation().epoch
      && (document.body.dataset.view !== 'translate') === management;
    do {
      if (!current()) return false;
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
      // Auto-sized source editors may have queued a resize for the next frame.
      // Flush that content measurement at the adopted width before revealing.
      const preparedWidth = window.innerWidth;
      if (!management) preparePopupContent();
      cancelAnimationFrame(frame); frame = 0; pending = true;
      await drain();
      if (!current()) return false;
      if (lastFitError) throw lastFitError;
      // The WebView may adopt native width before the IPC reply, with its
      // textarea resize callback still queued. A matching viewport alone does
      // not prove content was measured at that width.
      if (preparedWidth !== window.innerWidth) continue;
      if (nativeViewport && nativeViewport.presentationEpoch !== epoch) return false;
      const ready = (): boolean => !nativeViewport || viewportMatches(nativeViewport, {
        width: window.innerWidth, height: window.innerHeight, scaleFactor: window.devicePixelRatio,
      });
      if (!ready()) {
        if (!await waitForViewport({ ready, current, signal: waiter.signal,
          subscribe: check => { viewportChecks.add(check); return () => viewportChecks.delete(check); },
        })) return false;
        // Width adoption changes wrapping; fit that actual DOM before reveal,
        // not the previous management/restored-width layout. No extra frame wait.
        pending = true;
        continue;
      }
      if (nativeSizingRevision === null) return true;
    } while (current());
    return false;
  };
  const presentPopup = async (presentationEpoch: number, focusInput = false, reuseVisiblePopup = false): Promise<TranslationPresentation | null> => {
    const reveal = ++revealRevision;
    if (fittedPopupEpoch !== presentationEpoch) {
      // Native manual height belongs only to its presentation. Equal content
      // dimensions in a new translation must still restore automatic fitting.
      fittedPopupEpoch = presentationEpoch; invalidation++; last = ''; committedPopupHeight = 0;
    }
    if (!await preparePresentation(presentationEpoch, false) || reveal !== revealRevision) return null;
    if (/Mac/.test(navigator.platform)) {
      // Complete hit-region registration before reveal. Native resume may advance
      // the epoch; show_popup adopts this verified region in that same UI turn.
      const region = document.querySelector<HTMLElement>('.popup-drag-space')?.getBoundingClientRect() ?? null;
      const geometry = popupHeaderRegion(region, innerWidth, innerHeight, !disposed
        && document.body.dataset.view === 'translate' && !document.body.classList.contains('modal-open'));
      const payload = { presentationEpoch, ...geometry };
      const signature = JSON.stringify(payload);
      headerSignature = signature;
      try { await invoke('configure_popup_header_drag', { revision: ++headerRevision, ...payload }); }
      catch (error) { if (headerSignature === signature) headerSignature = ''; throw error; }
      if (disposed || reveal !== revealRevision || presentationEpoch < getPresentation().epoch) return null;
    }
    // The source event has switched the DOM and fitted its content before the
    // native window is shown, so a previous settings page cannot flash first.
    if (!disposed && document.body.dataset.view === 'translate' && presentationEpoch >= getPresentation().epoch) return invoke<TranslationPresentation>('show_popup', { presentationEpoch, focusInput, reuseVisiblePopup });
    return null;
  };
  const presentManagement = async (presentationEpoch: number): Promise<TranslationPresentation | null> => {
    const reveal = ++revealRevision;
    if (!await preparePresentation(presentationEpoch, true) || reveal !== revealRevision) return null;
    // A tray/Dock/menu Settings action is explicit: prepare management first,
    // then allow the native command to activate only this requested view.
    if (!disposed && document.body.dataset.view === 'settings' && presentationEpoch >= getPresentation().epoch) return invoke<TranslationPresentation>('show_management', { presentationEpoch });
    return null;
  };
  return { dispose, presentPopup, presentManagement };
}
