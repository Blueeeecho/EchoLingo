export type ProviderKind = 'system' | 'offline' | 'openai' | 'deepl' | 'libretranslate';
export type CredentialState = 'ready' | 'missing' | 'blocked' | 'unloaded';
export interface SystemTranslationStatus {
  supported: boolean;
  ready: boolean;
  message: string;
  platform: string;
  requiresSetup?: boolean;
  status?: string;
  minimumVersion?: string;
  providerName?: string;
}
export interface Provider {
  id: string;
  name: string;
  kind: ProviderKind;
  baseUrl: string;
  model: string;
  enabled: boolean;
  prompt?: string;
  hasKey?: boolean;
  credentialState?: CredentialState;
}
export interface OcrProvider {
  id: string; name: string; kind: 'baidu' | 'tencent' | 'openai-vision' | 'http-json'; baseUrl: string; model: string; prompt: string;
  authHeader: string; authPrefix: string; requestTemplate: string; responsePath: string; region?: string; hasKey?: boolean; credentialState?: CredentialState;
}
export type Action = 'selection' | 'capture' | 'ocr' | 'silentOcr' | 'input' | 'clipboard';
export type ShortcutAction = Exclude<Action, 'clipboard'>;
export interface Settings {
  providers: Provider[];
  targetLanguage: string;
  sourceLanguage: string;
  languageDirectionVersion?: number;
  shortcutDefaultsVersion?: number;
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
export interface TranslationProgress {
  requestId: number;
  presentationEpoch: number;
  sequence: number;
  done: boolean;
  result: TranslationResult;
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
export type PermissionKind = 'accessibility' | 'screenCapture';
export interface SourceTextEvent { text: string; mode: 'translate' | 'ocr' | 'input'; captureOrigin?: 'ocr'; permissionRequired?: PermissionKind; focusInput?: boolean; updateVisiblePopup?: boolean }
