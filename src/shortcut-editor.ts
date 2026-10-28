import { displayShortcut, normalizeShortcut, normalizeShortcuts, recordedShortcut } from './shortcuts';
import type { ShortcutAction } from './types';

type Bindings = Record<ShortcutAction, string>;
interface Context {
  form: HTMLFormElement;
  saveButton: HTMLButtonElement;
  mac: boolean;
  desktop: boolean;
  canRecord(): boolean;
  begin(): Promise<number>;
  end(id: number): Promise<void>;
  save(values: Bindings): Promise<void>;
  error(error: unknown): string;
  changed(): void;
}
export interface NativeRecordedShortcut { leaseId: number; shortcut: string; modifiersDown: number | null }
interface Session { id: number; action: ShortcutAction; held: Set<string>; modifiers: boolean; modifierEvidence: boolean; releasedEvidence: boolean; candidate: string | null; cancelled: boolean }
const core = [['selection', '选词翻译', '在其他应用中选中文字后翻译。'], ['silentOcr', '无感 OCR', '拖选屏幕区域，识别后自动翻译。']] as const;
const extra = [['capture', '截图翻译'], ['ocr', '截图识别'], ['input', '输入翻译']] as const;

// A registered main key can consume DOM events. Reconcile only modifier
// entries whose released state is known; unrelated held keys remain strict.
function clearReleasedModifiers(held: Set<string>, mask: number) {
  for (const [bit, keys] of [
    [1, ['Control', 'ControlLeft', 'ControlRight']],
    [2, ['Alt', 'AltLeft', 'AltRight', 'AltGraph']],
    [4, ['Shift', 'ShiftLeft', 'ShiftRight']],
    [8, ['Meta', 'MetaLeft', 'MetaRight', 'OS', 'OSLeft', 'OSRight']],
  ] as const) if (!(mask & bit)) for (const key of keys) held.delete(key);
}

