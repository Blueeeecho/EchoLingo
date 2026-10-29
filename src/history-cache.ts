import type { HistoryEntry } from './types';

// History is a management-view concern, not startup/translation work. Keep one
// fetch in flight and a revision so mutations cannot be erased by an old read.
export class HistoryCache {
  private revision = 0;
  private loadedRevision = -1;
  private pending: Promise<void> | null = null;
  private snapshot: HistoryEntry[] = [];

  constructor(
    private readonly fetchEntries: () => Promise<HistoryEntry[]>,
    private readonly isVisible: () => boolean,
    private readonly render: () => void,
  ) {}

  get entries(): HistoryEntry[] { return this.snapshot; }

  async load(): Promise<void> {
    if (!this.isVisible()) return;
    if (this.pending) {
      await this.pending;
      // A mutation may arrive after the loader's last revision check but
      // before its promise settles. Do not lose that final refresh request.
      if (this.isVisible() && this.loadedRevision !== this.revision) await this.load();
      return;
    }
    this.pending = (async () => {
      while (this.isVisible() && this.loadedRevision !== this.revision) {
        const revision = this.revision;
        const entries = await this.fetchEntries();
        if (revision !== this.revision) continue;
        this.snapshot = entries;
        this.loadedRevision = revision;
      }
      if (this.isVisible()) this.render();
    })().finally(() => { this.pending = null; });
    return this.pending;
  }

  async refresh(): Promise<void> {
    this.revision += 1;
    await this.load();
  }
}
