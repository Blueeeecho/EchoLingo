import { describe, expect, it } from 'vitest';
import { userFacingError } from './model';

describe('copy without clipboard update', () => {
  it('explains the observed timeout without claiming no selection or an administrator cause', () => {
    const message = userFacingError('COPY_NO_UPDATE: private diagnostic detail');
    expect(message).toContain('目标应用没有及时更新剪贴板');
    expect(message).toContain('Ctrl+C');
    expect(message).not.toContain('private diagnostic detail');
    expect(message).not.toContain('未选中');
    expect(message).not.toContain('管理员');
  });
  it('handles Error values and whitespace without changing unrelated errors', () => {
    expect(userFacingError(new Error(' COPY_NO_UPDATE: timeout'))).toContain('Ctrl+C');
    expect(userFacingError('NO_SELECTION: confirmed empty')).toBe('NO_SELECTION: confirmed empty');
    expect(userFacingError('CLIPBOARD_RESTORE_FAILED: failure')).toBe('CLIPBOARD_RESTORE_FAILED: failure');
  });
});

describe('unverifiable macOS selection', () => {
  it('offers the existing explicit clipboard route without an automatic copy or permission claim', () => {
    const message = userFacingError('SELECTION_UNAVAILABLE: generated native detail');
    expect(message).toContain('先按 ⌘C');
    expect(message).toContain('翻译剪贴板');
    expect(message).toContain('截图识别');
    expect(message).not.toContain('generated native detail');
    expect(message).not.toContain('权限');
  });
});
