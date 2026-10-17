'use strict';
const fs=require('fs'),path=require('path'),{spawnSync}=require('child_process');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const out=process.argv[2]||'design_refs/commerce_black_lion_v1/final/preview';
const build=spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',out],{encoding:'utf8'});
if(build.status!==0)throw Error(build.stdout+build.stderr);
// A Chrome-only scrollbar translation; native production uses ScrollThumb CSS.
const html=path.join(out,'index.html');let content=fs.readFileSync(html,'utf8');
content=content.replace('</style>','.BLMarketWindow .panel::-webkit-scrollbar-thumb{background:#948257}.BLMarketWindow .panel::-webkit-scrollbar-track{background:#11150f}</style>');
const stateSource=fs.readFileSync('tools/menus_v10/state.js','utf8').replace("params.get('page')||'archive'","params.get('page')||'commerce'")+"\npreviewReady.then(function(){if(page===\"commerce\"&&!new URLSearchParams(location.search).has(\"category\")){cfg.SurvivalCommerceView.SelectCategory(\"item\");syncLayout();}});";
fs.writeFileSync(path.join(out,'state.js'),stateSource);content=content.replace(/<script src="[^"]*tools\/menus_v10\/state\.js"><\/script>/,'<script src="state.js"></script>');
fs.writeFileSync(html,content);
(async()=>{const b=await browser(),records=[];try{
 for(const [w,h] of [[960,720],[1280,720],[1600,900],[1920,1080],[2560,1440]]){
  await b.call('Emulation.setDeviceMetricsOverride',{width:w,height:h,deviceScaleFactor:1,mobile:false});
  await b.go(html,'?page=commerce');await b.run('previewReady');
  const groups=w===1600?['item','technology','equipment','other']:['item'];
  for(const group of groups){await b.run('cfg.SurvivalCommerceView.SelectCategory('+JSON.stringify(group)+');syncLayout()');
   await b.shot(path.join(out,'..',group+'_'+w+'x'+h+'.png'));
   const result=await b.run('(()=>{const market=cfg.SurvivalBlackLionMarket.GetWindow(),rect=market.panel.el.getBoundingClientRect();return {category:cfg.SurvivalCommerceView.Inspect().category,bounds:rect.toJSON(),tabs:document.querySelectorAll(".BLMarketTab").length,visibleRows:market.content.FindChildrenWithClassTraverse("BLMarketRow").length,errors:previewErrors,missingImages:[...document.querySelectorAll(".BLMarketWindow img")].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src),checkoutCalls:previewCalls.filter(c=>c.method==="paid"||c.method==="wallet")}})()');
   records.push({viewport:[w,h],...result});
   if(result.errors.length||result.missingImages.length||result.tabs!==4||result.bounds.x<-.01||result.bounds.y<-.01||result.bounds.right>w+.01||result.bounds.bottom>h+.01||result.checkoutCalls.length)throw Error('Marketplace visual acceptance failed '+JSON.stringify(records.at(-1)));
  }
  if(w===1600){await b.run('cfg.SurvivalCommerceView.SelectCategory("item");syncLayout();cfg.SurvivalBlackLionMarket.GetWindow().content.FindChildrenWithClassTraverse("BLMarketRow")[1].events.onmouseover();syncLayout()');await b.shot(path.join(out,'..','item_hover_'+w+'x'+h+'.png'));}
 }
 fs.writeFileSync(path.join(out,'..','visual_checks.json'),JSON.stringify({scope:'real production XML/JS/CSS with labeled local catalog snapshots, no native game or account/payments',checks:records},null,2));
 console.log('BLACK_LION_PREVIEW_PASS '+records.length+' category/viewport states; no missing icons, errors, clipping or checkout calls');
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
