import type { ShortcutAction, ShortcutRegistration } from './types';

export type CoreShortcutAction = 'selection' | 'silentOcr';

const LABELS: Record<CoreShortcutAction, string> = {
  selection: '划词翻译',
  silentOcr: '截图识别',
};

const ALTERNATIVES: Record<CoreShortcutAction, readonly string[]> = {
  selection: ['Ctrl+Alt+D', 'Alt+Shift+D', 'Ctrl+Shift+D'],
  silentOcr: ['Ctrl+Alt+S', 'Ctrl+Shift+S', 'Alt+Shift+T'],
};

export interface CoreShortcutProblem {
  action: CoreShortcutAction;
  label: string;
  combo: string;
  reason: string;
  alternative: string | null;
}

export function suggestShortcutAlternative(action: CoreShortcutAction, shortcuts: Record<ShortcutAction, string>): string | null {
  const used = new Set(Object.values(shortcuts).filter((value) => value));
  const current = shortcuts[action];
  return ALTERNATIVES[action].find((candidate) => candidate !== current && !used.has(candidate)) ?? null;
}

export function explainShortcutFailure(error: string | null | undefined, combo: string): string {
  const text = (error ?? '').replace(/^注册快捷键失败：/, '').trim();
  if (!text) return `「${combo}」没有注册成功，可能被其他程序占用。`;
  if (/保留|仅支持|无效/.test(text)) return text;
  if (/AlreadyRegistered|HotKey|1409|占用|注册失败/.test(text)) return `「${combo}」被其他程序占用。关闭那个程序，或改用下面的组合。`;
  if (/监听|输入监听/.test(text)) return '系统键盘监听没有就绪。请重启 EchoLingo，或先改用其他快捷键。';
  return text;
}

export function coreShortcutProblems(
  shortcuts: Record<ShortcutAction, string>,
  registrations: ShortcutRegistration[] | undefined,
): CoreShortcutProblem[] {
  if (!registrations?.length) return [];
  const problems: CoreShortcutProblem[] = [];
  for (const action of ['selection', 'silentOcr'] as const) {
    const combo = shortcuts[action];
    if (!combo) continue;
    const state = registrations.find((item) => item.action === action && (!item.combo || item.combo === combo));
    if (!state || state.active) continue;
    problems.push({
      action,
      label: LABELS[action],
      combo,
      reason: explainShortcutFailure(state.error, combo),
      alternative: suggestShortcutAlternative(action, shortcuts),
    });
  }
  return problems;
}

export function emptyPopupPlaceholder(shortcuts: { selection: string; silentOcr: string }): string {
  if (!shortcuts.selection && !shortcuts.silentOcr) return '输入或粘贴文字';
  const selection = shortcuts.selection || '未设置';
  const ocr = shortcuts.silentOcr || '未设置';
  return `划词 ${selection} · ${ocr} 拖选屏幕，Esc 取消`;
}

export function coreGuidanceMessage(problems: CoreShortcutProblem[]): string {
  return problems.map((problem) => `${problem.label} ${problem.combo}：${problem.reason}`).join('\n');
}

export function recordingAvailabilityNote(
  action: ShortcutAction,
  combo: string,
  shortcuts: Record<ShortcutAction, string>,
  platform: 'windows' | 'macos' | 'other',
): string {
  const clash = (Object.keys(shortcuts) as ShortcutAction[]).find((key) => key !== action && shortcuts[key] === combo);
  if (clash) return '这个组合已经用于另一项操作，松开后不会保存。';
  if (platform === 'windows' && (combo === 'Alt+D' || combo === 'Alt+S')) {
    return 'EchoLingo 运行时会优先响应这个组合；退出后恢复给其他程序。';
  }
  if (platform === 'macos') return '若其他应用已占用，macOS 不允许强制覆盖，保存会失败并保留原快捷键。';
  return '若被占用，保存会失败并保留原来的快捷键。';
}
