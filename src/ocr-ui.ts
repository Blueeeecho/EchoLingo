import { invoke } from '@tauri-apps/api/core';
import { errorMessage, validateProvider } from './model';
import type { OcrProvider, Settings } from './types';

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
  const run = (work: () => Promise<unknown>): void => { void work().catch(context.reportError); };
  const setSaving = (value: boolean): void => {
    saving = value; modal.setAttribute('aria-busy', String(value));
    for (const control of modal.querySelectorAll<HTMLInputElement | HTMLButtonElement | HTMLSelectElement | HTMLTextAreaElement>('input, button, select, textarea')) control.disabled = value;
    $('save-ocr-provider').textContent = value ? '处理中…' : '保存 OCR 服务';
  };
  const close = (): void => {
    if (saving) { context.toast('正在保存 OCR 服务，请稍候。'); return; }
    input('ocr-provider-key').value = ''; context.closeModal(modal); editingId = null;
  };
  const kindChanged = (): void => {
    const vision = select('ocr-provider-kind').value === 'openai-vision';
    $('ocr-provider-model-field').hidden = !vision;
    $('ocr-provider-prompt-field').hidden = !vision;
    $('ocr-provider-template-field').hidden = vision;
    $('ocr-provider-response-field').hidden = vision;
    input('ocr-provider-model').required = vision;
    $('ocr-provider-url-help').textContent = vision ? '填写 OpenAI 兼容视觉 API 基础地址，例如 https://api.openai.com/v1。' : '填写你信任的 OCR JSON 网关完整请求地址，例如 https://ocr.example.com/recognize。';
  };
  const open = (provider?: OcrProvider): void => {
    if (saving) return;
    if (!provider && (context.settings().ocrProviders ?? []).length >= 12) { context.toast('最多可添加 12 个 OCR 服务。'); return; }
    editingId = provider?.id ?? null;
    $<HTMLFormElement>('ocr-provider-form').reset();
    $('ocr-provider-dialog-title').textContent = provider ? '编辑 OCR 服务' : '添加 OCR 服务';
    input('ocr-provider-name').value = provider?.name ?? '';
    select('ocr-provider-kind').value = provider?.kind ?? 'openai-vision';
    input('ocr-provider-url').value = provider?.baseUrl ?? 'https://api.openai.com/v1';
    input('ocr-provider-model').value = provider?.model ?? 'gpt-4o-mini';
    textArea('ocr-provider-prompt').value = provider?.prompt ?? '';
    input('ocr-provider-auth-header').value = provider?.authHeader ?? 'Authorization';
    input('ocr-provider-auth-prefix').value = provider?.authPrefix ?? 'Bearer ';
    textArea('ocr-provider-template').value = provider?.requestTemplate ?? '{\n  "image": "{imageBase64}"\n}';
    input('ocr-provider-response-path').value = provider?.responsePath ?? '/text';
    input('ocr-provider-key').value = '';
    input('ocr-provider-key').placeholder = provider?.hasKey ? '密钥已保存；留空保持不变' : '输入密钥（单独存入系统凭据库）';
    $('remove-ocr-provider-key').hidden = !provider?.hasKey;
    $('ocr-provider-error').hidden = true;
    kindChanged(); context.showModal(modal);
  };
  const render = (): void => {
    const settings = context.settings();
    const providers = settings.ocrProviders ?? [];
    const activeSelect = select('active-ocr-provider'); activeSelect.replaceChildren();
    const localOption = el('option', '', '本机 OCR · 不上传截图'); localOption.value = ''; activeSelect.append(localOption);
    for (const provider of providers) { const option = el('option', '', provider.name); option.value = provider.id; activeSelect.append(option); }
    activeSelect.value = settings.activeOcrProviderId ?? '';
    const active = providers.find((provider) => provider.id === settings.activeOcrProviderId);
    const notice = $('ocr-privacy-notice');
    notice.classList.toggle('cloud-active', Boolean(active));
    notice.textContent = active ? `云端 OCR 已启用：截图将上传到“${active.name}”的端点 ${active.baseUrl}。` : '本机 OCR 已启用：文字识别在此设备进行，不上传截图。';
    const list = $('ocr-provider-list'); list.replaceChildren();
    if (providers.length === 0) list.append(el('div', 'provider-empty', '无需配置即可使用系统 OCR。需要自定义识别时，再添加云端视觉模型或 JSON 网关。'));
    for (const provider of providers) {
      const row = el('div', 'provider-row'); row.append(el('span', 'provider-avatar ocr-avatar', '文'));
      const info = el('div', 'provider-info'); const title = el('div', 'provider-title', provider.name);
      if (provider.hasKey) title.append(el('span', 'provider-key-badge', '· 密钥已保存'));
      info.append(title, el('span', 'provider-details', `${provider.kind === 'openai-vision' ? '视觉模型' : 'HTTP JSON'} · ${provider.model || provider.responsePath} · ${provider.baseUrl}`));
      const controls = el('div', 'provider-controls');
      const test = el('button', 'text-button', '测试连接'); test.type = 'button'; test.title = '会上传生成的测试图片，可能消耗 API 额度';
      test.addEventListener('click', () => run(async () => {
        if (!context.desktop) { context.toast('请在桌面应用中测试 OCR API。'); return; }
        test.disabled = true; test.textContent = '测试中…';
        context.toast('正在上传生成的测试图片，可能消耗少量 OCR / 模型额度。');
        try { context.toast(await invoke<string>('test_ocr_provider', { providerId: provider.id }) || 'OCR 服务连接成功。'); }
        finally { test.disabled = false; test.textContent = '测试连接'; }
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
  select('ocr-provider-kind').addEventListener('change', kindChanged);
  select('active-ocr-provider').addEventListener('change', (event) => {
    const id = (event.target as HTMLSelectElement).value || null;
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
      $('remove-ocr-provider-key').hidden = true; input('ocr-provider-key').value = '';
      input('ocr-provider-key').placeholder = '输入密钥（单独存入系统凭据库）'; context.toast('OCR 密钥已移除。');
    } finally { setSaving(false); }
  }));
  $<HTMLFormElement>('ocr-provider-form').addEventListener('submit', (event) => {
    event.preventDefault();
    run(async () => {
      if (saving) return;
      if (!context.desktop) { context.toast('浏览器预览不保存 OCR API 或密钥，请在桌面应用中配置。'); return; }
      const provider: OcrProvider = {
        id: editingId ?? `ocr-${crypto.randomUUID()}`, name: input('ocr-provider-name').value.trim(),
        kind: select('ocr-provider-kind').value as OcrProvider['kind'], baseUrl: input('ocr-provider-url').value.trim().replace(/\/+$/, ''),
        model: input('ocr-provider-model').value.trim(), prompt: textArea('ocr-provider-prompt').value.trim(),
        authHeader: input('ocr-provider-auth-header').value.trim(), authPrefix: input('ocr-provider-auth-prefix').value,
        requestTemplate: textArea('ocr-provider-template').value.trim(), responsePath: input('ocr-provider-response-path').value.trim(),
      };
      let validation = validateProvider({ ...provider, kind: provider.kind === 'openai-vision' ? 'openai' : 'libretranslate', enabled: true });
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
      const key = input('ocr-provider-key').value.trim(); setSaving(true);
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
        input('ocr-provider-key').value = ''; await context.reloadSettings(); setSaving(false); close(); context.toast('OCR 服务已保存；在识别方式中选择后启用。');
      } catch (error) { errorOutput.textContent = errorMessage(error); errorOutput.hidden = false; }
      finally { setSaving(false); }
    });
  });
  return { render, close };
}
