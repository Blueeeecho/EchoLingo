import { describe, expect, it } from 'vitest';
import { displayShortcut, normalizeShortcut, normalizeShortcuts, recordedShortcut } from './shortcuts';
const keys = { selection: 'Alt+D', silentOcr: 'Alt+S', capture: '', ocr: 'Alt+Shift+S', input: 'Alt+A' };
const event = (values: Partial<KeyboardEvent> = {}): Parameters<typeof recordedShortcut>[0] => ({ key: 't', code: 'KeyT', ctrlKey: true, altKey: false, shiftKey: false, metaKey: false, repeat: false, isComposing: false, keyCode: 84, ...values });
describe('shortcut configuration', () => {
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
