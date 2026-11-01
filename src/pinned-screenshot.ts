import './pinned-screenshot.css';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { validateSize, MAX_ENCODED_BYTES } from './screenshot-model';

interface PinnedImage { pngBase64: string; width: number; height: number }
const image = document.querySelector<HTMLImageElement>('#pinned-image')!;
const toggle = document.querySelector<HTMLButtonElement>('#toggle-pin')!;
const close = document.querySelector<HTMLButtonElement>('#close-pin')!;
const status = document.querySelector<HTMLElement>('#pin-status')!;
let pinned = true, busy = false, closing = false;
const errorText = (error: unknown) => error instanceof Error ? error.message : String(error);

toggle.addEventListener('click', async () => {
  if (busy || closing) return;
  busy = true; toggle.disabled = true;
  try {
    await invoke('set_screenshot_pinned', { pinned: !pinned });
    pinned = !pinned;
    toggle.setAttribute('aria-pressed', String(pinned));
    toggle.setAttribute('aria-label', pinned ? '取消置顶' : '置顶贴图');
    toggle.title = pinned ? '取消置顶（图片仍会保留）' : '固定在其他窗口上方';
    status.textContent = ''; status.hidden = true;
  } catch (error) { status.hidden = false; status.textContent = `无法修改置顶状态：${errorText(error)}`; }
  finally { busy = false; toggle.disabled = closing; }
});
close.addEventListener('click', async () => {
  if (closing) return;
  closing = true; close.disabled = toggle.disabled = true;
  try { await invoke('close_pinned_screenshot'); image.removeAttribute('src'); }
  catch (error) {
    closing = false; close.disabled = false; toggle.disabled = busy;
    status.hidden = false; status.textContent = `无法关闭贴图：${errorText(error)}`;
  }
});
window.addEventListener('pagehide', () => { image.removeAttribute('src'); });
void (async () => {
  if (!isTauri()) { status.textContent = '请在桌面应用中使用贴图。'; return; }
  try {
    const value = await invoke<PinnedImage>('get_pinned_screenshot');
    validateSize(value);
    if (!value.pngBase64?.startsWith('iVBORw0KGgo') || value.pngBase64.length > Math.ceil(MAX_ENCODED_BYTES / 3) * 4) throw new Error('贴图数据无效');
    image.src = `data:image/png;base64,${value.pngBase64}`;
    value.pngBase64 = ''; // Do not retain a second encoded copy after delivery.
    await image.decode();
    if (image.naturalWidth !== value.width || image.naturalHeight !== value.height) throw new Error('贴图尺寸不一致');
    image.hidden = false;
    status.textContent = ''; status.hidden = true;
    // A hidden native WebView can throttle animation frames: decoded pixels
    // and prepared DOM, not a pre-show requestAnimationFrame, gate the handoff.
    await invoke('pinned_screenshot_ready', { success: true });
    toggle.disabled = closing;
  } catch (error) {
    image.hidden = true; image.removeAttribute('src');
    status.hidden = false; status.textContent = `无法打开贴图：${errorText(error)}`;
    await invoke('pinned_screenshot_ready', { success: false }).catch(() => {});
  }
})();

// Only image/background drags move the frameless native window. The two
// controls and resize edges have independent hit targets and never initiate drag.
document.querySelector('main')!.addEventListener('pointerdown', event => {
  if (!(event instanceof PointerEvent) || event.button !== 0 || closing || image.hidden || !isTauri()) return;
  event.preventDefault();
  void invoke('start_pinned_screenshot_drag').catch(error => { status.hidden = false; status.textContent = `无法移动贴图：${errorText(error)}`; });
});
document.querySelector('#resize-edges')!.addEventListener('pointerdown', event => {
  if (!(event instanceof PointerEvent) || event.button !== 0 || closing || !isTauri()) return;
  const direction = (event.target as HTMLElement).dataset.direction;
  if (!direction) return;
  event.preventDefault(); event.stopPropagation();
  void invoke('resize_pinned_screenshot', { direction: direction.toLowerCase() }).catch(error => { status.hidden = false; status.textContent = `无法调整贴图大小：${errorText(error)}`; });
});
