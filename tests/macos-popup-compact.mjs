// Generated content in production CSS; synthetic browser geometry, not a physical Mac.
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ headless: true, ignoreDefaultArgs: ['--hide-scrollbars'], ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 520, height: 450 } });
  await page.addInitScript(() => Object.defineProperty(navigator, 'platform', { get: () => 'MacIntel' }));
  await page.goto(process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420');
  await page.evaluate(async () => {
    document.body.dataset.view = 'translate'; document.body.classList.add('popup-resize-enabled');
    document.querySelector('#source-text').value = 'A neutral example selected in another application.';
    document.querySelector('.results-column').hidden = false;
    document.querySelector('#results').innerHTML = '<article class="result-card"><header class="result-card-header">Generated fixture</header><p class="result-text">用于验证排版的中性示例。</p></article>';
    const { installPopupScrollbar } = await import('/src/popup-scrollbar.ts'); window.__disposeRail = installPopupScrollbar();
  });
  const geometry = () => page.evaluate(() => {
    const rect = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { left: r.left, right: innerWidth-r.right, width: r.width, height:r.height }; };
    return { header:rect('.popup-toolbar'), source:rect('.source-column'), language:rect('.language-bar'), result:rect('.result-card'),
      sourceFont:getComputedStyle(document.querySelector('#source-text')).fontSize,resultFont:getComputedStyle(document.querySelector('.result-text')).fontSize,
      gutter:document.querySelector('#view-translate').offsetWidth-document.querySelector('#view-translate').clientWidth };
  });
  const short = await geometry();
  assert.equal(short.header.height,28); assert.equal(short.source.left,8);assert.equal(short.source.right,8);
  assert.deepEqual([short.result.left,short.result.right],[8,8]);assert.equal(short.gutter,0);assert.deepEqual([short.language.left,short.language.right],[8,8]);
  assert.deepEqual([short.sourceFont,short.resultFont],['14px','14px']);
  for (const side of ['west','east']) for (const inset of [1,2]) {
    assert.equal(await page.evaluate(({side,inset}) => document.elementFromPoint(side==='west'?inset:innerWidth-inset,30)?.getAttribute('data-window-resize'),{side,inset}),side);
  }
  for (const selector of ['#pin-button','#more-toggle','#close-popup','.translate-trigger']) {
    assert.equal(await page.locator(selector).evaluate(el => {const r=el.getBoundingClientRect();return document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('button')===el;}),true);
  }
  await page.locator('.result-text').evaluate(el => { el.textContent = 'A neutral generated paragraph. 中性示例文本。\n'.repeat(60); });
  await page.locator('.popup-scroll-rail').waitFor({state:'visible'});
  const tall=await geometry();assert.equal(tall.source.width,short.source.width);assert.equal(tall.result.width,short.result.width);assert.equal(tall.gutter,0);
  const rail=page.locator('.popup-scroll-rail'); const box=await rail.boundingBox();assert.equal(box.x+box.width,512);
  await rail.focus();await page.keyboard.press('End');
  assert.equal(await page.locator('#view-translate').evaluate(el => Math.abs(el.scrollHeight-el.clientHeight-el.scrollTop)<2),true);
  await page.keyboard.press('Home');const thumb=await page.locator('.popup-scroll-thumb').boundingBox();
  await page.mouse.move(thumb.x+2,thumb.y+5);await page.mouse.down();await page.mouse.move(thumb.x+2,thumb.y+85);await page.mouse.up();
  assert.ok(await page.locator('#view-translate').evaluate(el=>el.scrollTop)>0);
  await page.keyboard.press('Home');
  await mkdir('test-results',{recursive:true});await page.screenshot({path:'test-results/macos-popup-compact-520.png'});
  await page.setViewportSize({width:760,height:550});await page.screenshot({path:'test-results/macos-popup-compact-760.png'});
  for (const width of [420,680,900]) {
    await page.setViewportSize({width,height:550});
    for (const length of ['short','long']) {
      await page.locator('.result-text').evaluate((el,length) => { el.textContent = length === 'short' ? '用于验证对齐与留白的中性短句。' : 'A neutral generated paragraph. 中性示例文本。\n'.repeat(60); },length);
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const current = await geometry();
      assert.deepEqual([current.source.left,current.source.right,current.result.left,current.result.right],[8,8,8,8]);
      assert.deepEqual([current.sourceFont,current.resultFont],['14px','14px']);
      await page.screenshot({path:`test-results/macos-popup-${length}-${width}.png`});
    }
  }
  console.log(JSON.stringify({ok:true,outerInset:8,toolbar:28,resizeTarget:8,scrollbarSeparate:true,fontsUnchanged:true,physicalMac:false}));
} finally {await browser.close();}
