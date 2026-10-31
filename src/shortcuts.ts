import type { ShortcutAction } from './types';

const names: Record<string, string> = {
  ESC: 'Escape', RETURN: 'Enter', SPACE: 'Space', SPACEBAR: 'Space',
  UP: 'ArrowUp', DOWN: 'ArrowDown', LEFT: 'ArrowLeft', RIGHT: 'ArrowRight',
  '=': 'Equal', '-': 'Minus', ',': 'Comma', '.': 'Period', '/': 'Slash',
  ';': 'Semicolon', "'": 'Quote', '[': 'BracketLeft', ']': 'BracketRight',
  '\\': 'Backslash', '`': 'Backquote',
};
const namedKeys = ['Escape', 'Enter', 'Space', 'Tab', 'Backspace', 'Delete', 'Insert', 'Home', 'End',
  'PageUp', 'PageDown', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Equal', 'Minus', 'Comma',
  'Period', 'Slash', 'Semicolon', 'Quote', 'BracketLeft', 'BracketRight', 'Backslash', 'Backquote',
  'Pause', 'CapsLock', 'PrintScreen', 'ScrollLock', 'NumLock', 'NumpadAdd', 'NumpadSubtract',
  'NumpadMultiply', 'NumpadDivide', 'NumpadDecimal', 'NumpadEnter', 'NumpadEqual',
  'AudioVolumeUp', 'AudioVolumeDown', 'AudioVolumeMute', 'MediaPlay', 'MediaPause', 'MediaPlayPause',
  'MediaStop', 'MediaTrackNext', 'MediaTrackPrevious'];
