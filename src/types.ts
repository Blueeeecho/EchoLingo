export type ProviderKind = 'system' | 'offline' | 'baidu' | 'youdao' | 'microsoft' | 'openai' | 'deepl' | 'libretranslate';
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
  region?: string;
  hasKey?: boolean;
  credentialState?: CredentialState;
}
export interface OcrProvider {
  id: string; name: string; kind: 'baidu' | 'tencent' | 'youdao' | 'google' | 'openai-vision' | 'http-json'; baseUrl: string; model: string; prompt: string;
  authHeader: string; authPrefix: string; requestTemplate: string; responsePath: string; region?: string; hasKey?: boolean; credentialState?: CredentialState;
}
export type Action = 'selection' | 'capture' | 'ocr' | 'silentOcr' | 'input' | 'clipboard';
export type ShortcutAction = Exclude<Action, 'clipboard'>;
export interface ShortcutRegistration { action: ShortcutAction; combo?: string; active: boolean; error?: string | null }
export interface Settings {
  /** Read-only runtime metadata; the native settings serializer does not persist it. */
  appVersion?: string;
  providers: Provider[];
  targetLanguage: string;
  sourceLanguage: string;
  languageDirectionVersion?: number;
  shortcutDefaultsVersion?: number;
  shortcuts: Record<ShortcutAction, string>;
  shortcutRegistration?: ShortcutRegistration[];
  windowsSelectionStrategy?: 'copy' | 'auto';
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
  resolvedLanguages?: { sourceLanguage: string; targetLanguage: string };
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
export interface SourceTextEvent { text: string; mode: 'translate' | 'ocr' | 'input'; captureOrigin?: 'ocr'; permissionRequired?: PermissionKind; focusInput?: boolean; updateVisiblePopup?: boolean; reuseVisiblePopup?: boolean; presentationEpoch?: number; deliveryId?: number }
