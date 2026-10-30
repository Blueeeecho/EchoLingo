// Production settings DOM and read-only public quota data. No credentials,
// external account calls or installed application control.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  for (const platform of ['MacIntel', 'Win32']) {
    const page = await browser.newPage({ viewport: { width: 900, height: 850 } });
    const errors = [], externalRequests = []; page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(origin) && !request.url().startsWith('data:')) externalRequests.push(request.url()); });
    await page.addInitScript(value => Object.defineProperty(navigator, 'platform', { configurable: true, get: () => value }), platform);
    await page.goto(origin);
    await page.locator('#more-toggle').click(); await page.locator('#popup-more-menu button[data-view="settings"]').click();
    await page.locator('#add-provider').waitFor({ state:'visible' });
    assert.match(await page.locator('#ocr-quota-card').innerText(), /本机免费/);
    assert.equal(await page.locator('#active-ocr-provider').inputValue(),'');
    assert.match(await page.locator('#active-ocr-provider option').textContent(),/免费/);
    const data = await page.evaluate(async () => { const value=await import('/src/service-quotas.ts'); return {translation:value.TRANSLATION_QUOTAS,ocr:value.OCR_QUOTAS,date:value.SERVICE_QUOTA_CHECKED_ON}; });
    await page.locator('#add-provider').click();
    const recommendations=await page.locator('#provider-preset option[data-recommended="true"]').evaluateAll(options=>options.map(option=>option.value));
    assert.deepEqual(recommendations,[platform==='MacIntel'?'system':'offline','microsoft','baidu','siliconflow']);
    assert.equal(await page.locator('#provider-preset option').count(),Object.keys(data.translation).length,'No preset is duplicated or omitted by recommendation grouping.');
    for (const [preset,quota] of Object.entries(data.translation)) {
      await page.locator('#provider-preset').selectOption(preset);
      const card=page.locator('#provider-service-guide .service-quota');
      assert.equal(await card.locator('.service-quota-badge').innerText(),quota.badge);
      assert.equal(await card.locator('.service-quota-summary').innerText(),quota.summary);
      assert.match(await card.locator('.service-quota-date').innerText(),new RegExp(quota.checkedOn));
      await card.locator('summary').click();
      const text=await card.innerText();
      for (const allowance of quota.allowances) {
        assert.ok(text.includes(allowance.plan));
        if(allowance.amount!==null)assert.ok(text.includes(allowance.amount.toLocaleString('zh-CN')));
        for(const condition of allowance.conditions)assert.ok(text.includes(condition));
        if(allowance.expires)assert.ok(text.includes(allowance.expires));
      }
      for(const detail of quota.details)assert.ok(text.includes(detail));
      for(const [label,url] of quota.links) {
        const link=card.getByRole('link',{name:`${label} ↗`,exact:true}); assert.equal(await link.getAttribute('href'),url);
        assert.equal(await link.getAttribute('data-service-link'),'true'); assert.equal(await link.getAttribute('rel'),'noopener noreferrer');
      }
    }
    await page.locator('#provider-preset').selectOption('deepl');
    await page.locator('#provider-service-guide .service-quota summary').click();
    assert.match(await page.locator('#provider-service-guide .service-quota').innerText(),/1,000,000 字符 · 一次性/);
    assert.match(await page.locator('#provider-service-guide .service-quota').innerText(),/500,000 字符 \/ 月/);
    await page.locator('#provider-preset').selectOption('siliconflow');
    assert.equal(await page.locator('#provider-model').inputValue(),'tencent/Hunyuan-MT-7B');
    await page.locator('#provider-model').fill('existing-paid-model');
    assert.equal(await page.locator('#provider-model').inputValue(),'existing-paid-model','Read-only quota updates must not replace a current model.');
    assert.match(await page.locator('.service-quota-model-note').innerText(),/existing-paid-model.*不适用上述免费模型价格/);
    // Rebuilding recommendation labels retains an existing selection, and
    // does not dispatch change or touch the current API form/model.
    await page.evaluate(async () => { const {populateProviderPresets}=await import('/src/service-quota-ui.ts'); populateProviderPresets(document.querySelector('#provider-preset'),document.documentElement.dataset.platform); });
    assert.equal(await page.locator('#provider-preset').inputValue(),'siliconflow');
    assert.equal(await page.locator('#provider-model').inputValue(),'existing-paid-model');
    await page.locator('#cancel-provider-dialog').click();
    await page.locator('#add-ocr-provider').click();
    for(const [kind,quota] of Object.entries(data.ocr)) {
      if(kind==='local')continue;
      await page.locator('#ocr-provider-kind').selectOption(kind);
      const card=page.locator('#ocr-service-guide .service-quota');
      assert.equal(await card.locator('.service-quota-badge').innerText(),quota.badge);
      assert.equal(await card.locator('.service-quota-summary').innerText(),quota.summary);
      assert.match(await card.locator('.service-quota-date').innerText(),new RegExp(quota.checkedOn));
      await card.locator('summary').click();
      const text=await card.innerText();
      for(const allowance of quota.allowances)for(const condition of allowance.conditions)assert.ok(text.includes(condition));
      for(const [label,url] of quota.links)assert.equal(await card.getByRole('link',{name:`${label} ↗`,exact:true}).getAttribute('href'),url);
      assert.equal(await page.locator('#active-ocr-provider').inputValue(),'','Inspecting a cloud service must not enable it.');
      assert.match(await page.locator('#ocr-provider-form > .ocr-cloud-warning').innerText(),/选择它才会启用/);
    }
    await page.locator('#cancel-ocr-provider-dialog').click();
    await page.setViewportSize({width:420,height:820});
    await page.locator('#add-provider').click(); await page.locator('#provider-preset').selectOption('microsoft');
    assert.equal(await page.locator('#provider-service-guide .service-quota-badge').isVisible(),true);
    assert.equal(await page.locator('#provider-service-guide').evaluate(element=>element.scrollWidth<=element.clientWidth),true,'Quota conditions and pricing links must wrap at 420px.');
    assert.deepEqual(errors,[]); assert.deepEqual(externalRequests,[]);
    await page.close();
  }
  console.log(JSON.stringify({ok:true,platforms:['macOS','Windows'],translationPresets:13,ocrKinds:7,scope:'production browser settings DOM; read-only local quota data; no account/API calls'}));
} finally { await browser.close(); }
