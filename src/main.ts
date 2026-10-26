import './styles.css';
import { createOcrUi } from './ocr-ui';
import { installPanelLayout } from './panel-layout';
import type { TranslationPresentation } from './panel-layout';
import { normalizeCapturedText } from './text-normalization';
import { credentialScope } from './credential-scope';
import { credentialMayExist, credentialStateOf, credentialStatusLabel } from './credential-state';
import { inferProviderPreset, PROVIDER_PRESETS, qwenBaseUrl, qwenSettingsFromUrl } from './provider-presets';
import type { ProviderPresetId, QwenRegion } from './provider-presets';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { defaultSettings, errorMessage, userFacingError, filterHistory, LANGUAGES, languageName, MAX_TEXT_LENGTH, normalizeTimestamp, SHORTCUT_LABELS, validateProvider, isLocalProvider } from './model';
import type { Action, CredentialState, HistoryEntry, PermissionKind, Provider, ProviderKind, Settings, ShortcutAction, SourceTextEvent, SystemTranslationStatus, TranslationProgress, TranslationResult } from './types';

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
const providerDialog = $('#provider-dialog');
const confirmDialog = $('#confirm-dialog');
const ocrDialog = $('#ocr-provider-dialog');
const allModals = [providerDialog, confirmDialog, ocrDialog];
const modalReturnFocus = new Map<HTMLElement, HTMLElement | null>();
let settings = defaultSettings();
let history: HistoryEntry[] = [];
let favoritesOnly = false;
let pinned = false;
let generation = 0;
let translating = false;
let activeTranslationId: number | null = null;
let translationPresentation: TranslationPresentation = { epoch: 0, presented: false };
let visiblePopupUpdateBaseline: { epoch: number; generation: number } | null = null;
let translationStartQueue: Promise<void> = Promise.resolve();
let sourceComposing = false;
let permissionBusy = false;
let permissionGuidanceKind: PermissionKind | null = null;
const macDesktop = desktop && /Mac/.test(navigator.platform);
let editingProviderId: string | null = null;
let providerSaving = false;
let providerScopeAtOpen: string | null = null;
let providerLastInputScope: string | null = null;
let providerHadKeyAtOpen = false;
let providerCredentialStateAtOpen: CredentialState = 'missing';
let systemTranslationStatus: SystemTranslationStatus | null = null;
let systemTranslationStatusEpoch = 0;
let systemTranslationBusy = false;
let systemTranslationPreparing = false;
let systemTranslationLanguagesInitialized = false;
let toastTimer: ReturnType<typeof setTimeout> | undefined;
let saveQueue: Promise<void> = Promise.resolve();
let settingsReady = !desktop;
let currentView = 'translate';
let currentResults: TranslationResult[] = [];
interface ResultView { card: HTMLElement; body: HTMLElement; actions: HTMLButtonElement[]; result: TranslationResult; done: boolean; sequence: number }
const progressViews = new Map<string, ResultView>();
let progressEpoch: number | null = null;
let resultSource = '';
let pendingTranslate = false;
let originalCapture: SourceTextEvent | null = null;
let queuedCapture: SourceTextEvent | null = null;
let queuedInputFocus = false;
let pendingSettingsOpen: { presentationEpoch: number } | null = null;
let latestSettingsOpenEpoch = -1;
let confirmResolve: ((value: boolean) => void) | null = null;
const cleanupListeners: Array<() => void> = [];
const prefersDark = window.matchMedia('(prefers-color-scheme: dark)');
const panelLayout = installPanelLayout(desktop, () => translationPresentation);
let layoutQueued = false;
function notifyLayout(): void {
  if (layoutQueued) return;
  layoutQueued = true;
  requestAnimationFrame(() => { layoutQueued = false; window.dispatchEvent(new CustomEvent('echolingo:layout')); });
}
function closeMoreMenu(restoreFocus = false): void {
  const menu = $('#popup-more-menu');
  const wasOpen = !menu.hidden; menu.hidden = true;
  $('#more-toggle').setAttribute('aria-expanded', 'false');
  $('.app-shell').classList.remove('menu-open');
  if (wasOpen) { if (restoreFocus) $('#more-toggle').focus({ preventScroll: true }); notifyLayout(); }
}
function openMoreMenu(focusFirst = false): void {
  const menu = $('#popup-more-menu'); menu.hidden = false;
  $('#more-toggle').setAttribute('aria-expanded', 'true');
  document.documentElement.style.setProperty('--popup-menu-height', `${Math.min(380, menu.scrollHeight) + 38}px`);
  $('.app-shell').classList.add('menu-open');
  if (focusFirst) menu.querySelector<HTMLButtonElement>('button:not([disabled]):not([hidden])')?.focus({ preventScroll: true });
  notifyLayout();
}

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
function clearToast(): void {
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = undefined; $('#toast').hidden = true; $('#toast').textContent = '';
}
function isCompositionKey(event: KeyboardEvent): boolean {
  return sourceComposing || event.isComposing || event.keyCode === 229;
}
function status(message: string): void { $('#footer-status').textContent = message; }
function requireDesktop(): boolean {
  if (desktop) return true;
  toast('当前是浏览器预览。请在 EchoLingo 桌面应用中使用此功能。');
  return false;
}
function reportError(error: unknown): void { toast(userFacingError(error), 'error', 6500); }
function run(work: () => Promise<unknown>): void { void work().catch(reportError); }
function setView(view: string): void {
  if (!['translate', 'history', 'settings'].includes(view)) return;
  closeMoreMenu();
  currentView = view; document.body.dataset.view = view;
  $('#management-title').textContent = view === 'history' ? '历史与收藏' : '设置';
  for (const section of document.querySelectorAll<HTMLElement>('.view')) section.hidden = section.id !== `view-${view}`;
  for (const button of document.querySelectorAll<HTMLButtonElement>('button[data-view]')) {
    const selected = button.dataset.view === view;
    button.classList.toggle('active', selected);
    if (selected) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
  }
  if (view === 'history') { run(loadHistory); renderHistory(); }
  if (view === 'settings' && macDesktop) {
    // The first visit must still expose setup instructions while another
    // explicit permission action is in flight and status refresh is busy.
    $('#mac-permission-card').hidden = false;
    void refreshPermissionStatus();
  }
  if (view === 'settings') void refreshSystemTranslationStatus();
  window.scrollTo({ top: 0, behavior: 'instant' });
  if (view === 'translate') resizeSourceEditor();
  notifyLayout();
}
function applyTheme(): void {
  const theme = settings.theme === 'system' ? (prefersDark.matches ? 'dark' : 'light') : settings.theme;
  document.documentElement.dataset.theme = theme;
  const themeName = { system: '跟随系统', light: '浅色', dark: '深色' }[settings.theme];
  $('#theme-cycle').title = `当前：${themeName}，点击切换`;
  $('#theme-menu-label').textContent = `主题 · ${themeName}`;
}
function renderLanguages(): void {
  for (const select of [sourceLanguage, targetLanguage]) {
    select.replaceChildren();
    if (select === targetLanguage) {
      const automatic = node('option', '', '自动中英互译'); automatic.value = 'auto'; select.append(automatic);
    }
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
function resizeSourceEditor(): void {
  if (currentView === 'translate') {
    source.style.height = '0px';
    const height = Math.min(100, Math.max(source.value.trim() ? 25 : 46, source.scrollHeight));
    source.style.height = `${height}px`;
    source.style.overflowY = source.scrollHeight > 100 ? 'auto' : 'hidden';
  }
  const empty = !source.value.trim();
  document.body.classList.toggle('source-empty', empty);
  translateButton.disabled = !settingsReady || (!translating && empty);
  for (const id of ['#copy-source', '#speak-source', '#clear-source']) $<HTMLButtonElement>(id).disabled = empty;
  notifyLayout();
}
function setLoading(value: boolean): void {
  translating = value;
  translateButton.disabled = !settingsReady || (!value && !source.value.trim());
  translateButton.title = value ? '停止当前翻译' : '翻译';
  translateButton.setAttribute('aria-label', value ? '停止翻译' : '翻译');
  $('#translate-button-label').textContent = value ? '停止' : '翻译';
  $('#translate-arrow').hidden = value;
  $('#translate-spinner').hidden = !value;
  resultsContainer.setAttribute('aria-busy', String(value));
  $('#popup-services').hidden = value || currentResults.length > 0;
  notifyLayout();
}
function emptyResults(): void {
  progressViews.clear(); progressEpoch = null;
  resultsContainer.replaceChildren();
  $('.results-column').hidden = true;
  $('#popup-services').hidden = false;
  $('#translation-state').textContent = '';
  notifyLayout();
}
function invalidateResults(): void {
  cancelActiveTranslation();
  generation += 1;
  setLoading(false);
  currentResults = [];
  resultSource = '';
  emptyResults();
}
function cancelActiveTranslation(): void {
  const requestId = activeTranslationId;
  activeTranslationId = null;
  if (desktop && requestId !== null) void invoke('cancel_translation', { requestId }).catch(reportError);
}
function stopPendingTranslation(): void {
  if (!translating) return;
  invalidateResults();
  status('翻译已取消');
}
function applyTranslationPresentation(presentation: TranslationPresentation): void {
  // Native events and IPC responses may arrive out of order. Only newer
  // presentation epochs may invalidate an in-progress UI generation.
  if (presentation.epoch < translationPresentation.epoch) return;
  const changed = presentation.epoch > translationPresentation.epoch;
  translationPresentation = presentation;
  if (changed) {
    stopPendingTranslation();
    // A capture may finish while its pinned popup remains usable. Snapshot
    // after cancelling the previous request so later edits/manual work win.
    visiblePopupUpdateBaseline = presentation.presented ? { epoch: presentation.epoch, generation } : null;
  }
}
function beginTranslation(presentationEpoch: number): Promise<number> {
  // IPC handlers can run concurrently. Preserve ticket allocation order when
  // the user edits and submits again before an earlier allocation returns.
  const ticket = translationStartQueue.then(() => invoke<number>('begin_translation', { presentationEpoch }));
  translationStartQueue = ticket.then(() => undefined, () => undefined);
  return ticket;
}
function setSourceText(text: string): void {
  clearPermissionGuidance();
  clearOriginalCapture();
  source.value = text.slice(0, MAX_TEXT_LENGTH);
  resizeSourceEditor();
  invalidateResults();
  if (text.length > MAX_TEXT_LENGTH) toast('文字超过 20,000 字符，已截取前 20,000 字符。', 'error');
}
function clearOriginalCapture(): void {
  originalCapture = null;
  $('#restore-original-breaks').hidden = true;
}
async function receiveCapturedText(payload: SourceTextEvent & { presentationEpoch?: number }): Promise<void> {
  const presentationEpoch = payload.presentationEpoch ?? translationPresentation.epoch;
  if (presentationEpoch < translationPresentation.epoch) return;
  if (payload.updateVisiblePopup && (currentView !== 'translate' || !translationPresentation.presented
    || payload.presentationEpoch !== translationPresentation.epoch || visiblePopupUpdateBaseline?.epoch !== presentationEpoch
    || visiblePopupUpdateBaseline.generation !== generation)) return;
  // Preserve an unfinished credentials editor rather than displaying it over a
  // captured translation or silently discarding its fields. Latest capture wins.
  if (allModals.some((modal) => !modal.hidden)) { queuedCapture = payload; queuedInputFocus = false; return; }
  pendingTranslate = false; clearToast();
  setView('translate');
  const normalized = payload.mode === 'input' ? payload.text : normalizeCapturedText(payload.text);
  setSourceText(normalized);
  // A passive shortcut must not revive a control's old keyboard-focus ring.
  // Blur only this WebView's retained DOM focus; never focus another element
  // or activate the native window. Explicit Alt+A still focuses the editor.
  if (document.activeElement instanceof HTMLElement && document.activeElement.closest('.app-shell')) document.activeElement.blur();
  if (payload.permissionRequired) showPermissionGuidance(payload.permissionRequired);
  if (payload.mode === 'input') $<HTMLDetailsElement>('#popup-services').open = false;
  if (normalized !== payload.text && payload.mode !== 'input') {
    originalCapture = payload;
    const restore = $('#restore-original-breaks');
    restore.textContent = payload.mode === 'translate' ? '按原始换行重新翻译' : '恢复原始换行';
    restore.hidden = false;
  }
  const token = generation;
  try {
    const presentation = await panelLayout.presentPopup(presentationEpoch, Boolean(payload.focusInput), Boolean(payload.updateVisiblePopup));
    if (presentation) applyTranslationPresentation(presentation);
    else if (desktop) return;
  } catch (error) {
    if (errorMessage(error).startsWith('CANCELLED:')) return;
    throw error;
  }
  if (token !== generation || currentView !== 'translate') return;
  if (payload.mode === 'translate') { if (settingsReady) run(translate); else pendingTranslate = true; }
  else if (payload.mode === 'ocr') status('文字识别完成');
  // Empty Alt+D is now an explicit input action. Nonempty selection/OCR stays
  // passive; only the epoch-bound input payload may activate and focus.
  if (payload.focusInput) source.focus({ preventScroll: true });
}
function requestInputFocus(): void {
  if (allModals.some((modal) => !modal.hidden)) { queuedInputFocus = true; queuedCapture = null; return; }
  clearPermissionGuidance(); setView('translate'); requestAnimationFrame(() => source.focus());
}
async function openSettingsFromNative(payload: { presentationEpoch: number }): Promise<void> {
  if (!settingsReady) {
    if (!pendingSettingsOpen || payload.presentationEpoch > pendingSettingsOpen.presentationEpoch) pendingSettingsOpen = payload;
    return;
  }
  if (payload.presentationEpoch < translationPresentation.epoch || payload.presentationEpoch <= latestSettingsOpenEpoch) return;
  latestSettingsOpenEpoch = payload.presentationEpoch;
  pendingTranslate = false;
  clearToast(); clearPermissionGuidance(); stopPendingTranslation();
  setView('settings');
  try {
    const presentation = await panelLayout.presentManagement(payload.presentationEpoch);
    if (presentation) applyTranslationPresentation(presentation);
  } catch (error) {
    if (!errorMessage(error).startsWith('CANCELLED:')) throw error;
  }
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
  utterance.lang = ({ 'zh-Hans': 'zh-CN', 'zh-Hant': 'zh-TW', en: 'en-US', ja: 'ja-JP', ko: 'ko-KR' } as Record<string, string>)[language] ?? (language === 'auto' ? '' : language);
  utterance.onerror = (event) => { if (!['canceled', 'interrupted'].includes(event.error)) toast('朗读不可用，请检查系统语音与网络设置。', 'error'); };
  window.speechSynthesis.speak(utterance);
}
function updateResultView(view: ResultView, result: TranslationResult, done: boolean): void {
  view.result = result; view.done = done;
  view.card.setAttribute('aria-busy', String(!done));
  view.body.className = result.error ? 'result-error' : !done && !result.text ? 'result-loading' : 'result-text';
  const content = result.error ? userFacingError(result.error) : result.text;
  const previous = view.body.textContent ?? '';
  if (content !== previous) {
    if (view.body.childNodes.length === 1 && view.body.firstChild instanceof Text && content.startsWith(previous)) {
      view.body.firstChild.appendData(content.slice(previous.length));
    } else view.body.textContent = content;
  }
  if (!done && !result.text) view.body.append(node('span', 'spinner'), node('span', 'sr-only', '正在翻译'));
  for (const button of view.actions.slice(0, 2)) button.disabled = !!result.error || !result.text.trim();
  view.actions[2].disabled = translating;
}
function createResultView(result: TranslationResult, done: boolean): ResultView {
  const card = node('article', 'result-card'); card.tabIndex = 0; card.dataset.providerId = result.providerId;
  const header = node('div', 'result-card-header');
  const name = node('span', 'result-provider');
  name.append(node('span', 'provider-dot'), document.createTextNode(result.providerName));
  header.append(name);
  const body = node('p');
  const actions = node('div', 'result-actions'); actions.setAttribute('role', 'group'); actions.setAttribute('aria-label', `${result.providerName}译文操作`);
  const view: ResultView = { card, body, actions: [], result, done, sequence: 0 };
  const read = actionButton('朗读译文', 'audio', () => speak(view.result.text, targetLanguage.value));
  const copy = actionButton('复制译文', 'copy', () => run(() => copyText(view.result.text)));
  const retry = actionButton('重新翻译', 'history', () => run(translate)); retry.classList.add('result-retry');
  view.actions = [read, copy, retry]; actions.append(...view.actions);
  card.append(header, body, actions); updateResultView(view, result, done);
  return view;
}
function receiveTranslationProgress(payload: TranslationProgress): void {
  if (!translating || activeTranslationId === null || payload.requestId !== activeTranslationId
      || payload.presentationEpoch !== progressEpoch || payload.presentationEpoch !== translationPresentation.epoch
      || !translationPresentation.presented || currentView !== 'translate') return;
  const view = progressViews.get(payload.result.providerId);
  if (!view || view.done || !Number.isSafeInteger(payload.sequence) || payload.sequence <= view.sequence) return;
  view.sequence = payload.sequence;
  // Provider identity comes from the request snapshot, not a changing event label.
  updateResultView(view, { ...payload.result, providerName: view.result.providerName }, payload.done);
  if (!view.card.isConnected) resultsContainer.replaceChildren(...[...progressViews.values()].map((item) => item.card));
  $('#translation-state').textContent = payload.done ? '正在翻译' : '正在输出';
  notifyLayout();
}
function renderResults(results: TranslationResult[]): void {
  const existing = new Map(progressViews);
  progressViews.clear(); progressEpoch = null;
  if (results.length === 0) { emptyResults(); return; }
  $('.results-column').hidden = false;
  $('#popup-services').hidden = true;
  const cards = results.map((result) => {
    const view = existing.get(result.providerId) ?? createResultView(result, true);
    if (existing.has(result.providerId)) updateResultView(view, result, true);
    return view.card;
  });
  for (const child of [...resultsContainer.children]) if (!cards.includes(child as HTMLElement)) child.remove();
  cards.forEach((card, index) => {
    if (resultsContainer.children[index] !== card) resultsContainer.insertBefore(card, resultsContainer.children[index] ?? null);
  });
  const success = results.filter((result) => !result.error).length;
  $('#translation-state').textContent = success === results.length ? '翻译完成' : `${success} / ${results.length} 个服务成功`;
  notifyLayout();
}
async function translate(): Promise<void> {
  const text = source.value.trim();
  if (!text || translating) return;
  if (!settingsReady) throw new Error('设置正在加载，请稍候。');
  if (text.length > MAX_TEXT_LENGTH) throw new Error('每次最多翻译 20,000 字符。');
  if (!requireDesktop()) return;
  if (!settings.providers.some((provider) => provider.enabled)) { setView('settings'); toast('请先添加并启用一个翻译服务。'); return; }
  const token = ++generation;
  const presentationEpoch = translationPresentation.epoch;
  const from = sourceLanguage.value, to = targetLanguage.value;
  currentResults = []; resultSource = '';
  progressViews.clear(); progressEpoch = presentationEpoch;
  setLoading(true);
  resultsContainer.replaceChildren();
  $('.results-column').hidden = false;
  const loading = node('div', 'result-loading'); loading.append(node('span', 'spinner'), node('span', 'sr-only', '正在翻译'));
  resultsContainer.append(loading); notifyLayout();
  $('#translation-state').textContent = '正在翻译';
  status('正在翻译…');
  try {
    const requestId = await beginTranslation(presentationEpoch);
    if (token !== generation) { await invoke('cancel_translation', { requestId }); return; }
    activeTranslationId = requestId;
    for (const provider of settings.providers.filter((item) => item.enabled)) {
      progressViews.set(provider.id, createResultView({ providerId: provider.id, providerName: provider.name, text: '', elapsedMs: 0 }, false));
    }
    const results = await invoke<TranslationResult[]>('translate', { requestId, text, sourceLanguage: from, targetLanguage: to });
    if (token !== generation) return;
    currentResults = results;
    resultSource = text;
    renderResults(results);
    status(results.some((result) => !result.error) ? '翻译完成' : '服务返回错误');
  } catch (error) {
    if (token !== generation) return;
    if (errorMessage(error).startsWith('CANCELLED:')) { invalidateResults(); status('翻译已取消'); return; }
    resultsContainer.replaceChildren();
    const card = node('article', 'result-card');
    card.append(node('p', 'result-error', userFacingError(error)));
    resultsContainer.append(card); $('.results-column').hidden = false; notifyLayout();
    $('#translation-state').textContent = '翻译失败';
    status('翻译失败');
  } finally {
    if (token === generation) {
      activeTranslationId = null; setLoading(false);
      for (const retry of resultsContainer.querySelectorAll<HTMLButtonElement>('.result-retry')) retry.disabled = false;
    }
    await loadHistory().catch(() => undefined);
  }
}
function renderShortcutHints(): void {
  for (const element of document.querySelectorAll<HTMLElement>('[data-shortcut]')) {
    element.textContent = settings.shortcuts[element.dataset.shortcut as ShortcutAction] || '未设置';
  }
  source.placeholder = '输入或粘贴文字';
  for (const button of document.querySelectorAll<HTMLElement>('[data-action="capture"]')) button.title = `截图翻译${settings.shortcuts.capture ? ` · ${settings.shortcuts.capture}` : ''}`;
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
    empty.append(icon(favoritesOnly ? 'star' : 'history'), node('h2', '', query ? '没有找到相关翻译' : favoritesOnly ? '暂无收藏' : '暂无翻译记录'), node('p', '', query ? '试试搜索原文或译文中的其他关键词。' : favoritesOnly ? '点击历史记录旁的星标，即可加入收藏。' : '完成翻译后，最近记录会出现在这里。'));
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
function providerKindLabel(kind: ProviderKind): string { return { offline: '本机离线翻译', system: '系统翻译', openai: 'OpenAI 兼容', deepl: 'DeepL', libretranslate: 'LibreTranslate' }[kind]; }
function renderProviders(): void {
  const list = $('#provider-list'); list.replaceChildren();
  $<HTMLButtonElement>('#add-provider').disabled = !settingsReady || settings.providers.length >= 12;
  if (settings.providers.length === 0) {
    const empty = node('div', 'provider-empty');
    empty.append(node('div', '', '还没有翻译服务。可检查系统翻译是否可用，或添加 OpenAI 兼容接口、DeepL 与 LibreTranslate。'), node('div', '', '你可以使用自己的服务商、模型和 API 地址。'));
    list.append(empty); return;
  }
  for (const provider of settings.providers) {
    const row = node('div', 'provider-row');
    row.append(node('span', 'provider-avatar', provider.name.slice(0, 1).toUpperCase()));
    const info = node('div', 'provider-info');
    const title = node('div', 'provider-title', provider.name);
    if (isLocalProvider(provider.kind)) title.append(node('span', 'provider-key-badge', '· 无需 API Key'));
    else title.append(node('span', 'provider-key-badge', `· ${credentialStatusLabel(provider)}`));
    info.append(title, node('span', 'provider-details', provider.kind === 'offline' ? '内置中英模型 · 离线使用 · 无需配置' : provider.kind === 'system' ? '本机语言包 · 首次使用请检查下方准备状态' : `${providerKindLabel(provider.kind)}${provider.model ? ` · ${provider.model}` : ''} · ${provider.baseUrl}`));
    const controls = node('div', 'provider-controls');
    const enabled = node('input', 'switch'); enabled.type = 'checkbox'; enabled.checked = provider.enabled;
    enabled.setAttribute('aria-label', `启用 ${provider.name}`);
    enabled.addEventListener('change', () => {
      const value = enabled.checked; enabled.disabled = true;
      run(async () => { try { await updateSettings((next) => { const found = next.providers.find((item) => item.id === provider.id); if (found) found.enabled = value; }); } finally { renderProviders(); } });
    });
    const testLabel = isLocalProvider(provider.kind) ? '测试翻译' : '测试连接';
    const test = node('button', 'text-button', testLabel);
    test.title = provider.kind === 'offline' ? '使用内置模型离线翻译 Hello' : provider.kind === 'system' ? '使用已准备的本机语言包翻译 Hello，不会自动下载' : '发送 Hello 测试服务，可能消耗少量 API 额度';
    test.addEventListener('click', () => run(async () => {
      if (!requireDesktop()) return;
      test.disabled = true; test.textContent = '测试中…';
      toast(provider.kind === 'offline' ? '正在使用内置模型离线翻译 Hello。' : provider.kind === 'system' ? '正在使用本机语言包翻译 Hello。' : '正在发送 Hello 测试连接，可能消耗少量 API 额度。');
      try {
        const message = await invoke<string>('test_provider', { providerId: provider.id });
        toast(message || '服务连接成功。');
      } finally {
        test.disabled = false; test.textContent = testLabel;
        try { settings = await invoke<Settings>('get_settings'); renderProviders(); }
        catch (error) { reportError(error); }
      }
    }));
    const edit = node('button', 'text-button', '编辑'); edit.addEventListener('click', () => openProviderDialog(provider));
    const remove = actionButton(`删除 ${provider.name}`, 'trash', () => run(async () => {
      if (!await confirmAction('删除翻译服务？', isLocalProvider(provider.kind) ? `将移除“${provider.name}”配置。已安装的本机语言资源会保留。` : `将移除“${provider.name}”及其已保存的 API 密钥。`)) return;
      if (desktop && !isLocalProvider(provider.kind)) await invoke('delete_api_key', { providerId: provider.id });
      await updateSettings((next) => { next.providers = next.providers.filter((item) => item.id !== provider.id); });
      toast('翻译服务已删除。');
    }));
    controls.append(enabled, test, edit, remove); row.append(info, controls); list.append(row);
  }
}
function renderPopupServices(): void {
  const enabled = settings.providers.filter((provider) => provider.enabled);
  $('#popup-services-summary').textContent = enabled.map((provider) => provider.name).join(' · ');
  const list = $('#popup-services-list'); list.replaceChildren();
  for (const provider of settings.providers) {
    const label = node('label', 'popup-service-option'); const checkbox = node('input');
    checkbox.type = 'checkbox'; checkbox.checked = provider.enabled; checkbox.disabled = !settingsReady;
    checkbox.addEventListener('change', () => run(async () => {
      const enabled = checkbox.checked; checkbox.disabled = true;
      try { await updateSettings((next) => { const item = next.providers.find((candidate) => candidate.id === provider.id); if (item) item.enabled = enabled; }); }
      finally { renderPopupServices(); }
    }));
    label.append(checkbox, node('span', '', provider.name)); list.append(label);
  }
  const manage = node('button', 'text-button', '管理翻译服务'); manage.type = 'button';
  manage.addEventListener('click', () => setView('settings')); list.append(manage);
  notifyLayout();
}
function systemTranslationPair(): { sourceLanguage: string; targetLanguage: string } {
  return { sourceLanguage: $<HTMLSelectElement>('#system-translation-source').value, targetLanguage: $<HTMLSelectElement>('#system-translation-target').value };
}
function renderSystemTranslationSetup(): void {
  const from = $<HTMLSelectElement>('#system-translation-source');
  const to = $<HTMLSelectElement>('#system-translation-target');
  for (const select of [from, to]) {
    if (select.options.length === 0) for (const [value, label] of LANGUAGES) {
      if (value === 'auto') continue;
      const option = node('option', '', label); option.value = value; select.append(option);
    }
  }
  if (!systemTranslationLanguagesInitialized) {
    from.value = settings.sourceLanguage === 'auto' ? 'en' : settings.sourceLanguage;
    to.value = settings.targetLanguage === 'auto' ? 'zh-Hans' : settings.targetLanguage;
    if (!from.value) from.value = 'en';
    if (!to.value) to.value = 'zh-Hans';
    systemTranslationLanguagesInitialized = settingsReady;
  }
  const pair = systemTranslationPair();
  $('#system-translation-pair').textContent = `准备 ${languageName(pair.sourceLanguage)} → ${languageName(pair.targetLanguage)}；仅影响此处检查和准备的语言包。`;
  from.disabled = to.disabled = systemTranslationPreparing;
  $<HTMLButtonElement>('#refresh-system-translation').disabled = !settingsReady || systemTranslationBusy;
  const prepare = $<HTMLButtonElement>('#prepare-system-translation');
  prepare.disabled = !settingsReady || systemTranslationBusy || !systemTranslationStatus?.supported || systemTranslationStatus.ready || systemTranslationStatus.requiresSetup !== true;
  prepare.textContent = systemTranslationPreparing ? '正在准备语言包…' : '准备语言包';
  const systemProvider = settings.providers.find((provider) => provider.kind === 'system');
  const enable = $<HTMLButtonElement>('#enable-system-translation');
  enable.hidden = !systemTranslationStatus?.supported || Boolean(systemProvider?.enabled);
  enable.disabled = !settingsReady || systemTranslationBusy || (!systemProvider && settings.providers.length >= 12);
  if (!desktop) $('#system-translation-status').textContent = '浏览器预览无法检查本机翻译能力，请在桌面应用中检查。';
}
async function refreshSystemTranslationStatus(prepare = false): Promise<void> {
  if (!desktop || !settingsReady || systemTranslationPreparing) { renderSystemTranslationSetup(); return; }
  if (prepare && (!systemTranslationStatus?.supported || systemTranslationStatus.ready || systemTranslationStatus.requiresSetup !== true)) return;
  const epoch = ++systemTranslationStatusEpoch;
  systemTranslationBusy = true; systemTranslationPreparing = prepare;
  $('#system-translation-status').textContent = prepare ? '正在准备所选语言包；请按系统提示确认。' : '正在检查所选语言对…';
  renderSystemTranslationSetup();
  try {
    const result = await invoke<SystemTranslationStatus>(prepare ? 'prepare_system_translation' : 'get_system_translation_status', systemTranslationPair());
    if (epoch !== systemTranslationStatusEpoch) return;
    systemTranslationStatus = result;
    $('#system-translation-status').textContent = result.message;
  } catch (error) {
    if (epoch !== systemTranslationStatusEpoch) return;
    systemTranslationStatus = null;
    $('#system-translation-status').textContent = `系统翻译检查失败：${userFacingError(error)}。已有翻译服务配置会保留。`;
  } finally {
    if (epoch === systemTranslationStatusEpoch) {
      systemTranslationBusy = false; systemTranslationPreparing = false;
      renderSystemTranslationSetup(); notifyLayout();
    }
  }
}
function renderSettings(): void {
  renderProviders(); renderPopupServices();
  renderSystemTranslationSetup();
  ocrUi.render();
  const shortcutsForm = $('#shortcuts-form'); shortcutsForm.replaceChildren();
  for (const [action, label] of Object.entries(SHORTCUT_LABELS)) {
    const row = node('label', 'shortcut-row'); row.append(node('span', '', label));
    const input = node('input'); input.type = 'text'; input.value = settings.shortcuts[action as ShortcutAction]; input.name = action; input.maxLength = 80; input.autocomplete = 'off'; input.spellcheck = false; input.placeholder = '留空禁用';
    input.setAttribute('aria-label', `${label}快捷键`); row.append(input); shortcutsForm.append(row);
  }
  $<HTMLSelectElement>('#theme-select').value = settings.theme;
  $<HTMLInputElement>('#save-history').checked = settings.saveHistory;
  $<HTMLInputElement>('#max-history').value = String(settings.maxHistory);
}
function updateProviderCredentialState(clearOnScopeChange = true): void {
  if (isLocalProvider($<HTMLSelectElement>('#provider-kind').value)) {
    $<HTMLInputElement>('#provider-key').value = '';
    providerLastInputScope = null;
    $('#remove-provider-key').hidden = true;
    return;
  }
  const scope = credentialScope($<HTMLSelectElement>('#provider-kind').value, $<HTMLInputElement>('#provider-url').value);
  if (clearOnScopeChange && scope !== providerLastInputScope) $<HTMLInputElement>('#provider-key').value = '';
  providerLastInputScope = scope;
  const changed = providerScopeAtOpen !== null && scope !== providerScopeAtOpen;
  const state = changed ? 'missing' : providerCredentialStateAtOpen;
  $<HTMLInputElement>('#provider-key').placeholder = {
    ready: '已保存匹配此服务的密钥；留空保持不变',
    missing: '输入当前服务的 API 密钥',
    blocked: '凭据读取受阻；留空保留已有凭据',
    unloaded: '凭据尚未读取；留空保留已有凭据',
  }[state];
  $('#provider-key-help').textContent = changed ? '服务协议或地址来源已改变，原密钥不会复用。请为当前服务配置新密钥；留空只保存未配置凭据的服务。'
    : state === 'ready' ? '留空保留匹配当前协议及地址来源的密钥。修改模型或同源路径无需重新填写。'
    : state === 'blocked' ? '此前未能读取凭据。可在服务列表中点击“测试连接”重试；留空保存不会删除已有凭据，也可填写新密钥替换。'
    : state === 'unloaded' ? '打开设置不会读取系统凭据。首次使用服务时再读取；留空保存不会删除已有凭据，也可填写新密钥替换。'
    : 'API 密钥单独写入系统凭据库。LibreTranslate 按实例要求可不填。';
  $('#remove-provider-key').hidden = !credentialMayExist({ credentialState: state });
}
function renderProviderPreset(applyValues = false): void {
  const preset = PROVIDER_PRESETS.find((item) => item.id === $<HTMLSelectElement>('#provider-preset').value) ?? PROVIDER_PRESETS.find((item) => item.id === 'openai')!;
  const qwen = preset.id === 'qwen';
  $('#provider-preset-help').textContent = preset.help;
  $('#provider-qwen-region-field').hidden = !qwen;
  $('#provider-qwen-workspace-field').hidden = !qwen;
  if (!applyValues) return;
  $<HTMLSelectElement>('#provider-kind').value = preset.kind;
  const name = $<HTMLInputElement>('#provider-name');
  if (!name.value.trim() || PROVIDER_PRESETS.some((item) => item.name === name.value)) name.value = preset.name;
  $<HTMLInputElement>('#provider-url').value = qwen ? qwenBaseUrl($<HTMLSelectElement>('#provider-qwen-region').value as QwenRegion, $<HTMLInputElement>('#provider-qwen-workspace').value) : preset.baseUrl;
  $<HTMLInputElement>('#provider-model').value = preset.exampleModel;
  if (isLocalProvider(preset.kind)) $<HTMLTextAreaElement>('#provider-prompt').value = '';
  $<HTMLInputElement>('#provider-key').value = '';
  providerKindChanged(); updateProviderCredentialState();
}
function updateQwenBaseUrl(): void {
  try {
    $<HTMLInputElement>('#provider-url').value = qwenBaseUrl($<HTMLSelectElement>('#provider-qwen-region').value as QwenRegion, $<HTMLInputElement>('#provider-qwen-workspace').value);
    $('#provider-error').hidden = true; updateProviderCredentialState();
  } catch (error) { $('#provider-error').textContent = errorMessage(error); $('#provider-error').hidden = false; }
}
function providerKindChanged(useDefaults = false): void {
  const kind = $<HTMLSelectElement>('#provider-kind').value as ProviderKind;
  const openai = kind === 'openai';
  const system = isLocalProvider(kind);
  $('#provider-url-field').hidden = system;
  $('#provider-key-field').hidden = system;
  $('#provider-model-field').hidden = !openai;
  $('#provider-prompt-field').hidden = !openai;
  $<HTMLInputElement>('#provider-model').required = openai;
  const url = $<HTMLInputElement>('#provider-url');
  const defaults = { offline: '', system: '', openai: 'https://api.openai.com/v1', deepl: 'https://api-free.deepl.com/v2', libretranslate: 'http://127.0.0.1:5000' };
  url.required = !system;
  url.placeholder = defaults[kind];
  if (useDefaults) url.value = defaults[kind];
  if (system) {
    url.value = ''; $<HTMLInputElement>('#provider-model').value = ''; $<HTMLTextAreaElement>('#provider-prompt').value = ''; $<HTMLInputElement>('#provider-key').value = '';
  }
  $('#provider-url-help').textContent = {
    offline: '内置离线翻译无需 API 地址。',
    system: '系统翻译无需 API 地址。',
    openai: '填写 API 基础地址，无需包含 /chat/completions。DeepSeek、Ollama 等请填写对应地址。',
    deepl: '免费账户通常使用 api-free.deepl.com，付费账户使用 api.deepl.com。无需包含 /v2/translate。',
    libretranslate: '填写你使用的 LibreTranslate 服务地址，无需包含 /translate。',
  }[kind];
}
// Use a plain HTML overlay for consistent focus and keyboard behavior across WebViews.
// Desktop screenshot / accessibility capture anomalies were observed, but the user
// confirmed the app was visible; native dialog rendering was not established as a cause.
function modalFocusable(modal: HTMLElement): HTMLElement[] {
  return Array.from(modal.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'))
    .filter((element) => element.getClientRects().length > 0 && !element.closest('[hidden]'));
}
function showModal(modal: HTMLElement): void {
  modalReturnFocus.set(modal, document.activeElement instanceof HTMLElement ? document.activeElement : null);
  modal.hidden = false;
  const panel = modal.querySelector<HTMLElement>('.modal-panel');
  if (panel) panel.scrollTop = 0;
  document.body.classList.add('modal-open');
  (modalFocusable(modal)[0] ?? modal).focus({ preventScroll: true });
  // Inert is supported by recent WebKit; the focus trap below also protects older engines.
  $('.app-shell').inert = true;
  $('.app-shell').setAttribute('aria-hidden', 'true');
}
function closeModal(modal: HTMLElement): void {
  modal.hidden = true;
  const anotherModal = allModals.find((candidate) => !candidate.hidden);
  if (!anotherModal) {
    $('.app-shell').inert = false;
    $('.app-shell').removeAttribute('aria-hidden');
    document.body.classList.remove('modal-open');
  }
  const previous = modalReturnFocus.get(modal);
  modalReturnFocus.delete(modal);
  const fallback = anotherModal ? modalFocusable(anotherModal)[0] : document.querySelector<HTMLElement>('button[data-view].active');
  if (previous?.isConnected && previous.getClientRects().length > 0) previous.focus({ preventScroll: true });
  else fallback?.focus({ preventScroll: true });
  if (!anotherModal && queuedCapture) {
    const payload = queuedCapture; queuedCapture = null;
    queueMicrotask(() => run(() => receiveCapturedText(payload)));
  } else if (!anotherModal && queuedInputFocus) {
    queuedInputFocus = false; queueMicrotask(requestInputFocus);
  }
}
function setProviderSaving(value: boolean): void {
  providerSaving = value;
  providerDialog.setAttribute('aria-busy', String(value));
  for (const control of providerDialog.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | HTMLButtonElement>('input, select, textarea, button')) control.disabled = value;
  $('#save-provider').textContent = value ? '保存中…' : '保存服务';
}
function openProviderDialog(provider?: Provider): void {
  if (providerSaving) return;
  if (!settingsReady) { toast('设置正在加载，请稍候。'); return; }
  if (!provider && settings.providers.length >= 12) { toast('最多可添加 12 个翻译服务。'); return; }
  editingProviderId = provider?.id ?? null;
  providerScopeAtOpen = provider ? credentialScope(provider.kind, provider.baseUrl) : null;
  providerCredentialStateAtOpen = credentialStateOf(provider);
  providerHadKeyAtOpen = !isLocalProvider(provider?.kind ?? '') && providerCredentialStateAtOpen === 'ready'; providerLastInputScope = providerScopeAtOpen;
  $<HTMLFormElement>('#provider-form').reset();
  $<HTMLSelectElement>('#provider-preset').value = provider ? inferProviderPreset(provider) : 'openai';
  const qwenSettings = qwenSettingsFromUrl(provider?.baseUrl ?? '');
  $<HTMLSelectElement>('#provider-qwen-region').value = qwenSettings.region;
  $<HTMLInputElement>('#provider-qwen-workspace').value = qwenSettings.workspaceId;
  $('#provider-dialog-title').textContent = provider ? '编辑翻译服务' : '添加翻译服务';
  $<HTMLInputElement>('#provider-name').value = provider?.name ?? 'OpenAI 兼容服务';
  $<HTMLSelectElement>('#provider-kind').value = provider?.kind ?? 'openai';
  $<HTMLInputElement>('#provider-url').value = provider?.baseUrl ?? 'https://api.openai.com/v1';
  $<HTMLInputElement>('#provider-model').value = provider?.model ?? 'gpt-4o-mini';
  $<HTMLTextAreaElement>('#provider-prompt').value = provider?.prompt ?? '';
  $<HTMLInputElement>('#provider-key').value = '';
  $<HTMLInputElement>('#provider-enabled').checked = provider?.enabled ?? true;
  $('#provider-error').hidden = true;
  providerKindChanged(); renderProviderPreset(); updateProviderCredentialState(false);
  showModal(providerDialog);
}
function closeProviderDialog(): void {
  if (providerSaving) { toast('正在保存服务，请稍候。'); return; }
  $<HTMLInputElement>('#provider-key').value = '';
  closeModal(providerDialog);
  editingProviderId = null; providerScopeAtOpen = null; providerLastInputScope = null; providerHadKeyAtOpen = false; providerCredentialStateAtOpen = 'missing';
}
function confirmAction(title: string, description: string): Promise<boolean> {
  $('#confirm-title').textContent = title;
  $('#confirm-description').textContent = description;
  showModal(confirmDialog);
  return new Promise((resolve) => { confirmResolve = resolve; });
}
function settleConfirm(value: boolean): void { closeModal(confirmDialog); confirmResolve?.(value); confirmResolve = null; }
async function saveProvider(event: SubmitEvent): Promise<void> {
  event.preventDefault();
  if (providerSaving) return;
  if (!desktop) { toast('浏览器预览不保存 API 密钥。请在桌面应用中配置真实服务。'); return; }
  const provider: Provider = {
    id: editingProviderId ?? crypto.randomUUID(), name: $<HTMLInputElement>('#provider-name').value.trim(),
    kind: $<HTMLSelectElement>('#provider-kind').value as ProviderKind,
    baseUrl: $<HTMLInputElement>('#provider-url').value.trim().replace(/\/+$/, ''),
    model: $<HTMLInputElement>('#provider-model').value.trim(),
    enabled: $<HTMLInputElement>('#provider-enabled').checked,
    prompt: $<HTMLTextAreaElement>('#provider-prompt').value.trim(),
    hasKey: !isLocalProvider($<HTMLSelectElement>('#provider-kind').value) && providerHadKeyAtOpen && credentialScope($<HTMLSelectElement>('#provider-kind').value, $<HTMLInputElement>('#provider-url').value) === providerScopeAtOpen,
  };
  let validation = validateProvider(provider);
  if (isLocalProvider(provider.kind) && settings.providers.some((item) => item.kind === provider.kind && item.id !== provider.id)) validation = '已存在此本机翻译服务。请编辑或启用已有服务。';
  if ($<HTMLSelectElement>('#provider-preset').value === 'qwen') {
    try { qwenBaseUrl($<HTMLSelectElement>('#provider-qwen-region').value as QwenRegion, $<HTMLInputElement>('#provider-qwen-workspace').value); }
    catch (error) { validation = errorMessage(error); }
  }
  const errorOutput = $('#provider-error');
  if (validation) { errorOutput.textContent = validation; errorOutput.hidden = false; return; }
  setProviderSaving(true);
  const keyInput = $<HTMLInputElement>('#provider-key');
  const key = keyInput.value.trim();
  try {
    await updateSettings((next) => {
      const index = next.providers.findIndex((item) => item.id === provider.id);
      if (index === -1) next.providers.push(provider); else next.providers[index] = provider;
    });
    editingProviderId = provider.id;
    if (key && !isLocalProvider(provider.kind)) {
      try { await invoke('set_api_key', { providerId: provider.id, key }); }
      catch (error) { throw new Error(`服务已保存，但密钥未能存入系统凭据库：${errorMessage(error)}`); }
    }
    keyInput.value = '';
    settings = await invoke<Settings>('get_settings');
    renderSettings(); setProviderSaving(false); closeProviderDialog(); toast('翻译服务已保存。');
  } catch (error) { errorOutput.textContent = errorMessage(error); errorOutput.hidden = false; }
  finally { setProviderSaving(false); }
}
async function runAction(action: Action): Promise<void> {
  if (action === 'selection') { toast(settings.shortcuts.selection ? `在其他应用中选中文字后，按 ${settings.shortcuts.selection} 即可划词翻译。` : '划词翻译快捷键尚未启用，请到设置中配置。'); return; }
  if (!requireDesktop()) return;
  await invoke('run_action', { action });
}

interface PermissionStatus {
  platform: string; supported: boolean; identity?: string; runningBundledApp?: boolean;
  bundleIdentifier?: string; bundlePath?: string; processId?: number; accessibilityGranted?: boolean; screenCaptureGranted?: boolean;
  screenCaptureState?: 'granted' | 'unconfirmed' | 'inconsistent';
  screenCaptureRequestState?: 'available' | 'denied' | 'failed' | 'timedOut' | 'busy' | 'unsupported';
  screenCaptureAuthorizationConsistent?: boolean;
}
function clearPermissionGuidance(): void {
  permissionGuidanceKind = null;
  $('#permission-guidance').hidden = true;
  $('#permission-guidance-error').hidden = true;
  notifyLayout();
}
function showPermissionGuidance(kind: PermissionKind): void {
  if (!macDesktop || !['accessibility', 'screenCapture'].includes(kind)) return;
  clearToast();
  permissionGuidanceKind = kind;
  $('#permission-guidance-title').textContent = kind === 'screenCapture' ? '截图需要屏幕录制权限' : '划词需要辅助功能权限';
  $('#permission-guidance-description').textContent = kind === 'screenCapture'
    ? '首次使用请在 macOS 系统设置中允许 EchoLingo 录制屏幕。找不到应用时，请查看授权指引。'
    : '请在 macOS 系统设置中允许 EchoLingo 使用辅助功能，以读取选中的文字。';
  $('#permission-guidance-error').hidden = true;
  $('#permission-guidance').hidden = false;
  notifyLayout();
}
function openPermissionGuide(): void {
  setView('settings');
  $<HTMLDetailsElement>('#permission-setup-steps').open = true;
  requestAnimationFrame(() => {
    const card = $('#mac-permission-card');
    card.scrollIntoView({ block: 'start' });
    card.focus({ preventScroll: true });
  });
}
async function openPermissionSettings(kind: PermissionKind, fromGuidance = false): Promise<void> {
  if (!macDesktop || permissionBusy) return;
  setPermissionBusy(true);
  const output = $(fromGuidance ? '#permission-guidance-error' : '#permission-error');
  output.hidden = true;
  try { await invoke('open_permission_settings', { kind }); }
  catch {
    output.textContent = `未能打开系统设置。请手动进入“系统设置 → 隐私与安全（性）”，开启 EchoLingo 的${kind === 'screenCapture' ? '屏幕录制' : '辅助功能'}权限。`;
    output.hidden = false;
    notifyLayout();
  } finally { setPermissionBusy(false); }
}
function renderPermissionStatus(state: PermissionStatus): void {
  $('#mac-permission-card').hidden = !state.supported || state.platform !== 'macos';
  if (!state.supported || state.platform !== 'macos') return;
  for (const [kind, id, granted] of [['accessibility', '#accessibility-permission-state', state.accessibilityGranted], ['screenCapture', '#screen-capture-permission-state', state.screenCaptureGranted]] as const) {
    $(id).textContent = granted ? '已授权' : kind === 'screenCapture'
      ? state.screenCaptureState === 'inconsistent' ? '授权状态不一致' : '当前进程未确认'
      : '待授权';
    $(id).dataset.granted = String(Boolean(granted));
    const button = document.querySelector<HTMLButtonElement>(`[data-request-permission="${kind}"]`);
    if (button) button.hidden = Boolean(granted);
  }
  $('#permission-context').textContent = state.runningBundledApp === false ? '当前为开发进程，请在安装后的 EchoLingo 应用中完成授权。' : '授权对象为此 EchoLingo 应用。系统要求重新打开时，请退出后从应用目录重新启动。';
  if (!state.screenCaptureGranted && state.runningBundledApp !== false) {
    $('#permission-context').textContent = state.screenCaptureState === 'inconsistent'
      ? `系统授权接口与当前进程检查结果不一致。请先退出并重新打开 EchoLingo；仍不一致时，可在系统设置移除旧 EchoLingo 条目，再用「+」添加${state.bundlePath || '当前安装的 EchoLingo.app'}，完成一轮重新登记。`
      : '当前进程尚未确认录屏权限；这不代表系统开关未开启。若开关已开，请点击「验证录屏授权」，按系统提示完成后重新打开应用并刷新。';
  }
  if (state.screenCaptureRequestState && ['failed', 'timedOut', 'busy'].includes(state.screenCaptureRequestState)) {
    $('#permission-error').textContent = state.screenCaptureRequestState === 'busy'
      ? '已有录屏授权请求正在等待系统回应，请先处理当前系统提示。'
      : state.screenCaptureRequestState === 'timedOut'
        ? '系统暂未回应录屏授权请求；请检查系统提示或重新打开应用，不必反复点击。'
        : '未能完成录屏授权验证，请在系统设置核对 EchoLingo 后重新打开应用。';
    $('#permission-error').hidden = false;
  }
  if ((permissionGuidanceKind === 'screenCapture' && state.screenCaptureGranted)
    || (permissionGuidanceKind === 'accessibility' && state.accessibilityGranted)) clearPermissionGuidance();
}
function setPermissionBusy(busy: boolean): void {
  permissionBusy = busy;
  for (const button of $('#mac-permission-card').querySelectorAll<HTMLButtonElement>('button')) button.disabled = busy;
  $<HTMLButtonElement>('#permission-guidance-open').disabled = busy;
}
async function refreshPermissionStatus(): Promise<void> {
  if (!macDesktop || permissionBusy) return;
  $('#mac-permission-card').hidden = false; $('#permission-error').hidden = true; setPermissionBusy(true);
  try { renderPermissionStatus(await invoke<PermissionStatus>('permission_status')); }
  catch (error) { $('#permission-error').textContent = errorMessage(error); $('#permission-error').hidden = false; }
  finally { setPermissionBusy(false); }
}
function handleActionError(message: string): void {
  // Selection/cancellation compatibility only. Screenshot permission, NO_TEXT,
  // OCR service failures and translation failures remain actionable errors.
  if (/^(?:NO_SELECTION|SELECTION_EMPTY|CANCELLED):/i.test(message.trim()) || /^未取得选区/.test(message.trim())) return;
  const guidance = /^PERMISSION:/i.test(message.trim()) ? '\n可在“更多 → 设置 → 系统权限”中检查或授权。' : '';
  toast(`${message}${guidance}`, 'error', 8000);
}

const ocrUi = createOcrUi({
  desktop, settings: () => settings, updateSettings,
  reloadSettings: async () => { settings = await invoke<Settings>('get_settings'); renderSettings(); },
  showModal, closeModal, confirm: confirmAction, toast, reportError,
});

for (const button of document.querySelectorAll<HTMLButtonElement>('button[data-view]')) button.addEventListener('click', () => setView(button.dataset.view ?? 'translate'));
for (const button of document.querySelectorAll<HTMLButtonElement>('[data-action]')) button.addEventListener('click', () => run(() => runAction(button.dataset.action as Action)));
$('#copy-source').addEventListener('click', () => run(() => copyText(source.value)));
$('#speak-source').addEventListener('click', () => speak(source.value, sourceLanguage.value));
source.addEventListener('compositionstart', () => { sourceComposing = true; });
source.addEventListener('compositionend', () => { sourceComposing = false; resizeSourceEditor(); });
source.addEventListener('blur', () => { sourceComposing = false; });
source.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter' || isCompositionKey(event)) return;
  if (event.shiftKey || event.altKey) return;
  event.preventDefault(); event.stopPropagation();
  if (!event.repeat && source.value.trim() && !translating) run(translate);
});
$('#popup-services').addEventListener('toggle', notifyLayout);
$('#refresh-permissions').addEventListener('click', () => { void refreshPermissionStatus(); });
$('#refresh-system-translation').addEventListener('click', () => { void refreshSystemTranslationStatus(); });
$('#prepare-system-translation').addEventListener('click', () => { void refreshSystemTranslationStatus(true); });
for (const id of ['#system-translation-source', '#system-translation-target']) $(id).addEventListener('change', () => {
  systemTranslationStatus = null;
  void refreshSystemTranslationStatus();
});
$('#enable-system-translation').addEventListener('click', () => run(async () => {
  if (!requireDesktop() || !systemTranslationStatus?.supported) return;
  const providerName = systemTranslationStatus.providerName || '系统翻译';
  await updateSettings((next) => {
    const existing = next.providers.find((provider) => provider.kind === 'system');
    if (existing) existing.enabled = true;
    else {
      if (next.providers.length >= 12) throw new Error('最多可添加 12 个翻译服务。请先删除不需要的配置。');
      const id = next.providers.some((provider) => provider.id === 'system-translation') ? crypto.randomUUID() : 'system-translation';
      next.providers.push({ id, name: providerName, kind: 'system', baseUrl: '', model: '', prompt: '', enabled: true, hasKey: false });
    }
  });
}));
$('#permission-guidance-open').addEventListener('click', () => {
  if (permissionGuidanceKind) void openPermissionSettings(permissionGuidanceKind, true);
});
$('#permission-guidance-help').addEventListener('click', openPermissionGuide);
$('#permission-guidance-dismiss').addEventListener('click', clearPermissionGuidance);
for (const button of document.querySelectorAll<HTMLButtonElement>('[data-request-permission]')) button.addEventListener('click', () => {
  if (!macDesktop || permissionBusy) return;
  const kind = button.dataset.requestPermission as PermissionKind;
  setPermissionBusy(true); $('#permission-error').hidden = true;
  void invoke<PermissionStatus>('request_permission', { kind }).then(renderPermissionStatus).catch((error) => {
    $('#permission-error').textContent = errorMessage(error); $('#permission-error').hidden = false;
  }).finally(() => setPermissionBusy(false));
});
for (const button of document.querySelectorAll<HTMLButtonElement>('[data-open-permission]')) button.addEventListener('click', () => {
  void openPermissionSettings(button.dataset.openPermission as PermissionKind);
});
window.addEventListener('focus', () => { if (currentView === 'settings') void refreshPermissionStatus(); });
translateButton.addEventListener('click', () => { if (translating) stopPendingTranslation(); else run(translate); });
source.addEventListener('input', () => { clearPermissionGuidance(); clearOriginalCapture(); resizeSourceEditor(); invalidateResults(); });
window.addEventListener('resize', resizeSourceEditor);
$('#restore-original-breaks').addEventListener('click', () => {
  const original = originalCapture;
  if (!original) return;
  closeMoreMenu(); setSourceText(original.text);
  if (original.mode === 'translate') run(translate);
});
$('#clear-source').addEventListener('click', () => { setSourceText(''); });
for (const select of [sourceLanguage, targetLanguage]) select.addEventListener('change', () => {
  invalidateResults();
  run(() => updateSettings((next) => { next.sourceLanguage = sourceLanguage.value; next.targetLanguage = targetLanguage.value; }));
});
$('#swap-language').addEventListener('click', () => {
  if (sourceLanguage.value === 'auto' || targetLanguage.value === 'auto') { toast('自动模式会按原文决定翻译方向；需要交换时，请先选择具体语言。'); return; }
  const previousSource = sourceLanguage.value;
  sourceLanguage.value = targetLanguage.value; targetLanguage.value = previousSource;
  if (currentResults.find((result) => !result.error)?.text && resultSource === source.value.trim()) setSourceText(currentResults.find((result) => !result.error)!.text);
  else invalidateResults();
  run(() => updateSettings((next) => { next.sourceLanguage = sourceLanguage.value; next.targetLanguage = targetLanguage.value; }));
});
$('#more-toggle').addEventListener('click', (event) => {
  if ($('#popup-more-menu').hidden) openMoreMenu(event.detail === 0); else closeMoreMenu();
});
for (const id of ['#close-popup', '#close-management']) $(id).addEventListener('click', () => run(async () => {
  closeMoreMenu(); stopPendingTranslation(); if (requireDesktop()) await invoke('hide_window');
}));
$('#popup-more-menu').addEventListener('click', (event) => {
  if ((event.target as HTMLElement).closest('button[role="menuitem"]')) closeMoreMenu();
});
document.addEventListener('pointerdown', (event) => {
  if (!$('#popup-more-menu').hidden && !(event.target as HTMLElement).closest('.popup-toolbar')) closeMoreMenu();
});
window.addEventListener('resize', () => { if (currentView === 'translate') resizeSourceEditor(); });
$('#pin-button').addEventListener('click', () => run(async () => {
  if (!requireDesktop()) return;
  const next = !pinned; await invoke('set_pinned', { pinned: next }); pinned = next;
  const pinButton = $('#pin-button');
  pinButton.setAttribute('aria-pressed', String(pinned));
  pinButton.setAttribute('aria-label', pinned ? '取消钉住' : '钉住窗口');
  pinButton.title = pinned ? '已固定 · 点击取消固定' : '未固定 · 点击固定窗口';
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
$<HTMLInputElement>('#max-history').addEventListener('change', (event) => {
  const input = event.target as HTMLInputElement;
  const value = input.valueAsNumber;
  if (!Number.isInteger(value) || value < 1 || value > 100) {
    input.value = String(settings.maxHistory);
    toast('历史记录条数须为 1–100 的整数。', 'error');
    return;
  }
  run(async () => {
    try { await updateSettings((next) => { next.maxHistory = value; }); await loadHistory(); }
    finally { renderSettings(); }
  });
});
$('#save-shortcuts').addEventListener('click', () => run(async () => {
  const values = Object.fromEntries(new FormData($<HTMLFormElement>('#shortcuts-form')).entries()) as Record<ShortcutAction, string>;
  const normalized = Object.values(values).map((value) => value.trim().toLowerCase()).filter(Boolean);
  if (new Set(normalized).size !== normalized.length) throw new Error('不同操作不能使用相同的快捷键。');
  await updateSettings((next) => { for (const action of Object.keys(SHORTCUT_LABELS) as ShortcutAction[]) next.shortcuts[action] = values[action].trim(); });
  toast(desktop ? '快捷键已保存。若注册失败，将显示系统返回的原因。' : '快捷键已在预览中更新；桌面应用才能注册全局快捷键。');
}));
$('#add-provider').addEventListener('click', () => openProviderDialog());
$('#provider-kind').addEventListener('change', () => { providerKindChanged(true); updateProviderCredentialState(); });
$('#provider-url').addEventListener('input', () => updateProviderCredentialState());
$('#provider-preset').addEventListener('change', () => renderProviderPreset(true));
$('#provider-qwen-region').addEventListener('change', updateQwenBaseUrl);
$('#provider-qwen-workspace').addEventListener('change', updateQwenBaseUrl);
$('#close-provider-dialog').addEventListener('click', closeProviderDialog);
$('#cancel-provider-dialog').addEventListener('click', closeProviderDialog);
providerDialog.addEventListener('click', (event) => { if (event.target === providerDialog) closeProviderDialog(); });
$<HTMLFormElement>('#provider-form').addEventListener('submit', (event) => { void saveProvider(event).catch(reportError); });
$('#remove-provider-key').addEventListener('click', () => run(async () => {
  if (!editingProviderId || providerSaving || !requireDesktop()) return;
  if (isLocalProvider($<HTMLSelectElement>('#provider-kind').value)) return;
  const providerId = editingProviderId; setProviderSaving(true);
  try {
    await invoke('delete_api_key', { providerId });
    settings = await invoke<Settings>('get_settings'); renderProviders();
    providerHadKeyAtOpen = false; providerCredentialStateAtOpen = 'missing'; updateProviderCredentialState(false);
    toast('已从系统凭据库移除密钥。');
  } finally { setProviderSaving(false); }
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
confirmDialog.addEventListener('click', (event) => { if (event.target === confirmDialog) settleConfirm(false); });
document.addEventListener('keydown', (event) => {
  if (isCompositionKey(event)) return;
  const modal = allModals.find((candidate) => !candidate.hidden);
  if (modal) {
    if (event.key === 'Escape') {
      event.preventDefault(); event.stopPropagation();
      if (modal === confirmDialog) settleConfirm(false); else if (modal === ocrDialog) ocrUi.close(); else closeProviderDialog();
    } else if (event.key === 'Tab') {
      const focusable = modalFocusable(modal);
      const first = focusable[0], last = focusable[focusable.length - 1];
      if (!first) { event.preventDefault(); modal.focus(); }
      else if (event.shiftKey && (document.activeElement === first || !modal.contains(document.activeElement))) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && (document.activeElement === last || !modal.contains(document.activeElement))) { event.preventDefault(); first.focus(); }
    }
    return;
  }
  if (event.key === 'Escape' && !$('#popup-more-menu').hidden) {
    event.preventDefault(); event.stopPropagation(); closeMoreMenu(true); return;
  }
  if (event.key === 'ArrowDown' && document.activeElement === $('#more-toggle')) {
    event.preventDefault(); openMoreMenu(true); return;
  }
  if (!$('#popup-more-menu').hidden && ['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
    const items = Array.from($('#popup-more-menu').querySelectorAll<HTMLButtonElement>('button')).filter((button) => !button.disabled && !button.hidden);
    const current = items.indexOf(document.activeElement as HTMLButtonElement);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : (current + (event.key === 'ArrowUp' ? -1 : 1) + items.length) % items.length;
    event.preventDefault(); items[next]?.focus({ preventScroll: true }); return;
  }
  if (event.key === 'Enter' && (event.ctrlKey || event.metaKey) && !event.shiftKey && !event.altKey) {
    event.preventDefault(); if (!event.repeat && !translating && source.value.trim()) { setView('translate'); run(translate); }
  }
  if (event.key === 'Escape') {
    if (desktop) { event.preventDefault(); stopPendingTranslation(); run(() => invoke('hide_window')); }
    else if (currentView !== 'translate') setView('translate');
  }
});
window.addEventListener('beforeunload', () => { cancelActiveTranslation(); panelLayout.dispose(); for (const unlisten of cleanupListeners) unlisten(); if ('speechSynthesis' in window) window.speechSynthesis.cancel(); });

async function initialize(): Promise<void> {
  const presetSelect = $<HTMLSelectElement>('#provider-preset');
  for (const preset of PROVIDER_PRESETS) { const option = node('option', '', preset.label); option.value = preset.id as ProviderPresetId; presetSelect.append(option); }
  if (!desktop) {
    $('#preview-banner').hidden = false;
    status('界面预览 · 桌面能力未连接');
  }
  setView('translate');
  $('#speak-source').hidden = !('speechSynthesis' in window);
  applyTheme(); renderLanguages(); renderSettings(); renderShortcutHints(); renderHistory(); emptyResults();
  setLoading(false);
  if (!desktop) return;
  status('正在加载设置…');
  try {
    // Listen before loading settings so an incoming native selection is not lost during startup.
    cleanupListeners.push(await listen<SourceTextEvent & { presentationEpoch?: number }>('source-text', (event) => run(() => receiveCapturedText(event.payload))));
    cleanupListeners.push(await listen('focus-input', requestInputFocus));
    cleanupListeners.push(await listen<{ presentationEpoch: number }>('open-settings', (event) => run(() => openSettingsFromNative(event.payload))));
    cleanupListeners.push(await listen<TranslationPresentation>('translation-presentation', (event) => applyTranslationPresentation(event.payload)));
    cleanupListeners.push(await listen<TranslationProgress>('translation-progress', (event) => receiveTranslationProgress(event.payload)));
    cleanupListeners.push(await listen<string>('action-error', (event) => handleActionError(event.payload)));
    cleanupListeners.push(await listen<string>('shortcut-error', (event) => toast(event.payload, 'error', 8000)));
    applyTranslationPresentation(await invoke<TranslationPresentation>('get_translation_presentation'));
    const startupSettings = await invoke<{ presentationEpoch: number } | null>('get_pending_settings');
    if (startupSettings) pendingSettingsOpen = !pendingSettingsOpen || startupSettings.presentationEpoch > pendingSettingsOpen.presentationEpoch ? startupSettings : pendingSettingsOpen;
    settings = await invoke<Settings>('get_settings');
    settingsReady = true;
    applyTheme(); renderLanguages(); renderSettings(); renderShortcutHints();
    if (!translating) emptyResults();
    await loadHistory(); status('准备就绪');
    if (pendingSettingsOpen) { const request = pendingSettingsOpen; pendingSettingsOpen = null; await openSettingsFromNative(request); }
    if (pendingTranslate) run(translate);
    const diagnostic = await invoke<{ warnings?: unknown }>('diagnostics').catch(() => null);
    if (Array.isArray(diagnostic?.warnings) && diagnostic.warnings.length > 0) toast(diagnostic.warnings.filter((warning): warning is string => typeof warning === 'string').join('\n'), 'error', 10_000);
  } catch (error) {
    status('启动检查失败'); reportError(error);
    const output = $('#diagnostics-output'); output.hidden = false; output.textContent = `启动检查失败：${errorMessage(error)}`;
  } finally { resizeSourceEditor(); }
}
void initialize();
