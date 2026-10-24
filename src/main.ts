import './styles.css';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { defaultSettings, errorMessage, filterHistory, LANGUAGES, languageName, MAX_TEXT_LENGTH, normalizeTimestamp, SHORTCUT_LABELS, validateProvider } from './model';
import type { Action, HistoryEntry, Provider, ProviderKind, Settings, ShortcutAction, SourceTextEvent, TranslationResult } from './types';

const desktop = isTauri();
const $ = <T extends HTMLElement = HTMLElement>(selector: string): T => {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`界面组件不存在：${selector}`);
  return element;
};
const source = $<HTMLTextAreaElement>('#source-text');
const sourceLanguage = $<HTMLSelectElement>('#source-language');
const targetLanguage = $<HTMLSelectElement>('#target-language');
const translateButton = $<HTMLButtonElement>('#translate-button');
const resultsContainer = $('#results');
const providerDialog = $<HTMLDialogElement>('#provider-dialog');
const confirmDialog = $<HTMLDialogElement>('#confirm-dialog');
let settings = defaultSettings();
let history: HistoryEntry[] = [];
let favoritesOnly = false;
let pinned = false;
let generation = 0;
let translating = false;
let editingProviderId: string | null = null;
let toastTimer: ReturnType<typeof setTimeout> | undefined;
let saveQueue: Promise<void> = Promise.resolve();
let settingsReady = !desktop;
let currentView = 'translate';
let currentResults: TranslationResult[] = [];
let resultSource = '';
let confirmResolve: ((value: boolean) => void) | null = null;
const cleanupListeners: Array<() => void> = [];
const prefersDark = window.matchMedia('(prefers-color-scheme: dark)');

