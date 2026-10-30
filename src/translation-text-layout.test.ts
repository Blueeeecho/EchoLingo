import { describe, expect, it } from 'vitest';
import { translationTextParts } from './translation-text-layout';

describe('display-only translation paragraph spacing', () => {
  it('compacts only blank-line separators and keeps every original character', () => {
    for (const text of ['First\n\nSecond', '第一段\r\n \r\n\r\n第二段', '\n\nFirst\n\n\nLast\n\n']) {
      const parts = translationTextParts(text);
      expect(parts.map(part => part.text).join('')).toBe(text);
      expect(parts.some(part => part.paragraphBreak)).toBe(true);
    }
  });
  it('preserves list lines, poetry line breaks, spaces and raw HTML without parsing', () => {
    const text = 'Verse one\nVerse two\n\n- Item one\n- Item two\n\n<b>Literal</b>  spacing';
    const parts = translationTextParts(text);
    expect(parts.filter(part => !part.paragraphBreak).map(part => part.text)).toEqual([
      'Verse one\nVerse two', '- Item one\n- Item two', '<b>Literal</b>  spacing',
    ]);
    expect(parts.map(part => part.text).join('')).toBe(text);
  });
  it('does not compact fenced or indented literal content', () => {
    for (const text of ['Before\n\n```js\nconst a = 1;\n\nnext();\n```', '~~~\na\n\nb\n~~~', 'Header\n\n    code\n\n    more', 'const values = [1, 2];\n  return values;\n\nNext paragraph', 'List\n  - nested\n\nNext', '\tcode\n\nmore']) {
      expect(translationTextParts(text)).toEqual([{ text, paragraphBreak: false, edge: false }]);
    }
  });
  it('handles empty, single-line and streaming partial separators unchanged', () => {
    for (const text of ['', 'one', 'one\n', 'one\r\n', 'one\n  two']) {
      expect(translationTextParts(text)).toEqual([{ text, paragraphBreak: false, edge: false }]);
    }
  });
  it('removes only visual outer padding without dropping literal separators', () => {
    const parts = translationTextParts('\n\nFirst\n\nLast\n\n');
    expect(parts.filter(part => part.paragraphBreak).map(part => part.edge)).toEqual([true, false, true]);
  });
});
