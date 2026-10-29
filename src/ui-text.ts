export type UiLang = 'zh' | 'en';

export function uiLang(): UiLang {
  const value = (typeof navigator === 'undefined' ? 'zh' : navigator.language || 'zh').toLowerCase();
  return value.startsWith('zh') ? 'zh' : 'en';
}

export function tx(zh: string, en: string, lang: UiLang = uiLang()): string {
  return lang === 'zh' ? zh : en;
}
