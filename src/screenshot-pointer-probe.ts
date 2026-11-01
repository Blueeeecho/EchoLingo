/// <reference types="vite/client" />
// Diagnostic build only. No event mutation, content, pixels, coordinates, key
// values or arbitrary element strings are observed. Production removes this.
export type ProbeStage = 'ready' | 'canvas-down' | 'begin-attempt' | 'begin' | 'move-attempt' | 'move' | 'up-attempt' | 'update' | 'updated' | 'update-error' | 'cancel';
export interface ProbeState { canAdjust: boolean; busy: boolean; loading: boolean; selection: boolean; model: boolean; drag: boolean; primary: boolean; button: number; owner: boolean; pending: boolean; gesture: boolean; moving: boolean; text: boolean; tool: string }
export function createScreenshotPointerProbe(state: (event?: PointerEvent) => ProbeState): (stage: ProbeStage, event?: PointerEvent) => void {
  const node = document.createElement('div'); node.id = 'screenshot-pointer-probe'; node.setAttribute('role', 'status'); node.setAttribute('aria-live', 'off');
  node.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;overflow:hidden;opacity:.01;pointer-events:none;z-index:2147483647';
  document.body.append(node);
  const stages = ['ready','doc-down','doc-move','doc-up','doc-cancel','doc-got','doc-lost','canvas-down','begin-attempt','begin','move-attempt','move','up-attempt','update','updated','update-error','cancel'] as const;
  const counts = stages.map(() => 0);
  let target = 'none', downTarget = 'none', downPrimary = false, downButton = -1;
  const classify = (value: EventTarget | null) => {
    if (!(value instanceof Element)) return 'none';
    if (value.id === 'image-canvas') return 'canvas';
    if (value.id === 'canvas-frame') return 'frame';
    if (value.closest('#selection-handles')) return 'handle';
    if (value.closest('.editor-toolbar')) return 'toolbar';
    return 'other';
  };
  const emit = (stage: string, event?: PointerEvent) => {
    const index = stages.indexOf(stage as typeof stages[number]);
    if (index < 0) return;
    counts[index] = Math.min(255, counts[index] + 1);
    if (event) target = classify(event.target);
    if (stage === 'doc-down' && event) { downTarget = target; downPrimary = event.isPrimary; downButton = event.button; }
    node.setAttribute('aria-label', 'EL_SCREENSHOT_POINTER_PROBE_V1:' + JSON.stringify({ counts, stage, target, downTarget, downPrimary, downButton, state: state(event) }));
  };
  for (const [type, stage] of [['pointerdown','doc-down'],['pointermove','doc-move'],['pointerup','doc-up'],['pointercancel','doc-cancel'],['gotpointercapture','doc-got'],['lostpointercapture','doc-lost']] as const) {
    document.addEventListener(type, event => emit(stage, event), { capture: true, passive: true });
  }
  emit('ready'); return emit;
}
