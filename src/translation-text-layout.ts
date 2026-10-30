export interface TranslationTextPart {
  text: string;
  paragraphBreak: boolean;
  edge: boolean;
}

/** Display-only paragraph spacing. Never rewrite provider output or copied text.
 * Fenced/indented literal content keeps its original whitespace geometry.
 */
export function translationTextParts(text: string): TranslationTextPart[] {
  if (/^(?:[ \t]*(`{3,}|~{3,})| {4}|\t)/m.test(text)) {
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
  const nodes = translationTextParts(text).map((part): Node => {
    if (!part.paragraphBreak) return document.createTextNode(part.text);
    const separator = document.createElement('span');
    separator.className = `result-paragraph-break${part.edge ? ' result-paragraph-edge' : ''}`;
    // Keeping the separator as text preserves textContent, selection and accessibility.
    separator.textContent = part.text;
    return separator;
  });
  element.replaceChildren(...nodes);
}
