// Real DOM/pointer capture and production layout module, mocked native IPC.
// Native macOS/Windows frame/stacking acceptance belongs to platform fixtures.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
const origin = process.env.ECHOLINGO_TEST_ORIGIN ?? 'http://127.0.0.1:1420';
const directions = ['west', 'east', 'north', 'south', 'north-west', 'north-east', 'south-west', 'south-east'];
const browser = await chromium.launch({ headless: true, ...(process.env.ECHOLINGO_TEST_CHROMIUM ? { executablePath: process.env.ECHOLINGO_TEST_CHROMIUM } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 820 } });
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.route(`${origin}/__resize_edges`, route => route.fulfill({ contentType: 'text/html', body: `<!doctype html><link rel="stylesheet" href="/src/styles.css"><body data-view="translate">${directions.map(direction => `<div class="popup-resize-edge" data-window-resize="${direction}" aria-hidden="true"></div>`).join('')}<div class="app-shell"><div class="main-shell"><header class="popup-toolbar"><button class="icon-button" id="pin-button">P</button><div class="popup-drag-space" data-window-drag></div><button class="icon-button" id="more-toggle">M</button><button class="icon-button" id="close-popup">X</button></header><header class="management-header"><button class="icon-button" id="back">B</button><span class="management-spacer"></span><button class="icon-button" id="close-management">X</button></header><main><section class="view">Content</section></main></div></div></body>` }));
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'platform', { configurable: true, get: () => window.__resizeQA?.platform ?? 'MacIntel' });
    window.__resizeQA = { platform: 'MacIntel', presentation: { epoch: 1, presented: true }, requests: [], commands: [], hold: false,
      frames: async () => { for (let n = 0; n < 4; n++) await new Promise(requestAnimationFrame); } };
    window.__TAURI_INTERNALS__ = { invoke: async (command, args) => {
      const q = window.__resizeQA; q.commands.push(command);
      if (['resize_popup_width', 'resize_management_window', 'start_window_resize'].includes(command)) {
        q.requests.push({ command, ...structuredClone(args) });
        if (q.hold) await new Promise(resolve => { q.release = resolve; });
      } else if (command !== 'fit_window') throw new Error(`Unexpected command ${command}`);
    }};
  });
  await page.goto(`${origin}/__resize_edges`);
  await page.evaluate(async () => { const { installPanelLayout } = await import('/src/panel-layout.ts'); window.__resizeQA.layout = installPanelLayout(true, () => window.__resizeQA.presentation); await window.__resizeQA.frames(); });
  const edge = direction => page.locator(`[data-window-resize="${direction}"]`);
  for (const direction of directions) assert.equal(await edge(direction).isVisible(), direction === 'west' || direction === 'east');
  for (const direction of ['west', 'east']) {
    const box = await edge(direction).boundingBox(); assert.equal(box.width, 10); assert.equal(box.y, 36);
  }
  for (const selector of ['#pin-button', '#more-toggle', '#close-popup']) assert.equal(await page.locator(selector).evaluate(element => { const r=element.getBoundingClientRect(); return document.elementFromPoint(r.x+r.width/2,r.y+r.height/2) === element; }), true, `${selector} must retain its click target`);
  const drag = async (direction, dx, dy) => {
    const box = await edge(direction).boundingBox(); const x=box.x+box.width/2, y=box.y+box.height/2;
    const before = await page.evaluate(() => window.__resizeQA.requests.length);
    await page.mouse.move(x,y); await page.mouse.down(); await page.mouse.move(x+dx,y+dy,{steps:4}); await page.mouse.up();
    await page.evaluate(() => window.__resizeQA.frames());
    assert.ok(await page.evaluate(before => window.__resizeQA.requests.length > before,before));
    return page.evaluate(() => window.__resizeQA.requests.at(-1));
  };
  assert.deepEqual(await drag('east',-50,30), { command:'resize_popup_width', width:750, direction:'east', presentationEpoch:1 });
  await page.evaluate(() => { document.body.dataset.view='settings'; window.__resizeQA.presentation.epoch=2; });
  for (const selector of ['#back','#close-management']) assert.equal(await page.locator(selector).evaluate(element => { const r=element.getBoundingClientRect(); return document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)===element; }),true);
  for (const direction of directions) {
    assert.equal(await edge(direction).isVisible(),true);
    const horizontal=direction.includes('west')?-1:direction.includes('east')?1:0;
    const vertical=direction.includes('north')?-1:direction.includes('south')?1:0;
    const request=await drag(direction,20,15);
    assert.deepEqual(request,{command:'resize_management_window',width:800+20*horizontal,height:820+15*vertical,direction,presentationEpoch:2});
  }
  // A superseded epoch or view, blur, lost capture, hidden presentation and
  // mismatching pointer must not replay a pending edge gesture.
  for (const cancellation of ['epoch','view','blur','hidden','cancel']) {
    await page.evaluate(() => { document.body.dataset.view='settings'; window.__resizeQA.presentation={epoch:10,presented:true}; });
    const box=await edge('south-east').boundingBox(); await page.mouse.move(box.x+5,box.y+5); await page.mouse.down();
    const before=await page.evaluate(() => window.__resizeQA.requests.length);
    await page.evaluate(reason => { const q=window.__resizeQA;
      if(reason==='epoch')q.presentation.epoch++;
      if(reason==='view')document.body.dataset.view='translate';
      if(reason==='hidden')q.presentation.presented=false;
      if(reason==='blur')window.dispatchEvent(new Event('blur'));
      if(reason==='cancel')document.dispatchEvent(new PointerEvent('pointercancel',{pointerId:1}));
      window.dispatchEvent(new Event('echolingo:layout'));
    },cancellation);
    await page.mouse.move(box.x-10,box.y-10); await page.mouse.up(); await page.evaluate(() => window.__resizeQA.frames());
    assert.equal(await page.evaluate(() => window.__resizeQA.requests.length),before,cancellation);
    assert.equal(await page.locator('body').evaluate(element=>element.classList.contains('popup-resizing')),false);
  }
  await page.evaluate(() => { document.body.dataset.view='settings'; window.__resizeQA.presentation={epoch:15,presented:true}; });
  const pointerBox=await edge('east').boundingBox(); await page.mouse.move(pointerBox.x+5,pointerBox.y+20); await page.mouse.down();
  const pointerBefore=await page.evaluate(() => window.__resizeQA.requests.length);
  await page.evaluate(() => { document.dispatchEvent(new PointerEvent('pointermove',{pointerId:77,buttons:1,screenX:5,screenY:5})); document.dispatchEvent(new PointerEvent('pointerup',{pointerId:77})); });
  assert.equal(await page.evaluate(() => window.__resizeQA.requests.length),pointerBefore);
  assert.equal(await page.locator('body').evaluate(element=>element.classList.contains('popup-resizing')),true);
  await page.mouse.up(); await page.evaluate(() => window.__resizeQA.frames());
  // A pending request cannot carry a second coalesced movement into a newer
  // presentation after the first asynchronous IPC resolves.
  const heldBox=await edge('east').boundingBox(); await page.mouse.move(heldBox.x+5,heldBox.y+20); await page.mouse.down();
  const heldBefore=await page.evaluate(() => { window.__resizeQA.hold=true; return window.__resizeQA.requests.length; });
  await page.mouse.move(heldBox.x-15,heldBox.y+20);
  await page.waitForFunction(before => window.__resizeQA.requests.length>before,heldBefore);
  await page.mouse.move(heldBox.x-25,heldBox.y+20);
  await page.evaluate(() => { const q=window.__resizeQA; q.presentation.epoch++; window.dispatchEvent(new Event('echolingo:layout')); q.hold=false; q.release(); });
  await page.mouse.up(); await page.evaluate(() => window.__resizeQA.frames());
  assert.equal(await page.evaluate(() => window.__resizeQA.requests.length),heldBefore+1);
  await page.evaluate(() => { document.body.dataset.view='settings'; window.__resizeQA.presentation={epoch:20,presented:true}; window.__resizeQA.platform='Win32'; });
  assert.deepEqual(await drag('south-east',-30,-20),{command:'start_window_resize',direction:'south-east',presentationEpoch:20,management:true});
  await page.evaluate(() => { document.body.dataset.view='translate'; document.body.classList.add('modal-open'); });
  assert.equal(await edge('east').isVisible(),false);
  assert.equal(await edge('south-east').isVisible(),false);
  await page.evaluate(() => window.__resizeQA.layout.dispose());
  assert.equal(await page.locator('body').evaluate(element=>element.classList.contains('popup-resize-enabled')),false);
  assert.equal(await page.evaluate(()=>window.__resizeQA.commands.some(command=>/show|focus|hide|drag$/.test(command))),false);
  assert.deepEqual(errors,[]);
  // Mount the layout module over the actual application DOM in browser-preview
  // mode, then open the real Add API form. IPC stays mocked; pointer capture,
  // form controls, overlay, scrollbars and hit testing use production markup.
  await page.goto(origin);
  await page.locator('#more-toggle').click(); await page.locator('#popup-more-menu button[data-view="settings"]').click();
  await page.evaluate(async () => { const {installPanelLayout}=await import('/src/panel-layout.ts'); window.__resizeQA.presentation={epoch:30,presented:true}; window.__resizeQA.layout=installPanelLayout(true,()=>window.__resizeQA.presentation); });
  await page.locator('#add-provider').click();
  assert.equal(await page.locator('body').evaluate(element=>element.classList.contains('modal-open')),true);
  const modalControlHit = async selector => {
    await page.locator(selector).scrollIntoViewIfNeeded();
    assert.equal(await page.locator(selector).evaluate(element=> { const r=element.getBoundingClientRect(); return element.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)); }),true,`${selector} must not be covered by edge handles`);
  };
  await modalControlHit('#close-provider-dialog'); await modalControlHit('#provider-name');
  for(const direction of directions) {
    assert.equal(await edge(direction).isVisible(),true);
    const horizontal=direction.includes('west')?-1:direction.includes('east')?1:0;
    const vertical=direction.includes('north')?-1:direction.includes('south')?1:0;
    assert.deepEqual(await drag(direction,12,9),{command:'resize_management_window',width:800+12*horizontal,height:820+9*vertical,direction,presentationEpoch:30});
  }
  const scrollbarHit=await page.locator('#provider-dialog').evaluate(element=> {
    const width=element.offsetWidth-element.clientWidth;
    if(!width)return true;
    return !document.elementFromPoint(innerWidth-width/2,innerHeight/2)?.closest('[data-window-resize]');
  }); assert.equal(scrollbarHit,true,'Native modal scrollbar track must remain outside the edge handles.');
  // Closing or opening the real form changes gesture intent even when the
  // native window presentation epoch stays the same.
  for(const initiallyOpen of [true,false]) {
    if(!initiallyOpen)await page.locator('#cancel-provider-dialog').click();
    const box=await edge('east').boundingBox(); await page.mouse.move(box.x+5,box.y+30); await page.mouse.down();
    const before=await page.evaluate(()=>window.__resizeQA.requests.length);
    await page.evaluate(open=>document.querySelector(open?'#cancel-provider-dialog':'#add-provider').click(),initiallyOpen);
    await page.mouse.move(box.x-20,box.y+30); await page.mouse.up(); await page.evaluate(()=>window.__resizeQA.frames());
    assert.equal(await page.evaluate(()=>window.__resizeQA.requests.length),before,'Modal state changes must invalidate the previous edge gesture.');
    if(initiallyOpen)await page.locator('#add-provider').click();
  }
  await page.evaluate(()=>window.__resizeQA.layout.dispose());
  assert.deepEqual(errors,[]);
  console.log(JSON.stringify({ok:true,scope:'real browser pointer capture + production CSS/layout; mocked native IPC only',managementDirections:8,managementModalDirections:8,popupEdgeLogicalPixels:10,physicalPlatformAcceptance:false}));
} finally { await browser.close(); }
