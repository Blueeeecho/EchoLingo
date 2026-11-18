// A narrow, explicit scrollbar occupies the card's inner blank inset, outside
// the 8px window-resize strip. Native overlay/classic scrollbar preferences no
// longer add a second outer gutter or change the text width when results grow.
export function installPopupScrollbar(): () => void {
  const view = document.querySelector<HTMLElement>('#view-translate');
  if (!view || !/Mac/.test(navigator.platform)) return () => {};
  const rail = document.createElement('div'); rail.className = 'popup-scroll-rail';
  rail.tabIndex = 0; rail.setAttribute('role', 'scrollbar'); rail.setAttribute('aria-label', '滚动翻译内容');
  rail.setAttribute('aria-controls', view.id); rail.setAttribute('aria-orientation', 'vertical');
  const thumb = document.createElement('div'); thumb.className = 'popup-scroll-thumb'; rail.append(thumb); document.body.append(rail);
  let pointer: number | null = null, startY = 0, startScroll = 0, travel = 1, maximum = 0;
  const update = () => {
    const box = view.getBoundingClientRect(); maximum = Math.max(0, view.scrollHeight - view.clientHeight);
    rail.hidden = document.body.dataset.view !== 'translate' || document.body.classList.contains('modal-open') || maximum <= 0;
    if (rail.hidden) pointer = null;
    rail.style.top = `${box.top}px`; rail.style.height = `${box.height}px`;
    const height = Math.min(box.height, Math.max(24, box.height * view.clientHeight / Math.max(1, view.scrollHeight)));
    travel = Math.max(1, box.height - height); thumb.style.height = `${height}px`;
    thumb.style.transform = `translateY(${maximum ? view.scrollTop / maximum * travel : 0}px)`;
    rail.setAttribute('aria-valuemin', '0'); rail.setAttribute('aria-valuemax', String(maximum));
    rail.setAttribute('aria-valuenow', String(Math.round(view.scrollTop)));
  };
  const down = (event: PointerEvent) => {
    if (event.button !== 0 || rail.hidden) return;
    event.preventDefault(); event.stopPropagation(); rail.setPointerCapture(event.pointerId);
    if (event.target !== thumb) view.scrollTop = (event.clientY - rail.getBoundingClientRect().top - thumb.offsetHeight / 2) / travel * maximum;
    pointer = event.pointerId; startY = event.clientY; startScroll = view.scrollTop;
  };
  const move = (event: PointerEvent) => { if (pointer === event.pointerId) view.scrollTop = startScroll + (event.clientY - startY) / travel * maximum; };
  const end = () => { pointer = null; };
  const key = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowDown' ? 40 : event.key === 'ArrowUp' ? -40
      : event.key === 'PageDown' ? view.clientHeight : event.key === 'PageUp' ? -view.clientHeight : 0;
    if (step || event.key === 'Home' || event.key === 'End') {
      event.preventDefault(); view.scrollTop = event.key === 'Home' ? 0 : event.key === 'End' ? maximum : view.scrollTop + step;
    }
  };
  rail.addEventListener('pointerdown', down); rail.addEventListener('pointermove', move);
  rail.addEventListener('pointerup', end); rail.addEventListener('pointercancel', end); rail.addEventListener('lostpointercapture', end); rail.addEventListener('keydown', key);
  view.addEventListener('scroll', update); window.addEventListener('resize', update);
  const resize = new ResizeObserver(update); resize.observe(view); if (view.firstElementChild) resize.observe(view.firstElementChild);
  const mutation = new MutationObserver(update); mutation.observe(view, { childList: true, subtree: true, characterData: true });
  mutation.observe(document.body, { attributes: true, attributeFilter: ['data-view', 'class'] });
  update();
  return () => { resize.disconnect(); mutation.disconnect(); view.removeEventListener('scroll', update); window.removeEventListener('resize', update); rail.remove(); };
}
