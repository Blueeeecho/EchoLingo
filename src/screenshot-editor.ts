import './screenshot-editor.css';
import { createScreenshotPointerProbe, type ProbeStage } from './screenshot-pointer-probe';
import { adjustSelection, selectionCancelDisabled, type SelectionHandle } from './screenshot-selection';
import { overlayToolBounds, clampOverlayBox, placeOverlayToolbar, type OverlayRect } from './screenshot-overlay-layout';
import { closeDialog, dialogOpen, showDialog } from './screenshot-dialog';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { ScreenshotDocument, imagePoint, selectionRect, validateSize, MAX_ENCODED_BYTES, operationBounds, screenshotTextFont, translateOperation, type Point, type EditOperation, MAX_STROKE_POINTS, strokePathsIntersect } from './screenshot-model';
import { flattenedPng, renderScreenshot } from './screenshot-renderer';
interface ScreenshotOverlay { x: number; y: number; width: number; height: number; viewportWidth: number; viewportHeight: number; toolbarBounds?: OverlayRect }
interface ScreenshotSession { kind?: 'image'; revision?: number; id: number; pngBase64: string; width: number; height: number; capturedAt: number; sourceName?: string; overlay?: ScreenshotOverlay; initialAction?: InitialAction }
interface SelectionSession { kind: 'selection'; id: number; revision: number; width: number; height: number; overlay: ScreenshotOverlay }
type IncomingSession = ScreenshotSession | SelectionSession;
type Tool = 'select' | 'rectangle' | 'arrow' | 'text' | 'mosaic' | 'solid' | 'crop' | 'number' | 'pen' | 'highlight' | 'eraser';
type InitialAction = Exclude<Tool, 'eraser'> | 'copy' | 'save' | 'pin';
const toolActions: readonly string[] = ['select', 'rectangle', 'arrow', 'text', 'number', 'pen', 'highlight', 'mosaic', 'solid', 'crop'];
const $ = <T extends Element = HTMLElement>(selector: string) => document.querySelector<T>(selector)!;
const canvas = $<HTMLCanvasElement>('#image-canvas'), frame = $('#canvas-frame'), workspace = $('#editor-workspace');
const textDialog = $<HTMLElement>('#text-dialog'), discardDialog = $<HTMLDialogElement>('#discard-dialog');
const textInput = $<HTMLTextAreaElement>('#annotation-text');
const desktop = isTauri(), windows = /Win/i.test(navigator.platform);
let session: Omit<ScreenshotSession, 'pngBase64' | 'kind' | 'capturedAt'> & { kind?: 'image' | 'selection'; capturedAt?: number } | null = null, original: HTMLImageElement | null = null, model: ScreenshotDocument | null = null;
let latestId = -1, generation = 0, savedState: number | null = null, busy = false, nativeDialog = false, loading = false, tool: Tool = 'rectangle';
let rendered: { generation: number; stateId: number } | null = null;
let contextLost = false;
let selectionSession: SelectionSession | null = null;
let selectionDrag: { pointerId: number; start: Point; rect: OverlayRect; handle: SelectionHandle } | null = null;
let selectionUpdating = false;
let capturePending: Promise<boolean> | null = null;
let pendingStroke: { generation: number; down: PointerEvent; tool: Tool; style: string; events: PointerEvent[]; cancelled: boolean; released: boolean } | null = null;
const canAdjustSelection = () => !!session?.overlay && session.revision !== undefined && !!selectionSession && !model?.operations.length && !textOpen() && !pendingStroke;

const inplace = () => !!session?.overlay;
const exportReady = () => !contextLost && !!model && rendered?.generation === generation && rendered.stateId === model.stateId;
let decoding: HTMLImageElement | null = null;
let textFocusPending = false;
let selectedIndex: number | null = null, editingIndex: number | null = null;
let moveGesture: { index: number; start: Point; original: EditOperation; pointerId: number; moved: EditOperation } | null = null;
const textOpen = () => !textDialog.hidden;
let overlayFocus: { generation: number; promise: Promise<void> } | null = null;
let zoom = 1, fit = true, composing = false, imeEscape = false, textPoint: Point | null = null;
let gesture: { start: Point; end: Point; pointerId: number; points?: Point[] } | null = null;
let discardResolve: ((value: boolean) => void) | null = null;
// A non-empty inline draft is unsaved even before it enters operation history.
const dirty = () => model !== null && (savedState !== model.stateId || (textOpen() && !!textInput.value.trim()));
const pointerProbe: (stage: ProbeStage, event?: PointerEvent) => void = import.meta.env.VITE_SCREENSHOT_POINTER_PROBE === '1'
  ? createScreenshotPointerProbe(event => ({ canAdjust: canAdjustSelection(), busy, loading, selection: !!selectionSession, model: !!model,
    drag: !!selectionDrag, pending: !!pendingStroke, gesture: !!gesture, moving: !!moveGesture, text: textOpen(), tool, primary: event?.isPrimary ?? false, button: event?.button ?? -1,
    owner: !!event && event.pointerId === selectionDrag?.pointerId })) : () => {};

