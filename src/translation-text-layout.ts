export interface TranslationTextPart {
  text: string;
  paragraphBreak: boolean;
  edge: boolean;
}

/** Display-only paragraph spacing. Never rewrite provider output or copied text.
 * Fenced/indented literal content keeps its original whitespace geometry.
 */
export function translationTextParts(text: string): TranslationTextPart[] {
  // Provider output is plain text, not Markdown: two-space code/list indentation
  // is meaningful too. Whitespace-only separator lines do not count as code.
  if (/^(?:[ \t]*(`{3,}|~{3,})| {2,}\S|\t+\S)/m.test(text)) {
    return [{ text, paragraphBreak: false, edge: false }];
  }
  const parts: TranslationTextPart[] = [];
  const separator = /(?:\r?\n)[ \t]*(?:\r?\n)(?:[ \t]*(?:\r?\n))*/g;
  let offset = 0;
  for (const match of text.matchAll(separator)) {
    const start = match.index;
    if (start > offset) parts.push({ text: text.slice(offset, start), paragraphBreak: false, edge: false });
    const end = start + match[0].length;
    parts.push({ text: match[0], paragraphBreak: true, edge: start === 0 || end === text.length });
    offset = end;
  }
  if (offset < text.length || parts.length === 0) {
    parts.push({ text: text.slice(offset), paragraphBreak: false, edge: false });
  }
  return parts;
}

export function renderTranslationParagraphs(element: HTMLElement, text: string): void {
  const parts = translationTextParts(text);
  const compact = parts.some(part => part.paragraphBreak);
  element.dataset.paragraphSpacing = compact ? 'compact' : 'literal';
  if (!compact) {
    element.textContent = text;
    return;
  }
  // Every fragment stays inline: block boxes synthesize extra newlines when the
  // browser serializes a mouse selection for copying. A small parent strut lets
  // blank lines shrink, while actual text runs keep the normal reading height.
  const nodes = parts.map((part): Node => {
    const span = document.createElement('span');
    span.className = part.paragraphBreak ? 'result-paragraph-break' : 'result-text-run';
    span.textContent = part.text;
    return span;
  });
  element.replaceChildren(...nodes);
}
