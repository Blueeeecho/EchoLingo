import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { invoke } from '@tauri-apps/api/core';
import { installFreeSetup } from '../src/free-setup-ui';
import { defaultSettings } from '../src/model';
import type { Settings } from '../src/types';

vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn() }));

// Minimal DOM fixture for the production wizard's event handlers. No network,
// browser process, real account, credential store, or installed app is involved.
class Element {
  id = ''; hidden = false; disabled = false; value = ''; textContent = '';
  children: Element[] = [];
  attributes = new Map<string, string>();
  listeners = new Map<string, ((event: { target: Element; key?: string; preventDefault: () => void; stopPropagation: () => void }) => void)[]>();
  append(...children: Element[]) { this.children.push(...children); }
  replaceChildren(...children: Element[]) { this.children = children; }
  setAttribute(name: string, value: string) { this.attributes.set(name, value); }
  addEventListener(name: string, listener: (event: { target: Element; key?: string; preventDefault: () => void; stopPropagation: () => void }) => void) {
    this.listeners.set(name, [...this.listeners.get(name) ?? [], listener]);
  }
  emit(name = 'click', key?: string) { for (const listener of this.listeners.get(name) ?? []) listener({ target: this, key, preventDefault() {}, stopPropagation() {} }); }
  focus() {}
  find(id: string): Element | undefined { return this.id === id ? this : this.children.map((child) => child.find(id)).find(Boolean); }
}
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
}
const settle = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };
function fixture(desktop = true, blockingHint?: 'engine-hint' | 'core-guidance') {
  const ids = ['free-setup-hint', 'free-setup-dialog', 'free-setup-body', 'free-setup-error', 'free-translation-list', 'free-ocr-list', 'free-region-cn', 'free-region-overseas', 'core-guidance', 'engine-hint', 'free-setup-step', 'free-setup-next', 'free-setup-back', 'free-setup-close', 'free-setup-settings', 'free-setup-open', 'free-setup-docs', 'free-setup-dismiss'];
  const roots = ids.map((id) => { const node = new Element(); node.id = id; node.hidden = id === 'free-setup-hint' || id === 'free-setup-dialog' || ((id === 'core-guidance' || id === 'engine-hint') && id !== blockingHint); return node; });
  const find = (id: string) => roots.map((root) => root.find(id)).find(Boolean) ?? null;
  const node = (id: string) => { const result = find(id); if (!result) throw new Error(`Missing fixture node: ${id}`); return result; };
  vi.stubGlobal('document', { querySelector: (selector: string) => find(selector.slice(1)), getElementById: find, createElement: () => new Element(), createTextNode: () => new Element() });
  vi.stubGlobal('window', blockingHint ? {} : { __qa: true });
  vi.stubGlobal('navigator', { language: 'en-US' });
  vi.stubGlobal('localStorage', { getItem: () => null, setItem: vi.fn() });
  vi.stubGlobal('crypto', { randomUUID });
  let settings = defaultSettings();
  settings.providers.push({ id: 'existing-translation', name: 'Existing', kind: 'openai', baseUrl: 'https://example.invalid/v1', model: 'existing', enabled: true });
  settings.ocrProviders.push({ id: 'existing-ocr', name: 'Existing OCR', kind: 'google', baseUrl: 'https://vision.googleapis.com/v1/images:annotate', model: 'TEXT_DETECTION', prompt: '', authHeader: '', authPrefix: '', requestTemplate: '', responsePath: '', region: '' });
  settings.activeOcrProviderId = 'existing-ocr';
  const keys = new Map([['existing-translation', 'old-key'], ['existing-ocr', 'old-ocr-key']]);
  const invokeGates = new Map<string, ReturnType<typeof deferred>>();
  const invokeFailures = new Set<string>();
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    await invokeGates.get(command)?.promise;
    if (invokeFailures.has(command)) throw new Error(`Failed ${command}`);
    const id = (args as { providerId?: string })?.providerId;
    if (command.startsWith('set_') && id) keys.set(id, (args as { key: string }).key);
    if (command.startsWith('delete_') && id) keys.delete(id);
    return 'Connection tested' as never;
  });
  let calls = 0, queue = Promise.resolve();
  const beforeSave = new Map<number, ReturnType<typeof deferred>>();
  const afterSave = new Map<number, ReturnType<typeof deferred>>();
  const failSave = new Set<number>();
  const toast = vi.fn(), reportError = vi.fn();
  const updateSettings = (mutate: (next: Settings) => void, canCommit?: () => boolean) => {
    const call = ++calls;
    const operation = queue.then(async () => {
      await beforeSave.get(call)?.promise;
      if (canCommit && !canCommit()) return;
      const next = structuredClone(settings);
      mutate(next);
      await afterSave.get(call)?.promise;
      if (failSave.has(call)) throw new Error('Failed save');
      settings = next;
    });
    queue = operation.catch(() => {});
    return operation;
  };
  const api = installFreeSetup({ desktop, settings: () => settings, updateSettings, toast, reportError, setView() {}, showModal(modal) { modal.hidden = false; }, closeModal(modal) { modal.hidden = true; } });
  const open = (region: 'cn' | 'overseas' = 'cn', index = 0, role: 'translation' | 'ocr' = 'translation') => {
    node(`free-region-${region}`).emit();
    node(`free-${role}-list`).children[index]!.children[4]!.children[0]!.emit();
  };
  const fill = () => { for (const id of ['key', 'first', 'second']) { const input = find(`free-field-${id}`); if (input) input.value = 'private-test-key'; } if (find('free-field-endpoint')) node('free-field-endpoint').value = 'https://my-resource.cognitiveservices.azure.com'; };
  const submit = async () => { node('free-setup-next').emit(); await settle(); };
  const fresh = () => [...settings.providers, ...settings.ocrProviders].filter((provider) => provider.id.startsWith('free-'));
  return { api, node, find, open, fill, submit, fresh, settings: () => settings, keys, invokeGates, invokeFailures, beforeSave, afterSave, failSave, toast, reportError, calls: () => calls };
}

