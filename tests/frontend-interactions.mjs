// Isolated frontend regressions with a fake IPC boundary. This does not open or
// control the installed desktop app and never calls an external translation API.
// Start npm run dev first. Optionally set ECHOLINGO_TEST_CHROMIUM to a browser path.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';

const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 820 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.addInitScript(() => {
    window.isTauri = true;
    const state = {
      providers: [{ id: 'qa-service', name: 'QA IPC fixture', kind: 'openai', baseUrl: 'https://example.invalid/v1', model: 'test-model', enabled: true, prompt: '', hasKey: true }],
      sourceLanguage: 'auto', targetLanguage: 'zh-Hans',
      shortcuts: { selection: 'Alt+D', capture: 'Alt+S', ocr: 'Alt+Shift+S', silentOcr: 'Alt+C', input: 'Alt+A' },
      saveHistory: true, theme: 'light', maxHistory: 200, autoHideSeconds: 0, ocrProviders: [], activeOcrProviderId: null,
    };
    const callbacks = new Map(), listeners = new Map(), ocrKeys = new Map(), translationKeys = new Map(); let callbackId = 0;
    const scope = (provider) => `${provider.id}:${provider.kind}:${new URL(provider.baseUrl).origin}`;
    translationKeys.set(scope(state.providers[0]), 'qa-original-translation-key');
    const fixture = window.__qa = { settings: state, saveCalls: 0, keyCalls: 0, ocrKeyCalls: 0, ocrTestCalls: 0, ocrDeleteCalls: 0, credentialWrites: [], settingsWrites: [], hideCalls: 0, holdSave: false, failSave: false, releaseSave: () => {}, emit: (name, payload) => listeners.get(name)?.({ event: name, payload, id: 1 }) };
    window.__TAURI_INTERNALS__ = {
      transformCallback: (callback) => { const id = ++callbackId; callbacks.set(id, callback); return id; },
      invoke: async (command, args = {}) => {
        if (command === 'plugin:event|listen') { listeners.set(args.event, callbacks.get(args.handler)); return 1; }
        if (command === 'get_settings') { for (const provider of fixture.settings.providers) provider.hasKey = translationKeys.has(scope(provider)); for (const provider of fixture.settings.ocrProviders) provider.hasKey = ocrKeys.has(scope(provider)); return structuredClone(fixture.settings); }
        if (command === 'get_history') return [];
        if (command === 'diagnostics') return { warnings: [] };
        if (command === 'save_settings') {
          fixture.saveCalls++; fixture.settingsWrites.push(structuredClone(args.settings));
          if (fixture.holdSave) await new Promise((resolve) => { fixture.releaseSave = resolve; });
          if (fixture.failSave) throw new Error('QA save failure');
          fixture.settings = structuredClone(args.settings);
          for (const provider of fixture.settings.ocrProviders ?? []) provider.hasKey = ocrKeys.has(scope(provider));
          for (const provider of fixture.settings.providers) provider.hasKey = translationKeys.has(scope(provider));
          return;
        }
        if (command === 'set_api_key') { fixture.keyCalls++; const provider = fixture.settings.providers.find(item => item.id === args.providerId); if (provider) translationKeys.set(scope(provider), args.key); return; }
        if (command === 'set_ocr_api_key') { fixture.ocrKeyCalls++; const provider = fixture.settings.ocrProviders.find(item => item.id === args.providerId); if (provider) { provider.hasKey = true; ocrKeys.set(scope(provider), args.key); fixture.credentialWrites.push({ providerId: provider.id, kind: provider.kind, key: args.key }); } return; }
        if (command === 'delete_ocr_api_key') { fixture.ocrDeleteCalls++; const provider = fixture.settings.ocrProviders.find(item => item.id === args.providerId); if (provider) { ocrKeys.delete(scope(provider)); provider.hasKey = false; } return; }
        if (command === 'test_ocr_provider') { fixture.ocrTestCalls++; return 'QA OCR test succeeded'; }
        if (command === 'hide_window') { fixture.hideCalls++; return; }
        if (command === 'set_pinned') return;
        if (command === 'translate') return [{ providerId: 'qa-service', providerName: 'QA IPC fixture', text: 'Isolated test translation fixture', elapsedMs: 50 }];
        throw new Error(`Unimplemented QA command: ${command}`);
      },
    };
  });
  await page.goto(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  await page.locator('#footer-status').getByText('准备就绪').waitFor();
  await page.locator('[data-view="settings"]').click();

  // Saving is atomic from the form's perspective: closing or submitting again
  // while the backend is pending cannot replace or close a different editor.
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.locator('#provider-name').fill('QA edited fixture');
  await page.evaluate(() => { window.__qa.holdSave = true; });
  await page.locator('#save-provider').click();
  await page.waitForFunction(() => window.__qa.saveCalls === 1);
  assert.equal(await page.locator('#cancel-provider-dialog').isDisabled(), true);
  assert.equal(await page.locator('#close-provider-dialog').isDisabled(), true);
  assert.equal(await page.locator('#provider-name').isDisabled(), true);
  await page.keyboard.press('Escape');
  await page.locator('#provider-dialog').click({ position: { x: 2, y: 2 } });
  await page.locator('#provider-form').dispatchEvent('submit');
  assert.equal(await page.locator('#provider-dialog').isVisible(), true);
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), 1);
  await page.evaluate(() => { window.__qa.holdSave = false; window.__qa.releaseSave(); });
  await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  assert.equal(await page.locator('#provider-name').inputValue(), 'QA edited fixture');
  await page.evaluate(() => { window.__qa.failSave = true; });
  await page.locator('#save-provider').click();
  await page.locator('#provider-error').getByText('QA save failure').waitFor();
  assert.equal(await page.locator('#cancel-provider-dialog').isEnabled(), true);
  assert.equal(await page.locator('#provider-name').isEnabled(), true);
  await page.locator('#cancel-provider-dialog').click();
  await page.evaluate(() => { window.__qa.failSave = false; });

  // Multiple blanks disable those shortcuts; only nonempty values are compared.
  await page.locator('input[name="selection"]').fill('');
  await page.locator('input[name="capture"]').fill('');
  await page.locator('#save-shortcuts').click();
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === '' && window.__qa.settings.shortcuts.capture === '');
  const savesBeforeDuplicate = await page.evaluate(() => window.__qa.saveCalls);
  await page.locator('input[name="selection"]').fill('Ctrl+P');
  await page.locator('input[name="capture"]').fill('ctrl+p');
  await page.locator('#save-shortcuts').click();
  await page.getByText('不同操作不能使用相同的快捷键。').waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), savesBeforeDuplicate);

  // Presets populate the documented protocol/base while model names remain editable.
  await page.locator('#add-provider').click();
  for (const [preset, base] of [['deepseek', 'https://api.deepseek.com'], ['zhipu', 'https://open.bigmodel.cn/api/paas/v4'], ['siliconflow', 'https://api.siliconflow.cn/v1']]) {
    await page.locator('#provider-preset').selectOption(preset);
    assert.equal(await page.locator('#provider-url').inputValue(), base);
    assert.equal(await page.locator('#provider-kind').inputValue(), 'openai');
    assert.equal(await page.locator('#provider-model').isEditable(), true);
  }
  await page.locator('#provider-preset').selectOption('qwen');
  await page.locator('#provider-qwen-region').selectOption('singapore');
  await page.locator('#provider-qwen-workspace').fill('ws-qa');
  await page.locator('#provider-qwen-workspace').dispatchEvent('change');
  assert.equal(await page.locator('#provider-url').inputValue(), 'https://ws-qa.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1');
  await page.locator('#cancel-provider-dialog').click();

  // Same-origin edits preserve the saved-key indication; a cross-vendor preset
  // clears typed secrets and cannot claim that the original origin's key is valid.
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.locator('#provider-url').fill('https://example.invalid/another/path');
  await page.locator('#provider-model').fill('qa-other-model');
  assert.match(await page.locator('#provider-key').getAttribute('placeholder'), /已保存/);
  await page.locator('#provider-key').fill('qa-discard-on-vendor-change');
  await page.locator('#provider-preset').selectOption('deepseek');
  assert.equal(await page.locator('#provider-key').inputValue(), '');
  assert.doesNotMatch(await page.locator('#provider-key').getAttribute('placeholder'), /已保存/);
  await page.locator('#save-provider').click();
  await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => window.__qa.settings.providers[0].hasKey), false);
  assert.doesNotMatch(await page.locator('#provider-list').textContent(), /密钥已保存/);
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  assert.doesNotMatch(await page.locator('#provider-key').getAttribute('placeholder'), /已保存/);
  await page.locator('#cancel-provider-dialog').click();

  // Native OCR uses complete vendor bundles only in the credential command.
  await page.locator('#add-ocr-provider').click();
  assert.equal(await page.locator('#ocr-provider-kind').inputValue(), 'baidu');
  assert.equal(await page.locator('#ocr-provider-url-field').isHidden(), true);
  assert.equal(await page.locator('#ocr-provider-auth-header-field').isHidden(), true);
  await page.locator('#ocr-provider-name').fill('QA Baidu');
  await page.locator('#ocr-baidu-api-key').fill('qa-baidu-api');
  const beforePartial = await page.evaluate(() => window.__qa.saveCalls);
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-error').getByText('百度 OCR 需要同时填写', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforePartial);
  await page.locator('#ocr-baidu-secret-key').fill('qa-baidu-secret');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-dialog').waitFor({ state: 'hidden' });
  assert.deepEqual(JSON.parse(await page.evaluate(() => window.__qa.credentialWrites.at(-1).key)), { apiKey: 'qa-baidu-api', secretKey: 'qa-baidu-secret' });
  assert.equal(await page.evaluate(() => window.__qa.settings.activeOcrProviderId), null);
  const afterBaidu = await page.evaluate(() => window.__qa.credentialWrites.length);
  await page.getByRole('button', { name: '编辑 OCR QA Baidu', exact: true }).click();
  assert.equal(await page.locator('#ocr-baidu-api-key').inputValue(), '');
  assert.equal(await page.locator('#ocr-baidu-secret-key').inputValue(), '');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => window.__qa.credentialWrites.length), afterBaidu);
  await page.getByRole('button', { name: '编辑 OCR QA Baidu', exact: true }).click();
  await page.locator('#ocr-baidu-api-key').fill('discard-on-protocol-change');
  await page.locator('#ocr-provider-kind').selectOption('tencent');
  assert.equal(await page.locator('#ocr-baidu-api-key').inputValue(), '');
  assert.equal(await page.locator('#remove-ocr-provider-key').isHidden(), true);
  assert.equal(await page.locator('#ocr-provider-url').inputValue(), 'https://ocr.tencentcloudapi.com');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-error').getByText('切换 OCR 协议或服务地址后必须填写完整的新凭据', { exact: false }).waitFor();
  await page.locator('#ocr-tencent-secret-id').fill('qa-tencent-id');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-error').getByText('腾讯 OCR 需要同时填写', { exact: false }).waitFor();
  await page.locator('#ocr-tencent-secret-key').fill('qa-tencent-secret');
  await page.locator('#ocr-tencent-session-token').fill('qa-tencent-session');
  await page.locator('#ocr-provider-region').selectOption('ap-shanghai');
  await page.locator('#ocr-provider-name').fill('QA Tencent');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-dialog').waitFor({ state: 'hidden' });
  assert.deepEqual(JSON.parse(await page.evaluate(() => window.__qa.credentialWrites.at(-1).key)), { secretId: 'qa-tencent-id', secretKey: 'qa-tencent-secret', sessionToken: 'qa-tencent-session' });
  assert.equal(await page.evaluate(() => window.__qa.ocrDeleteCalls), 0);
  assert.equal(await page.evaluate(() => window.__qa.settings.ocrProviders[0].region), 'ap-shanghai');
  const settingsJson = await page.evaluate(() => JSON.stringify(window.__qa.settingsWrites));
  for (const secret of ['qa-baidu-api', 'qa-baidu-secret', 'qa-tencent-id', 'qa-tencent-secret', 'qa-tencent-session', 'discard-on-protocol-change', 'qa-original-translation-key', 'qa-discard-on-vendor-change']) assert.equal(settingsJson.includes(secret), false);
  await page.getByRole('button', { name: '删除 OCR QA Tencent', exact: true }).click();
  await page.locator('#confirm-accept').click();
  await page.waitForFunction(() => window.__qa.settings.ocrProviders.length === 0);
  await page.locator('#add-ocr-provider').click();
  await page.locator('#ocr-provider-name').fill('QA unconfigured');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-dialog').waitFor({ state: 'hidden' });
  const unconfiguredId = await page.evaluate(() => window.__qa.settings.ocrProviders[0].id);
  await page.locator('#active-ocr-provider').selectOption(unconfiguredId);
  await page.getByText('此 OCR 服务尚未配置完整凭据，请先编辑并保存密钥。').waitFor();
  assert.equal(await page.evaluate(() => window.__qa.settings.activeOcrProviderId), null);
  await page.getByRole('button', { name: '删除 OCR QA unconfigured', exact: true }).click();
  await page.locator('#confirm-accept').click();
  await page.waitForFunction(() => window.__qa.settings.ocrProviders.length === 0);

  // OCR is independent of translation services and remains local until selected.
  await page.locator('#add-ocr-provider').click();
  await page.getByRole('dialog', { name: '添加 OCR 服务' }).waitFor();
  await page.locator('#ocr-provider-name').fill('QA OCR gateway');
  await page.locator('#ocr-provider-kind').selectOption('http-json');
  await page.locator('#ocr-provider-url').fill('https://ocr.example.invalid/recognize');
  await page.locator('#ocr-provider-template').fill('{"image": "{imageBase64}"}');
  await page.locator('#ocr-provider-response-path').fill('/data/text');
  await page.locator('#ocr-provider-key').fill('qa-only-placeholder-secret');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => window.__qa.settings.activeOcrProviderId), null);
  assert.equal(await page.evaluate(() => window.__qa.credentialWrites.at(-1).kind), 'http-json');
  const ocrId = await page.evaluate(() => window.__qa.settings.ocrProviders[0].id);
  await page.locator('#active-ocr-provider').selectOption(ocrId);
  await page.locator('#ocr-privacy-notice').getByText('云端 OCR 已启用', { exact: false }).waitFor();
  assert.match(await page.locator('#ocr-privacy-notice').textContent(), /ocr\.example\.invalid/);
  await page.getByRole('button', { name: '编辑 OCR QA OCR gateway', exact: true }).click();
  assert.equal(await page.locator('#ocr-provider-key').inputValue(), '');
  await page.locator('#ocr-provider-template').fill('invalid JSON');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-error').getByText('请输入有效的 JSON 请求模板。').waitFor();
  await page.locator('#cancel-ocr-provider-dialog').click();
  await page.locator('#ocr-provider-list').getByRole('button', { name: '测试连接', exact: true }).click();
  await page.getByText('QA OCR test succeeded').waitFor();
  assert.equal(await page.evaluate(() => window.__qa.ocrTestCalls), 1);
  await page.getByRole('button', { name: '删除 OCR QA OCR gateway', exact: true }).click();
  await page.locator('#confirm-accept').click();
  await page.waitForFunction(() => window.__qa.settings.ocrProviders.length === 0 && window.__qa.settings.activeOcrProviderId === null);

  // Empty Alt+D clears the floating view without focusing its input or making API requests.
  await page.locator('[data-view="translate"]').click();
  await page.locator('#source-text').fill('QA text before empty selection');
  await page.locator('#pin-button').focus();
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => document.activeElement.id), 'pin-button');
  assert.equal(await page.locator('.result-card').count(), 0);

  // Default 0 creates no timer. An optional timer waits for idle time and resets
  // on pointer input; pinning prevents it from hiding a completed translation.
  await page.clock.install();
  await page.locator('[data-view="translate"]').click();
  await page.locator('#source-text').fill('QA default timer test');
  await page.locator('#translate-button').click();
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  await page.clock.fastForward(20_000);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), 0);
  await page.locator('[data-view="settings"]').click();
  await page.locator('#auto-hide-seconds').selectOption('3');
  await page.waitForFunction(() => window.__qa.settings.autoHideSeconds === 3);
  await page.locator('[data-view="translate"]').click();
  await page.locator('#source-text').fill('QA optional timer test');
  await page.locator('#translate-button').click();
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  await page.clock.fastForward(2000);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), 0);
  await page.mouse.move(150, 150);
  await page.clock.fastForward(2000);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), 0);
  await page.clock.fastForward(1100);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), 1);
  await page.locator('#pin-button').click();
  await page.locator('#source-text').fill('QA pinned timer test');
  await page.locator('#translate-button').click();
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  await page.clock.fastForward(10_000);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), 1);
  assert.deepEqual(errors, []);
  console.log('PASS: pending-save close/reentry guard; failure unlock; blank shortcuts; duplicate rejection; default no timer; optional idle reset; pinned timer suppression; OCR dual-key bundles/protocol isolation/no plaintext settings; documented vendor presets; origin-bound saved-key indications; OCR configuration/privacy; empty-selection focus preservation.');
} finally {
  await browser.close();
}
