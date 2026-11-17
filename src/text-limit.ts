/** Match Rust str::chars(): Unicode code points, not UTF-16 code units. */
export function codePointLength(text: string): number {
  let length = 0;
  for (const _ of text) length += 1;
  return length;
}
export function truncateCodePoints(text: string, maximum: number): string {
  let offset = 0, length = 0;
  for (const character of text) {
    if (length >= maximum) break;
    offset += character.length; length += 1;
  }
  return text.slice(0, offset);
}
/** Textarea selection positions remain UTF-16 offsets; never split a pair. */
export function safeTextRange(text: string, start: number, end: number): [number, number] {
  const insidePair = (offset: number) => offset > 0 && offset < text.length
    && /[\uD800-\uDBFF]/.test(text[offset - 1]) && /[\uDC00-\uDFFF]/.test(text[offset]);
  return [insidePair(start) ? start - 1 : start, insidePair(end) ? end + 1 : end];
}
