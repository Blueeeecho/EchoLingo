// Production-DOM category and deep-link checks; no native permissions/services.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const browser = await chromium.launch({headless:true,...(process.env.ECHOLINGO_TEST_CHROMIUM ? {executablePath:process.env.ECHOLINGO_TEST_CHROMIUM}:{})});
try {
 const page = await browser.newPage({viewport:{width:900,height:720}});
 const errors=[]; page.on('pageerror', e=>errors.push(e.message));
 await page.goto(origin); await page.locator('#more-toggle').click(); await page.locator('#popup-more-menu [data-view="settings"]').click();
 assert.equal(await page.locator('#theme-select').isVisible(),true);
 assert.equal(await page.locator('#update-settings').isVisible(),false);
 assert.equal(await page.getByRole('heading',{level:1,name:'常规'}).count(),1);
 assert.equal(await page.locator('#general-settings #theme-select').isVisible(),true);
 assert.equal(await page.locator('#history-settings #save-history').isVisible(),true);
 // The persistent header shortcut jump must reveal its now-categorized target.
 await page.locator('#open-shortcut-settings').click();
 assert.equal(await page.locator('#shortcut-selection').isVisible(),true);
 assert.equal(await page.locator('#shortcut-selection').evaluate(el=>document.activeElement===el),true);
 await page.locator('[data-settings-tab="general"]').click();
 const categories=['general','translation','capture','shortcuts','permissions','about'];
 for(const width of [420,680,900,1200]) {
  await page.setViewportSize({width,height:720});
  await page.waitForFunction(orientation=>document.querySelector('.settings-navigation').getAttribute('aria-orientation')===orientation,width<=680?'horizontal':'vertical');
  for(const category of categories) {
   await page.locator(`[data-settings-tab="${category}"]`).click();
   assert.equal(await page.locator('[data-settings-panel]:visible').count(),1);
   const panel=page.locator(`[data-settings-panel="${category}"]`);
   assert.equal(await panel.isVisible(),true);
   assert.equal(await panel.getByRole('heading',{level:1}).textContent(),await page.locator(`[data-settings-tab="${category}"]`).textContent());
   assert.equal(await page.locator('[data-settings-tab][aria-selected="true"][tabindex="0"]').count(),1);
   const overflow=await page.locator('#view-settings').evaluate(e=>[e,...e.querySelectorAll('*')].filter(n=>{const r=n.getBoundingClientRect();return r.width>0&&r.height>0&&(r.left < -1||r.right>innerWidth+1)}).map(n=>n.id||n.className));
   assert.deepEqual(overflow,[],`overflow ${width}/${category}`);
  }
 }
 const tab=name=>page.locator(`[data-settings-tab="${name}"]`);
 await tab('general').click(); await page.keyboard.press('ArrowRight');
 assert.equal(await tab('general').getAttribute('aria-selected'),'true');
 await page.keyboard.press('ArrowDown');
 assert.equal(await tab('translation').getAttribute('aria-selected'),'true');
 await page.setViewportSize({width:420,height:720});
 await page.waitForFunction(()=>document.querySelector('.settings-navigation').getAttribute('aria-orientation')==='horizontal');
 await page.keyboard.press('ArrowDown');
 assert.equal(await tab('translation').getAttribute('aria-selected'),'true');
 await page.keyboard.press('ArrowRight');
 assert.equal(await tab('capture').getAttribute('aria-selected'),'true');
 assert.equal(await tab('capture').evaluate(el=>document.activeElement===el),true);
 await page.keyboard.press('End');
 assert.equal(await page.locator('[data-settings-tab="about"]').getAttribute('aria-selected'),'true');
 await page.keyboard.press('Home'); assert.equal(await page.locator('[data-settings-tab="general"]').getAttribute('aria-selected'),'true');
 // Service manager language-pack deep link must reveal the destination.
 await tab('translation').click();
 assert.equal(await page.locator('#translation-settings .settings-heading-actions #open-service-manager').isVisible(),true);
 await page.locator('#open-service-manager').click();
 await page.locator('#service-manager-advanced').click(); assert.equal(await page.locator('#system-translation-setup').isVisible(),true);
 // Recommendations deep link chooses the same category, even after another tab.
 await page.locator('#open-service-manager').click(); await page.locator('#managed-service-recommend').click();
 assert.equal(await page.locator('#free-translation-summary').isVisible(),true);
 // Returning preserves the selected category and does not reset to Update.
 await page.locator('[data-settings-tab="shortcuts"]').click();
 await page.locator('.management-header [data-view="translate"]').click();
 assert.equal(await page.locator('#open-shortcut-settings').isHidden(),true);
 await page.locator('#more-toggle').click(); await page.locator('#popup-more-menu [data-view="settings"]').click();
 assert.equal(await page.locator('#shortcuts-form').isVisible(),true);
 // Popup service management must not land on the last visited unrelated tab.
 await page.locator('[data-settings-tab="general"]').click();
 await page.locator('.management-header [data-view="translate"]').click();
 await page.locator('#popup-services summary').click();
 await page.locator('#popup-services-list button').click();
 assert.equal(await page.locator('#translation-settings').isVisible(),true);
 assert.deepEqual(errors,[]); console.log('PASS settings categories, narrow layout, keyboard navigation, deep links and return state (browser only).');
} finally {await browser.close();}
