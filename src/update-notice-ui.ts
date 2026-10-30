import { invoke } from '@tauri-apps/api/core';
import type { Settings } from './types';
import { RELEASES_PAGE, UpdateNotice, updateStatusText, type UpdateStatus } from './update-notice';

export function installUpdateNotice(options: {
  desktop: boolean;
  settings: () => Settings;
  ready: () => boolean;
  updateSettings: (mutator: (next: Settings) => void) => Promise<void>;
}): { refresh: () => void; dispose: () => void } {
  const check = document.querySelector<HTMLButtonElement>('#check-updates')!;
  const open = document.querySelector<HTMLButtonElement>('#open-update-page')!;
  const automatic = document.querySelector<HTMLInputElement>('#automatic-update-checks')!;
  const prereleases = document.querySelector<HTMLInputElement>('#include-prerelease-updates')!;
  const status = document.querySelector<HTMLElement>('#update-status')!;
  const badge = document.querySelector<HTMLElement>('#settings-update-badge')!;
  const more = document.querySelector<HTMLElement>('#more-toggle')!;
  let saving = false;
  let saveFailed = false;
  let preferences = '';
  let automaticTimer: ReturnType<typeof setTimeout> | undefined;
  let disposed = false;
  const notice = new UpdateNotice({
    read: () => invoke<UpdateStatus>('get_update_status'),
    check: (manual) => invoke<UpdateStatus>('check_for_updates', { manual }),
    open: () => invoke('open_service_link', { url: RELEASES_PAGE }),
    changed: render,
  });
  function render(): void {
    if (disposed) return;
    const settings = options.settings();
    automatic.checked = settings.automaticUpdateChecks === true;
    prereleases.checked = settings.includePrereleaseUpdates !== false;
    automatic.disabled = prereleases.disabled = saving || !options.ready() || !options.desktop;
    check.disabled = notice.checking || saving || !options.ready() || !options.desktop;
    check.textContent = notice.checking ? '正在检查…' : '检查更新';
    open.disabled = notice.opening || !options.desktop;
    status.textContent = !options.desktop ? '请在桌面应用中检查更新。' : saveFailed ? '更新偏好保存失败，请重试；原设置保持不变。'
      : notice.openFailed ? '无法打开默认浏览器，请稍后重试。' : updateStatusText(notice.status, notice.checking);
    const available = Boolean(notice.status?.available);
    badge.hidden = !available;
    more.dataset.updateAvailable = String(available);
  }
  function scheduleAutomatic(): void {
    if (automaticTimer) clearTimeout(automaticTimer);
    automaticTimer = undefined;
    if (disposed || saving || !options.desktop || !options.ready() || !options.settings().automaticUpdateChecks) return;
    automaticTimer = setTimeout(async () => {
      automaticTimer = undefined;
      if (disposed || saving || !options.settings().automaticUpdateChecks) return;
      await notice.check(false);
      // Waking from sleep is harmless: native persisted cadence permits at most
      // one attempt per day. Never reveal/focus a hidden window or show a toast.
      if (!disposed && options.settings().automaticUpdateChecks) {
        automaticTimer = setTimeout(scheduleAutomatic, 60 * 60 * 1000);
      }
    }, 15_000);
  }
  function refresh(): void {
    if (disposed) return;
    render();
    if (!options.desktop || !options.ready()) return;
    const settings = options.settings();
    const next = `${settings.automaticUpdateChecks === true}:${settings.includePrereleaseUpdates !== false}`;
    if (next === preferences) return;
    preferences = next;
    notice.invalidate();
    void notice.refresh(); // Local metadata only; no startup network request.
    scheduleAutomatic();
  }
  async function save(key: 'automaticUpdateChecks' | 'includePrereleaseUpdates', checked: boolean): Promise<void> {
    if (saving || !options.ready() || !options.desktop) { render(); return; }
    saving = true; saveFailed = false;
    if (automaticTimer) clearTimeout(automaticTimer);
    automaticTimer = undefined;
    render();
    // Immediately invalidate obsolete async results, but do not switch persisted
    // preferences until save succeeds. Failed saves cannot silently enable checks.
    notice.invalidate();
    try { await options.updateSettings((next) => { next[key] = checked; }); }
    catch { saveFailed = true; }
    finally { saving = false; refresh(); scheduleAutomatic(); void notice.refresh(); }
  }
  check.addEventListener('click', () => { if (!check.disabled) { saveFailed = false; void notice.check(true); } });
  open.addEventListener('click', () => { if (!open.disabled) { saveFailed = false; void notice.open(); } });
  automatic.addEventListener('change', () => { void save('automaticUpdateChecks', automatic.checked); });
  prereleases.addEventListener('change', () => { void save('includePrereleaseUpdates', prereleases.checked); });
  return {
    refresh,
    dispose: () => { disposed = true; if (automaticTimer) clearTimeout(automaticTimer); notice.dispose(); },
  };
}
