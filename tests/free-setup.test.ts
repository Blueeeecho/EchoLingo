import { describe, expect, it } from 'vitest';
import { FREE_SERVICES, servicesFor, serviceById } from '../src/free-services';
import { tx } from '../src/ui-text';

describe('independent free service recommendations', () => {
  it('offers separate role lists with no pair or implicit second service', () => {
    for (const region of ['cn', 'overseas'] as const) for (const role of ['translation', 'ocr'] as const) {
      const list = servicesFor(region, role);
      expect(list.length).toBeGreaterThan(1);
      expect(list.every((item) => item.role === role && item.regionGroup === region)).toBe(true);
      expect(list.every((item) => !('pieces' in item))).toBe(true);
    }
    expect(new Set(FREE_SERVICES.map((item) => item.id)).size).toBe(FREE_SERVICES.length);
    expect(serviceById('missing')).toBeUndefined();
    expect(JSON.stringify(FREE_SERVICES)).not.toMatch(/gemini|generativelanguage|tencent-mt/i);
  });
  it('every recommendation has quota, period/conditions, date, official source and supported setup', () => {
    for (const item of FREE_SERVICES) {
      expect(item.allowance.summary.length).toBeGreaterThan(10);
      expect(item.allowance.details.length).toBeGreaterThan(0);
      expect(item.allowance.checkedOn).toMatch(/^2026-10-\d\d$/);
      expect(item.allowance.links.length).toBeGreaterThan(0);
      expect(item.quotaEn.length).toBeGreaterThan(10);
      expect(item.conditionsEn.length).toBeGreaterThan(10);
      expect(item.signupUrl).toMatch(/^https:\/\//);
      expect(item.allowance.links.every(([, url]) => url.startsWith('https://'))).toBe(true);
      expect(item.allowance.summary).not.toContain('永久免费');
    }
    expect(serviceById('deepl')!.allowance.allowances[0]!.period).toBe('once');
    expect(serviceById('microsoft')!.allowance.allowances[0]!.amount).toBe(2_000_000);
    expect(serviceById('ocrspace')!.model).toBe('2');
    expect(serviceById('aliyun')!.credential).toBe('appPair');
    expect(serviceById('siliconflow')!.allowance.summary).toContain('0');
  });
  it('follows the active UI language', () => {
    expect(tx('中文', 'English', 'zh')).toBe('中文');
    expect(tx('中文', 'English', 'en')).toBe('English');
  });
});

describe('conditional newcomer trials', () => {
  it('expires only the old enrollment recommendation, not the service/configuration', () => {
    expect(servicesFor('cn', 'translation', new Date('2026-12-31T15:59:59Z')).some(p => p.id === 'tokenhub-trial')).toBe(true);
    expect(servicesFor('cn', 'translation', new Date('2026-12-31T16:00:00Z')).some(p => p.id === 'tokenhub-trial')).toBe(false);
    expect(serviceById('tokenhub-trial')).toBeDefined();
  });
  it('requires account-confirmed models and never invents a numeric Ark quota', () => {
    for (const id of ['qianfan-trial', 'tokenhub-trial', 'ark-trial']) expect(serviceById(id)?.editableModel).toBe(true);
    expect(serviceById('ark-trial')!.allowance.allowances[0]!.amount).toBeNull();
    expect(serviceById('qianfan-trial')!.allowance.allowances[0]).toMatchObject({ amount: 1_000_000, period: 'once', expires: '3 个月' });
    expect(serviceById('tokenhub-trial')!.allowance.details.join(' ')).toContain('共享');
  });
});
