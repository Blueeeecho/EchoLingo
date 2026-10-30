import { describe, expect, it } from 'vitest';
import { nextPopupContentHeight } from '../src/popup-growth';
import { engineLimitCopy, isWeakEngineSignal, shouldShowFirstRun, shouldShowSoftHint } from '../src/engine-hint';

describe('popup growth', () => {
  it('grows immediately and ignores a tiny shrink', () => {
    expect(nextPopupContentHeight(240.2, 0)).toBe(241);
    expect(nextPopupContentHeight(300, 241)).toBe(300);
    expect(nextPopupContentHeight(290, 300)).toBe(300);
    expect(nextPopupContentHeight(270, 300)).toBe(270);
  });
});

describe('engine hints', () => {
  it('shows the first-run card once and rate-limits a later soft hint', () => {
    expect(shouldShowFirstRun({ dismissed: false, shownAt: 0 })).toBe(true);
    expect(shouldShowFirstRun({ dismissed: true, shownAt: 0 })).toBe(false);
    expect(shouldShowSoftHint({ dismissed: false, shownAt: 1_000 }, 1_000 + 60_000)).toBe(false);
    expect(shouldShowSoftHint({ dismissed: false, shownAt: 1_000 }, 1_000 + 24 * 60 * 60 * 1000)).toBe(true);
    expect(shouldShowSoftHint({ dismissed: true, shownAt: 0 }, 10_000)).toBe(false);
  });
  it('does not invent prices and keeps cloud privacy explicit', () => {
    const local = engineLimitCopy(['offline'], true);
    expect(local.title).toContain('本机');
    expect(local.detail).toContain('云端');
    expect(local.detail).not.toMatch(/免费|价格|永久/);
    const cloud = engineLimitCopy(['openai'], false);
    expect(cloud.detail).toContain('图片');
    expect(cloud.detail).toContain('原文');
  });
  it('treats recognition and translation failures as a soft hint, and ignores cancel', () => {
    expect(isWeakEngineSignal('没有识别到文字，请选择更清晰的区域')).toBe(true);
    expect(isWeakEngineSignal('NO_TEXT: No text was recognized.')).toBe(true);
    expect(isWeakEngineSignal('翻译失败')).toBe(true);
    expect(isWeakEngineSignal('CANCELLED: 已取消截图。')).toBe(false);
    expect(isWeakEngineSignal('PERMISSION: 需要屏幕录制权限')).toBe(false);
  });
});
