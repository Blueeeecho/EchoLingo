import { describe, expect, it } from 'vitest';
import { OCR_NATIVE_ACTIONS } from '../src/ocr-credentials';
import { PROVIDER_PRESETS, inferProviderPreset } from '../src/provider-presets';
import { OCR_QUOTAS, SERVICE_QUOTA_CHECKED_ON, TRANSLATION_QUOTAS, recommendedTranslationPresets } from '../src/service-quotas';

describe('service quota coverage and measurement', () => {
  it('covers only supported translation presets and OCR adapters', () => {
    expect(Object.keys(TRANSLATION_QUOTAS).sort()).toEqual(PROVIDER_PRESETS.map(preset => preset.id).sort());
    expect(Object.keys(OCR_QUOTAS).sort()).toEqual(['local', ...Object.keys(OCR_NATIVE_ACTIONS), 'openai-vision', 'http-json'].sort());
    expect(OCR_QUOTAS).not.toHaveProperty('aliyun');
    expect(OCR_QUOTAS).not.toHaveProperty('huawei');
  });
  it('keeps billing units, periods and conditional quantities explicit', () => {
    for (const entry of [...Object.values(TRANSLATION_QUOTAS), ...Object.values(OCR_QUOTAS)]) {
      expect(entry.checkedOn).toBe(SERVICE_QUOTA_CHECKED_ON);
      expect(entry.summary.length).toBeGreaterThan(0);
      for (const allowance of entry.allowances) {
        expect(allowance.conditions.length).toBeGreaterThan(0);
        if (allowance.amount !== null) {
          expect(Number.isFinite(allowance.amount)).toBe(true);
          expect(allowance.amount).toBeGreaterThan(0);
          expect(['month', 'once']).toContain(allowance.period);
        }
      }
      for (const [, link] of entry.links) {
        const url = new URL(link);
        expect(url.protocol).toBe('https:');
        expect(url.username + url.password + url.search).toBe('');
      }
    }
  });
  it('distinguishes new DeepL one-time quota from grandfathered monthly Free', () => {
    expect(TRANSLATION_QUOTAS.deepl.allowances).toEqual([
      expect.objectContaining({ plan: expect.stringContaining('Developer'), amount: 1_000_000, period: 'once', unit: 'characters' }),
      expect.objectContaining({ plan: expect.stringContaining('旧'), amount: 500_000, period: 'month', conditions: [expect.stringContaining('已不能新开通')] }),
    ]);
    expect(TRANSLATION_QUOTAS.deepl.summary).toContain('不重置');
  });
  it('does not turn account credits or expiring model trials into recurring quotas', () => {
    expect(TRANSLATION_QUOTAS.youdao.allowances.map(value => [value.amount, value.unit, value.period])).toEqual([[10, 'CNY', 'once'], [40, 'CNY', 'once']]);
    expect(OCR_QUOTAS.youdao).toBe(TRANSLATION_QUOTAS.youdao);
    expect(TRANSLATION_QUOTAS.qwen.allowances[0]).toMatchObject({ amount: 1_000_000, unit: 'tokens', period: 'once', expires: expect.stringContaining('90 天') });
    expect(TRANSLATION_QUOTAS.qwen.details.join(' ')).toMatch(/仅北京.*新加坡/);
    for (const key of ['openai', 'minimax', 'deepseek', 'zhipu'] as const) expect(TRANSLATION_QUOTAS[key].allowances).toEqual([]);
  });
  it('scopes monthly free quotas to the selected cloud plan and OCR measurement', () => {
    expect(TRANSLATION_QUOTAS.microsoft.allowances[0]).toMatchObject({ plan: 'Translator F0', amount: 2_000_000, unit: 'characters', period: 'month' });
    expect(TRANSLATION_QUOTAS.baidu.allowances.map(value => value.amount)).toEqual([50_000, 1_000_000]);
    expect(OCR_QUOTAS.baidu.allowances.map(value => value.amount)).toEqual([1000, 2000]);
    expect(OCR_QUOTAS.google.allowances[0]).toMatchObject({ amount: 1000, unit: 'units', period: 'month' });
    expect(OCR_QUOTAS.google.details.join(' ')).toContain('不能把 1000 units 当作 1000 个批量 HTTP 请求');
  });
});

describe('recommended configuration remains optional and platform-aware', () => {
  it('recommends the correct local adapter without inventing platform support', () => {
    expect(recommendedTranslationPresets('macos')).toEqual(['system', 'microsoft', 'baidu', 'siliconflow']);
    expect(recommendedTranslationPresets('WINDOWS')).toEqual(['offline', 'microsoft', 'baidu', 'siliconflow']);
    expect(recommendedTranslationPresets('harmonyos')).toEqual(['microsoft', 'baidu', 'siliconflow']);
    for (const entry of [TRANSLATION_QUOTAS.system, TRANSLATION_QUOTAS.offline, OCR_QUOTAS.local]) {
      expect(entry.allowances[0]).toMatchObject({ amount: null, unit: 'none', period: 'unmetered' });
    }
  });
  it('defaults new SiliconFlow services to the exact free model and preserves saved models', () => {
    const preset = PROVIDER_PRESETS.find(value => value.id === 'siliconflow')!;
    expect(preset.exampleModel).toBe(TRANSLATION_QUOTAS.siliconflow.recommendedModel);
    expect(preset.exampleModel).toBe('tencent/Hunyuan-MT-7B');
    expect(TRANSLATION_QUOTAS.siliconflow.allowances[0]).toMatchObject({ amount: null, period: 'variable' });
    const saved = { id: 'existing', name: '已有服务', kind: 'openai' as const, baseUrl: preset.baseUrl, model: 'saved-paid-model', enabled: true };
    expect(inferProviderPreset(saved)).toBe('siliconflow');
    expect(saved.model).toBe('saved-paid-model');
    expect(TRANSLATION_QUOTAS.siliconflow.details.join(' ')).toContain('受速率、并发');
  });
});
