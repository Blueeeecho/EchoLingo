export const RELEASES_PAGE = 'https://github.com/Blueeeecho/EchoLingo/releases';
export interface UpdateStatus {
  available: { version: string; prerelease: boolean } | null;
  checkedAt: number | null;
  failed: boolean;
}

/** Lifecycle state only: the native boundary owns networking, channel filtering,
 * persisted cadence and SemVer. Neither release HTML nor asset URLs enter the UI. */
export class UpdateNotice {
  status: UpdateStatus | null = null;
  checking = false;
  opening = false;
  openFailed = false;
  private revision = 0;
  private disposed = false;
  private pending: Promise<void> | null = null;
  constructor(private readonly actions: {
    read: () => Promise<UpdateStatus>;
    check: (manual: boolean) => Promise<UpdateStatus>;
    open: () => Promise<void>;
    changed: () => void;
  }) {}

  async refresh(): Promise<void> {
    if (this.disposed) return;
    const revision = ++this.revision;
    try {
      const status = await this.actions.read();
      if (this.disposed || revision !== this.revision) return;
      this.status = status;
      this.actions.changed();
    } catch { /* Cached notices are best effort; never interrupt translation. */ }
  }

  invalidate(): void {
    if (this.disposed) return;
    ++this.revision;
    this.status = null;
    this.openFailed = false;
    this.actions.changed();
  }

  check(manual: boolean): Promise<void> {
    if (this.disposed) return Promise.resolve();
    if (this.pending) return this.pending;
    const revision = ++this.revision;
    this.checking = true;
    this.openFailed = false;
    this.actions.changed();
    // Schedule the action after pending is assigned, including synchronous failures.
    this.pending = Promise.resolve().then(() => {
      if (this.disposed || revision !== this.revision) return null;
      return this.actions.check(manual);
    }).then((status) => {
      if (status && !this.disposed && revision === this.revision) this.status = status;
    }).catch(() => {
      if (!this.disposed && revision === this.revision) {
        this.status = { available: this.status?.available ?? null, checkedAt: this.status?.checkedAt ?? null, failed: true };
      }
    }).finally(() => {
      this.pending = null;
      this.checking = false;
      if (!this.disposed) this.actions.changed();
    });
    return this.pending;
  }

  async open(): Promise<void> {
    if (this.disposed || this.opening) return;
    this.opening = true;
    this.openFailed = false;
    this.actions.changed();
    const revision = this.revision;
    try { await this.actions.open(); }
    catch { if (revision === this.revision) this.openFailed = true; }
    finally { this.opening = false; if (!this.disposed) this.actions.changed(); }
  }

  dispose(): void { this.disposed = true; ++this.revision; }
}

export function updateStatusText(status: UpdateStatus | null, checking: boolean): string {
  if (checking) return '正在检查更新…';
  const notice = status?.available;
  if (notice) return `发现新版本 ${notice.version}${notice.prerelease ? '（内测版）' : ''}${status.failed ? ' · 暂时无法联网，显示上次检查结果' : ''}。可打开下载页手动安装。`;
  if (status?.failed) return '暂时无法检查更新，请稍后重试；不影响翻译。';
  if (status?.checkedAt !== null && status?.checkedAt !== undefined) return '所选版本通道暂无新版本。';
  return '尚未检查更新。只提示新版本，不会自动下载或安装。';
}
