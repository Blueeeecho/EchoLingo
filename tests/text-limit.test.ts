import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
import { codePointLength, truncateCodePoints, safeTextRange } from '../src/text-limit';

function editorFixture() {
  const sourceCode = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');
  const parsed = ts.createSourceFile('main.ts', sourceCode, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === 'enforceSourceLimit');
  if (!declaration) throw new Error('Missing production limiter');
  const source = { value: '', selectionStart: 0, selectionEnd: 0, setSelectionRange: vi.fn() };
  const toast = vi.fn();
  const run = new Function('source', 'truncateCodePoints', 'toast', 'sourceComposing', 'MAX_TEXT_LENGTH',
    ts.transpile(declaration.getText(parsed), { target: ts.ScriptTarget.ES2022 }) + '\nenforceSourceLimit();');
  return { source, toast, run: (composing: boolean) => run(source, truncateCodePoints, toast, composing, 20000) };
}

describe('translation Unicode code-point limit', () => {
  it('allows exactly 20,000 characters including emoji and supplementary Han', () => {
    for (const final of ['😀', '𠀀', '中']) {
      const text = 'a'.repeat(19999) + final;
      expect(codePointLength(text)).toBe(20000);
      expect(truncateCodePoints(text, 20000)).toBe(text);
    }
  });
  it('truncates captured text at a complete code point', () => {
    const text = 'a'.repeat(19999) + '😀z';
    expect(truncateCodePoints(text, 20000)).toBe('a'.repeat(19999) + '😀');
    expect(truncateCodePoints('😀😀', 1)).toBe('😀');
    expect(truncateCodePoints('anything', 0)).toBe('');
  });
  it('counts combining marks like Rust chars rather than claiming grapheme limits', () => {
    expect(codePointLength('e\u0301')).toBe(2);
    expect(truncateCodePoints('e\u0301', 2)).toBe('e\u0301');
  });
  it('does not split surrogate pairs in fallback replacement or backspace', () => {
    expect(safeTextRange('a😀b', 2, 3)).toEqual([1, 3]);
    expect(safeTextRange('a😀b', 1, 2)).toEqual([1, 3]);
    expect(safeTextRange('a😀b', 3, 4)).toEqual([3, 4]);
  });
  it('applies production manual-input limit only after IME commits', () => {
    const editor = editorFixture();
    editor.source.value = 'a'.repeat(19999) + '😀中';
    editor.source.selectionStart = editor.source.selectionEnd = editor.source.value.length;
    editor.run(true);
    expect(editor.source.value.endsWith('😀中')).toBe(true);
    expect(editor.toast).not.toHaveBeenCalled();
    editor.run(false);
    expect(editor.source.value).toBe('a'.repeat(19999) + '😀');
    expect(editor.source.setSelectionRange).toHaveBeenCalledWith(20001, 20001);
    expect(editor.toast).toHaveBeenCalledTimes(1);
  });
  it('keeps valid manual input intact', () => {
    const editor = editorFixture();
    editor.source.value = '😀'.repeat(20000);
    editor.run(false);
    expect(codePointLength(editor.source.value)).toBe(20000);
    expect(editor.toast).not.toHaveBeenCalled();
  });
});
