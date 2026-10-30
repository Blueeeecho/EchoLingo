import type { ProviderKind } from './types';

export const TRANSLATION_NATIVE_URLS = {
  baidu: 'https://fanyi-api.baidu.com/api/trans/vip/translate',
  youdao: 'https://openapi.youdao.com/api',
  microsoft: 'https://api.cognitive.microsofttranslator.com',
  volcengine: 'https://translate.volcengineapi.com',
  aliyun: 'https://mt.aliyuncs.com',
} as const;
export type NativeTranslationKind = keyof typeof TRANSLATION_NATIVE_URLS;
export function isNativeTranslation(kind: string): kind is NativeTranslationKind { return Object.hasOwn(TRANSLATION_NATIVE_URLS, kind); }
export interface TranslationSecretFields { appId?: string; secretKey?: string; appKey?: string; appSecret?: string; subscriptionKey?: string; genericKey?: string }
export function buildTranslationCredential(kind: ProviderKind, fields: TranslationSecretFields): { key: string | null; error: string | null } {
  const value = (name: keyof TranslationSecretFields): string => fields[name]?.trim() ?? '';
  if (kind === 'system' || kind === 'offline') return { key: null, error: null };
  if (kind === 'baidu' || kind === 'youdao' || kind === 'volcengine' || kind === 'aliyun') {
    const first = value(kind === 'youdao' ? 'appKey' : 'appId');
    const second = value(kind === 'youdao' ? 'appSecret' : 'secretKey');
    if (Boolean(first) !== Boolean(second)) {
      const error = kind === 'baidu' ? '百度翻译需要同时填写 APP ID 和密钥；保留已有凭据时请全部留空。'
        : kind === 'youdao' ? '有道翻译需要同时填写应用 ID 和应用密钥；保留已有凭据时请全部留空。'
        : kind === 'volcengine' ? '火山引擎机器翻译需要同时填写 AccessKey ID 和 Secret Access Key。'
        : '阿里云机器翻译需要同时填写 AccessKey ID 和 AccessKey Secret。这不是百炼 API Key。';
      return { key: null, error };
    }
    const key = !first ? null : kind === 'youdao' ? JSON.stringify({ appKey: first, appSecret: second })
      : kind === 'baidu' ? JSON.stringify({ appId: first, secretKey: second })
      : JSON.stringify({ accessKeyId: first, accessKeySecret: second });
    return { key, error: null };
  }
  const key = value(kind === 'microsoft' ? 'subscriptionKey' : 'genericKey');
  return { key: key ? kind === 'microsoft' ? JSON.stringify({ subscriptionKey: key }) : key : null, error: null };
}
