import { describe, expect, it } from 'vitest';
import { normalizeCapturedText, normalizeOcrCapturedText } from '../src/text-normalization';

describe('OCR Chinese spacing repair', () => {
  it('repairs single spaces between Chinese glyphs and punctuation only for OCR', () => {
    expect(normalizeOcrCapturedText('回 声 译 中 文 测 试 2468')).toBe('回声译中文测试 2468');
    expect(normalizeOcrCapturedText('这 是 测 试 ， 请 继 续 。')).toBe('这是测试，请继续。');
    expect(normalizeCapturedText('回 声 译 中 文')).toBe('回 声 译 中 文');
  });

  it('repairs OCR wraps together with spaces, retaining explicit paragraphs', () => {
    expect(normalizeOcrCapturedText('我 们 正 在\r\n使 用 这 个 功 能')).toBe('我们正在使用这个功能');
    expect(normalizeOcrCapturedText('我 们 正 在\n使 用 这 个 功 能\n\n这 是 新 段 落 。'))
      .toBe('我们正在使用这个功能\n\n这是新段落。');
    expect(normalizeOcrCapturedText('- 第 一 个 项 目\n- 第 二 个 项 目')).toBe('- 第一个项目\n- 第二个项目');
    expect(normalizeOcrCapturedText('# 中 文 标 题\n正 文 内 容 。')).toBe('# 中文标题\n正文内容。');
  });

  it('keeps meaningful Latin, numeric, Korean and mixed-script spacing', () => {
    for (const text of ['English words and quiet_pin', '한국어 문장 사이 공백', '100 000 123', '中文 API 接口 2026 年', '中  文  对  齐']) {
      expect(normalizeOcrCapturedText(text)).toBe(text);
    }
  });

  it('preserves code, configuration, tables, inline literals and indentation', () => {
    for (const text of [
      '```text\n中 文 空 格\n```', '~~~text\n中 文 空 格\n~~~',
      '`中 文` 空 格', '  中 文 缩 进', '中 文\t表 格', '中 文 | 表 格',
      'message: 中 文 配 置', 'const message = "中 文";', 'git commit -m "中 文"',
      '- message: 中 文 配 置', '中 文  对 齐', 'https://example.com/中 文',
    ]) expect(normalizeOcrCapturedText(text)).toBe(text);
  });

  it('retains exact empty rows and whitespace with no eligible prose', () => {
    for (const text of ['', ' ', '\n\n', '  \n\t\n']) expect(normalizeOcrCapturedText(text)).toBe(text);
  });
});

