import type { HistoryEntry, Provider, Settings } from './types';
import { isNativeTranslation, TRANSLATION_NATIVE_URLS } from './translation-credentials';

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
  providers: [], sourceLanguage: 'auto', targetLanguage: 'auto', languageDirectionVersion: 1,
  shortcutDefaultsVersion: 2,
  windowsSelectionStrategy: 'copy',
  automaticUpdateChecks: false, includePrereleaseUpdates: true,
  shortcuts: { selection: 'Alt+D', capture: '', ocr: '', silentOcr: 'Alt+S', input: '' },
  saveHistory: true, theme: 'system', maxHistory: 20, autoHideSeconds: 0, ocrProviders: [], activeOcrProviderId: null,
});
export function filterHistory(entries: HistoryEntry[], query: string, favoritesOnly: boolean): HistoryEntry[] {
  const normalized = query.trim().toLocaleLowerCase();
  return entries.filter((entry) => (!favoritesOnly || entry.favorite) && (!normalized ||
    entry.text.toLocaleLowerCase().includes(normalized) ||
    entry.results.some((result) => result.text.toLocaleLowerCase().includes(normalized))));
}
export function languageName(code: string): string { return LANGUAGES.find(([value]) => value === code)?.[1] ?? code; }
// Native automatic detection supports more languages than the short picker.
// Preserve its validated failed pair when opening preparation, never silently
// leave the starter English/Chinese pair selected instead.
export function systemTranslationSetupPair(value: unknown): { sourceLanguage: string; targetLanguage: string } | null {
  if (!value || typeof value !== 'object') return null;
  const pair = value as Record<string, unknown>;
  const valid = (code: unknown): code is string => typeof code === 'string' && code !== 'auto'
    && /^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8}){0,3}$/.test(code)
    && 'am ar hy bn bg my ca chr hr cs da nl en fi fr ka de el gu he hi hu is id it ja kn kk km ko lo ms ml mr mn no nb or ps fa pl pt pa ro ru sr si sk sl es sv ta te th bo tr uk ur vi zh'.split(' ').includes(code.split('-')[0].toLowerCase());
  return valid(pair.sourceLanguage) && valid(pair.targetLanguage) && pair.sourceLanguage !== pair.targetLanguage
    ? { sourceLanguage: pair.sourceLanguage, targetLanguage: pair.targetLanguage } : null;
}
export function errorMessage(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  return '操作失败，请稍后重试。';
}
export function userFacingError(error: unknown): string {
  if (/^SELECTION_UNAVAILABLE:/i.test(errorMessage(error).trim())) return '当前应用未提供可验证的选区。请先按 ⌘C，再使用菜单栏的“翻译剪贴板”或浮窗更多里的“剪贴板翻译”；也可使用截图识别。';
  if (/^COPY_NO_UPDATE:/i.test(errorMessage(error).trim())) return '已发送复制快捷键，但目标应用没有及时更新剪贴板。请在原应用选中文字后手动按 Ctrl+C 验证，或使用截图识别。';
  return errorMessage(error).replace(/^(?:SYSTEM_TRANSLATION_[A-Z_]+|NATIVE_[A-Z_]+|CAPTURE(?:_[A-Z_]+)?):\s*/, '');
}
export function isLocalProvider(kind: string): boolean { return kind === 'system' || kind === 'offline'; }
export function validateProvider(provider: Provider): string | null {
  if (!provider.name.trim()) return '请输入服务名称。';
  if (isLocalProvider(provider.kind)) {
    if (provider.baseUrl || provider.model || provider.prompt || provider.region || provider.hasKey) return '本机翻译不使用 API 地址、模型、提示词或密钥。';
    return null;
  }
  let url: URL;
  try { url = new URL(provider.baseUrl); } catch { return '请输入完整的 API URL，例如 https://api.openai.com/v1。'; }
  const local = ['localhost', '127.0.0.1', '[::1]', '::1'].includes(url.hostname);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && local)) return '远程 API 必须使用 HTTPS；本机 localhost 服务可使用 HTTP。';
  if (url.username || url.password) return '请将密钥填写在 API 密钥字段中，不要放入 URL。';
  if (url.search || url.hash) return 'API Base URL 不能包含查询参数或片段。';
  if (isNativeTranslation(provider.kind)) {
    if (provider.baseUrl.replace(/\/+$/, '') !== TRANSLATION_NATIVE_URLS[provider.kind]) return '官方机器翻译服务使用固定 API 地址。';
    if (provider.model || provider.prompt) return '官方机器翻译服务不使用模型名称或提示词。';
  }
  if (provider.region && (provider.kind !== 'microsoft' || !/^[a-z0-9-]{1,64}$/.test(provider.region))) return '仅微软翻译可填写资源地域，请使用控制台中的地域标识。';
  if (provider.kind === 'openai' && !provider.model.trim()) return 'OpenAI 兼容服务需要填写模型名称。';
  return null;
}
export function normalizeTimestamp(value: number): number { return value < 1_000_000_000_000 ? value * 1000 : value; }
