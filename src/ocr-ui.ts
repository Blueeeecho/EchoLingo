import { credentialScope } from './credential-scope';
import { credentialMayExist, credentialStateOf, credentialStatusLabel } from './credential-state';
import { invoke } from '@tauri-apps/api/core';
import { errorMessage, validateProvider } from './model';
import { buildOcrCredential, isNativeOcr, OCR_NATIVE_ACTIONS, OCR_NATIVE_URLS } from './ocr-credentials';
import { OCR_GUIDES, renderServiceGuide } from './service-guides';
import { OCR_QUOTAS } from './service-quotas';
import { renderServiceQuota } from './service-quota-ui';
import type { CredentialState, OcrProvider, Settings } from './types';

type UiContext = {
  desktop: boolean;
  settings: () => Settings;
  updateSettings: (mutator: (next: Settings) => void) => Promise<void>;
  reloadSettings: () => Promise<void>;
  showModal: (modal: HTMLElement) => void;
  closeModal: (modal: HTMLElement) => void;
  confirm: (title: string, description: string) => Promise<boolean>;
  toast: (message: string, tone?: 'info' | 'error', duration?: number) => void;
  reportError: (error: unknown) => void;
};
const $ = <T extends HTMLElement = HTMLElement>(id: string): T => {
  const element = document.getElementById(id);
  if (!element) throw new Error(`OCR 界面组件不存在：${id}`);
  return element as T;
};
const el = <K extends keyof HTMLElementTagNameMap>(tag: K, className = '', text = ''): HTMLElementTagNameMap[K] => {
  const element = document.createElement(tag); element.className = className; element.textContent = text; return element;
};
const input = (id: string): HTMLInputElement => $<HTMLInputElement>(id);
const textArea = (id: string): HTMLTextAreaElement => $<HTMLTextAreaElement>(id);
const select = (id: string): HTMLSelectElement => $<HTMLSelectElement>(id);

