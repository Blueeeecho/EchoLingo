import { describe, expect, it } from 'vitest';
import { compactBlankLines } from './translation-text-layout';

describe('compact blank lines in captured and translated text', () => {
  it('retains a single break between real lines, without edge blank lines', () => {
    expect(compactBlankLines('\n\n第一条。\n \n\t\n第二条。\n第三条。\n\n')).toBe('第一条。\n第二条。\n第三条。');
    expect(compactBlankLines('\n\t\n')).toBe('');
  });
  it('handles common clipboard line separators and invisible empty rows', () => {
    expect(compactBlankLines('甲\r\n\u3000\r\n\u200b\r乙\u2028\u00a0\u2029丙')).toBe('甲\n乙\n丙');
  });
  it('preserves indentation, literal punctuation, and every nonblank line', () => {
    const value = '- 一级\n  - 二级\n    literal <b>x</b>\noutside  text';
    expect(compactBlankLines(value)).toBe(value);
    expect(compactBlankLines(value.replace('  - 二级', '\n  - 二级'))).toBe(value);
  });
});
