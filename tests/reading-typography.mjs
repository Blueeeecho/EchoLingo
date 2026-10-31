// Focused browser CSS regression, not native OS font/glyph verification.
// Start npm run dev; optionally set ECHOLINGO_TEST_URL / ECHOLINGO_TEST_CHROMIUM.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';

const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage();
  await page.goto(process.env.ECHOLINGO_TEST_URL ?? 'http://127.0.0.1:1420/');
  await page.locator('#source-text').waitFor();
  const fixtures = ['中文与 English Ág gjpq.', 'First paragraph.\n\nSecond paragraph.\nThird line.', 'const values = [1, 2];\n  return values;\n\n```js\n  code\n```', 'https://example.invalid/' + 'LongToken'.repeat(80)];
  for (const platform of ['macos', 'windows']) {
    for (const width of [520, 1000]) {
      await page.setViewportSize({ width, height: 820 });
      for (const text of fixtures) {
        const metrics = await page.evaluate(async ({ platform, text }) => {
          const { renderTranslationParagraphs } = await import('/src/translation-text-layout.ts');
          document.documentElement.dataset.platform = platform;
          document.body.dataset.view = 'translate';
          const source = document.querySelector('#source-text');
          source.value = text;
          const container = document.querySelector('.results-container');
          container.innerHTML = '<article class="result-card"><p class="result-text"></p></article>';
          const result = container.querySelector('.result-text');
          renderTranslationParagraphs(result, text);
          const run = result.querySelector('.result-text-run') ?? result;
          const props = ['fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'letterSpacing', 'padding', 'margin', 'textAlign', 'textAlignLast', 'whiteSpace', 'wordBreak', 'overflowWrap'];
          const styles = element => Object.fromEntries(props.map(prop => [prop, getComputedStyle(element)[prop]]));
          const selection = window.getSelection(), range = document.createRange();
          range.selectNodeContents(result); selection.removeAllRanges(); selection.addRange(range);
          const selected = selection.toString(); selection.removeAllRanges();
          return { source: styles(source), result: styles(result), runHeight: getComputedStyle(run).lineHeight,
            sourceLeft: source.getBoundingClientRect().left, resultLeft: result.getBoundingClientRect().left,
            sourceText: source.value, resultText: result.textContent, selected, compact: result.dataset.paragraphSpacing,
            overflow: source.scrollWidth > source.clientWidth + 1 || result.scrollWidth > result.clientWidth + 1 };
        }, { platform, text });
        // Blank paragraph lines deliberately stay compact only in the read-only
        // renderer; normal text lines and all literal/code lines share density.
        metrics.result.lineHeight = metrics.runHeight;
        assert.deepEqual(metrics.source, metrics.result, `${platform}/${width}: shared text styling`);
        assert.equal(metrics.source.fontSize, platform === 'windows' ? '16px' : '14px');
        assert.ok(Math.abs(parseFloat(metrics.source.lineHeight) / parseFloat(metrics.source.fontSize) - 1.45) < .01);
        assert.ok(Math.abs(metrics.sourceLeft - metrics.resultLeft) < 1, 'matching left text inset');
        assert.equal(metrics.sourceText, text); assert.equal(metrics.resultText, text); assert.equal(metrics.selected, text);
        assert.equal(metrics.overflow, false);
        if (text.includes('```')) assert.equal(metrics.compact, 'literal');
        await page.locator('#source-text').fill('Still editable 中文');
        assert.equal(await page.locator('#source-text').inputValue(), 'Still editable 中文');
      }
    }
  }
  console.log('PASS: shared typography, left inset, density, editable source, literal code and paragraph selection across macOS/Windows CSS and narrow/wide viewports. Browser only; no native glyph claim.');
} finally { await browser.close(); }