function status(message: string, error = false): void { $('#editor-status').textContent = message; $('#editor-status').hidden = !message; $('#editor-status').dataset.error = String(error); placeOverlayTools(); }
function readableError(error: unknown): string { return error instanceof Error ? error.message : String(error); }
function annotationStyleKey(): string { return [...document.querySelectorAll<HTMLInputElement | HTMLSelectElement>('.tool-options input, .tool-options select')].map(input => input.value).join('\u0000'); }
function controls(): void {
  for (const input of document.querySelectorAll<HTMLInputElement | HTMLSelectElement>('.tool-options input, .tool-options select')) input.disabled = busy || loading || !!pendingStroke;
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-image-action]')) button.disabled = (!model && !selectionSession) || busy || loading || !!pendingStroke;
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-export-action]')) button.disabled ||= contextLost || (!(selectionSession && !model) && !exportReady() && !textOpen());
  $<HTMLButtonElement>('#undo-edit').disabled ||= !model?.canUndo;
  $<HTMLButtonElement>('#redo-edit').disabled ||= !model?.canRedo;
  $<HTMLButtonElement>('#open-image').disabled = busy || loading;
  $<HTMLButtonElement>('#close-editor').disabled = nativeDialog;
  $<HTMLButtonElement>('#overlay-cancel').disabled = selectionCancelDisabled(busy, !!capturePending, selectionUpdating, nativeDialog);
  $('#save-indicator').textContent = model ? dirty() ? '未保存' : '已保存' : '';
  $('#image-info').textContent = model ? `${model.size.width} × ${model.size.height} px` : loading ? '正在打开图片…' : '没有打开的图片';
  $('#overlay-info').textContent = model ? `${model.size.width} × ${model.size.height}` : selectionSession ? `${selectionSession.width} × ${selectionSession.height}` : '';
  $('#selection-handles').hidden = !canAdjustSelection() || busy || loading;
  frame.dataset.adjustable = String(canAdjustSelection());
  frame.dataset.liveSelection = String(!!selectionSession && !model);
  document.title = `${dirty() ? '• ' : ''}截图 · EchoLingo`;
}
function applyZoom(): void {
  if (!model) { if (selectionSession) placeSelectionFrame(); return; }
  const { width, height } = model.size;
  if (session?.overlay) {
    const overlay = session.overlay, scaleX = overlay.width / model.original.width, scaleY = overlay.height / model.original.height;
    // Crops retain their screen origin rather than stretching the cropped image.
    const offset = model.operations.reduce((point, operation) => operation.kind === 'crop'
      ? { x: point.x + operation.rect.x, y: point.y + operation.rect.y } : point, { x: 0, y: 0 });
    frame.style.left = `${overlay.x + offset.x * scaleX}px`; frame.style.top = `${overlay.y + offset.y * scaleY}px`;
    frame.style.width = `${width * scaleX}px`; frame.style.height = `${height * scaleY}px`;
    $('#gesture-preview').setAttribute('viewBox', `0 0 ${width} ${height}`);
    placeOverlayTools(); return;
  }
  frame.style.left = ''; frame.style.top = '';
  if (fit) zoom = Math.min(1, Math.max(0.01, Math.min((workspace.clientWidth - 56) / width, (workspace.clientHeight - 180) / height)));
  frame.style.width = `${width * zoom}px`; frame.style.height = `${height * zoom}px`;
  $('#zoom-level').textContent = `${Math.round(zoom * 100)}%`;
  $('#gesture-preview').setAttribute('viewBox', `0 0 ${width} ${height}`);
  placeOverlayTools();
}
let placementFrame = 0;
function placeOverlayTools(): void {
  if (placementFrame) return;
  placementFrame = requestAnimationFrame(() => { placementFrame = 0; layoutOverlayTools(); });
}
function layoutOverlayTools(): void {
  const monitor = overlayToolBounds(innerWidth, innerHeight, session?.overlay?.toolbarBounds);
  const margin = Math.min(8, monitor.width / 8, monitor.height / 8);
  const bounds = { x: monitor.x + margin, y: monitor.y + margin, width: monitor.width - margin * 2, height: monitor.height - margin * 2 };
  const toolbar = $('.editor-toolbar'); toolbar.dataset.compact = String(bounds.width < 620);
  toolbar.style.maxWidth = `${bounds.width}px`; toolbar.style.maxHeight = `${bounds.height}px`;
  // Read after applying monitor width: wrapping/tool option changes affect height.
  const selection = frame.getBoundingClientRect(), tools = toolbar.getBoundingClientRect();
  const position = placeOverlayToolbar({ x: selection.x, y: selection.y, width: selection.width, height: selection.height }, tools.width, tools.height, bounds);
  toolbar.style.left = `${position.x}px`; toolbar.style.top = `${position.y}px`;
  const info = $('#overlay-info'); info.style.maxWidth = `${bounds.width}px`;
  const infoPosition = clampOverlayBox(selection.left, selection.top - info.offsetHeight - 6, info.offsetWidth, info.offsetHeight, bounds);
  info.style.left = `${infoPosition.x}px`; info.style.top = `${infoPosition.y}px`;
  const message = $('#editor-status'); message.style.maxWidth = `${bounds.width}px`; message.style.maxHeight = `${Math.max(20, Math.min(70, bounds.height / 4))}px`;
  const statusY = position.y + tools.height + 6 + message.offsetHeight <= bounds.y + bounds.height
    ? position.y + tools.height + 6 : position.y - message.offsetHeight - 6;
  const statusPosition = clampOverlayBox(position.x, statusY, message.offsetWidth, message.offsetHeight, bounds);
  message.style.left = `${statusPosition.x}px`; message.style.top = `${statusPosition.y}px`; message.style.bottom = 'auto';
}
function setPresentation(overlay?: ScreenshotOverlay): void {
  document.body.dataset.inplace = String(!!overlay);
  document.documentElement.dataset.inplace = String(!!overlay);
  if (!overlay) { for (const selector of ['.editor-toolbar', '#overlay-info', '#editor-status']) $(selector).removeAttribute('style'); }
}
function validateOverlay(overlay?: ScreenshotOverlay): void {
  if (!overlay) return;
  if (![overlay.x, overlay.y, overlay.width, overlay.height, overlay.viewportWidth, overlay.viewportHeight].every(Number.isFinite)
    || overlay.x < 0 || overlay.y < 0 || overlay.width <= 0 || overlay.height <= 0
    || overlay.viewportWidth <= 0 || overlay.viewportHeight <= 0
    || overlay.x + overlay.width > overlay.viewportWidth + 1 || overlay.y + overlay.height > overlay.viewportHeight + 1) {
    throw new Error('截图区域坐标无效，已禁止导出。');
  }
}
function render(): boolean {
  // Fail closed before resetting/drawing any pixels. A failed redaction/crop
  // must never expose the original or a partial frame as an exportable result.
  rendered = null; controls();
  if (!model || !original || contextLost) { if (contextLost) frame.hidden = true; return false; }
  try {
    const editing = textOpen() && editingIndex !== null;
    renderScreenshot(canvas, original, model.original, editing ? model.operations.filter((_, index) => index !== editingIndex) : model.operations);
    rendered = editing ? null : { generation, stateId: model.stateId }; frame.hidden = false;
    applyZoom(); selectionOutline(); controls(); return true;
  } catch (error) {
    frame.hidden = true; canvas.width = canvas.height = 1; controls();
    status(`图片绘制失败，已禁用贴图、复制和保存。请撤销本次编辑，或重新打开图片：${readableError(error)}`, true);
    return false;
  }
}
function clearGesture(restorePreview = true): void {
  const restore = restorePreview && !!gesture?.points;
  if (gesture && canvas.hasPointerCapture(gesture.pointerId)) canvas.releasePointerCapture(gesture.pointerId);
  gesture = null; $('#gesture-rect').setAttribute('visibility', 'hidden'); $('#gesture-line').setAttribute('visibility', 'hidden');
  if (restore && model && original) render();
}
function cancelText(): void { const restore = textOpen() && editingIndex !== null; textDialog.hidden = true; textInput.value = ''; textPoint = null; editingIndex = null; composing = false; imeEscape = false; if (restore) render(); controls(); }
function annotationBounds(op: EditOperation): OverlayRect {
  if (op.kind !== 'text') return operationBounds(op);
  const ctx = canvas.getContext('2d')!; ctx.save(); ctx.font = screenshotTextFont(op.size);
  const bounds = operationBounds(op, text => ctx.measureText(text).width); ctx.restore(); return bounds;
}
function selectionOutline(preview?: EditOperation): void {
  const outline = $('#object-selection'), op = preview ?? (selectedIndex === null ? undefined : model?.operations[selectedIndex]);
  $('#delete-edit').hidden = !op || op.kind === 'crop';
  if (!op || !model || op.kind === 'crop') { outline.setAttribute('visibility', 'hidden'); return; }
  const bounds = annotationBounds(op), offset = model.operationOffset(selectedIndex!);
  outline.setAttribute('visibility', 'visible');
  for (const [key, value] of Object.entries({ x: bounds.x - offset.x, y: bounds.y - offset.y, width: bounds.width, height: bounds.height })) outline.setAttribute(key, String(value));
}
function hitAnnotation(p: Point): number | null {
  if (!model) return null;
  for (let i = model.operations.length - 1; i >= 0; i--) {
    const op = model.operations[i]; if (op.kind === 'crop') continue;
    const offset = model.operationOffset(i), b = annotationBounds(op), x = p.x + offset.x, y = p.y + offset.y;
    if (x < b.x - 5 || x > b.x + b.width + 5 || y < b.y - 5 || y > b.y + b.height + 5) continue;
    if ((op.kind === 'pen' || op.kind === 'highlight') && !strokePathsIntersect(op.points, [{ x, y }], op.width / 2 + 5)) continue;
    if (op.kind === 'arrow' || op.kind === 'numbered-arrow') {
      const dx = op.end.x - op.start.x, dy = op.end.y - op.start.y;
      const t = Math.max(0, Math.min(1, ((x - op.start.x) * dx + (y - op.start.y) * dy) / (dx * dx + dy * dy || 1)));
      if (Math.hypot(x - op.start.x - t * dx, y - op.start.y - t * dy) > Math.max(7, op.width * 2)
        && !(op.kind === 'numbered-arrow' && Math.hypot(x - op.start.x, y - op.start.y) <= op.size / 2 + 4)) continue;
    }
    return i;
  }
  return null;
}
function placeTextEditor(): void {
  if (!textOpen() || !textPoint || !model) return;
  const r = canvas.getBoundingClientRect(), offset = editingIndex === null ? { x: 0, y: 0 } : model.operationOffset(editingIndex);
  const scale = r.width / model.size.width, scaleY = r.height / model.size.height, size = Number($<HTMLSelectElement>('#edit-font-size').value);
  const sourceSize = editingIndex === null ? model.size : model.operationSize(editingIndex);
  const maxWidth = Math.max(1, sourceSize.width - textPoint.x);
  textDialog.style.left = `${r.x + (textPoint.x - offset.x) * scale}px`;
  textDialog.style.top = `${r.y + (textPoint.y - offset.y) * scaleY}px`;
  textInput.style.font = screenshotTextFont(size * scale);
  textInput.style.lineHeight = '1.35';
  textInput.style.color = $<HTMLInputElement>('#edit-color').value;
  textInput.style.backgroundColor = $<HTMLSelectElement>('#note-style').value || 'transparent';
  // Use this control's real glyph metrics, not a different canvas font context.
  textInput.style.whiteSpace = 'pre'; textInput.style.width = '1px';
  const naturalWidth = Math.max(size * scale * 2, textInput.scrollWidth + 2);
  textDialog.style.width = `${Math.max(1, Math.min(maxWidth * scale, Math.ceil(naturalWidth)))}px`;
  textInput.style.width = '100%'; textInput.style.whiteSpace = 'pre-wrap';
  // Measure the actual textarea line boxes after font/width settle. Fractional
  // CSS heights otherwise create a scrollbar that narrows and rewraps the text.
  textInput.style.height = '0px';
  const contentHeight = textInput.scrollHeight + 1;
  const availableHeight = Math.max(1, (sourceSize.height - textPoint.y) * scaleY);
  textDialog.style.height = `${Math.min(availableHeight, contentHeight)}px`;
  textInput.style.height = '100%';
  if (contentHeight <= availableHeight) textInput.scrollTop = 0;
}

