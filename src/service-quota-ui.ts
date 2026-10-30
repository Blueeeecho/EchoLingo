import './service-quota-ui.css';
import { PROVIDER_PRESETS } from './provider-presets';
import { recommendedTranslationPresets, TRANSLATION_QUOTAS, type ServiceAllowance, type ServiceQuota } from './service-quotas';

const element = <K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text = ''): HTMLElementTagNameMap[K] => {
  const value = document.createElement(tag); value.className = className; value.textContent = text; return value;
};
function allowanceLabel(value: ServiceAllowance): string {
  if (value.amount === null) return value.period === 'unmetered' ? '不按云调用量计费' : '按所选模型规则与限流使用';
  const unit = { characters: '字符', calls: '次', units: 'units', tokens: 'Token', CNY: '元', none: '' }[value.unit];
  const period = { day: ' / 日', month: ' / 月', once: ' · 一次性', unmetered: '', variable: ' · 按服务规则' }[value.period];
  return `${value.amount.toLocaleString('zh-CN')} ${unit}${period}`;
}

// Local, read-only product guidance. No account probes or quota API calls.
export function renderServiceQuota(quota: ServiceQuota, currentModel = ''): HTMLElement {
  const card = element('section', 'service-quota'); card.setAttribute('aria-label', '费用与免费额度');
  card.append(element('span', 'service-quota-badge', quota.badge), element('p', 'service-quota-summary', quota.summary));
  if (quota.recommendedModel && currentModel.trim() && currentModel.trim() !== quota.recommendedModel) {
    card.append(element('p', 'service-quota-model-note', `当前模型为 ${currentModel.trim()}，不适用上述免费模型价格。可手动选择 ${quota.recommendedModel}，或按官方价格继续使用当前模型。`));
  }
  const details = element('details', 'service-quota-details'); details.append(element('summary', '', '额度条件与说明'));
  const list = element('ul', 'service-quota-allowances');
  for (const allowance of quota.allowances) {
    const row = element('li', ''); row.append(element('strong', '', `${allowance.plan} · ${allowanceLabel(allowance)}`));
    for (const condition of allowance.conditions) row.append(element('p', '', condition));
    if (allowance.expires) row.append(element('p', '', `有效期：${allowance.expires}`));
    list.append(row);
  }
  for (const detail of quota.details) list.append(element('li', '', detail));
  details.append(list); card.append(details);
  const links = element('div', 'service-guide-links');
  for (const [label, url] of quota.links) {
    const link = element('a', '', `${label} ↗`); link.href = url; link.target = '_blank'; link.rel = 'noopener noreferrer'; link.dataset.serviceLink = 'true'; links.append(link);
  }
  card.append(links, element('small', 'service-quota-date', `额度核对：${quota.checkedOn}`));
  return card;
}

export function populateProviderPresets(select: HTMLSelectElement, platform: string): void {
  const selected = select.value;
  const recommended = recommendedTranslationPresets(platform);
  const addGroup = (label: string, ids: readonly string[], recommend = false): void => {
    const group = element('optgroup', ''); group.label = label;
    for (const id of ids) {
      const preset = PROVIDER_PRESETS.find(value => value.id === id); if (!preset) continue;
      const option = element('option', '', `${recommend ? '推荐 · ' : ''}${preset.label} · ${TRANSLATION_QUOTAS[preset.id].badge}`);
      option.value = preset.id; option.dataset.recommended = String(recommend); group.append(option);
    }
    if (group.children.length) select.append(group);
  };
  select.replaceChildren();
  addGroup('推荐 · 从这些服务开始', recommended, true);
  for (const [label, kinds] of [['本机翻译', ['system', 'offline']], ['官方机器翻译', ['baidu', 'youdao', 'microsoft', 'deepl', 'libretranslate', 'volcengine', 'aliyun', 'niutrans', 'google-translate', 'caiyun']], ['大模型 · 兼容接口', ['openai']]] as const) {
    addGroup(label, PROVIDER_PRESETS.filter(value => (kinds as readonly string[]).includes(value.kind) && !recommended.includes(value.id)).map(value => value.id));
  }
  // Populating recommendations never changes an existing selected service.
  if (PROVIDER_PRESETS.some(value => value.id === selected)) select.value = selected;
}
