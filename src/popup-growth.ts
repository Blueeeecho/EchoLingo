// Keep streamed growth immediate, but ignore tiny shrinks so a one-line
// reflow does not resize the native window back and forth.
export function nextPopupContentHeight(measured: number, committed: number): number {
  const next = Math.ceil(Number.isFinite(measured) ? Math.max(1, measured) : 1);
  if (!Number.isFinite(committed) || committed <= 0) return next;
  if (next >= committed) return next;
  return committed - next >= 24 ? next : committed;
}
