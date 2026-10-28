import { describe, expect, it } from 'vitest';
import { buildTranslationCredential, TRANSLATION_NATIVE_URLS } from '../src/translation-credentials';
import { buildOcrCredential, OCR_NATIVE_URLS, OCR_NATIVE_ACTIONS } from '../src/ocr-credentials';
import { PROVIDER_PRESETS, inferProviderPreset } from '../src/provider-presets';
import { OCR_GUIDES, TRANSLATION_GUIDES } from '../src/service-guides';
import { validateProvider } from '../src/model';

describe('official translation setup', () => {
  it('serializes only vendor credential components and preserves empty edits', () => {
    expect(JSON.parse(buildTranslationCredential('baidu', { appId: 'qa-app', secretKey: 'qa-secret', genericKey: 'irrelevant' }).key!)).toEqual({ appId: 'qa-app', secretKey: 'qa-secret' });
    expect(JSON.parse(buildTranslationCredential('youdao', { appKey: 'qa-app', appSecret: 'qa-secret' }).key!)).toEqual({ appKey: 'qa-app', appSecret: 'qa-secret' });
    expect(JSON.parse(buildTranslationCredential('microsoft', { subscriptionKey: 'qa-subscription' }).key!)).toEqual({ subscriptionKey: 'qa-subscription' });
    for (const kind of ['baidu', 'youdao', 'microsoft', 'system', 'offline'] as const) expect(buildTranslationCredential(kind, {})).toEqual({ key: null, error: null });
    expect(buildTranslationCredential('openai', { genericKey: 'qa-raw' }).key).toBe('qa-raw');
  });
  it('rejects partial paired credentials before saving settings', () => {
    for (const fields of [{ appId: 'qa' }, { secretKey: 'qa' }]) expect(buildTranslationCredential('baidu', fields).error).toMatch(/同时填写/);
    for (const fields of [{ appKey: 'qa' }, { appSecret: 'qa' }]) expect(buildTranslationCredential('youdao', fields).error).toMatch(/同时填写/);
  });
  it('uses fixed official endpoints without model or prompt and limits region to Microsoft', () => {
    for (const kind of ['baidu', 'youdao', 'microsoft'] as const) {
      const provider = { id: 'qa', name: 'QA', kind, baseUrl: TRANSLATION_NATIVE_URLS[kind], model: '', prompt: '', enabled: true };
      expect(validateProvider(provider)).toBeNull();
      expect(validateProvider({ ...provider, baseUrl: 'https://other.invalid' })).toMatch(/固定/);
      expect(validateProvider({ ...provider, model: 'qa-model' })).toMatch(/不使用模型/);
      expect(inferProviderPreset(provider)).toBe(kind);
      expect(PROVIDER_PRESETS.find(p => p.id === kind)).toMatchObject({ kind, baseUrl: provider.baseUrl, exampleModel: '' });
      expect(validateProvider({ ...provider, region: 'eastasia' })).toBe(kind === 'microsoft' ? null : '仅微软翻译可填写资源地域，请使用控制台中的地域标识。');
      expect(validateProvider({ ...provider, region: 'eastasia\r\n' })).not.toBeNull();
    }
  });
});
describe('official OCR setup', () => {
  it('requires a complete Youdao bundle while Google keeps a raw API Key', () => {
    expect(buildOcrCredential('youdao', { appKey: 'qa' }, false).error).toMatch(/同时填写/);
    expect(buildOcrCredential('youdao', { appSecret: 'qa' }, false).error).toMatch(/同时填写/);
    expect(JSON.parse(buildOcrCredential('youdao', { appKey: 'qa-app', appSecret: 'qa-secret', genericKey: 'ignored' }, false).key!)).toEqual({ appKey: 'qa-app', appSecret: 'qa-secret' });
    expect(buildOcrCredential('google', { genericKey: 'qa-google' }, false).key).toBe('qa-google');
    for (const kind of ['youdao', 'google'] as const) expect(buildOcrCredential(kind, {}, true).error).toMatch(/切换 OCR 协议/);
    expect(OCR_NATIVE_URLS.youdao).toBe('https://openapi.youdao.com/ocrapi');
    expect(OCR_NATIVE_URLS.google).toBe('https://vision.googleapis.com/v1/images:annotate');
    expect(OCR_NATIVE_ACTIONS.google.map(([action]) => action)).toEqual(['DOCUMENT_TEXT_DETECTION', 'TEXT_DETECTION']);
  });
});
describe('public official setup guides', () => {
  it('covers every preset and OCR kind with short instructions and secure fixed links', () => {
    expect(PROVIDER_PRESETS.every(preset => TRANSLATION_GUIDES[preset.id])).toBe(true);
    expect(Object.keys(OCR_GUIDES).sort()).toEqual(['baidu', 'google', 'http-json', 'openai-vision', 'tencent', 'youdao']);
    for (const guide of [...Object.values(TRANSLATION_GUIDES), ...Object.values(OCR_GUIDES)]) {
      expect(guide.steps.length).toBeGreaterThanOrEqual(2);
      expect(guide.links.length).toBeGreaterThan(0);
      for (const [label, url] of guide.links) { expect(label).toBeTruthy(); const link = new URL(url); expect(link.protocol).toBe('https:'); expect(link.username + link.password + link.search).toBe(''); }
    }
    expect(TRANSLATION_GUIDES.baidu.steps.join('')).toMatch(/百度 OCR.*不能/);
    expect(TRANSLATION_GUIDES.qwen.steps.join('')).toMatch(/不能填写阿里机器翻译/);
    expect(OCR_GUIDES.google.steps.join('')).toMatch(/启用 Cloud Vision API/);
  });
});
