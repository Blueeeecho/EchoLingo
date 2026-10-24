export type ProviderKind = 'openai' | 'deepl' | 'libretranslate';
export interface Provider {
  id: string;
  name: string;
  kind: ProviderKind;
  baseUrl: string;
  model: string;
  enabled: boolean;
  prompt?: string;
  hasKey?: boolean;
}
export interface OcrProvider {
  id: string; name: string; kind: 'baidu' | 'tencent' | 'openai-vision' | 'http-json'; baseUrl: string; model: string; prompt: string;
  authHeader: string; authPrefix: string; requestTemplate: string; responsePath: string; region?: string; hasKey?: boolean;
}
export type Action = 'selection' | 'capture' | 'ocr' | 'silentOcr' | 'input' | 'clipboard';
export type ShortcutAction = Exclude<Action, 'clipboard'>;
export interface Settings {
  providers: Provider[];
  targetLanguage: string;
  sourceLanguage: string;
  shortcuts: Record<ShortcutAction, string>;
  saveHistory: boolean;
  theme: 'system' | 'light' | 'dark';
  maxHistory: number;
  autoHideSeconds: number;
  ocrProviders: OcrProvider[];
  activeOcrProviderId: string | null;
}
export interface TranslationResult {
  providerId: string;
  providerName: string;
  text: string;
  error?: string;
  elapsedMs: number;
}
export interface HistoryEntry {
  id: string;
  text: string;
  sourceLanguage: string;
  targetLanguage: string;
  results: TranslationResult[];
  createdAt: number;
  favorite: boolean;
}
export interface SourceTextEvent { text: string; mode: 'translate' | 'ocr' | 'input' }
