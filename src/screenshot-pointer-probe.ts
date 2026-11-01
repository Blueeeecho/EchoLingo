/// <reference types="vite/client" />
// Isolated synthetic-fixture build only; production dead-code eliminates this.
export type ProbeStage = 'ready' | 'canvas-down' | 'begin-attempt' | 'begin' | 'move-attempt' | 'move' | 'up-attempt' | 'update' | 'updated' | 'update-error' | 'cancel' | 'terminal' | 'unchanged' | 'blocked-up' | 'update-result' | 'late-result';
export interface ProbeState { canAdjust: boolean; busy: boolean; loading: boolean; selection: boolean; model: boolean; drag: boolean; primary: boolean; button: number; owner: boolean; pending: boolean; gesture: boolean; moving: boolean; text: boolean; tool: string }
export interface ProbeGeometry { viewport: number[]; frame: number[]; overlay: number[] | null; original: number[] | null; start: number[] | null; revision: number | null; sessionId: number | null; pointer: number[] | null; captured: boolean }
export interface ProbeResult { code?: string; resultRevision?: number; resultId?: number; resultRect?: number[] }
export function createScreenshotPointerProbe(state: (event?: PointerEvent) => ProbeState, geometry: (event?: PointerEvent) => ProbeGeometry): (stage: ProbeStage, event?: PointerEvent, result?: ProbeResult) => void {
  const node = document.createElement('div'); node.id = 'screenshot-pointer-probe'; node.setAttribute('role', 'status'); node.setAttribute('aria-live', 'off');
  node.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;overflow:hidden;opacity:.01;pointer-events:none;z-index:2147483647'; document.body.append(node);
  const stages = ['ready','doc-down','doc-move','doc-up','doc-cancel','doc-got','doc-lost','canvas-down','begin-attempt','begin','move-attempt','move','up-attempt','update','updated','update-error','cancel','terminal','unchanged','blocked-up','update-result','late-result'] as const;
  const counts = stages.map(() => 0), samples: Record<string, unknown> = {};
  let target = 'none', downTarget = 'none', downPrimary = false, downButton = -1;
  const exceptions = { error: 0, rejection: 0, category: 'none' };
  const classify = (value: EventTarget | null) => {
    if (!(value instanceof Element)) return 'none';
    if (value.id === 'image-canvas') return 'canvas'; if (value.id === 'canvas-frame') return 'frame';
    if (value.closest('#selection-handles')) return 'handle'; if (value.closest('.editor-toolbar')) return 'toolbar'; return 'other';
  };
  const number = (value: number) => Number.isFinite(value) && Math.abs(value) <= Number.MAX_SAFE_INTEGER ? value : null;
  const numbers = (values: number[] | null) => values?.map(number) ?? null;
  const snapshot = (event?: PointerEvent, result?: ProbeResult) => {
    const g = geometry(event);
    return { state: state(event), geometry: { viewport: numbers(g.viewport), frame: numbers(g.frame), overlay: numbers(g.overlay), original: numbers(g.original), start: numbers(g.start), revision: g.revision === null ? null : number(g.revision), sessionId: g.sessionId === null ? null : number(g.sessionId), pointer: numbers(g.pointer), captured: g.captured },
      result: result ? { code: result.code ?? 'none', revision: result.resultRevision === undefined ? null : number(result.resultRevision), id: result.resultId === undefined ? null : number(result.resultId), rect: numbers(result.resultRect ?? null) } : null };
  };
  const slots: Record<string,string> = { 'doc-down':'down','doc-move':'documentMove','doc-up':'documentUp','doc-cancel':'documentCancel','doc-got':'got','doc-lost':'lost','begin':'begin','move':'move','up-attempt':'up','terminal':'terminal','unchanged':'unchanged','update':'update','update-result':'result','updated':'updated','update-error':'failure','cancel':'cancel','blocked-up':'blocked','late-result':'late' };
  let stage = 'ready';
  const publish = (event?: PointerEvent) => {
    const payload = JSON.stringify({ counts, stage, target, downTarget, downPrimary, downButton, state: state(event), samples, exceptions });
    // All fields and slots are fixed, bounded scalars. Fail visibly as a fixed
    // diagnostic category rather than truncate or emit arbitrary payloads.
    node.setAttribute('aria-label', 'EL_SCREENSHOT_POINTER_PROBE_V2:' + (payload.length <= 32000 ? payload : '{"overflow":true}'));
  };
  const emit = (next: string, event?: PointerEvent, result?: ProbeResult) => {
    const index = stages.indexOf(next as typeof stages[number]); if (index < 0) return;
    stage = next; counts[index] = Math.min(255, counts[index] + 1);
    if (event) target = classify(event.target);
    if (stage === 'doc-down' && event) { downTarget = target; downPrimary = event.isPrimary; downButton = event.button; }
    if (slots[stage]) samples[slots[stage]] = snapshot(event, result);
    publish(event);
  };
  const category = (value: unknown) => value instanceof Error && ['Error','TypeError','RangeError','ReferenceError','SyntaxError','NotFoundError','InvalidStateError','SecurityError','AbortError'].includes(value.name) ? value.name : 'other';
  window.addEventListener('error', event => { exceptions.error = Math.min(255, exceptions.error + 1); exceptions.category = category(event.error); publish(); });
  window.addEventListener('unhandledrejection', event => { exceptions.rejection = Math.min(255, exceptions.rejection + 1); exceptions.category = category(event.reason); publish(); });
  for (const [type, next] of [['pointerdown','doc-down'],['pointermove','doc-move'],['pointerup','doc-up'],['pointercancel','doc-cancel'],['gotpointercapture','doc-got'],['lostpointercapture','doc-lost']] as const) document.addEventListener(type, event => emit(next, event), { capture: true, passive: true });
  emit('ready'); return emit;
}
