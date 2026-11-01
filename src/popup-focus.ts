// WebViews may restore the first header button as :focus-visible when a
// native popup or management window opens. Keep focus and source selection
// untouched; distinguish keyboard interaction from restored/programmatic focus.
export function installPopupFocusRing(): () => void {
  const selector = '.popup-toolbar > .icon-button, .management-header > .icon-button';
  document.body.dataset.popupFocusManaged = 'true';
  const capture = { capture: true };
  let marked: HTMLElement | null = null;
  let keyboardIntent = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const clearRing = (): void => { marked?.removeAttribute('data-keyboard-focus'); marked = null; };
  const mark = (target: EventTarget | null): void => {
    clearRing();
    if (target instanceof HTMLElement && target.matches(selector)) {
      marked = target; marked.setAttribute('data-keyboard-focus', '');
    }
  };
  const reset = (): void => { keyboardIntent = false; clearTimeout(timer); timer = undefined; clearRing(); };
  const keydown = (event: KeyboardEvent): void => {
    if (event.isComposing || event.altKey || event.ctrlKey || event.metaKey
      || !['Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End', 'Escape', 'Enter', ' '].includes(event.key)) return;
    keyboardIntent = true;
    mark(document.activeElement);
    clearTimeout(timer);
    timer = setTimeout(() => { keyboardIntent = false; timer = undefined; }, 0);
  };
  const focusin = (event: FocusEvent): void => {
    if (keyboardIntent) mark(event.target); else clearRing();
    keyboardIntent = false;
  };
  document.addEventListener('keydown', keydown, capture);
  document.addEventListener('focusin', focusin, capture);
  document.addEventListener('focusout', clearRing, capture);
  document.addEventListener('pointerdown', reset, capture);
  window.addEventListener('blur', reset);
  return () => {
    reset();
    delete document.body.dataset.popupFocusManaged;
    document.removeEventListener('keydown', keydown, capture);
    document.removeEventListener('focusin', focusin, capture);
    document.removeEventListener('focusout', clearRing, capture);
    document.removeEventListener('pointerdown', reset, capture);
    window.removeEventListener('blur', reset);
  };
}
