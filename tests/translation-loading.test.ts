import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';
import { mergeProviderRetry, sameTranslationSnapshot } from '../src/translation-retry';

// Execute production request/render functions with a content-only DOM and IPC double.
// This does not test browser layout, native input or screen-reader delivery.
class Element {
  children: Element[] = []; parent: Element | null = null;
  attrs: Record<string, string> = {};
  className = ''; hidden = false; disabled = false; value = ''; text = '';
  get textContent(): string { return this.text + this.children.map(c => c.textContent).join(''); }
  set textContent(value: string) { this.text = value; this.children = []; }
  get childNodes() { return this.children; }
  get firstChild() { return this.children[0]; }
  get isConnected() { return false; }
  append(...children: Element[]) { for (const c of children) c.parent = this; this.children.push(...children); }
  replaceChildren(...children: Element[]) { this.text = ''; this.children = []; this.append(...children); }
  replaceWith(other: Element) {
    if (!this.parent) return;
    this.parent.children[this.parent.children.indexOf(this)] = other;
    other.parent = this.parent; this.parent = null;
  }
  setAttribute(key: string, value: string) { this.attrs[key] = value; }
  getAttribute(key: string) { return this.attrs[key]; }
  querySelectorAll() { return []; }
}
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
function harness() {
  const source = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');
  const names = ['translationLoadingStatus', 'setResultPlaceholder', 'updateResultView', 'receiveTranslationProgress',
    'receiveCapturedText', 'applyTranslationPresentation', 'translate', 'emptyResults', 'invalidateResults', 'cancelActiveTranslation', 'stopPendingTranslation'];
  const chunks = names.map(name => {
    const start = source.search(new RegExp(`(?:async )?function ${name}\\(`));
    return source.slice(start, source.indexOf('\n}', start) + 2);
  }).join('\n');
  const elements = new Map<string, Element>();
  const node = (_tag: string, cls = '', text = '') => {
    const el = new Element(); el.className = cls; el.textContent = text; return el;
  };
  const request = deferred<any[]>();
  const result = (text: string, providerId = 'p') => ({ providerId, providerName: 'Provider', text, elapsedMs: 0 });
  const ctx: any = {
    mergeProviderRetry, sameTranslationSnapshot, node, Node: { TEXT_NODE: 3 }, Text: class {},
    $: (selector: string) => { if (!elements.has(selector)) elements.set(selector, new Element()); return elements.get(selector); },
    resultsContainer: new Element(), source: { value: 'Hello' },
    sourceLanguage: { value: 'en' }, targetLanguage: { value: 'zh-Hans' },
    settings: { providers: [{ id: 'p', name: 'Provider', enabled: true }] },
    settingsReady: true, translating: false, generation: 0, focusIntentRevision: 0,
    currentResults: [], resultSnapshot: null, resultSource: '', progressViews: new Map(), progressEpoch: null,
    activeTranslationId: null, translationPresentation: { epoch: 1, presented: true }, currentView: 'translate',
    desktop: true, MAX_TEXT_LENGTH: 20000,
    compactBlankLines: (text: string) => text, needsSystemTranslationSetup: () => false,
    requireDesktop: () => true, codePointLength: (text: string) => text.length,
    beginTranslation: async () => 1,
    invoke: (command: string) => command === 'translate' ? request.promise : Promise.resolve(),
    errorMessage: (e: Error) => e.message, userFacingError: (e: Error | string) => typeof e === 'string' ? e : e.message,
    recordInputDiagnostic() {}, notifyLayout() {}, status() {}, maybeSoftEngineHint() {}, reportError() {},
    freeSetup: { noteWeak() {} }, refreshHistory: async () => {},
    pendingTranslate: false, preparedTranslationEpoch: null,
    languageSession: 0, startupSourceIntentRevision: 0, sourceDeliveryIntent: null,
    presentationFocusIntent: null, sourceDeliveryInbox: { peek: () => null },
    visiblePopupUpdateBaseline: null, allModals: [], modalActive: () => false,
    document: { activeElement: null }, HTMLElement: Element,
    historyLanguages: { newInput: (pair: unknown) => pair },
    selectedLanguagePair: () => ({}), applyLanguagePair() {},
    normalizeOcrCapturedText: (text: string) => text, normalizeCapturedText: (text: string) => text,
    clearToast() {}, suspendConfigurationDialogs() {}, setView(view: string) { ctx.currentView = view; },
    recordPopupStage() {}, endSourceInputSession() {},
    setSourceText(text: string) { ctx.source.value = text; ctx.invalidateResults(); },
    dispatched: [] as Promise<unknown>[],
    run(work: () => Promise<unknown>) { ctx.dispatched.push(work()); },

  };
  ctx.setLoading = (value: boolean) => { ctx.translating = value; };
  ctx.createResultView = (r: any, done: boolean) => {
    const view = { card: node('article'), body: node('p'), preservedNotice: node('span'),
      actions: Array.from({ length: 4 }, () => node('button')), result: r, done, sequence: 0 };
    view.card.append(view.body); ctx.updateResultView(view, r, done); return view;
  };
  ctx.renderResults = (results: any[]) => ctx.resultsContainer.replaceChildren(...results.map(r => ctx.createResultView(r, true).card));
  runInNewContext(ts.transpileModule(chunks, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText, ctx);
  const placeholder = ctx.$('#result-placeholder');
  const progress = (text: string, sequence: number, providerId = 'p', requestId = 1) =>
    ctx.receiveTranslationProgress({ requestId, presentationEpoch: 1, sequence, done: false, result: result(text, providerId) });
  return { ctx, request, result, progress, placeholder };
}
describe('translation loading presentation', () => {
  it('prepares a quiet result pane for genuine empty input before show', async () => {
    const { ctx, placeholder } = harness();
    let seen = false;
    ctx.panelLayout = { presentPopup: async () => {
      expect(placeholder.textContent).toBe('译文会显示在这里');
      expect(placeholder.children[0].attrs.role).toBeUndefined();
      seen = true;
      return { epoch: 1, presented: true };
    } };
    await ctx.receiveCapturedText({ text: '', mode: 'input' });
    expect(seen).toBe(true);
    expect(ctx.dispatched).toHaveLength(0);
  });
  it('pre-fits the pending pane before show without creating a translation ticket', async () => {
    const { ctx, request, result, placeholder } = harness();
    const shown = deferred<{ epoch: number; presented: boolean }>();
    let prepared = false;
    let allocated = 0;
    ctx.beginTranslation = async () => ++allocated;
    ctx.panelLayout = { presentPopup: () => {
      expect(placeholder.textContent).toBe('翻译中…');
      expect(ctx.$('#popup-services').hidden).toBe(true);
      prepared = true;
      return shown.promise;
    } };
    const reveal = ctx.receiveCapturedText({ text: 'Hello', mode: 'translate' });
    expect(prepared).toBe(true);
    expect(ctx.translating).toBe(false);
    expect(allocated).toBe(0);
    shown.resolve({ epoch: 2, presented: true });
    await reveal;
    expect(allocated).toBe(1);
    expect(placeholder.textContent).toBe('翻译中…');
    request.resolve([result('你好')]);
    await Promise.all(ctx.dispatched);
    expect(ctx.resultsContainer.textContent).toBe('你好');
  });
  it('preserves only the newest loading intent and restores the idle pane on cancelled show', async () => {
    const { ctx, placeholder } = harness();
    const old = deferred<null>(), fresh = deferred<null>();
    let calls = 0;
    ctx.panelLayout = { presentPopup: () => ++calls === 1 ? old.promise : fresh.promise };
    const older = ctx.receiveCapturedText({ text: 'Old', mode: 'translate' });
    const newer = ctx.receiveCapturedText({ text: 'New', mode: 'translate' });
    old.resolve(null);
    await older;
    expect(placeholder.textContent).toBe('翻译中…');
    fresh.resolve(null);
    await newer;
    expect(placeholder.textContent).toBe('译文会显示在这里');
    expect(ctx.dispatched).toHaveLength(0);
    expect(ctx.$('#popup-services').hidden).toBe(false);
  });
  it('Escape/hide cancels prepared loading even before the show acknowledgement', async () => {
    for (const explicitStop of [true, false]) {
      const { ctx, placeholder } = harness();
      const shown = deferred<{ epoch: number; presented: boolean }>();
      ctx.panelLayout = { presentPopup: () => shown.promise };
      const reveal = ctx.receiveCapturedText({ text: 'Old', mode: 'translate', presentationEpoch: 1 });
      expect(placeholder.textContent).toBe('翻译中…');
      expect(ctx.translating).toBe(false);
      if (explicitStop) ctx.stopPendingTranslation(); // Called by Escape and the close button.
      else ctx.applyTranslationPresentation({ epoch: 3, presented: false });
      expect(placeholder.textContent).toBe('译文会显示在这里');
      shown.resolve({ epoch: 2, presented: true });
      await reveal;
      expect(ctx.dispatched).toHaveLength(0);
      expect(placeholder.textContent).toBe('译文会显示在这里');
    }
  });
  it('shows polite visible loading and replaces whitespace-only progress with the first text', async () => {
    const { ctx, request, result, progress, placeholder } = harness();
    const running = ctx.translate();
    expect(ctx.resultsContainer.textContent).toBe('');
    expect(placeholder.textContent).toBe('翻译中…');
    const status = placeholder.children[0];
    expect(status.attrs).toEqual({ role: 'status', 'aria-live': 'polite' });
    expect(status.children[0].attrs['aria-hidden']).toBe('true');
    await tick(); expect(ctx.activeTranslationId).toBe(1);
    progress(' ', 1); expect(ctx.resultsContainer.textContent).toBe('翻译中…');
    progress('你', 2); expect(ctx.resultsContainer.textContent).toBe('你');
    request.resolve([result('你好')]); await running;
    expect(ctx.resultsContainer.textContent).toBe('你好');
  });
  it('handles fast non-streaming completion', async () => {
    const { ctx, request, result } = harness();
    request.resolve([result('你好')]); await ctx.translate();
    expect(ctx.resultsContainer.textContent).toBe('你好'); expect(ctx.translating).toBe(false);
  });
  it('clears cancellation and ignores superseded final and stream responses', async () => {
    const { ctx, request, result, progress, placeholder } = harness();
    const old = ctx.translate(); await tick(); ctx.stopPendingTranslation();
    expect(ctx.resultsContainer.textContent).toBe('');
    expect(placeholder.textContent).toBe('译文会显示在这里');
    const next = deferred<any[]>(); ctx.beginTranslation = async () => 2;
    ctx.invoke = (command: string) => command === 'translate' ? next.promise : Promise.resolve();
    const fresh = ctx.translate(); await tick(); request.resolve([result('Old')]); await old;
    progress('Old stream', 9); expect(ctx.resultsContainer.textContent).toBe('');
    expect(placeholder.textContent).toBe('翻译中…');
    next.resolve([result('New')]); await fresh; expect(ctx.resultsContainer.textContent).toBe('New');
  });
  it('replaces errors without leaving loading behind', async () => {
    const { ctx, request, result } = harness();
    const running = ctx.translate(); await tick(); request.reject(new Error('Request failed')); await running;
    expect(ctx.resultsContainer.textContent).toBe('Request failed');
    const view = ctx.createResultView({ ...result(''), error: 'Provider failed' }, false);
    expect(view.body.textContent).toBe('Provider failed'); expect(view.body.className).toBe('result-error');
  });
  it('does not show loading for idle or empty final results or existing text', async () => {
    const { ctx, result } = harness(); ctx.source.value = ''; await ctx.translate();
    expect(ctx.resultsContainer.textContent).toBe('');
    expect(ctx.createResultView(result(''), true).body.textContent).toBe('');
    expect(ctx.createResultView(result('Partial'), false).body.textContent).toBe('Partial');
    expect(ctx.createResultView(result(' \n'), false).body.textContent).toBe('翻译中…');
  });
  it('retains loading on empty provider cards when the initial row is replaced', async () => {
    const { ctx, request, result, progress, placeholder } = harness();
    ctx.settings.providers.push({ id: 'q', name: 'Second', enabled: true });
    const running = ctx.translate(); expect(ctx.resultsContainer.children).toHaveLength(0);
    expect(placeholder.textContent).toBe('翻译中…');
    await tick(); progress('First', 1);
    expect(ctx.resultsContainer.children).toHaveLength(2);
    expect(ctx.resultsContainer.children[0].textContent).toBe('First');
    expect(ctx.resultsContainer.children[1].textContent).toBe('翻译中…');
    expect(ctx.progressViews.get('q').body.children[0].attrs.role).toBe('status');
    request.resolve([result('First complete'), result('Second complete', 'q')]); await running;
    expect(ctx.resultsContainer.textContent).toBe('First completeSecond complete');
  });
  it('keeps successful siblings while retrying only one provider', async () => {
    const { ctx, request, result, progress, placeholder } = harness();
    ctx.settings.providers.push({ id: 'q', name: 'Second', enabled: true });
    ctx.currentResults = [result('Keep this'), { ...result('', 'q'), error: 'Failed' }];
    ctx.resultSnapshot = { text: 'Hello', sourceLanguage: 'en', targetLanguage: 'zh-Hans' };
    for (const r of ctx.currentResults) {
      const view = ctx.createResultView(r, true); ctx.progressViews.set(r.providerId, view); ctx.resultsContainer.append(view.card);
    }
    const successfulCard = ctx.resultsContainer.children[0]; const running = ctx.translate('q');
    expect(ctx.resultsContainer.children[0]).toBe(successfulCard);
    expect(ctx.resultsContainer.textContent).toBe('Keep this翻译中…');
    await tick(); progress('Retry chunk', 1, 'q');
    expect(ctx.resultsContainer.children[0]).toBe(successfulCard);
    expect(ctx.resultsContainer.textContent).toBe('Keep thisRetry chunk');
    request.resolve([result('Retry complete', 'q')]); await running;
    expect(ctx.currentResults.map((r: any) => r.text)).toEqual(['Keep this', 'Retry complete']);
    expect(ctx.resultsContainer.textContent).toBe('Keep thisRetry complete');
  });
});