beforeEach(() => vi.clearAllMocks());
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe('combined engine and signup guidance', () => {
  it.each(['engine-hint', 'core-guidance'] as const)('defers signup behind %s and reveals it only after the blocker is gone', (blocker) => {
    const f = fixture(true, blocker);
    expect(f.node('free-setup-hint').hidden).toBe(true);
    expect(localStorage.setItem).not.toHaveBeenCalled();
    f.api.refresh();
    expect(localStorage.setItem).not.toHaveBeenCalled();
    f.api.noteWeak('翻译失败');
    expect(f.node('free-setup-hint').hidden).toBe(true);
    f.node(blocker).hidden = true; f.api.refresh();
    expect(f.node('free-setup-hint').hidden).toBe(false);
    f.node(blocker).hidden = false; f.api.refresh();
    expect(f.node('free-setup-hint').hidden).toBe(true);
    f.node(blocker).hidden = true; f.api.refresh();
    f.node('free-setup-dismiss').emit();
    f.api.noteWeak('翻译失败'); f.api.refresh();
    expect(f.node('free-setup-hint').hidden).toBe(true);
  });
});

describe('free setup validation and step advancement', () => {
  it.each([['cn', 0], ['cn', 1], ['cn', 2], ['overseas', 0], ['overseas', 1]] as const)('keeps blank %s/%s credentials on the same step', async (region, index) => {
    const f = fixture(); f.open(region, index);
    const step = f.node('free-setup-step').textContent;
    await f.submit(); await f.submit();
    expect(f.node('free-setup-step').textContent).toBe(step);
    expect(f.node('free-setup-dialog').hidden).toBe(false);
    expect(f.node('free-setup-error').hidden).toBe(false);
    expect(f.node('free-setup-next').disabled).toBe(false);
    expect(f.calls()).toBe(0); expect(invoke).not.toHaveBeenCalled(); expect(f.toast).not.toHaveBeenCalled();
  });
  it('does not advance when a credential pair is incomplete or desktop testing is unavailable', async () => {
    let f = fixture(); f.open('cn', 1); f.node('free-field-first').value = 'one-half'; await f.submit();
    expect(f.node('free-setup-step').textContent).toContain('Translation'); expect(f.calls()).toBe(0);
    f = fixture(false); f.open(); f.fill(); await f.submit();
    expect(f.node('free-setup-step').textContent).toContain('Translation'); expect(f.calls()).toBe(0);
  });
  it('does not finish an invalid Azure endpoint, then completes only after a valid tested OCR', async () => {
    const f = fixture(); f.open('overseas', 1, 'ocr');
    f.fill(); f.node('free-field-endpoint').value = 'https://example.invalid'; await f.submit();
    expect(f.node('free-setup-dialog').hidden).toBe(false); expect(f.node('free-setup-step').textContent).toContain('OCR');
    expect(f.settings().activeOcrProviderId).toBe('existing-ocr');
    f.fill(); await f.submit();
    expect(f.node('free-setup-dialog').hidden).toBe(true); expect(f.find('free-field-key')).toBeNull();
    expect(f.fresh()).toHaveLength(1); expect(f.settings().activeOcrProviderId).toMatch(/^free-/);
    expect(vi.mocked(invoke).mock.calls.filter(([command]) => command === 'test_ocr_provider')).toHaveLength(1);
  });
});