function beginText(p: Point, index: number | null = null): void {
  if (!model) return;
  const op = index === null ? null : model.operations[index];
  editingIndex = op?.kind === 'text' ? index : null;
  textPoint = op?.kind === 'text' ? { ...op.point } : { x: Math.min(model.size.width - 1, Math.floor(p.x)), y: Math.min(model.size.height - 1, Math.floor(p.y)) };
  textInput.value = op?.kind === 'text' ? op.text : '';
  if (op?.kind === 'text') {
    $<HTMLInputElement>('#edit-color').value = op.color;
    $<HTMLSelectElement>('#edit-font-size').value = String(op.size);
    $<HTMLSelectElement>('#note-style').value = op.background ?? '';
  }
  textDialog.hidden = false; if (editingIndex !== null) render(); placeTextEditor(); controls(); textInput.focus();
}
function commitText(): boolean {
  if (!textOpen()) return true;
  if (composing || !model || !textPoint) return false;
  if (!textInput.value.trim()) { cancelText(); return true; }
  const size = editingIndex === null ? model.size : model.operationSize(editingIndex);
  const operation: EditOperation = { kind: 'text', point: textPoint, text: textInput.value, color: $<HTMLInputElement>('#edit-color').value,
    size: Number($<HTMLSelectElement>('#edit-font-size').value), maxWidth: Math.max(1, size.width - textPoint.x),
    background: $<HTMLSelectElement>('#note-style').value || undefined };
  try {
    if (editingIndex !== null) { model.update(editingIndex, operation); selectedIndex = editingIndex; }
    else { model.append(operation); selectedIndex = model.operations.length - 1; }
    cancelText(); render(); status('文字已添加，可用选择工具拖动，双击修改。'); return true;
  } catch (error) { status(readableError(error), true); return false; }
}

