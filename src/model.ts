import type { HistoryEntry, Provider, Settings } from './types';

export const MAX_TEXT_LENGTH = 20_000;
export const LANGUAGES: ReadonlyArray<readonly [string, string]> = [
  ['auto', '自动检测'], ['zh-Hans', '简体中文'], ['en', 'English'], ['ja', '日本語'],
  ['ko', '한국어'], ['zh-Hant', '繁體中文'], ['fr', 'Français'], ['de', 'Deutsch'],
  ['es', 'Español'], ['ru', 'Русский'], ['pt', 'Português'], ['it', 'Italiano'],
];
export const SHORTCUT_LABELS = {
  selection: '划词翻译', capture: '截图翻译', ocr: '截图识别', silentOcr: '无感 OCR', input: '输入翻译',
} as const;
export const defaultSettings = (): Settings => ({
  providers: [], sourceLanguage: 'auto', targetLanguage: 'zh-Hans',
  shortcuts: { selection: 'Alt+D', capture: 'Alt+S', ocr: 'Alt+Shift+S', silentOcr: 'Alt+C', input: 'Alt+A' },
  saveHistory: true, theme: 'system', maxHistory: 200, autoHideSeconds: 0, ocrProviders: [], activeOcrProviderId: null,
});
export function filterHistory(entries: HistoryEntry[], query: string, favoritesOnly: boolean): HistoryEntry[] {
  const normalized = query.trim().toLocaleLowerCase();
  return entries.filter((entry) => (!favoritesOnly || entry.favorite) && (!normalized ||
    entry.text.toLocaleLowerCase().includes(normalized) ||
    entry.results.some((result) => result.text.toLocaleLowerCase().includes(normalized))));
}
export function languageName(code: string): string { return LANGUAGES.find(([value]) => value === code)?.[1] ?? code; }
export function errorMessage(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  return '操作失败，请稍后重试。';
}
export function validateProvider(provider: Provider): string | null {
  if (!provider.name.trim()) return '请输入服务名称。';
  let url: URL;
  try { url = new URL(provider.baseUrl); } catch { return '请输入完整的 API URL，例如 https://api.openai.com/v1。'; }
  const local = ['localhost', '127.0.0.1', '[::1]', '::1'].includes(url.hostname);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && local)) return '远程 API 必须使用 HTTPS；本机 localhost 服务可使用 HTTP。';
  if (url.username || url.password) return '请将密钥填写在 API 密钥字段中，不要放入 URL。';
  if (url.search || url.hash) return 'API Base URL 不能包含查询参数或片段。';
  if (provider.kind === 'openai' && !provider.model.trim()) return 'OpenAI 兼容服务需要填写模型名称。';
  return null;
}
export function normalizeTimestamp(value: number): number { return value < 1_000_000_000_000 ? value * 1000 : value; }
