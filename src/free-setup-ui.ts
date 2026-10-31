import { invoke } from '@tauri-apps/api/core';
import { serviceById, servicesFor, type FreePiece, type FreeRegion } from './free-services';
import { EXTRA_SERVICE_LINKS } from './service-quotas';
import type { OcrProvider, Provider, Settings } from './types';
import { tx } from './ui-text';
import { buildTranslationCredential } from './translation-credentials';
import { buildOcrCredential } from './ocr-credentials';

const STORAGE_KEY = 'echolingo.free-setup';
const DAY_MS = 24 * 60 * 60 * 1000;
interface HintState { dismissed: boolean; shownAt: number; softAt: number }
interface SetupContext {
  desktop: boolean;
  settings: () => Settings;
  updateSettings: (mutator: (next: Settings) => void, canCommit?: () => boolean) => Promise<void>;
  toast: (message: string, tone?: 'info' | 'error', duration?: number) => void;
  setView: (view: string) => void;
  reportError: (error: unknown) => void;
  showModal: (modal: HTMLElement) => void;
  closeModal: (modal: HTMLElement) => void;
  resumeDraft?: () => boolean;
}

function readState(): HintState {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '') as Partial<HintState>;
    return {
      dismissed: parsed.dismissed === true,
      shownAt: typeof parsed.shownAt === 'number' ? parsed.shownAt : 0,
      softAt: typeof parsed.softAt === 'number' ? parsed.softAt : 0,
    };
  } catch { return { dismissed: false, shownAt: 0, softAt: 0 }; }
}
function writeState(state: HintState): void {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch { /* private mode */ }
}

function field(label: string, id: string, secret = true): HTMLLabelElement {
  const wrap = document.createElement('label');
  wrap.append(document.createTextNode(label));
  const input = document.createElement('input');
  input.id = id; input.autocomplete = 'off'; input.spellcheck = false;
  input.type = secret ? 'password' : 'text';
  wrap.append(input);
  return wrap;
}

function values(ids: string[]): Record<string, string> {
  return Object.fromEntries(ids.map((id) => [id, (document.getElementById(id) as HTMLInputElement | null)?.value.trim() ?? '']));
}

function credentialFor(piece: FreePiece, input: Record<string, string>): { key: string | null; error: string | null } {
  if (piece.credential === 'localOllama') return { key: null, error: null };
  if (piece.credential === 'youdaoPair') return piece.role === 'translation'
    ? buildTranslationCredential('youdao', { appKey: input.first, appSecret: input.second })
    : buildOcrCredential('youdao', { appKey: input.first, appSecret: input.second }, true);
  if (piece.role === 'translation') {
    if (piece.credential === 'appPair' || piece.credential === 'microsoft') {
      return piece.credential === 'microsoft'
        ? buildTranslationCredential('microsoft', { subscriptionKey: input.key })
        : buildTranslationCredential(piece.kind as Provider['kind'], { appId: input.first, secretKey: input.second });
    }
    return buildTranslationCredential(piece.kind as 'openai', { genericKey: input.key });
  }
  if (piece.credential === 'ocrPair') return buildOcrCredential('baidu', { apiKey: input.first, secretKey: input.second }, true);
  if (piece.credential === 'tencentOcr') return buildOcrCredential('tencent', { secretId: input.first, secretKey: input.second }, true);
  if (piece.credential === 'azureVision') return buildOcrCredential('azure-vision', { genericKey: input.key }, true);
  return buildOcrCredential(piece.kind as 'google', { genericKey: input.key }, true);
}

