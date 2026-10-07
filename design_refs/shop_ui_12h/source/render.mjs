import fs from 'node:fs';import path from 'node:path';import {createRequire} from 'node:module';import {fileURLToPath,pathToFileURL} from 'node:url';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),req=createRequire(import.meta.url),{chromium}=req(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES?path.join(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES,'playwright'):'playwright');
const b=await chromium.launch({headless:true,executablePath:process.env.CJ_CHROMIUM_PATH,args:['--no-sandbox']}),p=await b.newPage({viewport:{width:1920,height:1080}}),errors=[];p.on('pageerror',e=>errors.push(String(e)));p.on('requestfailed',r=>errors.push(r.url()));
const u=pathToFileURL(path.join(base,'source/shop.html')).href;
for(const hover of [1,0]){await p.goto(u+'?clean=1&hover='+hover);await p.evaluate(()=>document.fonts.ready);await p.evaluate(async()=>await Promise.all([...document.images].map(im=>im.decode())));await p.waitForTimeout(230);await p.screenshot({path:path.join(base,'previews/shop_v8_'+(hover?'hover':'normal')+'.png')});}
const geometry=await p.evaluate(()=>window.CJ_GEOMETRY);const fontCheck=await p.evaluate(()=>({sans:document.fonts.check('23px HanSans'),serif:document.fonts.check('48px HanSerif')}));
const checks={};
await p.locator('.card').first().screenshot({path:path.join(base,'previews/product_normal.png')});
await p.locator('.card').first().hover();await p.waitForFunction(()=>Number(getComputedStyle(document.querySelector('.card .hoverbox')).opacity)>=.999,{},{timeout:3000});
await p.locator('.card').first().screenshot({path:path.join(base,'previews/product_hover.png')});
checks.productHover=await p.locator('.card').first().evaluate(el=>({overlayVisible:getComputedStyle(el.querySelector('.hoverbox')).opacity==='1',frame:getComputedStyle(el).backgroundImage.includes('product_hover.png')}));
await p.locator('.card').first().locator('.buy').hover();
checks.buyHover=await p.locator('.card').first().locator('.buy').evaluate(el=>getComputedStyle(el).backgroundImage.includes('buy_button_hover.png'));
await p.locator('.nav:not(.selected)').first().hover();
checks.navHover=await p.locator('.nav:not(.selected)').first().evaluate(el=>getComputedStyle(el).backgroundImage.includes('nav_hover.png'));
checks.selectedBottomAlignment=await p.locator('.nav.selected').evaluate(el=>{const r=el.getBoundingClientRect(),g=el.querySelector('.nav-glow').getBoundingClientRect(),l=el.querySelector('.nav-line').getBoundingClientRect();return Math.abs(r.bottom-l.bottom)<.1;});
checks.glowExtendsOutside=await p.locator('.nav.selected').evaluate(el=>{const r=el.getBoundingClientRect(),g=el.querySelector('.nav-glow').getBoundingClientRect();return g.top<r.top&&g.bottom>r.bottom&&g.left<r.left&&g.right>r.right&&getComputedStyle(el).overflow==='visible';});
checks.itemSquareFree=await p.locator('.item-art').first().evaluate(el=>({aspectRatio:el.clientWidth/el.clientHeight,filter:getComputedStyle(el).filter}));
checks.transitionsNonInteractive=await p.evaluate(()=>[...document.querySelectorAll('.content-transition,.sidebar-seam')].every(el=>getComputedStyle(el).pointerEvents==='none'));
checks.contentFits=await p.evaluate(()=>[...document.querySelectorAll('.item-title,.price,.effect')].every(el=>el.scrollWidth<=el.clientWidth&&el.scrollHeight<=el.clientHeight));
const cases=[];for(const [w,h]of [[1280,720],[2560,1440],[2560,1080]]){await p.setViewportSize({width:w,height:h});await p.goto(u+'?clean=1');cases.push(await p.evaluate(()=>{const r=document.getElementById('window').getBoundingClientRect();return {viewport:[innerWidth,innerHeight],contained:r.left>=0&&r.top>=0&&r.right<=innerWidth&&r.bottom<=innerHeight};}));}
fs.writeFileSync(path.join(base,'layout.json'),JSON.stringify(geometry,null,2));fs.writeFileSync(path.join(base,'preview_qa.json'),JSON.stringify({renderer:'local Chromium component assembly, not in-game validation',errors,fontCheck,interactionChecks:checks,viewportChecks:cases},null,2));await b.close();console.log(JSON.stringify({errors,fontCheck,checks,cases}));
