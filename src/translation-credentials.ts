import type { ProviderKind } from './types';

export const TRANSLATION_NATIVE_URLS = {
  baidu: 'https://fanyi-api.baidu.com/api/trans/vip/translate',
  youdao: 'https://openapi.youdao.com/api',
  microsoft: 'https://api.cognitive.microsofttranslator.com',
} as const;
export type NativeTranslationKind = keyof typeof TRANSLATION_NATIVE_URLS;
export function isNativeTranslation(kind: string): kind is NativeTranslationKind { return Object.hasOwn(TRANSLATION_NATIVE_URLS, kind); }
export interface TranslationSecretFields { appId?: string; secretKey?: string; appKey?: string; appSecret?: string; subscriptionKey?: string; genericKey?: string }
export function buildTranslationCredential(kind: ProviderKind, fields: TranslationSecretFields): { key: string | null; error: string | null } {
  const value = (name: keyof TranslationSecretFields): string => fields[name]?.trim() ?? '';
  if (kind === 'system' || kind === 'offline') return { key: null, error: null };
  if (kind === 'baidu' || kind === 'youdao') {
    const first = value(kind === 'baidu' ? 'appId' : 'appKey'), second = value(kind === 'baidu' ? 'secretKey' : 'appSecret');
    if (Boolean(first) !== Boolean(second)) return { key: null, error: kind === 'baidu' ? '百度翻译需要同时填写 APP ID 和密钥；保留已有凭据时请全部留空。' : '有道翻译需要同时填写应用 ID 和应用密钥；保留已有凭据时请全部留空。' };
    return { key: first ? JSON.stringify(kind === 'baidu' ? { appId: first, secretKey: second } : { appKey: first, appSecret: second }) : null, error: null };
  }
  const key = value(kind === 'microsoft' ? 'subscriptionKey' : 'genericKey');
  return { key: key ? kind === 'microsoft' ? JSON.stringify({ subscriptionKey: key }) : key : null, error: null };
}
