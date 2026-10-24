// Mirrors the backend credential boundary. URL normalizes host case and default
// ports; model names, URL paths, query parameters and fragments are not scopes.
export function credentialScope(kind: string, baseUrl: string): string | null {
  try {
    const url = new URL(baseUrl.trim());
    if (!['https:', 'http:'].includes(url.protocol)) return null;
    return `${kind}:${url.origin}`;
  } catch { return null; }
}
