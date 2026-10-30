import { describe, expect, it } from 'vitest';
import { mergeProviderRetry, sameTranslationSnapshot } from '../src/translation-retry';
import type { TranslationResult } from '../src/types';

const success: TranslationResult = { providerId: 'success', providerName: 'Success', text: 'Already translated', elapsedMs: 12 };
const failed: TranslationResult = { providerId: 'retry', providerName: 'Retry', text: '', error: 'Timeout', elapsedMs: 20 };
const retried: TranslationResult = { ...failed, text: 'Recovered', error: undefined };

describe('single-provider retry', () => {
  it('replaces only the requested result, retaining the successful card and order', () => {
    const previous = [success, failed];
    const next = mergeProviderRetry(previous, 'retry', [retried, { ...success, text: 'Unexpected replacement' }]);
    expect(next).toEqual([success, retried]);
    expect(next[0]).toBe(success);
    expect(previous).toEqual([success, failed]);
  });
  it('retains other providers when the retry itself fails and rejects missing results', () => {
    expect(mergeProviderRetry([success, retried], 'retry', [failed])).toEqual([success, failed]);
    expect(() => mergeProviderRetry([success, failed], 'retry', [success])).toThrow();
  });
  it('requires the same source text and both language choices', () => {
    const snapshot = { text: 'Hello', sourceLanguage: 'auto', targetLanguage: 'zh-Hans' };
    expect(sameTranslationSnapshot(snapshot, { ...snapshot })).toBe(true);
    expect(sameTranslationSnapshot(null, snapshot)).toBe(false);
    for (const changed of [{ text: 'New source' }, { sourceLanguage: 'en' }, { targetLanguage: 'ja' }]) {
      expect(sameTranslationSnapshot(snapshot, { ...snapshot, ...changed })).toBe(false);
    }
  });
});