for (const key of namedKeys) names[key.toUpperCase()] = key;
for (let n = 0; n <= 9; n++) names[`NUMPAD${n}`] = `Numpad${n}`;
const modifier = (token: string, mac: boolean): string | undefined => {
  if (['CTRL', 'CONTROL'].includes(token)) return 'Ctrl';
  if (['ALT', 'OPTION'].includes(token)) return 'Alt';
  if (token === 'SHIFT') return 'Shift';
  if (['SUPER', 'META', 'WIN', 'WINDOWS', 'COMMAND', 'CMD'].includes(token)) return 'Super';
  if (['CMDORCTRL', 'COMMANDORCONTROL', 'COMMANDORCTRL', 'CMDORCONTROL'].includes(token)) return mac ? 'Super' : 'Ctrl';
  return undefined;
};
const isWindows = () => typeof navigator !== 'undefined' && /Win/i.test(navigator.platform);
const mouseKey = (value: string): string | undefined => ({
  MOUSEX1: 'MouseX1', XBUTTON1: 'MouseX1', MOUSEBACK: 'MouseX1',
  MOUSEX2: 'MouseX2', XBUTTON2: 'MouseX2', MOUSEFORWARD: 'MouseX2',
} as Record<string, string>)[value];
export function normalizeShortcut(value: string, mac = false, windows = isWindows()): string {
  if (value.length > 80 || /[\r\n\0]/.test(value)) throw new Error('快捷键过长或包含无效字符。');
  const text = value.trim();
  if (!text) return '';
  const mods = new Set<string>(); let key = '';
  for (const part of text.split('+')) {
    const token = part.trim().toUpperCase();
    if (!token) throw new Error('请用 + 分隔修饰键与一个按键；加号键可写 Shift+Equal。');
    const mod = modifier(token, mac);
    if (mod) {
      if (mods.has(mod)) throw new Error('同一修饰键不能重复填写。');
      mods.add(mod); continue;
    }
    if (key) throw new Error('一个快捷键只能包含一个普通按键。');
    if (/^(?:KEY)?[A-Z]$/.test(token)) key = token.replace(/^KEY/, '');
    else if (/^(?:DIGIT)?[0-9]$/.test(token)) key = token.replace(/^DIGIT/, '');
    else if (/^F(?:[1-9]|1[0-9]|2[0-4])$/.test(token)) key = token;
    else key = mouseKey(token) ?? names[token] ?? '';
    if (!key) throw new Error(`不支持按键“${part.trim()}”；可使用字母、数字、F1–F24 或 Enter、Space 等键名。`);
  }
  if (!key) throw new Error('请再按一个普通按键，不能只设置 Ctrl、Alt 等修饰键。');
  if (key === 'MouseX1' || key === 'MouseX2') {
    if (!windows || mac) throw new Error('鼠标侧键快捷操作目前仅支持 Windows。');
    if (mods.size) throw new Error('鼠标侧键请单独使用，不搭配 Ctrl、Alt 等修饰键。');
    return key;
  }
  // The pinned Windows backend maps NumpadEqual to the ordinary E key.
  if (windows && !mac && key === 'NumpadEqual') throw new Error('Windows 暂不支持小键盘等号键，请选择其他按键。');
  if (![...mods].some((item) => item !== 'Shift') && !/^F\d+$/.test(key)) {
    throw new Error('请搭配 Ctrl、Alt 或 Win/Command；F1–F24 可以单独使用。');
  }
  return [...['Ctrl', 'Alt', 'Shift', 'Super'].filter((item) => mods.has(item)), key].join('+');
}
export function normalizeShortcuts(values: Record<ShortcutAction, string>, mac = false, windows = isWindows()): Record<ShortcutAction, string> {
  const result = {} as Record<ShortcutAction, string>; const seen = new Set<string>();
  for (const action of ['selection', 'silentOcr', 'screenshot', 'capture', 'ocr', 'input'] as const) {
    const key = normalizeShortcut(values[action] ?? '', mac, windows);
    if (key && seen.has(key)) throw new Error('不同操作不能使用相同的快捷键。');
    if (key) seen.add(key);
    result[action] = key;
  }
  return result;
}
export function displayShortcut(value: string, mac = false): string {
  try { return normalizeShortcut(value, mac).replace(/\bSuper\b/g, mac ? 'Command' : 'Win'); }
  catch { return value; }
}
export type RecordedKey = { kind: 'wait' | 'cancel' } | { kind: 'key'; value: string } | { kind: 'error'; message: string };
export function recordedMouseShortcut(event: Pick<MouseEvent, 'button' | 'ctrlKey' | 'altKey' | 'shiftKey' | 'metaKey'>, mac = false, windows = isWindows()): RecordedKey | null {
  if (event.button !== 3 && event.button !== 4) return null;
  const modifiers = [event.ctrlKey ? 'Ctrl' : '', event.altKey ? 'Alt' : '', event.shiftKey ? 'Shift' : '', event.metaKey ? 'Super' : ''].filter(Boolean);
  try {
    return { kind: 'key', value: normalizeShortcut([...modifiers, event.button === 3 ? 'MouseX1' : 'MouseX2'].join('+'), mac, windows) };
  } catch (error) {
    return { kind: 'error', message: error instanceof Error ? error.message : '无法录制鼠标侧键。' };
  }
}
export function recordedShortcut(event: Pick<KeyboardEvent, 'key' | 'code' | 'ctrlKey' | 'altKey' | 'shiftKey' | 'metaKey' | 'repeat' | 'isComposing' | 'keyCode'> & { getModifierState?: (key: string) => boolean }, mac = false, windows = isWindows()): RecordedKey {
  if (event.isComposing || event.keyCode === 229 || ['Process', 'Dead', 'Unidentified'].includes(event.key)) return { kind: 'error', message: '请先结束输入法组合，再录制快捷键。' };
  if (event.repeat) return { kind: 'wait' };
  if (event.key === 'Escape' && !event.ctrlKey && !event.altKey && !event.shiftKey && !event.metaKey) return { kind: 'cancel' };
  if (['Control', 'Alt', 'Shift', 'Meta', 'OS', 'AltGraph'].includes(event.key)) return { kind: 'wait' };
  if (event.getModifierState?.('AltGraph')) return { kind: 'error', message: '请使用 Ctrl、Alt 或 Win/Command，不使用 AltGr 录制。' };
  const mods = [event.ctrlKey ? 'Ctrl' : '', event.altKey ? 'Alt' : '', event.shiftKey ? 'Shift' : '', event.metaKey ? 'Super' : ''].filter(Boolean);
  const key = /^(?:Key[A-Z]|Digit[0-9]|Numpad[A-Za-z0-9]+)$/.test(event.code) ? event.code : event.key === ' ' ? 'Space' : event.key;
  try { return { kind: 'key', value: normalizeShortcut([...mods, key].join('+'), mac, windows) }; }
  catch (error) { return { kind: 'error', message: error instanceof Error ? error.message : '该组合无法录制，请直接填写。' }; }
}