export function installFreeSetup(context: SetupContext): { refresh: () => void; noteWeak: (text?: string) => void; open: (region?: FreeRegion) => void; close: () => void } {
  const hint = document.querySelector<HTMLElement>('#free-setup-hint');
  const dialog = document.querySelector<HTMLElement>('#free-setup-dialog');
  const body = document.querySelector<HTMLElement>('#free-setup-body');
  const error = document.querySelector<HTMLElement>('#free-setup-error');
  let state = readState();
  let mode: 'first' | 'soft' | null = null;
  let region: FreeRegion = (navigator.language || '').toLowerCase().startsWith('zh') ? 'cn' : 'overseas';
  let selectedPiece: FreePiece | null = null;
  let revision = 0;
  let busy = false;
  const nextButton = document.querySelector<HTMLButtonElement>('#free-setup-next');
  const setBusy = (value: boolean): void => {
    busy = value;
    if (nextButton) nextButton.disabled = value;
    dialog?.setAttribute('aria-busy', String(value));
  };
  const invalidate = (): void => { revision += 1; setBusy(false); };
  const inTest = typeof window !== 'undefined' && '__qa' in window;

  // Keep the existing engine/privacy explanation and shortcut errors ahead of
  // optional signup guidance; never stack multiple onboarding banners.
  const hintBlocked = (): boolean => ['#core-guidance', '#engine-hint'].some((selector) => document.querySelector<HTMLElement>(selector)?.hidden === false);
  const showError = (message: string): void => { if (!error) return; error.hidden = !message; error.textContent = message; };
  const openLink = (url: string): void => {
    if (context.desktop) void invoke('open_service_link', { url }).catch(context.reportError);
    else window.open(url, '_blank', 'noopener');
  };
  const renderCards = (): void => {
    document.querySelector<HTMLButtonElement>('#free-region-cn')?.setAttribute('aria-pressed', String(region === 'cn'));
    document.querySelector<HTMLButtonElement>('#free-region-overseas')?.setAttribute('aria-pressed', String(region === 'overseas'));
    for (const role of ['translation', 'ocr'] as const) {
      const list = document.querySelector<HTMLElement>(`#free-${role}-list`);
      if (!list) continue;
      const services = servicesFor(region, role);
      const count = document.querySelector(`#free-${role}-count`);
      if (count) count.textContent = tx(`（${services.length} 项）`, `(${services.length})`);
      // Keep the native details element intact: refreshes and region changes
      // must retain each role's user-selected expansion state.
      list.replaceChildren();
      for (const item of services) {
        const row = document.createElement('li'); row.className = 'free-service';
        row.setAttribute('data-free-service', item.id);
        const title = document.createElement('h4'); title.textContent = tx(item.name, item.nameEn);
        const quota = document.createElement('p'); quota.className = 'free-service-quota';
        quota.textContent = tx(item.allowance.summary, item.quotaEn);
        const detail = document.createElement('p'); detail.className = 'free-service-conditions';
        detail.textContent = tx(item.allowance.details.join(' '), item.conditionsEn);
        const cost = document.createElement('p'); cost.className = 'free-service-warning';
        cost.textContent = tx('费用提醒：免费条件或额度之外可能收费，请核对平台计费规则。', 'Billing notice: use outside the free eligibility or allowance may be charged. Check the vendor rules.');
        const date = document.createElement('small');
        date.textContent = tx(`核对日期：${item.allowance.checkedOn} · 额度可能变化`, `Checked: ${item.allowance.checkedOn} · Quotas may change`);
        const actions = document.createElement('div'); actions.className = 'free-service-actions';
        const button = document.createElement('button'); button.type = 'button'; button.className = 'text-button';
        button.textContent = tx('配置此服务', 'Set up this service');
        button.setAttribute('aria-label', tx(`配置${item.name}`, `Set up ${item.nameEn}`));
        button.addEventListener('click', () => openWizard(item.id));
        actions.append(button);
        for (const [label, url] of item.allowance.links.slice(0, 1)) {
          const source = document.createElement('button'); source.type = 'button'; source.className = 'text-button';
          source.textContent = tx(label, 'Official quota'); source.setAttribute('data-free-source', item.id);
          source.addEventListener('click', () => openLink(url)); actions.append(source);
        }
        row.append(title, quota, detail, date, actions, cost); list.append(row);
      }
    }
  };
  const refresh = (): void => {
    renderCards();
    if (!hint || inTest) return;
    const blocked = hintBlocked();
    if (mode === null && !state.dismissed && state.shownAt <= 0 && !blocked) {
      mode = 'first'; state = { ...state, shownAt: Date.now() }; writeState(state);
    }
    const visible = mode !== null && !blocked && !state.dismissed;
    hint.hidden = !visible;
    if (!visible) return;
    const title = document.querySelector('#free-setup-hint-title');
    const detail = document.querySelector('#free-setup-hint-detail');
    if (title) title.textContent = mode === 'first'
      ? tx('3 分钟可以免费把翻译质量提高一截', 'Three minutes can get you a much better translation for free')
      : tx('这次结果可能受本机引擎限制', 'This result may be limited by the local engine');
    if (detail) detail.textContent = tx(
      '默认仍是本机翻译和本机识别，不会上传。若你自己启用云端服务，原文或选区图片才会发给该服务商。额度核对于 2026-10，会变，不是永久免费。',
      'The default stays on this computer and nothing is uploaded. Text or the selected image is sent only after you enable a cloud service. Quotas were checked in 2026-10, can change, and are not permanently free.',
    );
  };
  const noteWeak = (text?: string): void => {
    if (inTest || state.dismissed || mode === 'first') return;
    if (text !== undefined && !/没有识别|翻译失败|NO_TEXT:|OCR_|识别失败|服务返回错误/.test(text)) return;
    if (hintBlocked()) return;
    const now = Date.now();
    if (state.softAt > 0 && now - state.softAt < DAY_MS) return;
    mode = 'soft'; state = { ...state, softAt: now }; writeState(state); refresh();
  };
  const renderPiece = (): void => {
    if (!body) return;
    const piece = selectedPiece;
    if (!piece) return;
    showError('');
    const step = document.querySelector('#free-setup-step');
    if (step) step.textContent = tx(`${piece.role === 'translation' ? '翻译服务' : 'OCR 服务'} · ${piece.name}`, `${piece.role === 'translation' ? 'Translation' : 'OCR'} · ${piece.nameEn}`);
    const fields = document.createElement('div'); fields.className = 'free-setup-fields';
    const quota = document.createElement('p'); quota.className = 'field-help'; quota.textContent = tx(piece.allowance.summary, piece.quotaEn) + tx(` 核对日期：${piece.allowance.checkedOn}。`, ` Checked: ${piece.allowance.checkedOn}.`);
    const privacy = document.createElement('p'); privacy.className = 'field-help';
    privacy.textContent = piece.credential === 'localOllama' ? tx('测试会向本机 Ollama 发送内置短句，无需密钥。请选择已下载的本机模型，不要使用 cloud 模型；其他已启用翻译服务仍保留。', 'The test sends a built-in sentence to local Ollama without a key. Use a downloaded local model, not a cloud model. Other enabled translation services remain enabled.') : piece.role === 'ocr'
      ? tx('测试会发送内置示例图；启用后的识别会把你的选区图片发给这个服务商。密钥只写入系统凭据库。', 'The test sends a built-in sample image. Later recognition sends your selected image to this provider. The key is stored only in the system credential store.')
      : tx('测试会发送内置短句；启用后的翻译会把原文发给这个服务商。密钥只写入系统凭据库。启用会保留现有翻译服务；如不需要并行翻译，请在设置中关闭其他服务。', 'The test sends a built-in short sentence; later translation sends your source text to this provider. The key stays in the system credential store. Existing translation services remain enabled; disable others in Settings if you do not want parallel translation.');
    const warning = document.createElement('p'); warning.className = 'free-service-warning';
    warning.textContent = piece.credential === 'localOllama' ? tx('本机模型需要硬件、存储和电力；云模型不属于本机免费处理。', 'Local models use hardware, storage and electricity; cloud models are not local free inference.') : tx('费用提醒：免费额度用完后可能继续计费，请先确认控制台的计费与停止使用方式；应用不会保证自动停用。', 'Billing notice: usage above the free allowance may be billed. Check the vendor billing and stop-usage controls; this app does not guarantee an automatic stop.');
    const open = document.createElement('button'); open.type = 'button'; open.className = 'text-button'; open.textContent = tx('打开申请页', 'Open signup page');
    open.addEventListener('click', () => {
      if (context.desktop) void invoke('open_service_link', { url: piece.signupUrl }).catch(context.reportError);
      else window.open(piece.signupUrl, '_blank', 'noopener');
    });
    if (piece.credential === 'localOllama') {
      const modelField = field(tx('已下载的本机模型名', 'Downloaded local model name'), 'free-field-model', false);
      fields.append(modelField);
    } else if (piece.credential === 'appPair' || piece.credential === 'ocrPair' || piece.credential === 'tencentOcr' || piece.credential === 'youdaoPair') {
      const firstLabel = piece.credential === 'youdaoPair' ? 'AppKey' : piece.kind === 'volcengine' || piece.kind === 'aliyun' ? 'AccessKey ID' : piece.credential === 'tencentOcr' ? 'SecretId' : piece.role === 'translation' ? 'APP ID' : 'API Key';
      const secondLabel = piece.credential === 'youdaoPair' ? 'AppSecret' : piece.kind === 'volcengine' ? 'Secret Access Key' : piece.kind === 'aliyun' ? 'AccessKey Secret' : piece.credential === 'tencentOcr' ? 'SecretKey' : piece.role === 'ocr' ? 'Secret Key' : tx('密钥', 'Secret');
      fields.append(field(firstLabel, 'free-field-first'), field(secondLabel, 'free-field-second'));
    } else if (piece.credential === 'azureVision') {
      fields.append(field(tx('终结点，例如 https://名字.cognitiveservices.azure.com', 'Endpoint, for example https://name.cognitiveservices.azure.com'), 'free-field-endpoint', false), field('API Key', 'free-field-key'));
    } else if (piece.credential === 'microsoft') {
      fields.append(field(tx('资源密钥', 'Resource key'), 'free-field-key'), field(tx('地域，全球单服务可留空', 'Region, optional for a global resource'), 'free-field-region', false));
    } else fields.append(field('API Key', 'free-field-key'));
    if (piece.editableModel) {
      fields.append(field(tx('已确认有试用额度的模型 ID', 'Model ID with confirmed trial quota'), 'free-field-model', false));
    }
    body.replaceChildren(quota, warning, privacy, open, fields);
    const next = document.querySelector<HTMLButtonElement>('#free-setup-next');
    if (next) next.textContent = piece.role === 'translation'
      ? tx('测试并启用此翻译服务', 'Test and enable translation')
      : tx('测试并设为当前 OCR', 'Test and set as current OCR');
  };
  const openWizard = (id: string): void => {
    if (context.resumeDraft?.()) return;
    invalidate();
    selectedPiece = serviceById(id) ?? null;
    if (!selectedPiece) return;
    renderPiece();
    if (dialog && dialog.hidden) context.showModal(dialog);
    document.querySelector<HTMLElement>('#free-setup-dialog')?.focus();
  };
  const closeWizard = (): void => {
    invalidate();
    // Remove password inputs as well as hiding the dialog.
    body?.replaceChildren();
    selectedPiece = null;
    showError('');
    if (dialog && !dialog.hidden) context.closeModal(dialog);
  };
  const applyPiece = async (piece: FreePiece, current: () => boolean): Promise<boolean> => {
    const entered: Record<string, string> = {
      ...values(['free-field-model', 'free-field-key', 'free-field-first', 'free-field-second', 'free-field-region']),
      endpoint: (document.getElementById('free-field-endpoint') as HTMLInputElement | null)?.value.trim() ?? '',
    };
    const input = {
      key: entered['free-field-key'] ?? '',
      first: entered['free-field-first'] ?? '',
      second: entered['free-field-second'] ?? '',
      region: entered['free-field-region'] ?? '',
      endpoint: entered.endpoint,
    };
    if (piece.kind === 'ocrspace' && (input.key ?? '').toLowerCase() === 'helloworld') {
      showError(tx('不能使用 OCR.space 的公共示例密钥。', 'The public OCR.space sample key cannot be used.'));
      return false;
    }
    const secret = credentialFor(piece, { key: input.key ?? '', first: input.first ?? '', second: input.second ?? '' });
    const localModel = entered['free-field-model'] ?? '';
    if (piece.credential === 'localOllama' && (!localModel || /cloud/i.test(localModel))) {
      showError(tx('请填写已下载的本机模型名，不要使用 cloud 模型。', 'Enter a downloaded local model name, not a cloud model.')); return false;
    }
    if (secret.error || (!secret.key && piece.credential !== 'localOllama')) { showError(secret.error || tx('请填写完整密钥。', 'Enter the complete key.')); return false; }
    const chosenModel = piece.editableModel ? entered['free-field-model'] ?? '' : piece.model;
    if (piece.editableModel && (!chosenModel || chosenModel.length > 200)) {
      showError(tx('请先确认试用额度，再填写对应模型 ID（最长 200 字符）。', 'Confirm the trial quota and enter its model ID (up to 200 characters).')); return false;
    }
    if (!context.desktop) { showError(tx('测试连接需要桌面应用。', 'Testing a connection requires the desktop app.')); return false; }
    const id = `free-${crypto.randomUUID()}`;
    const baseUrl = piece.credential === 'azureVision' ? (input.endpoint ?? '').replace(/\/+$/, '') : piece.baseUrl;
    if (piece.credential === 'azureVision' && !/^https:\/\/[a-z0-9-]+\.cognitiveservices\.azure\.com$/i.test(baseUrl)) {
      showError(tx('Azure 终结点必须是 https://你的资源名.cognitiveservices.azure.com', 'The Azure endpoint must look like https://your-resource.cognitiveservices.azure.com'));
      return false;
    }
    let staged = false;
    let keyAttempted = false;
    let committed = false;
    let previousOcrId: string | null = null;
    const translation = piece.role === 'translation';
    try {
      if (translation) {
        const provider: Provider = { id, name: piece.name, kind: piece.kind as Provider['kind'], baseUrl, model: piece.credential === 'localOllama' ? localModel : chosenModel, enabled: false, prompt: '', region: input.region || piece.region || '' };
        await context.updateSettings((next) => { staged = true; next.providers.push(provider); }, current);
      } else {
        const provider: OcrProvider = {
          id, name: piece.name, kind: piece.kind as OcrProvider['kind'], baseUrl, model: piece.model, prompt: piece.prompt ?? '',
          authHeader: 'Authorization', authPrefix: 'Bearer ', requestTemplate: '', responsePath: '', region: piece.region ?? '',
        };
        await context.updateSettings((next) => { staged = true; next.ocrProviders.push(provider); }, current);
      }
      if (!current()) return false;
      if (secret.key) {
        keyAttempted = true;
        await invoke(translation ? 'set_api_key' : 'set_ocr_api_key', { providerId: id, key: secret.key });
      }
      if (!current()) return false;
      const message = await invoke<string>(translation ? 'test_provider' : 'test_ocr_provider', { providerId: id });
      if (!current()) return false;
      await context.updateSettings((next) => {
        if (translation) {
          const found = next.providers.find((item) => item.id === id);
          if (found) found.enabled = true;
        } else {
          previousOcrId = next.activeOcrProviderId;
          next.activeOcrProviderId = id;
        }
      }, current);
      if (!current()) return false;
      committed = true;
      context.toast(message || (translation
        ? tx('已启用这个翻译服务。本机服务仍然保留。', 'This translation service is enabled. The local service is still there.')
        : tx('已把这个 OCR 设为当前识别方式。', 'This OCR service is now the current recognizer.')));
      return true;
    } finally {
      if (staged && !committed) {
        // This operation owns only its fresh UUID. Never remove an existing service.
        // Keep a disabled row if credential deletion fails so it remains removable
        // from Settings rather than orphaning a secret in the credential store.
        let removeProvider = true;
        if (keyAttempted) {
          try { await invoke(translation ? 'delete_api_key' : 'delete_ocr_api_key', { providerId: id }); }
          catch (cleanupError) { removeProvider = false; context.reportError(cleanupError); }
        }
        try {
          await context.updateSettings((next) => {
            if (translation) {
              const found = next.providers.find((item) => item.id === id);
              if (found) found.enabled = false;
              if (removeProvider) next.providers = next.providers.filter((item) => item.id !== id);
            } else {
              if (next.activeOcrProviderId === id) next.activeOcrProviderId = next.ocrProviders.some((item) => item.id === previousOcrId) ? previousOcrId : null;
              if (removeProvider) next.ocrProviders = next.ocrProviders.filter((item) => item.id !== id);
            }
          });
        } catch (cleanupError) { context.reportError(cleanupError); }
      }
    }
  };

  const chooseService = (): void => {
    closeWizard(); context.setView('settings'); renderCards();
    const group = document.querySelector<HTMLDetailsElement>('#free-translation-section');
    if (group) group.open = true;
    const section = document.querySelector<HTMLElement>('#free-translation-summary');
    section?.scrollIntoView?.({ block: 'start' }); section?.focus();
  };
  document.querySelector('#free-region-cn')?.addEventListener('click', () => { region = 'cn'; renderCards(); });
  document.querySelector('#free-region-overseas')?.addEventListener('click', () => { region = 'overseas'; renderCards(); });
  document.querySelector('#free-setup-settings')?.addEventListener('click', chooseService);
  document.querySelector('#free-setup-open')?.addEventListener('click', chooseService);
  document.querySelector('#free-setup-docs')?.addEventListener('click', () => {
    const url = tx(EXTRA_SERVICE_LINKS.freeSetupZh, EXTRA_SERVICE_LINKS.freeSetupEn);
    if (context.desktop) void invoke('open_service_link', { url }).catch(context.reportError);
    else window.open(url, '_blank', 'noopener');
  });
  document.querySelector('#free-setup-dismiss')?.addEventListener('click', () => {
    mode = null; state = { ...state, dismissed: true, shownAt: Date.now() }; writeState(state); refresh();
  });
  document.querySelector('#free-setup-close')?.addEventListener('click', closeWizard);
  dialog?.addEventListener('click', (event) => { if (event.target === dialog) closeWizard(); });
  document.querySelector('#free-setup-back')?.addEventListener('click', closeWizard);
  nextButton?.addEventListener('click', () => {
    if (busy || !selectedPiece || dialog?.hidden) return;
    const piece = selectedPiece, intent = revision;
    const current = (): boolean => revision === intent && selectedPiece === piece && dialog?.hidden === false;
    setBusy(true);
    void applyPiece(piece, current).then((success) => {
      if (success && current()) closeWizard();
    }).catch((failure: unknown) => {
      if (current()) showError(typeof failure === 'string' ? failure : failure instanceof Error ? failure.message : tx('测试没有成功，请检查密钥、网络和是否已开通该服务。', 'The test did not succeed. Check the key, network, and that the service is enabled.'));
    }).finally(() => { if (revision === intent) setBusy(false); });
  });
  dialog?.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !event.isComposing && event.keyCode !== 229) {
      event.preventDefault(); event.stopPropagation(); closeWizard();
    }
  });
  for (const [id, zh, en] of [['free-translation-heading', '翻译服务', 'Translation services'], ['free-ocr-heading', 'OCR 服务', 'OCR services'], ['free-setup-settings', '选择服务', 'Choose a service']] as const) {
    const element = document.querySelector(`#${id}`); if (element) element.textContent = tx(zh, en);
  }
  const cardTitle = document.querySelector('#free-setup-card-title');
  const cardSummary = document.querySelector('#free-setup-card-summary');
  if (cardTitle) cardTitle.textContent = tx('有免费额度的服务', 'Services with free allowances');
  if (cardSummary) cardSummary.textContent = tx(
    '默认仍是本机翻译和本机识别。翻译和 OCR 分开选择，可自由搭配，也可只配置其中一项。免费额度与条件以官方当时说明为准。',
    'The default stays local. Choose translation and OCR independently, or configure only one. Free allowances and eligibility follow the current vendor terms.',
  );
  // The host refreshes hints after rendering its existing engine/privacy state.
  // Do not consume the first-run timestamp before that banner can block this one.
  renderCards();
  return { refresh, noteWeak, close: closeWizard, open: (next) => { if (next) region = next; chooseService(); } };
}
