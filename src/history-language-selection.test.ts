import { describe, expect, it } from 'vitest';
import { HistoryLanguageSelection } from './history-language-selection';

const automatic = { sourceLanguage: 'auto', targetLanguage: 'auto' };
const historical = { sourceLanguage: 'en', targetLanguage: 'zh-Hans' };

describe('history language selection', () => {
  it('uses the resolved history pair only for that replay, then restores automatic mode', () => {
    const selection = new HistoryLanguageSelection();
    expect(selection.replay(automatic, historical)).toEqual(historical);
    expect(selection.newInput(historical)).toEqual(automatic);
    expect(selection.newInput(historical)).toEqual(historical);
  });

  it('preserves a fixed target and never silently flips it', () => {
    const selection = new HistoryLanguageSelection();
    const preferred = { sourceLanguage: 'auto', targetLanguage: 'zh-Hans' };
    selection.replay(preferred, historical);
    expect(selection.newInput(historical)).toEqual(preferred);
  });

  it('does not replace the original choice when several history entries are opened', () => {
    const selection = new HistoryLanguageSelection();
    selection.replay(automatic, historical);
    const second = { sourceLanguage: 'zh-Hans', targetLanguage: 'en' };
    expect(selection.replay(historical, second)).toEqual(second);
    expect(selection.newInput(second)).toEqual(automatic);
  });

  it('keeps an explicit user choice during history replay for subsequent input', () => {
    const selection = new HistoryLanguageSelection();
    selection.replay(automatic, historical);
    selection.choose();
    const chosen = { sourceLanguage: 'auto', targetLanguage: 'en' };
    expect(selection.newInput(chosen)).toEqual(chosen);
  });

  it('copies the preference so queued updates cannot mutate it', () => {
    const selection = new HistoryLanguageSelection();
    const preferred = { ...automatic };
    const replay = selection.replay(preferred, historical);
    preferred.targetLanguage = 'ja';
    replay.targetLanguage = 'fr';
    expect(selection.newInput(replay)).toEqual(automatic);
    expect(historical.targetLanguage).toBe('zh-Hans');
  });
});
