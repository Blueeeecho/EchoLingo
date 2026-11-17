/** Compact display/copy text for a capture or successful translation. Keep
 * each real line and its indentation; only whitespace-only lines are dropped.
 * The original captured text remains available via Restore original breaks. */
export function compactBlankLines(text: string): string {
  return text.split(/\r\n?|\n|\u2028|\u2029/u)
    .filter(line => !/^[\p{Zs}\t\u200b\ufeff]*$/u.test(line))
    .join('\n');
}