function resolveDiscard(value: boolean): void { closeDialog(discardDialog); const resolve = discardResolve; discardResolve = null; resolve?.(value); }
async function confirmDiscard(action: 'open' | 'close' | 'restart'): Promise<boolean> {
  if (!dirty() || (action === 'restart' && !model?.operations.length && !(textOpen() && textInput.value.trim()))) return true;
  if (discardResolve) return false;
  $('#discard-description').textContent = action === 'restart' ? '重新框选将丢弃当前截图和标注，不会保存或复制。新选区可以拖动边角调整；取消新截图不会恢复旧标注。' : action === 'close' ? '关闭后，本次图片和编辑内容将被丢弃。不会自动保存。' : '打开新图片会替换当前图片。取消文件选择时，当前图片仍会保留。';
  $('#discard-confirm').textContent = action === 'restart' ? '丢弃并重新框选' : action === 'close' ? '丢弃并关闭' : '继续打开';
  showDialog(discardDialog); $<HTMLButtonElement>('#discard-cancel').focus();
  return new Promise(resolve => { discardResolve = resolve; });
}
async function acceptSession(value: IncomingSession | null): Promise<void> {
  if (value && (!Number.isSafeInteger(value.id) || value.id <= latestId)) return;
  if (value) latestId = value.id;
  const token = ++generation;
  if (pendingStroke) pendingStroke.cancelled = true;
  pendingStroke = null; clearPendingPreview(); capturePending = null; selectionSession = null; selectionDrag = null; selectionUpdating = false;
  if (decoding) { decoding.src = ''; decoding = null; } // Cancel superseded image decode work.
  clearGesture(); moveGesture = null; selectedIndex = null; cancelText(); resolveDiscard(false); textFocusPending = false; overlayFocus = null; busy = false; nativeDialog = false; loading = !!value;
  session = null; original = null; model = null; savedState = null; rendered = null;
  canvas.width = canvas.height = 1; canvas.hidden = false; frame.hidden = true; $('#empty-state').hidden = !!value; controls();
  if (!value) { setPresentation(); status('截图已取消。使用截图快捷键重新截图，或打开本地图片。'); return; }
  if (value.kind === 'selection') {
    try {
      validateSize(value); validateOverlay(value.overlay);
      if (!Number.isSafeInteger(value.revision) || value.revision < 0) throw new Error('截图选区版本无效');
      selectionSession = value; session = { ...value }; setPresentation(value.overlay); chooseTool('select');
      loading = false; frame.hidden = false; canvas.hidden = false; $('#empty-state').hidden = true;
      placeSelectionFrame(); controls(); status('');
      if (desktop) await invoke('screenshot_editor_ready', { sessionId: value.id });
    } catch (error) { if (token === generation) { loading = false; controls(); status(readableError(error), true); } }
    return;
  }
  if (value.overlay && value.revision !== undefined) selectionSession = { kind: 'selection', id: value.id, revision: value.revision, width: value.width, height: value.height, overlay: value.overlay };
  const { pngBase64, ...metadata } = value; session = metadata; setPresentation(value.overlay); chooseTool('select');
  status('正在准备图片…');
  try {
    validateSize(value); validateOverlay(value.overlay);
    if (!pngBase64 || pngBase64.length > Math.ceil(MAX_ENCODED_BYTES / 3) * 4 || !pngBase64.startsWith('iVBORw0KGgo')) throw new Error('图片损坏、格式不支持或超过 32 MiB。请打开有效的 PNG / JPEG。');
    const image = new Image(); decoding = image; image.src = `data:image/png;base64,${pngBase64}`;
    await image.decode();
    if (token !== generation) return;
    decoding = null;
    if (image.naturalWidth !== value.width || image.naturalHeight !== value.height) throw new Error('图片尺寸不一致，无法安全打开。');
    original = image; model = new ScreenshotDocument(value); fit = true;
    frame.hidden = false; $('#empty-state').hidden = true; loading = false; const drawn = render();
    if (drawn) status('');
    // A backend claim survives WebView reloads; event/snapshot metadata alone
    // must never trigger a second save/copy/pin of the same capture intent.
    const initialIntent = drawn && value.overlay && value.initialAction !== undefined;
    if (initialIntent) { busy = true; controls(); }
    if (desktop) await invoke('screenshot_editor_ready', { sessionId: value.id });
    if (token !== generation || session?.id !== value.id) return;
    if (desktop && initialIntent) {
      let action: string | null;
      try { action = await invoke<string | null>('consume_screenshot_initial_action', { sessionId: value.id }); }
      catch (error) {
        if (token === generation) { busy = false; controls(); status(`截图已保留，请手动选择工具或完成：${readableError(error)}`, true); }
        return;
      }
      if (token !== generation || session?.id !== value.id) return;
      busy = false; controls();
      if (action && toolActions.includes(action)) chooseTool(action as Tool);
      else if (action && ['copy', 'save', 'pin'].includes(action)) await exportImage(action as 'copy' | 'save' | 'pin');
    } else { busy = false; controls(); }
  } catch (error) {
    if (token !== generation) return;
    decoding = null; loading = false; busy = false; model = null; original = null; frame.hidden = true; $('#empty-state').hidden = false;
    status(`无法打开图片：${readableError(error)}`, true); controls();
    // Show a prepared error state too, rather than leave an invisible window.
    if (desktop) await invoke('screenshot_editor_ready', { sessionId: value.id }).catch(() => {});
  }
}
function chooseTool(next: Tool): void {
  if (textOpen() && !commitText()) return;
  cancelPointer(); tool = next;
  $<HTMLDetailsElement>('#zoom-menu').open = false;
  for (const button of document.querySelectorAll<HTMLButtonElement>('.editor-toolbar button[data-tool]')) button.setAttribute('aria-pressed', String(button.dataset.tool === tool));
  $('.tool-options').hidden = next === 'select' || next === 'crop';
  $('#color-label').hidden = ['select', 'crop', 'eraser', 'mosaic'].includes(next);
  $('#text-size-label').hidden = next !== 'text' && next !== 'number';
  $('#note-style-label').hidden = next !== 'text'; $('#step-style-label').hidden = next !== 'number';
  $('#line-width-label').hidden = !['rectangle', 'arrow', 'number', 'pen', 'highlight'].includes(next);
  $('#shape-style-label').hidden = next !== 'rectangle'; $('#eraser-size-label').hidden = next !== 'eraser'; $('#mosaic-size-label').hidden = next !== 'mosaic';
  const hints: Record<Tool, string> = { select: '点击标注选择；拖动移动，双击文字修改，Delete 删除。', rectangle: '选择矩形或椭圆后拖动绘制。所有标注均以原图像素为准。', pen: '按住拖动自由绘制；松开后整笔可撤销。', highlight: '半透明高亮，不遮住原有文字；不要用于遮挡隐私。', eraser: '仅局部擦除画笔和高亮，不擦原图、马赛克或实心遮挡；其他标注用选择工具删除。', arrow: '从起点拖向终点，绘制箭头。', text: '点击原位添加文字；可选便签背景，双击已有文字修改。', number: '连续点击添加序号，或切换序号箭头后拖动；编号自动递增。', mosaic: '拖动选择马赛克区域。敏感文字建议使用实心遮挡。', solid: '拖动绘制不透明色块，彻底遮挡区域内的像素。', crop: '拖动选择保留范围；松开立即裁剪，可撤销。' };
  $('#tool-hint').textContent = hints[next]; canvas.dataset.tool = next; placeOverlayTools();
}
function clearPendingPreview(): void {
  $('#gesture-rect').setAttribute('visibility', 'hidden'); $('#gesture-line').setAttribute('visibility', 'hidden');
  $('#pending-ink').setAttribute('points', '');
}
function previewPendingStroke(event: PointerEvent): void {
  const p = pendingStroke, selected = selectionSession; if (!p || !selected) return;
  const bounds = canvas.getBoundingClientRect();
  const at = (e: PointerEvent) => imagePoint({ x: e.clientX, y: e.clientY }, bounds, selected);
  const start = at(p.down), end = at(event);
  $('#gesture-preview').setAttribute('viewBox', `0 0 ${selected.width} ${selected.height}`);
  if (p.tool === 'pen' || p.tool === 'highlight') {
    const ink = $('#pending-ink'); ink.setAttribute('points', [p.down,...p.events].map(e=>{const q=at(e);return `${q.x},${q.y}`;}).join(' '));
    ink.setAttribute('stroke', $<HTMLInputElement>('#edit-color').value);
    ink.setAttribute('stroke-width', String(Number($<HTMLSelectElement>('#edit-width').value) * (p.tool === 'highlight' ? 4 : 1)));
    ink.setAttribute('opacity', p.tool === 'highlight' ? '.35' : '1');
  } else if (p.tool === 'arrow' || p.tool === 'number') {
    const line = $('#gesture-line'); line.setAttribute('visibility','visible');
    for (const [key,value] of Object.entries({x1:start.x,y1:start.y,x2:end.x,y2:end.y})) line.setAttribute(key,String(value));
  } else if (p.tool !== 'text') {
    const rect = $('#gesture-rect'); rect.setAttribute('visibility','visible');
    for (const [key,value] of Object.entries(selectionRect(start,end,selected))) rect.setAttribute(key,String(value));
  }
}
function placeSelectionFrame(): void {
  const overlay = session?.overlay; if (!overlay) return;
  frame.style.left = `${overlay.x}px`; frame.style.top = `${overlay.y}px`;
  frame.style.width = `${overlay.width}px`; frame.style.height = `${overlay.height}px`;
  frame.hidden = false; placeOverlayTools();
}
async function ensureSelectionImage(): Promise<boolean> {
  if (model) return true;
  if (capturePending) return capturePending;
  if (!selectionSession || !desktop || selectionUpdating) return false;
  const token = generation, selected = selectionSession;
  busy = true;
  const task = (async () => {
    try {
      const value = await invoke<ScreenshotSession>('capture_screenshot_selection', { sessionId: selected.id, revision: selected.revision });
      if (token !== generation || session?.id !== selected.id || session.revision !== selected.revision) return false;
      if (value.kind !== 'image' || value.id !== selected.id || value.revision !== selected.revision) throw new Error('截图返回了过期的选区');
      validateSize(value); validateOverlay(value.overlay);
      if (!value.pngBase64 || value.pngBase64.length > Math.ceil(MAX_ENCODED_BYTES / 3) * 4 || !value.pngBase64.startsWith('iVBORw0KGgo')) throw new Error('截图像素无效');
      const image = new Image(); decoding = image; image.src = `data:image/png;base64,${value.pngBase64}`; await image.decode();
      if (token !== generation || session?.id !== selected.id || session.revision !== selected.revision) return false;
      if (image.naturalWidth !== value.width || image.naturalHeight !== value.height) throw new Error('截图尺寸不一致');
      decoding = null; const { pngBase64: _pixels, ...metadata } = value; session = metadata;
      original = image; model = new ScreenshotDocument(value); savedState = model.stateId;
      if (!render()) return false;
      status(''); return true;
    } catch (error) {
      if (token === generation) { status(`未取得截图，请重试或取消：${readableError(error)}`, true); }
      return false;
    } finally { if (token === generation) { capturePending = null; busy = false; controls(); } }
  })();
  capturePending = task; controls(); return task;
}
function beginSelectionDrag(event: PointerEvent, handle: SelectionHandle): void {
  pointerProbe('begin-attempt', event);
  if (!event.isPrimary || event.button !== 0 || pendingStroke || selectionDrag || busy || loading || !canAdjustSelection() || !session?.overlay) return;
  event.preventDefault(); event.stopPropagation();
  selectionDrag = { pointerId: event.pointerId, start: { x: event.clientX, y: event.clientY }, rect: { ...session.overlay }, handle };
  frame.setPointerCapture(event.pointerId); pointerProbe('begin', event);
}
$('#selection-handles').addEventListener('pointerdown', event => {
  const pointer = event as PointerEvent, handle = (event.target as HTMLElement).dataset.resize as SelectionHandle | undefined;
  if (handle) beginSelectionDrag(pointer, handle);
});
frame.addEventListener('pointermove', event => {
  pointerProbe('move-attempt', event);
  if (!selectionDrag || selectionDrag.pointerId !== event.pointerId || !session?.overlay) return;
  const g = selectionDrag, overlay = session.overlay;
  const rect = adjustSelection(g.rect, g.handle, event.clientX - g.start.x, event.clientY - g.start.y,
    { x: 0, y: 0, width: overlay.viewportWidth, height: overlay.viewportHeight });
  session.overlay = { ...overlay, ...rect }; frame.dataset.liveSelection = 'true'; canvas.hidden = true; placeSelectionFrame(); pointerProbe('move', event);
});
async function endSelectionDrag(event: PointerEvent, cancelled = false): Promise<void> {
  pointerProbe(cancelled ? 'cancel' : 'up-attempt', event);
  if (!selectionDrag || selectionDrag.pointerId !== event.pointerId || !session?.overlay || !selectionSession) return;
  const g = selectionDrag; selectionDrag = null;
  if (frame.hasPointerCapture(event.pointerId)) frame.releasePointerCapture(event.pointerId);
  const token = generation, previous = selectionSession, rect = session.overlay;
  if (cancelled || ['x','y','width','height'].every(k => rect[k as keyof OverlayRect] === g.rect[k as keyof OverlayRect])) {
    session.overlay = { ...session.overlay, ...g.rect }; canvas.hidden = false; if (model) applyZoom(); else placeSelectionFrame(); controls(); return;
  }
  selectionUpdating = true; busy = true; controls(); pointerProbe('update', event);
  try {
    const value = await invoke<SelectionSession>('update_screenshot_selection', { sessionId: previous.id, revision: previous.revision,
      rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height } });
    if (token !== generation || session?.id !== previous.id) return;
    if (value.kind !== 'selection' || value.id !== previous.id || value.revision !== previous.revision + 1) throw new Error('选区更新版本无效');
    validateSize(value); validateOverlay(value.overlay);
    selectionSession = value; session = { ...value }; original = null; model = null; rendered = null; savedState = null;
    canvas.width = canvas.height = 1; placeSelectionFrame(); status(''); pointerProbe('updated', event);
  } catch (error) {
    pointerProbe('update-error', event);
    if (token === generation && session) { session.overlay = previous.overlay; if (model) applyZoom(); else placeSelectionFrame(); status(`未调整选区：${readableError(error)}`, true); }
  } finally { if (token === generation) { canvas.hidden = false; selectionUpdating = false; busy = false; controls(); } }
}
frame.addEventListener('pointerup', event => { void endSelectionDrag(event); });
frame.addEventListener('pointercancel', event => { void endSelectionDrag(event, true); });
canvas.addEventListener('pointerdown', event => {
  pointerProbe('canvas-down', event);
  if (!event.isPrimary || pendingStroke || selectionDrag || gesture || moveGesture) return;
  if (tool === 'select' && canAdjustSelection()) { beginSelectionDrag(event, 'move'); return; }
  if (model) { void beginCanvasPointer(event); return; }
  if (!selectionSession || busy || loading || event.button !== 0 || tool === 'select' || tool === 'eraser') return;
  event.preventDefault();
  const pending = { generation, down: event, tool, style: annotationStyleKey(), events: [] as PointerEvent[], cancelled: false, released: false };
  pendingStroke = pending; canvas.setPointerCapture(event.pointerId);
  controls();

});
canvas.addEventListener('pointermove', event => {
  if (pendingStroke) {
    if (event.pointerId !== pendingStroke.down.pointerId) return;
    if (pendingStroke.events.length >= MAX_STROKE_POINTS) { pendingStroke.cancelled = true; return; }
    pendingStroke.events.push(event); previewPendingStroke(event); return;
  }
  moveCanvasPointer(event);
});
canvas.addEventListener('pointerup', event => {
  if (pendingStroke) {
    if (event.pointerId !== pendingStroke.down.pointerId) return;
    const pending = pendingStroke; pending.released = true; pending.events.push(event);
    if (pending.cancelled) { pendingStroke = null; clearPendingPreview(); controls(); return; }
    // Hide/capture only after release: suspending a native host during a held
    // pointer would otherwise cancel capture or lose part of the first stroke.
    void ensureSelectionImage().then(async ok => {
      if (!ok || pending.cancelled || pending.generation !== generation || pendingStroke !== pending || pending.tool !== tool || pending.style !== annotationStyleKey()) return;
      await beginCanvasPointer(pending.down);
      if (pending.cancelled || pending.generation !== generation || pendingStroke !== pending || pending.tool !== tool || pending.style !== annotationStyleKey()) { cancelPointer(); return; }
      for (const e of pending.events) { if (e.type === 'pointerup') endCanvasPointer(e); else moveCanvasPointer(e); }
    }).finally(() => { if (pendingStroke === pending) { pendingStroke = null; clearPendingPreview(); controls(); } });
    return;
  }
  endCanvasPointer(event);
});

