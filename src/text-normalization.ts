/**
 * Normalize native selection/OCR text, never text typed or pasted by the user.
 * Plain text has no layout coordinates: a hard wrap and a paragraph boundary
 * can be identical. Keep uncertain boundaries instead of flattening everything.
 */

const CJK = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\u3000-\u303f\uff00-\uffef]/u;
const CJK_LETTER = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;
const LETTER = /\p{L}/u;
const SENTENCE_END = /[.!?。！？]["'”’」』）)\]]*$/u;
const COLON_END = /[:：]["'”’」』）)\]]*$/u;

interface CapturedLine {
  text: string;
  content: string;
  width: number;
  blockWidth: number;
  blockContinuation: boolean;
  protected: boolean;
  softBreak: boolean;
}

function displayWidth(text: string): number {
  let width = 0;
  for (const character of text) width += CJK.test(character) ? 2 : 1;
  return width;
}

function obviousStructure(text: string): boolean {
  const content = text.trim();
  if (!content) return true;
  // Paragraph/code indentation, Markdown hard breaks, TSV and aligned columns.
  if (/^(?:\t| {2,}|\u3000)/u.test(text) || / {2,}$/u.test(text) || text.includes('\t')) return true;
  if (/\S {2,}\S/u.test(content) || content.includes('|') || content.includes('`')) return true;
  if (/^(?:#{1,6}\s|>\s?|[-+*•▪▫‣⁃◦]\s|\[[ xX]\]\s)/u.test(content)) return true;
  if (/^(?:\d{1,4}[.)、．]\s*|[A-Za-z][.)]\s+|[一二三四五六七八九十百]+[、.)．]\s*|[（(][\d一二三四五六七八九十]+[）)]\s*)/u.test(content)) return true;
  if (/^(?:[-*_]\s*){3,}$/u.test(content) || /^[=~-]{3,}$/u.test(content)) return true;
  if (/^\d+(?:\.\d+)*\s+\p{Lu}/u.test(content) || /^\d+$/u.test(content)) return true;
  // URLs/emails and code are safer left intact, including their line breaks.
  if (/(?:https?:\/\/|ftp:\/\/|www\.)|\b[^\s@]+@/iu.test(content)) return true;
  if (/^[^,\s]+(?:,[^,\s]*){2,}$/u.test(content)) return true;
  if (/^(?:[{}[\]]\s*[,;]?|["'][^"']+["']\s*:.*)$/u.test(content)) return true;
  // Bare YAML/configuration keys and obvious shell commands keep executable
  // line boundaries even when they are as short as a narrow prose capture.
  if (/^[\p{L}_][\p{L}\d_.-]*\s*:\s+\S/u.test(content)) return true;
  if (/^(?:\$\s+\S|(?:git|npm|npx|pnpm|yarn|bun|cargo|rustc|python[\d.]*|pip[\d.]*|node|deno|cmake|bash|zsh|pwsh|powershell|docker|kubectl|curl|wget|ssh|sudo)\s+\S)/u.test(content)) return true;
  if (/^(?:\/\/|\/\*|\*\/?\s|#|--\s|(?:import|from)\s|(?:try|else|finally)\s*[{:]|\}\s*(?:else|catch|finally)\b)/u.test(content)) return true;
  if (/^(?:await\s+)?[\p{L}_$][\p{L}\d_$]*(?:\.[\p{L}_$][\p{L}\d_$]*)*\(/u.test(content)) return true;
  if (/^[\p{L}_$][\p{L}\d_$]*(?:\.[\p{L}_$][\p{L}\d_$]*|\[[^\]]+\])*\s*(?::\s*[\p{L}\d_[\],.| ]+\s*)?(?:[+\-*/%&|^<>?]{0,3}=|:=)/u.test(content)) return true;
  if (/^(?:(?:export\s+)?(?:const|let|var)\s+\w+\s*[=:]|(?:async\s+)?function\b|(?:async\s+)?def\s+\w+\s*\(|class\s+\w+|(?:if|for|while|switch|catch)\s*\(|(?:return|throw)\s+.*[;{}]$|<\/?[A-Za-z][^>]*>)/u.test(content)) return true;
  // Short titles/all-caps lines are not evidence of body-text wrapping.
  const words = content.split(/\s+/u);
  if (content.length <= 100 && !CJK.test(content) && /[A-Z]/u.test(content) && !/[a-z]/u.test(content)) return true;
  if (content.length <= 64 && words.length <= 8 && words.every((word) => /^(?:[A-Z][\p{L}\d'’-]*|of|the|and|in|for|to|a|an|on)$/u.test(word))) return true;
  return false;
}

function linesWithStructure(text: string): CapturedLine[] {
  let fence: { character: string; length: number } | null = null;
  const lines = text.split('\n').map((original) => {
    const text = original.replace(/\u00ad/gu, '');
    const content = text.trim();
    const marker = /^\s{0,3}(`{3,}|~{3,})/u.exec(text)?.[1];
    let fenced = fence !== null;
    if (marker) {
      fenced = true;
      if (!fence) fence = { character: marker[0], length: marker.length };
      else if (marker[0] === fence.character && marker.length >= fence.length && new RegExp(`^\\s{0,3}${fence.character}{${fence.length},}\\s*$`, 'u').test(text)) fence = null;
    }
    return {
      text, content, width: displayWidth(content), blockWidth: 0, blockContinuation: false, protected: fenced || obviousStructure(text),
      softBreak: /\p{Script=Latin}\u00ad[ \t]*$/u.test(original),
    };
  });
  // Compare a possible paragraph-ending short line with its surrounding prose
  // block. Blank lines and recognizable structure stop the width comparison.
  for (let start = 0; start < lines.length;) {
    if (lines[start].protected) { start++; continue; }
    let end = start;
    let width = 0;
    while (end < lines.length && !lines[end].protected) {
      width = Math.max(width, lines[end].width); end++;
    }
    for (let index = start; index < end; index++) {
      lines[index].blockWidth = width;
    }
    // A completed sentence must not lend its continuation evidence to a later
    // short title or a new paragraph that happens to lack a blank separator.
    for (let groupStart = start; groupStart < end;) {
      let groupEnd = groupStart + 1;
      while (groupEnd < end && !SENTENCE_END.test(lines[groupEnd - 1].content)
        && !COLON_END.test(lines[groupEnd - 1].content)) groupEnd++;
      const continuation = lines.slice(groupStart, groupEnd - 1).some((line, offset) =>
        narrowContinuation(line, lines[groupStart + offset + 1]));
      for (let index = groupStart; index < groupEnd; index++) lines[index].blockContinuation = continuation;
      groupStart = groupEnd;
    }
    start = end;
  }
  return lines;
}

function narrowContinuation(left: CapturedLine, right: CapturedLine): boolean {
  if (SENTENCE_END.test(left.content) || COLON_END.test(left.content)) return false;
  if (left.width < 12 || left.content.split(/\s+/u).length < 2) return false;
  // A lower-case continuation is useful evidence even in a narrow screenshot.
  // Tiny one-word rows, capitalized poetry and titles remain ambiguous.
  return /^\p{Ll}/u.test(right.content);
}

function longProseLine(line: CapturedLine): boolean {
  // Roughly 32 Latin columns or 16 CJK glyphs. Narrower prose needs additional
  // continuation evidence rather than a desktop-sized line-width assumption.
  // A comma/semicolon is additional evidence of an unfinished sentence, useful
  // for somewhat narrower OCR lines without treating tiny fragments as prose.
  return line.width >= 32
    || (line.width >= 24 && /[,，;；]$/u.test(line.content));
}

function canJoin(left: CapturedLine, right: CapturedLine): boolean {
  if (!left.content || !right.content || left.protected || right.protected) return false;
  if (left.softBreak && /\p{Script=Latin}$/u.test(left.content) && /^\p{Ll}/u.test(right.content)) return true;
  if (COLON_END.test(left.content) || !LETTER.test(left.content) || !LETTER.test(right.content)) return false;
  const cjkPair = CJK_LETTER.test(left.content) && CJK_LETTER.test(right.content);
  if (cjkPair) {
    // Narrow screenshot columns can contain only a few CJK characters per row.
    // Do not treat every short line or every full stop as a new paragraph.
    let glyphs = 0;
    for (const character of left.content) if (CJK_LETTER.test(character) && ++glyphs >= 3) break;
    if (glyphs < 3 && !longProseLine(left)) return false;
  } else if (!longProseLine(left)) {
    const continuedBlock = left.blockContinuation && !SENTENCE_END.test(left.content)
      && (left.width >= 12 && left.content.split(/\s+/u).length >= 2
        || left.width >= 4 && /^\p{Ll}/u.test(right.content));
    const danglingWord = left.width >= 8
      && /\b(?:a|an|the|and|or|to|of|in|at|on|for|with|by|from|your|our|their|its)$/iu.test(left.content);
    const splitName = left.width >= 12 && /\b(?:in|at|from|to|near)\s+\p{Lu}\p{Ll}+$/u.test(left.content)
      && /^\p{Lu}\p{Ll}/u.test(right.content);
    if (!narrowContinuation(left, right) && !continuedBlock && !danglingWord && !splitName) return false;
  }
  const reference = left.blockWidth;
  if (reference >= 32 && left.width < reference * 0.68 && right.width >= reference * 0.78) {
    if (SENTENCE_END.test(left.content) || left.width < reference * 0.5) return false;
  }
  return true;
}

function appendWrapped(left: string, right: CapturedLine, previous: CapturedLine): string {
  const before = left.replace(/[ \t]+$/u, '');
  const after = right.text.replace(/^[ \t]+/u, '');
  if (previous.softBreak) return before + after;

  if (/\p{Script=Latin}[-‐‑]$/u.test(previous.content) && /^\p{Script=Latin}/u.test(after)) {
    // ASCII hyphens are ambiguous: do not guess whether a word was originally
    // hyphenated. Only an explicit soft hyphen is removed; compounds survive.
    return before + after;
  }
  const finalUnit = before.charCodeAt(before.length - 1);
  const last = before.slice(finalUnit >= 0xdc00 && finalUnit <= 0xdfff ? -2 : -1);
  const first = String.fromCodePoint(after.codePointAt(0) ?? 0);
  const separator = CJK.test(last) || CJK.test(first) ? '' : ' ';
  return before + separator + after;
}

export function normalizeCapturedText(text: string): string {
  const normalized = text.replace(/\r\n?/gu, '\n');
  if (!normalized.includes('\n')) return normalized.replace(/\u00ad/gu, '');
  const lines = linesWithStructure(normalized);
  const result: string[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    const previous = lines[index - 1];
    if (previous && canJoin(previous, line)) {
      result[result.length - 1] = appendWrapped(result[result.length - 1], line, previous);
    } else result.push(line.text);
  }
  return result.join('\n');
}

/** OCR can return a space between every Chinese glyph. Limit this repair to
 * prose from OCR; spaces in selected/typed text, Latin words, Korean, numbers,
 * aligned columns and executable text are not evidence of an OCR artifact. */
export function normalizeOcrCapturedText(text: string): string {
  let fence: { character: string; length: number } | null = null;
  const cleaned = text.replace(/\r\n?/gu, '\n').split('\n').map((line) => {
    const marker = /^\s{0,3}(`{3,}|~{3,})/u.exec(line)?.[1];
    if (marker) {
      if (!fence) fence = { character: marker[0], length: marker.length };
      else if (marker[0] === fence.character && marker.length >= fence.length
        && new RegExp(`^\\s{0,3}${fence.character}{${fence.length},}\\s*$`, 'u').test(line)) fence = null;
      return line;
    }
    if (fence) return line;
    // Keep list/heading boundaries while allowing prose within them to repair.
    // Do not strip indentation before the structural safety check.
    const prefix = /^(?:#{1,6} |[-+*•▪▫‣⁃◦] |\[[ xX]\] |\d{1,4}[.)、．] ?|[一二三四五六七八九十百]+[、.)．] ?|[（(][\d一二三四五六七八九十]+[）)] ?)/u.exec(line)?.[0] ?? '';
    const body = line.slice(prefix.length);
    if (obviousStructure(body)) return line;
    // A lookahead leaves the right glyph available to repair the next pair.
    // Only a single ASCII space is eligible; wide spacing can be layout.
    const repaired = body.replace(/([\p{Script=Han}，。！？；：、（）「」『』【】《》“”‘’]) (?=[\p{Script=Han}，。！？；：、（）「」『』【】《》“”‘’])/gu, '$1');
    return prefix + repaired;
  }).join('\n');
  return normalizeCapturedText(cleaned);
}
