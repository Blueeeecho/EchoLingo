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
    Object.defineProperty(navigator, 'platform', { configurable: true, get: () => new URL(location.href).searchParams.has('windowsSelectionFixture') ? 'Win32' : 'MacIntel' });
    const state = {
      appVersion: '9.8.7-beta.6',
      providers: [{ id: 'qa-service', name: 'QA IPC fixture', kind: 'openai', baseUrl: 'https://example.invalid/v1', model: 'test-model', enabled: true, prompt: '', hasKey: true }],
      sourceLanguage: 'auto', targetLanguage: 'zh-Hans',
      shortcuts: { selection: 'Alt+D', capture: 'Alt+S', ocr: 'Alt+Shift+S', silentOcr: 'Alt+C', input: 'Alt+A' },
      saveHistory: true, theme: 'light', maxHistory: 20, autoHideSeconds: 0, ocrProviders: [], activeOcrProviderId: null,
    };
    const setupKind = new URL(location.href).searchParams.get('translationSetupFixture');
    if (new URL(location.href).searchParams.has('translationRetryFixture')) {
      state.providers.push({ ...state.providers[0], id: 'qa-retry', name: 'QA retry service' });
    }
    if (['system', 'offline', 'openai'].includes(setupKind)) state.providers[0].kind = setupKind;
    const callbacks = new Map(), listeners = new Map(), ocrKeys = new Map(), translationKeys = new Map(); let callbackId = 0;
    window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener: (event) => listeners.delete(event) };
    const scope = (provider) => ['system', 'offline'].includes(provider.kind) ? `${provider.id}:${provider.kind}` : `${provider.id}:${provider.kind}:${new URL(provider.baseUrl).origin}`;
    translationKeys.set(scope(state.providers[0]), 'qa-original-translation-key');
    const fixture = window.__qa = { permissionState: { platform: 'macos', supported: true, identity: 'application-process', runningBundledApp: true, bundleIdentifier: 'io.github.qa.echolingo', processId: 1, accessibilityGranted: false, screenCaptureGranted: false }, permissionReads: 0, permissionRequests: [], permissionSettings: [], holdTranslation: false, releaseTranslation: () => {}, translationError: null, settings: state, saveCalls: 0, keyCalls: 0, ocrKeyCalls: 0, ocrTestCalls: 0, ocrDeleteCalls: 0, credentialWrites: [], settingsWrites: [], hideCalls: 0, layoutCalls: [], showCalls: [], translationRequests: [], dragCalls: 0, holdSave: false, failSave: false, releaseSave: () => {}, emit: (name, payload) => listeners.get(name)?.({ event: name, payload, id: 1 }) };
    Object.assign(fixture, { nextTranslationId: 0, cancellationRequests: [], holdBegin: false, holdBeginBeforeAllocate: false, beginAttempts: [], releaseBegin: () => {}, presentation: { epoch: 0, presented: true }, holdFit: false, fitWaits: 0, releaseFit: () => {}, showPopupAttempts: [], permissionAtShow: [], failPermissionSettings: false, holdPermissionSettings: false, releasePermissionSettings: () => {} });
    Object.assign(fixture, { systemStatus: { platform: 'macos', supported: true, ready: false, requiresSetup: true, status: 'downloadRequired', message: 'QA 语言包尚未准备', minimumVersion: '26.0' }, systemStatusCalls: [], systemPrepareCalls: [], keyDeleteCalls: 0 });
    Object.assign(fixture, { shortcutLeases: [], nextShortcutLease: 0, holdShortcutBegin: false, releaseShortcutBegin: () => {}, holdShortcutEnd: false, shortcutEndWaits: 0, releaseShortcutEnd: () => {} });
    Object.assign(fixture, { copies: [], spoken: [], permissionOverride: null, managementShows: [] });
    Object.assign(fixture, { diagnosticCalls: [], diagnosticReport: { warnings: [] }, holdDiagnostics: false, releaseDiagnostics: () => {} });
    Object.assign(fixture, { credentialStates: {}, credentialReadCalls: 0, translationTestCalls: 0, settingsReads: 0, translationCredentialWrites: [], serviceLinks: [] });
    Object.assign(fixture, { resizeRequests: [], nativeResizeRequests: [], holdResize: false, releaseResize: () => {} });
    Object.assign(fixture, { pinned: false, nativeVisible: true, popupReveals: 0, nativeHideTransitions: 0 });
    Object.assign(fixture, { holdPopupAck: false, popupAckWaits: 0, releasePopupAck: () => {}, sourceFocusCalls: 0 });
    Object.assign(fixture, { holdPresentationRead: false, presentationReadWaits: 0, releasePresentationRead: () => {} });
    Object.assign(fixture, { historyReads: 0, holdHistory: false, failHistory: false, releaseHistory: () => {} });
    const sourceBoot = new URL(location.href).searchParams.get('sourceDeliveryFixture');
    Object.assign(fixture, { pendingSource: null, sourceAcks: [], sourceAckResults: [], pendingSourceReads: 0, bootSettingsWaits: 0, releaseBootSettings: () => {}, oldSourceAckWaits: 0, newSourceAckWaits: 0, releaseOldSourceAck: () => {}, releaseNewSourceAck: () => {} });
    if (sourceBoot) {
      const permissionBlocked = sourceBoot === 'accessibility-permission';
      fixture.presentation = { epoch: sourceBoot === 'management' || sourceBoot === 'newtask' ? 2 : 1, presented: false };
      fixture.pendingSource = { deliveryId: sourceBoot === 'newtask' ? 2 : 1, presentationEpoch: fixture.presentation.epoch,
        text: sourceBoot === 'empty' || permissionBlocked ? '' : sourceBoot === 'newtask' ? 'Latest generated startup source' : 'Generated startup source', mode: sourceBoot === 'empty' || permissionBlocked ? 'input' : 'translate', focusInput: sourceBoot === 'empty' || permissionBlocked,
        ...(permissionBlocked ? { permissionRequired: 'accessibility' } : {}) };
      if (sourceBoot === 'management') { fixture.pendingSource = null; fixture.pendingSettings = { presentationEpoch: 2 }; }
    }
    fixture.emitInputFocus = (presentation = fixture.nativeInputShow()) => fixture.emit('focus-input', structuredClone(presentation));
    const elementFocus = HTMLElement.prototype.focus;
    HTMLElement.prototype.focus = function (...args) {
      if (this.id === 'source-text') fixture.sourceFocusCalls++;
      return elementFocus.apply(this, args);
    };
    const decorateCredential = (provider, keys) => {
      const cached = fixture.credentialStates[scope(provider)];
      if (cached) provider.credentialState = cached; else delete provider.credentialState;
      provider.hasKey = cached ? cached === 'ready' : keys.has(scope(provider));
    };
    fixture.setCredentialState = (provider, value) => { fixture.credentialStates[scope(provider)] = value; };
    Object.defineProperty(window, 'speechSynthesis', { configurable: true, value: { cancel() {}, speak(value) { fixture.spoken.push({ text: value.text, lang: value.lang }); } } });
    const pendingTranslations = new Map(), cancelledTranslations = new Set();
    let activeTranslationId = null;
    const cancelTranslation = (id) => {
      cancelledTranslations.add(id);
      pendingTranslations.get(id)?.reject(new Error('CANCELLED: fixture translation cancelled'));
      pendingTranslations.delete(id);
      if (activeTranslationId === id) activeTranslationId = null;
    };
    const announcePresentation = () => fixture.emit('translation-presentation', structuredClone(fixture.presentation));
    fixture.nativeHide = (announce = true) => {
      if (fixture.nativeVisible) fixture.nativeHideTransitions++;
      fixture.nativeVisible = false;
      fixture.presentation = { epoch: fixture.presentation.epoch + 1, presented: false };
      if (activeTranslationId !== null) cancelTranslation(activeTranslationId);
      if (announce) announcePresentation();
      return structuredClone(fixture.presentation);
    };
    fixture.nativeShow = (announce = true) => {
      if (!fixture.nativeVisible) fixture.popupReveals++;
      fixture.nativeVisible = true;
      if (!fixture.presentation.presented) fixture.presentation = { epoch: fixture.presentation.epoch + 1, presented: true };
      if (announce) announcePresentation();
      return structuredClone(fixture.presentation);
    };
    fixture.nativeInputShow = (announce = true) => {
      fixture.presentation = { ...fixture.presentation, epoch: fixture.presentation.epoch + 1 };
      if (activeTranslationId !== null) cancelTranslation(activeTranslationId);
      return fixture.nativeShow(announce);
    };
    // Models the backend's pinned-visible-popup decision, not screen capture.
    // Invalidate old translation work while keeping the presentation visible.
    fixture.nativePinnedCaptureStart = () => {
      if (!fixture.pinned || !fixture.nativeVisible || !fixture.presentation.presented || document.body.dataset.view !== 'translate') throw new Error('QA pinned popup must already be visible');
      fixture.presentation = { epoch: fixture.presentation.epoch + 1, presented: true };
      if (activeTranslationId !== null) cancelTranslation(activeTranslationId);
      announcePresentation();
      return structuredClone(fixture.presentation);
    };
    window.__TAURI_INTERNALS__ = {
      transformCallback: (callback) => { const id = ++callbackId; callbacks.set(id, callback); return id; },
      invoke: async (command, args = {}) => {
        if (command === 'plugin:event|listen') {
          listeners.set(args.event, callbacks.get(args.handler));
          if (args.event === 'source-text' && ['dual', 'management', 'newtask'].includes(sourceBoot)) fixture.emit('source-text',
            sourceBoot === 'dual' ? structuredClone(fixture.pendingSource) : { deliveryId: 1, presentationEpoch: 1, text: 'Old generated startup source', mode: 'translate' });
          return 1;
        }
        if (command === 'plugin:event|unlisten') { listeners.delete(args.event); return; }
        if (command === 'get_settings') { fixture.settingsReads++; if (sourceBoot === 'edit' && fixture.settingsReads === 1) { fixture.bootSettingsWaits++; await new Promise(resolve => { fixture.releaseBootSettings = resolve; }); } for (const provider of fixture.settings.providers) decorateCredential(provider, translationKeys); for (const provider of fixture.settings.ocrProviders) decorateCredential(provider, ocrKeys); const value = structuredClone(fixture.settings); if (fixture.registrationOverride !== undefined) value.shortcutRegistration = structuredClone(fixture.registrationOverride); return value; }
        if (command === 'get_history') {
          fixture.historyReads++;
          const snapshot = structuredClone(fixture.history ?? []);
          if (fixture.holdHistory) await new Promise(resolve => { fixture.releaseHistory = resolve; });
          if (fixture.failHistory) throw new Error('QA history read failed');
          return snapshot;
        }
        if (command === 'toggle_favorite') { const entry = fixture.history?.find(item => item.id === args.id); if (entry) entry.favorite = !entry.favorite; return; }
        if (command === 'delete_history') { fixture.history = args.id ? (fixture.history ?? []).filter(item => item.id !== args.id) : []; return; }
        if (command === 'copy_text') { fixture.copies.push(args.text); return; }
        if (command === 'get_translation_presentation') {
          const presentation = structuredClone(fixture.presentation);
          if (fixture.holdPresentationRead) { fixture.presentationReadWaits++; await new Promise((resolve) => { fixture.releasePresentationRead = resolve; }); }
          return presentation;
        }
        if (command === 'get_pending_settings') return fixture.pendingSettings ?? null;
        if (command === 'get_pending_source') { fixture.pendingSourceReads++; return structuredClone(fixture.pendingSource); }
        if (command === 'ack_source_delivery') {
          fixture.sourceAcks.push(args.deliveryId);
          if (sourceBoot === 'delayed-ack') {
            if (args.deliveryId === 1) { fixture.oldSourceAckWaits++; await new Promise(resolve => { fixture.releaseOldSourceAck = resolve; }); }
            if (args.deliveryId === 2) { fixture.newSourceAckWaits++; await new Promise(resolve => { fixture.releaseNewSourceAck = resolve; }); }
          }
          const cleared = fixture.pendingSource?.deliveryId === args.deliveryId;
          if (cleared) fixture.pendingSource = null;
          fixture.sourceAckResults.push({ deliveryId: args.deliveryId, cleared }); return cleared;
        }
        if (command === 'get_system_translation_status') { fixture.systemStatusCalls.push(structuredClone(args)); return structuredClone(fixture.systemStatus); }
        if (command === 'prepare_system_translation') { fixture.systemPrepareCalls.push(structuredClone(args)); if (fixture.holdSystemPreparation) await new Promise(resolve => { fixture.releaseSystemPreparation = resolve; }); fixture.systemStatus = { ...fixture.systemStatus, ready: true, requiresSetup: false, status: 'installed', message: 'QA 本机语言包已就绪' }; return structuredClone(fixture.systemStatus); }
        if (command === 'permission_status') { fixture.permissionReads++; return structuredClone(fixture.permissionState); }
        if (command === 'request_permission') { fixture.permissionRequests.push(args.kind); if (fixture.permissionOverride) return structuredClone(fixture.permissionOverride); if (args.kind === 'accessibility') fixture.permissionState.accessibilityGranted = true; else fixture.permissionState.screenCaptureGranted = true; return structuredClone(fixture.permissionState); }
        if (command === 'open_permission_settings') {
          fixture.permissionSettings.push(args.kind);
          if (fixture.holdPermissionSettings) await new Promise((resolve) => { fixture.releasePermissionSettings = resolve; });
          if (fixture.failPermissionSettings) throw new Error('QA internal permission-link failure detail');
          return;
        }
        if (command === 'set_shortcut_recording') {
          if (args.active) { const id = ++fixture.nextShortcutLease; fixture.shortcutLeases.push({ active: true, id }); if (fixture.holdShortcutBegin) await new Promise(resolve => { fixture.releaseShortcutBegin = resolve; }); return id; }
          fixture.shortcutLeases.push({ active: false, id: args.leaseId }); if (fixture.holdShortcutEnd) { fixture.shortcutEndWaits++; await new Promise(resolve => { fixture.releaseShortcutEnd = resolve; }); } return args.leaseId;
        }
        if (command === 'diagnostics') {
          fixture.diagnosticCalls.push(structuredClone(args));
          if (fixture.holdDiagnostics) await new Promise(resolve => { fixture.releaseDiagnostics = resolve; });
          return structuredClone(fixture.diagnosticReport);
        }
        if (command === 'save_settings') {
          fixture.saveCalls++; fixture.settingsWrites.push(structuredClone(args.settings));
          (fixture.shortcutRetryActions ??= []).push(structuredClone(args.retryShortcutActions ?? []));
          if (fixture.holdSave) await new Promise((resolve) => { fixture.releaseSave = resolve; });
          if (fixture.failSave) throw new Error('QA save failure');
          const unavailable = args.retryShortcutActions?.find((action) => fixture.unavailableShortcutActions?.includes(action));
          if (unavailable) throw new Error(`QA unavailable shortcut: ${unavailable}`);
          fixture.settings = structuredClone(args.settings);
          for (const provider of fixture.settings.ocrProviders ?? []) provider.hasKey = ocrKeys.has(scope(provider));
          for (const provider of fixture.settings.providers) provider.hasKey = translationKeys.has(scope(provider));
          return;
        }
        if (command === 'set_api_key') { fixture.keyCalls++; const provider = fixture.settings.providers.find(item => item.id === args.providerId); if (provider) { translationKeys.set(scope(provider), args.key); fixture.translationCredentialWrites.push({ kind: provider.kind, key: args.key }); } return; }
        if (command === 'open_service_link') { fixture.serviceLinks.push(args.url); return; }
        if (command === 'delete_api_key') { fixture.keyDeleteCalls++; const provider = fixture.settings.providers.find(item => item.id === args.providerId); if (provider) translationKeys.delete(scope(provider)); return; }
        if (command === 'set_ocr_api_key') { fixture.ocrKeyCalls++; const provider = fixture.settings.ocrProviders.find(item => item.id === args.providerId); if (provider) { provider.hasKey = true; ocrKeys.set(scope(provider), args.key); fixture.credentialWrites.push({ providerId: provider.id, kind: provider.kind, key: args.key }); } return; }
        if (command === 'delete_ocr_api_key') { fixture.ocrDeleteCalls++; const provider = fixture.settings.ocrProviders.find(item => item.id === args.providerId); if (provider) { ocrKeys.delete(scope(provider)); provider.hasKey = false; } return; }
        if (command === 'test_provider') { fixture.translationTestCalls++; fixture.credentialReadCalls++; const provider = fixture.settings.providers.find(item => item.id === args.providerId); if (provider) fixture.setCredentialState(provider, 'ready'); return 'QA translation credential test succeeded'; }
        if (command === 'test_ocr_provider') { fixture.ocrTestCalls++; fixture.credentialReadCalls++; const provider = fixture.settings.ocrProviders.find(item => item.id === args.providerId); if (provider && fixture.credentialStates[scope(provider)]) fixture.setCredentialState(provider, 'ready'); return 'QA OCR test succeeded'; }
        if (command === 'hide_window') { fixture.hideCalls++; fixture.nativeHide(); return; }
        if (command === 'wait_for_window_sizing') return 0;
        if (command === 'fit_window') { fixture.layoutCalls.push(args); if (fixture.holdFit) { fixture.fitWaits++; await new Promise((resolve) => { fixture.releaseFit = resolve; }); } return; }
        if (command === 'start_window_drag') { fixture.dragCalls++; return; }
        if (command === 'start_window_resize') { fixture.nativeResizeRequests.push(structuredClone(args)); return; }
        if (command === 'resize_popup_width') { fixture.resizeRequests.push(structuredClone(args)); if (fixture.holdResize) await new Promise((resolve) => { fixture.releaseResize = resolve; }); return; }
        if (command === 'show_management') {
          if (args.presentationEpoch !== fixture.presentation.epoch) throw new Error('CANCELLED: stale management presentation');
          if (fixture.layoutCalls.at(-1)?.presentation !== 'management') throw new Error('MANAGEMENT_NOT_READY');
          (fixture.managementShows ??= []).push({ view: document.body.dataset.view, layout: structuredClone(fixture.layoutCalls.at(-1)) });
          fixture.pendingSettings = null;
          return fixture.nativeShow();
        }
        if (command === 'show_popup') {
          fixture.showPopupAttempts.push(structuredClone(args));
          if (args.presentationEpoch !== fixture.presentation.epoch) throw new Error('CANCELLED: stale popup presentation');
          fixture.permissionAtShow.push({ visible: !document.querySelector('#permission-guidance').hidden, title: document.querySelector('#permission-guidance-title').textContent, layout: structuredClone(fixture.layoutCalls.at(-1)) });
          fixture.showCalls.push(structuredClone(fixture.layoutCalls.at(-1)));
          const presentation = fixture.nativeShow();
          if (fixture.holdPopupAck) { fixture.popupAckWaits++; await new Promise((resolve) => { fixture.releasePopupAck = resolve; }); }
          return presentation;
        }
        if (command === 'set_pinned') { fixture.pinned = args.pinned; (fixture.pinRequests ??= []).push(args.pinned); return; }
        if (command === 'begin_translation') {
          fixture.beginAttempts.push(structuredClone(args));
          if (fixture.holdBeginBeforeAllocate) await new Promise((resolve) => { fixture.releaseBegin = resolve; });
          if (!fixture.presentation.presented || args.presentationEpoch !== fixture.presentation.epoch) throw new Error('CANCELLED: stale translation presentation');
          if (activeTranslationId !== null) cancelTranslation(activeTranslationId);
          const id = ++fixture.nextTranslationId; activeTranslationId = id;
          if (fixture.holdBegin) await new Promise((resolve) => { fixture.releaseBegin = resolve; });
          return id;
        }
        if (command === 'cancel_translation') { fixture.cancellationRequests.push(args.requestId); cancelTranslation(args.requestId); return; }
        if (command === 'translate') {
          if (cancelledTranslations.has(args.requestId) || activeTranslationId !== args.requestId) throw new Error('CANCELLED: fixture translation cancelled');
          fixture.translationRequests.push(structuredClone(args));
          if (fixture.holdTranslation) await new Promise((resolve, reject) => {
            pendingTranslations.set(args.requestId, { resolve, reject });
            fixture.releaseTranslation = () => { pendingTranslations.delete(args.requestId); resolve(); };
          });
          if (fixture.translationError) throw new Error(fixture.translationError);
          activeTranslationId = null;
          if (fixture.translationResults) return structuredClone(fixture.translationResults.filter((result) => !args.providerId || result.providerId === args.providerId));
          return [{ providerId: 'qa-service', providerName: 'QA IPC fixture', text: fixture.translationResultError ? '' : fixture.translationResultText ?? 'Isolated test translation fixture', ...(fixture.translationResultError ? { error: fixture.translationResultError } : {}), ...(fixture.translationResultLanguages !== undefined ? { resolvedLanguages: structuredClone(fixture.translationResultLanguages) } : {}), elapsedMs: 50 }];
        }
        throw new Error(`Unimplemented QA command: ${command}`);
      },
    };
  });
  const sourceFixtureUrl = (mode) => {
    const url = new URL(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
    url.searchParams.set('sourceDeliveryFixture', mode); return url.href;
  };
  for (const mode of ['before-listener', 'dual', 'newtask']) {
    await page.goto(sourceFixtureUrl(mode));
    await page.waitForFunction(() => window.__qa.translationRequests.length === 1 && window.__qa.sourceAcks.length > 0);
    assert.equal(await page.locator('#source-text').inputValue(), mode === 'newtask' ? 'Latest generated startup source' : 'Generated startup source');
    await page.waitForTimeout(60);
    assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 1);
    assert.equal(await page.evaluate(() => window.__qa.pendingSource), null);
    assert.equal(await page.evaluate(() => window.__qa.historyReads), 0);
    assert.equal(await page.locator('#history-list > *').count(), 0);
  }
  // The startup-pull ACK is still in flight when a newer live delivery arrives.
  // Hold the new ACK too, so the old completion must visibly preserve ID2.
  await page.goto(sourceFixtureUrl('delayed-ack'));
  await page.waitForFunction(() => window.__qa.oldSourceAckWaits === 1 && window.__qa.translationRequests.length === 1);
  await page.evaluate(() => {
    const fixture = window.__qa;
    fixture.presentation = { epoch: fixture.presentation.epoch + 1, presented: false };
    fixture.pendingSource = { deliveryId: 2, presentationEpoch: fixture.presentation.epoch, text: 'New live source during old ACK', mode: 'translate' };
    fixture.emit('translation-presentation', structuredClone(fixture.presentation));
    fixture.emit('source-text', structuredClone(fixture.pendingSource));
  });
  await page.waitForFunction(() => window.__qa.newSourceAckWaits === 1 && window.__qa.translationRequests.length === 2);
  await page.evaluate(() => window.__qa.releaseOldSourceAck());
  await page.waitForFunction(() => window.__qa.sourceAckResults.some(item => item.deliveryId === 1));
  assert.deepEqual(await page.evaluate(() => window.__qa.sourceAckResults.find(item => item.deliveryId === 1)), { deliveryId: 1, cleared: false });
  assert.equal(await page.evaluate(() => window.__qa.pendingSource.deliveryId), 2);
  assert.equal(await page.locator('#source-text').inputValue(), 'New live source during old ACK');
  assert.deepEqual(await page.evaluate(() => window.__qa.sourceAcks), [1, 2]);
  await page.evaluate(() => window.__qa.releaseNewSourceAck());
  await page.waitForFunction(() => window.__qa.pendingSource === null);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 2);
  assert.equal(await page.locator('#source-text').inputValue(), 'New live source during old ACK');
  await page.goto(sourceFixtureUrl('empty'));
  await page.waitForFunction(() => document.activeElement.id === 'source-text' && window.__qa.sourceAcks.length === 1);
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 0);
  await page.goto(sourceFixtureUrl('edit'));
  await page.waitForFunction(() => window.__qa.bootSettingsWaits === 1);
  await page.locator('#source-text').fill('Generated user edit while settings load');
  await page.evaluate(() => window.__qa.releaseBootSettings());
  await page.waitForFunction(() => window.__qa.sourceAcks.length === 1);
  assert.equal(await page.locator('#source-text').inputValue(), 'Generated user edit while settings load');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 0);
  await page.goto(sourceFixtureUrl('management'));
  await page.waitForFunction(() => document.body.dataset.view === 'settings' && window.__qa.sourceAcks.length === 1);
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 0);
  // A cold-start permission failure uses the same durable source delivery as
  // selection. Prepare the accessibility guide before the very first show.
  await page.goto(sourceFixtureUrl('accessibility-permission'));
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  await page.waitForFunction(() => window.__qa.sourceAcks.length === 1 && window.__qa.showCalls.length === 1);
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => window.__qa.permissionAtShow[0].visible), true);
  assert.match(await page.evaluate(() => window.__qa.permissionAtShow[0].title), /划词.*辅助功能权限/);
  assert.equal(await page.evaluate(() => window.__qa.permissionAtShow[0].layout.presentation), 'popup');
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts[0].focusInput), true);
  assert.equal(await page.evaluate(() => document.activeElement.id), 'source-text');
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionSettings), []);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 0);
  console.log('PASS: capture before listener replays once after readiness; event plus pull translates once; old startup payloads cannot overwrite edits, management, or a newer task; empty Alt+D retains first-input focus. Fake IPC only.');
  await page.goto(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
  const goView = async (view) => {
    if (await page.locator('body').getAttribute('data-view') === view) return;
    if (await page.locator('body').getAttribute('data-view') !== 'translate') {
      await page.locator('button[data-view="translate"]').click();
      if (view === 'translate') return;
    }
    await page.locator('#more-toggle').click();
    await page.locator(`button[data-view="${view}"]`).click();
  };
  // History is not on the startup/capture/translation critical path. A read
  // already in flight may finish after navigation, but must not build hidden
  // cards or clear a newer translation's dirty revision.
  assert.equal(await page.evaluate(() => window.__qa.historyReads), 0);
  assert.equal(await page.locator('#history-list > *').count(), 0);
  await page.evaluate(() => {
    window.__qa.history = [{ id: 'lazy-old', createdAt: 1792890000000, text: 'Old lazy snapshot', sourceLanguage: 'en', targetLanguage: 'zh-Hans', results: [], favorite: false }];
    window.__qa.holdHistory = true;
  });
  await page.locator('#source-text').fill('Translation before history is opened');
  await page.locator('#translate-button').click();
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.historyReads), 0);
  await goView('history');
  await page.waitForFunction(() => window.__qa.historyReads === 1);
  await goView('translate');
  await page.evaluate(() => { window.__qa.history = [{ id: 'lazy-new', createdAt: 1792890001000, text: 'New lazy snapshot', sourceLanguage: 'en', targetLanguage: 'zh-Hans', results: [], favorite: false }]; });
  await page.locator('#source-text').fill('Translation superseding the held history snapshot');
  await page.locator('#translate-button').click();
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  await page.evaluate(async () => {
    window.__qa.holdHistory = false; window.__qa.releaseHistory();
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
  assert.equal(await page.evaluate(() => window.__qa.historyReads), 1);
  assert.equal(await page.locator('#history-list > *').count(), 0);
  await goView('history');
  await page.getByText('New lazy snapshot', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.historyReads), 2);
  await goView('translate');
  await goView('history');
  assert.equal(await page.evaluate(() => window.__qa.historyReads), 2, 'clean history reuses its fetched snapshot');
  await page.evaluate(() => { window.__qa.holdHistory = true; });
  await page.getByRole('button', { name: '收藏翻译', exact: true }).click();
  await page.waitForFunction(() => window.__qa.historyReads === 3);
  await page.getByRole('button', { name: '收藏翻译', exact: true }).click();
  await page.waitForFunction(() => window.__qa.history[0].favorite === false);
  assert.equal(await page.evaluate(() => window.__qa.historyReads), 3, 'mutations share one active history read');
  await page.evaluate(() => { window.__qa.holdHistory = false; window.__qa.releaseHistory(); });
  await page.waitForFunction(() => window.__qa.historyReads === 4);
  await page.getByRole('button', { name: '收藏翻译', exact: true }).waitFor();
  await page.evaluate(() => { window.__qa.failHistory = true; });
  await page.getByRole('button', { name: '收藏翻译', exact: true }).click();
  await page.locator('#toast').filter({ hasText: 'QA history read failed' }).waitFor();
  await goView('translate');
  await page.evaluate(() => { window.__qa.failHistory = false; });
  await goView('history');
  await page.getByRole('button', { name: '取消收藏', exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.historyReads), 6, 'failed history reads stay dirty and can retry');
  await page.getByRole('button', { name: '删除记录', exact: true }).click();
  await page.getByText('暂无翻译记录', { exact: true }).waitFor();
  console.log('PASS: history never fetches/renders during startup or hidden translation; clean visits reuse data; delayed reads do not render hidden cards or erase newer mutations; concurrent mutations coalesce; failures retry and deletion refreshes.');
  await page.goto(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
  // A blank popup has no app chrome, tutorial, counters, or result placeholder.
  assert.equal(await page.locator('.management-header').isVisible(), false);
  assert.equal(await page.locator('.app-footer').isVisible(), false);
  assert.equal(await page.locator('.preview-banner').isVisible(), false);
  assert.equal(await page.locator('#view-translate .column-caption, #view-translate .translation-empty, #character-count, #service-counter').count(), 0);
  assert.equal(await page.locator('#translate-button').isDisabled(), true);
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  assert.match(await page.locator('#source-text').getAttribute('placeholder'), /划词 Alt\+D/);
  assert.match(await page.locator('#source-text').getAttribute('placeholder'), /Esc 取消/);
  assert.equal(await page.locator('#core-guidance').isHidden(), true);
  await page.evaluate(() => {
    window.__qa.registrationOverride = [{ action: 'selection', combo: 'Alt+D', active: false, error: 'AlreadyRegistered' }];
  });
  await goView('settings');
  const historyBeforeGuidance = await page.locator('#save-history').isChecked();
  const readsBeforeGuidance = await page.evaluate(() => window.__qa.settingsReads);
  await page.locator('#save-history').click();
  await page.waitForFunction((reads) => window.__qa.settingsReads > reads, readsBeforeGuidance);
  await goView('translate');
  await page.locator('#core-guidance').waitFor({ state: 'visible' });
  assert.match(await page.locator('#core-guidance-text').textContent(), /划词翻译 Alt\+D/);
  assert.match(await page.locator('#core-guidance-text').textContent(), /占用/);
  assert.equal((await page.locator('#core-guidance-apply').textContent()).trim(), '改用 Ctrl+Alt+D');
  await page.evaluate(() => { window.__qa.registrationOverride = null; });
  await goView('settings');
  if ((await page.locator('#save-history').isChecked()) !== historyBeforeGuidance) await page.locator('#save-history').click();
  await goView('translate');
  await page.waitForFunction(() => document.querySelector('#core-guidance').hidden);
  await page.evaluate(() => {
    const toast = document.querySelector('#toast'); toast.hidden = true; toast.textContent = '';
    window.__qa.saveCalls = 0; window.__qa.settingsWrites = [];
  });
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionSettings), []);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);
  assert.equal(await page.locator('#restore-original-breaks').isHidden(), true);
  // Empty Alt+D neither pins the window nor revives old toolbar focus. Pinning
  // uses the icon state, without a block background or success notification.
  const pin = page.locator('#pin-button');
  const pinBounds = await pin.boundingBox();
  assert.ok(pinBounds && pinBounds.width >= 32 && pinBounds.height >= 32);
  assert.ok(await pin.locator('svg').evaluate((element) => element.getBoundingClientRect().width >= 18));
  assert.equal(await pin.getAttribute('aria-pressed'), 'false');
  assert.notEqual(await pin.locator('svg').evaluate((element) => getComputedStyle(element).transform), 'none');
  assert.equal(await pin.locator('svg').evaluate((element) => getComputedStyle(element).fill), 'none');
  await pin.focus();
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  assert.equal(await page.evaluate(() => document.activeElement.id), '');
  await page.waitForFunction(() => window.__qa.showPopupAttempts.at(-1)?.reuseVisiblePopup === false);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).focusInput), false);
  assert.equal(await pin.getAttribute('aria-pressed'), 'false');
  assert.deepEqual(await page.evaluate(() => window.__qa.pinRequests ?? []), []);
  assert.equal(await page.locator('#toast').isHidden(), true);

  // Native empty Alt+D explicitly focuses only after the popup is prepared.
  // Actual typing requires no click; passive nonempty source stays passive.
  const emptyRequestsBefore = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input', focusInput: true }));
  await page.waitForFunction(() => document.activeElement.id === 'source-text');
  await page.keyboard.type('QA immediate keyboard input');
  assert.equal(await page.locator('#source-text').inputValue(), 'QA immediate keyboard input');
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).focusInput), true);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).reuseVisiblePopup), false);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestsBefore);
  // Window activation can move focus to the document after the editor was focused.
  // A single redirected character has no later native input event to repair
  // button state. Backspace and paste need the same editing/layout pipeline.
  await page.locator('#source-text').fill('');
  await page.evaluate(() => document.querySelector('#source-text').blur());
  await page.keyboard.type('X');
  assert.equal(await page.locator('#source-text').inputValue(), 'X');
  for (const id of ['#translate-button', '#copy-source', '#speak-source', '#clear-source']) assert.equal(await page.locator(id).isEnabled(), true);
  assert.equal(await page.locator('body').evaluate(element => element.classList.contains('source-empty')), false);
  await page.evaluate(() => document.querySelector('#source-text').blur());
  await page.keyboard.press('Backspace');
  assert.equal(await page.locator('#source-text').inputValue(), '');
  for (const id of ['#translate-button', '#copy-source', '#speak-source', '#clear-source']) assert.equal(await page.locator(id).isDisabled(), true);
  assert.equal(await page.locator('body').evaluate(element => element.classList.contains('source-empty')), true);
  const emptySourceHeight = await page.locator('#source-text').evaluate(element => element.getBoundingClientRect().height);
  const fallbackPaste = (text) => page.evaluate((text) => {
    document.querySelector('#source-text').blur();
    const clipboardData = new DataTransfer(); clipboardData.setData('text', text);
    document.dispatchEvent(new ClipboardEvent('paste', { clipboardData, bubbles: true, cancelable: true }));
  }, text);
  await fallbackPaste('Pasted line one\nPasted line two\nPasted line three\nPasted line four');
  assert.equal(await page.locator('#translate-button').isEnabled(), true);
  assert.equal(await page.locator('#copy-source').isEnabled(), true);
  assert.ok(await page.locator('#source-text').evaluate(element => element.getBoundingClientRect().height) > emptySourceHeight);
  const fallbackPending = await page.evaluate(() => {
    window.__qa.holdTranslation = true;
    return { requests: window.__qa.translationRequests.length, cancellations: window.__qa.cancellationRequests.length };
  });
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction(count => window.__qa.translationRequests.length > count, fallbackPending.requests);
  await fallbackPaste(' newer fallback edit');
  await page.waitForFunction(count => window.__qa.cancellationRequests.length > count, fallbackPending.cancellations);
  assert.equal(await page.locator('.results-column').isHidden(), true);
  assert.equal(await page.locator('#translate-button').getAttribute('aria-label'), '翻译');
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.releaseTranslation(); });
  await page.locator('#source-text').fill('x'.repeat(20000));
  await page.evaluate(() => document.querySelector('#source-text').setSelectionRange(19998, 20000));
  await fallbackPaste('ABCDE');
  assert.equal((await page.locator('#source-text').inputValue()).length, 20000);
  assert.ok((await page.locator('#source-text').inputValue()).endsWith('AB'));
  console.log('PASS: body-focus single-key input, fallback Backspace and paste immediately synchronize actions/layout; fallback edits cancel old translation; selection replacement respects the text limit.');
  // Window activation can move focus to the document after the editor was focused.
  // The first typed burst, including Enter, must still land in the blank popup.
  await page.locator('#source-text').fill('');
  await page.evaluate(() => document.querySelector('#source-text').blur());
  assert.notEqual(await page.evaluate(() => document.activeElement.id), 'source-text');
  const stolenRequests = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.keyboard.type('Typed blank popup 55001');
  await page.keyboard.press('Enter');
  assert.equal(await page.locator('#source-text').inputValue(), 'Typed blank popup 55001');
  await page.waitForFunction((count) => window.__qa.translationRequests.length > count, stolenRequests);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), 'Typed blank popup 55001');
  await page.locator('#pin-button').focus();
  await page.keyboard.type('NOPE');
  assert.equal(await page.locator('#source-text').inputValue(), 'Typed blank popup 55001');
  assert.equal(await page.locator('#speak-source').isVisible(), true);
  assert.equal(await page.locator('#copy-source').isVisible(), true);
  await page.locator('#copy-source').click();
  await page.locator('#speak-source').click();
  assert.equal(await page.evaluate(() => window.__qa.copies.at(-1)), 'Typed blank popup 55001');
  assert.equal(await page.evaluate(() => window.__qa.spoken.at(-1).text), 'Typed blank popup 55001');
  await page.locator('.app-shell').screenshot({ path: 'test-results/source-actions.png' });
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  await page.waitForFunction(() => document.activeElement.id !== 'source-text');
  assert.equal(await page.locator('.source-actions').isVisible(), false);
  // A native popup may have been accepted before its IPC acknowledgment reaches
  // this WebView. A newer selection epoch, edit or management view must stop
  // that old blank-input continuation from focusing the source afterward.
  for (const superseding of ['selection-epoch', 'edit', 'view', 'view-roundtrip']) {
    const before = await page.evaluate(() => {
      const fixture = window.__qa;
      document.activeElement?.blur();
      fixture.holdPopupAck = true;
      const before = { waits: fixture.popupAckWaits, focuses: fixture.sourceFocusCalls, requests: fixture.translationRequests.length };
      fixture.emit('source-text', { text: '', mode: 'input', focusInput: true, presentationEpoch: fixture.presentation.epoch });
      return before;
    });
    await page.waitForFunction((waits) => window.__qa.popupAckWaits > waits, before.waits);
    if (superseding === 'selection-epoch') await page.evaluate(() => { window.__qa.nativeHide(); window.__qa.nativeShow(); });
    else if (superseding === 'edit') await page.evaluate(() => {
      const source = document.querySelector('#source-text');
      source.value = 'QA edit before delayed popup acknowledgment';
      source.dispatchEvent(new Event('input', { bubbles: true }));
    });
    else {
      await goView('settings');
      if (superseding === 'view-roundtrip') await goView('translate');
    }
    await page.evaluate(() => { window.__qa.holdPopupAck = false; window.__qa.releasePopupAck(); });
    // Drain the promise continuation, independently of future layout frames.
    await page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 0)));
    assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), before.focuses, `old popup acknowledgment focused after ${superseding}`);
    assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), before.requests);
    if (superseding === 'edit') assert.equal(await page.locator('#source-text').inputValue(), 'QA edit before delayed popup acknowledgment');
    await goView('translate');
  }
  // Hold only frames scheduled by this explicit focus request, then let a newer
  // capture/edit/view overtake it before executing those exact callbacks.
  for (const superseding of ['selection-epoch', 'edit', 'view', 'view-roundtrip']) {
    const before = await page.evaluate(async () => {
      const fixture = window.__qa;
      document.activeElement?.blur();
      const frames = [], scheduleFrame = window.requestAnimationFrame;
      window.requestAnimationFrame = (callback) => { frames.push(callback); return 0; };
      try {
        fixture.emitInputFocus();
        await new Promise((resolve) => setTimeout(resolve, 0));
      } finally { window.requestAnimationFrame = scheduleFrame; }
      fixture.releaseInputFocusFrames = () => { for (const callback of frames) callback(performance.now()); };
      return { focuses: fixture.sourceFocusCalls, frames: frames.length };
    });
    assert.ok(before.frames > 0);
    if (superseding === 'selection-epoch') await page.evaluate(() => { window.__qa.nativeHide(); window.__qa.nativeShow(); });
    else if (superseding === 'edit') await page.evaluate(() => {
      const source = document.querySelector('#source-text');
      source.value = 'QA edit before delayed input frame';
      source.dispatchEvent(new Event('input', { bubbles: true }));
    });
    else {
      await goView('settings');
      if (superseding === 'view-roundtrip') await goView('translate');
    }
    await page.evaluate(() => window.__qa.releaseInputFocusFrames());
    assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), before.focuses, `old input frame focused after ${superseding}`);
    if (superseding === 'edit') assert.equal(await page.locator('#source-text').inputValue(), 'QA edit before delayed input frame');
    await goView('translate');
  }
  await page.evaluate(() => window.__qa.emitInputFocus());
  await page.waitForFunction(() => document.activeElement.id === 'source-text');
  // The native presentation arrives first, but its entire focus event can be
  // delayed past a user edit or navigation that keeps the native epoch equal.
  for (const superseding of ['edit', 'view', 'view-roundtrip']) {
    const before = await page.evaluate(() => {
      const fixture = window.__qa;
      document.activeElement?.blur();
      const presentation = fixture.nativeInputShow();
      return { presentation, focuses: fixture.sourceFocusCalls };
    });
    if (superseding === 'edit') await page.evaluate(() => {
      const source = document.querySelector('#source-text');
      source.value = 'QA edit before same-epoch whole input event';
      source.dispatchEvent(new Event('input', { bubbles: true }));
    });
    else {
      await goView('settings');
      if (superseding === 'view-roundtrip') await goView('translate');
    }
    const expectedView = await page.locator('body').getAttribute('data-view');
    assert.equal(await page.evaluate(() => window.__qa.presentation.epoch), before.presentation.epoch);
    await page.evaluate((presentation) => {
      // Replaying its presentation must not refresh an already observed epoch's
      // baseline and thereby legitimize the delayed complete focus event.
      window.__qa.emit('translation-presentation', presentation);
      window.__qa.emitInputFocus(presentation);
    }, before.presentation);
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), before.focuses, `same-epoch whole input event refocused after ${superseding}`);
    assert.equal(await page.locator('body').getAttribute('data-view'), expectedView);
    // A new explicit input action, even while visible or in management, gets a
    // fresh native epoch and is allowed to return to the editor and focus it.
    await page.evaluate(() => window.__qa.emitInputFocus());
    await page.waitForFunction((before) => window.__qa.presentation.epoch > before.presentation.epoch
      && window.__qa.sourceFocusCalls === before.focuses + 1 && document.activeElement.id === 'source-text', before);
    assert.equal(await page.locator('body').getAttribute('data-view'), 'translate');
  }
  // A delayed complete focus event must retain its native identity, including
  // when the newer backend selection has not yet reached the WebView.
  for (const announceSelection of [true, false]) {
    const before = await page.evaluate((announce) => {
      const fixture = window.__qa;
      document.activeElement?.blur();
      const payload = structuredClone(fixture.presentation), focuses = fixture.sourceFocusCalls;
      fixture.nativeHide(announce);
      fixture.emitInputFocus(payload);
      return focuses;
    }, announceSelection);
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), before, `old complete input event focused; selection announced=${announceSelection}`);
    await page.evaluate(() => window.__qa.nativeShow());
  }
  const beforeInvalidFocus = await page.evaluate(() => {
    const fixture = window.__qa;
    document.activeElement?.blur();
    const epoch = fixture.presentation.epoch, focuses = fixture.sourceFocusCalls;
    for (const payload of [undefined, null, {}, { epoch, presented: false }, { epoch: -1, presented: true },
      { epoch: 0.5, presented: true }, { epoch: String(epoch), presented: true }, { epoch: epoch + 100, presented: true }]) {
      fixture.emit('focus-input', payload);
    }
    return { epoch, focuses };
  });
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), beforeInvalidFocus.focuses);
  assert.equal(await page.evaluate(() => window.__qa.presentation.epoch), beforeInvalidFocus.epoch);

  // A valid native hidden→visible Alt+A may deliver focus before or after its
  // presentation announcement. Verify its backend state before accepting it.
  for (const focusFirst of [true, false]) {
    const requests = await page.evaluate(() => { window.__qa.holdTranslation = true; return window.__qa.translationRequests.length; });
    await page.locator('#source-text').fill('QA old translation before native input');
    await page.locator('#source-text').press('Enter');
    await page.waitForFunction((count) => window.__qa.translationRequests.length > count, requests);
    const before = await page.evaluate((first) => {
      const fixture = window.__qa;
      document.activeElement?.blur();
      fixture.nativeHide(!first);
      const presentation = fixture.nativeInputShow(!first);
      const before = { focuses: fixture.sourceFocusCalls, shows: fixture.showPopupAttempts.length, presentation };
      fixture.emitInputFocus(presentation);
      return before;
    }, focusFirst);
    await page.waitForFunction((focuses) => window.__qa.sourceFocusCalls === focuses + 1
      && document.activeElement.id === 'source-text', before.focuses);
    if (focusFirst) await page.evaluate((presentation) => window.__qa.emit('translation-presentation', presentation), before.presentation);
    assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.length), before.shows);
    await page.evaluate(() => { window.__qa.holdTranslation = false; });
  }
  // Even an accepted backend read can be delayed. User work while it is in
  // flight must prevent its eventual response from granting a fresh focus.
  for (const superseding of ['selection-epoch', 'edit', 'view', 'submit']) {
    const before = await page.evaluate(() => {
      const fixture = window.__qa;
      document.activeElement?.blur();
      fixture.holdPresentationRead = true;
      const source = document.querySelector('#source-text');
      source.value = 'QA source before delayed focus validation';
      source.dispatchEvent(new Event('input', { bubbles: true }));
      const before = { waits: fixture.presentationReadWaits, focuses: fixture.sourceFocusCalls };
      fixture.emitInputFocus();
      return before;
    });
    await page.waitForFunction((waits) => window.__qa.presentationReadWaits > waits, before.waits);
    if (superseding === 'selection-epoch') await page.evaluate(() => { window.__qa.nativeHide(); window.__qa.nativeShow(); });
    else if (superseding === 'edit') await page.evaluate(() => {
      const source = document.querySelector('#source-text');
      source.value = 'QA edit before delayed focus validation';
      source.dispatchEvent(new Event('input', { bubbles: true }));
    });
    else if (superseding === 'submit') await page.locator('#translate-button').click();
    else await goView('settings');
    await page.evaluate(() => { window.__qa.holdPresentationRead = false; window.__qa.releasePresentationRead(); });
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), before.focuses, `delayed focus validation focused after ${superseding}`);
    await goView('translate');
  }
  const hiddenInput = await page.evaluate(() => {
    const fixture = window.__qa, hidden = fixture.nativeHide();
    const before = { epoch: hidden.epoch, focuses: fixture.sourceFocusCalls };
    fixture.emit('source-text', { text: '', mode: 'input', focusInput: true, presentationEpoch: hidden.epoch });
    return before;
  });
  await page.waitForFunction((before) => window.__qa.sourceFocusCalls === before.focuses + 1
    && window.__qa.presentation.epoch > before.epoch && document.activeElement.id === 'source-text', hiddenInput);
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  await page.waitForFunction(() => document.activeElement.id !== 'source-text');
  // Padding belongs to the button's hit area, and must never start a drag.
  const pinDragCalls = await page.evaluate(() => window.__qa.dragCalls);
  await pin.click({ position: { x: 3, y: 3 } });
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'true');
  assert.equal(await pin.getAttribute('aria-label'), '取消钉住');
  assert.equal(await page.evaluate(() => window.__qa.dragCalls), pinDragCalls);
  assert.equal(await pin.evaluate((element) => getComputedStyle(element).backgroundColor), 'rgba(0, 0, 0, 0)');
  assert.equal(await page.locator('#toast').isHidden(), true);
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  assert.equal(await page.evaluate(() => document.activeElement.id), '');
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await page.evaluate(() => window.__qa.pinRequests), [true]);
  assert.equal(await pin.locator('svg').evaluate((element) => getComputedStyle(element).transform), 'none');
  assert.notEqual(await pin.locator('svg').evaluate((element) => getComputedStyle(element).fill), 'none');
  await page.locator('.app-shell').screenshot({ path: 'test-results/quiet-pin-blank.png' });
  await pin.press('Space');
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'false');
  assert.equal(await pin.evaluate((element) => element.matches(':focus-visible')), true);
  assert.equal(await pin.getAttribute('aria-label'), '钉住窗口');
  assert.deepEqual(await page.evaluate(() => window.__qa.pinRequests), [true, false]);
  assert.equal(await page.locator('#toast').isHidden(), true);

  // Hitting the icon itself also reaches pinning without entering drag mode.
  await pin.locator('svg').click();
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'true');
  await pin.locator('svg').click();
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'false');
  assert.deepEqual(await page.evaluate(() => window.__qa.pinRequests), [true, false, true, false]);
  assert.equal(await page.evaluate(() => window.__qa.dragCalls), pinDragCalls);
  assert.equal(await page.locator('#toast').isHidden(), true);

  assert.equal(await page.locator('.popup-toolbar').getAttribute('data-window-drag'), null);
  assert.equal(await page.locator('.popup-drag-space').getAttribute('data-window-drag'), '');
  assert.equal(await page.locator('.popup-toolbar').getAttribute('data-tauri-drag-region'), null);
  await page.locator('.popup-drag-space').click();
  assert.equal(await page.evaluate(() => window.__qa.dragCalls), pinDragCalls + 1);
  assert.deepEqual(await page.evaluate(() => window.__qa.resizeRequests), []);
  assert.deepEqual(await page.evaluate(() => window.__qa.nativeResizeRequests), []);
  // The actual macOS tao backend has no native drag-resize implementation.
  // Thin edges capture the pointer and send only bounded width/epoch requests.
  await page.setViewportSize({ width: 680, height: 820 });
  await page.waitForFunction(() => window.__qa.layoutCalls.at(-1)?.contentWidth === 680);
  const geometryBaseline = await page.evaluate(() => ({ height: window.__qa.layoutCalls.at(-1).contentHeight,
    shows: window.__qa.showCalls.length, hides: window.__qa.hideCalls, drags: window.__qa.dragCalls,
    source: document.querySelector('#source-text').value, pins: window.__qa.pinRequests.length }));
  const westEdge = page.locator('[data-window-resize="west"]'), eastEdge = page.locator('[data-window-resize="east"]');
  for (const edge of [westEdge, eastEdge]) {
    assert.equal(await edge.isVisible(), true);
    assert.equal(await edge.getAttribute('aria-hidden'), 'true');
    assert.equal(await edge.getAttribute('tabindex'), null);
    assert.equal(await edge.getAttribute('title'), '拖动调整窗口宽度');
    assert.equal(await edge.evaluate((element) => getComputedStyle(element).cursor), 'ew-resize');
    assert.equal((await edge.boundingBox()).width, 10);
  }
  assert.deepEqual(await page.evaluate(() => ['pin-button', 'more-toggle', 'close-popup'].map(id => {
    const button = document.getElementById(id), bounds = button.getBoundingClientRect();
    const hit = document.elementFromPoint(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
    return { id, buttonReceivesCenter: hit?.closest('button') === button, coveredByResizeEdge: Boolean(hit?.closest('[data-window-resize]')) };
  })), ['pin-button', 'more-toggle', 'close-popup'].map(id => ({ id, buttonReceivesCenter: true, coveredByResizeEdge: false })));
  for (const [edge, movement, expected, direction] of [[eastEdge, -80, 600, 'east'], [westEdge, 75, 605, 'west']]) {
    const bounds = await edge.boundingBox(), count = await page.evaluate(() => window.__qa.resizeRequests.length);
    await page.mouse.move(bounds.x + 2, 45); await page.mouse.down();
    await page.mouse.move(bounds.x + 2 + movement, 45, { steps: 4 }); await page.mouse.up();
    await page.waitForFunction(({ count, width }) => window.__qa.resizeRequests.length > count && window.__qa.resizeRequests.at(-1).width === width, { count, width: expected });
    assert.equal(await page.evaluate(() => window.__qa.resizeRequests.at(-1).direction), direction);
    assert.equal(await page.evaluate(() => window.__qa.resizeRequests.at(-1).presentationEpoch === window.__qa.presentation.epoch), true);
    assert.equal(await page.locator('body').evaluate((element) => element.classList.contains('popup-resizing')), false);
  }
  assert.deepEqual(await page.evaluate(() => window.__qa.nativeResizeRequests), []);
  assert.equal(await page.evaluate(() => window.__qa.dragCalls), geometryBaseline.drags);
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), geometryBaseline.shows);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), geometryBaseline.hides);
  assert.equal(await page.locator('#source-text').inputValue(), geometryBaseline.source);
  assert.equal(await page.evaluate(() => window.__qa.pinRequests.length), geometryBaseline.pins);
  await page.setViewportSize({ width: 850, height: 820 });
  await page.waitForFunction(() => window.__qa.layoutCalls.at(-1)?.contentWidth === 850);
  assert.equal(await page.evaluate(() => window.__qa.layoutCalls.at(-1).contentHeight), geometryBaseline.height);
  await page.locator('#source-text').fill(Array(5).fill('A later height fit must retain the actual 850 pixel viewport width.').join('\n'));
  await page.waitForFunction((height) => window.__qa.layoutCalls.at(-1)?.contentWidth === 850 && window.__qa.layoutCalls.at(-1).contentHeight > height, geometryBaseline.height);
  assert.deepEqual(await page.evaluate(() => Object.keys(window.__qa.layoutCalls.at(-1)).sort()), ['contentHeight', 'contentWidth', 'presentation']);
  await page.locator('#source-text').fill('');
  // Hiding while one width IPC is pending discards the coalesced follow-up.
  const beforeHiddenResize = await page.evaluate(() => { window.__qa.holdResize = true; return window.__qa.resizeRequests.length; });
  await page.mouse.move(848, 45); await page.mouse.down(); await page.mouse.move(810, 45);
  await page.waitForFunction((count) => window.__qa.resizeRequests.length > count, beforeHiddenResize);
  await page.mouse.move(790, 45);
  await page.evaluate(() => { window.__qa.nativeHide(); window.__qa.holdResize = false; window.__qa.releaseResize(); });
  await page.mouse.move(770, 45); await page.mouse.up();
  assert.equal(await page.evaluate(() => window.__qa.resizeRequests.length), beforeHiddenResize + 1);
  assert.equal(await page.locator('body').evaluate((element) => element.classList.contains('popup-resizing')), false);
  await page.evaluate(() => window.__qa.nativeShow());
  const beforeChangedEpoch = await page.evaluate(() => window.__qa.resizeRequests.length);
  await page.mouse.move(848, 45); await page.mouse.down();
  await page.evaluate(() => { window.__qa.presentation.epoch++; window.__qa.emit('translation-presentation', structuredClone(window.__qa.presentation)); });
  await page.mouse.move(800, 45); await page.mouse.up();
  assert.equal(await page.evaluate(() => window.__qa.resizeRequests.length), beforeChangedEpoch);
  // Windows uses its native resize API; this fixture only verifies dispatch.
  await page.evaluate(() => Object.defineProperty(navigator, 'platform', { configurable: true, get: () => 'Win32' }));
  await eastEdge.click({ position: { x: 2, y: 45 } });
  assert.deepEqual(await page.evaluate(() => window.__qa.nativeResizeRequests.at(-1)), { direction: 'east', presentationEpoch: await page.evaluate(() => window.__qa.presentation.epoch) });
  await page.evaluate(() => Object.defineProperty(navigator, 'platform', { configurable: true, get: () => 'MacIntel' }));
  await page.setViewportSize({ width: 800, height: 820 });
  await page.locator('#more-toggle').click();
  await page.locator('#popup-more-menu').waitFor({ state: 'visible' });
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('#popup-more-menu').isHidden(), true);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), 0);
  await page.locator('#source-text').fill(Array(30).fill('A line for automatic height.').join('\n'));
  const tallSourceShell = await page.locator('.app-shell').evaluate((element) => element.getBoundingClientRect().height);
  // The editor grows past one line for a long selection, then stops at 180px and scrolls.
  assert.ok(await page.locator('#source-text').evaluate((element) => {
    const height = element.getBoundingClientRect().height;
    return height > 100 && height <= 180;
  }));
  assert.equal(await page.locator('#translate-button').isEnabled(), true);
  await page.locator('#source-text').fill('');
  assert.ok(await page.locator('.app-shell').evaluate((element, tall) => element.getBoundingClientRect().height < tall - 40, tallSourceShell));
  assert.ok(await page.locator('#source-text').evaluate((element) => element.getBoundingClientRect().height >= 44));

  // A blocked screenshot is an atomic source event: its persistent guidance is
  // prepared before the native popup is shown. Receiving it is always passive.
  await page.clock.install();
  const emitPermissionCapture = () => page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input', presentationEpoch: window.__qa.presentation.epoch, permissionRequired: 'screenCapture' }));
  const beforePermission = await page.evaluate(() => ({ shows: window.__qa.showCalls.length, requests: window.__qa.translationRequests.length }));
  await page.locator('#pin-button').focus();
  await emitPermissionCapture();
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  await page.waitForFunction((shows) => window.__qa.showCalls.length === shows + 1, beforePermission.shows);
  assert.match(await page.locator('#permission-guidance-title').textContent(), /截图.*屏幕录制权限/);
  assert.equal(await page.evaluate(() => window.__qa.permissionAtShow.at(-1).visible), true);
  assert.equal(await page.evaluate(() => window.__qa.permissionAtShow.at(-1).layout.presentation), 'popup');
  assert.equal(await page.evaluate(() => document.activeElement.id), '');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforePermission.requests);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionSettings), []);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);
  await page.clock.fastForward(8_100);
  assert.equal(await page.locator('#permission-guidance').isVisible(), true);
  assert.equal(await page.locator('#toast').isHidden(), true);

  // The direct link opens only the correct pane on a click. Failure keeps a
  // usable manual path visible beyond the old toast timeout, without raw IPC data.
  await page.evaluate(() => { window.__qa.failPermissionSettings = true; });
  await page.locator('#permission-guidance-open').click();
  await page.locator('#permission-guidance-error').getByText('未能打开系统设置。', { exact: false }).waitFor();
  assert.match(await page.locator('#permission-guidance-error').textContent(), /系统设置 → 隐私与安全（性）.*屏幕录制/);
  assert.doesNotMatch(await page.locator('#permission-guidance-error').textContent(), /QA internal/);
  await page.clock.fastForward(8_100);
  assert.equal(await page.locator('#permission-guidance-error').isVisible(), true);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionSettings), ['screenCapture']);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);

  // Capture only the isolated fixture: light/narrow/dark screenshots include no
  // desktop contents, credentials or live API output. Both actions fit at the
  // supported minimum popup width of 420 px.
  await page.locator('.app-shell').screenshot({ path: 'test-results/permission-light-800.png' });
  await page.setViewportSize({ width: 420, height: 600 });
  const guidanceBounds = await page.locator('#permission-guidance').boundingBox();
  for (const id of ['#permission-guidance-open', '#permission-guidance-help']) {
    const bounds = await page.locator(id).boundingBox();
    assert.ok(bounds.x >= guidanceBounds.x && bounds.x + bounds.width <= guidanceBounds.x + guidanceBounds.width + 1, `${id} fits within narrow guidance`);
  }
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.locator('.app-shell').screenshot({ path: 'test-results/permission-narrow-420.png' });
  await page.evaluate(() => { document.documentElement.dataset.theme = 'dark'; });
  await page.locator('.app-shell').screenshot({ path: 'test-results/permission-dark-420.png' });
  await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
  await page.setViewportSize({ width: 800, height: 820 });

  // A first visit to the help still exposes and focuses the steps when opening
  // System Settings is pending. No authorization is requested by either action.
  assert.equal(await page.locator('#mac-permission-card').isHidden(), true);
  await page.evaluate(() => { window.__qa.failPermissionSettings = false; window.__qa.holdPermissionSettings = true; });
  await page.locator('#permission-guidance-open').click();
  await page.waitForFunction(() => window.__qa.permissionSettings.length === 2);
  assert.equal(await page.locator('#permission-guidance-open').isDisabled(), true);
  await page.locator('#permission-guidance-help').click();
  await page.locator('#mac-permission-card').waitFor({ state: 'visible' });

  await page.waitForFunction(() => document.activeElement.id === 'mac-permission-card');
  assert.equal(await page.locator('body').getAttribute('data-view'), 'settings');
  assert.equal(await page.locator('#permission-setup-steps').getAttribute('open'), '');
  assert.equal(await page.locator('#permission-setup-steps li').count(), 4);
  assert.match(await page.locator('#permission-setup-steps').textContent(), /EchoLingo\.app/);
  assert.match(await page.locator('#permission-setup-steps').textContent(), /重新打开.*刷新状态/);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);
  await page.evaluate(() => { window.__qa.holdPermissionSettings = false; window.__qa.releasePermissionSettings(); });
  await page.waitForFunction(() => !document.querySelector('[data-open-permission="screenCapture"]').disabled);
  await goView('translate');
  assert.equal(await page.locator('#permission-guidance').isVisible(), true);
  assert.equal(await page.locator('#permission-guidance-error').isHidden(), true);
  await page.locator('#permission-guidance-dismiss').click();
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  await emitPermissionCapture();
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  await page.locator('#source-text').fill('QA manual input after denied capture');
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);

  // Empty selection and Alt+A recover quietly. Obsolete capture events cannot
  // expose a guide or replace text after a newer native presentation wins.
  await emitPermissionCapture();
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input', presentationEpoch: window.__qa.presentation.epoch }));
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  await emitPermissionCapture();
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  await page.evaluate(() => window.__qa.emitInputFocus());
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  const beforeStalePermission = await page.evaluate(() => {
    const epoch = window.__qa.presentation.epoch;
    window.__qa.nativeHide(); window.__qa.nativeShow();
    return { epoch, shows: window.__qa.showCalls.length };
  });
  await page.locator('#source-text').fill('QA newer input survives old permission capture');
  await page.evaluate(({ epoch }) => window.__qa.emit('source-text', { text: '', mode: 'input', presentationEpoch: epoch, permissionRequired: 'screenCapture' }), beforeStalePermission);
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA newer input survives old permission capture');
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), beforeStalePermission.shows);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionSettings), ['screenCapture', 'screenCapture']);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);
  await page.locator('#source-text').fill('');
  await goView('history');
  assert.equal(await page.locator('.management-header').isVisible(), true);
  await goView('settings');
  assert.equal(await westEdge.isVisible(), true);
  assert.equal(await eastEdge.isVisible(), true);
  const managementResizeCount = await page.evaluate(() => window.__qa.resizeRequests.length);
  await eastEdge.dispatchEvent('pointerdown', { button: 0, pointerId: 110, screenX: 798 });
  await eastEdge.dispatchEvent('pointermove', { pointerId: 110, screenX: 700 });
  await eastEdge.dispatchEvent('pointerup', { pointerId: 110, screenX: 700 });
  assert.equal(await page.evaluate(() => window.__qa.resizeRequests.length), managementResizeCount);

  // Permission reads are passive, and only explicit management actions request
  // authorization or open a system pane. Unsupported platforms show no Mac UI.
  await page.locator('#accessibility-permission-state').getByText('待授权').waitFor();
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);
  const readsBeforeRefresh = await page.evaluate(() => window.__qa.permissionReads);
  await page.locator('#refresh-permissions').click();
  await page.waitForFunction((reads) => window.__qa.permissionReads > reads, readsBeforeRefresh);
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), []);
  await page.locator('[data-request-permission="accessibility"]').click();
  await page.locator('#accessibility-permission-state').getByText('已授权').waitFor();
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), ['accessibility']);
  const settingsBeforeExplicitOpen = await page.evaluate(() => window.__qa.permissionSettings.length);
  await page.locator('[data-open-permission="screenCapture"]').click();
  assert.equal(await page.evaluate(() => window.__qa.permissionSettings.length), settingsBeforeExplicitOpen + 1);
  assert.equal(await page.evaluate(() => window.__qa.permissionSettings.at(-1)), 'screenCapture');
  assert.deepEqual(await page.evaluate(() => window.__qa.permissionRequests), ['accessibility']);
  await page.evaluate(() => { window.__qa.permissionState.platform = 'windows'; window.__qa.permissionState.supported = false; });
  await page.locator('#refresh-permissions').click();
  await page.locator('#mac-permission-card').waitFor({ state: 'hidden' });
  await page.evaluate(() => { window.__qa.permissionState.platform = 'macos'; window.__qa.permissionState.supported = true; });
  await goView('translate'); await goView('settings');
  await page.locator('#mac-permission-card').waitFor({ state: 'visible' });

  // A verified modern request may contradict the old passive preflight. Do
  // not incorrectly tell the owner the system switch was never enabled.
  await page.evaluate(() => { window.__qa.permissionOverride = { ...window.__qa.permissionState, screenCaptureGranted: false, screenCaptureState: 'inconsistent', screenCaptureRequestState: 'available', screenCaptureAuthorizationConsistent: false }; });
  await page.locator('[data-request-permission="screenCapture"]').click();
  await page.locator('#screen-capture-permission-state').getByText('授权状态不一致').waitFor();
  assert.match(await page.locator('#permission-context').textContent(), /不一致.*重新打开/);
  await page.evaluate(() => { window.__qa.permissionOverride = null; });
  await page.locator('#refresh-permissions').click();

  // Missing selection permission is distinct from an ordinary empty selection.
  // Use production delivery IDs/ACKs and a fresh native epoch for every action.
  await goView('translate');
  await page.evaluate(() => { window.__qa.permissionState.accessibilityGranted = false; });
  await pin.click();
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'true');
  const selectionPermissionBaseline = await page.evaluate(() => ({
    opens: window.__qa.permissionSettings.length, authorizations: window.__qa.permissionRequests.length,
    shows: window.__qa.showCalls.length, translations: window.__qa.translationRequests.length,
  }));
  const emitSelectionDelivery = (deliveryId, payload) => page.evaluate(({ deliveryId, payload }) => {
    const fixture = window.__qa;
    const presentation = fixture.pinned && fixture.nativeVisible && fixture.presentation.presented
      ? fixture.nativePinnedCaptureStart() : fixture.nativeHide();
    fixture.pendingSource = { deliveryId, presentationEpoch: presentation.epoch, ...payload };
    fixture.emit('source-text', structuredClone(fixture.pendingSource));
  }, { deliveryId, payload });
  await emitSelectionDelivery(500, { text: '', mode: 'input', focusInput: true, permissionRequired: 'accessibility' });
  await page.waitForFunction(() => window.__qa.sourceAcks.includes(500));
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  assert.match(await page.locator('#permission-guidance-title').textContent(), /划词.*辅助功能权限/);
  assert.match(await page.locator('#permission-guidance-description').textContent(), /系统设置 → 隐私与安全 → 辅助功能/);
  assert.equal(await page.evaluate(() => window.__qa.permissionAtShow.at(-1).visible), true);
  assert.match(await page.evaluate(() => window.__qa.permissionAtShow.at(-1).title), /辅助功能权限/);
  assert.equal(await page.evaluate(() => document.activeElement.id), 'source-text');
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), selectionPermissionBaseline.shows + 1);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), selectionPermissionBaseline.translations);
  assert.equal(await page.evaluate(() => window.__qa.permissionSettings.length), selectionPermissionBaseline.opens);
  assert.equal(await page.evaluate(() => window.__qa.permissionRequests.length), selectionPermissionBaseline.authorizations);
  await page.clock.fastForward(8_100);
  assert.equal(await page.locator('#permission-guidance').isVisible(), true);
  assert.equal(await page.locator('#toast').isHidden(), true);

  await page.setViewportSize({ width: 420, height: 600 });
  const accessibilityGuidanceBounds = await page.locator('#permission-guidance').boundingBox();
  for (const id of ['#permission-guidance-open', '#permission-guidance-help']) {
    const bounds = await page.locator(id).boundingBox();
    assert.ok(bounds.x >= accessibilityGuidanceBounds.x
      && bounds.x + bounds.width <= accessibilityGuidanceBounds.x + accessibilityGuidanceBounds.width + 1);
  }
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.locator('.app-shell').screenshot({ path: 'test-results/accessibility-permission-narrow-420.png' });
  await page.setViewportSize({ width: 800, height: 820 });

  // Only this explicit click opens the accessibility pane; it never invokes
  // request_permission. The help action stays inside the application's guide.
  await page.locator('#permission-guidance-open').click();
  await page.waitForFunction((count) => window.__qa.permissionSettings.length === count + 1, selectionPermissionBaseline.opens);
  assert.equal(await page.evaluate(() => window.__qa.permissionSettings.at(-1)), 'accessibility');
  assert.equal(await page.evaluate(() => window.__qa.permissionRequests.length), selectionPermissionBaseline.authorizations);
  await page.locator('#permission-guidance-help').click();
  await page.waitForFunction(() => document.activeElement.id === 'mac-permission-card');
  assert.equal(await page.locator('body').getAttribute('data-view'), 'settings');
  assert.equal(await page.locator('#permission-setup-steps').getAttribute('open'), '');
  assert.equal(await page.evaluate(() => window.__qa.permissionSettings.length), selectionPermissionBaseline.opens + 1);
  await page.evaluate(() => { window.__qa.permissionState.accessibilityGranted = true; });
  await page.locator('#refresh-permissions').click();
  await page.locator('#accessibility-permission-state').getByText('已授权').waitFor();
  assert.equal(await page.locator('#permission-guidance').evaluate(element => element.hidden), true);
  assert.equal(await page.evaluate(() => window.__qa.permissionRequests.length), selectionPermissionBaseline.authorizations);
  await goView('translate');

  // A subsequent successful selection removes obsolete guidance and translates
  // normally, while a late permission failure cannot replace newer user input.
  await emitSelectionDelivery(501, { text: '', mode: 'input', focusInput: true, permissionRequired: 'accessibility' });
  await page.waitForFunction(() => window.__qa.sourceAcks.includes(501));
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  await emitSelectionDelivery(502, { text: 'QA selected source after accessibility recovery', mode: 'translate' });
  await page.waitForFunction(() => window.__qa.sourceAcks.includes(502));
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), 'QA selected source after accessibility recovery');
  const staleSelectionPermission = await page.evaluate(() => {
    const epoch = window.__qa.presentation.epoch;
    window.__qa.nativeHide(); window.__qa.nativeShow();
    return { epoch, shows: window.__qa.showCalls.length };
  });
  await page.locator('#source-text').fill('QA newer input survives old accessibility failure');
  await page.evaluate(({ epoch }) => {
    const payload = { deliveryId: 503, text: '', mode: 'input', focusInput: true, presentationEpoch: epoch, permissionRequired: 'accessibility' };
    window.__qa.pendingSource = payload; window.__qa.emit('source-text', payload);
  }, staleSelectionPermission);
  await page.waitForFunction(() => window.__qa.sourceAcks.includes(503));
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA newer input survives old accessibility failure');
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), staleSelectionPermission.shows);
  // The same native epoch is also obsolete after an edit. This isolates the
  // delivery intent guard from the old-epoch rejection above.
  await page.evaluate(() => {
    const fixture = window.__qa;
    const payload = { deliveryId: 504, text: '', mode: 'input', focusInput: true,
      presentationEpoch: fixture.presentation.epoch, permissionRequired: 'accessibility' };
    fixture.pendingSource = payload; fixture.emit('source-text', payload);
  });
  await page.waitForFunction(() => window.__qa.sourceAcks.includes(504));
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA newer input survives old accessibility failure');
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), staleSelectionPermission.shows);
  await emitSelectionDelivery(505, { text: '', mode: 'input', focusInput: true });
  await page.waitForFunction(() => window.__qa.sourceAcks.includes(505) && document.activeElement.id === 'source-text');
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  assert.equal(await page.locator('#toast').isHidden(), true);
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => window.__qa.permissionSettings.length), selectionPermissionBaseline.opens + 1);
  assert.equal(await page.evaluate(() => window.__qa.permissionRequests.length), selectionPermissionBaseline.authorizations);
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  await pin.click();
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'false');
  console.log('PASS: missing Accessibility is actionable before first popup, opens only the clicked permission pane, never requests authorization automatically, and clears on refresh/new selection; late failures and ordinary empty selections stay quiet. Fake IPC only.');
  await goView('settings');

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
  // The outer 10px corners are resize handles even while a settings modal
  // is open. Click the actual backdrop padding, with an explicit hit test.
  assert.equal(await page.locator('#provider-dialog').evaluate(element => {
    const bounds = element.getBoundingClientRect();
    return document.elementFromPoint(bounds.left + 2, bounds.top + 2)?.closest('[data-window-resize]')?.getAttribute('data-window-resize');
  }), 'north-west');
  assert.equal(await page.locator('#provider-dialog').evaluate(element => {
    const bounds = element.getBoundingClientRect();
    return document.elementFromPoint(bounds.left + 16, bounds.top + 16) === element;
  }), true, 'The atomic-save dismissal check must target the real backdrop, not a resize handle or form control.');
  await page.locator('#provider-dialog').click({ position: { x: 16, y: 16 } });
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

  // Recorder uses an acknowledged bounded native lease; these assertions exercise
  // the frontend/fake IPC only, not OS-wide shortcut registration.
  assert.equal(await page.locator('[data-shortcut-record]').count(), 2);
  const beforeRecordedSave = await page.evaluate(() => window.__qa.saveCalls);
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === true);
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.down('Control'); await page.keyboard.down('Shift'); await page.keyboard.down('t');
  assert.equal(await page.locator('input[name="selection"]').inputValue(), 'Alt+D');
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeRecordedSave);
  await page.keyboard.up('t'); await page.keyboard.up('Shift'); await page.keyboard.up('Control');
  await page.waitForFunction(() => document.querySelector('input[name="selection"]').value === 'Ctrl+Shift+T');
  assert.equal(await page.evaluate(() => window.__qa.shortcutLeases.at(-1).active), false);
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === 'Ctrl+Shift+T');
  await page.locator('#shortcut-feedback').getByText('快捷键已保存并立即生效', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeRecordedSave + 1);
  assert.deepEqual(await page.evaluate(() => window.__qa.shortcutRetryActions.at(-1)), ['selection']);
  // Editing one or several rows must not explicitly retry an unrelated
  // inactive registration. An unchanged explicit save remains a retry intent.
  const beforeManualRows = await page.evaluate(() => {
    window.__qa.unavailableShortcutActions = ['input'];
    return { saves: window.__qa.saveCalls, shortcuts: structuredClone(window.__qa.settings.shortcuts) };
  });
  await page.locator('#shortcut-selection').fill('Ctrl+Shift+K');
  await page.locator('#save-shortcuts').click();
  await page.waitForFunction((count) => window.__qa.saveCalls === count + 1 && !document.querySelector('#save-shortcuts').disabled, beforeManualRows.saves);
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.selection), 'Ctrl+Shift+K');
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.input), beforeManualRows.shortcuts.input);
  assert.deepEqual(await page.evaluate(() => window.__qa.shortcutRetryActions.at(-1)), ['selection']);
  await page.locator('#shortcut-selection').fill('Ctrl+Shift+J');
  await page.locator('#shortcut-silentOcr').fill('Ctrl+Shift+P');
  await page.locator('#save-shortcuts').click();
  await page.waitForFunction((count) => window.__qa.saveCalls === count + 2 && !document.querySelector('#save-shortcuts').disabled, beforeManualRows.saves);
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.selection), 'Ctrl+Shift+J');
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.silentOcr), 'Ctrl+Shift+P');
  assert.deepEqual(await page.evaluate(() => window.__qa.shortcutRetryActions.at(-1)), ['selection', 'silentOcr']);
  await page.locator('#shortcut-selection').fill(beforeManualRows.shortcuts.selection);
  await page.locator('#shortcut-silentOcr').fill(beforeManualRows.shortcuts.silentOcr);
  await page.locator('#save-shortcuts').click();
  await page.waitForFunction((count) => window.__qa.saveCalls === count + 3 && !document.querySelector('#save-shortcuts').disabled, beforeManualRows.saves);
  assert.deepEqual(await page.evaluate(() => window.__qa.settings.shortcuts), beforeManualRows.shortcuts);
  assert.deepEqual(await page.evaluate(() => window.__qa.shortcutRetryActions.at(-1)), ['selection', 'silentOcr']);
  await page.locator('#save-shortcuts').click();
  await page.locator('#shortcut-feedback').getByText('QA unavailable shortcut: input', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeManualRows.saves + 4);
  assert.deepEqual(await page.evaluate(() => window.__qa.settings.shortcuts), beforeManualRows.shortcuts);
  assert.deepEqual(await page.evaluate(() => window.__qa.shortcutRetryActions.at(-1)), ['selection', 'silentOcr', 'capture', 'ocr', 'input']);
  await page.evaluate(() => { window.__qa.unavailableShortcutActions = []; });
  await page.locator('#shortcut-selection').fill('Control+Shift+t');
  await page.locator('#save-shortcuts').click();
  await page.waitForFunction((count) => window.__qa.saveCalls === count + 5 && !document.querySelector('#save-shortcuts').disabled, beforeManualRows.saves);
  assert.deepEqual(await page.evaluate(() => window.__qa.settings.shortcuts), beforeManualRows.shortcuts);
  assert.deepEqual(await page.evaluate(() => window.__qa.shortcutRetryActions.at(-1)), ['selection', 'silentOcr', 'capture', 'ocr', 'input']);
  // A backend registration/save rejection must retain both the committed
  // binding and the editable candidate; it must not claim success.
  await page.locator('input[name="selection"]').fill('Ctrl+Shift+K');
  await page.evaluate(() => { window.__qa.failSave = true; });
  await page.locator('#save-shortcuts').click();
  await page.locator('#shortcut-feedback').getByText('QA save failure', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.selection), 'Ctrl+Shift+T');
  assert.equal(await page.locator('input[name="selection"]').inputValue(), 'Ctrl+Shift+K');
  assert.equal(await page.locator('#save-shortcuts').isEnabled(), true);
  await page.evaluate(() => { window.__qa.failSave = false; });
  // A recorded field saves automatically once, without committing unrelated
  // manual drafts or requiring them to be syntactically valid.
  await page.locator('#shortcut-advanced > summary').click();
  const savedOcr = await page.evaluate(() => window.__qa.settings.shortcuts.silentOcr);
  const savedCapture = await page.evaluate(() => window.__qa.settings.shortcuts.capture);
  await page.locator('#shortcut-silentOcr').fill('Ctrl+Shift+L');
  await page.locator('#shortcut-capture').fill('Unfinished manual draft');
  const beforeFieldOnlySave = await page.evaluate(() => window.__qa.saveCalls);
  await page.evaluate(() => { window.__qa.holdSave = true; });
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Control+Shift+j');
  await page.waitForFunction((count) => window.__qa.saveCalls === count + 1, beforeFieldOnlySave);
  assert.equal(await page.locator('#save-shortcuts').isDisabled(), true);
  assert.equal(await page.locator('#shortcut-silentOcr').getAttribute('readonly'), '');
  // A duplicate delivery for the completed lease cannot submit another save.
  await page.evaluate(() => window.__qa.emit('shortcut-recorded', { leaseId: window.__qa.shortcutLeases.at(-1).id, shortcut: 'Ctrl+Shift+J', modifiersDown: 0 }));
  await page.evaluate(() => { window.__qa.holdSave = false; window.__qa.releaseSave(); });
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === 'Ctrl+Shift+J');
  await page.locator('#shortcut-feedback').getByText('其他手动修改仍待保存', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeFieldOnlySave + 1);
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.silentOcr), savedOcr);
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.capture), savedCapture);
  assert.equal(await page.locator('#shortcut-silentOcr').inputValue(), 'Ctrl+Shift+L');
  assert.equal(await page.locator('#shortcut-capture').inputValue(), 'Unfinished manual draft');
  await page.locator('#shortcut-silentOcr').fill(savedOcr);
  await page.locator('#shortcut-capture').fill(savedCapture);
  await page.locator('#shortcut-advanced > summary').click();
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Control+Shift+t');
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === 'Ctrl+Shift+T');
  // Backend conflict/save rejection keeps the old committed binding and the
  // new editable recorded candidate; no second attempt occurs automatically.
  const beforeAutomaticFailure = await page.evaluate(() => window.__qa.saveCalls);
  await page.evaluate(() => { window.__qa.failSave = true; });
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Control+Shift+k');
  await page.locator('#shortcut-feedback').getByText('QA save failure', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.selection), 'Ctrl+Shift+T');
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+K');
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeAutomaticFailure + 1);
  assert.equal(await page.locator('#save-shortcuts').isEnabled(), true);
  await page.evaluate(() => { window.__qa.failSave = false; });
  // A preference save must not erase a shortcut draft.
  await page.locator('input[name="selection"]').fill('Ctrl+Shift+Y');
  await page.locator('#theme-select').selectOption('dark');
  await page.waitForFunction(() => window.__qa.settings.theme === 'dark');
  assert.equal(await page.locator('input[name="selection"]').inputValue(), 'Ctrl+Shift+Y');
  const hideBeforeCancel = await page.evaluate(() => window.__qa.hideCalls);
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === false);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), hideBeforeCancel);
  assert.equal(await page.locator('input[name="selection"]').inputValue(), 'Ctrl+Shift+Y');
  await page.locator('[data-shortcut-record="silentOcr"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.locator('input[name="silentOcr"]').dispatchEvent('keydown', { key: 'Process', code: 'KeyS', keyCode: 229, isComposing: true });
  await page.locator('#shortcut-feedback').getByText('请先结束输入法组合', { exact: false }).waitFor();
  await page.locator('input[name="silentOcr"]').dispatchEvent('keyup', { key: 'Process', code: 'KeyS', keyCode: 229, isComposing: true });
  assert.equal(await page.locator('input[name="silentOcr"]').inputValue(), 'Alt+C');
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === false);
  // A delayed end ACK cannot commit a candidate after navigation cancels it.
  const beforeCancelledEnd = await page.evaluate(() => window.__qa.saveCalls);
  await page.evaluate(() => { window.__qa.holdShortcutEnd = true; });
  await page.locator('[data-shortcut-record="silentOcr"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Control+Shift+r');
  await page.waitForFunction(() => window.__qa.shortcutEndWaits === 1);
  await page.getByRole('button', { name: '返回翻译', exact: true }).click();
  await page.evaluate(() => { window.__qa.holdShortcutEnd = false; window.__qa.releaseShortcutEnd(); });
  await page.locator('#more-toggle').click(); await page.locator('button[data-view="settings"]').click();
  assert.equal(await page.locator('input[name="silentOcr"]').inputValue(), 'Alt+C');
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeCancelledEnd);
  // An automatic save queued behind a preference write is cancelled before
  // its IPC call when settings closes; it must not overwrite newer state.
  const beforeQueuedRecording = await page.evaluate(() => window.__qa.saveCalls);
  await page.evaluate(() => { window.__qa.holdSave = true; });
  await page.locator('#theme-select').selectOption('light');
  await page.waitForFunction((count) => window.__qa.saveCalls === count + 1, beforeQueuedRecording);
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Control+Shift+n');
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === false && document.querySelector('#shortcut-feedback').textContent.startsWith('正在自动保存'));
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeQueuedRecording + 1);
  await page.getByRole('button', { name: '返回翻译', exact: true }).click();
  await page.evaluate(() => { window.__qa.holdSave = false; window.__qa.releaseSave(); });
  await page.waitForFunction(() => window.__qa.settings.theme === 'light');
  await page.locator('#more-toggle').click(); await page.locator('button[data-view="settings"]').click();
  await page.waitForFunction(() => !document.querySelector('#save-shortcuts').disabled);
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.selection), 'Ctrl+Shift+T');
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeQueuedRecording + 1);
  assert.doesNotMatch(await page.locator('#shortcut-feedback').textContent(), /正在自动保存|SHORTCUT_SAVE_CANCELLED/);
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+N');
  // A preceding preference save can return bindings changed independently by
  // the backend. The queued recording cannot overwrite that newer snapshot.
  const beforeChangedBindings = await page.evaluate(() => window.__qa.saveCalls);
  await page.evaluate(() => { window.__qa.holdSave = true; });
  await page.locator('#theme-select').selectOption('dark');
  await page.waitForFunction((count) => window.__qa.saveCalls === count + 1, beforeChangedBindings);
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Control+Shift+m');
  await page.waitForFunction(() => document.querySelector('#shortcut-feedback').textContent.startsWith('正在自动保存'));
  await page.evaluate(() => {
    window.__qa.holdSave = false; window.__qa.releaseSave();
    // Run after the held save publishes its mock state, before get_settings
    // returns that state to the real frontend's serialized save queue.
    queueMicrotask(() => { window.__qa.settings.shortcuts.selection = 'Ctrl+Shift+U'; });
  });
  await page.waitForFunction(() => !document.querySelector('#save-shortcuts').disabled && window.__qa.settings.shortcuts.selection === 'Ctrl+Shift+U');
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeChangedBindings + 1);
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+M');
  await page.locator('#shortcut-feedback').getByText('录制的输入尚未保存', { exact: false }).waitFor();
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.keyboard.press('Control+Shift+t');
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === 'Ctrl+Shift+T');
  await page.locator('#shortcut-feedback').getByText('快捷键已保存并立即生效', { exact: false }).waitFor();
  await page.locator('#shortcut-selection').fill('Ctrl+Shift+Y');
  // Leaving settings before the begin reply still ends exactly that lease.
  await page.evaluate(() => { window.__qa.holdShortcutBegin = true; });
  await page.locator('[data-shortcut-record="silentOcr"]').click();
  await page.getByRole('button', { name: '返回翻译', exact: true }).click();
  await page.evaluate(() => { window.__qa.holdShortcutBegin = false; window.__qa.releaseShortcutBegin(); });
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === false);
  const lastLease = await page.evaluate(() => window.__qa.shortcutLeases.slice(-2));
  assert.equal(lastLease[0].id, lastLease[1].id);
  await page.locator('#more-toggle').click();
  await page.locator('button[data-view="settings"]').click();
  // The OS can consume the registered main key, so no DOM D/S event is
  // invented here. A matching native release supplies only that configured
  // combo; a held modifier still prevents completion.
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'Alt', code: 'AltLeft', altKey: true });
  await page.evaluate(() => { const id = window.__qa.shortcutLeases.at(-1).id; window.__qa.emit('shortcut-recorded', { leaseId: id - 1, shortcut: 'Alt+X', modifiersDown: 0 }); });
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+Y');
  await page.evaluate(() => { const id = window.__qa.shortcutLeases.at(-1).id; window.__qa.emit('shortcut-recorded', { leaseId: id, shortcut: 'Alt+D', modifiersDown: 2 }); });
  await page.locator('#shortcut-feedback').getByText('已记录 Alt+D', { exact: false }).waitFor();
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+Y');
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Alt', code: 'AltLeft', altKey: false });
  await page.waitForFunction(() => document.querySelector('#shortcut-selection').value === 'Alt+D');
  // A native release whose IPC arrives after the DOM modifier release can
  // complete immediately, despite the older native snapshot saying held.
  await page.locator('[data-shortcut-record="silentOcr"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.locator('#shortcut-silentOcr').dispatchEvent('keydown', { key: 'Alt', code: 'AltLeft', altKey: true });
  await page.locator('#shortcut-silentOcr').dispatchEvent('keyup', { key: 'Alt', code: 'AltLeft', altKey: false });
  await page.evaluate(() => { const id = window.__qa.shortcutLeases.at(-1).id; window.__qa.emit('shortcut-recorded', { leaseId: id, shortcut: 'Alt+S', modifiersDown: 2 }); });
  await page.waitForFunction(() => document.querySelector('#shortcut-silentOcr').value === 'Alt+S');
  // A modifier held before the recorder's DOM listeners saw a down is still
  // held. Native main-key release alone must not finish such a recording.
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.evaluate(() => { const id = window.__qa.shortcutLeases.at(-1).id; window.__qa.emit('shortcut-recorded', { leaseId: id, shortcut: 'Ctrl+Shift+T', modifiersDown: 16 }); });
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.evaluate(() => { const id = window.__qa.shortcutLeases.at(-1).id; window.__qa.emit('shortcut-recorded', { leaseId: id, shortcut: 'Ctrl+Shift+T', modifiersDown: 5 }); });
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Alt+D');
  assert.equal(await page.evaluate(() => window.__qa.shortcutLeases.at(-1).active), true);
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Control', code: 'ControlLeft', shiftKey: true });
  assert.equal(await page.evaluate(() => window.__qa.shortcutLeases.at(-1).active), true);
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Shift', code: 'ShiftLeft' });
  await page.waitForFunction(() => document.querySelector('#shortcut-selection').value === 'Ctrl+Shift+T');
  // A platform without native modifier evidence waits for an actual DOM up;
  // it cannot assume that missing DOM downs meant all modifiers were released.
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.evaluate(() => { const id = window.__qa.shortcutLeases.at(-1).id; window.__qa.emit('shortcut-recorded', { leaseId: id, shortcut: 'Alt+D', modifiersDown: null }); });
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+T');
  assert.equal(await page.evaluate(() => window.__qa.shortcutLeases.at(-1).active), true);
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Alt', code: 'AltLeft' });
  await page.waitForFunction(() => document.querySelector('#shortcut-selection').value === 'Alt+D');
  // A Windows snapshot can establish that pre-held modifiers are all released
  // even if the main key and modifier events never reached the DOM.
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  await page.evaluate(() => { const id = window.__qa.shortcutLeases.at(-1).id; window.__qa.emit('shortcut-recorded', { leaseId: id, shortcut: 'Ctrl+Shift+T', modifiersDown: 0 }); });
  await page.waitForFunction(() => document.querySelector('#shortcut-selection').value === 'Ctrl+Shift+T');
  // Esc after a candidate, while its modifiers are still held, cancels too.
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  for (const event of [
    ['keydown', { key: 'Control', code: 'ControlLeft', ctrlKey: true }],
    ['keydown', { key: 'k', code: 'KeyK', ctrlKey: true }],
    ['keydown', { key: 'Escape', code: 'Escape', ctrlKey: true }],
    ['keyup', { key: 'Escape', code: 'Escape', ctrlKey: true }],
    ['keyup', { key: 'k', code: 'KeyK', ctrlKey: true }],
    ['keyup', { key: 'Control', code: 'ControlLeft', ctrlKey: false }],
  ]) await page.locator('#shortcut-selection').dispatchEvent(...event);
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === false);
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+T');
  // The frontend's deadline starts before begin IPC, so a >14s late ACK cannot
  // expose an apparently active recorder after its native protection expired.
  await page.evaluate(() => { window.__qa.holdShortcutBegin = true; });
  await page.locator('[data-shortcut-record="selection"]').click();
  await page.evaluate(() => {
    const now = performance.now.bind(performance);
    Object.defineProperty(performance, 'now', { configurable: true, value: () => now() + 15000 });
    window.__qa.holdShortcutBegin = false; window.__qa.releaseShortcutBegin();
  });
  await page.locator('#shortcut-feedback').getByText('录制准备已超时', { exact: false }).waitFor();
  await page.evaluate(() => { delete performance.now; });
  assert.equal(await page.evaluate(() => window.__qa.shortcutLeases.at(-1).active), false);
  assert.equal(await page.locator('#shortcut-selection').inputValue(), 'Ctrl+Shift+T');
  await page.locator('#shortcut-advanced > summary').click();
  // Multiple blanks disable those shortcuts; only nonempty values are compared.
  await page.locator('input[name="selection"]').fill('');
  await page.locator('input[name="capture"]').fill('');
  await page.locator('#save-shortcuts').click();
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === '' && window.__qa.settings.shortcuts.capture === '');
  const savesBeforeDuplicate = await page.evaluate(() => window.__qa.saveCalls);
  await page.locator('input[name="selection"]').fill('Ctrl+P');
  await page.locator('input[name="capture"]').fill('ctrl+p');
  await page.locator('#save-shortcuts').click();
  await page.locator('#shortcut-feedback').getByText('不同操作不能使用相同的快捷键。', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), savesBeforeDuplicate);

  // Presets populate the documented protocol/base while model names remain editable.
  await page.locator('#add-provider').click();
  assert.equal(await page.locator('#provider-preset').inputValue(), 'baidu');
  assert.equal(await page.locator('#provider-baidu-credentials').isVisible(), true);
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

  // Official MT uses separate masked bundles, while only region enters Settings.
  const officialSecrets = [];
  for (const [kind, fields, expected] of [
    ['baidu', [['provider-baidu-app-id', 'qa-mt-baidu-app'], ['provider-baidu-secret-key', 'qa-mt-baidu-secret']], { appId: 'qa-mt-baidu-app', secretKey: 'qa-mt-baidu-secret' }],
    ['youdao', [['provider-youdao-app-key', 'qa-mt-youdao-app'], ['provider-youdao-app-secret', 'qa-mt-youdao-secret']], { appKey: 'qa-mt-youdao-app', appSecret: 'qa-mt-youdao-secret' }],
    ['microsoft', [['provider-microsoft-subscription-key', 'qa-mt-microsoft-secret']], { subscriptionKey: 'qa-mt-microsoft-secret' }],
  ]) {
    await page.locator('#add-provider').click();
    await page.locator('#provider-preset').selectOption(kind);
    assert.equal(await page.locator(`#provider-preset option[value="${kind}"]`).evaluate(element => element.parentElement.label), ['baidu', 'microsoft'].includes(kind) ? '推荐 · 从这些服务开始' : '官方机器翻译');
    assert.equal(await page.locator('#provider-url-field').isHidden(), true);
    assert.equal(await page.locator('#provider-model-field').isHidden(), true);
    assert.equal(await page.locator('#provider-prompt-field').isHidden(), true);
    assert.equal(await page.locator('#provider-key-field').isHidden(), true);
    assert.equal(await page.locator('#provider-microsoft-region-field').isVisible(), kind === 'microsoft');
    await page.locator('#provider-service-guide a').first().click();
    assert.equal(await page.evaluate(() => window.__qa.serviceLinks.at(-1).startsWith('https://')), true);
    if (kind === 'baidu') {
      const originalTheme = await page.evaluate(() => document.documentElement.dataset.theme);
      await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
      await page.screenshot({ path: 'test-results/official-translation-800-light.png' });
      await page.setViewportSize({ width: 420, height: 700 });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      await page.evaluate(() => { document.documentElement.dataset.theme = 'dark'; });
      await page.screenshot({ path: 'test-results/official-translation-420-dark.png' });
      await page.evaluate(theme => { document.documentElement.dataset.theme = theme; }, originalTheme);
      await page.setViewportSize({ width: 800, height: 820 });
    }
    await page.locator('#provider-name').fill(`QA MT ${kind}`);
    await page.locator(`#${fields[0][0]}`).fill(fields[0][1]);
    if (fields.length === 2) {
      const saves = await page.evaluate(() => window.__qa.saveCalls);
      await page.locator('#save-provider').click();
      await page.locator('#provider-error').getByText('需要同时填写', { exact: false }).waitFor();
      assert.equal(await page.evaluate(() => window.__qa.saveCalls), saves);
      await page.locator(`#${fields[1][0]}`).fill(fields[1][1]);
    } else await page.locator('#provider-microsoft-region').fill('eastasia');
    for (const [, secret] of fields) officialSecrets.push(secret);
    await page.locator('#save-provider').click();
    await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
    assert.deepEqual(JSON.parse(await page.evaluate(() => window.__qa.translationCredentialWrites.at(-1).key)), expected);
    const nativeRow = page.locator('#provider-list .provider-row').filter({ hasText: `QA MT ${kind}` });
    await nativeRow.getByRole('button', { name: '编辑', exact: true }).click();
    for (const [field] of fields) assert.equal(await page.locator(`#${field}`).inputValue(), '');
    const writes = await page.evaluate(() => window.__qa.translationCredentialWrites.length);
    await page.locator('#save-provider').click();
    await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
    assert.equal(await page.evaluate(() => window.__qa.translationCredentialWrites.length), writes);
    if (kind === 'microsoft') assert.equal(await page.evaluate(() => window.__qa.settings.providers.find(item => item.kind === 'microsoft').region), 'eastasia');
    await nativeRow.getByRole('button', { name: '编辑', exact: true }).click();
    await page.locator(`#${fields[0][0]}`).fill('qa-discard-mt-scope');
    await page.locator('#provider-preset').selectOption('openai');
    assert.equal(await page.locator(`#${fields[0][0]}`).inputValue(), '');
    await page.locator('#provider-key').fill('qa-discard-mt-close');
    await page.locator('#cancel-provider-dialog').click();
    assert.equal(await page.locator('#provider-key').inputValue(), '');
    await page.getByRole('button', { name: `删除 QA MT ${kind}`, exact: true }).click();
    await page.locator('#confirm-accept').click();
    await page.waitForFunction(kind => !window.__qa.settings.providers.some(item => item.name === `QA MT ${kind}`), kind);
  }
  for (const secret of [...officialSecrets, 'qa-discard-mt-scope', 'qa-discard-mt-close']) assert.equal(await page.evaluate(secret => JSON.stringify(window.__qa.settingsWrites).includes(secret), secret), false);

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

  for (const kind of ['youdao', 'google']) {
    await page.locator('#add-ocr-provider').click();
    await page.locator('#ocr-provider-kind').selectOption(kind);
    await page.locator('#ocr-provider-name').fill(`QA OCR ${kind}`);
    for (const id of ['ocr-provider-url-field', 'ocr-provider-auth-header-field', 'ocr-provider-auth-prefix-field', 'ocr-provider-template-field', 'ocr-provider-response-field', 'ocr-provider-region-field']) assert.equal(await page.locator(`#${id}`).isHidden(), true);
    assert.equal(await page.locator('#ocr-service-guide a').count() >= 3, true);
    const originalTheme = await page.evaluate(() => document.documentElement.dataset.theme);
    await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
    await page.screenshot({ path: `test-results/official-ocr-${kind}-800-light.png` });
    await page.evaluate(theme => { document.documentElement.dataset.theme = theme; }, originalTheme);
    if (kind === 'youdao') {
      await page.locator('#ocr-youdao-app-key').fill('qa-ocr-youdao-app');
      const saves = await page.evaluate(() => window.__qa.saveCalls);
      await page.locator('#save-ocr-provider').click();
      await page.locator('#ocr-provider-error').getByText('有道 OCR 需要同时填写', { exact: false }).waitFor();
      assert.equal(await page.evaluate(() => window.__qa.saveCalls), saves);
      await page.locator('#ocr-youdao-app-secret').fill('qa-ocr-youdao-secret');
    } else {
      assert.equal(await page.locator('#ocr-provider-native-action').inputValue(), 'DOCUMENT_TEXT_DETECTION');
      await page.locator('#ocr-provider-native-action').selectOption('TEXT_DETECTION');
      await page.locator('#ocr-provider-key').fill('qa-ocr-google-secret');
    }
    await page.locator('#save-ocr-provider').click();
    await page.locator('#ocr-provider-dialog').waitFor({ state: 'hidden' });
    const credential = await page.evaluate(() => window.__qa.credentialWrites.at(-1));
    assert.equal(credential.kind, kind);
    if (kind === 'youdao') assert.deepEqual(JSON.parse(credential.key), { appKey: 'qa-ocr-youdao-app', appSecret: 'qa-ocr-youdao-secret' });
    else assert.equal(credential.key, 'qa-ocr-google-secret');
    assert.equal(await page.evaluate(() => window.__qa.settings.activeOcrProviderId), null);
    await page.getByRole('button', { name: `编辑 OCR QA OCR ${kind}`, exact: true }).click();
    const secretField = kind === 'youdao' ? '#ocr-youdao-app-secret' : '#ocr-provider-key';
    assert.equal(await page.locator(secretField).inputValue(), '');
    await page.locator(secretField).fill('qa-discard-ocr-scope');
    await page.locator('#ocr-provider-kind').selectOption('baidu');
    assert.equal(await page.locator(secretField).inputValue(), '');
    await page.locator('#ocr-baidu-api-key').fill('qa-discard-ocr-close');
    await page.locator('#cancel-ocr-provider-dialog').click();
    assert.equal(await page.locator('#ocr-baidu-api-key').inputValue(), '');
    await page.getByRole('button', { name: `删除 OCR QA OCR ${kind}`, exact: true }).click();
    await page.locator('#confirm-accept').click();
    await page.waitForFunction(() => window.__qa.settings.ocrProviders.length === 0);
  }
  for (const secret of ['qa-ocr-youdao-app', 'qa-ocr-youdao-secret', 'qa-ocr-google-secret', 'qa-discard-ocr-scope', 'qa-discard-ocr-close']) assert.equal(await page.evaluate(secret => JSON.stringify(window.__qa.settingsWrites).includes(secret), secret), false);

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

  // A passive blank event clears the floating view without focus or API requests.
  await goView('translate');
  await page.locator('#source-text').fill('QA text before empty selection');
  await page.locator('#pin-button').focus();
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => document.activeElement.id), '');
  assert.equal(await page.locator('.result-card').count(), 0);

  // Empty selection clears an old error without adding a tip or requesting an API.
  const emptyRequestCount = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.evaluate(() => window.__qa.emit('action-error', 'OCR 已完成，但复制到剪贴板失败'));
  await page.locator('#toast').getByText('OCR 已完成，但复制到剪贴板失败').waitFor();
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  assert.equal(await page.locator('#toast').isHidden(), true);
  for (const error of ['NO_SELECTION: No selected text', 'SELECTION_EMPTY: empty', 'CANCELLED: picker closed', '未取得选区，已打开输入框。PERMISSION: Accessibility']) {
    await page.evaluate((message) => window.__qa.emit('action-error', message), error);
    assert.equal(await page.locator('#toast').isHidden(), true);
  }
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount);
  // Real screenshot permission/NO_TEXT/OCR failures remain visible and explain
  // where the user can inspect permissions; translating API errors are separate.
  await page.evaluate(() => window.__qa.emit('action-error', 'PERMISSION: Screen capture is not granted'));
  await page.locator('#toast').getByText('Screen capture is not granted', { exact: false }).waitFor();
  assert.match(await page.locator('#toast').textContent(), /更多 → 设置 → 系统权限/);
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  await page.evaluate(() => window.__qa.emit('action-error', 'NO_TEXT: OCR did not recognize any text'));
  await page.locator('#toast').getByText('NO_TEXT: OCR did not recognize any text').waitFor();
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  await page.evaluate(() => window.__qa.emit('action-error', 'OCR provider request failed: HTTP 503'));
  await page.locator('#toast').getByText('OCR provider request failed: HTTP 503').waitFor();
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));
  await page.evaluate(() => window.__qa.emit('shortcut-error', '快捷键已被占用'));
  await page.locator('#toast').getByText('快捷键已被占用').waitFor();
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));

  // Source Enter submits once; Shift+Enter inserts a real newline. Composition
  // Enter/Escape, the legacy 229 confirmation event and key-repeat never submit.
  await page.locator('#source-text').fill('   ');
  await page.locator('#source-text').press('Enter');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount);
  assert.equal(await page.locator('#toast').isHidden(), true);
  await page.locator('#source-text').fill('QA Enter submits');
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, emptyRequestCount);
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  await page.locator('#source-text').dispatchEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, repeat: true });
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount + 1);
  await page.locator('#source-text').fill('First line');
  await page.locator('#source-text').press('End');
  await page.locator('#source-text').press('Shift+Enter');
  await page.locator('#source-text').press('x');
  assert.equal(await page.locator('#source-text').inputValue(), 'First line\nx');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount + 1);
  const hidesBeforeComposition = await page.evaluate(() => window.__qa.hideCalls);
  await page.locator('#source-text').dispatchEvent('compositionstart', { data: '中' });
  await page.locator('#source-text').dispatchEvent('keydown', { key: 'Enter', isComposing: true });
  await page.locator('#source-text').dispatchEvent('keydown', { key: 'Enter', ctrlKey: true, isComposing: true });
  await page.locator('#source-text').dispatchEvent('keydown', { key: 'Escape', isComposing: true });
  await page.locator('#source-text').dispatchEvent('compositionend', { data: '中' });
  await page.locator('#source-text').dispatchEvent('keydown', { key: 'Enter', keyCode: 229, isComposing: false });
  await page.locator('#source-text').dispatchEvent('keydown', { key: 'Enter', keyCode: 229, metaKey: true, isComposing: false });
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount + 1);
  assert.equal(await page.evaluate(() => window.__qa.hideCalls), hidesBeforeComposition);
  await page.evaluate(() => { window.__qa.holdTranslation = true; });
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 2, emptyRequestCount);
  await page.locator('#source-text').press('Enter');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount + 2);
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.releaseTranslation(); });
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  await page.locator('#source-text').dispatchEvent('keydown', { key: 'Enter', keyCode: 13, repeat: true });
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount + 2);
  await goView('settings');
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.locator('#provider-name').press('Enter');
  await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), emptyRequestCount + 2);
  await goView('translate');
  await page.evaluate(() => { window.__qa.translationError = '供应商 API 返回 403：PERMISSION_DENIED'; });
  await page.locator('#source-text').fill('QA real translation error');
  await page.locator('#source-text').press('Enter');
  await page.locator('.result-error').getByText('供应商 API 返回 403：PERMISSION_DENIED').waitFor();
  await page.evaluate(() => { window.__qa.translationError = null; });
  await page.evaluate(() => window.__qa.emit('source-text', { text: '', mode: 'input' }));

  // Captured text is cleaned before display AND API submission, while manual
  // input and explicit restoration retain their intentional line breaks.
  const captured = 'This paragraph uses a deliberately long first line copied from a PDF viewer\nand continues on the following visual line without starting a paragraph.\n\nSecond paragraph remains separate.';
  const cleaned = captured.replace('viewer\nand', 'viewer and');
  const beforeCapture = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.evaluate((text) => window.__qa.emit('source-text', { text, mode: 'translate' }), captured);
  await page.waitForFunction((length) => window.__qa.translationRequests.length === length + 1, beforeCapture);
  assert.equal(await page.locator('#source-text').inputValue(), cleaned);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), cleaned);
  assert.equal(await page.evaluate(() => window.__qa.showCalls.at(-1).presentation), 'popup');
  await page.locator('#more-toggle').click();
  await page.locator('#restore-original-breaks').click();
  await page.waitForFunction((length) => window.__qa.translationRequests.length === length + 2, beforeCapture);
  assert.equal(await page.locator('#source-text').inputValue(), captured);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), captured);
  await page.locator('#source-text').fill(captured);
  await page.locator('#translate-button').click();
  await page.waitForFunction((length) => window.__qa.translationRequests.length === length + 3, beforeCapture);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), captured);
  assert.equal(await page.locator('#restore-original-breaks').isHidden(), true);

  // Incoming shortcuts do not reveal or discard an unfinished credentials
  // editor. The latest captured source is presented after the editor closes.
  await goView('settings');
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.locator('#provider-name').fill('QA unfinished editor');
  const beforeQueued = await page.evaluate(() => ({ shows: window.__qa.showCalls.length, requests: window.__qa.translationRequests.length }));
  await page.evaluate(() => window.__qa.emit('source-text', { text: '这是一段自动换行的正文，\n下一行应该连续展示。\n\n这里是新的段落。', mode: 'ocr' }));
  assert.equal(await page.locator('#provider-dialog').isVisible(), true);
  assert.equal(await page.locator('#provider-name').inputValue(), 'QA unfinished editor');
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), beforeQueued.shows);
  await page.locator('#cancel-provider-dialog').click();
  await page.waitForFunction((shows) => window.__qa.showCalls.length === shows + 1, beforeQueued.shows);
  assert.equal(await page.locator('#source-text').inputValue(), '这是一段自动换行的正文，下一行应该连续展示。\n\n这里是新的段落。');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeQueued.requests);
  assert.equal(await page.evaluate(() => window.__qa.showCalls.at(-1).presentation), 'popup');
  await page.locator('#more-toggle').click();
  await page.locator('#restore-original-breaks').click();
  assert.match(await page.locator('#source-text').inputValue(), /正文，\n下一行/);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeQueued.requests);

  // Auto-translating OCR carries origin separately from its translate mode;
  // normalize only captured OCR and retain the exact raw capture for restore.
  const rawSpacedOcr = '中 文 测 试，\n换 行 识 别。';
  await page.evaluate(text => window.__qa.emit('source-text', { text, mode: 'translate', captureOrigin: 'ocr' }), rawSpacedOcr);
  await page.waitForFunction(() => document.querySelector('#source-text').value === '中文测试，换行识别。');
  await page.locator('#more-toggle').click(); await page.locator('#restore-original-breaks').click();
  assert.equal(await page.locator('#source-text').inputValue(), rawSpacedOcr);
  console.log('PASS: core shortcut recording/save/cancel/IME/navigation/late ACK/draft/failure frontend checks and OCR-origin normalization/raw restore. Isolated DOM and fake IPC only.');

  // Blocked capture keeps its permission metadata while a service editor owns
  // the window, then presents the guide after the user closes that editor.
  await goView('settings');
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.locator('#provider-name').fill('QA permission capture unfinished editor');
  const beforeQueuedPermission = await page.evaluate(() => ({ shows: window.__qa.showCalls.length, requests: window.__qa.translationRequests.length, opens: window.__qa.permissionSettings.length, authorizations: window.__qa.permissionRequests.length }));
  await emitPermissionCapture();
  assert.equal(await page.locator('#provider-dialog').isVisible(), true);
  assert.equal(await page.locator('#provider-name').inputValue(), 'QA permission capture unfinished editor');
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), beforeQueuedPermission.shows);
  await page.locator('#cancel-provider-dialog').click();
  await page.locator('#permission-guidance').waitFor({ state: 'visible' });
  await page.waitForFunction((shows) => window.__qa.showCalls.length === shows + 1, beforeQueuedPermission.shows);
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await page.evaluate(() => window.__qa.permissionAtShow.at(-1).visible), true);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeQueuedPermission.requests);
  assert.equal(await page.evaluate(() => window.__qa.permissionSettings.length), beforeQueuedPermission.opens);
  assert.equal(await page.evaluate(() => window.__qa.permissionRequests.length), beforeQueuedPermission.authorizations);

  // A user-triggered passive refresh clears obsolete guidance once macOS reports
  // that the corresponding permission is granted, without requesting it again.
  await page.locator('#permission-guidance-help').click();
  await page.waitForFunction(() => document.activeElement.id === 'mac-permission-card');
  await page.evaluate(() => { window.__qa.permissionState.screenCaptureGranted = true; });
  await page.locator('#refresh-permissions').click();
  await page.locator('#screen-capture-permission-state').getByText('已授权').waitFor();
  assert.equal(await page.locator('#permission-guidance').evaluate((element) => element.hidden), true);
  assert.equal(await page.evaluate(() => window.__qa.permissionRequests.length), beforeQueuedPermission.authorizations);
  await goView('translate');
  assert.equal(await page.locator('#permission-guidance').isHidden(), true);
  await page.evaluate(() => { window.__qa.permissionState.screenCaptureGranted = false; });

  // Alt+A is also deferred while editing a service, and then focuses only when
  // the user has closed the editor. It must not shrink the open editor.
  await goView('settings');
  await page.waitForFunction(() => window.__qa.layoutCalls.at(-1)?.presentation === 'management');
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.locator('#provider-name').fill('QA Alt+A unfinished editor');
  await page.evaluate(() => window.__qa.emitInputFocus());
  assert.equal(await page.locator('body').getAttribute('data-view'), 'settings');
  assert.equal(await page.locator('#provider-name').inputValue(), 'QA Alt+A unfinished editor');
  assert.equal(await page.evaluate(() => window.__qa.layoutCalls.at(-1).presentation), 'management');
  await page.locator('#cancel-provider-dialog').click();
  await page.waitForFunction(() => document.body.dataset.view === 'translate' && document.activeElement.id === 'source-text');

  // An Alt+A queued in an editor retains its original epoch. Closing that
  // editor after a newer selection starts must not reissue the old focus.
  await goView('settings');
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  const beforeQueuedFocus = await page.evaluate(async () => {
    const fixture = window.__qa;
    fixture.emitInputFocus();
    await new Promise((resolve) => setTimeout(resolve, 0));
    fixture.nativeHide(); fixture.nativeShow();
    return fixture.sourceFocusCalls;
  });
  await page.locator('#cancel-provider-dialog').click();
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await page.locator('body').getAttribute('data-view'), 'settings');
  assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), beforeQueuedFocus);
  await goView('translate');

  await goView('settings');
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.evaluate(async () => { window.__qa.emitInputFocus(); await new Promise((resolve) => setTimeout(resolve, 0)); });
  const beforeQueuedRoundtrip = await page.evaluate(() => {
    const focuses = window.__qa.sourceFocusCalls;
    // Close queues a microtask; navigate away and back before that continuation.
    document.querySelector('#cancel-provider-dialog').click();
    document.querySelector('button[data-view="translate"]').click();
    document.querySelector('button[data-view="settings"]').click();
    return focuses;
  });
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await page.locator('body').getAttribute('data-view'), 'settings');
  assert.equal(await page.evaluate(() => window.__qa.sourceFocusCalls), beforeQueuedRoundtrip);
  await goView('translate');

  // Tray, Cmd+, and reopen use an explicit Settings event. Configuration is
  // prepared in management geometry before the native focused presentation.
  const openNativeSettings = () => page.evaluate(() => {
    const state = window.__qa.nativeHide();
    window.__qa.pendingSettings = { presentationEpoch: state.epoch, section: 'shortcuts' };
    window.__qa.emit('open-settings', window.__qa.pendingSettings);
    return state.epoch;
  });
  const managementBefore = await page.evaluate(() => window.__qa.managementShows?.length ?? 0);
  const settingsEpoch = await openNativeSettings();
  await page.waitForFunction((count) => window.__qa.managementShows?.length === count + 1, managementBefore);
  assert.equal(await page.locator('body').getAttribute('data-view'), 'settings');
  assert.equal(await page.locator('#provider-list').isVisible(), true);
  assert.equal(await page.locator('#ocr-provider-list').isVisible(), true);
  assert.equal(await page.locator('#shortcuts-form').isVisible(), true);
  assert.deepEqual(await page.evaluate(() => window.__qa.managementShows.at(-1)), { view: 'settings', layout: await page.evaluate(() => window.__qa.layoutCalls.at(-1)) });
  await page.waitForFunction(() => document.activeElement?.id === 'shortcut-selection');
  await page.evaluate((presentationEpoch) => window.__qa.emit('open-settings', { presentationEpoch }), settingsEpoch);
  assert.equal(await page.evaluate(() => window.__qa.managementShows.length), managementBefore + 1);
  // Built-in translation never prepares/downloads from a status refresh. Its
  // service configuration has no endpoint or credential writes/deletions.
  await page.waitForFunction(() => document.querySelector('#system-translation-status').textContent === 'QA 语言包尚未准备');
  assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), []);
  await page.locator('#system-translation-source').selectOption('zh-Hans');
  await page.locator('#system-translation-target').selectOption('en');
  await page.waitForFunction(() => window.__qa.systemStatusCalls.at(-1)?.sourceLanguage === 'zh-Hans' && window.__qa.systemStatusCalls.at(-1)?.targetLanguage === 'en');
  await page.locator('#prepare-system-translation').click();
  await page.waitForFunction(() => document.querySelector('#system-translation-status').textContent === 'QA 本机语言包已就绪');
  assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), [{ sourceLanguage: 'zh-Hans', targetLanguage: 'en' }]);
  assert.equal(await page.locator('#prepare-system-translation').isDisabled(), true);
  await page.evaluate(() => { window.__qa.systemStatus = { platform: 'windows', supported: false, ready: false, requiresSetup: false, message: 'QA 此系统暂无通用内置翻译接口' }; });
  await page.locator('#refresh-system-translation').click();
  await page.waitForFunction(() => document.querySelector('#system-translation-status').textContent === 'QA 此系统暂无通用内置翻译接口');
  assert.equal(await page.locator('#prepare-system-translation').isDisabled(), true);
  assert.equal(await page.locator('#enable-system-translation').isHidden(), true);
  await page.evaluate(() => { window.__qa.systemStatus = { platform: 'macos', supported: true, ready: true, requiresSetup: false, message: 'QA 本机语言包已就绪' }; });
  await page.locator('#refresh-system-translation').click();
  await page.locator('#enable-system-translation').waitFor({ state: 'visible' });
  const systemKeysBefore = await page.evaluate(() => ({ writes: window.__qa.keyCalls, deletes: window.__qa.keyDeleteCalls }));
  await page.locator('#enable-system-translation').click();
  await page.waitForFunction(() => window.__qa.settings.providers.some(p => p.kind === 'system' && p.enabled));
  assert.equal(await page.evaluate(() => window.__qa.settings.providers.find(p => p.id === 'qa-service').enabled), true);
  const systemName = await page.evaluate(() => window.__qa.settings.providers.find(p => p.kind === 'system').name);
  const systemRow = page.locator('.provider-row').filter({ hasText: '无需 API Key' });
  await systemRow.getByRole('button', { name: '编辑', exact: true }).click();
  assert.equal(await page.locator('#provider-url').isVisible(), false);
  assert.equal(await page.locator('#provider-key').isVisible(), false);
  assert.equal(await page.locator('#provider-model').isVisible(), false);
  await page.locator('#save-provider').click();
  await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
  await page.locator('.app-shell').screenshot({ path: 'test-results/system-translation-settings.png' });
  await systemRow.getByRole('button', { name: `删除 ${systemName}`, exact: true }).click();
  await page.locator('#confirm-accept').click();
  await page.waitForFunction(() => !window.__qa.settings.providers.some(p => p.kind === 'system'));
  assert.deepEqual(await page.evaluate(() => ({ writes: window.__qa.keyCalls, deletes: window.__qa.keyDeleteCalls })), systemKeysBefore);
  // Offline service edits/removal must not query, write or delete credentials.
  const offlineKeysBefore = await page.evaluate(() => ({ writes: window.__qa.keyCalls, deletes: window.__qa.keyDeleteCalls, reads: window.__qa.credentialReadCalls }));
  await page.locator('#add-provider').click();
  await page.locator('#provider-preset').selectOption('offline');
  assert.equal(await page.locator('#provider-url-field').isHidden(), true);
  assert.equal(await page.locator('#provider-key-field').isHidden(), true);
  assert.equal(await page.locator('#provider-model-field').isHidden(), true);
  await page.locator('#save-provider').click();
  await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
  const offlineRow = page.locator('.provider-row').filter({ hasText: '本机离线翻译' });
  assert.equal(await offlineRow.getByText('内置中英模型 · 离线使用 · 无需配置').isVisible(), true);
  await offlineRow.getByRole('button', { name: '编辑', exact: true }).click();
  assert.equal(await page.locator('#provider-preset').inputValue(), 'offline');
  await page.locator('#save-provider').click();
  await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
  await offlineRow.getByRole('button', { name: '删除 本机离线翻译', exact: true }).click();
  await page.locator('#confirm-accept').click();
  await page.waitForFunction(() => !window.__qa.settings.providers.some(p => p.kind === 'offline'));
  assert.deepEqual(await page.evaluate(() => ({ writes: window.__qa.keyCalls, deletes: window.__qa.keyDeleteCalls, reads: window.__qa.credentialReadCalls })), offlineKeysBefore);
  await page.locator('.app-shell').screenshot({ path: 'test-results/settings-main.png' });
  await goView('translate');
  await page.waitForFunction(() => window.__qa.layoutCalls.at(-1)?.presentation === 'popup');
  const beforeDelayedManagement = await page.evaluate(() => ({ waits: window.__qa.fitWaits, shows: window.__qa.managementShows.length }));
  await page.evaluate(() => { window.__qa.holdFit = true; });
  await openNativeSettings();
  await page.waitForFunction((count) => window.__qa.fitWaits > count, beforeDelayedManagement.waits);
  await page.evaluate(() => {
    const state = window.__qa.nativeHide();
    window.__qa.emit('source-text', { text: '', mode: 'input', presentationEpoch: state.epoch });
    window.__qa.holdFit = false; window.__qa.releaseFit();
  });
  await page.waitForFunction(() => document.body.dataset.view === 'translate' && window.__qa.layoutCalls.at(-1)?.presentation === 'popup');
  assert.equal(await page.evaluate(() => window.__qa.managementShows.length), beforeDelayedManagement.shows);

  // Editing/clearing/stopping/hiding cancel the backend ticket. Native hide
  // events also reset the UI, and a late ticket cannot start an abandoned HTTP job.
  for (const action of ['edit', 'clear', 'stop', 'native-hide', 'escape', 'close']) {
    await page.evaluate(() => { window.__qa.holdTranslation = true; });
    await page.locator('#source-text').fill(`QA cancellation ${action}`);
    const count = await page.evaluate(() => window.__qa.translationRequests.length);
    await page.locator('#source-text').press('Enter');
    await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, count);
    const requestId = await page.evaluate(() => window.__qa.translationRequests.at(-1).requestId);
    assert.equal(await page.locator('#translate-button').getAttribute('aria-label'), '停止翻译');
    if (action === 'edit') await page.locator('#source-text').fill('QA replacement text');
    else if (action === 'clear') { await page.locator('#more-toggle').click(); await page.locator('#clear-source').click(); }
    else if (action === 'stop') await page.locator('#translate-button').click();
    else if (action === 'native-hide') await page.evaluate(() => window.__qa.nativeHide());
    else if (action === 'escape') await page.keyboard.press('Escape');
    else await page.locator('#close-popup').click();
    await page.waitForFunction((id) => window.__qa.cancellationRequests.includes(id), requestId);
    assert.equal(await page.locator('#results').getAttribute('aria-busy'), 'false');
    assert.equal(await page.locator('.result-error').count(), 0);
    assert.equal(await page.locator('#translate-button').getAttribute('aria-label'), '翻译');
    await page.evaluate(() => window.__qa.nativeShow());
  }
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.holdBegin = true; });
  const beforeLateTicket = await page.evaluate(() => ({ requests: window.__qa.translationRequests.length, tickets: window.__qa.nextTranslationId }));
  await page.locator('#source-text').fill('QA cancelled before ticket returned');
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction((id) => window.__qa.nextTranslationId > id, beforeLateTicket.tickets);
  await page.locator('#more-toggle').click(); await page.locator('#clear-source').click();
  await page.evaluate(() => { window.__qa.holdBegin = false; window.__qa.releaseBegin(); });
  await page.waitForFunction((id) => window.__qa.cancellationRequests.includes(id), beforeLateTicket.tickets + 1);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeLateTicket.requests);
  await page.evaluate(() => { window.__qa.holdBegin = true; });
  const beforeReplacement = await page.evaluate(() => ({ requests: window.__qa.translationRequests.length, tickets: window.__qa.nextTranslationId }));
  await page.locator('#source-text').fill('QA old ticket delayed');
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction((id) => window.__qa.nextTranslationId > id, beforeReplacement.tickets);
  await page.locator('#source-text').fill('QA latest ticket wins');
  await page.locator('#source-text').press('Enter');
  assert.equal(await page.evaluate(() => window.__qa.nextTranslationId), beforeReplacement.tickets + 1);
  await page.evaluate(() => { window.__qa.holdBegin = false; window.__qa.releaseBegin(); });
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, beforeReplacement.requests);
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), 'QA latest ticket wins');

  // A cancellation returned only by the backend must also clear the previous
  // successful result's state, so its service row/auto-hide/swap logic is inert.
  await page.evaluate(() => { window.__qa.translationError = 'CANCELLED: backend fixture cancellation'; });
  await page.locator('#translate-button').click();
  await page.waitForFunction(() => document.querySelector('#results').getAttribute('aria-busy') === 'false');
  assert.equal(await page.locator('#popup-services').isVisible(), true);
  assert.equal(await page.locator('.result-text, .result-error').count(), 0);
  await page.evaluate(() => { window.__qa.translationError = null; window.__qa.holdBeginBeforeAllocate = true; });

  // Hide before the backend has even allocated a ticket. Withhold the native
  // event entirely: the epoch check, rather than event delivery order, must
  // prevent an abandoned translation from starting its HTTP work.
  const beforeNativeHide = await page.evaluate(() => ({ requests: window.__qa.translationRequests.length, attempts: window.__qa.beginAttempts.length }));
  await page.locator('#source-text').fill('QA hidden before ticket allocation');
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction((count) => window.__qa.beginAttempts.length > count, beforeNativeHide.attempts);
  const delayedHide = await page.evaluate(() => window.__qa.nativeHide(false));
  await page.evaluate(() => { window.__qa.holdBeginBeforeAllocate = false; window.__qa.releaseBegin(); });
  await page.waitForFunction(() => document.querySelector('#results').getAttribute('aria-busy') === 'false');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeNativeHide.requests);
  assert.equal(await page.locator('#popup-services').isVisible(), true);

  // The user reopens the native input window (tray/hotkey/single-instance path)
  // and starts a valid translation. A delayed hide event from the old popup
  // must not stop it or overwrite it with an old captured-source event.
  await page.evaluate(() => { window.__qa.nativeShow(); window.__qa.holdTranslation = true; });
  await page.locator('#source-text').fill('QA reopened input remains usable');
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, beforeNativeHide.requests);
  await page.evaluate((old) => {
    window.__qa.emit('translation-presentation', old);
    window.__qa.emit('source-text', { text: 'STALE NATIVE CAPTURE', mode: 'translate', presentationEpoch: old.epoch });
  }, delayedHide);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA reopened input remains usable');
  assert.equal(await page.locator('#translate-button').getAttribute('aria-label'), '停止翻译');
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.releaseTranslation(); });
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();

  // Reopening can itself overtake an old begin IPC. The old epoch is still
  // rejected after resume; the serialized new ticket then translates normally.
  await page.evaluate(() => { window.__qa.holdBeginBeforeAllocate = true; });
  const beforeOvertaken = await page.evaluate(() => ({ requests: window.__qa.translationRequests.length, attempts: window.__qa.beginAttempts.length }));
  await page.locator('#source-text').fill('QA old begin overtaken by reopen');
  await page.locator('#source-text').press('Enter');
  await page.waitForFunction((count) => window.__qa.beginAttempts.length > count, beforeOvertaken.attempts);
  const overtakenHide = await page.evaluate(() => { const hidden = window.__qa.nativeHide(false); window.__qa.nativeShow(); return hidden; });
  await page.locator('#source-text').fill('QA latest reopened ticket wins');
  await page.locator('#source-text').press('Enter');
  await page.evaluate(() => { window.__qa.holdBeginBeforeAllocate = false; window.__qa.releaseBegin(); });
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, beforeOvertaken.requests);
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  await page.evaluate((old) => window.__qa.emit('translation-presentation', old), overtakenHide);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), 'QA latest reopened ticket wins');
  assert.equal(await page.locator('.result-text').isVisible(), true);
  assert.match(await page.locator('.result-text').evaluate((element) => getComputedStyle(element).fontFamily), /^"?Times New Roman"?,/);
  assert.doesNotMatch(await page.locator('#source-text').evaluate((element) => getComputedStyle(element).fontFamily), /Times New Roman/);

  // Fitting content is asynchronous. An older capture must not show its popup
  // after the user has already hidden it and reopened a newer input window.
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const beforeDelayedPopup = await page.evaluate(() => {
    const before = { fits: window.__qa.fitWaits, shows: window.__qa.showCalls.length, attempts: window.__qa.showPopupAttempts.length, requests: window.__qa.translationRequests.length };
    const hidden = window.__qa.nativeHide(); window.__qa.holdFit = true;
    window.__qa.emit('source-text', { text: 'QA captured source awaiting fit\n'.repeat(12), mode: 'translate', presentationEpoch: hidden.epoch });
    return before;
  });
  await page.waitForFunction((count) => window.__qa.fitWaits > count, beforeDelayedPopup.fits);
  await page.evaluate(() => { window.__qa.nativeHide(false); window.__qa.nativeShow(); });
  await page.locator('#source-text').fill('QA newer input survives delayed popup');
  await page.evaluate(async () => {
    window.__qa.holdFit = false; window.__qa.releaseFit();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.length), beforeDelayedPopup.attempts);
  assert.equal(await page.evaluate(() => window.__qa.showCalls.length), beforeDelayedPopup.shows);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeDelayedPopup.requests);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA newer input survives delayed popup');
  // Auto direction is a first-class target; fixed targets remain selectable.
  await page.locator('#target-language').selectOption('auto');
  await page.waitForFunction(() => window.__qa.settings.targetLanguage === 'auto');
  await page.locator('#source-text').fill('你好');
  await page.locator('#source-text').press('Enter');
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).targetLanguage), 'auto');
  await page.locator('#target-language').selectOption('en');
  await page.waitForFunction(() => window.__qa.settings.targetLanguage === 'en');
  await page.locator('#translate-button').click();
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).targetLanguage), 'en');
  // The countdown feature was removed; theme/favorites and bounded history remain.
  await goView('settings');
  assert.equal(await page.locator('#auto-hide-seconds').count(), 0);
  assert.equal(await page.locator('#theme-select').isVisible(), true);
  assert.equal(await page.locator('#max-history').getAttribute('max'), '100');
  assert.equal(await page.locator('#max-history').inputValue(), '20');
  await page.locator('#max-history').fill('37');
  await page.locator('#max-history').dispatchEvent('change');
  await page.waitForFunction(() => window.__qa.settings.maxHistory === 37);
  await page.locator('#max-history').fill('101');
  await page.locator('#max-history').dispatchEvent('change');
  assert.equal(await page.evaluate(() => window.__qa.settings.maxHistory), 37);
  assert.equal(await page.locator('#max-history').inputValue(), '37');
  await page.locator('#theme-select').selectOption('dark');
  await page.waitForFunction(() => window.__qa.settings.theme === 'dark' && document.documentElement.dataset.theme === 'dark');
  await page.locator('#theme-select').selectOption('system');
  await page.waitForFunction(() => window.__qa.settings.theme === 'system');
  await page.evaluate(() => { window.__qa.history = [
    { id: 'qa-history-a', createdAt: 1792890000000, text: 'QA history first', sourceLanguage: 'en', targetLanguage: 'zh-Hans', results: [], favorite: false },
    { id: 'qa-history-b', createdAt: 1792880000000, text: 'QA history second', sourceLanguage: 'en', targetLanguage: 'zh-Hans', results: [], favorite: false },
  ]; });
  await goView('history');
  await page.locator('.history-item').first().waitFor();
  assert.equal(await page.locator('.history-item').count(), 2);
  await page.locator('.history-item').first().getByRole('button', { name: '收藏翻译', exact: true }).click();
  await page.locator('.history-item').first().getByRole('button', { name: '取消收藏', exact: true }).waitFor();
  await page.locator('#filter-favorites').click();
  assert.equal(await page.locator('.history-item').count(), 1);
  assert.equal(await page.locator('.history-original').textContent(), 'QA history first');
  await page.getByRole('button', { name: '取消收藏', exact: true }).click();
  await page.getByText('暂无收藏', { exact: true }).waitFor();
  await page.locator('#filter-all').click();
  assert.equal(await page.locator('.history-item').count(), 2);
  // Captures stay editable after completion and while an automatic request is
  // pending. Use an actual click/key sequence, preserving the captured text.
  await goView('translate');
  await page.evaluate(() => window.__qa.emit('source-text', { text: 'Select text in any app\nand press the shortcut.', mode: 'translate', presentationEpoch: window.__qa.presentation.epoch }));
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).reuseVisiblePopup), false);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).focusInput), false);
  assert.equal(await page.locator('#source-text').inputValue(), 'Select text in any app and press the shortcut.');
  assert.equal(await page.locator('#source-text').isEditable(), true);
  await page.locator('#source-text').click();
  await page.keyboard.press('ControlOrMeta+End');
  await page.keyboard.type(' Edited.');
  assert.equal(await page.locator('#source-text').inputValue(), 'Select text in any app and press the shortcut. Edited.');
  await page.keyboard.press('Enter');
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), 'Select text in any app and press the shortcut. Edited.');
  const pendingEdit = await page.evaluate(() => { window.__qa.holdTranslation = true; return { requests: window.__qa.translationRequests.length, cancellations: window.__qa.cancellationRequests.length }; });
  await page.evaluate(() => window.__qa.emit('source-text', { text: 'QA OCR captured words', mode: 'translate', presentationEpoch: window.__qa.presentation.epoch }));
  await page.waitForFunction((count) => window.__qa.translationRequests.length > count, pendingEdit.requests);
  await page.locator('#source-text').click();
  await page.keyboard.press('ControlOrMeta+End');
  await page.keyboard.type(' corrected');
  await page.waitForFunction((count) => window.__qa.cancellationRequests.length > count, pendingEdit.cancellations);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA OCR captured words corrected');
  await page.evaluate(() => { window.__qa.holdTranslation = false; });
  await page.keyboard.press('Enter');
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), 'QA OCR captured words corrected');
  // A second capture keeps an already pinned, completed result readable. Only
  // successful recognition replaces source text; cancel/error sends no source.
  await pin.click();
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'true');
  const pinnedCaptureBaseline = await page.evaluate(() => {
    window.__qa.pinnedOldCard = document.querySelector('.result-card');
    return { text: document.querySelector('#source-text').value, result: document.querySelector('.result-text').textContent,
      requests: window.__qa.translationRequests.length, reveals: window.__qa.popupReveals, hides: window.__qa.nativeHideTransitions,
      pinRequests: window.__qa.pinRequests.length, permissions: window.__qa.permissionRequests.length,
      oldRequest: window.__qa.translationRequests.at(-1), oldEpoch: window.__qa.presentation.epoch };
  });
  let previousPinnedEpoch = pinnedCaptureBaseline.oldEpoch;
  for (const failure of [null, 'NO_TEXT: QA no text in this region', 'OCR: QA recognition failed', 'PERMISSION: QA screen capture is not granted']) {
    const capture = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
    assert.ok(capture.epoch > previousPinnedEpoch); previousPinnedEpoch = capture.epoch;
    assert.equal(capture.presented, true);
    // Escape/selection cancellation emits nothing. Actionable failures use the
    // existing error event and must not synthesize an empty source payload.
    if (failure) {
      await page.evaluate((message) => window.__qa.emit('action-error', message), failure);
      assert.equal(await page.locator('#toast').isVisible(), true);
      assert.match(await page.locator('#toast').textContent(), /QA/);
      if (failure.startsWith('PERMISSION:')) assert.match(await page.locator('#toast').textContent(), /更多.*设置.*系统权限/);
    }
    assert.equal(await page.locator('#source-text').inputValue(), pinnedCaptureBaseline.text);
    assert.equal(await page.locator('.result-text').textContent(), pinnedCaptureBaseline.result);
    assert.equal(await page.evaluate(() => window.__qa.pinnedOldCard.isConnected), true);
    assert.equal(await pin.getAttribute('aria-pressed'), 'true');
    assert.equal(await page.evaluate(() => window.__qa.nativeVisible && window.__qa.presentation.presented), true);
  }
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), pinnedCaptureBaseline.requests);
  assert.equal(await page.evaluate(() => window.__qa.popupReveals), pinnedCaptureBaseline.reveals);
  assert.equal(await page.evaluate(() => window.__qa.nativeHideTransitions), pinnedCaptureBaseline.hides);
  assert.equal(await page.evaluate(() => window.__qa.pinRequests.length), pinnedCaptureBaseline.pinRequests);
  assert.equal(await page.evaluate(() => window.__qa.permissionRequests.length), pinnedCaptureBaseline.permissions);
  const beforeUnmatchedMarked = await page.evaluate(() => ({ source: document.querySelector('#source-text').value,
    requests: window.__qa.translationRequests.length, shows: window.__qa.showPopupAttempts.length }));
  await page.evaluate(() => {
    window.__qa.emit('source-text', { text: 'QA marked OCR missing epoch', mode: 'translate', updateVisiblePopup: true });
    window.__qa.emit('source-text', { text: 'QA marked OCR future epoch', mode: 'translate', presentationEpoch: window.__qa.presentation.epoch + 1, updateVisiblePopup: true });
  });
  assert.equal(await page.locator('#source-text').inputValue(), beforeUnmatchedMarked.source);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeUnmatchedMarked.requests);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.length), beforeUnmatchedMarked.shows);
  const nextPinnedCapture = await page.evaluate(() => { window.__qa.holdTranslation = true; return window.__qa.nativePinnedCaptureStart(); });
  await page.evaluate((epoch) => window.__qa.emit('source-text', { text: 'QA next pinned OCR capture result', mode: 'translate', presentationEpoch: epoch, updateVisiblePopup: true }), nextPinnedCapture.epoch);
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, pinnedCaptureBaseline.requests);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).reuseVisiblePopup), true);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).focusInput), false);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA next pinned OCR capture result');
  assert.equal(await page.evaluate(() => window.__qa.pinnedOldCard.isConnected), false);
  const stalePinnedProgress = { requestId: pinnedCaptureBaseline.oldRequest.requestId, presentationEpoch: pinnedCaptureBaseline.oldEpoch,
    sequence: 100, done: true, result: { providerId: 'qa-service', providerName: 'QA stale pinned capture', text: 'STALE PINNED TRANSLATION', elapsedMs: 1 } };
  await page.evaluate(({ epoch, progress }) => {
    window.__qa.emit('source-text', { text: 'STALE PINNED OCR SOURCE', mode: 'translate', presentationEpoch: epoch, updateVisiblePopup: true });
    window.__qa.emit('translation-presentation', { epoch, presented: false });
    window.__qa.emit('translation-progress', progress);
  }, { epoch: pinnedCaptureBaseline.oldEpoch, progress: stalePinnedProgress });
  assert.equal(await page.locator('#source-text').inputValue(), 'QA next pinned OCR capture result');
  assert.equal(await page.getByText('STALE PINNED TRANSLATION', { exact: true }).count(), 0);
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.releaseTranslation(); });
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.at(-1).text), 'QA next pinned OCR capture result');
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  assert.equal(await page.evaluate(() => window.__qa.popupReveals), pinnedCaptureBaseline.reveals);
  assert.equal(await page.evaluate(() => window.__qa.nativeHideTransitions), pinnedCaptureBaseline.hides);
  // An ordinary selection is a fresh presentation request even when this
  // pinned popup is already visible. Only marked OCR may request reuse.
  const ordinaryPinnedCount = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.evaluate(() => window.__qa.emit('source-text', { text: 'QA ordinary selection requests a passive raise', mode: 'translate',
    presentationEpoch: window.__qa.presentation.epoch, updateVisiblePopup: false }));
  await page.waitForFunction((count) => window.__qa.translationRequests.length > count, ordinaryPinnedCount);
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).reuseVisiblePopup), false);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).focusInput), false);
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  // Exercise the production delivery IDs/ACK path as well as legacy synthetic
  // events: every fresh pinned task may replace a completed result, while
  // edits/navigation and a newer task still invalidate the previous request.
  let pinnedDeliveryId = 1000;
  for (const kind of ['ocr', 'selection', 'ocr', 'selection']) {
    const task = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
    const count = await page.evaluate(() => window.__qa.translationRequests.length);
    const id = ++pinnedDeliveryId;
    await page.evaluate(({ kind, task, id }) => {
      const payload = { text: `QA identified pinned ${kind} ${id}`, mode: 'translate', presentationEpoch: task.epoch,
        deliveryId: id, updateVisiblePopup: true, reuseVisiblePopup: kind === 'ocr', ...(kind === 'ocr' ? { captureOrigin: 'ocr' } : {}) };
      window.__qa.pendingSource = structuredClone(payload); window.__qa.emit('source-text', payload);
    }, { kind, task, id });
    await page.waitForFunction(({ count, id }) => window.__qa.translationRequests.length === count + 1 && window.__qa.sourceAcks.includes(id), { count, id });
    await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
    assert.equal(await page.locator('#source-text').inputValue(), `QA identified pinned ${kind} ${id}`);
    assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).reuseVisiblePopup), kind === 'ocr');
    assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  }
  // A fresh empty Alt+D is a manual-input task even while pinned. The
  // backend must deliver this event; this UI test verifies its ACK/focus path.
  const emptyPinned = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
  const emptyPinnedId = ++pinnedDeliveryId;
  const beforeEmptyPinned = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.evaluate(({ task, id }) => {
    const payload = { text: '', mode: 'input', focusInput: true, presentationEpoch: task.epoch, deliveryId: id };
    window.__qa.pendingSource = structuredClone(payload); window.__qa.emit('source-text', payload);
  }, { task: emptyPinned, id: emptyPinnedId });
  await page.waitForFunction((id) => window.__qa.sourceAcks.includes(id) && document.activeElement.id === 'source-text', emptyPinnedId);
  assert.equal(await page.locator('#source-text').inputValue(), '');
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), beforeEmptyPinned);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).focusInput), true);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).reuseVisiblePopup), false);
  await page.keyboard.type('QA pinned immediate keyboard input');
  assert.equal(await page.locator('#source-text').inputValue(), 'QA pinned immediate keyboard input');
  await page.keyboard.press('Enter');
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, beforeEmptyPinned);
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  const supersededPinned = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
  const latestPinned = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
  const latestPinnedId = ++pinnedDeliveryId;
  const beforeLatestPinned = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.evaluate(({ old, current, id }) => {
    window.__qa.emit('source-text', { text: 'QA stale native OCR completion', mode: 'translate', presentationEpoch: old.epoch, deliveryId: id,
      updateVisiblePopup: true, reuseVisiblePopup: true, captureOrigin: 'ocr' });
    window.__qa.emit('source-text', { text: 'QA latest AltD replaces pending OCR', mode: 'translate', presentationEpoch: current.epoch, deliveryId: id + 1,
      updateVisiblePopup: true, reuseVisiblePopup: false });
  }, { old: supersededPinned, current: latestPinned, id: latestPinnedId });
  pinnedDeliveryId++;
  await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, beforeLatestPinned);
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.locator('#source-text').inputValue(), 'QA latest AltD replaces pending OCR');
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.at(-1).reuseVisiblePopup), false);
  const beforeRestoreNotice = await page.evaluate(() => ({
    source: document.querySelector('#source-text').value, results: document.querySelector('#results').textContent,
    requests: window.__qa.translationRequests.length, shows: window.__qa.showPopupAttempts.length,
    hides: window.__qa.nativeHideTransitions, epoch: window.__qa.presentation.epoch,
  }));
  await page.evaluate(() => window.__qa.emit('action-error', '原剪贴板恢复失败，当前剪贴板可能仍是刚才复制的选中文字。'));
  await page.locator('#toast').getByText('原剪贴板恢复失败，当前剪贴板可能仍是刚才复制的选中文字。').waitFor();
  assert.deepEqual(await page.evaluate(() => ({
    source: document.querySelector('#source-text').value, results: document.querySelector('#results').textContent,
    requests: window.__qa.translationRequests.length, shows: window.__qa.showPopupAttempts.length,
    hides: window.__qa.nativeHideTransitions, epoch: window.__qa.presentation.epoch,
  })), beforeRestoreNotice);
  for (const invalidation of ['edit', 'pin-toggle', 'management']) {
    const task = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
    const baseline = await page.evaluate(() => ({ requests: window.__qa.translationRequests.length, shows: window.__qa.showPopupAttempts.length }));
    if (invalidation === 'edit') await page.locator('#source-text').fill('QA edit during retained selection wins');
    if (invalidation === 'management') await goView('history');
    if (invalidation === 'pin-toggle') { await pin.click(); await pin.click(); }
    const text = await page.locator('#source-text').inputValue();
    const id = ++pinnedDeliveryId;
    await page.evaluate(({ task, id }) => window.__qa.emit('source-text', { text: 'QA retained selection completion', mode: 'translate',
      deliveryId: id, presentationEpoch: task.epoch, updateVisiblePopup: true, reuseVisiblePopup: false }), { task, id });
    await page.waitForFunction((id) => window.__qa.sourceAcks.includes(id), id);
    if (invalidation === 'pin-toggle') {
      await page.waitForFunction((count) => window.__qa.translationRequests.length === count + 1, baseline.requests);
      await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
      assert.equal(await page.locator('#source-text').inputValue(), 'QA retained selection completion');
    } else {
      assert.equal(await page.locator('#source-text').inputValue(), text);
      assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), baseline.requests);
      assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.length), baseline.shows);
    }
    if (invalidation === 'management') await goView('translate');
  }
  // A pinned capture result is an update to the existing translation view,
  // never an instruction to navigate away from later management actions.
  for (const managementView of ['settings', 'history']) {
    const capture = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
    const before = await page.evaluate(() => ({ source: document.querySelector('#source-text').value,
      requests: window.__qa.translationRequests.length, shows: window.__qa.showPopupAttempts.length }));
    await goView(managementView);
    await page.evaluate((epoch) => window.__qa.emit('source-text', { text: 'QA late OCR must not replace management', mode: 'translate', presentationEpoch: epoch, updateVisiblePopup: true }), capture.epoch);
    assert.equal(await page.locator('body').getAttribute('data-view'), managementView);
    assert.equal(await page.locator('#source-text').inputValue(), before.source);
    assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), before.requests);
    assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.length), before.shows);
    await goView('translate');
  }
  // Direct edits and Alt+A typing advance the UI generation without changing
  // the native presentation epoch; a late OCR update must respect both.
  for (const action of ['edit', 'focus-input']) {
    const capture = await page.evaluate(() => window.__qa.nativePinnedCaptureStart());
    if (action === 'edit') await page.locator('#source-text').fill('QA manual edit wins over pending OCR');
    else {
      await page.evaluate(() => window.__qa.emitInputFocus());
      await page.waitForFunction(() => document.activeElement.id === 'source-text');
      await page.keyboard.press('ControlOrMeta+End'); await page.keyboard.type(' with Alt+A typing');
    }
    const before = await page.evaluate(() => ({ source: document.querySelector('#source-text').value,
      requests: window.__qa.translationRequests.length, shows: window.__qa.showPopupAttempts.length }));
    await page.evaluate((epoch) => window.__qa.emit('source-text', { text: 'QA late OCR must not replace edited input', mode: 'translate', presentationEpoch: epoch, updateVisiblePopup: true }), capture.epoch);
    assert.equal(await page.locator('#source-text').inputValue(), before.source);
    assert.equal(await page.locator('body').getAttribute('data-view'), 'translate');
    assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), before.requests);
    assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.length), before.shows);
  }
  const manuallyTranslatedCapture = await page.evaluate(() => { window.__qa.holdTranslation = true; return window.__qa.nativePinnedCaptureStart(); });
  const manualTranslationCount = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.locator('#translate-button').click();
  await page.waitForFunction((count) => window.__qa.translationRequests.length > count, manualTranslationCount);
  const manualTranslationBefore = await page.evaluate(() => ({ source: document.querySelector('#source-text').value,
    cancellations: window.__qa.cancellationRequests.length, requestId: window.__qa.translationRequests.at(-1).requestId }));
  await page.evaluate((epoch) => window.__qa.emit('source-text', { text: 'QA late OCR must not cancel manual translation', mode: 'translate', presentationEpoch: epoch, updateVisiblePopup: true }), manuallyTranslatedCapture.epoch);
  assert.equal(await page.locator('#source-text').inputValue(), manualTranslationBefore.source);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), manualTranslationCount + 1);
  assert.equal(await page.evaluate(() => window.__qa.cancellationRequests.length), manualTranslationBefore.cancellations);
  assert.equal(await page.locator('#translate-button').getAttribute('aria-label'), '停止翻译');
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.releaseTranslation(); });
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  // In-flight partial translations retain the existing cancellation policy;
  // a capture start must not leave a partial result looking completed.
  await page.locator('#source-text').fill('QA pending translation before pinned OCR');
  const pendingPinnedCount = await page.evaluate(() => { window.__qa.holdTranslation = true; return window.__qa.translationRequests.length; });
  await page.locator('#translate-button').click();
  await page.waitForFunction((count) => window.__qa.translationRequests.length > count, pendingPinnedCount);
  await page.evaluate(() => {
    const provider = window.__qa.settings.providers.find((item) => item.enabled);
    window.__qa.emit('translation-progress', { requestId: window.__qa.translationRequests.at(-1).requestId,
      presentationEpoch: window.__qa.presentation.epoch, sequence: 1, done: false,
      result: { providerId: provider.id, providerName: provider.name, text: 'QA partial result before capture', elapsedMs: 1 } });
  });
  await page.getByText('QA partial result before capture', { exact: true }).waitFor();
  await page.evaluate(() => { window.__qa.nativePinnedCaptureStart(); window.__qa.holdTranslation = false; });
  await page.waitForFunction(() => document.querySelectorAll('.result-card').length === 0);
  assert.equal(await page.locator('#source-text').inputValue(), 'QA pending translation before pinned OCR');
  assert.equal(await pin.getAttribute('aria-pressed'), 'true');
  assert.equal(await page.evaluate(() => window.__qa.popupReveals), pinnedCaptureBaseline.reveals);
  assert.equal(await page.evaluate(() => window.__qa.nativeHideTransitions), pinnedCaptureBaseline.hides);
  const closedPinned = await page.evaluate(() => { const hidden = window.__qa.nativeHide(); return { ...hidden,
    source: document.querySelector('#source-text').value, shows: window.__qa.showPopupAttempts.length }; });
  await page.evaluate((epoch) => window.__qa.emit('source-text', { text: 'QA marked OCR cannot reopen closed popup', mode: 'translate', presentationEpoch: epoch, updateVisiblePopup: true }), closedPinned.epoch);
  assert.equal(await page.locator('#source-text').inputValue(), closedPinned.source);
  assert.equal(await page.evaluate(() => window.__qa.showPopupAttempts.length), closedPinned.shows);
  assert.equal(await page.evaluate(() => window.__qa.nativeVisible), false);
  await page.evaluate(() => window.__qa.nativeShow());
  await pin.click();
  await page.waitForFunction(() => document.querySelector('#pin-button').getAttribute('aria-pressed') === 'false');
  // Real progress events update one stable card before the translate IPC ends.
  // Partial content remains plain text; copy/read use the latest snapshot and
  // stay visible without hover. Stale requests/epochs/sequences cannot repaint.
  const streamStart = await page.evaluate(() => { window.__qa.holdTranslation = true; return window.__qa.translationRequests.length; });
  await page.locator('#source-text').fill('QA incremental translation');
  await page.locator('#translate-button').click();
  await page.waitForFunction((count) => window.__qa.translationRequests.length > count, streamStart);
  const streamEvent = await page.evaluate(() => {
    const provider = window.__qa.settings.providers.find((item) => item.enabled);
    return { requestId: window.__qa.translationRequests.at(-1).requestId, presentationEpoch: window.__qa.presentation.epoch,
      sequence: 1, done: false, result: { providerId: provider.id, providerName: provider.name, text: '<b>First</b>', elapsedMs: 1 } };
  });
  await page.evaluate((event) => window.__qa.emit('translation-progress', event), streamEvent);
  const streamingCard = page.locator('.result-card').filter({ has: page.locator('.result-text', { hasText: '<b>First</b>' }) });
  await streamingCard.waitFor();
  assert.equal(await streamingCard.locator('.result-text b').count(), 0);
  assert.equal(await streamingCard.getAttribute('aria-busy'), 'true');
  assert.equal(await page.locator('#translate-button').getAttribute('aria-label'), '停止翻译');
  await streamingCard.evaluate((element) => { window.__qa.streamCard = element; });
  const progressed = { ...streamEvent, sequence: 2, result: { ...streamEvent.result, text: '<b>First</b> second segment' } };
  await page.evaluate((event) => window.__qa.emit('translation-progress', event), progressed);
  assert.equal(await page.evaluate(() => window.__qa.streamCard.isConnected), true);
  await page.mouse.move(790, 810);
  assert.equal(await streamingCard.locator('.result-actions').evaluate((element) => getComputedStyle(element).opacity), '1');
  assert.equal(await streamingCard.getByRole('button', { name: '复制译文', exact: true }).isVisible(), true);
  assert.equal(await streamingCard.getByRole('button', { name: '朗读译文', exact: true }).isVisible(), true);
  assert.equal(await streamingCard.locator('.result-actions').evaluate((element) => element.previousElementSibling.className), 'result-text');
  await streamingCard.getByRole('button', { name: '复制译文', exact: true }).click();
  await streamingCard.getByRole('button', { name: '朗读译文', exact: true }).click();
  assert.equal(await page.evaluate(() => window.__qa.copies.at(-1)), progressed.result.text);
  assert.equal(await page.evaluate(() => window.__qa.spoken.at(-1).text), progressed.result.text);
  for (const ignored of [streamEvent, { ...progressed, sequence: 9, requestId: streamEvent.requestId - 1 },
    { ...progressed, sequence: 9, presentationEpoch: streamEvent.presentationEpoch - 1 },
    { ...progressed, sequence: 9, result: { ...progressed.result, providerId: 'unknown-service' } }]) {
    await page.evaluate((event) => window.__qa.emit('translation-progress', event), ignored);
    assert.equal(await streamingCard.locator('.result-text').textContent(), progressed.result.text);
  }
  const failedStream = { ...progressed, sequence: 3, done: true, result: { ...progressed.result, text: '', error: 'QA stream interrupted' } };
  await page.evaluate((event) => window.__qa.emit('translation-progress', event), failedStream);
  await page.locator('.result-error', { hasText: 'QA stream interrupted' }).waitFor();
  assert.equal(await page.locator('.result-text', { hasText: progressed.result.text }).count(), 0);
  await page.evaluate((event) => window.__qa.emit('translation-progress', event), { ...progressed, sequence: 4 });
  assert.equal(await page.locator('.result-error', { hasText: 'QA stream interrupted' }).count(), 1);
  await page.locator('#source-text').fill('QA cancel completed stream');
  await page.evaluate((event) => window.__qa.emit('translation-progress', event), { ...progressed, sequence: 5 });
  assert.equal(await page.locator('.result-card').count(), 0);
  // A fast provider's completed result is shown while other work/IPC is pending.
  const nextStreamCount = await page.evaluate(() => window.__qa.translationRequests.length);
  await page.locator('#translate-button').click();
  await page.waitForFunction((count) => window.__qa.translationRequests.length > count, nextStreamCount);
  const completeProgress = await page.evaluate((event) => ({ ...event, requestId: window.__qa.translationRequests.at(-1).requestId,
    presentationEpoch: window.__qa.presentation.epoch, sequence: 1, done: true,
    result: { ...event.result, text: 'QA provider finished early' } }), streamEvent);
  await page.evaluate((event) => window.__qa.emit('translation-progress', event), completeProgress);
  await page.getByText('QA provider finished early', { exact: true }).waitFor();
  await page.getByText('QA provider finished early', { exact: true }).evaluate((element) => { window.__qa.finishedStreamCard = element.closest('.result-card'); });
  await page.locator('.result-card').filter({ hasText: 'QA provider finished early' }).getByRole('button', { name: '复制译文', exact: true }).focus();
  assert.equal(await page.locator('#translate-button').getAttribute('aria-label'), '停止翻译');
  await page.evaluate((event) => window.__qa.emit('translation-progress', event), { ...completeProgress, sequence: 2, done: false });
  assert.equal(await page.getByText('QA provider finished early', { exact: true }).count(), 1);
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.releaseTranslation(); });
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.finishedStreamCard.isConnected), true);
  assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('aria-label')), '复制译文');
  await page.getByRole('button', { name: '复制译文', exact: true }).click();
  await page.getByRole('button', { name: '朗读译文', exact: true }).click();
  assert.equal(await page.evaluate(() => window.__qa.copies.at(-1)), 'Isolated test translation fixture');
  assert.equal(await page.evaluate(() => window.__qa.spoken.at(-1).text), 'Isolated test translation fixture');
  const panelSurfaces = await page.evaluate(() => {
    const source = getComputedStyle(document.querySelector('.source-column'));
    const result = getComputedStyle(document.querySelector('.result-card'));
    return { source: { radius: source.borderRadius, background: source.backgroundColor, width: source.borderTopWidth },
      result: { radius: result.borderRadius, background: result.backgroundColor, width: result.borderTopWidth } };
  });
  assert.deepEqual(panelSurfaces.result, panelSurfaces.source);
  await page.locator('.app-shell').screenshot({ path: 'test-results/streaming-result-actions.png' });
  await page.setViewportSize({ width: 420, height: 820 });
  await page.evaluate(() => { document.documentElement.dataset.theme = 'dark'; });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  for (const label of ['复制译文', '朗读译文']) assert.equal(await page.getByRole('button', { name: label, exact: true }).isVisible(), true);
  await page.locator('.app-shell').screenshot({ path: 'test-results/streaming-result-actions-dark-narrow.png' });

  // The wider default is illustrated with synthetic long prose, never an API
  // account or user capture. Both themes retain visible result actions.
  await page.setViewportSize({ width: 680, height: 820 });
  await page.evaluate(() => {
    document.documentElement.dataset.theme = 'light';
    window.__qa.translationResultText = '选中文字后按下翻译快捷键，即可在当前应用上方查看译文。窗口默认提供更舒适的阅读宽度，也可以从左右边缘拖动调整。后续译文会按照用户选择的宽度重新排版，复制和朗读按钮始终位于正文下方。';
  });
  await page.locator('#source-text').fill('Select text and press the translation shortcut to read the result above the current application. The popup starts at a comfortable reading width, and either side can be dragged to resize it. Later results follow your chosen width while copy and pronunciation remain visible below the translation.');
  await page.locator('#translate-button').click();
  await page.getByText('选中文字后按下翻译快捷键，即可在当前应用上方查看译文。窗口默认提供更舒适的阅读宽度，也可以从左右边缘拖动调整。后续译文会按照用户选择的宽度重新排版，复制和朗读按钮始终位于正文下方。', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.locator('.app-shell').screenshot({ path: 'test-results/popup-width-680-light.png' });
  await page.evaluate(() => { document.documentElement.dataset.theme = 'dark'; });
  for (const label of ['复制译文', '朗读译文']) assert.equal(await page.getByRole('button', { name: label, exact: true }).isVisible(), true);
  await page.locator('.app-shell').screenshot({ path: 'test-results/popup-width-680-dark.png' });
  await page.evaluate(() => { delete window.__qa.translationResultText; });

  // Opening settings uses passive cache facts. Unread/blocked credentials must
  // not appear missing, unlock automatically, or block an explicitly selected
  // OCR service merely because its OS credential has not been read this run.
  await page.setViewportSize({ width: 800, height: 900 });
  await goView('settings');
  const credentialBaseline = await page.evaluate(() => ({ reads: window.__qa.credentialReadCalls,
    translations: window.__qa.translationRequests.length, translationTests: window.__qa.translationTestCalls,
    ocrTests: window.__qa.ocrTestCalls, keyWrites: window.__qa.keyCalls + window.__qa.ocrKeyCalls,
    providerName: window.__qa.settings.providers[0].name }));
  const refreshCachedSettings = async () => {
    await page.locator('#save-history').setChecked(!await page.locator('#save-history').isChecked());
    await page.waitForFunction(() => window.__qa.settings.saveHistory === document.querySelector('#save-history').checked);
  };
  const translationCredentialRow = page.locator('#provider-list .provider-row').filter({ has: page.locator('.provider-title', { hasText: credentialBaseline.providerName }) });
  await page.evaluate(() => window.__qa.setCredentialState(window.__qa.settings.providers[0], 'unloaded'));
  await refreshCachedSettings();
  await translationCredentialRow.getByText('· 凭据未读取', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.settings.providers[0].hasKey), false);
  await translationCredentialRow.getByRole('button', { name: '编辑', exact: true }).click();
  assert.match(await page.locator('#provider-key').getAttribute('placeholder'), /尚未读取.*留空保留/);
  assert.match(await page.locator('#provider-key-help').textContent(), /打开设置不会读取.*不会删除已有凭据/);
  assert.equal(await page.locator('#provider-key').inputValue(), '');
  await page.locator('#provider-url').fill('https://changed-credential-origin.invalid/v1');
  assert.match(await page.locator('#provider-key-help').textContent(), /原密钥不会复用/);
  assert.doesNotMatch(await page.locator('#provider-key').getAttribute('placeholder'), /尚未读取|已保存/);
  await page.locator('#cancel-provider-dialog').click();
  await page.evaluate(() => window.__qa.setCredentialState(window.__qa.settings.providers[0], 'blocked'));
  await refreshCachedSettings();
  await translationCredentialRow.getByText('· 凭据读取受阻', { exact: true }).waitFor();
  await translationCredentialRow.getByRole('button', { name: '编辑', exact: true }).click();
  assert.match(await page.locator('#provider-key').getAttribute('placeholder'), /读取受阻.*留空保留/);
  assert.match(await page.locator('#provider-key-help').textContent(), /测试连接.*不会删除已有凭据/);
  await page.locator('#cancel-provider-dialog').click();
  assert.equal(await page.evaluate(() => window.__qa.credentialReadCalls), credentialBaseline.reads);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), credentialBaseline.translations);
  assert.equal(await page.evaluate(() => window.__qa.keyCalls + window.__qa.ocrKeyCalls), credentialBaseline.keyWrites);
  const readsBeforeExplicitTest = await page.evaluate(() => window.__qa.settingsReads);
  await translationCredentialRow.getByRole('button', { name: '测试连接', exact: true }).click();
  await translationCredentialRow.getByText('· 凭据已就绪', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.credentialReadCalls), credentialBaseline.reads + 1);
  assert.equal(await page.evaluate(() => window.__qa.translationTestCalls), credentialBaseline.translationTests + 1);
  assert.equal(await page.evaluate(() => window.__qa.settingsReads), readsBeforeExplicitTest + 1);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), credentialBaseline.translations);

  await page.locator('#add-ocr-provider').click();
  await page.locator('#ocr-provider-name').fill('QA unread native OCR');
  await page.locator('#save-ocr-provider').click();
  await page.locator('#ocr-provider-dialog').waitFor({ state: 'hidden' });
  const unreadOcrId = await page.evaluate(() => {
    const provider = window.__qa.settings.ocrProviders.find(item => item.name === 'QA unread native OCR');
    window.__qa.setCredentialState(provider, 'unloaded'); return provider.id;
  });
  await refreshCachedSettings();
  const unreadOcrRow = page.locator('#ocr-provider-list .provider-row').filter({ hasText: 'QA unread native OCR' });
  await unreadOcrRow.getByText('· 凭据未读取', { exact: true }).waitFor();
  await page.locator('#active-ocr-provider').selectOption(unreadOcrId);
  await page.waitForFunction((id) => window.__qa.settings.activeOcrProviderId === id, unreadOcrId);
  await unreadOcrRow.getByRole('button', { name: '编辑 OCR QA unread native OCR', exact: true }).click();
  assert.match(await page.locator('#ocr-protocol-notice').textContent(), /尚未|不会读取系统凭据/);
  assert.match(await page.locator('#ocr-protocol-notice').textContent(), /不会删除已有凭据/);
  assert.equal(await page.locator('#ocr-baidu-api-key').inputValue(), '');
  assert.equal(await page.locator('#ocr-baidu-secret-key').inputValue(), '');
  await page.locator('#cancel-ocr-provider-dialog').click();
  assert.equal(await page.evaluate(() => window.__qa.credentialReadCalls), credentialBaseline.reads + 1);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), credentialBaseline.translations);
  await page.locator('#active-ocr-provider').selectOption('');
  await page.waitForFunction(() => window.__qa.settings.activeOcrProviderId === null);
  await page.evaluate((id) => window.__qa.setCredentialState(window.__qa.settings.ocrProviders.find(item => item.id === id), 'missing'), unreadOcrId);
  await refreshCachedSettings();
  await unreadOcrRow.getByText('· 未配置凭据', { exact: true }).waitFor();
  await page.locator('#active-ocr-provider').selectOption(unreadOcrId);
  await page.getByText('此 OCR 服务尚未配置完整凭据，请先编辑并保存密钥。', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.settings.activeOcrProviderId), null);
  await page.evaluate((id) => window.__qa.setCredentialState(window.__qa.settings.ocrProviders.find(item => item.id === id), 'unloaded'), unreadOcrId);
  await refreshCachedSettings();
  await unreadOcrRow.getByRole('button', { name: '测试连接', exact: true }).click();
  await unreadOcrRow.getByText('· 凭据已就绪', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.credentialReadCalls), credentialBaseline.reads + 2);
  assert.equal(await page.evaluate(() => window.__qa.ocrTestCalls), credentialBaseline.ocrTests + 1);
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), credentialBaseline.translations);
  assert.deepEqual(errors, []);
  // Result setup actions only navigate. They never authorize, download, read
  // credentials or silently retry; preparation remains a separate explicit act.
  for (const [platform, kind, appleAction] of [
    ['mac', 'system', true], ['windows', 'offline', false],
    ['windows', 'system', false], ['mac', 'openai', false],
  ]) {
    const url = new URL(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
    url.searchParams.set('translationSetupFixture', kind);
    if (platform === 'windows') url.searchParams.set('windowsSelectionFixture', '1');
    await page.goto(url.href);
    await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
    await page.evaluate((kind) => {
      window.__qa.translationResultError = kind === 'offline'
        ? 'Synthetic offline resources unavailable'
        : 'SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: Synthetic language packs not installed';
      window.__qa.translationResultLanguages = { sourceLanguage: 'zh-Hant', targetLanguage: 'en' };
    }, kind);
    await page.locator('#source-text').fill('Generated translation setup fixture');
    await page.locator('#source-text').press('Enter');
    const setup = page.locator('.result-setup');
    await setup.waitFor({ state: 'visible' });
    assert.equal(await setup.textContent(), appleAction ? '准备系统翻译' : '打开翻译设置');
    assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), []);
    const reads = await page.evaluate(() => ({ translation: window.__qa.credentialReadCalls, ocr: window.__qa.ocrKeyCalls, requests: window.__qa.translationRequests.length }));
    const preferences = await page.evaluate(() => ({ source: window.__qa.settings.sourceLanguage, target: window.__qa.settings.targetLanguage, writes: window.__qa.saveCalls }));
    await page.evaluate(() => { window.__qa.systemStatusCalls = []; });
    await setup.click();
    await page.waitForFunction(() => document.body.dataset.view === 'settings');
    assert.equal(await page.locator('#app-version').textContent(), 'EchoLingo 9.8.7-beta.6');
    assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), []);
    assert.deepEqual(await page.evaluate(() => ({ translation: window.__qa.credentialReadCalls, ocr: window.__qa.ocrKeyCalls, requests: window.__qa.translationRequests.length })), reads);
    assert.deepEqual(await page.evaluate(() => ({ source: window.__qa.settings.sourceLanguage, target: window.__qa.settings.targetLanguage, writes: window.__qa.saveCalls })), preferences);
    assert.deepEqual(await page.evaluate(() => window.__qa.systemStatusCalls), [appleAction ? { sourceLanguage: 'zh-Hant', targetLanguage: 'en' } : { sourceLanguage: 'en', targetLanguage: 'zh-Hans' }]);
    assert.equal(await page.locator('#system-translation-source').inputValue(), appleAction ? 'zh-Hant' : 'en');
    assert.equal(await page.locator('#system-translation-target').inputValue(), appleAction ? 'en' : 'zh-Hans');
    if (appleAction) {
      assert.equal(await page.locator('#system-translation-setup').getAttribute('open'), '');
      await page.waitForFunction(() => !document.querySelector('#prepare-system-translation').disabled);
      await page.locator('#prepare-system-translation').click();
      await page.waitForFunction(() => window.__qa.systemPrepareCalls.length === 1);
      assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), [{ sourceLanguage: 'zh-Hant', targetLanguage: 'en' }]);
    }
  }
  for (const pair of [null, { sourceLanguage: 'auto', targetLanguage: 'en' }, { sourceLanguage: 'xx-unknown', targetLanguage: 'en' }, { sourceLanguage: 'en', targetLanguage: 'en' }, { sourceLanguage: 7, targetLanguage: 'en' }]) {
    const url = new URL(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
    url.searchParams.set('translationSetupFixture', 'system');
    await page.goto(url.href);
    await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
    await goView('settings');
    await page.locator('#system-translation-source').selectOption('fr');
    await page.locator('#system-translation-target').selectOption('de');
    await goView('translate');
    await page.evaluate((pair) => { window.__qa.translationResultError = 'SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: fixture'; window.__qa.translationResultLanguages = pair; }, pair);
    await page.locator('#source-text').fill('Generated invalid setup metadata');
    await page.locator('#source-text').press('Enter');
    await page.locator('.result-setup').waitFor({ state: 'visible' });
    const baseline = await page.evaluate(() => ({ translations: window.__qa.translationRequests.length, keys: window.__qa.credentialReadCalls, writes: window.__qa.saveCalls }));
    await page.evaluate(() => { window.__qa.systemStatusCalls = []; });
    await page.locator('.result-setup').click();
    assert.equal(await page.locator('#system-translation-source').inputValue(), 'fr');
    assert.equal(await page.locator('#system-translation-target').inputValue(), 'de');
    assert.deepEqual(await page.evaluate(() => window.__qa.systemStatusCalls), [{ sourceLanguage: 'fr', targetLanguage: 'de' }]);
    assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), []);
    assert.deepEqual(await page.evaluate(() => ({ translations: window.__qa.translationRequests.length, keys: window.__qa.credentialReadCalls, writes: window.__qa.saveCalls })), baseline);
  }
  {
    const url = new URL(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
    url.searchParams.set('translationSetupFixture', 'system');
    await page.goto(url.href);
    await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
    await goView('settings');
    await page.locator('#system-translation-source').selectOption('fr');
    await page.locator('#system-translation-target').selectOption('de');
    await page.waitForFunction(() => !document.querySelector('#prepare-system-translation').disabled);
    await page.evaluate(() => { window.__qa.holdSystemPreparation = true; });
    await page.locator('#prepare-system-translation').click();
    await page.waitForFunction(() => window.__qa.systemPrepareCalls.length === 1);
    await goView('translate');
    await page.evaluate(() => { window.__qa.translationResultError = 'SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: fixture'; window.__qa.translationResultLanguages = { sourceLanguage: 'zh-Hant', targetLanguage: 'en' }; });
    await page.locator('#source-text').fill('Generated pending preparation');
    await page.locator('#source-text').press('Enter');
    await page.locator('.result-setup').waitFor({ state: 'visible' });
    const statusReads = await page.evaluate(() => window.__qa.systemStatusCalls.length);
    await page.locator('.result-setup').click();
    await page.getByText('系统翻译正在准备，请完成或取消后再选择该语言对。', { exact: true }).waitFor();
    assert.equal(await page.locator('#system-translation-source').inputValue(), 'fr');
    assert.equal(await page.locator('#system-translation-target').inputValue(), 'de');
    assert.equal(await page.locator('#system-translation-source').isDisabled(), true);
    assert.equal(await page.evaluate(() => window.__qa.systemStatusCalls.length), statusReads);
    assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), [{ sourceLanguage: 'fr', targetLanguage: 'de' }]);
    await page.evaluate(() => { window.__qa.releaseSystemPreparation(); });
    await page.waitForFunction(() => document.querySelector('#system-translation-status').textContent === 'QA 本机语言包已就绪');
  }
  assert.deepEqual(errors, []);
  console.log('PASS: full runtime version visible; result error settings actions use request provider kind plus platform, navigate without preparation/credentials/retry, and only explicit Apple preparation downloads the selected pair. Fake IPC only.');
  // A registered main key can be consumed by the OS, and its DOM modifier
  // keyups can be absent too. Observe this handoff separately from the
  // held/null/stale/releasedEvidence cases above: a matching native release
  // explicitly says all modifiers are up. This is fake IPC evidence only,
  // not proof of the cause of any particular Windows runtime failure.
  // A fresh page reruns the existing mock bootstrap and isolates this probe
  // from the earlier clock override and intentionally delayed IPC replies.
  await page.goto(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
  await goView('settings');
  // Use the existing Settings save mock to configure this exact native combo,
  // then leave a different draft so completing the recording must change it.
  await page.locator('#shortcut-selection').fill('Ctrl+Alt+Shift+F9');
  await page.locator('#save-shortcuts').click();
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === 'Ctrl+Alt+Shift+F9');
  await page.locator('#shortcut-selection').fill('Ctrl+Alt+Shift+F8');
  await page.locator('[data-shortcut-record="selection"]').click();
  const releaseProbeReady = await page.waitForFunction(() =>
    window.__qa.shortcutLeases.at(-1)?.active === true
    && document.querySelector('#shortcut-feedback').textContent.startsWith('请按快捷键'),
    null, { timeout: 5000 }).then(() => true, error => {
      if (error.name !== 'TimeoutError') throw error;
      return false;
    });
  const releaseProbeReadyState = await page.evaluate(() => ({
    value: document.querySelector('#shortcut-selection').value,
    feedback: document.querySelector('#shortcut-feedback').textContent,
    lease: { ...window.__qa.shortcutLeases.at(-1) },
    recordButtonPressed: document.querySelector('[data-shortcut-record="selection"]').getAttribute('aria-pressed'),
    inputReadOnly: document.querySelector('#shortcut-selection').readOnly,
    focusedId: document.activeElement?.id,
    heldBegin: window.__qa.holdShortcutBegin,
    heldEnd: window.__qa.holdShortcutEnd,
  }));
  console.log(`SHORTCUT_RELEASE_PRECONDITION ${JSON.stringify({ ready: releaseProbeReady, observed: releaseProbeReadyState })}`);
  assert.equal(releaseProbeReady, true, `Regression probe requires an active ready lease: ${JSON.stringify(releaseProbeReadyState)}`);
  for (const value of [
    { key: 'Control', code: 'ControlLeft', ctrlKey: true },
    { key: 'Alt', code: 'AltLeft', ctrlKey: true, altKey: true },
    { key: 'Shift', code: 'ShiftLeft', ctrlKey: true, altKey: true, shiftKey: true },
  ]) await page.locator('#shortcut-selection').dispatchEvent('keydown', value);
  await page.evaluate(() => {
    const leaseId = window.__qa.shortcutLeases.at(-1).id;
    window.__qa.emit('shortcut-recorded', { leaseId, shortcut: 'Ctrl+Alt+Shift+F9', modifiersDown: 0 });
  });
  let releaseProbeCompleted = false;
  try {
    // Same five-second completion expectation as the actual Windows recorder
    // fixture, before its existing fourteen-second cancellation deadline.
    await page.waitForFunction(() => document.querySelector('#shortcut-selection').value === 'Ctrl+Alt+Shift+F9'
      && document.querySelector('#shortcut-feedback').textContent.startsWith('快捷键已保存并立即生效')
      && window.__qa.shortcutLeases.at(-1)?.active === false, null, { timeout: 5000 });
    releaseProbeCompleted = true;
  } catch (error) { if (error.name !== 'TimeoutError') throw error; }
  const releaseProbeObserved = await page.evaluate(() => ({
    value: document.querySelector('#shortcut-selection').value,
    feedback: document.querySelector('#shortcut-feedback').textContent,
    lease: { ...window.__qa.shortcutLeases.at(-1) },
    recordButtonPressed: document.querySelector('[data-shortcut-record="selection"]').getAttribute('aria-pressed'),
    inputReadOnly: document.querySelector('#shortcut-selection').readOnly,
  }));
  console.log(`SHORTCUT_RELEASE_REGRESSION ${JSON.stringify({ scope: 'isolated DOM and matching native-event mock; not a Windows root-cause claim', expectationMilliseconds: 5000, completed: releaseProbeCompleted, observed: releaseProbeObserved })}`);
  assert.equal(releaseProbeCompleted, true, `A matching native all-up release must complete without DOM keyups: ${JSON.stringify(releaseProbeObserved)}`);
  // Native modifier evidence clears only modifier bookkeeping. An unrelated
  // ordinary key still needs its own DOM release before the candidate commits.
  const beginReleaseBoundary = async () => {
    await page.locator('#shortcut-selection').fill('Ctrl+Alt+Shift+F8');
    await page.locator('[data-shortcut-record="selection"]').click();
    await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === true
      && document.querySelector('#shortcut-feedback').textContent.startsWith('请按快捷键'), null, { timeout: 5000 });
  };
  const emitReleaseSnapshot = async (modifiersDown) => page.evaluate((mask) => {
    const leaseId = window.__qa.shortcutLeases.at(-1).id;
    window.__qa.emit('shortcut-recorded', { leaseId, shortcut: 'Ctrl+Alt+Shift+F9', modifiersDown: mask });
  }, modifiersDown);
  const releaseBoundaryState = async () => page.evaluate(() => ({
    value: document.querySelector('#shortcut-selection').value,
    feedback: document.querySelector('#shortcut-feedback').textContent,
    lease: { ...window.__qa.shortcutLeases.at(-1) },
    inputReadOnly: document.querySelector('#shortcut-selection').readOnly,
  }));
  const requireReleaseCompletion = async () => {
    await page.waitForFunction(() => document.querySelector('#shortcut-selection').value === 'Ctrl+Alt+Shift+F9'
      && document.querySelector('#shortcut-feedback').textContent.startsWith('快捷键已保存并立即生效')
      && window.__qa.shortcutLeases.at(-1)?.active === false, null, { timeout: 5000 });
    return releaseBoundaryState();
  };
  const releaseBoundaryResults = [];
  await beginReleaseBoundary();
  // A plain X is invalid as a candidate, but remains a real held ordinary key.
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'x', code: 'KeyX' });
  for (const value of [
    { key: 'Control', code: 'ControlLeft', ctrlKey: true },
    { key: 'Alt', code: 'AltLeft', ctrlKey: true, altKey: true },
    { key: 'Shift', code: 'ShiftLeft', ctrlKey: true, altKey: true, shiftKey: true },
  ]) await page.locator('#shortcut-selection').dispatchEvent('keydown', value);
  await emitReleaseSnapshot(0);
  const unrelatedHeld = await releaseBoundaryState();
  assert.equal(unrelatedHeld.value, 'Ctrl+Alt+Shift+F8');
  assert.equal(unrelatedHeld.lease.active, true);
  assert.equal(unrelatedHeld.inputReadOnly, true);
  assert.match(unrelatedHeld.feedback, /^已记录 Ctrl\+Alt\+Shift\+F9/);
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'x', code: 'KeyX' });
  releaseBoundaryResults.push({ case: 'unrelated ordinary key stays held until its own up', pending: unrelatedHeld, completed: await requireReleaseCompletion() });

  // A partial native snapshot reports Ctrl still down and Alt already up;
  // missing Alt DOM keyup must not block the later actual Ctrl release.
  await beginReleaseBoundary();
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'Control', code: 'ControlLeft', ctrlKey: true });
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'Alt', code: 'AltLeft', ctrlKey: true, altKey: true });
  await emitReleaseSnapshot(1);
  const controlHeld = await releaseBoundaryState();
  assert.equal(controlHeld.value, 'Ctrl+Alt+Shift+F8');
  assert.equal(controlHeld.lease.active, true);
  assert.equal(controlHeld.inputReadOnly, true);
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Control', code: 'ControlLeft' });
  releaseBoundaryResults.push({ case: 'partial native Ctrl mask waits for Ctrl up', pending: controlHeld, completed: await requireReleaseCompletion() });

  // The later Alt keyup says every modifier is up even though Ctrl's DOM up
  // was lost. That newer DOM evidence wins a delayed native Ctrl-held snapshot.
  await beginReleaseBoundary();
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'Control', code: 'ControlLeft', ctrlKey: true });
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'Alt', code: 'AltLeft', ctrlKey: true, altKey: true });
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Alt', code: 'AltLeft' });
  const domReleased = await releaseBoundaryState();
  assert.equal(domReleased.value, 'Ctrl+Alt+Shift+F8');
  assert.equal(domReleased.lease.active, true);
  await emitReleaseSnapshot(1);
  releaseBoundaryResults.push({ case: 'newer DOM all-up beats stale native Ctrl-held snapshot', pending: domReleased, completed: await requireReleaseCompletion() });
  console.log(`SHORTCUT_RELEASE_BOUNDARIES ${JSON.stringify({ scope: 'isolated DOM and existing fake IPC only', cases: releaseBoundaryResults })}`);
  assert.deepEqual(errors, []);
  console.log('PASS: native input focus events require exact backend-verified presentation metadata; an observed epoch keeps its original intent baseline across duplicate announcements, edits and navigation; fresh explicit input works while visible or in management; stale complete events, missing/malformed/future payloads and delayed verification cannot rebind focus; hidden Alt+A works with either presentation-event order. Fake IPC only.');
  console.log('PASS: accepted popup acknowledgments, explicit input animation frames and modal queues cannot revive focus after a newer selection epoch, edit or management-view roundtrip; current empty-selection typing and current input focus remain available. Isolated DOM/IPC only, not a native WPS root-cause claim.');
  console.log('PASS: repeated pinned capture epochs keep completed source/result DOM visible through cancel/no-text/OCR/permission errors; successful OCR replaces source and auto-translates without a modeled hide/reveal; pin remains active; stale source/presentation/progress cannot overwrite; in-flight partial results are cancelled and removed. Fake IPC only, no real capture or native visibility pass.');
  console.log('PASS: marked visible-popup OCR updates cannot navigate away from settings/history, overwrite newer edits or Alt+A typing, or cancel a newer manual translation; accepted marked capture still auto-translates; ordinary unmarked source workflows remain covered.');
  console.log('PASS: show_popup IPC explicitly requests reuseVisiblePopup=false for ordinary blank/input/selection, including an already visible pinned popup; only marked pinned OCR sends true. Payload dispatch only; no native physical raise/z-order acceptance is claimed.');
  console.log('PASS: popup left/right pointer-captured width requests; native Windows resize dispatch fixture; pin/input/toolbar drag isolation; bounded actual viewport width participates in same-height680→850 layout fits; later height fits retain850; coalesced pending resize invalidated by hide/epoch; management edges hidden/inert;680px light/dark long-prose screenshots inspected separately.');
  // Windows-only choice: legacy payload defaults to compatibility, saves only
  // the chosen field, survives management navigation, and rolls back failed saves.
  const windowsSelectionUrl = new URL(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  windowsSelectionUrl.searchParams.set('windowsSelectionFixture', '1');
  await page.goto(windowsSelectionUrl.toString());
  await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
  await goView('settings');
  assert.equal(await page.locator('#windows-selection-settings').isVisible(), true);
  assert.equal(await page.locator('#windows-selection-strategy').inputValue(), 'copy');
  const beforeStrategySave = await page.evaluate(() => structuredClone(window.__qa.settings));
  await page.locator('#windows-selection-strategy').selectOption('auto');
  await page.waitForFunction(() => window.__qa.settings.windowsSelectionStrategy === 'auto');
  assert.deepEqual(await page.evaluate(() => { const value = structuredClone(window.__qa.settings); delete value.windowsSelectionStrategy; return value; }), beforeStrategySave);
  await goView('translate'); await goView('settings');
  assert.equal(await page.locator('#windows-selection-strategy').inputValue(), 'auto');
  await page.evaluate(() => { window.__qa.failSave = true; });
  const failedStrategySaves = await page.evaluate(() => window.__qa.saveCalls);
  await page.locator('#windows-selection-strategy').selectOption('copy');
  await page.waitForFunction((count) => window.__qa.saveCalls > count && document.querySelector('#windows-selection-strategy').value === 'auto', failedStrategySaves);
  assert.equal(await page.evaluate(() => window.__qa.settings.windowsSelectionStrategy), 'auto');
  await page.evaluate(() => { window.__qa.failSave = false; });
  await page.locator('#windows-selection-strategy').selectOption('copy');
  await page.waitForFunction(() => window.__qa.settings.windowsSelectionStrategy === 'copy');
  // Windows side buttons share the recorder's release/cancel/autosave path.
  // Synthetic DOM pointers prove editor handling, not a native global hook.
  const beginMouseRecording = async (action = 'selection') => {
    await page.locator(`[data-shortcut-record="${action}"]`).click();
    await page.locator('#shortcut-feedback').getByText('请按快捷键', { exact: false }).waitFor();
  };
  const pointer = async (type, button, extra = {}) => page.evaluate(({ type, button, extra }) => {
    const target = document.querySelector('#shortcut-selection');
    const event = new PointerEvent(type, { bubbles: true, cancelable: true, pointerType: 'mouse', pointerId: 9, button, ...extra });
    return !target.dispatchEvent(event);
  }, { type, button, extra });
  await beginMouseRecording();
  const beforeMouseSave = await page.evaluate(() => window.__qa.saveCalls);
  assert.equal(await pointer('pointerdown', 0), false);
  assert.equal(await pointer('pointerup', 0), false);
  assert.equal(await pointer('pointerdown', 1), false);
  assert.equal(await pointer('pointerup', 1), false);
  assert.equal(await pointer('pointerdown', 3), true);
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeMouseSave);
  const releaseAndAuxclick = await page.evaluate(() => {
    const input = document.querySelector('#shortcut-selection');
    const up = new PointerEvent('pointerup', { bubbles: true, cancelable: true, pointerType: 'mouse', pointerId: 9, button: 3 });
    const aux = new MouseEvent('auxclick', { bubbles: true, cancelable: true, button: 3 });
    return { upBlocked: !input.dispatchEvent(up), auxBlocked: !input.dispatchEvent(aux) };
  });
  assert.deepEqual(releaseAndAuxclick, { upBlocked: true, auxBlocked: true });
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === 'MouseX1');
  await page.locator('#shortcut-feedback').getByText('快捷键已保存并立即生效', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeMouseSave + 1);
  assert.deepEqual(await page.evaluate(() => window.__qa.shortcutRetryActions.at(-1)), ['selection']);
  assert.equal(await pointer('pointerdown', 3), false);
  assert.equal(await pointer('pointerup', 3), false);
  await beginMouseRecording();
  const beforeNativeMouseSave = await page.evaluate(() => window.__qa.saveCalls);
  assert.equal(await pointer('pointerdown', 4), true);
  await page.evaluate(() => window.__qa.emit('shortcut-recorded', { leaseId: window.__qa.shortcutLeases.at(-1).id, shortcut: 'MouseX2', modifiersDown: 0 }));
  await page.waitForFunction(() => window.__qa.settings.shortcuts.selection === 'MouseX2');
  await page.locator('#shortcut-feedback').getByText('快捷键已保存并立即生效', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeNativeMouseSave + 1);
  // The native release can consume DOM pointerup. Its completed pairing must
  // not leave a stale frontend side-button marker that swallows another up.
  assert.equal(await pointer('pointerup', 4), false);
  await beginMouseRecording();
  const beforeModifiedMouseSave = await page.evaluate(() => window.__qa.saveCalls);
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'Control', code: 'ControlLeft', ctrlKey: true });
  assert.equal(await pointer('pointerdown', 4, { ctrlKey: true }), true);
  assert.equal(await pointer('pointerup', 4, { ctrlKey: true }), true);
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeModifiedMouseSave);
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Control', code: 'ControlLeft' });
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.selection), 'MouseX2');
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeModifiedMouseSave);
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === false);
  await beginMouseRecording();
  const beforeCancelledMouseSave = await page.evaluate(() => window.__qa.saveCalls);
  assert.equal(await pointer('pointerdown', 3), true);
  await page.locator('#shortcut-selection').dispatchEvent('keydown', { key: 'Escape', code: 'Escape' });
  await page.locator('#shortcut-selection').dispatchEvent('keyup', { key: 'Escape', code: 'Escape' });
  assert.equal(await pointer('pointerup', 3), true);
  await page.waitForFunction(() => window.__qa.shortcutLeases.at(-1)?.active === false);
  assert.equal(await page.evaluate(() => window.__qa.settings.shortcuts.selection), 'MouseX2');
  assert.equal(await page.evaluate(() => window.__qa.saveCalls), beforeCancelledMouseSave);
  console.log('PASS: completed recording automatically saves one field once, preserves unrelated manual drafts, reports failed saves without replacing committed bindings, cancels queued writes on navigation, and records Windows side-button DOM release/cancel without intercepting ordinary buttons. Fake IPC/pointer events only.');
  await goView('translate');
  await page.locator('#source-text').fill('English translation font fixture');
  await page.locator('#source-text').press('Enter');
  await page.getByText('Isolated test translation fixture', { exact: true }).waitFor();
  const readingFonts = await page.evaluate(() => ({
    result: getComputedStyle(document.querySelector('.result-text')).fontFamily,
    source: getComputedStyle(document.querySelector('#source-text')).fontFamily,
    action: getComputedStyle(document.querySelector('.result-actions button')).fontFamily,
  }));
  assert.match(readingFonts.result, /^"?Times New Roman"?,/);
  assert.match(readingFonts.result, /SimSun/);
  assert.match(readingFonts.source, /^SimSun,/);
  assert.doesNotMatch(readingFonts.action, /Times New Roman/);
  console.log('PASS: translated Latin font prefers installed Times New Roman; Windows retains SimSun CJK fallback/source and UI action typography. Computed CSS only, not physical font rendering.');
  for (const platform of ['mac', 'windows']) {
    const url = new URL(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
    if (platform === 'windows') url.searchParams.set('windowsSelectionFixture', '1');
    await page.goto(url.href);
    await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪' && window.__qa.diagnosticCalls.length >= 1);
    await goView('settings');
    await page.locator('.diagnostics-details > summary').click();
    const diagnosticCopy = page.locator('#copy-diagnostics');
    assert.equal(await diagnosticCopy.isDisabled(), true);
    assert.equal(await page.locator('#diagnostics-output').isHidden(), true);
    const diagnosticText = `平台：${platform === 'mac' ? 'macOS' : 'Windows'}\n权限检查：完成\n\n快捷键：Alt+D / Alt+S\n状态：仅测试元数据，不含原文或密钥。`;
    const diagnosticBefore = await page.evaluate((report) => {
      window.__qa.diagnosticReport = report; window.__qa.holdDiagnostics = true;
      return { calls: window.__qa.diagnosticCalls.length, copies: window.__qa.copies.length,
        credentialReads: window.__qa.credentialReadCalls, keyWrites: window.__qa.keyCalls,
        ocrKeyWrites: window.__qa.ocrKeyCalls, translations: window.__qa.translationRequests.length };
    }, diagnosticText);
    await page.locator('#run-diagnostics').click();
    await page.waitForFunction((count) => window.__qa.diagnosticCalls.length === count + 1, diagnosticBefore.calls);
    assert.equal(await page.locator('#diagnostics-output').textContent(), '正在检查…');
    assert.equal(await diagnosticCopy.isDisabled(), true);
    await diagnosticCopy.dispatchEvent('click');
    assert.equal(await page.evaluate(() => window.__qa.copies.length), diagnosticBefore.copies);
    await page.evaluate(() => { window.__qa.holdDiagnostics = false; window.__qa.releaseDiagnostics(); });
    await page.waitForFunction(() => !document.querySelector('#copy-diagnostics').disabled);
    assert.equal(await page.locator('#diagnostics-output').textContent(), diagnosticText);
    await page.evaluate(() => { window.__qa.diagnosticReport = '尚未运行的下一份诊断'; });
    await diagnosticCopy.click();
    assert.equal(await page.evaluate(() => window.__qa.copies.at(-1)), diagnosticText);
    await diagnosticCopy.click();
    assert.deepEqual(await page.evaluate(() => window.__qa.copies.slice(-2)), [diagnosticText, diagnosticText]);
    assert.deepEqual(await page.evaluate(() => ({ calls: window.__qa.diagnosticCalls.length,
      credentialReads: window.__qa.credentialReadCalls, keyWrites: window.__qa.keyCalls,
      ocrKeyWrites: window.__qa.ocrKeyCalls, translations: window.__qa.translationRequests.length })),
      { calls: diagnosticBefore.calls + 1, credentialReads: diagnosticBefore.credentialReads,
        keyWrites: diagnosticBefore.keyWrites, ocrKeyWrites: diagnosticBefore.ocrKeyWrites, translations: diagnosticBefore.translations });
    await page.evaluate(() => { window.__qa.diagnosticReport = ''; });
    await page.locator('#run-diagnostics').click();
    await page.waitForFunction(() => !document.querySelector('#run-diagnostics').disabled);
    assert.equal(await page.locator('#diagnostics-output').textContent(), '');
    assert.equal(await diagnosticCopy.isDisabled(), true);
    await diagnosticCopy.dispatchEvent('click');
    assert.equal(await page.evaluate(() => window.__qa.copies.length), diagnosticBefore.copies + 2);
    await goView('translate');
    const preservedText = '中文段落保留原有换行，输入和译文使用相同的阅读对齐方式。\n\nconst values = [1, 2, 3];\n  return values.map(value => value + 1);\nhttps://example.invalid/' + 'LongEnglishIdentifier'.repeat(16);
    await page.evaluate((text) => { window.__qa.translationResultText = text; }, preservedText);
    await page.locator('#source-text').fill(preservedText);
    await page.locator('#source-text').press('Enter');
    await page.waitForFunction((text) => document.querySelector('.result-text')?.textContent === text, preservedText);
    assert.equal(await page.locator('#source-text').inputValue(), preservedText);
    const alignment = await page.evaluate(() => {
      const read = (element) => {
        const style = getComputedStyle(element);
        return { align: style.textAlign, last: style.textAlignLast, whitespace: style.whiteSpace,
          wordBreak: style.wordBreak, wrap: style.overflowWrap, horizontalOverflow: element.scrollWidth > element.clientWidth + 1 };
      };
      return { source: read(document.querySelector('#source-text')), result: read(document.querySelector('.result-text')),
        actions: [...document.querySelectorAll('.result-actions button, .source-actions button')].map(element => getComputedStyle(element).textAlign) };
    });
    for (const textStyle of [alignment.source, alignment.result]) {
      assert.equal(textStyle.align, 'justify'); assert.equal(textStyle.last, 'left');
      assert.equal(textStyle.whitespace, 'pre-wrap'); assert.equal(textStyle.wordBreak, 'normal');
      assert.equal(textStyle.wrap, 'anywhere'); assert.equal(textStyle.horizontalOverflow, false);
    }
    assert.equal(alignment.actions.includes('justify'), false);
    await page.locator('#copy-source').click();
    await page.getByRole('button', { name: '复制译文', exact: true }).click();
    assert.deepEqual(await page.evaluate(() => window.__qa.copies.slice(-2)), [preservedText, preservedText]);
  }
  assert.deepEqual(errors, []);
  console.log('PASS: macOS/Windows shared UI copies only the displayed Chinese multiline diagnostics without rerunning checks/credentials/translation; absent, pending and empty reports stay disabled. Source/result justify with left final lines, preserved code/URL/long-token text and independent action styling. Mock IPC and computed CSS only.');
  await page.goto(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
  await goView('settings');
  assert.equal(await page.locator('#windows-selection-settings').isHidden(), true);
  assert.deepEqual(errors, []);
  console.log('PASS: isolated Windows strategy settings default compatibility for old payloads; strict and copy save without changing providers/shortcuts/theme, navigation retains strict, failed save rolls back, and macOS hides the setting. Fake IPC only.');
  const retryUrl = new URL(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  retryUrl.searchParams.set('translationRetryFixture', '1');
  await page.goto(retryUrl.href);
  await page.waitForFunction(() => document.querySelector('#footer-status')?.textContent === '准备就绪');
  await page.evaluate(() => { window.__qa.translationResults = [
    { providerId: 'qa-service', providerName: 'QA IPC fixture', text: 'Keep successful result', elapsedMs: 10 },
    { providerId: 'qa-retry', providerName: 'QA retry service', text: '', error: 'Initial timeout', elapsedMs: 20 },
  ]; });
  await page.locator('#source-text').fill('Provider retry source');
  await page.locator('#translate-button').click();
  await page.getByText('Keep successful result', { exact: true }).waitFor();
  const successCard = page.locator('.result-card[data-provider-id="qa-service"]');
  const retryCard = page.locator('.result-card[data-provider-id="qa-retry"]');
  await successCard.evaluate((element) => { element.dataset.retained = 'same-card'; });
  await page.evaluate(() => { window.__qa.holdTranslation = true; window.__qa.translationResults[1] = { ...window.__qa.translationResults[1], error: undefined, text: 'Retried only one provider' }; });
  await retryCard.locator('.result-retry').click();
  await page.waitForFunction(() => window.__qa.translationRequests.length === 2);
  assert.deepEqual(await page.evaluate(() => window.__qa.translationRequests.map(({ providerId }) => providerId ?? null)), [null, 'qa-retry']);
  assert.equal(await successCard.locator('.result-text').textContent(), 'Keep successful result');
  assert.equal(await successCard.getAttribute('data-retained'), 'same-card');
  assert.equal(await retryCard.locator('.result-retry').isDisabled(), true);
  await retryCard.locator('.result-retry').dispatchEvent('click');
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 2);
  await page.evaluate(() => {
    const request = window.__qa.translationRequests.at(-1);
    window.__qa.emit('translation-progress', { requestId: request.requestId, presentationEpoch: window.__qa.presentation.epoch, sequence: 1, done: false,
      result: { providerId: 'qa-retry', providerName: 'untrusted name', text: 'Retry streaming', elapsedMs: 1 } });
  });
  await retryCard.getByText('Retry streaming', { exact: true }).waitFor();
  assert.equal(await successCard.getAttribute('data-retained'), 'same-card');
  await page.evaluate(() => { window.__qa.holdTranslation = false; window.__qa.releaseTranslation(); });
  await retryCard.getByText('Retried only one provider', { exact: true }).waitFor();
  assert.equal(await successCard.locator('.result-text').textContent(), 'Keep successful result');
  assert.equal(await successCard.getAttribute('data-retained'), 'same-card');
  assert.equal(await page.locator('.result-card').count(), 2);
  // A top-level IPC failure must affect just this card, not the successful sibling.
  await page.evaluate(() => { window.__qa.translationError = 'Retry transport failed'; });
  await retryCard.locator('.result-retry').click();
  await retryCard.getByText('Retry transport failed', { exact: true }).waitFor();
  assert.equal(await successCard.locator('.result-text').textContent(), 'Keep successful result');
  // Protect against an out-of-band language change without trusting stale cards.
  await page.evaluate(() => { document.querySelector('#target-language').value = 'ja'; });
  await retryCard.locator('.result-retry').click();
  assert.equal(await page.evaluate(() => window.__qa.translationRequests.length), 3);
  await page.evaluate(() => { document.querySelector('#target-language').value = 'zh-Hans'; window.__qa.translationError = null; window.__qa.holdTranslation = true; });
  await retryCard.locator('.result-retry').click();
  await page.waitForFunction(() => window.__qa.translationRequests.length === 4);
  const cancelledRetry = await page.evaluate(() => structuredClone(window.__qa.translationRequests.at(-1)));
  await page.locator('#source-text').fill('Newer source wins over retry');
  await page.waitForFunction((id) => window.__qa.cancellationRequests.includes(id), cancelledRetry.requestId);
  await page.evaluate((request) => {
    window.__qa.holdTranslation = false; window.__qa.releaseTranslation();
    window.__qa.emit('translation-progress', { requestId: request.requestId, presentationEpoch: window.__qa.presentation.epoch, sequence: 99, done: true,
      result: { providerId: 'qa-retry', providerName: 'QA retry service', text: 'Stale retry result', elapsedMs: 1 } });
  }, cancelledRetry);
  await page.waitForTimeout(50);
  assert.equal(await page.locator('#source-text').inputValue(), 'Newer source wins over retry');
  assert.equal(await page.locator('.result-card').count(), 0);
  assert.deepEqual(errors, []);
  console.log('PASS: retry sends one provider ID, preserves successful text and DOM through streaming/completion/error, suppresses duplicate clicks, validates source/language snapshots, and discards cancelled late progress. Mock IPC only.');
  // Same-ID provider edits must replace request-owned metadata, not retain the
  // previous cloud kind/name on a newly retried system-translation result.
  await page.locator('#translate-button').click();
  await successCard.getByText('Keep successful result', { exact: true }).waitFor();
  await successCard.evaluate((element) => { element.dataset.retained = 'metadata-sibling'; });
  await goView('settings');
  await page.locator('.provider-row').filter({ hasText: 'QA retry service' }).getByRole('button', { name: '编辑', exact: true }).click();
  await page.locator('#provider-preset').selectOption('system');
  await page.locator('#provider-name').fill('Renamed system retry');
  await page.locator('#save-provider').click();
  await page.locator('#provider-dialog').waitFor({ state: 'hidden' });
  await goView('translate');
  await page.evaluate(() => { window.__qa.translationResults[1] = {
    providerId: 'qa-retry', providerName: 'Renamed system retry', text: '', elapsedMs: 2,
    error: 'SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: Retry language packs unavailable',
    resolvedLanguages: { sourceLanguage: 'zh-Hant', targetLanguage: 'en' },
  }; });
  await retryCard.locator('.result-retry').click();
  await retryCard.locator('.result-setup').waitFor({ state: 'visible' });
  assert.equal(await retryCard.locator('.result-provider').textContent(), 'Renamed system retry');
  assert.equal(await retryCard.locator('.result-actions').getAttribute('aria-label'), 'Renamed system retry译文操作');
  assert.equal(await retryCard.locator('.result-setup').textContent(), '准备系统翻译');
  assert.equal(await successCard.getAttribute('data-retained'), 'metadata-sibling');
  await retryCard.locator('.result-setup').click();
  assert.equal(await page.locator('#system-translation-source').inputValue(), 'zh-Hant');
  assert.equal(await page.locator('#system-translation-target').inputValue(), 'en');
  assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), []);
  // A history card starts without a provider kind; its retry must acquire the
  // current system kind and name, then offer the returned resolved pair.
  await page.evaluate(() => { window.__qa.history = [{
    id: 'history-system-retry', text: 'Historical system retry source', sourceLanguage: 'en', targetLanguage: 'zh-Hans',
    results: [{ providerId: 'qa-retry', providerName: 'Old historical name', text: 'Old historical result', elapsedMs: 3 }],
    createdAt: Date.now(), favorite: false,
  }]; });
  await goView('history');
  await page.locator('.history-open').click();
  assert.equal(await retryCard.locator('.result-provider').textContent(), 'Old historical name');
  await retryCard.locator('.result-retry').click();
  await retryCard.locator('.result-setup').waitFor({ state: 'visible' });
  assert.equal(await retryCard.locator('.result-provider').textContent(), 'Renamed system retry');
  assert.equal(await retryCard.locator('.result-actions').getAttribute('aria-label'), 'Renamed system retry译文操作');
  assert.equal(await retryCard.locator('.result-setup').textContent(), '准备系统翻译');
  await retryCard.locator('.result-setup').click();
  assert.equal(await page.locator('#system-translation-source').inputValue(), 'zh-Hant');
  assert.equal(await page.locator('#system-translation-target').inputValue(), 'en');
  assert.deepEqual(await page.evaluate(() => window.__qa.systemPrepareCalls), []);
  assert.deepEqual(errors, []);
  console.log('PASS: same-ID cloud-to-system/rename and history-card retries refresh provider kind, visible name and accessible action labels, route to the resolved system-language setup without downloading, and preserve successful sibling DOM. Mock IPC only.');
  console.log('PASS: persistent screenshot permission guidance prepared before presentation; click-only correct pane without authorization; retained sanitized link failure and manual path; first-use pending-open help navigation/focus; 800 px light and 420 px narrow/dark screenshots; dismiss/input/quiet Alt+D/Alt+A/stale-epoch recovery; deferred-modal permission payload and granted-status clearing; backend cancellation tickets on edit/clear/stop/Escape/close/native hide; native presentation epochs cover unallocated tickets, omitted/stale hide events, reopen overtaking pending begin and stale delayed popup fitting; backend-only cancellation clears old result state; late-ticket and replacement ordering; pending-save close/reentry guard; failure unlock; blank shortcuts; duplicate rejection; no countdown; theme/favorites and history bounds; OCR dual-key bundles/protocol isolation/no plaintext settings; documented vendor presets; origin-bound saved-key indications; minimal popup/menu/automatic source height; OCR configuration/privacy; empty-selection immediate typing; persistent source copy/speech; pin edge/icon/keyboard hit areas and drag isolation; captured source editing after completion and pending cancellation/retranslation; narrow-wrap source presentation; inconsistent permission feedback; automatic/fixed targets; Enter/ShiftEnter/IME/repeat; passive permissions; real capture and translation error preservation.');
} finally {
  await browser.close();
}
