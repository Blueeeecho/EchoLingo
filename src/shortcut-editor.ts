import { displayShortcut, normalizeShortcut, normalizeShortcuts, recordedMouseShortcut, recordedShortcut } from './shortcuts';
import type { ShortcutAction, ShortcutRegistration } from './types';

type Bindings = Record<ShortcutAction, string>;
interface Context {
  form: HTMLFormElement;
  saveButton: HTMLButtonElement;
  mac: boolean;
  desktop: boolean;
  canRecord(): boolean;
  begin(): Promise<number>;
  end(id: number): Promise<void>;
  save(values: Bindings, canCommit?: () => boolean, retryActions?: ShortcutAction[]): Promise<void>;
  error(error: unknown): string;
  changed(): void;
}
export interface NativeRecordedShortcut { leaseId: number; shortcut: string; modifiersDown: number | null }
interface Session { id: number; action: ShortcutAction; held: Set<string>; modifiers: boolean; modifierEvidence: boolean; releasedEvidence: boolean; candidate: string | null; cancelled: boolean }
const core = [['selection', '选词翻译', '在其他应用中选中文字后翻译。'], ['silentOcr', '无感 OCR', '拖选屏幕区域，识别后自动翻译。']] as const;
const extra = [['capture', '截图翻译'], ['ocr', '截图识别'], ['input', '输入翻译']] as const;
const actions: ShortcutAction[] = ['selection', 'silentOcr', 'capture', 'ocr', 'input'];
const bindingsKey = (values: Bindings) => JSON.stringify(actions.map((action) => values[action]));

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
  const windows = !mac && /Win/i.test(navigator.platform);
  let revision = 0, starting = false, ending = false, saving = false, ready = false;
  let session: Session | null = null, base = '', timer: ReturnType<typeof setTimeout> | undefined;
  let persisted: Bindings | null = null, pendingSave: { values: string; intent: number | null } | null = null;
  const heldMouseButtons = new Set<number>(), auxclickButtons = new Set<number>();
  let auxclickTimer: ReturnType<typeof setTimeout> | undefined;
  const inputs = new Map<ShortcutAction, HTMLInputElement>(), buttons = new Map<ShortcutAction, HTMLButtonElement>();
  const registrationNotes = new Map<ShortcutAction, HTMLElement>();
  const jump = document.createElement('button'); jump.type = 'button'; jump.className = 'secondary-button'; jump.textContent = '快捷键设置';
  jump.addEventListener('click', () => { const input = inputs.get('selection'); input?.scrollIntoView({ block: 'center' }); input?.focus({ preventScroll: true }); });
  document.querySelector('#view-settings .section-heading')?.append(jump);
  const feedback = document.createElement('p'); feedback.className = 'shortcut-feedback'; feedback.id = 'shortcut-feedback';
  feedback.setAttribute('role', 'status'); feedback.setAttribute('aria-live', 'polite');
  saveButton.textContent = '保存并立即生效';
  const help = form.nextElementSibling;
  if (help instanceof HTMLElement) help.textContent = '录制后松开所有按键即可自动保存并生效。直接填写的修改请点击保存，留空可禁用。Esc 取消录制。' + (windows
    ? 'Alt+D、Alt+S 在应用运行时优先处理；退出后恢复原用途。也可录制鼠标侧键：MouseX1（后退）、MouseX2（前进）。其他键盘组合若被占用会保留原绑定，请更换该行。'
    : '使用 Ctrl、Alt 或 Command 搭配一个按键；F1–F24 可单独使用。系统保留或被占用的组合会拒绝保存，原绑定会保留。');
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
  const draftValues = (): Bindings => Object.fromEntries([...inputs].map(([action, input]) => [action, input.value])) as Bindings;
  const hasDrafts = () => persisted !== null && [...inputs].some(([action, input]) => input.value !== displayShortcut(persisted![action], mac));
  const persist = async (values: Bindings, intent: number | null = null, recordedAction?: ShortcutAction) => {
    const current = () => intent === null || (intent === revision && context.canRecord());
    if (!current()) return;
    saving = true; const operation = { values: bindingsKey(values), intent }; pendingSave = operation;
    updateControls(); status(intent === null ? '正在保存快捷键…' : '正在自动保存快捷键…');
    try {
      await context.save(values, intent === null ? undefined : current, recordedAction ? [recordedAction] : actions);
      if (!current()) return;
      const message = context.desktop ? '快捷键已保存并立即生效；下次启动继续使用。' : '已在界面预览中更新；桌面应用才能注册全局快捷键。';
      status(message + (intent !== null && hasDrafts() ? '其他手动修改仍待保存。' : ''));
    } catch (error) {
      if (current()) status(`未完成保存：${context.error(error)}`, true);
    } finally {
      if (pendingSave === operation) pendingSave = null;
      saving = false; updateControls();
    }
  };
  const finish = async (cancel = true) => {
    const intent = ++revision;
    if (timer) clearTimeout(timer); timer = undefined;
    const previous = session; session = null;
    if (!previous) { updateControls(); return; }
    if (!cancel) heldMouseButtons.clear();
    ending = true; updateControls();
    try {
      await context.end(previous.id);
      if (intent !== revision || !context.canRecord()) return;
      if (!cancel && previous.candidate && !previous.cancelled) {
        inputs.get(previous.action)!.value = displayShortcut(previous.candidate, mac);
        // Recording commits exactly this field over the latest accepted
        // bindings. Other manual inputs stay drafts, including invalid text.
        if (!persisted) return;
        let values: Bindings;
        try { values = normalizeShortcuts({ ...persisted, [previous.action]: previous.candidate }, mac); }
        catch (error) { status(`未完成保存：${context.error(error)}`, true); return; }
        await persist(values, intent, previous.action);
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
  const sideButton = (event: MouseEvent) => event.button === 3 || event.button === 4;
  const blockMouseEvent = (event: MouseEvent) => { event.preventDefault(); event.stopImmediatePropagation(); };
  const pointerDown = (event: PointerEvent) => {
    if (!sideButton(event)) return;
    if (!session && !starting && !ending) { heldMouseButtons.delete(event.button); return; }
    blockMouseEvent(event);
    if (!session) return;
    heldMouseButtons.add(event.button);
    session.held.add(event.button === 3 ? 'MouseX1' : 'MouseX2');
    session.modifiers = event.ctrlKey || event.altKey || event.shiftKey || event.metaKey;
    session.modifierEvidence = true; session.releasedEvidence = false;
    if (session.cancelled || session.candidate) return;
    const value = recordedMouseShortcut(event, mac);
    if (value?.kind === 'key') { session.candidate = value.value; status(`已记录 ${displayShortcut(value.value, mac)}，请松开所有按键。`); }
    else if (value?.kind === 'error') status(value.message, true);
  };
  const pointerUp = (event: PointerEvent) => {
    if (!sideButton(event) || (!session && !starting && !ending && !heldMouseButtons.has(event.button))) return;
    blockMouseEvent(event); heldMouseButtons.delete(event.button);
    // Browsers emit auxclick after pointerup. Preserve only this event-turn's
    // consumed side-button release, even if a fast save has already completed.
    auxclickButtons.add(event.button);
    if (auxclickTimer) clearTimeout(auxclickTimer);
    auxclickTimer = setTimeout(() => { auxclickButtons.clear(); auxclickTimer = undefined; }, 0);
    if (!session) return;
    session.held.delete(event.button === 3 ? 'MouseX1' : 'MouseX2');
    session.modifiers = event.ctrlKey || event.altKey || event.shiftKey || event.metaKey;
    clearReleasedModifiers(session.held, (event.ctrlKey ? 1 : 0) | (event.altKey ? 2 : 0) | (event.shiftKey ? 4 : 0) | (event.metaKey ? 8 : 0));
    session.modifierEvidence = true; session.releasedEvidence = !session.modifiers;
    if ((session.candidate || session.cancelled) && session.held.size === 0 && !session.modifiers) void finish(session.cancelled);
  };
  const auxclick = (event: MouseEvent) => {
    if (sideButton(event) && (session || starting || ending || auxclickButtons.has(event.button))) {
      blockMouseEvent(event); auxclickButtons.delete(event.button);
    }
  };
  document.addEventListener('pointerdown', pointerDown, true); document.addEventListener('pointerup', pointerUp, true);
  document.addEventListener('auxclick', auxclick, true);
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
  const leave = () => {
    const automaticSavePending = pendingSave !== null && pendingSave.intent !== null;
    revision++; void finish(true);
    if (automaticSavePending) status('录制已结束。未保存的输入可点击保存。');
  };
  window.addEventListener('blur', leave);
  const visibility = () => { if (document.hidden) leave(); };
  document.addEventListener('visibilitychange', visibility);
  const save = async () => {
    if (!ready || saving || starting || ending || session) return;
    try {
      await persist(normalizeShortcuts(draftValues(), mac));
    } catch (error) { status(`未完成保存：${context.error(error)}`, true); }
  };
  saveButton.addEventListener('click', () => { void save(); });
  const row = (action: ShortcutAction, label: string, description = '', record = false) => {
    const element = document.createElement('div'); element.className = 'shortcut-binding';
    const copy = document.createElement('label'); copy.htmlFor = `shortcut-${action}`; copy.textContent = label;
    if (description) { const small = document.createElement('small'); small.textContent = description; copy.append(small); }
    const note = document.createElement('small'); note.hidden = true; note.className = 'shortcut-registration';
    note.dataset.shortcutStatus = action; registrationNotes.set(action, note); copy.append(note);
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
    render(values: Bindings, loaded: boolean, registrations?: ShortcutRegistration[]) {
      ready = loaded;
      const key = bindingsKey(values);
      if (key !== base || inputs.size === 0) {
        const drafts = new Map<ShortcutAction, string>();
        const acceptedManualSave = pendingSave?.intent === null && pendingSave.values === key;
        if (persisted && !acceptedManualSave) for (const [action, input] of inputs) {
          if (input.value !== displayShortcut(persisted[action], mac)) drafts.set(action, input.value);
        }
        if (session || starting) leave();
        // An unrelated accepted binding update supersedes an automatic save
        // still queued behind other settings work. Our own accepted values do
        // not cancel their completion status or discard other manual drafts.
        if (pendingSave && pendingSave.intent !== null && pendingSave.values !== key) {
          revision++; status('快捷键配置已更新；录制的输入尚未保存。');
        }
        const open = form.querySelector('details')?.open ?? false;
        form.replaceChildren(); inputs.clear(); buttons.clear(); registrationNotes.clear();
        for (const [action, label, description] of core) form.append(row(action, label, description, true));
        const details = document.createElement('details'); details.id = 'shortcut-advanced'; details.className = 'shortcut-advanced'; details.open = open;
        const summary = document.createElement('summary'); summary.textContent = '其他快捷键'; details.append(summary);
        for (const [action, label] of extra) details.append(row(action, label));
        details.addEventListener('toggle', context.changed); form.append(details, feedback);
        for (const [action, input] of inputs) input.value = drafts.get(action) ?? displayShortcut(values[action], mac);
        base = key;
      }
      persisted = { ...values };
      for (const [action, note] of registrationNotes) {
        const state = registrations?.find((item) => item.action === action && (!item.combo || item.combo === values[action]));
        note.hidden = !state || !values[action];
        note.dataset.error = String(state?.active === false);
        note.textContent = state ? (state.active
          ? (windows && ['Alt+D', 'Alt+S'].includes(values[action]) ? `优先处理：${values[action]}（应用运行时）` : `已启用：${displayShortcut(values[action], mac)}`)
          : `未启用：${state.error || '请重新录制或更换此按键。'}`) : '';
      }
      updateControls();
    },
    leave,
    dispose() {
      leave(); jump.remove(); document.removeEventListener('keydown', keyDown, true); document.removeEventListener('keyup', keyUp, true);
      document.removeEventListener('pointerdown', pointerDown, true); document.removeEventListener('pointerup', pointerUp, true); document.removeEventListener('auxclick', auxclick, true);
      if (auxclickTimer) clearTimeout(auxclickTimer); auxclickButtons.clear();
      window.removeEventListener('blur', leave); document.removeEventListener('visibilitychange', visibility);
    },
  };
}