describe('native capture text normalization', () => {
  it('leaves visual wraps without newline and internal spacing unchanged', () => {
    const text = 'This is already one long logical line.  Keep these  spaces, API_IDs and punctuation.';
    expect(normalizeCapturedText(text)).toBe(text);
  });

  it('normalizes CRLF/lone CR and removes discretionary soft hyphens', () => {
    expect(normalizeCapturedText('one\r\ntwo\rthree\u00ad words')).toBe('one\ntwo\nthree words');
    expect(normalizeCapturedText('trans\u00adlation')).toBe('translation');
  });

  it('keeps empty input, spaces, and the exact number of blank lines', () => {
    for (const text of ['', ' ', '  \n\t\n', '\n\n', 'alpha\n\n\nbeta\n']) expect(normalizeCapturedText(text)).toBe(text);
  });

  it('joins long English PDF lines using one boundary space and preserves source order', () => {
    const first = 'This sufficiently long PDF line explains how captured text should';
    const second = 'continue in its original order when the source inserts a visual';
    const third = 'line break inside one sentence.';
    expect(normalizeCapturedText(`${first}\n${second}\n${third}`)).toBe(`${first} ${second} ${third}`);
  });

  it('joins narrow English screenshot rows within an unfinished sentence', () => {
    expect(normalizeCapturedText('With macOS Sonoma,\nwork and play on your\nMac are even more\npowerful.'))
      .toBe('With macOS Sonoma, work and play on your Mac are even more powerful.');
    expect(normalizeCapturedText('Select text in any app\nand press the shortcut\nto translate it.'))
      .toBe('Select text in any app and press the shortcut to translate it.');
    expect(normalizeCapturedText('Our app translates\nEnglish text and\nkeeps the paragraphs.'))
      .toBe('Our app translates English text and keeps the paragraphs.');
  });

  it('keeps blank paragraphs, short completed sentences and structure beside narrow prose', () => {
    const input = 'Select text in any app\nand press the shortcut.\n\n- quiet-pin:\n- another item';
    expect(normalizeCapturedText(input)).toBe('Select text in any app and press the shortcut.\n\n- quiet-pin:\n- another item');
    expect(normalizeCapturedText('This is complete.\nAnother short paragraph')).toBe('This is complete.\nAnother short paragraph');
  });

  it('preserves short shell commands and configuration keys', () => {
    for (const input of [
      'git fetch origin\ngit checkout main\nnpm run build',
      'description: a short description\nenabled: true\nmode: offline',
      '$ echo hello\n$ echo world',
    ]) expect(normalizeCapturedText(input)).toBe(input);
  });

  it('does not borrow continuation evidence across a completed narrow sentence', () => {
    const input = 'This first line wraps\nonto a second line.\nImportant notice\nDo not share this.';
    expect(normalizeCapturedText(input)).toBe('This first line wraps onto a second line.\nImportant notice\nDo not share this.');
  });

  it('joins a split proper name or single-word row within established prose', () => {
    expect(normalizeCapturedText('The weather in San\nFrancisco is nice.')).toBe('The weather in San Francisco is nice.');
    expect(normalizeCapturedText('Please confirm the\npassword\nbefore continuing.')).toBe('Please confirm the password before continuing.');
  });

  it('merges layout boundary spaces without collapsing spaces inside prose', () => {
    const first = 'This sufficiently long captured line contains an ordinary word ';
    expect(normalizeCapturedText(`${first}\n followed by more text.`)).toBe(`${first}followed by more text.`);
    const aligned = 'This sufficiently long line keeps  deliberate spacing inside its content';
    expect(normalizeCapturedText(`${aligned}\ncontinued text.`)).toBe(`${aligned}\ncontinued text.`);
  });

  it('joins long CJK lines without inserting a space', () => {
    const first = '这是从长篇中文文档中识别得到的一行正文，内容仍然没有结束';
    const second = '需要继续连接到下一行，保持原有语序和标点。';
    expect(normalizeCapturedText(`${first}\n${second}`)).toBe(first + second);
  });

  it('handles full-width punctuation and mixed Chinese/English word boundaries', () => {
    const first = '这段中文说明介绍了如何配置自己的 API';
    const second = 'response 以及后续的中文处理，';
    const third = '这些内容应该连续显示。';
    expect(normalizeCapturedText(`${first}\n${second}\n${third}`)).toBe(`${first} ${second}${third}`);
    const chinese = '这段中文说明介绍了如何配置自己的 OCR';
    expect(normalizeCapturedText(`${chinese}\n识别功能及其运行方式。`)).toBe(`${chinese}识别功能及其运行方式。`);
  });

  it('preserves true paragraphs separated by blank lines', () => {
    const first = 'This sufficiently long paragraph contains several meaningful words';
    const next = 'This is a separate paragraph and must stay separate from the previous one.';
    expect(normalizeCapturedText(`${first}\n\n${next}`)).toBe(`${first}\n\n${next}`);
  });

  it('keeps short paragraph endings before a new full-width paragraph', () => {
    const first = 'This sufficiently long paragraph begins with a line that was wrapped';
    const ending = 'and ends right here.';
    const next = 'Another sufficiently long paragraph begins with its own separate statement.';
    expect(normalizeCapturedText(`${first}\n${ending}\n${next}`)).toBe(`${first} ${ending}\n${next}`);
    const chinese = '这是一段较长的中文正文，在这里开始讲述一个需要换行显示的完整内容';
    const chineseEnding = '到此结束。';
    const chineseNext = '这是另外一段较长的中文正文，应该继续保留它与上一个段落之间的边界。';
    expect(normalizeCapturedText(`${chinese}\n${chineseEnding}\n${chineseNext}`)).toBe(`${chinese}${chineseEnding}\n${chineseNext}`);
  });

  it('keeps short Latin paragraphs, poetry, and very short dialog fragments', () => {
    for (const text of ['A short first paragraph\nAnother short paragraph', 'The quiet moon\nAbove the silent sea\nA distant light', '甲说。\n乙说。']) expect(normalizeCapturedText(text)).toBe(text);
  });

  it('merges automatic wraps that happen to fall after a full stop', () => {
    const first = 'This sufficiently long sentence ends at the visual edge of a PDF line.';
    const next = 'The next sufficiently long sentence belongs to the same captured paragraph.';
    expect(normalizeCapturedText(`${first}\n${next}`)).toBe(`${first} ${next}`);
    const chinese = '这是第一句中文正文，在这里恰好遇到截图产生的自动换行。';
    const chineseNext = '这是第二句中文正文，它仍然属于同一个需要连续显示的段落。';
    expect(normalizeCapturedText(`${chinese}\n${chineseNext}`)).toBe(chinese + chineseNext);
  });

  it('merges similarly narrow CJK screenshot rows including sentence punctuation', () => {
    for (const [text, expected] of [
      ['这是短行正文\n这里继续正文\n保持顺序。', '这是短行正文这里继续正文保持顺序。'],
      ['第一句话。\n第二句话。\n第三句话。', '第一句话。第二句话。第三句话。'],
      ['窄截图内容，\n继续下一行，\n最后一行。', '窄截图内容，继续下一行，最后一行。'],
    ]) expect(normalizeCapturedText(text)).toBe(expected);
  });

  it('preserves paragraph indentation, Markdown hard breaks, and tabs', () => {
    for (const text of [
      'A sufficiently long prose line may visually wrap inside its sentence\n  A new indented paragraph starts here.',
      '　　这是一个具有明显全角缩进的较长中文段落\n下一行保持原样。',
      'This sufficiently long text intentionally has a Markdown hard break  \ncontinued here',
      '\tIndented code or source text\nnext line',
    ]) expect(normalizeCapturedText(text)).toBe(text);
  });

  it('preserves numbered, bulleted, checkbox, and Chinese lists', () => {
    for (const text of [
      '- first item\n  wrapped detail\n- second item', '1. first item\n2. second item',
      '• 第一条\n• 第二条', '一、第一部分\n二、第二部分', '(1) first\n(2) second',
      '[x] finished\n[ ] pending',
    ]) expect(normalizeCapturedText(text)).toBe(text);
  });

  it('preserves headings and colon-introduced structures', () => {
    for (const text of [
      '# A heading\nThe following paragraph begins here.', 'INTRODUCTION\nThe following paragraph begins here.',
      'A Short Heading\nThis sufficiently long paragraph contains several meaningful words\ncontinued here.',
      '1 Introduction\nThe following paragraph begins here.',
      'This sufficiently long introductory sentence ends with an explicit colon:\nThe First Item',
    ]) {
      const result = normalizeCapturedText(text);
      expect(result.split('\n')[0]).toBe(text.split('\n')[0]);
    }
    const title = '方法与结果\n这是下一段足够长的中文内容，它需要保留清楚可读的章节标题。';
    expect(normalizeCapturedText(title)).toBe(title);
  });

  it('keeps fenced code intact including long unindented strings', () => {
    const code = '```text\nThis very long unindented line inside a code fence must preserve\nits exact newline structure\n```\nAfter the block.';
    expect(normalizeCapturedText(code)).toBe(code);
    const tilde = '~~~\nSome sufficiently long text which is still a literal code sample\ncontinued literally\n~~~';
    expect(normalizeCapturedText(tilde)).toBe(tilde);
  });

  it('preserves source code, JSON, HTML, tables, and aligned columns', () => {
    for (const text of [
      'if (ready) {\n    return value;\n}', 'const result = callWithALongDescriptiveArgumentName(\nnextArgument);',
      '// This long source comment must keep the following code boundary intact\n} else {\n    return value;\n}',
      '{\n"description": "A sufficiently long JSON value must not join the next row",\n"other": "value"\n}',
      '<div>\nSome sufficiently long text is still part of an HTML source example\n</div>',
      '| first | second |\n| --- | --- |\n| one | two |', 'name\tvalue\nfirst\tsecond',
      'name  value\nfirst  second',
      'first_column_name,second_column_name,third_column_name,fourth_column_name\nfirst_value,second_value,third_value,fourth_value',
    ]) expect(normalizeCapturedText(text)).toBe(text);
  });

  it('preserves URL and email line breaks instead of attempting to repair them', () => {
    for (const text of [
      'See https://example.com/a-\nb for details.',
      'This sufficiently long line contains a URL https://example.com/path\ncontinued here',
      'Contact person@example.\ncom for details.',
      'This sufficiently long line provides an address: person@example.\ncom for details.',
      'This sufficiently long line provides an address: person@\nexample.com for details.',
      'This sufficiently long line explains an ordinary continuation\nhttps://example.com/',
    ]) expect(normalizeCapturedText(text)).toBe(text);
  });

  it('keeps unindented function calls as separate statements', () => {
    for (const code of [
      'print("This sufficiently long unindented Python call must remain a separate statement")\nprint("second statement")',
      'console.log("This sufficiently long unindented JavaScript call is a separate statement");\nconsole.log("second statement");',
      'await client.send("This sufficiently long unindented async call must keep its newline")\nawait client.close()',
    ]) expect(normalizeCapturedText(code)).toBe(code);
  });

  it('keeps unindented assignments and line comments separate from following code', () => {
    for (const code of [
      'long_variable_name = "This long Python assignment should remain a separate statement"\nsecond_variable = "second statement"',
      'state.longPropertyName += "This long augmented assignment must remain a separate statement"\nstate.secondProperty = "next"',
      '# This sufficiently long Python comment must not absorb the following statement\npass',
      '-- This sufficiently long SQL comment must not absorb the following query\nSELECT value FROM example',
    ]) expect(normalizeCapturedText(code)).toBe(code);
  });

  it('repairs an explicit soft-hyphen line break without adding a space', () => {
    expect(normalizeCapturedText('inter\u00ad\nnational')).toBe('international');
    expect(normalizeCapturedText('trans\u00ad\r\nlation')).toBe('translation');
    expect(normalizeCapturedText('inter\u00ad\n\nnational')).toBe('inter\n\nnational');
  });

  it('keeps ordinary ASCII hyphens rather than guessing whether they were discretionary', () => {
    const first = 'This sufficiently long PDF line explains how the trans-';
    expect(normalizeCapturedText(`${first}\nlation engine behaves.`)).toBe('This sufficiently long PDF line explains how the trans-lation engine behaves.');
    expect(normalizeCapturedText('trans-\nlation')).toBe('trans-\nlation');
  });

  it('retains existing compounds when joining a long wrapped line', () => {
    for (const [ending, continuation, compound] of [
      ['well-', 'known example.', 'well-known example.'],
      ['state-of-the-', 'art example.', 'state-of-the-art example.'],
      ['re-', 'creation example.', 're-creation example.'],
      ['co-', 'operation example.', 'co-operation example.'],
      ['X-', 'ray example.', 'X-ray example.'],
      ['T-', 'Shirt example.', 'T-Shirt example.'],
      ['über-', 'regional example.', 'über-regional example.'],
    ]) {
      const start = 'This sufficiently long captured paragraph describes a ';
      expect(normalizeCapturedText(`${start}${ending}\n${continuation}`)).toBe(start + compound);
    }
  });

  it('does not reorder or flatten consecutive captured paragraphs', () => {
    const one = 'The first sufficiently long captured line describes the first';
    const two = 'piece of text.';
    const three = 'The second sufficiently long captured line describes another';
    const four = 'piece of text.';
    expect(normalizeCapturedText(`${one}\r\n${two}\r\n\r\n${three}\r\n${four}`)).toBe(`${one} ${two}\n\n${three} ${four}`);
  });

  it('handles supplementary CJK characters at a join without splitting a surrogate pair', () => {
    const first = '这里是足够长的中文正文，最后一个扩展汉字是𠀀';
    expect(normalizeCapturedText(`${first}\n继续识别其余文字。`)).toBe(`${first}继续识别其余文字。`);
  });
});