function point(event: PointerEvent): Point { const r = canvas.getBoundingClientRect(); return imagePoint({ x: event.clientX, y: event.clientY }, { x: r.x, y: r.y, width: r.width, height: r.height }, model!.size); }
function append(operation: EditOperation): void {
  try { model?.append(operation); if (render()) status(operation.kind === 'crop' ? '已裁剪实际像素。可撤销；导出不会包含裁剪掉的部分。' : '标注已添加。尚未写入文件。'); }
  catch (error) { status(readableError(error), true); }
}
function requestOverlayFocus(): Promise<void> {
  if (!desktop || !inplace() || !session) return Promise.resolve();
  if (overlayFocus?.generation === generation) return overlayFocus.promise;
  const token = generation, sessionId = session.id;
  const promise = invoke<void>('focus_screenshot_overlay', { sessionId });
  overlayFocus = { generation: token, promise };
  // Retain successful focus for this session; a failed explicit click can retry.
  void promise.catch(() => { if (overlayFocus?.promise === promise) overlayFocus = null; });
  return promise;
}
function focusFromEditorPointer(event: PointerEvent): void {
  if (!windows || event.button !== 0 || !inplace() || busy || loading || !model || textOpen() || composing) return;
  if (event.target instanceof Element && (event.target.closest('.inplace-actions') || event.target.closest('button:disabled'))) return;
  const token = generation;
  // Do not await: ordinary pointer capture/drawing must begin synchronously.
  void requestOverlayFocus().catch(error => {
    if (token === generation) status(`无法接管编辑快捷键，可再次点击重试：${readableError(error)}`, true);
  });
}
$('.editor-toolbar').addEventListener('pointerdown', focusFromEditorPointer, true);
canvas.addEventListener('pointerdown', focusFromEditorPointer, true);
async function beginCanvasPointer(event: PointerEvent): Promise<void> {
  if (event.button !== 0 || busy || loading || !model ) return;
  // Text owns focus from this pointer gesture. The browser's later default
  // mousedown focus on the canvas would otherwise immediately blur/commit it.
  if (tool === 'text') event.preventDefault();
  const start = point(event); canvas.focus({ preventScroll: true });
  if (textOpen() && !commitText()) return;
  if (tool === 'select') {
    selectedIndex = hitAnnotation(start); selectionOutline();
    if (selectedIndex !== null) {
      const original = model.operations[selectedIndex];
      moveGesture = { index: selectedIndex, start, original, moved: original, pointerId: event.pointerId };
      canvas.setPointerCapture(event.pointerId);
    }
    return;
  }
  if (tool === 'text') {
    const token = generation;
    if (desktop && inplace()) {
      textFocusPending = true;
      try { await requestOverlayFocus(); }
      catch (error) { if (token === generation) status(`无法输入标注：${readableError(error)}`, true); return; }
      finally { if (token === generation) textFocusPending = false; }
      if (token !== generation || busy || !model || tool !== 'text') return;
    }
    const hit = hitAnnotation(start);
    beginText(start, hit !== null && model.operations[hit].kind === 'text' ? hit : null); return;
  }
  if (tool === 'number' && $<HTMLSelectElement>('#step-style').value === 'number') {
    append({ kind: 'number', point: start, number: model.nextNumber, size: Number($<HTMLSelectElement>('#edit-font-size').value), color: $<HTMLInputElement>('#edit-color').value }); return;
  }
  gesture = { start, end: start, pointerId: event.pointerId, ...(['pen', 'highlight', 'eraser'].includes(tool) ? { points: [start] } : {}) }; if (event.buttons) { try { canvas.setPointerCapture(event.pointerId); } catch { /* Buffered pointer may already be released. */ } } event.preventDefault();
}
function moveCanvasPointer(event: PointerEvent): void {
  if (moveGesture && model && original && event.pointerId === moveGesture.pointerId) {
    const p = point(event), g = moveGesture;
    if (model.operations[g.index] !== g.original) { cancelPointer(); return; }
    g.moved = translateOperation(g.original, { x: p.x - g.start.x, y: p.y - g.start.y }, model.operationSize(g.index));
    const preview = [...model.operations]; preview[g.index] = g.moved;
    try { renderScreenshot(canvas, original, model.original, preview); selectionOutline(g.moved); rendered = null; controls(); }
    catch (error) { status(readableError(error), true); clearGesture(); moveGesture = null; render(); }
    return;
  }
  if (!gesture || !model || gesture.pointerId !== event.pointerId) return;
  gesture.end = point(event);
  if (gesture.points) {
    const points = gesture.points, last = points[points.length - 1];
    if (Math.hypot(last.x - gesture.end.x, last.y - gesture.end.y) >= 1) {
      if (points.length >= MAX_STROKE_POINTS) { cancelPointer(); status('单笔路径过长，已取消本笔；请分成多笔绘制或擦除。', true); return; }
      points.push(gesture.end);
    }
    if (tool === 'pen' || tool === 'highlight') {
      try {
        const op: EditOperation = { kind: tool, points, color: $<HTMLInputElement>('#edit-color').value, width: Number($<HTMLSelectElement>('#edit-width').value) * (tool === 'highlight' ? 4 : 1) };
        renderScreenshot(canvas, original!, model.original, [...model.operations, op]); rendered = null; controls();
      } catch (error) { cancelPointer(); status(readableError(error), true); }
    }
    return;
  }
  if (tool === 'arrow' || tool === 'number') {
    const line = $('#gesture-line'); line.setAttribute('visibility', 'visible');
    for (const [key, value] of Object.entries({ x1: gesture.start.x, y1: gesture.start.y, x2: gesture.end.x, y2: gesture.end.y })) line.setAttribute(key, String(value));
  } else {
    const rect = selectionRect(gesture.start, gesture.end, model.size), preview = $('#gesture-rect'); preview.setAttribute('visibility', 'visible');
    for (const [key, value] of Object.entries(rect)) preview.setAttribute(key, String(value));
  }
}
function endCanvasPointer(event: PointerEvent): void {
  if (moveGesture && model && event.pointerId === moveGesture.pointerId) {
    const g = moveGesture; moveGesture = null;
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    try { if (model.operations[g.index] === g.original && JSON.stringify(g.original) !== JSON.stringify(g.moved)) model.update(g.index, g.moved); }
    catch (error) { status(readableError(error), true); }
    render(); return;
  }
  if (!gesture || !model || gesture.pointerId !== event.pointerId) return;
  const { start, points } = gesture, end = point(event); clearGesture();
  if (points) {
    if (points.length < MAX_STROKE_POINTS && Math.hypot(points[points.length - 1].x - end.x, points[points.length - 1].y - end.y) >= 1) points.push(end);
    try {
      if (tool === 'eraser') { const changed = model.eraseStrokes(points, Number($<HTMLSelectElement>('#eraser-size').value)); render(); status(changed ? '已擦除笔迹，可撤销；原图和隐私遮挡未改变。' : '这里没有可擦除的画笔或高亮。'); }
      else if (tool === 'pen' || tool === 'highlight') append({ kind: tool, points, color: $<HTMLInputElement>('#edit-color').value, width: Number($<HTMLSelectElement>('#edit-width').value) * (tool === 'highlight' ? 4 : 1) });
    } catch (error) { render(); status(readableError(error), true); }
    return;
  }
  if (Math.hypot(end.x - start.x, end.y - start.y) < 1) return;
  const rect = selectionRect(start, end, model.size), color = $<HTMLInputElement>('#edit-color').value, width = Number($<HTMLSelectElement>('#edit-width').value);
  if (tool === 'arrow') append({ kind: 'arrow', start, end, color, width });
  else if (tool === 'number') append({ kind: 'numbered-arrow', start, end, color, width, number: model.nextNumber, size: Number($<HTMLSelectElement>('#edit-font-size').value) });
  else if (rect.width && rect.height) {
    if (tool === 'crop') append({ kind: 'crop', rect });
    else if (tool === 'mosaic') append({ kind: 'mosaic', rect, blockSize: Number($<HTMLSelectElement>('#edit-block-size').value) });
    else if (tool === 'rectangle' && $<HTMLSelectElement>('#shape-style').value === 'ellipse') append({ kind: 'ellipse', rect, color, width });
    else append({ kind: 'rectangle', rect, color, width, solid: tool === 'solid' });
  }
}
canvas.addEventListener('contextlost', event => {
  event.preventDefault(); contextLost = true; moveGesture = null; clearGesture(false); rendered = null; frame.hidden = true; controls();
  status('图片画布已中断，已禁用贴图、复制和保存。正在等待画布恢复；也可以重新打开图片。', true);
});
canvas.addEventListener('contextrestored', () => { contextLost = false; if (render()) status('图片画布已恢复。'); });
function cancelPointer(): void {
  if (pendingStroke) { pendingStroke.cancelled = true; if (!capturePending) { pendingStroke = null; clearPendingPreview(); controls(); } }
  const moving = moveGesture; moveGesture = null;
  if (moving && canvas.hasPointerCapture(moving.pointerId)) canvas.releasePointerCapture(moving.pointerId);
  clearGesture(); if (moving) render();
}
function cancelOwnedPointer(event: PointerEvent): void {
  const owner = pendingStroke?.down.pointerId ?? moveGesture?.pointerId ?? gesture?.pointerId;
  if (owner === undefined || event.pointerId !== owner) return;
  if (event.type === 'lostpointercapture' && pendingStroke?.released) return;
  cancelPointer();
}
canvas.addEventListener('pointercancel', cancelOwnedPointer); canvas.addEventListener('lostpointercapture', cancelOwnedPointer);
canvas.addEventListener('dblclick', event => {
  if (busy || loading || !model || !['select', 'text'].includes(tool)) return;
  const r = canvas.getBoundingClientRect(), p = imagePoint({ x: event.clientX, y: event.clientY }, r, model.size), hit = hitAnnotation(p);
  if (hit !== null && model.operations[hit].kind === 'text') { chooseTool('text'); selectedIndex = hit; beginText(p, hit); }
});
$('#delete-edit').addEventListener('click', () => {
  if (busy || !model || selectedIndex === null || textOpen()) return;
  try { cancelPointer(); model.remove(selectedIndex); selectedIndex = null; render(); status('已删除标注，可撤销。'); } catch (error) { status(readableError(error), true); }
});
for (const button of document.querySelectorAll<HTMLButtonElement>('.editor-toolbar button[data-tool]')) button.addEventListener('click', () => chooseTool(button.dataset.tool as Tool));
textInput.addEventListener('compositionstart', () => { composing = true; }); textInput.addEventListener('compositionend', () => { composing = false; });
textInput.addEventListener('input', () => { controls(); placeTextEditor(); });
textInput.addEventListener('keydown', event => {
  if (event.isComposing || event.keyCode === 229 || composing) { if (event.key === 'Escape') imeEscape = true; return; }
  if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); if (imeEscape) { imeEscape = false; return; } cancelText(); canvas.focus(); }
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); if (commitText()) canvas.focus(); }
});
$('#discard-cancel').addEventListener('click', () => resolveDiscard(false)); $('#discard-confirm').addEventListener('click', () => resolveDiscard(true));
discardDialog.addEventListener('cancel', event => { event.preventDefault(); resolveDiscard(false); });
$('#undo-edit').addEventListener('click', () => { if (!busy && commitText() && model?.undo()) { selectedIndex = null; cancelPointer(); if (render()) status('已撤销。'); } });
$('#redo-edit').addEventListener('click', () => { if (!busy && commitText() && model?.redo()) { selectedIndex = null; cancelPointer(); if (render()) status('已重做。'); } });
function changeZoom(value: number): void { fit = false; zoom = Math.max(0.05, Math.min(4, value)); applyZoom(); }
$('#zoom-in').addEventListener('click', () => changeZoom(zoom * 1.25)); $('#zoom-out').addEventListener('click', () => changeZoom(zoom / 1.25));
$('#zoom-actual').addEventListener('click', () => changeZoom(1)); $('#zoom-fit').addEventListener('click', () => { fit = true; applyZoom(); });
new ResizeObserver(() => { if (fit || inplace()) applyZoom(); }).observe(workspace);
new ResizeObserver(placeOverlayTools).observe($('.editor-toolbar'));
new ResizeObserver(placeTextEditor).observe(textDialog);
window.addEventListener('resize', placeTextEditor);
for (const selector of ['#edit-font-size', '#edit-color', '#note-style']) $(selector).addEventListener('input', placeTextEditor);
async function exportImage(action: 'copy' | 'save' | 'saveAs' | 'pin'): Promise<void> {
  if (action === 'saveAs' && inplace()) {
    status('原地截图使用设置中的保存目录；请在设置修改目录'); return;
  }
  if (!session || busy || loading || selectionDrag || pendingStroke || gesture || moveGesture || !commitText()) return;
  if (!model && !await ensureSelectionImage()) return;
  if (!model || !session) return;
  if (!exportReady()) { status('当前图片尚未完整绘制，不能贴图、复制或保存。请撤销或重新打开图片。', true); return; }
  if (!desktop) { status('请在桌面应用中贴图、复制或保存图片。'); return; }
  clearGesture(); const token = generation, sessionId = session.id, revision = session.revision ?? 0, state = model.stateId;
  busy = true; controls(); status(action === 'pin' ? '正在固定图片…' : action === 'copy' ? '正在复制图片…' : '正在准备保存…');
  try {
    const pngBase64 = await flattenedPng(canvas);
    if (token !== generation || session?.id !== sessionId || !exportReady() || model.stateId !== state) return;
    if (action === 'pin') {
      await invoke('pin_screenshot_image', { sessionId, revision, pngBase64 });
      if (token === generation) {
        status('图片已固定到桌面；未保存文件，也未更改剪贴板。');
        if (inplace()) await dismissAfterExport(sessionId, revision, token, '图片已固定到桌面');
      }
    }
    else if (action === 'copy') { await invoke('copy_screenshot_image', { sessionId, revision, pngBase64 }); if (token === generation) { status('已复制合并后的图片。剪贴板不包含原图或编辑图层。'); if (inplace()) await dismissAfterExport(sessionId, revision, token, '图片已复制到剪贴板'); } }
    else {
      nativeDialog = action === 'saveAs'; controls();
      const result = await invoke<{ path: string; fileName?: string } | null>('save_screenshot_image', { sessionId, revision, pngBase64, saveAs: action === 'saveAs' });
      if (token !== generation) return;
      if (result) { savedState = state; status(`已保存：${result.path}`); if (inplace()) await dismissAfterExport(sessionId, revision, token, `图片已保存：${result.path}`); } else status('已取消保存，图片和编辑内容仍保留。');
    }
  } catch (error) { if (token === generation) status(`未完成${action === 'pin' ? '贴图' : action === 'copy' ? '复制' : '保存'}：${readableError(error)}`, true); }
  finally { if (token === generation) { busy = false; nativeDialog = false; controls(); } }
}
async function openImage(): Promise<void> {
  if (busy || loading) return;
  if (!desktop) { status('请在桌面应用中打开本地图片。'); return; }
  const token = generation;
  if (!await confirmDiscard('open') || token !== generation) return;
  busy = true; nativeDialog = true; controls();
  try {
    // Null/cancel never clears the existing image. A successful open is delivered
    // through the same durable session/event boundary as a fresh capture.
    const next = await invoke<ScreenshotSession | null>('open_screenshot_image', { sessionId: session?.id ?? null });
    if (next && typeof next.id === 'number') await acceptSession(next);
    else if (token === generation) status('未选择新图片；当前图片保持不变。');
  } catch (error) { if (token === generation) status(`无法打开图片：${readableError(error)}`, true); }
  finally { if (token === generation) { busy = false; nativeDialog = false; controls(); } }
}
async function dismissOverlay(sessionId: number, token: number, revision?: number): Promise<void> {
  if (generation !== token || session?.id !== sessionId) return;
  if (desktop) await invoke('close_screenshot_editor', { sessionId, ...(revision === undefined ? {} : { revision }) });
  if (generation === token && session?.id === sessionId) await acceptSession(null);
}
async function dismissAfterExport(sessionId: number, revision: number, token: number, completed: string): Promise<void> {
  try { await dismissOverlay(sessionId, token, revision); }
  catch (error) {
    // The explicit clipboard/file operation has committed. Never label it a
    // failed export or retry it merely because native dismissal failed.
    if (token === generation) status(`${completed}；退出失败，请点击 × 关闭，无需再次贴图、复制或保存：${readableError(error)}`, true);
  }
}
async function closeEditor(): Promise<void> {
  // Keep an owned native sheet visible. Plain export/copy can finish after a
  // confirmed close only if the backend has already committed the explicit act.
  if (nativeDialog) { status('请先完成或取消当前文件对话框，再关闭编辑器。'); return; }
  const token = generation;
  if (inplace()) {
    if (capturePending || selectionUpdating) {
      const id = session!.id;
      // Invalidate local continuations before waiting for native cancellation.
      await acceptSession(null);
      try { if (desktop) await invoke('close_screenshot_editor', { sessionId: id }); }
      catch (error) { status(`无法关闭截图：${readableError(error)}`, true); }
      return;
    }
    if (busy) return;
    cancelPointer(); // Never race a committed clipboard/file export with discard.
    busy = true; controls();
    try { await dismissOverlay(session!.id, token); }
    catch (error) { if (token === generation) status(`无法取消截图：${readableError(error)}`, true); }
    finally { if (token === generation) { busy = false; controls(); } }
    return;
  }
  if (!await confirmDiscard('close') || token !== generation) return;
  try { if (desktop) await invoke('close_screenshot_editor', { sessionId: session?.id ?? null }); if (token === generation) await acceptSession(null); }
  catch (error) { status(`无法关闭窗口：${readableError(error)}`, true); }
}
async function restartSelection(): Promise<void> {
  if (!desktop || !session || !inplace() || busy || loading || nativeDialog || composing) return;
  cancelPointer(); const token = generation, sessionId = session.id;
  if (!await confirmDiscard('restart') || token !== generation || session?.id !== sessionId) return;
  busy = true; controls();
  try { await invoke('restart_screenshot_capture', { sessionId }); }
  catch (error) { if (token === generation) status(`无法重新框选：${readableError(error)}`, true); }
  finally { if (token === generation) { busy = false; controls(); } }
}
$('#restart-selection').addEventListener('click', () => void restartSelection());
$('#overlay-pin').addEventListener('click', () => void exportImage('pin'));
$('#pin-image').addEventListener('click', () => void exportImage('pin'));
$('#overlay-copy').addEventListener('click', () => void exportImage('copy'));
$('#overlay-save').addEventListener('click', () => void exportImage('save'));
$('#overlay-cancel').addEventListener('click', () => void closeEditor());
$('#open-image').addEventListener('click', () => void openImage()); $('#close-editor').addEventListener('click', () => void closeEditor());
$('#copy-image').addEventListener('click', () => void exportImage('copy')); $('#save-image').addEventListener('click', () => void exportImage('save')); $('#save-as-image').addEventListener('click', () => void exportImage('saveAs'));
document.addEventListener('keydown', event => {
  if (textFocusPending || event.isComposing || event.keyCode === 229 || composing || textOpen() || dialogOpen(discardDialog)) return;
  if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement || event.target instanceof HTMLSelectElement) return;
  const mod = event.ctrlKey || event.metaKey, key = event.key.toLowerCase();
  if (event.key === 'Enter' && inplace() && !mod && !event.altKey && !event.shiftKey) { event.preventDefault(); if (!event.repeat) void exportImage('copy'); return; }
  if (event.key === 'Escape' && $<HTMLDetailsElement>('#zoom-menu').open) { event.preventDefault(); $<HTMLDetailsElement>('#zoom-menu').open = false; $<HTMLElement>('#zoom-menu summary').focus(); return; }
  if (event.key === 'Escape') { event.preventDefault(); if (gesture || moveGesture) cancelPointer(); else if (selectedIndex !== null) { selectedIndex = null; selectionOutline(); } else void closeEditor(); return; }
  if ((event.key === 'Delete' || event.key === 'Backspace') && selectedIndex !== null && !busy) { event.preventDefault(); $('#delete-edit').click(); return; }
  if (mod && ['z', 'y', 's', 'c', 'o'].includes(key)) {
    event.preventDefault(); if (busy) return;
    if (key === 'z') $<HTMLButtonElement>(event.shiftKey ? '#redo-edit' : '#undo-edit').click();
    else if (key === 'y') $<HTMLButtonElement>('#redo-edit').click();
    else if (key === 'o') { if (!inplace()) void openImage(); } else void exportImage(key === 'c' ? 'copy' : event.shiftKey ? 'saveAs' : 'save');
  } else if (!mod && !event.altKey && !busy) { const next = ({ v: 'select', r: 'rectangle', a: 'arrow', t: 'text', p: 'pen', h: 'highlight', e: 'eraser', n: 'number', m: 'mosaic', b: 'solid', x: 'crop' } as Record<string, Tool>)[key]; if (next) chooseTool(next); }
});
clearGesture(); controls();
if (desktop) {
  // Register before the snapshot; monotonic session ids reject delayed delivery.
  void (async () => {
    await listen<IncomingSession | null>('screenshot-session', event => { void acceptSession(event.payload); });
    await listen<{ id: number }>('screenshot-session-cleared', event => {
      const id = event.payload.id;
      if (!Number.isSafeInteger(id)) return;
      latestId = Math.max(latestId, id); // Tombstone even a clear preceding startup replay.
      if (session?.id === id) void acceptSession(null);
    });
    await listen<{ sessionId: number; key: string }>('screenshot-overlay-key', event => {
      if (textFocusPending || !inplace() || event.payload.sessionId !== session?.id || composing || textOpen() || dialogOpen(discardDialog)
        || document.activeElement instanceof HTMLInputElement || document.activeElement instanceof HTMLTextAreaElement || document.activeElement instanceof HTMLSelectElement) return;
      if (event.payload.key === 'Enter') void exportImage('copy');
      else if (event.payload.key === 'Escape') { if (gesture || moveGesture) cancelPointer(); else if (selectedIndex !== null) { selectedIndex = null; selectionOutline(); } else void closeEditor(); }
    });
    await listen('screenshot-close-requested', () => { void closeEditor(); });
    const snapshot = await invoke<IncomingSession | null>('get_screenshot_session');
    if (snapshot) await acceptSession(snapshot);
  })().catch(error => status(`截图窗口初始化失败：${readableError(error)}`, true));
}

