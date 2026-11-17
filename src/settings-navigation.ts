/** Settings categories organize the existing controls; native visibility remains
 * owned by the original platform logic inside each panel. */
export type SettingsCategory = 'general' | 'translation' | 'capture' | 'shortcuts' | 'permissions' | 'about';
const categories: Array<[SettingsCategory, string, string]> = [
  ['general', '常规', '外观与历史记录'],
  ['translation', '翻译服务', '服务、语言包与推荐'],
  ['capture', '识别与截图', '文字识别与图片保存'],
  ['shortcuts', '快捷键', '按你的习惯操作'],
  ['permissions', '权限与诊断', '授权状态与问题排查'],
  ['about', '关于与更新', '版本与更新偏好'],
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
    general: [document.querySelector('#general-settings')],
    translation: [document.querySelector('#translation-settings'), document.querySelector('#free-setup-card')],
    capture: [document.querySelector('#ocr-settings'), document.querySelector('#screenshot-settings')],
    shortcuts: [document.querySelector('#shortcut-settings'), document.querySelector('#windows-selection-settings')],
    permissions: [document.querySelector('#mac-permission-card'), root.querySelector('.diagnostics-details')],
    about: [document.querySelector('#update-settings')],
  };
  const layout = document.createElement('div'); layout.className = 'settings-layout';
  const nav = document.createElement('div'); nav.className = 'settings-navigation'; nav.setAttribute('role', 'tablist'); nav.setAttribute('aria-label', '设置分类'); nav.setAttribute('aria-orientation', 'vertical');
  const content = document.createElement('div'); content.className = 'settings-content';
  for (const [id, label, description] of categories) {
    const tab = document.createElement('button'); tab.type = 'button'; tab.id = `settings-tab-${id}`; tab.dataset.settingsTab = id; tab.setAttribute('role', 'tab'); tab.setAttribute('aria-controls', `settings-panel-${id}`); tab.textContent = label;
    tab.addEventListener('click', () => selectSettingsCategory(id)); nav.append(tab);
    const panel = document.createElement('section'); panel.id = `settings-panel-${id}`; panel.dataset.settingsPanel = id; panel.setAttribute('role', 'tabpanel'); panel.setAttribute('aria-labelledby', tab.id); panel.tabIndex = 0;
    const intro = document.createElement('p'); intro.className = 'settings-category-description'; intro.textContent = description; panel.append(intro);
    if (id === 'translation') {
      const manager = document.querySelector('#open-service-manager'); if (manager) panel.append(manager);
    }
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
    if (!['ArrowDown', 'ArrowUp', 'ArrowRight', 'ArrowLeft', 'Home', 'End'].includes(key)) return;
    event.preventDefault();
    const index = categories.findIndex(([id]) => id === current);
    const next = key === 'Home' ? 0 : key === 'End' ? categories.length - 1 : (index + (key === 'ArrowDown' || key === 'ArrowRight' ? 1 : -1) + categories.length) % categories.length;
    selectSettingsCategory(categories[next][0], true);
  });
  installed = true;
  try { const saved = sessionStorage.getItem('echolingo.settings-category'); if (categories.some(([id]) => id === saved)) current = saved as SettingsCategory; } catch { /* use default */ }
  selectSettingsCategory(current);
}
