import { invoke } from '@tauri-apps/api/core';
import { comboById, combosFor, type FreeCombo, type FreePiece, type FreeRegion } from './free-combos';
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
  updateSettings: (mutator: (next: Settings) => void) => Promise<void>;
  toast: (message: string, tone?: 'info' | 'error', duration?: number) => void;
  setView: (view: string) => void;
  reportError: (error: unknown) => void;
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
  if (piece.role === 'translation') {
    if (piece.credential === 'appPair' || piece.credential === 'microsoft') {
      return piece.credential === 'microsoft'
        ? buildTranslationCredential('microsoft', { subscriptionKey: input.key })
        : buildTranslationCredential(piece.kind as 'baidu', { appId: input.first, secretKey: input.second });
    }
    return buildTranslationCredential(piece.kind as 'openai', { genericKey: input.key });
  }
  if (piece.credential === 'ocrPair') return buildOcrCredential('baidu', { apiKey: input.first, secretKey: input.second }, true);
  if (piece.credential === 'tencentOcr') return buildOcrCredential('tencent', { secretId: input.first, secretKey: input.second }, true);
  if (piece.credential === 'azureVision') return buildOcrCredential('azure-vision', { genericKey: input.key }, true);
  return buildOcrCredential(piece.kind as 'google', { genericKey: input.key }, true);
}

