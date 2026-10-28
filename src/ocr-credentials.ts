import type { OcrProvider } from './types';

export interface OcrSecretFields { apiKey?: string; secretId?: string; secretKey?: string; sessionToken?: string; appKey?: string; appSecret?: string; genericKey?: string }
export type OcrCredentialResult = { key: string | null; error: null } | { key: null; error: string };
// This object is handed only to the credential-store command, never Settings.
export function buildOcrCredential(kind: OcrProvider['kind'], fields: OcrSecretFields, requireNew: boolean): OcrCredentialResult {
  const apiKey = fields.apiKey?.trim() ?? '', secretId = fields.secretId?.trim() ?? '';
  const secretKey = fields.secretKey?.trim() ?? '', sessionToken = fields.sessionToken?.trim() ?? '';
  let key: string | null = null;
  if (kind === 'baidu') {
    if (Boolean(apiKey) !== Boolean(secretKey)) return { key: null, error: '百度 OCR 需要同时填写 API Key 和 Secret Key；保留已有凭据时请全部留空。' };
    if (apiKey && secretKey) key = JSON.stringify({ apiKey, secretKey });
  } else if (kind === 'tencent') {
    if ((secretId || secretKey || sessionToken) && (!secretId || !secretKey)) return { key: null, error: '腾讯 OCR 需要同时填写 SecretId 和 SecretKey；SessionToken 不能单独更新。' };
    if (secretId && secretKey) key = JSON.stringify({ secretId, secretKey, ...(sessionToken ? { sessionToken } : {}) });
  } else if (kind === 'youdao') {
    const appKey = fields.appKey?.trim() ?? '', appSecret = fields.appSecret?.trim() ?? '';
    if (Boolean(appKey) !== Boolean(appSecret)) return { key: null, error: '有道 OCR 需要同时填写应用 ID 和应用密钥；保留已有凭据时请全部留空。' };
    if (appKey && appSecret) key = JSON.stringify({ appKey, appSecret });
  } else key = fields.genericKey?.trim() || null;
  if (requireNew && !key) return { key: null, error: '切换 OCR 协议或服务地址后必须填写完整的新凭据，原服务的密钥不会复用。' };
  return { key, error: null };
}
export const OCR_NATIVE_URLS = { baidu: 'https://aip.baidubce.com', tencent: 'https://ocr.tencentcloudapi.com', youdao: 'https://openapi.youdao.com/ocrapi', google: 'https://vision.googleapis.com/v1/images:annotate' } as const;
export function isNativeOcr(kind: string): kind is keyof typeof OCR_NATIVE_URLS { return Object.hasOwn(OCR_NATIVE_URLS, kind); }
export const OCR_NATIVE_ACTIONS = {
  baidu: [['general_basic', '通用文字识别 · 标准版'], ['accurate_basic', '通用文字识别 · 高精度版']],
  tencent: [['GeneralBasicOCR', '通用印刷体识别'], ['GeneralAccurateOCR', '通用文字识别 · 高精度版']],
  youdao: [['general', '通用文字识别']],
  google: [['DOCUMENT_TEXT_DETECTION', '文档文字识别'], ['TEXT_DETECTION', '图片文字识别']],
} as const;
