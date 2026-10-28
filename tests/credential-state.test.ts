import { describe, expect, it } from 'vitest';
import { credentialMayExist, credentialStateOf, credentialStatusLabel } from '../src/credential-state';

describe('passive credential summaries', () => {
  it('distinguishes an unread or blocked credential from a confirmed missing one', () => {
    for (const credentialState of ['unloaded', 'blocked'] as const) {
      const provider = { credentialState, hasKey: false };
      expect(credentialStateOf(provider)).toBe(credentialState);
      expect(credentialMayExist(provider)).toBe(true);
      expect(credentialStatusLabel(provider)).not.toMatch(/未配置|已就绪|匹配/);
    }
    expect(credentialMayExist({ credentialState: 'missing', hasKey: false })).toBe(false);
    expect(credentialStatusLabel({ credentialState: 'missing' })).toBe('未配置凭据');
  });
  it('uses explicit cache state before the legacy boolean', () => {
    expect(credentialStateOf({ credentialState: 'unloaded', hasKey: true })).toBe('unloaded');
    expect(credentialStateOf({ credentialState: 'blocked', hasKey: true })).toBe('blocked');
    expect(credentialStateOf({ credentialState: 'ready', hasKey: false })).toBe('ready');
    expect(credentialMayExist({ credentialState: 'ready' })).toBe(true);
  });
  it('keeps compatibility with older backends and new unsaved services', () => {
    expect(credentialStateOf({ hasKey: true })).toBe('ready');
    expect(credentialStateOf({ hasKey: false })).toBe('missing');
    expect(credentialStateOf()).toBe('missing');
  });
});
