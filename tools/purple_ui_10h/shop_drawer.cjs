'use strict';
// The shop-only drawer contract. No native commands or real transactions.
const fs=require('fs'),path=require('path'),assert=require('assert'),crypto=require('crypto');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const args=process.argv.slice(2),arg=(key,fallback)=>{const i=args.indexOf(key);return i<0?fallback:args[i+1];};
const base='design_refs/purple_ui_10h/work/shop_reference_drawer';
const input=arg('--input','design_refs/purple_ui_10h/work/preview/index.html');
const candidate=arg('--candidate','current standalone shop browser candidate');
const out=arg('--out',base+'/current'),baseline=args.includes('--baseline');
const sizes=arg('--sizes','1280x720,1920x1080,2560x1440,2560x1080').split(',').map(x=>x.split('x').map(Number));
const categories=arg('--categories','equipment,challenge,other').split(',');
const assembly=JSON.parse(fs.readFileSync(path.join(path.dirname(input),'assembly.json'),'utf8'));
const digest=crypto.createHash('sha256').update(JSON.stringify(assembly.sourceGraph)).digest('hex');
let written=false;
process.on('beforeExit',()=>{if(!written){console.error('SHOP_DRAWER_INCOMPLETE: no new report');process.exitCode=1;}});
function inspect(){
 const shown=e=>!!(e&&!e.hidden&&e.getBoundingClientRect().width&&getComputedStyle(e).display!=='none'&&Number(getComputedStyle(e).opacity)>0);
 const describe=e=>{if(!e)return null;const c=getComputedStyle(e);return {id:e.id,classes:e.className,text:e.textContent,bounds:e.getBoundingClientRect().toJSON(),visible:shown(e),opacity:c.opacity,transform:c.transform,translate:c.translate,transition:c.transition,background:c.backgroundColor,backgroundImage:c.backgroundImage,pointerEvents:c.pointerEvents,inline:e.style.cssText};};
 const win=nodes.CustomShopWindow.el,tip=nodes.ShopEntryTooltip.el;
 const cardPanels=nodes.CustomShopWindow.FindChildrenWithClassTraverse('ShopShelfSlot');
 const cards=[...win.querySelectorAll('.ShopShelfSlot')].map(e=>{const panel=cardPanels.find(p=>p.el===e),stock=panel&&panel.__survivalStockLabel;return {bounds:e.getBoundingClientRect().toJSON(),name:describe(e.querySelector('.ShopCardName')),icon:describe(e.querySelector('.ShopItemIcon')),stock:stock?{...describe(stock.el),explicitVisible:stock.visible}:null,decoded:[...e.querySelectorAll('img')].every(i=>i.complete&&i.naturalWidth>0),labels:[...e.querySelectorAll('.label')].filter(shown).map(describe)};});
 const arrow=tip.querySelector('#ShopTooltipArrow,#ShopTooltipPointer,[class*="TooltipArrow"],[class*="TooltipPointer"]');
 return {state:previewState,errors:previewErrors,calls:previewCalls,models:previewGeometryModels,window:describe(win),header:describe(nodes.ShopHeader&&nodes.ShopHeader.el),titleDivider:describe(nodes.ShopTitleDivider&&nodes.ShopTitleDivider.el),title:describe(nodes.ShopTitle&&nodes.ShopTitle.el),close:describe(nodes.ShopCloseButton&&nodes.ShopCloseButton.el),tabs:[...win.querySelectorAll('.ShopModeToggle')].map(describe),cards,purpleNav:[...win.querySelectorAll('.PurpleNav,.PurpleBalance')].filter(shown).map(describe),tooltip:describe(tip),tooltipFrame:describe(nodes.ShopTooltipFrame&&nodes.ShopTooltipFrame.el),arrow:describe(arrow),tooltipCorners:[...tip.querySelectorAll('.ShopFrameCorner')].map(describe),fields:['ShopTooltipIconHost','ShopTooltipTitle','ShopTooltipType','ShopTooltipCostRow','ShopTooltipDescription','ShopTooltipPurchase'].map(id=>describe(nodes[id]&&nodes[id].el)),effectHeading:[...tip.querySelectorAll('.label')].filter(e=>shown(e)&&e.textContent.trim()==='效果').map(describe)};
}
async function evaluate(b){await b.run('syncLayout();true');return b.run('('+inspect.toString()+')()');}
const forbidden=calls=>calls.filter(x=>/purchase|checkout|draw|claim|promote/.test(x.name||x.method||''));
const inside=(r,outer,t=1)=>r.x>=outer.x-t&&r.y>=outer.y-t&&r.right<=outer.right+t&&r.bottom<=outer.bottom+t;
async function frame(b,prefix,width,height,label){const info=await evaluate(b);await b.shot(prefix+'_'+label+'.png',{x:0,y:0,width,height});fs.writeFileSync(prefix+'_'+label+'_metrics.json',JSON.stringify(info,null,2));return info;}
async function animate(b,prefix,width,height){
 const closed=await b.run(`(async()=>{cfg.SurvivalShop.Close();syncLayout();const e=nodes.CustomShopWindow.el,card=e.querySelector('.ShopShelfSlot'),r=card&&card.getBoundingClientRect(),hit=r&&document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);window.previewClosedHitLeak=!!(hit&&(hit.closest('.ShopShelfSlot')||hit.closest('#ShopTooltipPurchase')));await Promise.all(e.getAnimations().map(a=>a.finished.catch(()=>null)));await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));return {classes:e.className,display:getComputedStyle(e).display,opacity:getComputedStyle(e).opacity,bounds:e.getBoundingClientRect().toJSON(),closedHitLeak:window.previewClosedHitLeak};})()`);
 assert.equal(closed.closedHitLeak,false,'Closing drawer still exposes descendant pointer targets');
 const sampled=await b.run(`(async()=>{const e=nodes.CustomShopWindow.el;cfg.SurvivalShop.Open();syncLayout();const started=performance.now();for(let n=0;n<80;n++){await new Promise(requestAnimationFrame);const animations=e.getAnimations().filter(a=>a.effect&&a.effect.target===e&&['left','top','transform','opacity'].includes(a.transitionProperty)),rows=animations.map(a=>({a,t:a.effect.getComputedTiming()})),eligible=rows.some(x=>x.t.progress>0.1&&x.t.progress<0.8);if(eligible){for(const {a}of rows)a.pause();await Promise.all(rows.map(x=>x.a.ready));window.previewDrawerAnimations=rows.map(x=>x.a);return {observedElapsed:performance.now()-started,rect:e.getBoundingClientRect().toJSON(),transform:getComputedStyle(e).transform,opacity:getComputedStyle(e).opacity,animations:rows.map(({a})=>({property:a.transitionProperty,currentTime:a.currentTime,duration:a.effect.getTiming().duration,progress:a.effect.getComputedTiming().progress,keyframes:a.effect.getKeyframes()}))};}}throw Error('No actual partial transform/opacity CSSTransition observed; do not substitute a timeout or injected transform');})()`);
 const partial=await frame(b,prefix,width,height,'slide_partial');
 await b.run(`(async()=>{const list=window.previewDrawerAnimations||[];for(const a of list)a.play();await Promise.all(list.map(a=>a.finished));await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));syncLayout();return true;})()`);
 const settled=await frame(b,prefix,width,height,'slide_settled');
 assert(settled.window.visible,'Settled drawer invisible');
 assert(sampled.animations.some(a=>['left','transform'].includes(a.property)),'Drawer lacks a real translation transition');
 assert(partial.window.bounds.x<settled.window.bounds.x-1,'Drawer did not move in from left');
 assert(partial.window.bounds.right>0,'Partial drawer is not visible on screen');
 assert.equal(forbidden(settled.calls).length,0,'Drawer animation requested a transaction');
 return {kind:'actual browser production CSS transition observed then paused without changing layout values',closed,sampled,partial,settled};
}
(async()=>{
 const b=await browser(),cases=[];
 try{
  fs.mkdirSync(out,{recursive:true});
  for(const [width,height]of sizes)for(const category of categories){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(input,'?page=shop&state=normal&category='+category+'&scope=projected&rebirth=0');
   assert.equal(await b.run('previewReady'),true);
   const prefix=out+'/'+width+'x'+height+'_shop_'+category;
   const normal=await frame(b,prefix,width,height,'normal');
   assert.equal(normal.errors.length,0);assert.equal(normal.cards.length,{equipment:4,other:6,challenge:12}[category]);
   assert(normal.cards.every(x=>x.decoded),'Visible native item icon failed to decode');
   let animation=null,pointer=null;
   if(!baseline){
    assert(normal.window.visible&&inside(normal.window.bounds,{x:0,y:0,right:width,bottom:height}),'Drawer exceeds viewport');
    assert(normal.title.visible&&normal.close.visible,'Reference title/close missing');
    assert.equal(normal.title.text,'生存商店','Reference title stays生存商店 across all three ordinary categories; research is separate');
    assert.equal(normal.tabs.filter(x=>x.visible).length,3,'Reference has exactly three visible tabs');
    const tabs=normal.tabs.filter(x=>x.visible);assert(tabs.every(x=>Math.abs(x.bounds.width-tabs[0].bounds.width)<1&&Math.abs(x.bounds.height-tabs[0].bounds.height)<1),'Reference tabs must have equal width and height in each category');
    assert(normal.header&&tabs.every(x=>inside(x.bounds,normal.header.bounds)),'Actual native ShopHeader must contain all tabs; browser noclip alone does not prove native children draw');
    assert(normal.cards.every(c=>!c.stock||c.stock.explicitVisible===false),'Authoritative card update must keep ordinary stock labels explicitly invisible');
    assert(normal.titleDivider&&normal.titleDivider.visible,'Standalone reference title divider missing');
    assert.equal(normal.purpleNav.length,0,'Rejected shared navigation or wallet remains in independent shop');
    assert(normal.cards.every(x=>!x.name||!x.name.visible),'Grid must contain icons only');
    assert(normal.cards.every(x=>inside(x.bounds,normal.window.bounds)),'Reference grid card exceeds drawer');
    const columns=[...new Set(normal.cards.map(x=>Math.round(x.bounds.x)))];assert.equal(columns.length,4,'Reference grid has four columns');
    animation=await animate(b,prefix,width,height);
   }
   const source=normal.cards[Math.min(3,normal.cards.length-1)].bounds;
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:source.x+source.width/2,y:source.y+source.height/2});
   await b.run('new Promise(r=>setTimeout(r,90)).then(()=>true)');
   const hover=await frame(b,prefix,width,height,'hover');
   assert(hover.tooltip.visible,'Actual physical hover did not reveal detail');
   if(!baseline){
    const body=hover.tooltipFrame||hover.tooltip,scale=hover.window.bounds.width/680;
    assert(Math.abs(body.bounds.width/scale-348)<1,'Reference colored tooltip body must remain348; transparent outer frame must not substitute for it');
    assert(Math.abs((body.bounds.x-hover.window.bounds.right)/scale-22)<1,'Reference colored tooltip body must have22 gap from drawer');
    assert(hover.tooltip.bounds.x>=hover.window.bounds.right-1,'Reference tooltip must be on right of drawer');
    assert(inside(hover.tooltip.bounds,{x:0,y:0,right:width,bottom:height}),'Right tooltip exceeds viewport');
    assert(hover.arrow&&hover.arrow.visible,'Reference pointed tooltip lacks a visible arrow');
    assert(hover.arrow.bounds.x<body.bounds.x&&hover.arrow.bounds.right>=body.bounds.x-3*scale,'Reference arrow must protrude left of colored body and touch its edge');
    const field=id=>hover.fields.find(x=>x&&x.id===id),icon=field('ShopTooltipIconHost'),title=field('ShopTooltipTitle'),type=field('ShopTooltipType'),cost=field('ShopTooltipCostRow'),effect=field('ShopTooltipDescription'),buy=field('ShopTooltipPurchase');
    assert([icon,title,type,cost,effect,buy].every(x=>x&&x.visible),'Reference tooltip field missing');
    assert(title.bounds.x>=icon.bounds.right-1&&type.bounds.x>=icon.bounds.right-1,'Name/type belong to right of header icon');
    assert(cost.bounds.y<effect.bounds.y,'Reference price must precede effect');
    assert(hover.effectHeading.length===1,'Reference effect heading missing');
    assert(inside(buy.bounds,body.bounds),'Purchase action exceeds colored detail body');
    const colors=[...(buy.backgroundImage+' '+buy.background).matchAll(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/g)];assert(colors.some(m=>+m[1]>+m[2]&&+m[1]>+m[3]),'Reference purchase action must remain red');
    const gap={x:(source.right+hover.tooltip.bounds.x)/2,y:source.y+source.height/2},entry={x:hover.tooltip.bounds.x+4,y:Math.max(hover.tooltip.bounds.y+4,Math.min(gap.y,hover.tooltip.bounds.bottom-4))};
    const started=await b.run('performance.now()');
    await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...gap});
    await b.run('new Promise(r=>setTimeout(r,70)).then(()=>true)');
    assert((await evaluate(b)).tooltip.visible,'Tooltip vanished while crossing the actual frame-to-detail gap');
    await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...entry});
    const enteredAfter=await b.run('performance.now()')-started;
    await b.run('new Promise(r=>setTimeout(r,230)).then(()=>true)');
    assert((await evaluate(b)).tooltip.visible,'Tooltip did not remain visible after entering it and passing the hide delay');
    const point={x:buy.bounds.x+buy.bounds.width/2,y:buy.bounds.y+buy.bounds.height/2};
    await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:point.x,y:point.y});
    await b.run('new Promise(r=>setTimeout(r,220)).then(()=>true)');
    assert(await b.run(`!!document.elementFromPoint(${point.x},${point.y}).closest('#ShopTooltipPurchase')`),'Reference purchase button cannot be physically hit');
    pointer={method:'physical CDP mouseMoved; no activation or DOM event dispatch',source:{x:source.x+source.width/2,y:source.y+source.height/2},gap,entry,buy:point,gapWaitMs:70,enteredAfterMs:enteredAfter,tooltipWaitMs:230,buyWaitMs:220,buttonHit:true};
   }
   assert.equal(forbidden(hover.calls).length,0,'Visual reference fixture requested a transaction');
   cases.push({width,height,category,normal,hover,animation,pointer});
   console.log('SHOP_DRAWER_CAPTURE '+width+'x'+height+' '+category+(baseline?' rejected_previous':' current'));
  }
  const result={at:new Date().toISOString(),candidate,status:baseline?'CAPTURE_REJECTED_PREVIOUS_VERSION':'PASS_BROWSER_SHOP_REFERENCE_DRAWER',kind:'production_component_browser_preview',sourceDigest:digest,sourceAssemblyAt:assembly.at,cases,limitations:['Conversation reference coordinates are approximate manual observations, not native image measurements','Local CSV state projects11 challenge+next rebirth at explicit level0; no native account state','Partial screenshot pauses an observed production CSS transition, not a manufactured layout','No game, server purchase, claim, payment or native acceptance']};
  fs.writeFileSync(out+'/report.json',JSON.stringify(result,null,2));written=true;
  console.log('SHOP_DRAWER_REPORT '+out+'/report.json cases='+cases.length);
 }finally{b.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