describe('free setup interrupted and repeated requests', () => {
  it('ignores double Next even when events bypass the disabled button', async () => {
    const f = fixture(); const gate = deferred(); f.invokeGates.set('test_provider', gate);
    f.open(); f.fill(); await f.submit(); await f.submit();
    expect(f.node('free-setup-next').disabled).toBe(true); expect(f.fresh()).toHaveLength(1);
    expect(vi.mocked(invoke).mock.calls.filter(([command]) => command === 'test_provider')).toHaveLength(1);
    gate.resolve(); await settle();
    expect(f.node('free-setup-dialog').hidden).toBe(true); expect(f.node('free-setup-next').disabled).toBe(false);
    expect(f.fresh()).toHaveLength(1);
  });
  it.each(['queued-stage', 'in-flight-stage', 'key', 'test', 'queued-activation', 'in-flight-activation'] as const)('cancels %s without stale activation, secrets, or advancing a reopened wizard', async (stage) => {
    const f = fixture(), gate = deferred();
    if (stage === 'queued-stage') f.beforeSave.set(1, gate);
    if (stage === 'in-flight-stage') f.afterSave.set(1, gate);
    if (stage === 'key') f.invokeGates.set('set_api_key', gate);
    if (stage === 'test') f.invokeGates.set('test_provider', gate);
    if (stage === 'queued-activation') f.beforeSave.set(2, gate);
    if (stage === 'in-flight-activation') f.afterSave.set(2, gate);
    f.open(); f.fill(); await f.submit();
    f.node('free-setup-close').emit(); expect(f.find('free-field-key')).toBeNull();
    f.open('overseas', 1); const step = f.node('free-setup-step').textContent;
    gate.resolve(); await settle();
    expect(f.fresh()).toEqual([]); expect([...f.keys.keys()]).toEqual(['existing-translation', 'existing-ocr']);
    expect(f.settings().providers[0]!.enabled).toBe(true); expect(f.settings().activeOcrProviderId).toBe('existing-ocr');
    expect(f.node('free-setup-step').textContent).toBe(step); expect(f.node('free-setup-dialog').hidden).toBe(false);
    expect(f.toast).not.toHaveBeenCalled(); expect(f.reportError).not.toHaveBeenCalled();
  });
  it.each(['back', 'escape', 'backdrop', 'open-new'] as const)('invalidates pending OCR on %s and preserves completed steps and existing OCR', async (action) => {
    const f = fixture(); f.open(); f.fill(); await f.submit();
    const translator = f.fresh()[0]!.id; f.toast.mockClear(); f.open('cn', 0, 'ocr');
    const gate = deferred(); f.invokeGates.set('test_ocr_provider', gate);
    f.fill(); await f.submit();
    if (action === 'back') f.node('free-setup-back').emit();
    if (action === 'escape') f.node('free-setup-dialog').emit('keydown', 'Escape');
    if (action === 'backdrop') f.node('free-setup-dialog').emit();
    if (action === 'open-new') f.open('overseas', 1);
    gate.resolve(); await settle();
    expect(f.settings().activeOcrProviderId).toBe('existing-ocr'); expect(f.fresh().map((provider) => provider.id)).toEqual([translator]);
    expect([...f.keys.keys()]).toEqual(['existing-translation', 'existing-ocr', translator]);
    expect(f.toast).not.toHaveBeenCalled(); expect(f.reportError).not.toHaveBeenCalled();
    if (action === 'open-new') expect(f.node('free-setup-step').textContent).toContain('Translation');
    else expect(f.find('free-field-first')).toBeNull();
  });
  it('rolls back an OCR activation already in flight when Close occurs', async () => {
    const f = fixture(); f.open(); f.fill(); await f.submit();
    const gate = deferred(); f.afterSave.set(4, gate); f.toast.mockClear(); f.open('cn', 0, 'ocr');
    f.fill(); await f.submit(); f.node('free-setup-close').emit(); gate.resolve(); await settle();
    expect(f.settings().activeOcrProviderId).toBe('existing-ocr'); expect(f.settings().ocrProviders.map((p) => p.id)).toEqual(['existing-ocr']);
    expect(f.toast).not.toHaveBeenCalled();
  });
  it('an old completion cannot clear the busy state of a new submission', async () => {
    const f = fixture(), oldGate = deferred(), newGate = deferred(); f.invokeGates.set('test_provider', oldGate);
    f.open(); f.fill(); await f.submit(); f.node('free-setup-close').emit();
    f.invokeGates.set('test_provider', newGate); f.open('overseas', 1); f.fill(); await f.submit();
    oldGate.resolve(); await settle(); expect(f.node('free-setup-next').disabled).toBe(true);
    newGate.resolve(); await settle(); expect(f.node('free-setup-next').disabled).toBe(false);
    expect(f.node('free-setup-dialog').hidden).toBe(true); expect(f.fresh()).toHaveLength(1);
  });
});

