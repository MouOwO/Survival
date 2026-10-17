"use strict";
const fs=require('node:fs'),path=require('node:path'),{browser}=require('../shop_ui_12h/cdp.cjs');
const out='design_refs/shop_catalog_20261016/ui';
(async()=>{const b=await browser(),records=[];try{
 await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:900,deviceScaleFactor:1,mobile:false});
 for(const sku of ['video_p140','video_p151']){
  await b.go(path.join(out,'preview/index.html'),'?page=commerce&state=vip0&category=all');if(!await b.run('marketReady'))throw Error('Production preview failed');
  const record=await b.run(`(()=>{const sku=${JSON.stringify(sku)},view=cfg.SurvivalCommerceView,market=cfg.SurvivalBlackLionMarket.GetWindow(),index=view.Inspect().visibleSkus.indexOf(sku);if(index<0)throw Error('New formal SKU not visible: '+sku);const page=Math.floor(index/40);
   for(let step=0;step<page;step++){const next=market.actions.FindChildrenWithClassTraverse('CJPageAction')[1];if(!next||!next.enabled)throw Error('Page inaccessible');next.events.onactivate();}
   syncLayout();const row=market.content.FindChildrenWithClassTraverse('BLMarketRow')[index%40];if(!row)throw Error('Expected rendered row not found');
   market.content.el.scrollTop=row.el.offsetTop;syncLayout();const icon=row.__menuCell.iconPanel.el.querySelector('img');return {sku,index,page,name:row.__menuCell.namePanel.text,image:icon&&icon.src,missingImage:!icon||!icon.complete||!icon.naturalWidth,checkoutCalls:previewCalls.filter(c=>c.method==='paid'||c.method==='wallet')};})()`);
  await b.run('Promise.all([...document.querySelectorAll(".BLMarketWindow img")].map(i=>i.decode().catch(()=>false))).then(()=>{syncLayout();return true;})');
  record.missingImage=await b.run(`(()=>{const row=cfg.SurvivalBlackLionMarket.GetWindow().content.FindChildrenWithClassTraverse('BLMarketRow')[${record.index%40}],icon=row&&row.__menuCell.iconPanel.el.querySelector('img');return !icon||!icon.complete||!icon.naturalWidth;})()`);
  await b.run('new Promise(resolve=>setTimeout(resolve,80))');
  if(record.missingImage||record.checkoutCalls.length)throw Error('New item image / no-checkout validation failed');
  await b.shot(path.join(out,sku+'_1600x900.png'),{x:0,y:0,width:1600,height:900});records.push(record);
 }
 fs.writeFileSync(path.join(out,'new_item_visual_checks.json'),JSON.stringify({scope:'Actual production list pages; final formal catalog, offline profile, no account/order/payment requests.',checks:records},null,2));
 console.log('NEW_ITEM_VISUAL_PASS '+records.length+' formally configured icons and list rows');
}finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
