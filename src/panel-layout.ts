import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { nextPopupContentHeight } from './popup-growth';
import { PopupDragController } from './popup-drag';
import { installPopupFocusRing } from './popup-focus';

export interface TranslationPresentation { epoch: number; presented: boolean }

// Read intrinsic content rather than viewport height, so a short translation
// can shrink again after a long result. Requests are coalesced and serialized.
export function installPanelLayout(desktop: boolean, getPresentation: () => TranslationPresentation): { dispose: () => void; presentPopup: (presentationEpoch: number, focusInput?: boolean, reuseVisiblePopup?: boolean) => Promise<TranslationPresentation | null>; presentManagement: (presentationEpoch: number) => Promise<TranslationPresentation | null> } {
  if (!desktop) return { dispose: () => {}, presentPopup: async () => null, presentManagement: async () => null };
  const disposeFocusRing = installPopupFocusRing();
  let frame = 0, pending = false, disposed = false, last = '';
  let invalidation = 0;
  let unlistenUserResize: UnlistenFn | null = null;
  let committedPopupHeight = 0;
  let fittedPopupEpoch: number | null = null;
  let inFlight: Promise<void> | null = null;
  let nativeSizingRevision: number | null = null, completedSizingRevision = 0;
  let unlistenSizing: UnlistenFn | null = null;
  const nativeSizingSupported = /Win/.test(navigator.platform);
  const shell = document.querySelector<HTMLElement>('.app-shell');
  const boundedSize = (value: number): number => Math.min(100_000, Math.max(1, Math.ceil(Number.isFinite(value) ? value : 1)));
  const measure = (): { presentation: string; contentHeight: number; contentWidth: number } => {
    syncModalResizeInset();
    const management = document.body.dataset.view !== 'translate';
    const main = document.querySelector('main');
    const view = document.querySelector<HTMLElement>('.view:not([hidden])');
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
        const payload = measure(), key = JSON.stringify(payload);
        if (key === last) continue;
        const measuredRevision = invalidation;
        try { await invoke('fit_window', payload); if (measuredRevision === invalidation) last = key; }
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
  if (/Mac/.test(navigator.platform)) void listen<unknown>('popup-user-resize-ended', ({ payload }) => {
    if (disposed || payload !== getPresentation().epoch) return;
    invalidation++; last = ''; schedule();
  }).then((unlisten) => { if (disposed) unlisten(); else unlistenUserResize = unlisten; }).catch(() => {});
  const observer = new ResizeObserver(schedule);
  if (shell) observer.observe(shell);
  document.querySelectorAll('.view').forEach((view) => observer.observe(view));
  window.addEventListener('echolingo:layout', schedule);
  window.addEventListener('resize', schedule);
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
    if (!currentResizePresentation(gesture.presentationEpoch, gesture.management, gesture.modalOpen) || (!final && !(event.buttons & 1))) { clearGesture(); return; }
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
    clearGesture();
  };
  function syncModalResizeInset(): void {
    const modal = document.querySelector<HTMLElement>('.modal-overlay:not([hidden])');
    const inset = document.body.dataset.view !== 'translate' && document.body.classList.contains('modal-open') && modal
      ? Math.max(0, modal.offsetWidth - modal.clientWidth) : 0;
    // A classic Windows scrollbar occupies real client pixels. Place the
    // narrow east hit strip beside it, never over its thumb or track.
    document.body.style.setProperty('--resize-scrollbar-inset', `${inset}px`);
  }
  const checkWidthPresentation = (): void => {
    if (gesture && !currentResizePresentation(gesture.presentationEpoch, gesture.management, gesture.modalOpen)) clearGesture();
    syncModalResizeInset();
  };
  let dragCapture: { target: HTMLElement; pointerId: number } | null = null;
  let suppressDragClickUntil = 0;
  const clearDragCapture = (): void => {
    const previous = dragCapture; dragCapture = null;
    if (previous?.target.hasPointerCapture(previous.pointerId)) previous.target.releasePointerCapture(previous.pointerId);
  };
  const popupDrag = new PopupDragController({
    valid: epoch => currentResizePresentation(epoch, false, false),
    begin: press => invoke<number>('begin_popup_drag', { presentationEpoch: press.epoch, anchorX: press.anchorX, anchorY: press.anchorY }),
    move: dragId => invoke('move_popup_drag', { dragId }),
    end: dragId => invoke('end_popup_drag', { dragId }),
    active: value => document.body.classList.toggle('popup-dragging', value),
    settled: () => { last = ''; schedule(); },
  });
  const cancelPopupDrag = (event?: Event): void => {
    if (event instanceof PointerEvent && (!dragCapture || event.pointerId !== dragCapture.pointerId)) return;
    popupDrag.cancel(); clearDragCapture();
  };
  const lostPopupCapture = (event: PointerEvent): void => {
    // A moved WKWebView may lose DOM capture while the same physical press is
    // still active. Only an established native token can keep tracking safely.
    if (!popupDrag.retainsNativeGesture(event.pointerId)) cancelPopupDrag(event);
  };
  const movePopupDrag = (event: PointerEvent): void => popupDrag.move(event.pointerId, event.screenX, event.screenY, event.buttons);
  const endPopupDrag = (event: PointerEvent): void => {
    if (!dragCapture || event.pointerId !== dragCapture.pointerId) return;
    if (popupDrag.release(event.pointerId)) suppressDragClickUntil = performance.now() + 400;
    clearDragCapture();
  };
  const suppressDragClick = (event: MouseEvent): void => {
    if (performance.now() < suppressDragClickUntil) {
      suppressDragClickUntil = 0; event.preventDefault(); event.stopImmediatePropagation();
    }
  };
  const checkDragPresentation = (): void => { if (!popupDrag.check()) clearDragCapture(); };
  const widthViewObserver = new MutationObserver(() => { checkWidthPresentation(); checkDragPresentation(); });
  widthViewObserver.observe(document.body, { attributes: true, attributeFilter: ['data-view', 'class'] });
  document.body.classList.add('popup-resize-enabled');
  const drag = (event: PointerEvent): void => {
    // Any new press, including a button/input or secondary click, retires an old drag.
    if (/Mac/.test(navigator.platform)) cancelPopupDrag();
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
    // Starting any new press clears a drag's click suppression. A click on a
    // button/text input is never a native drag, including nested SVG children.
    suppressDragClickUntil = 0;
    const dragTarget = event.target.closest<HTMLElement>('[data-window-drag]');
    if (!dragTarget || event.target.closest('button, a, input, textarea, select, [role="menu"], [contenteditable="true"]')) return;
    event.preventDefault();
    if (/Mac/.test(navigator.platform)) {
      const presentation = getPresentation();
      if (!currentResizePresentation(presentation.epoch, false, false)) return;
      cancelPopupDrag();
      try { dragTarget.setPointerCapture(event.pointerId); } catch { return; }
      dragCapture = { target: dragTarget, pointerId: event.pointerId };
      popupDrag.press({ pointerId: event.pointerId, screenX: event.screenX, screenY: event.screenY,
        anchorX: event.clientX, anchorY: event.clientY, epoch: presentation.epoch });
    } else void invoke('start_window_drag').catch(() => {});
  };
  // Custom commands avoid granting unrelated general window-control powers.
  document.addEventListener('pointerdown', drag);
  document.addEventListener('pointermove', moveWidth);
  document.addEventListener('pointermove', movePopupDrag);
  document.addEventListener('pointerup', endPopupDrag);
  document.addEventListener('pointercancel', cancelPopupDrag);
  document.addEventListener('lostpointercapture', lostPopupCapture);
  document.addEventListener('click', suppressDragClick, true);
  document.addEventListener('visibilitychange', checkDragPresentation);
  window.addEventListener('blur', cancelPopupDrag);
  window.addEventListener('echolingo:layout', checkDragPresentation);
  document.addEventListener('pointerup', endWidth);
  document.addEventListener('pointercancel', cancelWidth);
  document.addEventListener('lostpointercapture', cancelWidth);
  document.addEventListener('visibilitychange', checkWidthPresentation);
  window.addEventListener('blur', cancelWidth);
  window.addEventListener('echolingo:layout', checkWidthPresentation);
  schedule();
  const dispose = (): void => {
    disposeFocusRing();
    disposed = true; cancelPopupDrag(); clearGesture(); widthViewObserver.disconnect(); observer.disconnect(); cancelAnimationFrame(frame);
    unlistenSizing?.(); unlistenSizing = null;
    unlistenUserResize?.(); unlistenUserResize = null;
    document.body.classList.remove('popup-resize-enabled');
    window.removeEventListener('echolingo:layout', schedule);
    window.removeEventListener('resize', schedule);
    window.removeEventListener('blur', cancelWidth);
    window.removeEventListener('echolingo:layout', checkWidthPresentation);
    document.removeEventListener('pointerdown', drag);
    document.removeEventListener('pointermove', moveWidth);
    document.removeEventListener('pointermove', movePopupDrag);
    document.removeEventListener('pointerup', endPopupDrag);
    document.removeEventListener('pointercancel', cancelPopupDrag);
    document.removeEventListener('lostpointercapture', lostPopupCapture);
    document.removeEventListener('click', suppressDragClick, true);
    document.removeEventListener('visibilitychange', checkDragPresentation);
    window.removeEventListener('blur', cancelPopupDrag);
    window.removeEventListener('echolingo:layout', checkDragPresentation);
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
    if (fittedPopupEpoch !== presentationEpoch) {
      // Native manual height belongs only to its presentation. Equal content
      // dimensions in a new translation must still restore automatic fitting.
      fittedPopupEpoch = presentationEpoch; invalidation++; last = ''; committedPopupHeight = 0;
    }
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
