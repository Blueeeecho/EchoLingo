import './screenshot-editor.css';
import { overlayToolBounds, clampOverlayBox, placeOverlayToolbar, type OverlayRect } from './screenshot-overlay-layout';
import { closeDialog, dialogOpen, showDialog } from './screenshot-dialog';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { ScreenshotDocument, imagePoint, selectionRect, validateSize, MAX_ENCODED_BYTES, operationBounds, screenshotTextFont, translateOperation, type Point, type EditOperation, MAX_STROKE_POINTS, strokePathsIntersect } from './screenshot-model';
import { flattenedPng, renderScreenshot } from './screenshot-renderer';
interface ScreenshotOverlay { x: number; y: number; width: number; height: number; viewportWidth: number; viewportHeight: number; toolbarBounds?: OverlayRect }
interface ScreenshotSession { id: number; pngBase64: string; width: number; height: number; capturedAt: number; sourceName?: string; overlay?: ScreenshotOverlay; initialAction?: InitialAction }
type Tool = 'select' | 'rectangle' | 'arrow' | 'text' | 'mosaic' | 'solid' | 'crop' | 'number' | 'pen' | 'highlight' | 'eraser';
type InitialAction = Exclude<Tool, 'eraser'> | 'copy' | 'save' | 'pin';
const toolActions: readonly string[] = ['select', 'rectangle', 'arrow', 'text', 'number', 'pen', 'highlight', 'mosaic', 'solid', 'crop'];
const $ = <T extends Element = HTMLElement>(selector: string) => document.querySelector<T>(selector)!;
const canvas = $<HTMLCanvasElement>('#image-canvas'), frame = $('#canvas-frame'), workspace = $('#editor-workspace');
const textDialog = $<HTMLElement>('#text-dialog'), discardDialog = $<HTMLDialogElement>('#discard-dialog');
const textInput = $<HTMLTextAreaElement>('#annotation-text');
const desktop = isTauri(), windows = /Win/i.test(navigator.platform);
let session: Omit<ScreenshotSession, 'pngBase64'> | null = null, original: HTMLImageElement | null = null, model: ScreenshotDocument | null = null;
let latestId = -1, generation = 0, savedState: number | null = null, busy = false, nativeDialog = false, loading = false, tool: Tool = 'rectangle';
let rendered: { generation: number; stateId: number } | null = null;
let contextLost = false;
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
function status(message: string, error = false): void { $('#editor-status').textContent = message; $('#editor-status').hidden = !message; $('#editor-status').dataset.error = String(error); placeOverlayTools(); }
function readableError(error: unknown): string { return error instanceof Error ? error.message : String(error); }
function controls(): void {
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-image-action]')) button.disabled = !model || busy || loading;
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-export-action]')) button.disabled ||= !exportReady();
  $<HTMLButtonElement>('#undo-edit').disabled ||= !model?.canUndo;
  $<HTMLButtonElement>('#redo-edit').disabled ||= !model?.canRedo;
  $<HTMLButtonElement>('#open-image').disabled = busy || loading;
  $<HTMLButtonElement>('#close-editor').disabled = nativeDialog;
  $<HTMLButtonElement>('#overlay-cancel').disabled = busy || nativeDialog;
  $('#save-indicator').textContent = model ? dirty() ? '未保存' : '已保存' : '';
  $('#image-info').textContent = model ? `${model.size.width} × ${model.size.height} px` : loading ? '正在打开图片…' : '没有打开的图片';
  $('#overlay-info').textContent = model ? `${model.size.width} × ${model.size.height}` : '';
  document.title = `${dirty() ? '• ' : ''}截图 · EchoLingo`;
}
function applyZoom(): void {
  if (!model) return;
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
    renderScreenshot(canvas, original, model.original, model.operations);
    rendered = { generation, stateId: model.stateId }; frame.hidden = false;
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
function cancelText(): void { textDialog.hidden = true; textInput.value = ''; textPoint = null; editingIndex = null; composing = false; imeEscape = false; controls(); }
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
  const monitor = overlayToolBounds(innerWidth, innerHeight, session?.overlay?.toolbarBounds);
  textDialog.style.maxWidth = `${Math.max(1, monitor.width - 16)}px`;
  textDialog.style.maxHeight = `${Math.max(1, monitor.height - 16)}px`;
  const displaySize = Number($<HTMLSelectElement>('#edit-font-size').value) * r.width / model.size.width;
  textInput.style.font = screenshotTextFont(Math.max(8, displaySize));
  textInput.style.color = $<HTMLInputElement>('#edit-color').value;
  textInput.style.backgroundColor = $<HTMLSelectElement>('#note-style').value || 'var(--surface)';
  const box = clampOverlayBox(r.x + (textPoint.x - offset.x) * r.width / model.size.width,
    r.y + (textPoint.y - offset.y) * r.height / model.size.height, textDialog.offsetWidth, textDialog.offsetHeight,
    { x: monitor.x + 8, y: monitor.y + 8, width: Math.max(1, monitor.width - 16), height: Math.max(1, monitor.height - 16) });
  textDialog.style.left = `${box.x}px`; textDialog.style.top = `${box.y}px`;
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
  $('#text-count').textContent = `${textInput.value.length} / 2000`;
  textDialog.hidden = false; placeTextEditor(); controls(); textInput.focus();
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
async function acceptSession(value: ScreenshotSession | null): Promise<void> {
  if (value && (!Number.isSafeInteger(value.id) || value.id <= latestId)) return;
  if (value) latestId = value.id;
  const token = ++generation;
  if (decoding) { decoding.src = ''; decoding = null; } // Cancel superseded image decode work.
  clearGesture(); moveGesture = null; selectedIndex = null; cancelText(); resolveDiscard(false); textFocusPending = false; overlayFocus = null; busy = false; nativeDialog = false; loading = !!value;
  session = null; original = null; model = null; savedState = null; rendered = null;
  canvas.width = canvas.height = 1; frame.hidden = true; $('#empty-state').hidden = !!value; controls();
  if (!value) { setPresentation(); status('截图已取消。使用截图快捷键重新截图，或打开本地图片。'); return; }
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
  for (const button of document.querySelectorAll<HTMLButtonElement>('.editor-toolbar button[data-tool]')) button.setAttribute('aria-pressed', String(button.dataset.tool === tool));
  $('#text-size-label').hidden = next !== 'text' && next !== 'number';
  $('#note-style-label').hidden = next !== 'text'; $('#step-style-label').hidden = next !== 'number';
  $('#line-width-label').hidden = !['rectangle', 'arrow', 'number', 'pen', 'highlight'].includes(next);
  $('#shape-style-label').hidden = next !== 'rectangle'; $('#eraser-size-label').hidden = next !== 'eraser'; $('#mosaic-size-label').hidden = next !== 'mosaic';
  const hints: Record<Tool, string> = { select: '点击标注选择；拖动移动，双击文字修改，Delete 删除。', rectangle: '选择矩形或椭圆后拖动绘制。所有标注均以原图像素为准。', pen: '按住拖动自由绘制；松开后整笔可撤销。', highlight: '半透明高亮，不遮住原有文字；不要用于遮挡隐私。', eraser: '仅局部擦除画笔和高亮，不擦原图、马赛克或实心遮挡；其他标注用选择工具删除。', arrow: '从起点拖向终点，绘制箭头。', text: '点击原位添加文字；可选便签背景，双击已有文字修改。', number: '连续点击添加序号，或切换序号箭头后拖动；编号自动递增。', mosaic: '拖动选择马赛克区域。敏感文字建议使用实心遮挡。', solid: '拖动绘制不透明色块，彻底遮挡区域内的像素。', crop: '拖动选择保留范围；松开立即裁剪，可撤销。' };
  $('#tool-hint').textContent = hints[next]; canvas.dataset.tool = next; placeOverlayTools();
}
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
canvas.addEventListener('pointerdown', async event => {
  if (event.button !== 0 || busy || loading || !model ) return;
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
  gesture = { start, end: start, pointerId: event.pointerId, ...(['pen', 'highlight', 'eraser'].includes(tool) ? { points: [start] } : {}) }; canvas.setPointerCapture(event.pointerId); event.preventDefault();
});
canvas.addEventListener('pointermove', event => {
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
});
canvas.addEventListener('pointerup', event => {
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
});
canvas.addEventListener('contextlost', event => {
  event.preventDefault(); contextLost = true; moveGesture = null; clearGesture(false); rendered = null; frame.hidden = true; controls();
  status('图片画布已中断，已禁用贴图、复制和保存。正在等待画布恢复；也可以重新打开图片。', true);
});
canvas.addEventListener('contextrestored', () => { contextLost = false; if (render()) status('图片画布已恢复。'); });
function cancelPointer(): void {
  const moving = moveGesture; moveGesture = null;
  if (moving && canvas.hasPointerCapture(moving.pointerId)) canvas.releasePointerCapture(moving.pointerId);
  clearGesture(); if (moving) render();
}
canvas.addEventListener('pointercancel', cancelPointer); canvas.addEventListener('lostpointercapture', cancelPointer);
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
textInput.addEventListener('input', () => { $('#text-count').textContent = `${textInput.value.length} / 2000`; controls(); placeTextEditor(); });
$('#text-form').addEventListener('submit', event => { event.preventDefault(); if (commitText()) canvas.focus(); });
textInput.addEventListener('keydown', event => {
  if (event.isComposing || event.keyCode === 229 || composing) { if (event.key === 'Escape') imeEscape = true; return; }
  if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); if (imeEscape) { imeEscape = false; return; } cancelText(); canvas.focus(); }
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); if (commitText()) canvas.focus(); }
});
$('#cancel-text').addEventListener('click', () => { if (!composing) { cancelText(); canvas.focus(); } });
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
  if (!session || !model || busy || loading || gesture || moveGesture || !commitText()) return;
  if (!exportReady()) { status('当前图片尚未完整绘制，不能贴图、复制或保存。请撤销或重新打开图片。', true); return; }
  if (!desktop) { status('请在桌面应用中贴图、复制或保存图片。'); return; }
  clearGesture(); const token = generation, sessionId = session.id, state = model.stateId;
  busy = true; controls(); status(action === 'pin' ? '正在固定图片…' : action === 'copy' ? '正在复制图片…' : '正在准备保存…');
  try {
    const pngBase64 = await flattenedPng(canvas);
    if (token !== generation || session?.id !== sessionId || !exportReady() || model.stateId !== state) return;
    if (action === 'pin') {
      await invoke('pin_screenshot_image', { sessionId, pngBase64 });
      if (token === generation) {
        status('图片已固定到桌面；未保存文件，也未更改剪贴板。');
        if (inplace()) await dismissAfterExport(sessionId, token, '图片已固定到桌面');
      }
    }
    else if (action === 'copy') { await invoke('copy_screenshot_image', { sessionId, pngBase64 }); if (token === generation) { status('已复制合并后的图片。剪贴板不包含原图或编辑图层。'); if (inplace()) await dismissAfterExport(sessionId, token, '图片已复制到剪贴板'); } }
    else {
      nativeDialog = action === 'saveAs'; controls();
      const result = await invoke<{ path: string; fileName?: string } | null>('save_screenshot_image', { sessionId, pngBase64, saveAs: action === 'saveAs' });
      if (token !== generation) return;
      if (result) { savedState = state; status(`已保存：${result.path}`); if (inplace()) await dismissAfterExport(sessionId, token, `图片已保存：${result.path}`); } else status('已取消保存，图片和编辑内容仍保留。');
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
async function dismissOverlay(sessionId: number, token: number): Promise<void> {
  if (generation !== token || session?.id !== sessionId) return;
  if (desktop) await invoke('close_screenshot_editor', { sessionId });
  if (generation === token && session?.id === sessionId) await acceptSession(null);
}
async function dismissAfterExport(sessionId: number, token: number, completed: string): Promise<void> {
  try { await dismissOverlay(sessionId, token); }
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
    await listen<ScreenshotSession | null>('screenshot-session', event => { void acceptSession(event.payload); });
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
    const snapshot = await invoke<ScreenshotSession | null>('get_screenshot_session');
    if (snapshot) await acceptSession(snapshot);
  })().catch(error => status(`截图窗口初始化失败：${readableError(error)}`, true));
}