describe('free setup failed requests', () => {
  it.each(['set_api_key', 'test_provider', 'save-stage', 'save-activation'] as const)('cleans only this operation after %s failure and allows retry', async (failure) => {
    const f = fixture();
    if (failure === 'save-stage') f.failSave.add(1);
    else if (failure === 'save-activation') f.failSave.add(2);
    else f.invokeFailures.add(failure);
    f.open(); f.fill(); await f.submit();
    expect(f.fresh()).toEqual([]); expect([...f.keys.keys()]).toEqual(['existing-translation', 'existing-ocr']);
    expect(f.node('free-setup-step').textContent).toContain('Translation'); expect(f.node('free-setup-error').hidden).toBe(false);
    expect(f.node('free-setup-next').disabled).toBe(false); expect(f.toast).not.toHaveBeenCalled();
    f.invokeFailures.clear(); f.failSave.clear(); await f.submit();
    expect(f.node('free-setup-dialog').hidden).toBe(true); expect(f.fresh()).toHaveLength(1);
  });
  it('retains a disabled removable provider and reports failed secret cleanup', async () => {
    const f = fixture(); f.invokeFailures.add('test_provider'); f.invokeFailures.add('delete_api_key');
    f.open(); f.fill(); await f.submit();
    expect(f.fresh()).toHaveLength(1); expect(f.settings().providers.at(-1)!.enabled).toBe(false);
    expect(f.reportError).toHaveBeenCalledOnce(); expect(f.toast).not.toHaveBeenCalled();
    expect(f.node('free-setup-step').textContent).toContain('Translation');
  });
});


