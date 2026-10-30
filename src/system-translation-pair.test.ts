import { describe, expect, it } from 'vitest';
import { systemTranslationSetupPair } from './model';
describe('system translation failed pair validation', () => {
  it('keeps valid detected languages beyond the short picker', () => {
    expect(systemTranslationSetupPair({ sourceLanguage: 'ca', targetLanguage: 'zh-Hans' })).toEqual({ sourceLanguage: 'ca', targetLanguage: 'zh-Hans' });
    expect(systemTranslationSetupPair({ sourceLanguage: 'pt-BR', targetLanguage: 'en' })).toEqual({ sourceLanguage: 'pt-BR', targetLanguage: 'en' });
  });
  it('rejects missing, auto, same, malformed and oversized values', () => {
    for (const sourceLanguage of ['auto', 'en', '', 'ca<script>', 'de\n', 'a'.repeat(100)]) expect(systemTranslationSetupPair({ sourceLanguage, targetLanguage: 'en' })).toBeNull();
    expect(systemTranslationSetupPair(null)).toBeNull();
  });
});