function icon(name: string): SVGSVGElement {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.classList.add('icon');
  svg.setAttribute('aria-hidden', 'true');
  const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
  use.setAttribute('href', `#i-${name}`);
  svg.append(use);
  return svg;
}
function node<K extends keyof HTMLElementTagNameMap>(tag: K, className = '', text = ''): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);
  element.className = className;
  if (text) element.textContent = text;
  return element;
}
function actionButton(label: string, iconName: string, handler: () => void, className = 'icon-button'): HTMLButtonElement {
  const button = node('button', className);
  button.type = 'button';
  button.title = label;
  button.setAttribute('aria-label', label);
  button.append(icon(iconName));
  button.addEventListener('click', handler);
  return button;
}
function toast(message: string, tone: 'info' | 'error' = 'info', duration = 4200): void {
  if (toastTimer) clearTimeout(toastTimer);
  const element = $('#toast');
  element.textContent = message;
  element.dataset.tone = tone;
  element.hidden = false;
  toastTimer = setTimeout(() => { element.hidden = true; }, duration);
}
function status(message: string): void { $('#footer-status').textContent = message; }
function requireDesktop(): boolean {
  if (desktop) return true;
  toast('当前是浏览器预览。请在 EchoLingo 桌面应用中使用此功能。');
  return false;
}
function reportError(error: unknown): void { toast(errorMessage(error), 'error', 6500); }
function run(work: () => Promise<unknown>): void { void work().catch(reportError); }
function setView(view: string): void {
  if (!['translate', 'history', 'settings'].includes(view)) return;
  currentView = view;
  for (const section of document.querySelectorAll<HTMLElement>('.view')) section.hidden = section.id !== `view-${view}`;
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-view]')) {
    const selected = button.dataset.view === view;
    button.classList.toggle('active', selected);
    if (selected) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
  }
  if (view === 'history') { run(loadHistory); renderHistory(); }
  window.scrollTo({ top: 0, behavior: 'instant' });
}
function applyTheme(): void {
  const theme = settings.theme === 'system' ? (prefersDark.matches ? 'dark' : 'light') : settings.theme;
  document.documentElement.dataset.theme = theme;
  $('#theme-cycle').title = `当前：${{ system: '跟随系统', light: '浅色', dark: '深色' }[settings.theme]}，点击切换`;
}
function renderLanguages(): void {
  for (const select of [sourceLanguage, targetLanguage]) {
    select.replaceChildren();
    for (const [value, name] of LANGUAGES) {
      if (select === targetLanguage && value === 'auto') continue;
      const option = node('option', '', name); option.value = value; select.append(option);
    }
  }
  sourceLanguage.value = settings.sourceLanguage;
  targetLanguage.value = settings.targetLanguage;
  // Keep custom language codes supplied by a future backend visible rather than silently changing them.
  for (const [select, value] of [[sourceLanguage, settings.sourceLanguage], [targetLanguage, settings.targetLanguage]] as const) {
    if (!select.value) { const option = node('option', '', value); option.value = value; select.append(option); select.value = value; }
  }
}
function updateCharacterCount(): void { $('#character-count').textContent = `${source.value.length.toLocaleString()} / 20,000`; }
function setLoading(value: boolean): void {
  translating = value;
  translateButton.disabled = value || !settingsReady;
  $('#translate-button-label').textContent = value ? '翻译中' : '翻译';
  $('#translate-arrow').hidden = value;
  $('#translate-spinner').hidden = !value;
  resultsContainer.setAttribute('aria-busy', String(value));
}
function emptyResults(): void {
  resultsContainer.replaceChildren();
  const empty = node('div', 'translation-empty');
  const orbit = node('div', 'empty-orbit');
  orbit.append(node('span', 'orbit-letter', 'A'), node('span', 'orbit-letter small', '译'), node('span', 'orbit-dot'));
  const title = source.value.trim() ? '准备好，遇见另一种表达' : '你的下一次理解，从这里开始';
  const description = settings.providers.some((provider) => provider.enabled)
    ? '输入文字后点击翻译，或按 Ctrl / Cmd + Enter。'
    : '先添加一个翻译服务，再输入文字开始翻译。';
  empty.append(orbit, node('h2', '', title), node('p', '', description));
  if (!settings.providers.some((provider) => provider.enabled)) {
    const button = node('button', 'text-button accent', '配置翻译服务 ↗');
    button.addEventListener('click', () => setView('settings'));
    empty.append(button);
  }
  resultsContainer.append(empty);
  $('#translation-state').textContent = source.value.trim() ? '等待翻译' : '等候输入';
}
function invalidateResults(): void {
  generation += 1;
  setLoading(false);
  currentResults = [];
  resultSource = '';
  emptyResults();
}
function setSourceText(text: string): void {
  source.value = text.slice(0, MAX_TEXT_LENGTH);
  updateCharacterCount();
  invalidateResults();
  if (text.length > MAX_TEXT_LENGTH) toast('文字超过 20,000 字符，已截取前 20,000 字符。', 'error');
}
async function copyText(text: string): Promise<void> {
  if (!text) return;
  if (desktop) await invoke('copy_text', { text });
  else if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(text);
  else throw new Error('当前浏览器不支持写入剪贴板，请手动选择并复制文字。');
  toast('已复制到剪贴板。');
}
function speak(text: string, language: string): void {
  if (!('speechSynthesis' in window) || !('SpeechSynthesisUtterance' in window)) {
    toast('当前系统没有可用的语音合成能力。'); return;
  }
  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = ({ 'zh-Hans': 'zh-CN', 'zh-Hant': 'zh-TW', en: 'en-US', ja: 'ja-JP', ko: 'ko-KR' } as Record<string, string>)[language] ?? language;
  utterance.onerror = (event) => { if (!['canceled', 'interrupted'].includes(event.error)) toast('朗读不可用，请检查系统语音与网络设置。', 'error'); };
  window.speechSynthesis.speak(utterance);
}
function renderResults(results: TranslationResult[]): void {
  resultsContainer.replaceChildren();
  if (results.length === 0) {
    emptyResults();
    $('#translation-state').textContent = '未返回结果';
    return;
  }
  for (const result of results) {
    const card = node('article', 'result-card');
    const header = node('div', 'result-card-header');
    const name = node('span', 'result-provider');
    name.append(node('span', 'provider-dot'), document.createTextNode(result.providerName));
    header.append(name, node('span', 'result-timing', `${(result.elapsedMs / 1000).toFixed(1)} s`));
    card.append(header);
    if (result.error) card.append(node('p', 'result-error', result.error));
    else {
      card.append(node('p', 'result-text', result.text));
      const actions = node('div', 'result-actions');
      actions.append(actionButton('复制译文', 'copy', () => run(() => copyText(result.text))));
      if ('speechSynthesis' in window) actions.append(actionButton('朗读译文', 'audio', () => speak(result.text, targetLanguage.value)));
      card.append(actions);
    }
    resultsContainer.append(card);
  }
  const success = results.filter((result) => !result.error).length;
  $('#translation-state').textContent = success === results.length ? '翻译完成' : `${success} / ${results.length} 个服务成功`;
}
async function translate(): Promise<void> {
  if (!settingsReady) throw new Error('设置正在加载，请稍候。');
  const text = source.value.trim();
  if (!text) { source.focus(); toast('先输入需要翻译的文字。'); return; }
  if (text.length > MAX_TEXT_LENGTH) throw new Error('每次最多翻译 20,000 字符。');
  if (!requireDesktop()) return;
  if (!settings.providers.some((provider) => provider.enabled)) { setView('settings'); toast('请先添加并启用一个翻译服务。'); return; }
  const token = ++generation;
  const from = sourceLanguage.value, to = targetLanguage.value;
  setLoading(true);
  resultsContainer.replaceChildren();
  const loading = node('div', 'result-loading'); loading.append(node('span', 'spinner'), document.createTextNode('正在寻找最贴切的表达…'));
  resultsContainer.append(loading);
  $('#translation-state').textContent = '正在请求 API';
  status('正在翻译…');
  try {
    const results = await invoke<TranslationResult[]>('translate', { text, sourceLanguage: from, targetLanguage: to });
    if (token !== generation) return;
    currentResults = results;
    resultSource = text;
    renderResults(results);
    status(results.some((result) => !result.error) ? '翻译完成' : '服务返回错误');
  } catch (error) {
    if (token !== generation) return;
    resultsContainer.replaceChildren();
    const card = node('article', 'result-card');
    card.append(node('p', 'result-error', errorMessage(error)));
    resultsContainer.append(card);
    $('#translation-state').textContent = '翻译失败';
    status('翻译失败');
  } finally {
    if (token === generation) setLoading(false);
    await loadHistory().catch(() => undefined);
  }
}
function renderShortcutHints(): void {
  for (const element of document.querySelectorAll<HTMLElement>('[data-shortcut]')) {
    element.textContent = settings.shortcuts[element.dataset.shortcut as ShortcutAction];
  }
}
async function updateSettings(mutator: (next: Settings) => void): Promise<void> {
  const operation = saveQueue.then(async () => {
    if (!settingsReady) throw new Error('设置尚未加载，无法保存。请稍后重试。');
    const next = structuredClone(settings);
    mutator(next);
    if (desktop) {
      await invoke('save_settings', { settings: next });
      settings = await invoke<Settings>('get_settings');
    } else settings = next;
    applyTheme();
    renderSettings();
    renderShortcutHints();
    $('#service-counter').textContent = `${settings.providers.filter((provider) => provider.enabled).length} 个服务已启用`;
    if (currentResults.length === 0 && !translating) emptyResults();
  });
  saveQueue = operation.catch(() => undefined);
  return operation;
}
async function loadHistory(): Promise<void> {
  if (desktop) history = await invoke<HistoryEntry[]>('get_history');
  renderHistory();
}
function historyDate(value: number): string {
  const date = new Date(normalizeTimestamp(value));
  return Number.isNaN(date.getTime()) ? '时间未知' : new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).format(date);
}
function renderHistory(): void {
  const query = $<HTMLInputElement>('#history-search').value;
  const filtered = filterHistory(history, query, favoritesOnly);
  const list = $('#history-list'); list.replaceChildren();
  $('#history-summary').textContent = `${filtered.length} 条${favoritesOnly ? '收藏' : '翻译'}记录${query.trim() ? `（共 ${history.length} 条）` : ''} · 仅保存在此设备`;
  $<HTMLButtonElement>('#clear-history').disabled = history.length === 0;
  if (filtered.length === 0) {
    const empty = node('div', 'list-empty');
    empty.append(icon(favoritesOnly ? 'star' : 'history'), node('h2', '', query ? '没有找到相关翻译' : favoritesOnly ? '把喜欢的表达，收藏起来' : '每一次理解，都值得被记住'), node('p', '', query ? '试试搜索原文、译文中的其他关键词。' : favoritesOnly ? '点击历史记录旁的星标，即可加入收藏。' : '完成翻译后，记录会出现在这里。你可以在设置中关闭历史保存。'));
    list.append(empty); return;
  }
  for (const entry of filtered) {
    const item = node('article', 'history-item');
    const header = node('div', 'history-item-heading');
    const meta = node('div', 'history-item-meta');
    meta.append(node('time', '', historyDate(entry.createdAt)), node('span', '', '·'), node('span', '', `${languageName(entry.sourceLanguage)} → ${languageName(entry.targetLanguage)}`));
    const actions = node('div', 'history-item-actions');
    const favorite = actionButton(entry.favorite ? '取消收藏' : '收藏翻译', 'star', () => run(async () => {
      if (!requireDesktop()) return;
      await invoke('toggle_favorite', { id: entry.id }); await loadHistory();
    }));
    favorite.setAttribute('aria-pressed', String(entry.favorite));
    actions.append(favorite, actionButton('复制原文', 'copy', () => run(() => copyText(entry.text))), actionButton('删除记录', 'trash', () => run(async () => {
      if (!requireDesktop()) return;
      await invoke('delete_history', { id: entry.id }); await loadHistory();
    })));
    header.append(meta, actions);
    item.append(header, node('p', 'history-original', entry.text));
    for (const result of entry.results) {
      if (!result.error && result.text) item.append(node('p', 'history-result', `${result.providerName} · ${result.text}`));
    }
    const reopen = node('button', 'text-button accent history-open', '在翻译窗口打开 ↗');
    reopen.addEventListener('click', () => {
      sourceLanguage.value = entry.sourceLanguage; targetLanguage.value = entry.targetLanguage;
      setSourceText(entry.text); currentResults = entry.results; resultSource = entry.text; renderResults(entry.results); setView('translate');
    });
    item.append(reopen); list.append(item);
  }
}
function providerKindLabel(kind: ProviderKind): string { return { openai: 'OpenAI 兼容', deepl: 'DeepL', libretranslate: 'LibreTranslate' }[kind]; }
function renderProviders(): void {
  const list = $('#provider-list'); list.replaceChildren();
  $<HTMLButtonElement>('#add-provider').disabled = !settingsReady || settings.providers.length >= 12;
  if (settings.providers.length === 0) {
    const empty = node('div', 'provider-empty');
    empty.append(node('div', '', '还没有翻译服务。支持 OpenAI 兼容接口、DeepL 与 LibreTranslate。'), node('div', '', '你可以使用自己的服务商、模型和 API 地址。'));
    list.append(empty); return;
  }
  for (const provider of settings.providers) {
    const row = node('div', 'provider-row');
    row.append(node('span', 'provider-avatar', provider.name.slice(0, 1).toUpperCase()));
    const info = node('div', 'provider-info');
    const title = node('div', 'provider-title', provider.name);
    if (provider.hasKey) title.append(node('span', 'provider-key-badge', '· 密钥已保存'));
    info.append(title, node('span', 'provider-details', `${providerKindLabel(provider.kind)}${provider.model ? ` · ${provider.model}` : ''} · ${provider.baseUrl}`));
    const controls = node('div', 'provider-controls');
    const enabled = node('input', 'switch'); enabled.type = 'checkbox'; enabled.checked = provider.enabled;
    enabled.setAttribute('aria-label', `启用 ${provider.name}`);
    enabled.addEventListener('change', () => {
      const value = enabled.checked; enabled.disabled = true;
      run(async () => { try { await updateSettings((next) => { const found = next.providers.find((item) => item.id === provider.id); if (found) found.enabled = value; }); } finally { renderProviders(); } });
    });
    const test = node('button', 'text-button', '测试连接');
    test.title = '发送 Hello 测试服务，可能消耗少量 API 额度';
    test.addEventListener('click', () => run(async () => {
      if (!requireDesktop()) return;
      test.disabled = true; test.textContent = '测试中…';
      toast('正在发送 Hello 测试连接，可能消耗少量 API 额度。');
      try {
        const message = await invoke<string>('test_provider', { providerId: provider.id });
        toast(message || '服务连接成功。');
      } finally { test.disabled = false; test.textContent = '测试连接'; }
    }));
    const edit = node('button', 'text-button', '编辑'); edit.addEventListener('click', () => openProviderDialog(provider));
    const remove = actionButton(`删除 ${provider.name}`, 'trash', () => run(async () => {
      if (!await confirmAction('删除翻译服务？', `将移除“${provider.name}”及其已保存的 API 密钥。`)) return;
      if (desktop) await invoke('delete_api_key', { providerId: provider.id });
      await updateSettings((next) => { next.providers = next.providers.filter((item) => item.id !== provider.id); });
      toast('翻译服务已删除。');
    }));
    controls.append(enabled, test, edit, remove); row.append(info, controls); list.append(row);
  }
}
function renderSettings(): void {
  renderProviders();
  const shortcutsForm = $('#shortcuts-form'); shortcutsForm.replaceChildren();
  for (const [action, label] of Object.entries(SHORTCUT_LABELS)) {
    const row = node('label', 'shortcut-row'); row.append(node('span', '', label));
    const input = node('input'); input.type = 'text'; input.value = settings.shortcuts[action as ShortcutAction]; input.name = action; input.maxLength = 80; input.autocomplete = 'off'; input.spellcheck = false;
    input.setAttribute('aria-label', `${label}快捷键`); row.append(input); shortcutsForm.append(row);
  }
  $<HTMLSelectElement>('#theme-select').value = settings.theme;
  $<HTMLInputElement>('#save-history').checked = settings.saveHistory;
  const historyLimit = $<HTMLSelectElement>('#max-history');
  if (!Array.from(historyLimit.options).some((option) => option.value === String(settings.maxHistory))) {
    const option = node('option', '', `${settings.maxHistory} 条`); option.value = String(settings.maxHistory); historyLimit.append(option);
  }
  historyLimit.value = String(settings.maxHistory);
}
function providerKindChanged(useDefaults = false): void {
  const kind = $<HTMLSelectElement>('#provider-kind').value as ProviderKind;
  const openai = kind === 'openai';
  $('#provider-model-field').hidden = !openai;
  $('#provider-prompt-field').hidden = !openai;
  $<HTMLInputElement>('#provider-model').required = openai;
  const url = $<HTMLInputElement>('#provider-url');
  const defaults = { openai: 'https://api.openai.com/v1', deepl: 'https://api-free.deepl.com/v2', libretranslate: 'http://127.0.0.1:5000' };
  url.placeholder = defaults[kind];
  if (useDefaults) url.value = defaults[kind];
  $('#provider-url-help').textContent = {
    openai: '填写 API 基础地址，无需包含 /chat/completions。DeepSeek、Ollama 等请填写对应地址。',
    deepl: '免费账户通常使用 api-free.deepl.com，付费账户使用 api.deepl.com。无需包含 /v2/translate。',
    libretranslate: '填写你使用的 LibreTranslate 服务地址，无需包含 /translate。',
  }[kind];
}
function openProviderDialog(provider?: Provider): void {
  if (!settingsReady) { toast('设置正在加载，请稍候。'); return; }
  if (!provider && settings.providers.length >= 12) { toast('最多可添加 12 个翻译服务。'); return; }
  editingProviderId = provider?.id ?? null;
  $<HTMLFormElement>('#provider-form').reset();
  $('#provider-dialog-title').textContent = provider ? '编辑翻译服务' : '添加翻译服务';
  $<HTMLInputElement>('#provider-name').value = provider?.name ?? '';
  $<HTMLSelectElement>('#provider-kind').value = provider?.kind ?? 'openai';
  $<HTMLInputElement>('#provider-url').value = provider?.baseUrl ?? 'https://api.openai.com/v1';
  $<HTMLInputElement>('#provider-model').value = provider?.model ?? 'gpt-4o-mini';
  $<HTMLTextAreaElement>('#provider-prompt').value = provider?.prompt ?? '';
  $<HTMLInputElement>('#provider-key').value = '';
  $<HTMLInputElement>('#provider-key').placeholder = provider?.hasKey ? '已保存密钥；留空保持不变' : '输入密钥（仅存入系统凭据库）';
  $<HTMLInputElement>('#provider-enabled').checked = provider?.enabled ?? true;
  $('#remove-provider-key').hidden = !provider?.hasKey;
  $('#provider-error').hidden = true;
  providerKindChanged();
  providerDialog.showModal();
}
function closeProviderDialog(): void {
  $<HTMLInputElement>('#provider-key').value = '';
  providerDialog.close();
  editingProviderId = null;
}
function confirmAction(title: string, description: string): Promise<boolean> {
  $('#confirm-title').textContent = title;
  $('#confirm-description').textContent = description;
  confirmDialog.showModal();
  return new Promise((resolve) => { confirmResolve = resolve; });
}
function settleConfirm(value: boolean): void { confirmDialog.close(); confirmResolve?.(value); confirmResolve = null; }
async function saveProvider(event: SubmitEvent): Promise<void> {
  event.preventDefault();
  if (!desktop) { toast('浏览器预览不保存 API 密钥。请在桌面应用中配置真实服务。'); return; }
  const existing = settings.providers.find((provider) => provider.id === editingProviderId);
  const provider: Provider = {
    id: editingProviderId ?? crypto.randomUUID(), name: $<HTMLInputElement>('#provider-name').value.trim(),
    kind: $<HTMLSelectElement>('#provider-kind').value as ProviderKind,
    baseUrl: $<HTMLInputElement>('#provider-url').value.trim().replace(/\/+$/, ''),
    model: $<HTMLInputElement>('#provider-model').value.trim(),
    enabled: $<HTMLInputElement>('#provider-enabled').checked,
    prompt: $<HTMLTextAreaElement>('#provider-prompt').value.trim(),
    hasKey: existing?.hasKey,
  };
  const validation = validateProvider(provider);
  const errorOutput = $('#provider-error');
  if (validation) { errorOutput.textContent = validation; errorOutput.hidden = false; return; }
  const saveButton = $<HTMLButtonElement>('#save-provider'); saveButton.disabled = true;
  const keyInput = $<HTMLInputElement>('#provider-key');
  const key = keyInput.value.trim();
  try {
    await updateSettings((next) => {
      const index = next.providers.findIndex((item) => item.id === provider.id);
      if (index === -1) next.providers.push(provider); else next.providers[index] = provider;
    });
    editingProviderId = provider.id;
    if (key) {
      try { await invoke('set_api_key', { providerId: provider.id, key }); }
      catch (error) { throw new Error(`服务已保存，但密钥未能存入系统凭据库：${errorMessage(error)}`); }
    }
    keyInput.value = '';
    settings = await invoke<Settings>('get_settings');
    renderSettings(); closeProviderDialog(); toast('翻译服务已保存。');
  } catch (error) { errorOutput.textContent = errorMessage(error); errorOutput.hidden = false; }
  finally { saveButton.disabled = false; }
}
async function runAction(action: Action): Promise<void> {
  if (action === 'selection') { toast(`在其他应用中选中文字后，按 ${settings.shortcuts.selection} 即可划词翻译。`); return; }
  if (!requireDesktop()) return;
  await invoke('run_action', { action });
}