describe('independent role selection and setup', () => {
  it('the general entry selects no provider and submits nothing', async () => {
    const f = fixture(); f.node('free-setup-settings').emit(); await settle();
    expect(f.node('free-setup-dialog').hidden).toBe(true);
    expect(f.fresh()).toEqual([]); expect(invoke).not.toHaveBeenCalled();
  });
  it('translation completion never asks for OCR or changes its selection', async () => {
    const f = fixture(); const before = structuredClone(f.settings().ocrProviders);
    f.open(); f.fill(); await f.submit();
    expect(f.node('free-setup-dialog').hidden).toBe(true);
    expect(f.settings().ocrProviders).toEqual(before);
    expect(f.settings().activeOcrProviderId).toBe('existing-ocr');
    expect(vi.mocked(invoke).mock.calls.some(([command]) => command.includes('ocr'))).toBe(false);
    expect(f.fresh()).toHaveLength(1);
  });
  it('OCR can be configured first without adding or changing any translation service', async () => {
    const f = fixture(); const before = structuredClone(f.settings().providers);
    f.open('cn', 0, 'ocr'); f.fill(); await f.submit();
    expect(f.node('free-setup-dialog').hidden).toBe(true);
    expect(f.settings().providers).toEqual(before);
    expect(f.settings().activeOcrProviderId).toMatch(/^free-/);
    expect(vi.mocked(invoke).mock.calls.some(([command]) => command === 'test_provider')).toBe(false);
  });
  it.each([['volcengine', 3, 'cn-beijing'], ['aliyun', 4, 'cn-hangzhou']] as const)('uses native credential shape and default region for %s', async (kind, index, region) => {
    const f = fixture(); f.open('cn', index); f.fill(); await f.submit();
    const provider = f.settings().providers.at(-1)!;
    expect(provider.kind).toBe(kind); expect(provider.region).toBe(region);
    const secret = JSON.parse(f.keys.get(provider.id)!);
    expect(secret).toEqual({ accessKeyId: 'private-test-key', accessKeySecret: 'private-test-key' });
    expect(JSON.stringify(provider)).not.toContain('private-test-key');
    expect(f.settings().activeOcrProviderId).toBe('existing-ocr');
  });
  it('publishes verified quota summaries and source buttons in both role lists', () => {
    const f = fixture();
    expect(f.node('free-translation-list').children.length).toBeGreaterThan(1);
    expect(f.node('free-ocr-list').children.length).toBeGreaterThan(1);
    for (const list of ['free-translation-list', 'free-ocr-list']) for (const row of f.node(list).children) {
      expect(row.children[1]!.textContent.length).toBeGreaterThan(10);
      expect(row.children[3]!.textContent).toContain('2026-10-30');
      expect(row.children[4]!.children).toHaveLength(2);
    }
  });
  it.each([['translation', 6], ['ocr', 3]] as const)('stores Youdao %s credentials without sharing or saving secrets in settings', async (role, index) => {
    const f = fixture(); f.open('cn', index, role); f.fill(); await f.submit();
    const provider = f.fresh()[0]!;
    expect(JSON.parse(f.keys.get(provider.id)!)).toEqual({ appKey: 'private-test-key', appSecret: 'private-test-key' });
    expect(JSON.stringify(f.settings())).not.toContain('private-test-key');
    expect(f.fresh()).toHaveLength(1);
  });
  it('rejects the public OCR.space sample key without staging a service', async () => {
    const f = fixture(); f.open('overseas', 2, 'ocr'); f.node('free-field-key').value = 'helloworld'; await f.submit();
    expect(f.node('free-setup-error').hidden).toBe(false); expect(f.fresh()).toEqual([]); expect(invoke).not.toHaveBeenCalled();
  });

});

describe('newcomer trial model confirmation', () => {
  it.each(['qianfan', 'tokenhub', 'ark'])('requires an explicitly selected trial model for %s', async (id) => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-10-30T00:00:00Z'));
    const f = fixture(); f.node('free-region-cn').emit();
    f.node('free-translation-list').children.find(row => row.attributes.get('data-free-service') === `${id}-trial`)!.children[4]!.children[0]!.emit();
    f.fill(); await f.submit();
    expect(f.fresh()).toHaveLength(0); expect(invoke).not.toHaveBeenCalled();
    f.node('free-field-model').value = 'account-confirmed-model';
    await f.submit();
    expect(f.fresh()[0]).toMatchObject({ kind: 'openai', model: 'account-confirmed-model', enabled: true });
    expect(f.settings().activeOcrProviderId).toBe('existing-ocr');
    expect(JSON.stringify(f.settings())).not.toContain('private-test-key');
  });
});
