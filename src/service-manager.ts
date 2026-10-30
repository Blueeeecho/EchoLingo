import type { Settings } from './types';
import { credentialStatusLabel } from './credential-state';
import { isLocalProvider } from './model';

export type ServiceRole = 'translation' | 'ocr';
type Operation = 'edit' | 'remove';
interface Context {
  settings: () => Settings;
  ready: () => boolean;
  add: (role: ServiceRole) => void;
  operate: (role: ServiceRole, id: string, operation: Operation) => void;
  test: (role: ServiceRole, id: string) => Promise<void>;
  enable: (role: ServiceRole, id: string, enabled: boolean) => Promise<void>;
  recommend: (role: ServiceRole) => void;
  reportError: (error: unknown) => void;
}
interface Item { id: string; name: string; kind: string; endpoint: string; model: string; local: boolean; active: boolean; credential: string }
const element = <K extends keyof HTMLElementTagNameMap>(tag: K, className = '', text = ''): HTMLElementTagNameMap[K] => {
  const node = document.createElement(tag); node.className = className; node.textContent = text; return node;
};
export function installServiceManager(context: Context): { render: () => void } {
  const root = document.querySelector<HTMLElement>('#service-manager')!;
  const list = document.querySelector<HTMLUListElement>('#managed-service-list')!;
  const detail = document.querySelector<HTMLElement>('#managed-service-detail')!;
  const add = document.querySelector<HTMLButtonElement>('#managed-service-add')!;
  let role: ServiceRole = 'translation';
  const selected: Record<ServiceRole, string | null> = { translation: null, ocr: null };
  let pending = false;
  const items = (): Item[] => role === 'translation' ? context.settings().providers.map(p => ({ id: p.id, name: p.name, kind: p.kind,
    endpoint: p.baseUrl, model: p.model, local: isLocalProvider(p.kind), active: p.enabled, credential: isLocalProvider(p.kind) ? '内置 · 无需密钥' : credentialStatusLabel(p) }))
    : [{ id: '', name: '本机文字识别', kind: 'local', endpoint: '', model: '', local: true, active: !context.settings().activeOcrProviderId, credential: '内置 · 无需密钥' },
      ...context.settings().ocrProviders.map(p => ({ id: p.id, name: p.name, kind: p.kind, endpoint: p.baseUrl, model: p.model, local: false,
        active: p.id === context.settings().activeOcrProviderId, credential: credentialStatusLabel(p) }))];
  const select = (id: string, focus = false): void => {
    selected[role] = id; root.dataset.detail = 'true'; render();
    if (focus) detail.querySelector<HTMLElement>('h2')?.focus({ preventScroll: true });
  };
  const restoreFocus = (id: string, initiatingRole: ServiceRole, action: string): void => {
    if (root.closest<HTMLElement>('.view')?.hidden || role !== initiatingRole) return;
    if (document.activeElement !== document.body && !root.contains(document.activeElement)) return;
    if (action !== 'list' && detail.getClientRects().length > 0) {
      const target = detail.querySelector<HTMLButtonElement>(`[data-manager-action="${action}"]`);
      if (target && !target.disabled) target.focus({ preventScroll: true });
      else detail.querySelector<HTMLElement>('h2')?.focus({ preventScroll: true });
    } else Array.from(list.querySelectorAll<HTMLInputElement>('input')).find(input => input.dataset.serviceId === id)?.focus({ preventScroll: true });
  };
  const activate = async (item: Item, enabled: boolean): Promise<void> => {
    if (pending || !context.ready()) return;
    const initiatingRole = role, focusAction = list.contains(document.activeElement) ? 'list' : 'enable'; pending = true; render();
    try { await context.enable(initiatingRole, item.id, enabled); }
    catch (error) { context.reportError(error); }
    finally { pending = false; render(); restoreFocus(item.id, initiatingRole, focusAction); }
  };
  const test = async (item: Item): Promise<void> => {
    if (pending || !context.ready()) return;
    const initiatingRole = role; pending = true; render();
    try { await context.test(initiatingRole, item.id); }
    catch (error) { context.reportError(error); }
    finally { pending = false; render(); restoreFocus(item.id, initiatingRole, 'test'); }
  };
  const button = (text: string, action: () => void, className = 'secondary-button'): HTMLButtonElement => {
    const node = element('button', className, text); node.type = 'button'; node.disabled = pending || !context.ready(); node.addEventListener('click', action); return node;
  };
  function render(): void {
    root.setAttribute('aria-busy', String(pending));
    const values = items();
    if (!values.some(item => item.id === selected[role])) selected[role] = values[0]?.id ?? null;
    for (const tab of root.querySelectorAll<HTMLButtonElement>('[data-service-role]')) tab.setAttribute('aria-pressed', String(tab.dataset.serviceRole === role));
    document.querySelector('#managed-service-rule')!.textContent = role === 'translation' ? '翻译服务可同时启用多项；原文会发送给每个已启用的云服务。' : 'OCR 每次只使用一个服务；选择云端后，截图会上传给该服务商。';
    document.querySelector('#managed-service-count')!.textContent = `已添加 ${values.length} 项`;
    add.textContent = role === 'translation' ? '＋ 添加翻译服务' : '＋ 添加 OCR 服务';
    add.disabled = pending || !context.ready() || (role === 'translation' ? values.length : values.length - 1) >= 12;
    list.replaceChildren();
    for (const item of values) {
      const row = element('li', 'managed-service-row'); row.dataset.serviceId = item.id;
      const choose = button('', () => select(item.id, true), 'managed-service-select');
      choose.setAttribute('aria-pressed', String(item.id === selected[role])); choose.setAttribute('aria-controls', 'managed-service-detail');
      choose.append(element('span', 'provider-avatar', item.local ? '本' : item.name.slice(0, 1)));
      const info = element('span', 'managed-service-name'); info.append(element('strong', '', item.name), element('small', '', item.credential)); choose.append(info);
      const label = element('label', 'managed-service-state');
      const control = element('input'); control.type = role === 'translation' ? 'checkbox' : 'radio'; control.name = 'managed-current-ocr'; control.dataset.serviceId = item.id; control.checked = item.active;
      control.disabled = pending || !context.ready(); control.setAttribute('aria-label', role === 'translation' ? `启用 ${item.name}` : `使用 ${item.name}`);
      control.addEventListener('change', () => { void activate(item, control.checked); });
      label.append(control, element('span', '', item.active ? (role === 'translation' ? '已启用' : '当前') : (role === 'translation' ? '未启用' : '选择')));
      row.append(choose, label); list.append(row);
    }
    detail.replaceChildren();
    const current = values.find(item => item.id === selected[role]);
    const back = button('← 返回服务列表', () => {
      root.dataset.detail = 'false';
      const index = values.findIndex(item => item.id === selected[role]);
      list.querySelectorAll<HTMLButtonElement>('.managed-service-select')[index]?.focus({ preventScroll: true });
    }, 'text-button managed-service-back'); detail.append(back);
    if (!current) { detail.append(element('h2', '', '添加你的第一个翻译服务'), element('p', 'field-help', '先添加服务，再配置凭据、测试连接并启用。本机服务无需 API 密钥。')); return; }
    const title = element('h2', '', current.name); title.tabIndex = -1; detail.append(title);
    detail.append(element('p', 'managed-service-status', `${current.local ? '内置服务' : current.credential} · ${current.active ? (role === 'translation' ? '已启用' : '当前 OCR') : '未启用'}`));
    const description = current.local ? '在本机处理，不上传原文或截图。内置服务可切换使用，但不能删除。'
      : role === 'translation' ? '启用后，翻译会发送原文给此服务。多个已启用的翻译服务会并行工作。' : '设为当前后，文字识别会发送截图给此服务；其他 OCR 配置保留但不参与识别。';
    detail.append(element('p', 'field-help', description));
    const facts = element('dl', 'managed-service-facts');
    for (const [name, value] of [['服务协议', current.kind], ['模型 / 接口', current.model || '由服务确定'], ['服务地址', current.endpoint || '本机内置'], ['凭据', current.credential]]) {
      facts.append(element('dt', '', name), element('dd', '', value));
    }
    detail.append(facts, element('p', 'field-help', current.local ? '无需填写密钥；系统翻译如提示缺少语言包，请在高级设置中准备。' : '配置 → 测试连接 → 启用。已保存密钥不会显示；编辑时留空可保留原密钥。测试会发送内置短句或示例图，可能消耗额度。'));
    const actions = element('div', 'managed-service-actions');
    if (!current.local || role === 'translation') {
      const testButton = button(pending ? '处理中…' : current.local ? '测试翻译' : '测试连接', () => { void test(current); }); testButton.dataset.managerAction = 'test'; actions.append(testButton);
      if (!current.local) actions.append(button('编辑配置', () => context.operate(role, current.id, 'edit')));
    }
    actions.append(button(role === 'translation' ? (current.active ? '停用此服务' : '启用此服务') : (current.active ? '当前正在使用' : '设为当前 OCR'), () => { void activate(current, role === 'translation' ? !current.active : true); }));
    (actions.lastChild as HTMLButtonElement).dataset.managerAction = 'enable';
    if (role === 'ocr' && current.active) (actions.lastChild as HTMLButtonElement).disabled = true;
    if (!current.local) actions.append(button('删除配置', () => context.operate(role, current.id, 'remove'), 'text-button danger'));
    detail.append(actions);
  }
  for (const tab of root.querySelectorAll<HTMLButtonElement>('[data-service-role]')) tab.addEventListener('click', () => {
    if (pending) return; role = tab.dataset.serviceRole as ServiceRole; root.dataset.detail = 'false'; render();
  });
  add.addEventListener('click', () => context.add(role));
  document.querySelector('#managed-service-recommend')!.addEventListener('click', () => context.recommend(role));
  return { render };
}
