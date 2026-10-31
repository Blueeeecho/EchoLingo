import { invoke } from '@tauri-apps/api/core';
import type { Settings } from './types';
interface ScreenshotDirectory { path: string; isDefault: boolean }
interface Context { desktop: boolean; settings(): Settings; ready(): boolean; updateSettings(mutator: (next: Settings) => void): Promise<void>; action(): Promise<void> }
/** Only narrowly scoped native dialogs; the webview never receives filesystem
 * read/write privileges. Image bytes never enter generic settings. */
export function installScreenshotSettings(context: Context) {
  const root = document.querySelector<HTMLElement>('#screenshot-settings')!;
  const folder = root.querySelector<HTMLElement>('#screenshot-folder')!, feedback = root.querySelector<HTMLElement>('#screenshot-settings-status')!;
  let busy = false, directory: ScreenshotDirectory | null = null, lastSetting: string | undefined;
  const buttons = [...root.querySelectorAll<HTMLButtonElement>('button')];
  const controls = () => { for (const button of buttons) button.disabled = busy || !context.ready(); };
  const showFolder = () => { folder.textContent = directory ? `${directory.isDefault ? '桌面（默认） · ' : ''}${directory.path}` : context.settings().screenshotSaveDirectory || '桌面（默认）'; };
  async function run(action: () => Promise<void>) {
    if (busy || !context.ready()) return;
    if (!context.desktop) { feedback.textContent = '请在桌面应用中使用截图或选择文件夹。'; return; }
    busy = true; controls(); feedback.textContent = '';
    try { await action(); } catch (error) { feedback.textContent = `未完成操作：${error instanceof Error ? error.message : String(error)}`; }
    finally { busy = false; controls(); }
  }
  root.querySelector('#screenshot-choose-folder')!.addEventListener('click', () => void run(async () => {
    const result = await invoke<ScreenshotDirectory | null>('choose_screenshot_directory');
    if (!result) { feedback.textContent = '已取消，保存位置未改变。'; return; }
    directory = result;
    // Queue the selected directory with the rest of the settings writes too:
    // another in-flight preference save must not restore a stale directory.
    await context.updateSettings(next => { next.screenshotSaveDirectory = result.isDefault ? '' : result.path; });
    showFolder(); feedback.textContent = '截图保存位置已更新。不会自动保存截图。';
  }));
  root.querySelector('#screenshot-reset-folder')!.addEventListener('click', () => void run(async () => {
    directory = await invoke<ScreenshotDirectory>('reset_screenshot_directory');
    await context.updateSettings(next => { next.screenshotSaveDirectory = ''; }); showFolder(); feedback.textContent = '已恢复为系统桌面。';
  }));
  root.querySelector('#screenshot-start')!.addEventListener('click', () => void run(context.action));
  root.querySelector('#screenshot-open-local')!.addEventListener('click', () => void run(async () => { await invoke('open_screenshot_image', { sessionId: null }); }));
  return { refresh() {
    controls(); showFolder();
    const setting = context.settings().screenshotSaveDirectory ?? '';
    if (context.desktop && context.ready() && setting !== lastSetting) {
      lastSetting = setting;
      void invoke<ScreenshotDirectory>('get_screenshot_directory').then(value => { if (lastSetting === setting) { directory = value; showFolder(); } }).catch(() => {});
    }
  } };
}
