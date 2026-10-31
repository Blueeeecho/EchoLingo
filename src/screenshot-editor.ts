import './screenshot-editor.css';
import { overlayToolBounds, clampOverlayBox, placeOverlayToolbar, type OverlayRect } from './screenshot-overlay-layout';
import { closeDialog, dialogOpen, showDialog } from './screenshot-dialog';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { ScreenshotDocument, imagePoint, selectionRect, validateSize, MAX_ENCODED_BYTES, type Point, type EditOperation } from './screenshot-model';
import { flattenedPng, renderScreenshot } from './screenshot-renderer';
interface ScreenshotOverlay { x: number; y: number; width: number; height: number; viewportWidth: number; viewportHeight: number; toolbarBounds?: OverlayRect }
interface ScreenshotSession { id: number; pngBase64: string; width: number; height: number; capturedAt: number; sourceName?: string; overlay?: ScreenshotOverlay }
type Tool = 'select' | 'rectangle' | 'arrow' | 'text' | 'mosaic' | 'solid' | 'crop';
const $ = <T extends Element = HTMLElement>(selector: string) => document.querySelector<T>(selector)!;
const canvas = $<HTMLCanvasElement>('#image-canvas'), frame = $('#canvas-frame'), workspace = $('#editor-workspace');
const textDialog = $<HTMLDialogElement>('#text-dialog'), discardDialog = $<HTMLDialogElement>('#discard-dialog');
const textInput = $<HTMLTextAreaElement>('#annotation-text');
const desktop = isTauri();
let session: Omit<ScreenshotSession, 'pngBase64'> | null = null, original: HTMLImageElement | null = null, model: ScreenshotDocument | null = null;
let latestId = -1, generation = 0, savedState: number | null = null, busy = false, nativeDialog = false, loading = false, tool: Tool = 'rectangle';
let rendered: { generation: number; stateId: number } | null = null;
const inplace = () => !!session?.overlay;
const exportReady = () => !!model && rendered?.generation === generation && rendered.stateId === model.stateId;
let decoding: HTMLImageElement | null = null;
let textFocusPending = false;
let zoom = 1, fit = true, composing = false, imeEscape = false, textPoint: Point | null = null;
let gesture: { start: Point; end: Point; pointerId: number } | null = null;
let discardResolve: ((value: boolean) => void) | null = null;
const dirty = () => model !== null && savedState !== model.stateId;
function status(message: string, error = false): void { $('#editor-status').textContent = message; $('#editor-status').dataset.error = String(error); placeOverlayTools(); }
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
  if (fit) zoom = Math.min(1, Math.max(0.01, Math.min((workspace.clientWidth - 56) / width, (workspace.clientHeight - 56) / height)));
  frame.style.width = `${width * zoom}px`; frame.style.height = `${height * zoom}px`;
  $('#zoom-level').textContent = `${Math.round(zoom * 100)}%`;
  $('#gesture-preview').setAttribute('viewBox', `0 0 ${width} ${height}`);
}
let placementFrame = 0;
function placeOverlayTools(): void {
  if (!inplace() || placementFrame) return;
  placementFrame = requestAnimationFrame(() => { placementFrame = 0; layoutOverlayTools(); });
}
function layoutOverlayTools(): void {
  if (!inplace()) return;
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
  if (!model || !original) return false;
  try {
    renderScreenshot(canvas, original, model.original, model.operations);
    rendered = { generation, stateId: model.stateId }; frame.hidden = false;
    applyZoom(); controls(); return true;
  } catch (error) {
    frame.hidden = true; canvas.width = canvas.height = 1; controls();
    status(`图片绘制失败，已禁用复制和保存。请撤销本次编辑，或重新打开图片：${readableError(error)}`, true);
    return false;
  }
}
function clearGesture(): void {
  if (gesture && canvas.hasPointerCapture(gesture.pointerId)) canvas.releasePointerCapture(gesture.pointerId);
  gesture = null; $('#gesture-rect').setAttribute('visibility', 'hidden'); $('#gesture-line').setAttribute('visibility', 'hidden');
}
function cancelText(): void { closeDialog(textDialog); textInput.value = ''; textPoint = null; composing = false; imeEscape = false; }
function resolveDiscard(value: boolean): void { closeDialog(discardDialog); const resolve = discardResolve; discardResolve = null; resolve?.(value); }
async function confirmDiscard(action: 'open' | 'close'): Promise<boolean> {
  if (!dirty()) return true;
  if (discardResolve) return false;
  $('#discard-description').textContent = action === 'close' ? '关闭后，本次图片和编辑内容将被丢弃。不会自动保存。' : '打开新图片会替换当前图片。取消文件选择时，当前图片仍会保留。';
  $('#discard-confirm').textContent = action === 'close' ? '丢弃并关闭' : '继续打开';
  showDialog(discardDialog); $<HTMLButtonElement>('#discard-cancel').focus();
  return new Promise(resolve => { discardResolve = resolve; });
}
async function acceptSession(value: ScreenshotSession | null): Promise<void> {
  if (value && (!Number.isSafeInteger(value.id) || value.id <= latestId)) return;
  if (value) latestId = value.id;
  const replaced = dirty(), token = ++generation;
  if (decoding) { decoding.src = ''; decoding = null; } // Cancel superseded image decode work.
  clearGesture(); cancelText(); resolveDiscard(false); textFocusPending = false; busy = false; nativeDialog = false; loading = !!value;
  session = null; original = null; model = null; savedState = null; rendered = null;
  canvas.width = canvas.height = 1; frame.hidden = true; $('#empty-state').hidden = !!value; controls();
  if (!value) { setPresentation(); status('截图已取消。使用截图快捷键重新截图，或打开本地图片。'); return; }
  const { pngBase64, ...metadata } = value; session = metadata; setPresentation(value.overlay); chooseTool(value.overlay ? 'select' : 'rectangle');
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
    if (drawn) status(value.overlay ? '✓ / Enter 复制并完成 · × / Esc 取消 · ↓ 保存到截图目录' : replaced ? '已打开新图片；上一张未保存的编辑已丢弃。图片仅在点击保存后写入文件。' : '仅在本机编辑，不识别文字、不上传图片。保存为合并后的 PNG；复制为合并后的图片。');
    if (desktop) await invoke('screenshot_editor_ready', { sessionId: value.id });
  } catch (error) {
    if (token !== generation) return;
    decoding = null; loading = false; model = null; original = null; frame.hidden = true; $('#empty-state').hidden = false;
    status(`无法打开图片：${readableError(error)}`, true); controls();
    // Show a prepared error state too, rather than leave an invisible window.
    if (desktop) await invoke('screenshot_editor_ready', { sessionId: value.id }).catch(() => {});
  }
}
function chooseTool(next: Tool): void {
  clearGesture(); tool = next;
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-tool]')) button.setAttribute('aria-pressed', String(button.dataset.tool === tool));
  $('#text-size-label').hidden = next !== 'text'; $('#mosaic-size-label').hidden = next !== 'mosaic';
  const hints: Record<Tool, string> = { select: '选择工具进行标注，或点击 ✓ 复制并完成。', rectangle: '拖动绘制矩形。所有标注均以原始图片像素为准。', arrow: '从起点拖向终点，绘制箭头。', text: '点击图片放置文字；支持中文输入法和多行文字。', mosaic: '拖动选择马赛克区域。敏感文字建议使用实心遮挡。', solid: '拖动绘制不透明色块，彻底遮挡区域内的像素。', crop: '拖动选择保留范围；松开立即裁剪，可撤销。' };
  $('#tool-hint').textContent = hints[next]; canvas.dataset.tool = next; placeOverlayTools();
}
function point(event: PointerEvent): Point { const r = canvas.getBoundingClientRect(); return imagePoint({ x: event.clientX, y: event.clientY }, { x: r.x, y: r.y, width: r.width, height: r.height }, model!.size); }
function append(operation: EditOperation): void {
  try { model?.append(operation); if (render()) status(operation.kind === 'crop' ? '已裁剪实际像素。可撤销；导出不会包含裁剪掉的部分。' : '标注已添加。尚未写入文件。'); }
  catch (error) { status(readableError(error), true); }
}
canvas.addEventListener('pointerdown', async event => {
  if (event.button !== 0 || busy || loading || !model || tool === 'select') return;
  const start = point(event); canvas.focus({ preventScroll: true });
  if (tool === 'text') {
    const token = generation;
    if (desktop && inplace()) {
      textFocusPending = true;
      try { await invoke('focus_screenshot_overlay', { sessionId: session?.id }); }
      catch (error) { if (token === generation) status(`无法输入标注：${readableError(error)}`, true); return; }
      finally { if (token === generation) textFocusPending = false; }
      if (token !== generation || busy || !model || tool !== 'text') return;
    }
    textPoint = { x: Math.min(model.size.width - 1, Math.floor(start.x)), y: Math.min(model.size.height - 1, Math.floor(start.y)) };
    textInput.value = ''; $('#text-count').textContent = '0 / 2000'; showDialog(textDialog); textInput.focus(); return;
  }
  gesture = { start, end: start, pointerId: event.pointerId }; canvas.setPointerCapture(event.pointerId); event.preventDefault();
});
canvas.addEventListener('pointermove', event => {
  if (!gesture || !model || gesture.pointerId !== event.pointerId) return;
  gesture.end = point(event);
  if (tool === 'arrow') {
    const line = $('#gesture-line'); line.setAttribute('visibility', 'visible');
    for (const [key, value] of Object.entries({ x1: gesture.start.x, y1: gesture.start.y, x2: gesture.end.x, y2: gesture.end.y })) line.setAttribute(key, String(value));
  } else {
    const rect = selectionRect(gesture.start, gesture.end, model.size), preview = $('#gesture-rect'); preview.setAttribute('visibility', 'visible');
    for (const [key, value] of Object.entries(rect)) preview.setAttribute(key, String(value));
  }
});
canvas.addEventListener('pointerup', event => {
  if (!gesture || !model || gesture.pointerId !== event.pointerId) return;
  const { start } = gesture, end = point(event); clearGesture();
  if (Math.hypot(end.x - start.x, end.y - start.y) < 1) return;
  const rect = selectionRect(start, end, model.size), color = $<HTMLInputElement>('#edit-color').value, width = Number($<HTMLSelectElement>('#edit-width').value);
  if (tool === 'arrow') append({ kind: 'arrow', start, end, color, width });
  else if (rect.width && rect.height) {
    if (tool === 'crop') append({ kind: 'crop', rect });
    else if (tool === 'mosaic') append({ kind: 'mosaic', rect, blockSize: Number($<HTMLSelectElement>('#edit-block-size').value) });
    else append({ kind: 'rectangle', rect, color, width, solid: tool === 'solid' });
  }
});
canvas.addEventListener('contextlost', event => {
  event.preventDefault(); rendered = null; clearGesture(); frame.hidden = true; controls();
  status('图片画布已中断，已禁用复制和保存。正在等待画布恢复；也可以重新打开图片。', true);
});
canvas.addEventListener('contextrestored', () => { if (render()) status('图片画布已恢复。'); });
canvas.addEventListener('pointercancel', clearGesture); canvas.addEventListener('lostpointercapture', clearGesture);
for (const button of document.querySelectorAll<HTMLButtonElement>('[data-tool]')) button.addEventListener('click', () => chooseTool(button.dataset.tool as Tool));
textInput.addEventListener('compositionstart', () => { composing = true; }); textInput.addEventListener('compositionend', () => { composing = false; });
textInput.addEventListener('input', () => { $('#text-count').textContent = `${textInput.value.length} / 2000`; });
$('#text-form').addEventListener('submit', event => {
  event.preventDefault(); if (composing || !model || !textPoint || !textInput.value.trim()) return;
  const operation: EditOperation = { kind: 'text', point: textPoint, text: textInput.value, color: $<HTMLInputElement>('#edit-color').value,
    size: Number($<HTMLSelectElement>('#edit-font-size').value), maxWidth: Math.max(1, model.size.width - textPoint.x) };
  cancelText(); append(operation);
});
textInput.addEventListener('keydown', event => {
  imeEscape = event.key === 'Escape' && (composing || event.isComposing || event.keyCode === 229);
  if (imeEscape) { event.preventDefault(); return; }
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter' && !event.isComposing && event.keyCode !== 229 && !composing) { event.preventDefault(); $<HTMLButtonElement>('#apply-text').click(); } });
$('#cancel-text').addEventListener('click', cancelText); textDialog.addEventListener('cancel', event => { event.preventDefault(); if (composing || imeEscape) { imeEscape = false; return; } cancelText(); });
$('#discard-cancel').addEventListener('click', () => resolveDiscard(false)); $('#discard-confirm').addEventListener('click', () => resolveDiscard(true));
discardDialog.addEventListener('cancel', event => { event.preventDefault(); resolveDiscard(false); });
$('#undo-edit').addEventListener('click', () => { if (!busy && model?.undo()) { clearGesture(); if (render()) status('已撤销。'); } });
$('#redo-edit').addEventListener('click', () => { if (!busy && model?.redo()) { clearGesture(); if (render()) status('已重做。'); } });
function changeZoom(value: number): void { fit = false; zoom = Math.max(0.05, Math.min(4, value)); applyZoom(); }
$('#zoom-in').addEventListener('click', () => changeZoom(zoom * 1.25)); $('#zoom-out').addEventListener('click', () => changeZoom(zoom / 1.25));
$('#zoom-actual').addEventListener('click', () => changeZoom(1)); $('#zoom-fit').addEventListener('click', () => { fit = true; applyZoom(); });
new ResizeObserver(() => { if (fit || inplace()) applyZoom(); }).observe(workspace);
new ResizeObserver(placeOverlayTools).observe($('.editor-toolbar'));
async function exportImage(action: 'copy' | 'save' | 'saveAs'): Promise<void> {
  if (action === 'saveAs' && inplace()) {
    status('原地截图使用设置中的保存目录；请在设置修改目录'); return;
  }
  if (!session || !model || busy || loading) return;
  if (!exportReady()) { status('当前图片尚未完整绘制，不能复制或保存。请撤销或重新打开图片。', true); return; }
  if (!desktop) { status('请在桌面应用中复制或保存图片。'); return; }
  clearGesture(); const token = generation, sessionId = session.id, state = model.stateId;
  busy = true; controls(); status(action === 'copy' ? '正在复制图片…' : '正在准备保存…');
  try {
    const pngBase64 = await flattenedPng(canvas);
    if (token !== generation || session?.id !== sessionId || !exportReady() || model.stateId !== state) return;
    if (action === 'copy') { await invoke('copy_screenshot_image', { sessionId, pngBase64 }); if (token === generation) { status('已复制合并后的图片。剪贴板不包含原图或编辑图层。'); if (inplace()) await dismissAfterExport(sessionId, token, '图片已复制到剪贴板'); } }
    else {
      nativeDialog = action === 'saveAs'; controls();
      const result = await invoke<{ path: string; fileName?: string } | null>('save_screenshot_image', { sessionId, pngBase64, saveAs: action === 'saveAs' });
      if (token !== generation) return;
      if (result) { savedState = state; status(`已保存：${result.path}`); if (inplace()) await dismissAfterExport(sessionId, token, `图片已保存：${result.path}`); } else status('已取消保存，图片和编辑内容仍保留。');
    }
  } catch (error) { if (token === generation) status(`未完成${action === 'copy' ? '复制' : '保存'}：${readableError(error)}`, true); }
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
    if (token === generation) status(`${completed}；退出失败，请点击 × 关闭，无需再次复制或保存：${readableError(error)}`, true);
  }
}
async function closeEditor(): Promise<void> {
  // Keep an owned native sheet visible. Plain export/copy can finish after a
  // confirmed close only if the backend has already committed the explicit act.
  if (nativeDialog) { status('请先完成或取消当前文件对话框，再关闭编辑器。'); return; }
  const token = generation;
  if (inplace()) {
    if (busy) return; // Never race a committed clipboard/file export with discard.
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
$('#overlay-copy').addEventListener('click', () => void exportImage('copy'));
$('#overlay-save').addEventListener('click', () => void exportImage('save'));
$('#overlay-cancel').addEventListener('click', () => void closeEditor());
$('#open-image').addEventListener('click', () => void openImage()); $('#close-editor').addEventListener('click', () => void closeEditor());
$('#copy-image').addEventListener('click', () => void exportImage('copy')); $('#save-image').addEventListener('click', () => void exportImage('save')); $('#save-as-image').addEventListener('click', () => void exportImage('saveAs'));
document.addEventListener('keydown', event => {
  if (textFocusPending || event.isComposing || event.keyCode === 229 || composing || dialogOpen(textDialog) || dialogOpen(discardDialog)) return;
  if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement || event.target instanceof HTMLSelectElement) return;
  const mod = event.ctrlKey || event.metaKey, key = event.key.toLowerCase();
  if (event.key === 'Enter' && inplace() && !mod && !event.altKey && !event.shiftKey) { event.preventDefault(); if (!event.repeat) void exportImage('copy'); return; }
  if (event.key === 'Escape') { event.preventDefault(); if (gesture) clearGesture(); else void closeEditor(); return; }
  if (mod && ['z', 'y', 's', 'c', 'o'].includes(key)) {
    event.preventDefault(); if (busy) return;
    if (key === 'z') $<HTMLButtonElement>(event.shiftKey ? '#redo-edit' : '#undo-edit').click();
    else if (key === 'y') $<HTMLButtonElement>('#redo-edit').click();
    else if (key === 'o') { if (!inplace()) void openImage(); } else void exportImage(key === 'c' ? 'copy' : event.shiftKey ? 'saveAs' : 'save');
  } else if (!mod && !event.altKey && !busy) { const next = ({ v: 'select', r: 'rectangle', a: 'arrow', t: 'text', m: 'mosaic', b: 'solid', x: 'crop' } as Record<string, Tool>)[key]; if (next) chooseTool(next); }
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
      if (textFocusPending || !inplace() || event.payload.sessionId !== session?.id || composing || dialogOpen(textDialog) || dialogOpen(discardDialog)
        || document.activeElement instanceof HTMLInputElement || document.activeElement instanceof HTMLTextAreaElement || document.activeElement instanceof HTMLSelectElement) return;
      if (event.payload.key === 'Enter') void exportImage('copy');
      else if (event.payload.key === 'Escape') { if (gesture) clearGesture(); else void closeEditor(); }
    });
    await listen('screenshot-close-requested', () => { void closeEditor(); });
    const snapshot = await invoke<ScreenshotSession | null>('get_screenshot_session');
    if (snapshot) await acceptSession(snapshot);
  })().catch(error => status(`截图窗口初始化失败：${readableError(error)}`, true));
}
