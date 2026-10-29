import { describe, expect, it } from 'vitest';
import { coreGuidanceMessage, coreShortcutProblems, emptyPopupPlaceholder, explainShortcutFailure, recordingAvailabilityNote, suggestShortcutAlternative } from '../src/shortcut-guidance';
import type { ShortcutAction } from '../src/types';

const shortcuts = {
  selection: 'Alt+D', capture: '', ocr: 'Alt+Shift+S', silentOcr: 'Alt+S', input: 'Alt+A',
} satisfies Record<ShortcutAction, string>;

describe('core shortcut guidance', () => {
  it('offers an unused alternative and explains a registration conflict', () => {
    expect(suggestShortcutAlternative('selection', shortcuts)).toBe('Ctrl+Alt+D');
    expect(suggestShortcutAlternative('silentOcr', { ...shortcuts, capture: 'Ctrl+Alt+S', ocr: 'Ctrl+Shift+S' })).toBe('Alt+Shift+T');
    expect(explainShortcutFailure('系统注册失败：AlreadyRegistered', 'Alt+D')).toContain('占用');
    const problems = coreShortcutProblems(shortcuts, [
      { action: 'selection', combo: 'Alt+D', active: false, error: 'AlreadyRegistered' },
      { action: 'silentOcr', combo: 'Alt+S', active: true },
    ]);
    expect(problems.map((problem) => problem.action)).toEqual(['selection']);
    expect(problems[0]?.alternative).toBe('Ctrl+Alt+D');
    expect(coreGuidanceMessage(problems)).toContain('划词翻译 Alt+D');
  });
  it('stays quiet when registration state is absent or the shortcut is active', () => {
    expect(coreShortcutProblems(shortcuts, undefined)).toEqual([]);
    expect(coreShortcutProblems(shortcuts, [{ action: 'selection', combo: 'Alt+D', active: true }])).toEqual([]);
    expect(coreShortcutProblems({ ...shortcuts, selection: '' }, [{ action: 'selection', active: false }])).toEqual([]);
  });
  it('names the real shortcuts and how to cancel a region', () => {
    expect(emptyPopupPlaceholder(shortcuts)).toBe('划词 Alt+D · Alt+S 拖选屏幕，Esc 取消');
    expect(emptyPopupPlaceholder({ selection: '', silentOcr: '' })).toBe('输入或粘贴文字');
  });
  it('warns while recording about duplicates and macOS limits', () => {
    expect(recordingAvailabilityNote('selection', 'Alt+A', shortcuts, 'macos')).toContain('另一项');
    expect(recordingAvailabilityNote('silentOcr', 'Alt+S', shortcuts, 'windows')).toContain('优先');
    expect(recordingAvailabilityNote('selection', 'Ctrl+Alt+D', shortcuts, 'macos')).toContain('不允许强制覆盖');
  });
});
