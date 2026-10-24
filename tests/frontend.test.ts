import { describe, expect, it } from 'vitest';
import { defaultSettings, errorMessage, filterHistory, languageName, normalizeTimestamp, validateProvider } from '../src/model';
import type { HistoryEntry, Provider } from '../src/types';

const provider: Provider = { id: 'private-api', name: '我的服务', kind: 'openai', baseUrl: 'https://api.example.com/v1', model: 'small-model', enabled: true };
const history: HistoryEntry[] = [
  { id: '1', text: 'A quiet place', sourceLanguage: 'en', targetLanguage: 'zh-Hans', results: [{ providerId: 'private-api', providerName: '我的服务', text: '安静的地方', elapsedMs: 800 }], createdAt: 1_777_777_777_000, favorite: false },
  { id: '2', text: '<script>alert("test")</script>', sourceLanguage: 'en', targetLanguage: 'zh-Hans', results: [{ providerId: 'private-api', providerName: '我的服务', text: '保持原文', elapsedMs: 500 }], createdAt: 1_777_777_778_000, favorite: true },
];

describe('provider privacy and validation', () => {
  it('rejects embedded URL credentials, query secrets, fragments, and insecure remote endpoints', () => {
    for (const baseUrl of ['https://user:secret@example.com', 'https://example.com?api_key=secret', 'https://example.com#secret', 'http://example.com', 'javascript:alert(1)', 'file:///tmp/secrets']) {
      expect(validateProvider({ ...provider, baseUrl })).not.toBeNull();
    }
  });
  it('supports secure remote and local self-hosted APIs', () => {
    for (const baseUrl of ['https://api.example.com/v1', 'http://localhost:11434/v1', 'http://127.0.0.1:5000', 'http://[::1]:11434/v1']) expect(validateProvider({ ...provider, baseUrl })).toBeNull();
  });
  it('requires a model only for OpenAI-compatible APIs', () => {
    expect(validateProvider({ ...provider, model: '' })).not.toBeNull();
    expect(validateProvider({ ...provider, kind: 'deepl', model: '' })).toBeNull();
    expect(validateProvider({ ...provider, kind: 'libretranslate', model: '' })).toBeNull();
  });
  it('creates separate defaults without an API secret field or simulated results', () => {
    const first = defaultSettings(); const second = defaultSettings();
    first.providers.push(provider);
    expect(second.providers).toEqual([]);
    expect(JSON.stringify(second)).not.toMatch(/apiKey|secret|token|results/);
  });
});

describe('history discovery', () => {
  it('searches original and translated content, ignoring case and outer whitespace', () => {
    expect(filterHistory(history, '  QUIET ', false).map((entry) => entry.id)).toEqual(['1']);
    expect(filterHistory(history, '安静', false).map((entry) => entry.id)).toEqual(['1']);
  });
  it('combines favorites with search and treats markup as ordinary text', () => {
    expect(filterHistory(history, '', true).map((entry) => entry.id)).toEqual(['2']);
    expect(filterHistory(history, '<script>', true).map((entry) => entry.id)).toEqual(['2']);
    expect(filterHistory(history, 'quiet', true)).toEqual([]);
  });
  it('does not mutate the history when filtering', () => {
    const before = structuredClone(history); filterHistory(history, 'quiet', true); expect(history).toEqual(before);
  });
});

describe('display compatibility', () => {
  it('accepts Unix second and millisecond timestamps', () => {
    expect(normalizeTimestamp(1_777_777_777)).toBe(1_777_777_777_000);
    expect(normalizeTimestamp(1_777_777_777_000)).toBe(1_777_777_777_000);
  });
  it('preserves server errors and unknown language codes', () => {
    expect(errorMessage('请求超时')).toBe('请求超时');
    expect(errorMessage(new Error('网络不可用'))).toBe('网络不可用');
    expect(languageName('xx-custom')).toBe('xx-custom');
  });
});
