import { describe, expect, it } from 'vitest';
import { credentialScope } from '../src/credential-scope';
import { buildOcrCredential, OCR_NATIVE_ACTIONS, OCR_NATIVE_URLS } from '../src/ocr-credentials';
import { inferProviderPreset, PROVIDER_PRESETS, qwenBaseUrl, qwenSettingsFromUrl } from '../src/provider-presets';
import type { Provider } from '../src/types';

describe('native OCR credential bundles', () => {
  it('requires both Baidu credential components whenever either is supplied', () => {
    expect(buildOcrCredential('baidu', { apiKey: 'qa-api' }, false).error).toBeTruthy();
    expect(buildOcrCredential('baidu', { secretKey: 'qa-secret' }, false).error).toBeTruthy();
    const result = buildOcrCredential('baidu', { apiKey: 'qa-api', secretKey: 'qa-secret', sessionToken: 'irrelevant' }, false);
    expect(result.error).toBeNull();
    expect(JSON.parse(result.key!)).toEqual({ apiKey: 'qa-api', secretKey: 'qa-secret' });
  });
  it('permits all-empty same-protocol edits to preserve the stored bundle', () => {
    expect(buildOcrCredential('baidu', {}, false)).toEqual({ key: null, error: null });
    expect(buildOcrCredential('tencent', {}, false)).toEqual({ key: null, error: null });
  });
  it('rejects partial Tencent credentials and a token supplied without a complete pair', () => {
    for (const fields of [{ secretId: 'qa-id' }, { secretKey: 'qa-secret' }, { sessionToken: 'qa-session' }, { secretId: 'qa-id', sessionToken: 'qa-session' }]) expect(buildOcrCredential('tencent', fields, false).error).toBeTruthy();
  });
  it('serializes Tencent optional session token only when supplied with a pair', () => {
    const pair = buildOcrCredential('tencent', { secretId: 'qa-id', secretKey: 'qa-secret' }, false);
    expect(JSON.parse(pair.key!)).toEqual({ secretId: 'qa-id', secretKey: 'qa-secret' });
    const temporary = buildOcrCredential('tencent', { secretId: 'qa-id', secretKey: 'qa-secret', sessionToken: 'qa-session' }, false);
    expect(JSON.parse(temporary.key!)).toEqual({ secretId: 'qa-id', secretKey: 'qa-secret', sessionToken: 'qa-session' });
  });
  it('requires new credentials when switching any OCR protocol', () => {
    for (const kind of ['baidu', 'tencent', 'openai-vision', 'http-json'] as const) expect(buildOcrCredential(kind, {}, true).error).toMatch(/切换 OCR 协议/);
    expect(buildOcrCredential('tencent', { secretId: 'qa-id', secretKey: 'qa-secret' }, true).error).toBeNull();
  });
  it('keeps native endpoints and actions separate from generic gateway configuration', () => {
    expect(OCR_NATIVE_URLS).toEqual({ baidu: 'https://aip.baidubce.com', tencent: 'https://ocr.tencentcloudapi.com' });
    expect(OCR_NATIVE_ACTIONS.baidu.map(([action]) => action)).toEqual(['general_basic', 'accurate_basic']);
    expect(OCR_NATIVE_ACTIONS.tencent.map(([action]) => action)).toEqual(['GeneralBasicOCR', 'GeneralAccurateOCR']);
  });
});

describe('vendor presets and Qwen regions', () => {
  it('uses distinct official standard API bases instead of guessing from service names', () => {
    const bases = Object.fromEntries(PROVIDER_PRESETS.map((preset) => [preset.id, preset.baseUrl]));
    expect(bases.deepseek).toBe('https://api.deepseek.com');
    expect(bases.zhipu).toBe('https://open.bigmodel.cn/api/paas/v4');
    expect(bases.siliconflow).toBe('https://api.siliconflow.cn/v1');
    expect(PROVIDER_PRESETS.find((preset) => preset.id === 'qwen')?.help).toMatch(/不接入阿里机器翻译/);
  });
  it('constructs the selected Qwen region and optional workspace host', () => {
    expect(qwenBaseUrl('beijing')).toBe('https://dashscope.aliyuncs.com/compatible-mode/v1');
    expect(qwenBaseUrl('singapore')).toBe('https://dashscope-intl.aliyuncs.com/compatible-mode/v1');
    const base = qwenBaseUrl('singapore', 'ws-qa');
    expect(base).toBe('https://ws-qa.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1');
    expect(qwenSettingsFromUrl(base)).toEqual({ region: 'singapore', workspaceId: 'ws-qa' });
    expect(() => qwenBaseUrl('beijing', 'qa.example.com/path')).toThrow();
  });
  it('infers presets only from actual protocol and host, not misleading text', () => {
    const provider: Provider = { id: 'qa', name: 'DeepSeek', kind: 'openai', baseUrl: 'https://api.deepseek.com.attacker.invalid', model: 'test', enabled: true };
    expect(inferProviderPreset(provider)).toBe('openai');
    expect(inferProviderPreset({ ...provider, baseUrl: 'https://api.deepseek.com' })).toBe('deepseek');
    expect(inferProviderPreset({ ...provider, kind: 'deepl' })).toBe('deepl');
  });
});


describe('credential origin binding', () => {
  it('preserves credentials across same-origin model and path changes', () => {
    expect(credentialScope('openai', 'https://API.EXAMPLE.COM:443/v1')).toBe(credentialScope('openai', 'https://api.example.com/v2/chat'));
    expect(credentialScope('http-json', 'http://localhost:80/first')).toBe(credentialScope('http-json', 'http://localhost/second'));
  });
  it('separates protocol, origin scheme, host, and non-default port', () => {
    const scope = credentialScope('openai', 'https://api.example.com/v1');
    for (const [kind, url] of [['deepl', 'https://api.example.com/v1'], ['openai', 'https://other.example.com/v1'], ['openai', 'http://api.example.com/v1'], ['openai', 'https://api.example.com:8443/v1']]) expect(credentialScope(kind, url)).not.toBe(scope);
    expect(credentialScope('openai', 'not a URL')).toBeNull();
  });
});
