import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { PROVIDER_PRESETS } from '../src/provider-presets';
import { TRANSLATION_NATIVE_URLS } from '../src/translation-credentials';

// The hidden protocol select is still the source of truth when a visible
// preset is selected. Browsers reset .value to '' for a missing option.
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const protocolSelect = html.match(/<select\b[^>]*\bid="provider-kind"[^>]*>([\s\S]*?)<\/select>/)?.[1];
const options = [...(protocolSelect ?? '').matchAll(/<option\b[^>]*\bvalue="([^"]+)"[^>]*>([^<]*)<\/option>/g)];
const values = options.map((option) => option[1]);

describe('translation preset protocol select contract', () => {
  it('provides exactly one selectable protocol for every preset kind', () => {
    expect(protocolSelect).toBeDefined();
    expect(new Set(values).size).toBe(values.length);
    expect([...new Set(values)].sort()).toEqual([...new Set(PROVIDER_PRESETS.map((preset) => preset.kind))].sort());
  });

  it.each(['volcengine', 'aliyun', 'niutrans', 'google-translate', 'caiyun'] as const)('keeps the %s native adapter selectable with its own endpoint', (kind) => {
    expect(options.find((option) => option[1] === kind)?.[2].trim()).toBeTruthy();
    expect(PROVIDER_PRESETS.find((preset) => preset.id === kind)).toMatchObject({ kind, baseUrl: TRANSLATION_NATIVE_URLS[kind], exampleModel: '' });
  });
});