for (const button of document.querySelectorAll<HTMLButtonElement>('[data-view]')) button.addEventListener('click', () => setView(button.dataset.view ?? 'translate'));
for (const button of document.querySelectorAll<HTMLButtonElement>('[data-action]')) button.addEventListener('click', () => run(() => runAction(button.dataset.action as Action)));
$('.brand-mark').addEventListener('click', (event) => { event.preventDefault(); setView('translate'); });
$('#setup-services').addEventListener('click', () => setView('settings'));
translateButton.addEventListener('click', () => run(translate));
source.addEventListener('input', () => { updateCharacterCount(); invalidateResults(); });
$('#clear-source').addEventListener('click', () => { setSourceText(''); source.focus(); });
for (const select of [sourceLanguage, targetLanguage]) select.addEventListener('change', () => {
  invalidateResults();
  run(() => updateSettings((next) => { next.sourceLanguage = sourceLanguage.value; next.targetLanguage = targetLanguage.value; }));
});
$('#swap-language').addEventListener('click', () => {
  if (sourceLanguage.value === 'auto') { toast('先选择具体的源语言，即可交换语言方向。'); return; }
  const previousSource = sourceLanguage.value;
  sourceLanguage.value = targetLanguage.value; targetLanguage.value = previousSource;
  if (currentResults.find((result) => !result.error)?.text && resultSource === source.value.trim()) setSourceText(currentResults.find((result) => !result.error)!.text);
  else invalidateResults();
  run(() => updateSettings((next) => { next.sourceLanguage = sourceLanguage.value; next.targetLanguage = targetLanguage.value; }));
});
$('#pin-button').addEventListener('click', () => run(async () => {
  if (!requireDesktop()) return;
  const next = !pinned; await invoke('set_pinned', { pinned: next }); pinned = next;
  $('#pin-button').setAttribute('aria-pressed', String(pinned)); $('#pin-button').title = pinned ? '取消置顶' : '置顶窗口';
  toast(pinned ? '窗口已置顶。' : '已取消窗口置顶。');
}));
$('#theme-cycle').addEventListener('click', () => run(async () => {
  const order: Settings['theme'][] = ['system', 'light', 'dark'];
  await updateSettings((next) => { next.theme = order[(order.indexOf(next.theme) + 1) % order.length]!; });
}));
prefersDark.addEventListener('change', applyTheme);
$<HTMLSelectElement>('#theme-select').addEventListener('change', (event) => run(() => updateSettings((next) => { next.theme = (event.target as HTMLSelectElement).value as Settings['theme']; })));
$<HTMLInputElement>('#save-history').addEventListener('change', (event) => {
  const value = (event.target as HTMLInputElement).checked;
  run(async () => { try { await updateSettings((next) => { next.saveHistory = value; }); toast(value ? '已开启翻译历史。' : '已关闭历史保存；已有记录可在历史页面删除。'); } finally { renderSettings(); } });
});
$<HTMLSelectElement>('#max-history').addEventListener('change', (event) => {
  const value = Number((event.target as HTMLSelectElement).value);
  run(() => updateSettings((next) => { next.maxHistory = value; }));
});
$('#save-shortcuts').addEventListener('click', () => run(async () => {
  const values = Object.fromEntries(new FormData($<HTMLFormElement>('#shortcuts-form')).entries()) as Record<ShortcutAction, string>;
  const normalized = Object.values(values).map((value) => value.trim().toLowerCase());
  if (normalized.some((value) => !value)) throw new Error('每个操作都需要一个快捷键。');
  if (new Set(normalized).size !== normalized.length) throw new Error('不同操作不能使用相同的快捷键。');
  await updateSettings((next) => { for (const action of Object.keys(SHORTCUT_LABELS) as ShortcutAction[]) next.shortcuts[action] = values[action].trim(); });
  toast(desktop ? '快捷键已保存。若注册失败，将显示系统返回的原因。' : '快捷键已在预览中更新；桌面应用才能注册全局快捷键。');
}));
$('#add-provider').addEventListener('click', () => openProviderDialog());
$('#provider-kind').addEventListener('change', () => providerKindChanged(true));
$('#close-provider-dialog').addEventListener('click', closeProviderDialog);
$('#cancel-provider-dialog').addEventListener('click', closeProviderDialog);
providerDialog.addEventListener('close', () => { $<HTMLInputElement>('#provider-key').value = ''; });
$<HTMLFormElement>('#provider-form').addEventListener('submit', (event) => { void saveProvider(event).catch(reportError); });
$('#remove-provider-key').addEventListener('click', () => run(async () => {
  if (!editingProviderId || !requireDesktop()) return;
  await invoke('delete_api_key', { providerId: editingProviderId });
  settings = await invoke<Settings>('get_settings'); renderProviders();
  $('#remove-provider-key').hidden = true;
  $<HTMLInputElement>('#provider-key').placeholder = '输入密钥（仅存入系统凭据库）';
  toast('已从系统凭据库移除密钥。');
}));
$('#run-diagnostics').addEventListener('click', () => run(async () => {
  const button = $<HTMLButtonElement>('#run-diagnostics'); const output = $('#diagnostics-output');
  button.disabled = true; output.hidden = false; output.textContent = '正在检查…';
  try {
    const diagnostic = desktop ? await invoke<unknown>('diagnostics') : {
      environment: '浏览器预览', desktopFeatures: '不可用，请启动桌面应用',
      clipboard: Boolean(navigator.clipboard), speechSynthesis: 'speechSynthesis' in window,
      screenshot: '需要桌面权限', ocr: '需要桌面应用', credentials: '预览不读取或保存密钥',
    };
    output.textContent = typeof diagnostic === 'string' ? diagnostic : JSON.stringify(diagnostic, null, 2);
  } catch (error) { output.textContent = errorMessage(error); } finally { button.disabled = false; }
}));
$('#history-search').addEventListener('input', renderHistory);
for (const [id, value] of [['#filter-all', false], ['#filter-favorites', true]] as const) $(id).addEventListener('click', () => {
  favoritesOnly = value;
  for (const [selector, selected] of [['#filter-all', !value], ['#filter-favorites', value]] as const) { $(selector).classList.toggle('active', selected); $(selector).setAttribute('aria-pressed', String(selected)); }
  renderHistory();
});
$('#clear-history').addEventListener('click', () => run(async () => {
  if (!requireDesktop()) return;
  if (!await confirmAction('清空全部翻译历史？', '原文、译文和收藏记录都会从本机删除，此操作无法撤销。')) return;
  await invoke('delete_history'); await loadHistory(); toast('翻译历史已清空。');
}));
$('#confirm-cancel').addEventListener('click', () => settleConfirm(false));
$('#confirm-accept').addEventListener('click', () => settleConfirm(true));
confirmDialog.addEventListener('cancel', (event) => { event.preventDefault(); settleConfirm(false); });
document.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && (event.ctrlKey || event.metaKey) && !providerDialog.open && !confirmDialog.open) {
    event.preventDefault(); if (!translating) { setView('translate'); run(translate); }
  }
  if (event.key === 'Escape' && !providerDialog.open && !confirmDialog.open) {
    if (desktop) { event.preventDefault(); run(() => invoke('hide_window')); }
    else if (currentView !== 'translate') setView('translate');
  }
});
window.addEventListener('beforeunload', () => { for (const unlisten of cleanupListeners) unlisten(); if ('speechSynthesis' in window) window.speechSynthesis.cancel(); });

