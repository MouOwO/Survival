'use strict';
const fs=require('fs'),assert=require('assert/strict'),{browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const out='design_refs/video_shop_20261015/final';
(async()=>{const b=await browser(),checks=[];try{
for(const [width,height] of [[960,720],[1280,720],[1600,900],[1920,1080],[2560,1440]]){
 await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
 for(const state of ['vip12','vip0']){
  await b.go(out+'/preview/index.html','?state='+state);assert(await b.run('videoBundleReady'));
  const view=await b.run(`(()=>{const w=cfg.SurvivalBlackLionMarket.GetWindow(),rows=w.content.FindChildrenWithClassTraverse('BLMarketRow');return {errors:window.previewErrors||[],names:rows.map(r=>r.FindChildrenWithClassTraverse('BLMarketName')[0].text),buttons:rows.map(r=>({name:r.FindChildrenWithClassTraverse('BLMarketName')[0].text,enabled:r.FindChildrenWithClassTraverse('BLMarketBuy')[0].enabled,text:r.FindChildrenWithClassTraverse('BLMarketBuy')[0].Children()[0].text})),box:w.panel.el.getBoundingClientRect().toJSON(),calls:previewCalls.filter(c=>['paid','wallet'].includes(c.method))};})()`);
  assert.equal(view.errors.length,0);assert.equal(view.names.length,15);assert.equal(new Set(view.names).size,15);assert.equal(view.calls.length,0);
  assert(view.box.x>=-1&&view.box.y>=-1&&view.box.right<=width+1&&view.box.bottom<=height+1,JSON.stringify(view.box));
  assert.equal(view.buttons.filter(r=>r.enabled).length,state==='vip12'?13:3);
  for(const name of ['新手礼包','新皮肤礼包']){const row=view.buttons.find(r=>r.name===name);assert(!row.enabled);assert.equal(row.text,'待开放');}
  if(width===1600&&state==='vip12')await b.shot(out+'/bundles_1600x900.png',{x:0,y:0,width,height});
  if(width===1600&&state==='vip0')await b.shot(out+'/vip_locked_1600x900.png',{x:0,y:0,width,height});
  const details=await b.run(`(()=>{window.activeVideoRow=cfg.SurvivalBlackLionMarket.GetWindow().content.FindChildrenWithClassTraverse('BLMarketRow').find(r=>r.FindChildrenWithClassTraverse('BLMarketName')[0].text==='新人礼包');activeVideoRow.__purpleShow(true);syncLayout();return true;})()`);assert(details);await sleep(650);await b.run('syncLayout()');
  const tip=await b.run(`(()=>{const t=activeVideoRow.__purpleDetail,rows=t.FindChildrenWithClassTraverse('RCBundleItem'),m=t.FindChildrenWithClassTraverse('RCBundleMemberEffect')[0];rows[rows.length-1].events.onmouseover();syncLayout();const text=m.text;return {count:rows.length,text,box:t.el.getBoundingClientRect().toJSON(),summary:t.FindChildrenWithClassTraverse('RCProductEffect')[0].text,icons:rows.map(r=>r.FindChildrenWithClassTraverse('RCBundleArt')[0].el.src)};})()`);
  assert.equal(tip.count,8);assert(tip.text.includes('伐木斧'));assert(tip.text.length>10);assert(tip.summary.length<100);assert(tip.icons[7].includes('quelling_blade'));
  assert(tip.box.x>=-1&&tip.box.y>=-1&&tip.box.right<=width+1&&tip.box.bottom<=height+1,JSON.stringify(tip.box));
  if(state==='vip12')await b.shot(out+'/newcomer_details_'+width+'x'+height+'.png',{x:0,y:0,width,height});
  if(width===1600&&state==='vip0'){
   const blocked=await b.run(`(()=>{activeVideoRow.__purpleHide();const row=cfg.SurvivalBlackLionMarket.GetWindow().content.FindChildrenWithClassTraverse('BLMarketRow').find(r=>r.FindChildrenWithClassTraverse('BLMarketName')[0].text==='V1专属特惠礼包');row.__purpleShow(true);const t=row.__purpleDetail,buy=t.FindChildrenWithClassTraverse('CommercePurpleBuy')[0];buy.events.onactivate();return {enabled:buy.enabled,calls:previewCalls.filter(c=>['paid','wallet'].includes(c.method))};})()`);assert(!blocked.enabled);assert.equal(blocked.calls.length,0);
  }
  if(width===1600){
   const pending=await b.run(`(()=>{activeVideoRow.__purpleHide();const row=cfg.SurvivalBlackLionMarket.GetWindow().content.FindChildrenWithClassTraverse('BLMarketRow').find(r=>r.FindChildrenWithClassTraverse('BLMarketName')[0].text==='新手礼包');row.__purpleShow(true);window.pendingVideoRow=row;syncLayout();return true;})()`);assert(pending);await sleep(650);await b.run('syncLayout()');
   const noOrder=await b.run(`(()=>{const t=pendingVideoRow.__purpleDetail,buy=t.FindChildrenWithClassTraverse('CommercePurpleBuy')[0];buy.events.onactivate();return {enabled:buy.enabled,calls:previewCalls.filter(c=>['paid','wallet'].includes(c.method)),text:t.FindChildrenWithClassTraverse('CommercePurpleState').map(p=>p.text).join('\\n')};})()`);assert(!noOrder.enabled);assert.equal(noOrder.calls.length,0);assert(noOrder.text.includes('缺少完整外观资源'));
   if(state==='vip12')await b.shot(out+'/pending_assets_1600x900.png',{x:0,y:0,width,height});
  }
  checks.push({width,height,state,rows:15,available:state==='vip12'?13:3,member_effect_switch:true,tooltip_in_viewport:true,orders_created:0,passed:true});
 }
}
fs.writeFileSync(out+'/visual_validation.json',JSON.stringify({passed:true,validation_scope:'Actual production Panorama JavaScript/CSS through browser adapter, exact server-compiled catalogs; synthetic account/VIP state; no real order or account connection; not native game verification.',checks},null,2));console.log('VIDEO_BUNDLE_VISUAL_PASS '+checks.length+' states, 15 rows, 8-member effect selection, VIP gates, pending no-order, five resolutions');
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
