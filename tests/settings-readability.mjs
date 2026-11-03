// Focused production-DOM typography/layout checks. No native app, real keys,
// service requests, or provider activation. Start npm run dev first.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';

const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
const fontSize = (locator) => locator.evaluate(el => parseFloat(getComputedStyle(el).fontSize));
const fits = async (page, selector) => {
  const overflow = await page.locator(selector).evaluateAll(roots => roots.flatMap(root => [root, ...root.querySelectorAll('*')]).filter(el => {
    const box = el.getBoundingClientRect();
    return box.width > 0 && box.height > 0 && (box.left < -1 || box.right > innerWidth + 1);
  }).map(el => `${el.tagName}#${el.id}.${el.className}`));
  assert.deepEqual(overflow, [], `horizontal overflow within ${selector}`);
};
try {
  for (const platform of ['MacIntel', 'Win32']) {
    const page = await browser.newPage({ viewport: { width: 1000, height: 850 }, locale: 'zh-CN' });
    const errors = [], externalRequests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(origin) && !request.url().startsWith('data:')) externalRequests.push(request.url()); });
    await page.addInitScript(value => Object.defineProperty(navigator, 'platform', { configurable: true, get: () => value }), platform);
    await page.goto(origin);
    const sourceFont = await fontSize(page.locator('#source-text'));
    await page.locator('#more-toggle').click();
    await page.locator('#popup-more-menu [data-view="settings"]').click();
    await page.locator('#free-region-cn').click();
    await page.locator('#free-translation-summary').click();
    await page.locator('#free-ocr-summary').click();

    for (const theme of ['light', 'dark']) {
      await page.locator('#theme-select').selectOption(theme);
      for (const width of [420, 640, 900, 1000]) {
        await page.setViewportSize({ width, height: 850 });
        await page.mouse.move(0, 0);
        await fits(page, '#view-settings');
        for (const selector of ['.settings-card-heading p', '.field-help', '.free-service small']) {
          assert.ok(await fontSize(page.locator(`#view-settings ${selector}`).first()) >= 13, `${selector} remains readable at ${width}px`);
        }
        for (const selector of ['#theme-select', '#max-history', '#add-provider', '#free-translation-list .free-service p']) {
          assert.ok(await fontSize(page.locator(selector).first()) >= 14, `${selector} readable controls/body`);
        }
        assert.ok(await fontSize(page.locator('#view-settings h2').first()) >= 17);
        const actions = page.locator('#free-translation-list .free-service-actions').first();
        for (const action of await actions.locator('button, a').all()) {
          const style = await action.evaluate(el => {
            const value = getComputedStyle(el);
            return { color: value.color, decoration: value.textDecorationLine, cursor: value.cursor, height: el.getBoundingClientRect().height };
          });
          assert.equal(style.color, theme === 'dark' ? 'rgb(138, 180, 255)' : 'rgb(24, 90, 188)');
          assert.ok(style.decoration.includes('underline')); assert.equal(style.cursor, 'pointer'); assert.ok(style.height >= 36);
        }
        const official = actions.locator('a');
        assert.match(await official.getAttribute('href'), /^https:\/\//);
        assert.equal(await official.getAttribute('rel'), 'noopener noreferrer');
        await official.press('Tab');
        await page.keyboard.press('Shift+Tab');
        assert.equal(await official.evaluate(el => getComputedStyle(el).outlineStyle), 'solid');
        assert.ok(await official.evaluate(el => parseFloat(getComputedStyle(el).outlineWidth)) >= 2);
        if (width === 420 || width === 1000) {
          await page.locator('[data-free-service="siliconflow"]').screenshot({ path: `test-results/service-manager-readability-${platform}-${theme}-${width}.png` });
        }

        // Repeated opening/cancel must leave the recommendation disclosure intact.
        await actions.locator('button').click();
        assert.equal(await page.locator('#free-setup-dialog').isVisible(), true);
        await fits(page, '#free-setup-dialog .provider-dialog');
        assert.equal(await page.locator('#free-setup-body > a').count(), 1);
        assert.ok(await fontSize(page.locator('#free-setup-body input').first()) >= 14);
        await page.keyboard.press('Escape');
        assert.equal(await page.locator('#free-setup-dialog').isVisible(), false);
        assert.equal(await page.locator('#free-translation-section').evaluate(el => el.open), true);

        await page.locator('#add-provider').click();
        await page.locator('#provider-preset').selectOption('siliconflow');
        await page.locator('#provider-service-guide summary').click();
        await fits(page, '#provider-dialog .provider-dialog');
        assert.ok(await fontSize(page.locator('#provider-model')) >= 14);
        assert.ok(await fontSize(page.locator('#provider-service-guide .service-quota-details')) >= 13);
        assert.equal(await page.locator('#provider-service-guide a').first().evaluate(el => getComputedStyle(el).textDecorationLine), 'underline');
        if (width === 420) await page.screenshot({ path: `test-results/service-manager-add-readable-${platform}-${theme}.png` });
        await page.locator('#cancel-provider-dialog').click();
        await page.locator('#add-ocr-provider').click();
        await page.locator('#ocr-provider-kind').selectOption('azure-vision');
        await fits(page, '#ocr-provider-dialog .provider-dialog');
        await page.locator('#cancel-ocr-provider-dialog').click();

        await page.locator('#open-service-manager').click();
        await page.locator('[data-service-role="ocr"]').click();
        await fits(page, '#view-services');
        await page.locator('.managed-service-select').first().click();
        await fits(page, '#view-services');
        if (width <= 640) {
          assert.equal(await page.locator('.service-manager-master').isVisible(), false);
          await page.locator('.managed-service-back').click();
          assert.equal(await page.locator('.service-manager-master').isVisible(), true);
        }
        await page.locator('#service-manager-advanced').click();
      }
    }
    await page.locator('.management-header [data-view="translate"]').click();
    assert.equal(await fontSize(page.locator('#source-text')), sourceFont, 'settings styles do not resize translation text');
    assert.deepEqual(errors, []); assert.deepEqual(externalRequests, []);
    await page.close();
  }
  console.log('PASS: readable settings/forms, blue underlined keyboard links, repeated cancel/reopen, 420–1000px layout, light/dark and macOS/Windows DOM branches. Browser-only, no native font claim.');
} finally { await browser.close(); }