export function createShortcutEditor(context: Context) {
  const { form, saveButton, mac } = context;
  let revision = 0, starting = false, ending = false, saving = false, ready = false;
  let session: Session | null = null, base = '', timer: ReturnType<typeof setTimeout> | undefined;
  const inputs = new Map<ShortcutAction, HTMLInputElement>(), buttons = new Map<ShortcutAction, HTMLButtonElement>();
  const jump = document.createElement('button'); jump.type = 'button'; jump.className = 'secondary-button'; jump.textContent = '快捷键设置';
  jump.addEventListener('click', () => { const input = inputs.get('selection'); input?.scrollIntoView({ block: 'center' }); input?.focus({ preventScroll: true }); });
  document.querySelector('#view-settings .section-heading')?.append(jump);
  const feedback = document.createElement('p'); feedback.className = 'shortcut-feedback'; feedback.id = 'shortcut-feedback';
  feedback.setAttribute('role', 'status'); feedback.setAttribute('aria-live', 'polite');
  saveButton.textContent = '保存并立即生效';
  const help = form.nextElementSibling;
  if (help instanceof HTMLElement) help.textContent = '直接填写组合，或点击“录制”后按键。使用 Ctrl、Alt 或 Win/Command 搭配一个按键；F1–F24 可单独使用。Esc 取消录制，留空禁用。系统保留或被占用的组合会拒绝保存，原绑定会保留。';
  const intro = form.closest('.settings-card')?.querySelector('.settings-card-heading p');
  if (intro) intro.textContent = '自定义选词翻译与无感 OCR 的全局快捷键。';
  form.addEventListener('submit', (event) => event.preventDefault());
  const status = (message: string, error = false) => {
    feedback.textContent = message; feedback.dataset.error = String(error); context.changed();
  };
  const updateControls = () => {
    const busy = starting || ending || session !== null || saving;
    saveButton.disabled = !ready || busy;
    for (const input of inputs.values()) input.readOnly = busy;
    for (const [action, button] of buttons) {
      button.disabled = !ready || starting || ending || saving || (busy && session?.action !== action);
      button.textContent = session?.action === action ? '取消录制' : '录制';
      button.setAttribute('aria-pressed', String(session?.action === action));
    }
  };
  const finish = async (cancel = true) => {
    const intent = ++revision;
    if (timer) clearTimeout(timer); timer = undefined;
    const previous = session; session = null;
    if (!previous) { updateControls(); return; }
    ending = true; updateControls();
    try {
      await context.end(previous.id);
      if (intent !== revision || !context.canRecord()) return;
      if (!cancel && previous.candidate && !previous.cancelled) {
        inputs.get(previous.action)!.value = displayShortcut(previous.candidate, mac);
        status('已录入，点击“保存并立即生效”应用。');
      } else status('录制已取消，原输入未更改。');
    } catch (error) { if (intent === revision && context.canRecord()) status(`录制结束失败：${context.error(error)}。录制保护会自动到期。`, true); }
    finally { ending = false; updateControls(); }
  };
  const start = async (action: ShortcutAction) => {
    if (!ready || saving || starting || ending) return;
    if (session) { await finish(true); return; }
    const intent = ++revision; starting = true; updateControls(); status('正在准备录制，请稍候…');
    const requestedAt = performance.now();
    try {
      const id = await context.begin();
      if (intent !== revision || !context.canRecord()) { await context.end(id); return; }
      const remaining = 14_000 - (performance.now() - requestedAt);
      if (remaining <= 0) { await context.end(id); status('录制准备已超时，请重试。', true); return; }
      session = { id, action, held: new Set(), modifiers: false, modifierEvidence: false, releasedEvidence: false, candidate: null, cancelled: false };
      inputs.get(action)?.focus({ preventScroll: true });
      status('请按快捷键并松开所有按键；Esc 取消。15 秒后自动结束。');
      timer = setTimeout(() => { void finish(true); }, remaining);
    } catch (error) { status(`无法开始录制：${context.error(error)}`, true); }
    finally { starting = false; updateControls(); }
  };
  const keyDown = (event: KeyboardEvent) => {
    if (!session && !starting && !ending) return;
    event.preventDefault(); event.stopImmediatePropagation();
    if (!session) { if (event.key === 'Escape') revision++; return; }
    session.held.add(event.code || event.key);
    session.modifiers = event.ctrlKey || event.altKey || event.shiftKey || event.metaKey;
    session.modifierEvidence = true; session.releasedEvidence = false;
    if (event.key === 'Escape') { session.cancelled = true; status('已取消，请松开按键。'); return; }
    if (session.cancelled || session.candidate) return;
    const value = recordedShortcut(event, mac);
    if (value.kind === 'cancel') { session.cancelled = true; status('已取消，请松开按键。'); }
    else if (value.kind === 'key') { session.candidate = value.value; status(`已记录 ${displayShortcut(value.value, mac)}，请松开所有按键。`); }
    else if (value.kind === 'error') status(value.message, true);
    else if (!event.repeat) status('继续按一个普通按键；Esc 取消录制。');
  };
  const keyUp = (event: KeyboardEvent) => {
    if (!session && !starting && !ending) return;
    event.preventDefault(); event.stopImmediatePropagation();
    if (!session) return;
    session.held.delete(event.code || event.key);
    session.modifiers = event.ctrlKey || event.altKey || event.shiftKey || event.metaKey;
    clearReleasedModifiers(session.held, (event.ctrlKey ? 1 : 0) | (event.altKey ? 2 : 0) | (event.shiftKey ? 4 : 0) | (event.metaKey ? 8 : 0));
    session.modifierEvidence = true; session.releasedEvidence = !session.modifiers;
    if ((session.candidate || session.cancelled) && session.held.size === 0 && !session.modifiers) void finish(session.cancelled);
  };
  document.addEventListener('keydown', keyDown, true); document.addEventListener('keyup', keyUp, true);
  const receiveNative = (value: NativeRecordedShortcut) => {
    if (!session || starting || ending || session.cancelled || !context.canRecord() || value?.leaseId !== session.id) return;
    if (typeof value.shortcut !== 'string' || !(value.modifiersDown === null || (Number.isInteger(value.modifiersDown) && value.modifiersDown >= 0 && value.modifiersDown <= 15))) return;
    let candidate: string;
    try { candidate = normalizeShortcut(value.shortcut, mac); } catch { return; }
    if (!candidate || (session.candidate !== null && session.candidate !== candidate)) return;
    session.candidate = candidate;
    // RegisterHotKey can consume the main key's DOM down/up. Its native
    // release supplies that key; a non-null physical modifier snapshot can
    // also clear stale DOM modifier downs. Later DOM release evidence wins
    // over an older native snapshot which still said a modifier was held.
    const key = candidate.split('+').at(-1)!;
    session.held.delete(key); session.held.delete(key.length === 1 ? (/^[A-Z]$/.test(key) ? `Key${key}` : `Digit${key}`) : key);
    if (!session.releasedEvidence) {
      if (value.modifiersDown !== null) {
        session.modifiers = value.modifiersDown !== 0; session.modifierEvidence = true;
        clearReleasedModifiers(session.held, value.modifiersDown);
      }
    } else clearReleasedModifiers(session.held, 0);
    status(`已记录 ${displayShortcut(candidate, mac)}，请松开所有按键。`);
    if (session.modifierEvidence && !session.modifiers && session.held.size === 0) void finish(false);
  };
  const leave = () => { revision++; void finish(true); };
  window.addEventListener('blur', leave);
  const visibility = () => { if (document.hidden) leave(); };
  document.addEventListener('visibilitychange', visibility);
  const save = async () => {
    if (!ready || saving || starting || ending || session) return;
    try {
      const values = normalizeShortcuts(Object.fromEntries([...inputs].map(([action, input]) => [action, input.value])) as Bindings, mac);
      saving = true; updateControls(); status('正在保存快捷键…');
      await context.save(values);
      status(context.desktop ? '快捷键已保存并立即生效；下次启动继续使用。' : '已在界面预览中更新；桌面应用才能注册全局快捷键。');
    } catch (error) { status(`未完成保存：${context.error(error)}`, true); }
    finally { saving = false; updateControls(); }
  };
  saveButton.addEventListener('click', () => { void save(); });
  const row = (action: ShortcutAction, label: string, description = '', record = false) => {
    const element = document.createElement('div'); element.className = 'shortcut-binding';
    const copy = document.createElement('label'); copy.htmlFor = `shortcut-${action}`; copy.textContent = label;
    if (description) { const small = document.createElement('small'); small.textContent = description; copy.append(small); }
    const control = document.createElement('div'); control.className = 'shortcut-binding-control';
    const input = document.createElement('input'); input.id = `shortcut-${action}`; input.name = action;
    input.type = 'text'; input.maxLength = 80; input.autocomplete = 'off'; input.spellcheck = false;
    input.placeholder = '留空禁用'; input.setAttribute('aria-label', `${label}快捷键`); inputs.set(action, input); control.append(input);
    if (record) {
      const button = document.createElement('button'); button.type = 'button'; button.className = 'secondary-button shortcut-record';
      button.dataset.shortcutRecord = action; button.setAttribute('aria-label', `录制${label}快捷键`);
      button.addEventListener('click', () => { void start(action); }); buttons.set(action, button); control.append(button);
    }
    element.append(copy, control); return element;
  };
  return {
    receiveNative,
    render(values: Bindings, loaded: boolean) {
      ready = loaded;
      const key = JSON.stringify(values);
      if (key !== base || inputs.size === 0) {
        if (session || starting) leave();
        const open = form.querySelector('details')?.open ?? false;
        form.replaceChildren(); inputs.clear(); buttons.clear();
        for (const [action, label, description] of core) form.append(row(action, label, description, true));
        const details = document.createElement('details'); details.id = 'shortcut-advanced'; details.className = 'shortcut-advanced'; details.open = open;
        const summary = document.createElement('summary'); summary.textContent = '其他快捷键'; details.append(summary);
        for (const [action, label] of extra) details.append(row(action, label));
        details.addEventListener('toggle', context.changed); form.append(details, feedback);
        for (const [action, input] of inputs) input.value = displayShortcut(values[action], mac);
        base = key;
      }
      updateControls();
    },
    leave,
    dispose() {
      leave(); jump.remove(); document.removeEventListener('keydown', keyDown, true); document.removeEventListener('keyup', keyUp, true);
      window.removeEventListener('blur', leave); document.removeEventListener('visibilitychange', visibility);
    },
  };
}
