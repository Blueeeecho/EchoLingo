/** Settings categories organize the existing controls; native visibility remains
 * owned by the original platform logic inside each panel. */
export type SettingsCategory = 'general' | 'translation' | 'capture' | 'shortcuts' | 'permissions' | 'about';
const categories: Array<[SettingsCategory, string, string, string]> = [
  ['general', '常规', '调整界面主题与本机历史记录。', 'settings'],
  ['translation', '翻译服务', '管理本机语言包和云端翻译服务。', 'translate'],
  ['capture', '识别与截图', '选择识别方式，或更改截图的保存位置。', 'capture'],
  ['shortcuts', '快捷键', '修改划词、文字识别和截图编辑的快捷键。', 'bolt'],
  ['permissions', '权限与诊断', '排查划词、截图和快捷键问题。', 'shield'],
  ['about', '关于与更新', '查看当前版本，选择何时检查更新。', 'history'],
];
let installed = false;
let current: SettingsCategory = 'general';
export function selectSettingsCategory(category: SettingsCategory, focus = false): void {
  if (!installed) return;
  current = category;
  for (const panel of document.querySelectorAll<HTMLElement>('[data-settings-panel]')) panel.hidden = panel.dataset.settingsPanel !== category;
  for (const tab of document.querySelectorAll<HTMLButtonElement>('[data-settings-tab]')) {
    const selected = tab.dataset.settingsTab === category;
    tab.setAttribute('aria-selected', String(selected)); tab.tabIndex = selected ? 0 : -1;
    if (selected && focus) tab.focus();
  }
  if (document.body.dataset.view === 'settings') {
    const main = document.querySelector('main'); if (main) main.scrollTop = 0;
    window.scrollTo({ top: 0, behavior: 'instant' });
  }
  try { sessionStorage.setItem('echolingo.settings-category', category); } catch { /* optional convenience */ }
  document.dispatchEvent(new CustomEvent('settings-category-change'));
}
export function revealSettingsTarget(target: Element | string | null): void {
  if (!installed) return;
  const node = typeof target === 'string' ? document.querySelector(target) : target;
  const panel = node?.closest<HTMLElement>('[data-settings-panel]');
  if (panel) selectSettingsCategory(panel.dataset.settingsPanel as SettingsCategory);
}
export function installSettingsNavigation(): void {
  if (installed) return;
  const root = document.querySelector<HTMLElement>('#view-settings');
  if (!root) return;
  const groups: Record<SettingsCategory, (Element | null | undefined)[]> = {
    general: [document.querySelector('#general-settings'), document.querySelector('#history-settings')],
    translation: [document.querySelector('#translation-settings'), document.querySelector('#free-setup-card')],
    capture: [document.querySelector('#ocr-settings'), document.querySelector('#screenshot-settings')],
    shortcuts: [document.querySelector('#shortcut-settings'), document.querySelector('#windows-selection-settings')],
    permissions: [document.querySelector('#mac-permission-card'), root.querySelector('.diagnostics-details')],
    about: [document.querySelector('#update-settings')],
  };
  const layout = document.createElement('div'); layout.className = 'settings-layout';
  const nav = document.createElement('div'); nav.className = 'settings-navigation'; nav.setAttribute('role', 'tablist'); nav.setAttribute('aria-label', '设置分类'); nav.setAttribute('aria-orientation', 'vertical');
  const content = document.createElement('div'); content.className = 'settings-content';
  for (const [id, label, description, iconName] of categories) {
    const tab = document.createElement('button'); tab.type = 'button'; tab.id = `settings-tab-${id}`; tab.dataset.settingsTab = id; tab.setAttribute('role', 'tab'); tab.setAttribute('aria-controls', `settings-panel-${id}`);
    const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    icon.classList.add('icon'); icon.setAttribute('aria-hidden', 'true');
    const use = document.createElementNS(icon.namespaceURI, 'use'); use.setAttribute('href', `#i-${iconName}`);
    icon.append(use); tab.append(icon, label);
    tab.addEventListener('click', () => selectSettingsCategory(id)); nav.append(tab);
    const panel = document.createElement('section'); panel.id = `settings-panel-${id}`; panel.dataset.settingsPanel = id; panel.setAttribute('role', 'tabpanel'); panel.setAttribute('aria-labelledby', tab.id); panel.tabIndex = 0;
    const heading = document.createElement('header'); heading.className = 'settings-category-heading';
    const title = document.createElement('h1'); title.textContent = label;
    const intro = document.createElement('p'); intro.textContent = description;
    heading.append(title, intro); panel.append(heading);
    for (const card of groups[id]) if (card) panel.append(card);
    content.append(panel);
  }
  const compact = window.matchMedia('(max-width: 680px)');
  const orientation = () => nav.setAttribute('aria-orientation', compact.matches ? 'horizontal' : 'vertical');
  compact.addEventListener('change', orientation); orientation();
  root.querySelector('.settings-grid')?.remove();
  layout.append(nav, content); root.append(layout);
  nav.addEventListener('keydown', event => {
    const key = event.key;
    const arrows = compact.matches ? ['ArrowLeft', 'ArrowRight'] : ['ArrowUp', 'ArrowDown'];
    if (!arrows.includes(key) && key !== 'Home' && key !== 'End') return;
    event.preventDefault();
    const index = categories.findIndex(([id]) => id === current);
    const next = key === 'Home' ? 0 : key === 'End' ? categories.length - 1 : (index + (key === 'ArrowDown' || key === 'ArrowRight' ? 1 : -1) + categories.length) % categories.length;
    selectSettingsCategory(categories[next][0], true);
  });
  installed = true;
  try { const saved = sessionStorage.getItem('echolingo.settings-category'); if (categories.some(([id]) => id === saved)) current = saved as SettingsCategory; } catch { /* use default */ }
  selectSettingsCategory(current);
}
