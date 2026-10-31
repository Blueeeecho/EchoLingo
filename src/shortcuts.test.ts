import { defaultSettings } from './model';
import { describe, expect, it, vi } from 'vitest';
import { displayShortcut, normalizeShortcut, normalizeShortcuts, recordedShortcut, recordedMouseShortcut } from './shortcuts';
const keys = { selection: 'Alt+D', silentOcr: 'Alt+S', capture: '', ocr: 'Alt+Shift+S', input: 'Alt+A', screenshot: 'F1' };
const event = (values: Partial<KeyboardEvent> = {}): Parameters<typeof recordedShortcut>[0] => ({ key: 't', code: 'KeyT', ctrlKey: true, altKey: false, shiftKey: false, metaKey: false, repeat: false, isComposing: false, keyCode: 84, ...values });
describe('shortcut configuration', () => {
  it('defaults to F1 screenshot editing while preserving Alt+D and silent Alt+S on both platforms', () => {
    for (const mac of [false, true]) {
      const settings = defaultSettings();
      expect(settings.shortcutDefaultsVersion).toBe(2);
      const defaults = normalizeShortcuts(settings.shortcuts, mac, !mac);
      expect(Object.values(defaults).filter(Boolean)).toEqual(['Alt+D', 'Alt+S', 'F1']);
      const changed = normalizeShortcuts({ ...defaults, selection: 'Ctrl+Alt+T', silentOcr: 'Ctrl+Alt+R', input: 'Alt+A', ocr: 'Alt+Shift+S' }, mac, !mac);
      expect(changed.input).toBe('Alt+A');
      expect(changed.ocr).toBe('Alt+Shift+S');
      expect(normalizeShortcuts({ ...changed, selection: '', silentOcr: '' }, mac, !mac).selection).toBe('');
      expect(() => normalizeShortcuts({ ...changed, input: changed.selection }, mac, !mac)).toThrow();
    }
  });

  it('accepts opt-in unmodified Windows side buttons and rejects cross-platform or modified bindings', () => {
    expect(normalizeShortcut('xbutton1', false, true)).toBe('MouseX1');
    expect(normalizeShortcut('MouseForward', false, true)).toBe('MouseX2');
    expect(normalizeShortcuts({ ...keys, selection: 'MouseX1', silentOcr: 'MouseX2' }, false, true).selection).toBe('MouseX1');
    expect(() => normalizeShortcuts({ ...keys, selection: 'MouseX1', silentOcr: 'XButton1' }, false, true)).toThrow('相同');
    for (const key of ['MouseX1', 'MouseX2']) {
      expect(() => normalizeShortcut(key, true, false)).toThrow('Windows');
      expect(() => normalizeShortcut(key, false, false)).toThrow('Windows');
      expect(() => normalizeShortcut('Ctrl+' + key, false, true)).toThrow('单独');
    }
  });
  it('records only the two side buttons while leaving normal pointer controls alone', () => {
    const mouse = { button: 3, ctrlKey: false, altKey: false, shiftKey: false, metaKey: false };
    expect(recordedMouseShortcut(mouse, false, true)).toEqual({ kind: 'key', value: 'MouseX1' });
    expect(recordedMouseShortcut({ ...mouse, button: 4 }, false, true)).toEqual({ kind: 'key', value: 'MouseX2' });
    for (const button of [0, 1, 2, 5]) expect(recordedMouseShortcut({ ...mouse, button }, false, true)).toBeNull();
    expect(recordedMouseShortcut({ ...mouse, ctrlKey: true }, false, true)?.kind).toBe('error');
    expect(recordedMouseShortcut(mouse, true, false)?.kind).toBe('error');
  });
  it('canonicalizes aliases and modifier order without changing the physical key', () => {
    expect(normalizeShortcut(' shift + control + KeyT ')).toBe('Ctrl+Shift+T');
    expect(normalizeShortcut('Windows+Digit2')).toBe('Super+2');
    expect(normalizeShortcut('CmdOrCtrl+T', true)).toBe('Super+T');
    expect(normalizeShortcut('CmdOrCtrl+T', false)).toBe('Ctrl+T');
    expect(displayShortcut('Super+T', false)).toBe('Win+T');
    expect(displayShortcut('Super+T', true)).toBe('Command+T');
    expect(normalizeShortcut('Ctrl+Numpad1')).not.toBe(normalizeShortcut('Ctrl+1'));
  });
  it('allows disabling and function keys, rejects text-typing combinations and malformed values', () => {
    expect(normalizeShortcut(' ')).toBe('');
    for (let n = 1; n <= 24; n++) expect(normalizeShortcut(`F${n}`)).toBe(`F${n}`);
    for (const value of ['T', 'Shift+T', 'Ctrl', 'Ctrl+Control+T', 'Ctrl+T+Q', 'Ctrl++', 'F25', 'Alt+🍎', '\nAlt+S', 'Alt+S\0', ' '.repeat(81)]) expect(() => normalizeShortcut(value), value).toThrow();
  });
  it('finds aliases and advanced-binding conflicts while allowing multiple empty bindings', () => {
    expect(() => normalizeShortcuts({ ...keys, selection: 'Win+T', capture: 'meta+t' })).toThrow('相同');
    expect(normalizeShortcuts({ ...keys, selection: '', capture: '' }).selection).toBe('');
  });
  it('rejects Windows NumpadEqual in typed and recorded input without changing macOS or other platforms', () => {
    const message = 'Windows 暂不支持小键盘等号键，请选择其他按键。';
    expect(() => normalizeShortcut('control+numpadequal', false, true)).toThrow(message);
    for (const action of ['selection', 'silentOcr', 'screenshot', 'capture', 'ocr', 'input'] as const) {
      expect(() => normalizeShortcuts({ ...keys, [action]: 'Ctrl+NumpadEqual' }, false, true)).toThrow(message);
    }
    const keypad = event({ key: '=', code: 'NumpadEqual' });
    expect(recordedShortcut(keypad, false, true)).toEqual({ kind: 'error', message });
    expect(normalizeShortcut('Ctrl+NumpadEqual', true, false)).toBe('Ctrl+NumpadEqual');
    expect(recordedShortcut(keypad, true, false)).toEqual({ kind: 'key', value: 'Ctrl+NumpadEqual' });
    expect(normalizeShortcut('Ctrl+NumpadEqual', false, false)).toBe('Ctrl+NumpadEqual');
  });
  it('keeps ordinary E, equals and function keys available on Windows', () => {
    for (const value of ['Ctrl+E', 'Ctrl+Equal', 'Ctrl+Numpad1', 'Alt+D', 'Alt+S']) {
      expect(normalizeShortcut(value, false, true)).toBe(value);
    }
    for (let n = 1; n <= 24; n++) expect(normalizeShortcut(`F${n}`, false, true)).toBe(`F${n}`);
    // Windows F12 reservation is still checked by the backend before registration.
    expect(recordedShortcut(event({ key: 'e', code: 'KeyE' }), false, true)).toEqual({ kind: 'key', value: 'Ctrl+E' });
  });
  it('applies the Windows restriction through the default browser platform path only', () => {
    try {
      vi.stubGlobal('navigator', { platform: 'Win32' });
      expect(() => normalizeShortcuts({ ...keys, silentOcr: 'Ctrl+NumpadEqual' })).toThrow('Windows 暂不支持');
      expect(recordedShortcut(event({ key: '=', code: 'NumpadEqual' })).kind).toBe('error');
      vi.stubGlobal('navigator', { platform: 'MacIntel' });
      expect(normalizeShortcut('Ctrl+NumpadEqual', true)).toBe('Ctrl+NumpadEqual');
      vi.stubGlobal('navigator', { platform: 'Linux x86_64' });
      expect(normalizeShortcut('Ctrl+NumpadEqual')).toBe('Ctrl+NumpadEqual');
    } finally { vi.unstubAllGlobals(); }
  });
  it('never commits repeats, IME confirmations or modifier-only events', () => {
    expect(recordedShortcut(event())).toEqual({ kind: 'key', value: 'Ctrl+T' });
    expect(recordedShortcut(event({ key: 'T', shiftKey: true }))).toEqual({ kind: 'key', value: 'Ctrl+Shift+T' });
    expect(recordedShortcut(event({ repeat: true })).kind).toBe('wait');
    expect(recordedShortcut(event({ key: 'Control', code: 'ControlLeft' })).kind).toBe('wait');
    expect(recordedShortcut(event({ isComposing: true })).kind).toBe('error');
    expect(recordedShortcut(event({ keyCode: 229 })).kind).toBe('error');
    expect(recordedShortcut(event({ key: 'Process' })).kind).toBe('error');
    expect(recordedShortcut(event({ getModifierState: () => true } as Partial<KeyboardEvent>)).kind).toBe('error');
  });
  it('treats plain Escape as cancellation but allows an explicit modified Escape binding', () => {
    expect(recordedShortcut(event({ key: 'Escape', code: 'Escape', ctrlKey: false }))).toEqual({ kind: 'cancel' });
    expect(recordedShortcut(event({ key: 'Escape', code: 'Escape' }))).toEqual({ kind: 'key', value: 'Ctrl+Escape' });
  });
});