async function initialize(): Promise<void> {
  if (!desktop) {
    $('#preview-banner').hidden = false;
    $('#runtime-badge').classList.add('preview');
    $('#runtime-badge span').textContent = '浏览器预览';
    status('界面预览 · 桌面能力未连接');
  }
  $('#translate-key-hint').textContent = /Mac|iPhone|iPad/.test(navigator.platform) ? '⌘' : 'Ctrl';
  applyTheme(); renderLanguages(); renderSettings(); renderShortcutHints(); renderHistory(); emptyResults();
  setLoading(false);
  if (!desktop) return;
  status('正在加载设置…');
  let pendingTranslate = false;
  try {
    // Listen before loading settings so an incoming native selection is not lost during startup.
    cleanupListeners.push(await listen<SourceTextEvent>('source-text', (event) => {
      setView('translate'); setSourceText(event.payload.text);
      if (event.payload.mode === 'translate') { if (settingsReady) run(translate); else pendingTranslate = true; }
      else { toast('已完成本机文字识别。'); source.focus(); }
    }));
    cleanupListeners.push(await listen('focus-input', () => { setView('translate'); requestAnimationFrame(() => source.focus()); }));
    cleanupListeners.push(await listen('ocr-copied', () => { status('OCR 文字已复制到剪贴板'); }));
    for (const eventName of ['action-error', 'shortcut-error']) cleanupListeners.push(await listen<string>(eventName, (event) => toast(event.payload, 'error', 8000)));
    settings = await invoke<Settings>('get_settings');
    settingsReady = true;
    applyTheme(); renderLanguages(); renderSettings(); renderShortcutHints();
    $('#service-counter').textContent = `${settings.providers.filter((provider) => provider.enabled).length} 个服务已启用`;
    if (!translating) emptyResults();
    await loadHistory(); status('准备就绪');
    if (pendingTranslate) run(translate);
    const diagnostic = await invoke<{ warnings?: unknown }>('diagnostics').catch(() => null);
    if (Array.isArray(diagnostic?.warnings) && diagnostic.warnings.length > 0) toast(diagnostic.warnings.filter((warning): warning is string => typeof warning === 'string').join('\n'), 'error', 10_000);
  } catch (error) {
    status('启动检查失败'); reportError(error);
    const output = $('#diagnostics-output'); output.hidden = false; output.textContent = `启动检查失败：${errorMessage(error)}`;
  } finally { translateButton.disabled = translating || !settingsReady; }
}
void initialize();
