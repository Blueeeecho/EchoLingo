import type { CredentialState } from './types';

type CredentialSummary = { hasKey?: boolean; credentialState?: CredentialState };

// These are passive session-cache facts supplied by the backend. In particular,
// unloaded and blocked never mean that a saved OS credential is missing.
export function credentialStateOf(provider?: CredentialSummary): CredentialState {
  return provider?.credentialState ?? (provider?.hasKey ? 'ready' : 'missing');
}

export function credentialStatusLabel(provider?: CredentialSummary): string {
  return {
    ready: '凭据已就绪', missing: '未配置凭据', blocked: '凭据读取受阻', unloaded: '凭据未读取',
  }[credentialStateOf(provider)];
}

export function credentialMayExist(provider?: CredentialSummary): boolean {
  return credentialStateOf(provider) !== 'missing';
}
