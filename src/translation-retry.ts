import type { TranslationResult } from './types';

export interface TranslationSnapshot { text: string; sourceLanguage: string; targetLanguage: string }

export function sameTranslationSnapshot(left: TranslationSnapshot | null, right: TranslationSnapshot): boolean {
  return left !== null && left.text === right.text
    && left.sourceLanguage === right.sourceLanguage && left.targetLanguage === right.targetLanguage;
}

// Only the requested provider may replace a card. Keep ordering, successes and
// errors from all other providers, without trusting an unexpected IPC result.
export function mergeProviderRetry(previous: TranslationResult[], providerId: string, results: TranslationResult[]): TranslationResult[] {
  const replacement = results.find((result) => result.providerId === providerId);
  if (!replacement) throw new Error('翻译服务没有返回结果，请重试。');
  return previous.map((result) => result.providerId === providerId ? replacement : result);
}