export function createOcrUi(context: UiContext): { render: () => void; close: () => void } {
  const modal = $('ocr-provider-dialog');
  let editingId: string | null = null;
  let saving = false;
  let originalCredentialState: CredentialState = 'missing';
  let originalScope: string | null = null;
  let lastInputScope: string | null = null;
  const secretIds = ['ocr-provider-key', 'ocr-baidu-api-key', 'ocr-baidu-secret-key', 'ocr-tencent-secret-id', 'ocr-tencent-secret-key', 'ocr-tencent-session-token', 'ocr-youdao-app-key', 'ocr-youdao-app-secret'];
  const missingPlaceholders: Record<string, string> = {
    'ocr-baidu-api-key': 'OCR 应用的 API Key', 'ocr-baidu-secret-key': '与 API Key 对应的 Secret Key',
    'ocr-tencent-secret-id': '腾讯云 SecretId', 'ocr-tencent-secret-key': '与 SecretId 对应的 SecretKey',
    'ocr-youdao-app-key': '应用 ID（AppKey）', 'ocr-youdao-app-secret': '应用密钥（AppSecret）',
  };
  const clearSecrets = (): void => { for (const id of secretIds) input(id).value = ''; };
  const kindLabel = (kind: OcrProvider['kind']): string => ({ baidu: '百度 OCR', tencent: '腾讯云 OCR', youdao: '有道 OCR', google: 'Google Cloud Vision OCR', 'openai-vision': '视觉模型', 'http-json': 'HTTP JSON' })[kind];
  const run = (work: () => Promise<unknown>): void => { void work().catch(context.reportError); };
  const setSaving = (value: boolean): void => {
    saving = value; modal.setAttribute('aria-busy', String(value));
    for (const control of modal.querySelectorAll<HTMLInputElement | HTMLButtonElement | HTMLSelectElement | HTMLTextAreaElement>('input, button, select, textarea')) control.disabled = value;
    $('save-ocr-provider').textContent = value ? '处理中…' : '保存 OCR 服务';
  };
  const close = (): void => {
    if (saving) { context.toast('正在保存 OCR 服务，请稍候。'); return; }
    clearSecrets(); context.closeModal(modal); editingId = null; originalCredentialState = 'missing'; originalScope = null; lastInputScope = null;
  };
  const updateCredentialState = (clearOnChange = true): void => {
    const kind = select('ocr-provider-kind').value as OcrProvider['kind'];
    const native = isNativeOcr(kind);
    const scope = credentialScope(kind, native ? OCR_NATIVE_URLS[kind] : input('ocr-provider-url').value);
    if (clearOnChange && scope !== lastInputScope) clearSecrets();
    lastInputScope = scope;
    const changed = originalScope !== null && scope !== originalScope;
    const state = changed ? 'missing' : originalCredentialState;
    $('remove-ocr-provider-key').hidden = !credentialMayExist({ credentialState: state });
    input('ocr-provider-key').placeholder = {
      ready: '密钥已保存；留空保持不变', missing: '输入当前服务密钥（单独存入系统凭据库）',
      blocked: '凭据读取受阻；留空保留已有凭据', unloaded: '凭据尚未读取；留空保留已有凭据',
    }[state];
    const notice = $('ocr-protocol-notice');
    notice.hidden = !changed && !native && !['blocked', 'unloaded'].includes(state);
    notice.textContent = changed ? 'OCR 协议或服务地址来源已改变。请完整填写新凭据，原密钥不会复用；保存失败不会删除原服务凭据。'
      : state === 'ready' ? '凭据已保存。所有密钥字段留空则保留；修改模型或同源路径无需重新填写，不显示已存密钥。'
      : state === 'blocked' ? '此前未能读取凭据。可在服务列表中点击“测试连接”重试；所有密钥字段留空不会删除已有凭据，也可完整填写新凭据替换。'
      : state === 'unloaded' ? '打开设置不会读取系统凭据。实际使用 OCR 服务时再读取；所有密钥字段留空不会删除已有凭据，也可完整填写新凭据替换。'
      : '请从所选厂商控制台填写对应凭据。也可先保存配置；未配置凭据时不会启用该云服务。';
    for (const id of secretIds.filter((id) => id !== 'ocr-tencent-session-token')) input(id).placeholder = state === 'missing' ? missingPlaceholders[id] ?? input('ocr-provider-key').placeholder : input('ocr-provider-key').placeholder;
  };
  const kindChanged = (resetDefaults = false): void => {
    const kind = select('ocr-provider-kind').value as OcrProvider['kind'];
    const native = isNativeOcr(kind);
    renderServiceGuide($('ocr-service-guide'), OCR_GUIDES[kind], OCR_QUOTAS[kind]);
    const vision = kind === 'openai-vision';
    if (resetDefaults) {
      clearSecrets();
      const nameInput = input('ocr-provider-name');
      if (!nameInput.value.trim() || ['百度 OCR', '腾讯云 OCR', '有道 OCR', 'Google Cloud Vision OCR', '视觉模型 OCR', 'JSON 网关 OCR'].includes(nameInput.value)) nameInput.value = native ? kindLabel(kind) : vision ? '视觉模型 OCR' : 'JSON 网关 OCR';
      input('ocr-provider-model').value = vision ? 'gpt-4o-mini' : '';
      input('ocr-provider-url').value = native ? OCR_NATIVE_URLS[kind] : vision ? 'https://api.openai.com/v1' : '';
    }
    $('ocr-provider-url-field').hidden = native;
    $('ocr-provider-native-action-field').hidden = !native;
    $('ocr-provider-region-field').hidden = kind !== 'tencent';
    $('ocr-provider-baidu-credentials').hidden = kind !== 'baidu';
    $('ocr-provider-tencent-credentials').hidden = kind !== 'tencent';
    $('ocr-provider-youdao-credentials').hidden = kind !== 'youdao';
    $('ocr-provider-model-field').hidden = !vision;
    $('ocr-provider-prompt-field').hidden = !vision;
    $('ocr-provider-key-field').hidden = native && kind !== 'google';
    $('ocr-provider-auth-header-field').hidden = native;
    $('ocr-provider-auth-prefix-field').hidden = native;
    $('ocr-provider-template-field').hidden = kind !== 'http-json';
    $('ocr-provider-response-field').hidden = kind !== 'http-json';
    input('ocr-provider-model').required = vision;
    input('ocr-provider-url').required = !native;
    if (native) {
      input('ocr-provider-url').value = OCR_NATIVE_URLS[kind];
      const actions = select('ocr-provider-native-action'); actions.replaceChildren();
      for (const [value, label] of OCR_NATIVE_ACTIONS[kind]) { const option = el('option', '', label); option.value = value; actions.append(option); }
      const savedAction = input('ocr-provider-model').value;
      if (!resetDefaults && Array.from(actions.options).some((option) => option.value === savedAction)) actions.value = savedAction;
    }
    updateCredentialState(false);
    $('ocr-provider-url-help').textContent = vision ? '填写 OpenAI 兼容视觉 API 基础地址，例如 https://api.openai.com/v1。' : '高级配置：填写你信任的 OCR JSON 网关完整请求地址，例如 https://ocr.example.com/recognize。';
  };
  const open = (provider?: OcrProvider): void => {
    if (saving) return;
    if (!provider && (context.settings().ocrProviders ?? []).length >= 12) { context.toast('最多可添加 12 个 OCR 服务。'); return; }
    editingId = provider?.id ?? null;
    originalCredentialState = credentialStateOf(provider);
    originalScope = provider ? credentialScope(provider.kind, provider.baseUrl) : null; lastInputScope = originalScope;
    $<HTMLFormElement>('ocr-provider-form').reset();
    $('ocr-provider-dialog-title').textContent = provider ? '编辑 OCR 服务' : '添加 OCR 服务';
    input('ocr-provider-name').value = provider?.name ?? '百度 OCR';
    select('ocr-provider-kind').value = provider?.kind ?? 'baidu';
    input('ocr-provider-url').value = provider?.baseUrl ?? OCR_NATIVE_URLS.baidu;
    input('ocr-provider-model').value = provider?.model ?? 'general_basic';
    textArea('ocr-provider-prompt').value = provider?.prompt ?? '';
    input('ocr-provider-auth-header').value = provider?.authHeader ?? 'Authorization';
    input('ocr-provider-auth-prefix').value = provider?.authPrefix ?? 'Bearer ';
    textArea('ocr-provider-template').value = provider?.requestTemplate ?? '{\n  "image": "{imageBase64}"\n}';
    input('ocr-provider-response-path').value = provider?.responsePath ?? '/text';
    const region = select('ocr-provider-region');
    if (provider?.region && !Array.from(region.options).some((option) => option.value === provider.region)) { const option = el('option', '', provider.region); option.value = provider.region; region.append(option); }
    region.value = provider?.region ?? '';
    clearSecrets();
    $('ocr-provider-error').hidden = true;
    kindChanged(); context.showModal(modal);
  };
  const render = (): void => {
    const settings = context.settings();
    const providers = settings.ocrProviders ?? [];
    const activeSelect = select('active-ocr-provider'); activeSelect.replaceChildren();
    const localOption = el('option', '', '本机 OCR · 免费 · 不上传截图'); localOption.value = ''; activeSelect.append(localOption);
    for (const provider of providers) {
      const native = isNativeOcr(provider.kind);
      const state = credentialStateOf(provider);
      const suffix = state === 'unloaded' || state === 'blocked' ? `（${credentialStatusLabel(provider)}）` : native && state === 'missing' ? '（待配置凭据）' : '';
      const option = el('option', '', `${provider.name}${suffix}`); option.value = provider.id; activeSelect.append(option);
    }
    activeSelect.value = settings.activeOcrProviderId ?? '';
    const active = providers.find((provider) => provider.id === settings.activeOcrProviderId);
    $('ocr-quota-card').replaceChildren(renderServiceQuota(OCR_QUOTAS[active?.kind ?? 'local']));
    const notice = $('ocr-privacy-notice');
    notice.classList.toggle('cloud-active', Boolean(active));
    notice.textContent = active ? `云端 OCR 已启用：截图将上传到“${active.name}”的端点 ${active.baseUrl}。` : '本机 OCR 已启用：文字识别在此设备进行，不上传截图。';
    const list = $('ocr-provider-list'); list.replaceChildren();
    if (providers.length === 0) list.append(el('div', 'provider-empty', '默认使用本机 OCR。可添加百度、腾讯云、有道、Google OCR，或视觉模型与高级 JSON 网关。'));
    for (const provider of providers) {
      const row = el('div', 'provider-row'); row.append(el('span', 'provider-avatar ocr-avatar', '文'));
      const info = el('div', 'provider-info'); const title = el('div', 'provider-title', provider.name);
      title.append(el('span', 'provider-key-badge', `· ${credentialStatusLabel(provider)}`));
      info.append(title, el('span', 'provider-details', `${kindLabel(provider.kind)} · ${provider.model || provider.responsePath} · ${provider.baseUrl}`));
      const controls = el('div', 'provider-controls');
      const test = el('button', 'text-button', '测试连接'); test.type = 'button'; test.title = '会上传生成的测试图片，可能消耗 API 额度';
      test.addEventListener('click', () => run(async () => {
        if (!context.desktop) { context.toast('请在桌面应用中测试 OCR API。'); return; }
        test.disabled = true; test.textContent = '测试中…';
        context.toast('正在上传生成的测试图片，可能消耗少量 OCR / 模型额度。');
        try { context.toast(await invoke<string>('test_ocr_provider', { providerId: provider.id }) || 'OCR 服务连接成功。'); }
        finally {
          test.disabled = false; test.textContent = '测试连接';
          await context.reloadSettings().catch(context.reportError);
        }
      }));
      const edit = el('button', 'text-button', '编辑'); edit.type = 'button'; edit.setAttribute('aria-label', `编辑 OCR ${provider.name}`); edit.addEventListener('click', () => open(provider));
      const remove = el('button', 'text-button danger', '删除'); remove.type = 'button'; remove.setAttribute('aria-label', `删除 OCR ${provider.name}`);
      remove.addEventListener('click', () => run(async () => {
        if (!await context.confirm('删除 OCR 服务？', `将移除“${provider.name}”及其密钥；如果正在使用此服务，会切回本机 OCR。`)) return;
        if (context.desktop) await invoke('delete_ocr_api_key', { providerId: provider.id });
        await context.updateSettings((next) => {
          next.ocrProviders = (next.ocrProviders ?? []).filter((item) => item.id !== provider.id);
          if (next.activeOcrProviderId === provider.id) next.activeOcrProviderId = null;
        });
        context.toast('OCR 服务已删除。');
      }));
      controls.append(test, edit, remove); row.append(info, controls); list.append(row);
    }
    $<HTMLButtonElement>('add-ocr-provider').disabled = providers.length >= 12;
  };
  $('add-ocr-provider').addEventListener('click', () => open());
  $('close-ocr-provider-dialog').addEventListener('click', close);
  $('cancel-ocr-provider-dialog').addEventListener('click', close);
  modal.addEventListener('click', (event) => { if (event.target === modal) close(); });
  select('ocr-provider-kind').addEventListener('change', () => kindChanged(true));
  input('ocr-provider-url').addEventListener('input', () => updateCredentialState());
  select('active-ocr-provider').addEventListener('change', (event) => {
    const id = (event.target as HTMLSelectElement).value || null;
    const provider = (context.settings().ocrProviders ?? []).find((item) => item.id === id);
    if (provider && isNativeOcr(provider.kind) && credentialStateOf(provider) === 'missing') { context.toast('此 OCR 服务尚未配置完整凭据，请先编辑并保存密钥。', 'error'); render(); return; }
    run(async () => {
      try {
        await context.updateSettings((next) => { next.activeOcrProviderId = id; });
        context.toast(id ? '云端 OCR 已启用，截图会上传到选定服务。' : '已切换为本机 OCR，不上传截图。');
      } finally { render(); }
    });
  });
  $('remove-ocr-provider-key').addEventListener('click', () => run(async () => {
    if (!context.desktop || !editingId || saving) return;
    const providerId = editingId; setSaving(true);
    try {
      await invoke('delete_ocr_api_key', { providerId }); await context.reloadSettings();
      originalCredentialState = 'missing'; clearSecrets(); kindChanged();
      $('remove-ocr-provider-key').hidden = true;
      input('ocr-provider-key').placeholder = '输入密钥（单独存入系统凭据库）'; context.toast('OCR 密钥已移除。');
    } finally { setSaving(false); }
  }));
  $<HTMLFormElement>('ocr-provider-form').addEventListener('submit', (event) => {
    event.preventDefault();
    run(async () => {
      if (saving) return;
      if (!context.desktop) { context.toast('浏览器预览不保存 OCR API 或密钥，请在桌面应用中配置。'); return; }
      const kind = select('ocr-provider-kind').value as OcrProvider['kind'];
      const native = isNativeOcr(kind);
      const provider: OcrProvider = {
        id: editingId ?? `ocr-${crypto.randomUUID()}`, name: input('ocr-provider-name').value.trim(),
        kind, baseUrl: native ? OCR_NATIVE_URLS[kind] : input('ocr-provider-url').value.trim().replace(/\/+$/, ''),
        model: native ? select('ocr-provider-native-action').value : input('ocr-provider-model').value.trim(), prompt: native ? '' : textArea('ocr-provider-prompt').value.trim(),
        authHeader: native ? 'Authorization' : input('ocr-provider-auth-header').value.trim(), authPrefix: native ? 'Bearer ' : input('ocr-provider-auth-prefix').value,
        requestTemplate: native ? '' : textArea('ocr-provider-template').value.trim(), responsePath: native ? '/text' : input('ocr-provider-response-path').value.trim(), region: kind === 'tencent' ? select('ocr-provider-region').value : '',
      };
      let validation = validateProvider({ ...provider, region: '', kind: provider.kind === 'openai-vision' ? 'openai' : 'libretranslate', enabled: true });
      if (!validation && (!/^[A-Za-z0-9-]+$/.test(provider.authHeader) || /[\r\n]/.test(provider.authPrefix))) validation = '认证 Header 只能包含英文字母、数字和短横线；前缀不能包含换行。';
      if (!validation && provider.kind === 'http-json') {
        try {
          const containsImage = (value: unknown): boolean => {
            if (typeof value === 'string') return value.includes('{imageBase64}') || value.includes('{imageDataUrl}');
            if (Array.isArray(value)) return value.some(containsImage);
            if (value && typeof value === 'object') return Object.values(value).some(containsImage);
            return false;
          };
          if (!containsImage(JSON.parse(provider.requestTemplate))) validation = '请求模板的字符串值中需要包含 {imageBase64} 或 {imageDataUrl}。';
        } catch { validation = '请输入有效的 JSON 请求模板。'; }
        if (!validation && ((provider.responsePath && !provider.responsePath.startsWith('/')) || /~(?![01])/.test(provider.responsePath))) validation = '响应路径应使用 JSON Pointer，例如 /text 或 /data/text。';
      }
      const errorOutput = $('ocr-provider-error');
      if (validation) { errorOutput.textContent = validation; errorOutput.hidden = false; return; }
      const credential = buildOcrCredential(kind, { apiKey: input('ocr-baidu-api-key').value, secretId: input('ocr-tencent-secret-id').value, secretKey: input(kind === 'baidu' ? 'ocr-baidu-secret-key' : 'ocr-tencent-secret-key').value, sessionToken: input('ocr-tencent-session-token').value, appKey: input('ocr-youdao-app-key').value, appSecret: input('ocr-youdao-app-secret').value, genericKey: input('ocr-provider-key').value }, originalScope !== null && credentialScope(provider.kind, provider.baseUrl) !== originalScope);
      if (credential.error) { errorOutput.textContent = credential.error; errorOutput.hidden = false; return; }
      const key = credential.key; setSaving(true);
      try {
        await context.updateSettings((next) => {
          const providers = next.ocrProviders ?? []; const index = providers.findIndex((item) => item.id === provider.id);
          if (index === -1) providers.push(provider); else providers[index] = provider; next.ocrProviders = providers;
        });
        editingId = provider.id;
        if (key) {
          try { await invoke('set_ocr_api_key', { providerId: provider.id, key }); }
          catch (error) { throw new Error(`OCR 服务已保存，但密钥未能写入系统凭据库：${errorMessage(error)}`); }
        }
        clearSecrets(); await context.reloadSettings(); setSaving(false); close(); context.toast('OCR 服务已保存；在识别方式中选择后启用。');
      } catch (error) { errorOutput.textContent = errorMessage(error); errorOutput.hidden = false; }
      finally { setSaving(false); }
    });
  });
  return { render, close };
}
