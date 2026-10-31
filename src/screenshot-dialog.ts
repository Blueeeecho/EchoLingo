/** Native <dialog> when available; bounded, focus-trapped fallback for older
 * system WebViews (the app supports macOS versions predating dialog support). */
const stack: HTMLDialogElement[] = [];
const previousFocus = new WeakMap<HTMLDialogElement, HTMLElement>();
let backdrop: HTMLElement | null = null;
const controls = (dialog: HTMLElement) => [...dialog.querySelectorAll<HTMLElement>('button:not(:disabled), textarea:not(:disabled), input:not(:disabled), [tabindex="0"]')].filter(element => element.getClientRects().length > 0);
const top = () => stack[stack.length - 1];
export const dialogOpen = (dialog: HTMLDialogElement) => dialog.hasAttribute('open');
function refresh(): void {
  if (backdrop) backdrop.hidden = stack.length === 0;
  stack.forEach((dialog, index) => { dialog.style.zIndex = String(101 + index); });
}
export function showDialog(dialog: HTMLDialogElement): void {
  if (dialogOpen(dialog)) return;
  if (typeof dialog.showModal === 'function') { dialog.showModal(); return; }
  if (!backdrop) {
    backdrop = document.createElement('div'); backdrop.className = 'screenshot-modal-backdrop'; backdrop.setAttribute('aria-hidden', 'true'); document.body.append(backdrop);
  }
  if (document.activeElement instanceof HTMLElement) previousFocus.set(dialog, document.activeElement);
  dialog.dataset.dialogFallback = 'true'; dialog.setAttribute('role', 'dialog'); dialog.setAttribute('aria-modal', 'true');
  dialog.setAttribute('open', ''); stack.push(dialog); refresh(); controls(dialog)[0]?.focus();
}
export function closeDialog(dialog: HTMLDialogElement): void {
  if (typeof dialog.close === 'function' && dialog.dataset.dialogFallback !== 'true') { dialog.close(); return; }
  if (!dialogOpen(dialog)) return;
  dialog.removeAttribute('open'); const index = stack.indexOf(dialog); if (index >= 0) stack.splice(index, 1); refresh();
  const previous = previousFocus.get(dialog); previousFocus.delete(dialog);
  if (previous?.getClientRects().length) previous.focus({ preventScroll: true }); else if (top()) controls(top())[0]?.focus();
}
document.addEventListener('keydown', event => {
  const dialog = top(); if (!dialog) return;
  if (event.key === 'Escape' && !event.defaultPrevented && !event.isComposing && event.keyCode !== 229) {
    event.preventDefault(); event.stopImmediatePropagation(); dialog.dispatchEvent(new Event('cancel', { cancelable: true }));
  } else if (event.key === 'Tab') {
    const items = controls(dialog); if (!items.length) { event.preventDefault(); return; }
    const index = items.indexOf(document.activeElement as HTMLElement);
    if (index < 0 || (event.shiftKey && index === 0) || (!event.shiftKey && index === items.length - 1)) {
      event.preventDefault(); items[event.shiftKey ? items.length - 1 : 0].focus();
    }
  }
});
document.addEventListener('focusin', event => {
  const dialog = top(); if (dialog && event.target instanceof Node && !dialog.contains(event.target)) controls(dialog)[0]?.focus();
});