$('#zoom-menu').addEventListener('toggle', placeOverlayTools);
document.addEventListener('pointerdown', event => { const menu = $<HTMLDetailsElement>('#zoom-menu'); if (menu.open && event.target instanceof Node && !menu.contains(event.target)) menu.open = false; });

// Commit outside pointer interactions only once their click target is fixed.
// Committing on pointerdown can move the toolbar before pointerup and lose the
// intended Save/Close click. Keyboard-only focus changes still commit on blur.
let outsideTextPointer = false;
let outsideTextPoint: Point | null = null;
document.addEventListener('pointerdown', event => {
  outsideTextPointer = false; outsideTextPoint = null;
  if (!textOpen() || !(event.target instanceof Node) || textDialog.contains(event.target)) return;
  if (composing) { event.preventDefault(); event.stopImmediatePropagation(); textInput.focus(); return; }
  if (event.target instanceof Element && event.target.closest('.tool-options')) return;
  outsideTextPointer = true; outsideTextPoint = textPoint;
}, true);
document.addEventListener('click', event => {
  const sameEdit = outsideTextPointer && outsideTextPoint === textPoint;
  outsideTextPointer = false; outsideTextPoint = null;
  if (!textOpen() || !(event.target instanceof Node) || textDialog.contains(event.target)) return;
  if (composing) { event.preventDefault(); event.stopImmediatePropagation(); return; }
  if (!sameEdit) return; // The initiating canvas click must not commit the edit it just opened.
  if (event.target instanceof Element && event.target.closest('.tool-options')) return;
  if (!commitText()) { event.preventDefault(); event.stopImmediatePropagation(); }
}, true);
textInput.addEventListener('blur', () => {
  queueMicrotask(() => {
    if (!textOpen() || composing || outsideTextPointer || document.activeElement === textInput || document.activeElement?.closest('.tool-options')) return;
    commitText();
  });
});
document.addEventListener('pointercancel', () => {
  outsideTextPointer = false; outsideTextPoint = null;
  if (textOpen() && !composing && document.activeElement !== textInput) commitText();
});