export function installFreeSetup(context: SetupContext): { refresh: () => void; noteWeak: (text?: string) => void; open: (region?: FreeRegion) => void } {
  const hint = document.querySelector<HTMLElement>('#free-setup-hint');
  const dialog = document.querySelector<HTMLElement>('#free-setup-dialog');
  const body = document.querySelector<HTMLElement>('#free-setup-body');
  const error = document.querySelector<HTMLElement>('#free-setup-error');
  let state = readState();
  let mode: 'first' | 'soft' | null = null;
  let region: FreeRegion = (navigator.language || '').toLowerCase().startsWith('zh') ? 'cn' : 'overseas';
  let combo: FreeCombo | null = null;
  let pieceIndex = 0;
  const inTest = typeof window !== 'undefined' && '__qa' in window;

  const showError = (message: string): void => { if (!error) return; error.hidden = !message; error.textContent = message; };
  const renderCards = (): void => {
    const list = document.querySelector<HTMLElement>('#free-combo-list');
    if (!list) return;
    document.querySelector<HTMLButtonElement>('#free-region-cn')?.setAttribute('aria-pressed', String(region === 'cn'));
    document.querySelector<HTMLButtonElement>('#free-region-overseas')?.setAttribute('aria-pressed', String(region === 'overseas'));
    list.replaceChildren();
    for (const item of combosFor(region)) {
      const card = document.createElement('article'); card.className = 'free-combo';
      const title = document.createElement('h3'); title.textContent = tx(item.titleZh, item.titleEn);
      const detail = document.createElement('p'); detail.textContent = tx(item.detailZh, item.detailEn);
      const button = document.createElement('button'); button.type = 'button'; button.className = 'text-button';
      button.textContent = tx('一键配置', 'Set up');
      button.addEventListener('click', () => openWizard(item.id));
      card.append(title, detail, button); list.append(card);
    }
  };
  const refresh = (): void => {
    renderCards();
    if (!hint || inTest) return;
    const blocked = document.querySelector<HTMLElement>('#core-guidance')?.hidden === false;
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
    if (document.querySelector<HTMLElement>('#core-guidance')?.hidden === false) return;
    const now = Date.now();
    if (state.softAt > 0 && now - state.softAt < DAY_MS) return;
    mode = 'soft'; state = { ...state, softAt: now }; writeState(state); refresh();
  };
  const renderPiece = (): void => {
    if (!body || !combo) return;
    const piece = combo.pieces[pieceIndex];
    if (!piece) return;
    showError('');
    const step = document.querySelector('#free-setup-step');
    if (step) step.textContent = tx(`第 ${pieceIndex + 1} / ${combo.pieces.length} 步 · ${piece.name}`, `Step ${pieceIndex + 1} of ${combo.pieces.length} · ${piece.name}`);
    const fields = document.createElement('div'); fields.className = 'free-setup-fields';
    const quota = document.createElement('p'); quota.className = 'field-help'; quota.textContent = tx(piece.quotaZh, piece.quotaEn);
    const privacy = document.createElement('p'); privacy.className = 'field-help';
    privacy.textContent = piece.role === 'ocr'
      ? tx('测试和之后的识别会把选区图片发给这个服务商。密钥只写入系统凭据库。', 'The test and later recognition send the selected image to this provider. The key is stored only in the system credential store.')
      : tx('测试和之后的翻译会把原文发给这个服务商。密钥只写入系统凭据库。', 'The test and later translation send the source text to this provider. The key is stored only in the system credential store.');
    const warning = document.createElement('p'); warning.className = 'field-help';
    warning.textContent = tx(piece.warningZh ?? '如果免费额度用完后会自动转为按量计费，请到该服务商控制台关闭后付费或打开“用完即停”。', piece.warningEn ?? 'If this provider starts charging after the free tier, turn off post-paid billing or enable stop-when-exhausted in its console.');
    const open = document.createElement('button'); open.type = 'button'; open.className = 'text-button'; open.textContent = tx('打开申请页', 'Open signup page');
    open.addEventListener('click', () => {
      if (context.desktop) void invoke('open_service_link', { url: piece.signupUrl }).catch(context.reportError);
      else window.open(piece.signupUrl, '_blank', 'noopener');
    });
    if (piece.credential === 'appPair' || piece.credential === 'ocrPair' || piece.credential === 'tencentOcr') {
      fields.append(field(piece.credential === 'tencentOcr' ? 'SecretId' : tx('第一项 ID / Key', 'First ID / key'), 'free-field-first'), field(tx('密钥', 'Secret'), 'free-field-second'));
    } else if (piece.credential === 'azureVision') {
      fields.append(field(tx('终结点，例如 https://名字.cognitiveservices.azure.com', 'Endpoint, for example https://name.cognitiveservices.azure.com'), 'free-field-endpoint', false), field('API Key', 'free-field-key'));
    } else if (piece.credential === 'microsoft') {
      fields.append(field(tx('资源密钥', 'Resource key'), 'free-field-key'), field(tx('地域，全球单服务可留空', 'Region, optional for a global resource'), 'free-field-region', false));
    } else fields.append(field('API Key', 'free-field-key'));
    body.replaceChildren(quota, warning, privacy, open, fields);
    const next = document.querySelector<HTMLButtonElement>('#free-setup-next');
    if (next) next.textContent = tx('测试并设为当前', 'Test and set as current');
  };
  const openWizard = (id?: string): void => {
    combo = id ? comboById(id) ?? null : combosFor(region)[0] ?? null;
    pieceIndex = 0;
    if (dialog) dialog.hidden = false;
    renderPiece();
    document.querySelector<HTMLElement>('#free-setup-dialog')?.focus();
  };
  const closeWizard = (): void => { if (dialog) dialog.hidden = true; showError(''); };
  const applyPiece = async (): Promise<void> => {
    if (!combo) return;
    const piece = combo.pieces[pieceIndex];
    if (!piece) return;
    const entered: Record<string, string> = {
      ...values(['free-field-key', 'free-field-first', 'free-field-second', 'free-field-region']),
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
      return;
    }
    const secret = credentialFor(piece, { key: input.key ?? '', first: input.first ?? '', second: input.second ?? '' });
    if (secret.error || !secret.key) { showError(secret.error || tx('请填写完整密钥。', 'Enter the complete key.')); return; }
    if (!context.desktop) { showError(tx('测试连接需要桌面应用。', 'Testing a connection requires the desktop app.')); return; }
    const id = `free-${crypto.randomUUID()}`;
    const baseUrl = piece.credential === 'azureVision' ? (input.endpoint ?? '').replace(/\/+$/, '') : piece.baseUrl;
    if (piece.credential === 'azureVision' && !/^https:\/\/[a-z0-9-]+\.cognitiveservices\.azure\.com$/i.test(baseUrl)) {
      showError(tx('Azure 终结点必须是 https://你的资源名.cognitiveservices.azure.com', 'The Azure endpoint must look like https://your-resource.cognitiveservices.azure.com'));
      return;
    }
    if (piece.role === 'translation') {
      const provider: Provider = { id, name: piece.name, kind: piece.kind as Provider['kind'], baseUrl, model: piece.model, enabled: false, prompt: '', region: input.region ?? '' };
      await context.updateSettings((next) => { next.providers.push(provider); });
      await invoke('set_api_key', { providerId: id, key: secret.key });
      const message = await invoke<string>('test_provider', { providerId: id });
      await context.updateSettings((next) => { const found = next.providers.find((item) => item.id === id); if (found) found.enabled = true; });
      context.toast(message || tx('已启用这个翻译服务。本机服务仍然保留。', 'This translation service is enabled. The local service is still there.'));
    } else {
      const provider: OcrProvider = {
        id, name: piece.name, kind: piece.kind as OcrProvider['kind'], baseUrl, model: piece.model, prompt: piece.prompt ?? '',
        authHeader: 'Authorization', authPrefix: 'Bearer ', requestTemplate: '', responsePath: '', region: piece.region ?? '',
      };
      await context.updateSettings((next) => { next.ocrProviders.push(provider); });
      await invoke('set_ocr_api_key', { providerId: id, key: secret.key });
      const message = await invoke<string>('test_ocr_provider', { providerId: id });
      await context.updateSettings((next) => { next.activeOcrProviderId = id; });
      context.toast(message || tx('已把这个 OCR 设为当前识别方式。', 'This OCR service is now the current recognizer.'));
    }
  };

  document.querySelector('#free-region-cn')?.addEventListener('click', () => { region = 'cn'; renderCards(); });
  document.querySelector('#free-region-overseas')?.addEventListener('click', () => { region = 'overseas'; renderCards(); });
  document.querySelector('#free-setup-settings')?.addEventListener('click', () => openWizard());
  document.querySelector('#free-setup-open')?.addEventListener('click', () => { context.setView('settings'); openWizard(); });
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
  document.querySelector('#free-setup-back')?.addEventListener('click', () => {
    if (pieceIndex === 0) closeWizard(); else { pieceIndex -= 1; renderPiece(); }
  });
  document.querySelector('#free-setup-next')?.addEventListener('click', () => {
    void applyPiece().then(() => {
      if (!combo) return;
      pieceIndex += 1;
      if (pieceIndex >= combo.pieces.length) {
        closeWizard();
        context.toast(tx('这一组已经启用。本机引擎仍是默认兜底，可在设置里关掉不需要的服务。', 'This combination is enabled. The local engine remains available; turn off anything you do not want in Settings.'));
      } else renderPiece();
    }).catch((error: unknown) => showError(typeof error === 'string' ? error : error instanceof Error ? error.message : tx('测试没有成功，请检查密钥、网络和是否已开通该服务。', 'The test did not succeed. Check the key, network, and that the service is enabled.')));
  });
  const cardTitle = document.querySelector('#free-setup-card-title');
  const cardSummary = document.querySelector('#free-setup-card-summary');
  if (cardTitle) cardTitle.textContent = tx('推荐免费组合', 'Recommended free combinations');
  if (cardSummary) cardSummary.textContent = tx(
    '默认仍是本机翻译和本机识别。下面的组合来自 2026-10 的公开额度，会变，不代表永久免费。',
    'The default stays local. These combinations use public quotas checked in 2026-10. They can change and are not permanently free.',
  );
  refresh();
  return { refresh, noteWeak, open: (next) => { if (next) region = next; openWizard(); } };
}
