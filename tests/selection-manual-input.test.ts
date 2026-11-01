import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
import ts from 'typescript';

// Execute the production listener's error handler without starting providers,
// a desktop app or permission APIs. Source focus/delivery is covered in UI CI.
function actionErrorHandler() {
  const source = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');
  const parsed = ts.createSourceFile('main.ts', source, ts.ScriptTarget.Latest, true);
  const handler = parsed.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === 'handleActionError');
  if (!handler) throw new Error('Production action error handler missing');
  const toast = vi.fn(), engineHint = vi.fn(), weak = vi.fn();
  const handle = new Function('toast', 'maybeSoftEngineHint', 'freeSetup', 'userFacingError',
    ts.transpile(handler.getText(parsed), { target: ts.ScriptTarget.ES2022 }) + '\nreturn handleActionError;')(
    toast, engineHint, { noteWeak: weak }, (message: string) => message) as (message: string) => void;
  return { handle, toast, engineHint, weak };
}

describe('Alt+D manual-input fallback', () => {
  it('does not surface selection failures or suggest provider changes', () => {
    const { handle, toast, engineHint, weak } = actionErrorHandler();
    for (const message of ['NO_SELECTION: empty', 'SELECTION_EMPTY: empty', 'COPY_NO_UPDATE: native timeout',
      'SELECTION_UNAVAILABLE: native failure', '  copy_no_update: late legacy delivery', 'CANCELLED: superseded']) handle(message);
    expect(toast).not.toHaveBeenCalled();
    expect(engineHint).not.toHaveBeenCalled();
    expect(weak).not.toHaveBeenCalled();
  });

  it('retains non-selection permission, OCR, provider and clipboard-safety errors', () => {
    const { handle, toast } = actionErrorHandler();
    for (const message of ['PERMISSION: Screen capture is not granted', 'OCR 服务返回 HTTP 403',
      'HTTP 503', 'OCR 已完成，但复制到剪贴板失败']) {
      handle(message);
      expect(toast).toHaveBeenLastCalledWith(expect.stringContaining(message), 'error', 8000);
    }
    expect(toast).toHaveBeenCalledTimes(4);
  });
});
