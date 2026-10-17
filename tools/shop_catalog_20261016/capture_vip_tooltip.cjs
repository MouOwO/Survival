"use strict";
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'design_refs/shop_catalog_20261016/ui/vip_tooltip_fix'),base=path.join(repo,'design_refs/shop_catalog_20261016/ui/preview');
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const build=spawnSync(process.execPath,['tools/shop_catalog_20261016/preview.cjs'],{encoding:'utf8',windowsHide:true});if(build.status!==0)throw Error(build.stdout+build.stderr);
fs.cpSync(base,path.join(out,'preview'),{recursive:true});
const production=['panorama/src/scripts/custom_game/common/commerce_components.js','panorama/src/styles/custom_game/black_lion_market.css'];
const hashes=production.map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}));
const scenarios=[[1600,900],[960,720]].flatMap(([w,h])=>[['video_bundle_vip_02','vip'],['video_bundle_vip_10','vip'],['video_bundle_b001','bundles']].map(([sku,category])=>({w,h,sku,category})));
(async()=>{const b=await browser(),records=[];try{
 for(const{w,h,sku,category}of scenarios){
  await b.call('Emulation.setDeviceMetricsOverride',{width:w,height:h,deviceScaleFactor:1,mobile:false});
  await b.go(path.join(out,'preview/index.html'),'?page=commerce&state=vip12&category='+category);if(!await b.run('marketReady'))throw Error('Production assembly failed');
  await b.run(`(()=>{const sku=${JSON.stringify(sku)},view=cfg.SurvivalCommerceView,market=cfg.SurvivalBlackLionMarket.GetWindow(),index=view.Inspect().visibleSkus.indexOf(sku);if(index<0)throw Error('Formal SKU is not visible');for(let step=0;step<Math.floor(index/40);step++){const next=market.actions.FindChildrenWithClassTraverse('CJPageAction')[1];next.events.onactivate();}syncLayout();window.tooltipTarget=market.content.FindChildrenWithClassTraverse('BLMarketRow')[index%40];market.content.el.scrollTop=tooltipTarget.el.offsetTop;window.tooltipSourceBefore=JSON.stringify(MARKET_CATALOG_SOURCE);syncLayout();tooltipTarget.events.onmouseover();syncLayout();})()`);
  await b.run('new Promise(resolve=>setTimeout(()=>{syncLayout();resolve(true);},150))');
  const result=await b.run(`(()=>{const sku=${JSON.stringify(sku)},row=tooltipTarget,tip=row.__purpleDetail,effect=tip.FindChildrenWithClassTraverse('RCProductEffect')[0],body=tip.FindChildrenWithClassTraverse('MenuV10CommerceDetailBody')[0],market=cfg.SurvivalBlackLionMarket.GetWindow(),windowBounds=market.panel.el.getBoundingClientRect(),tipBounds=tip.el.getBoundingClientRect(),effectBounds=effect.el.getBoundingClientRect(),bodyBounds=body.el.getBoundingClientRect();
   const source=MARKET_CATALOG_SOURCE.paid.products.find(p=>p.sku===sku),rewards=(source.grants||{}).lines||[],normalize=value=>String(value||'').replace(/\\r\\n?/g,'\\n').replace(/[；;][ \\t]*/g,'\\n');
   const descriptions=rewards.filter(r=>r.description).map(r=>normalize(r.description));
   const effectText=effect.text,rewardChecks=descriptions.map(description=>({description,allLinesPresent:description.split('\\n').every(line=>effectText.split('\\n').includes(line)),contiguousDescription:effectText.includes(description)}));
   const range=document.createRange();range.selectNodeContents(effect.el);const lineRects=[...range.getClientRects()].filter(r=>r.width>.1&&r.height>.1).map(r=>r.toJSON());
   return {sku,title:row.__menuCell.namePanel.text,effectText,rewardChecks,visible:tip.BHasClass('Visible'),effectClientHeight:effect.el.clientHeight,effectScrollHeight:effect.el.scrollHeight,bodyClientHeight:body.el.clientHeight,bodyScrollHeight:body.el.scrollHeight,
    tooltipBounds:tipBounds.toJSON(),windowBounds:windowBounds.toJSON(),effectBounds:effectBounds.toJSON(),bodyBounds:bodyBounds.toJSON(),textLineRects:lineRects,errors:previewErrors,sourceUnchanged:tooltipSourceBefore===JSON.stringify(MARKET_CATALOG_SOURCE),checkoutCalls:previewCalls.filter(c=>c.method==='paid'||c.method==='wallet')};})()`);
  const failures=[];
  if(result.errors.length)failures.push('script errors');if(!result.visible)failures.push('tooltip not visible');
  if(result.rewardChecks.some(r=>!r.allLinesPresent||!r.contiguousDescription))failures.push('formal reward description changed or missing');
  if(result.effectScrollHeight>result.effectClientHeight+1)failures.push('inner effect text clipped');if(result.bodyScrollHeight>result.bodyClientHeight+1)failures.push('tooltip body clipped');
  const t=result.tooltipBounds,r=result.windowBounds;
  if(t.left<r.left-.5||t.top<r.top-.5||t.right>r.right+.5||t.bottom>r.bottom+.5||t.left<-.5||t.top<-.5||t.right>w+.5||t.bottom>h+.5)failures.push('tooltip outside window/viewport');
  if(result.textLineRects.some(line=>line.top<result.effectBounds.top-.5||line.bottom>result.effectBounds.bottom+.5||line.top<result.bodyBounds.top-.5||line.bottom>result.bodyBounds.bottom+.5))failures.push('painted line outside visible effect/body');
  if(result.checkoutCalls.length)failures.push('checkout called');if(!result.sourceUnchanged)failures.push('formal catalog mutated');
  const shot=sku+'_'+w+'x'+h+'.png';await b.shot(path.join(out,shot),{x:0,y:0,width:w,height:h});records.push({viewport:[w,h],category,screenshot:shot,failures,...result});
  fs.writeFileSync(path.join(out,'visual_checks.json'),JSON.stringify({scope:'Actual production XML/JS/CSS assembly; formal release catalogs, explicit offline VIP12; browser is not native game rendering. No real account, payment, order or save request.',sourceHashes:hashes,checks:records},null,2));
  console.log((failures.length?'FAIL ':'PASS ')+shot+(failures.length?' '+failures.join('; '):' all formal effect lines visible, tooltip within window, no checkout'));
 }
 const assembly=JSON.parse(fs.readFileSync(path.join(out,'preview/assembly.json'),'utf8')),compiled=JSON.parse(fs.readFileSync(path.join(out,'compile.json'),'utf8').replace(/^\uFEFF/,'')),sourceGraph=Object.fromEntries(assembly.sourceGraph.map(r=>[r.path,r.sha256]));
 const compiledRecords=compiled.records.map(r=>{const readHash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');return {relative:r.relative,sourceMatchesCompile:readHash(r.source)===r.sourceHash.toLowerCase(),previewMatchesCompile:sourceGraph[r.relative]===r.sourceHash.toLowerCase(),contentMatchesSource:readHash(r.content)===r.sourceHash.toLowerCase(),runtimeMatchesCompile:readHash(r.artifact)===r.compiledHash.toLowerCase()};});
 const success=records.length===6&&records.every(r=>r.failures.length===0)&&compiledRecords.every(r=>r.sourceMatchesCompile&&r.previewMatchesCompile&&r.contentMatchesSource&&r.runtimeMatchesCompile);
 fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify({success,nativeGameVisualVerification:false,sourceHashes:hashes,compiledRecords,states:records.length,screenshots:records.map(r=>({path:r.screenshot,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(out,r.screenshot))).digest('hex')}))},null,2));
 if(!success)throw Error('VIP tooltip visual / source verification failed; see visual_checks.json');
 console.log('VIP_TOOLTIP_VISUAL_PASS 6 states; formal per-effect lines complete, no inner crop, bounded tooltip, no checkout, preview/source/content/runtime agree');
}finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
