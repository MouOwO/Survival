'use strict';
// Offline browser preview of the production XML/JS/CSS. No native-game claims.
const fs=require('node:fs'),assert=require('node:assert/strict'),{browser,sleep}=require('./browser.cjs');
const out='design_refs/market_filter_20261017/preview',results=[];
(async()=>{const b=await browser();try{
 for(const [width,height] of [[1600,900],[960,720]]){
  await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
  await b.go(out+'/index.html','?page=commerce&state=normal');
  assert(await b.run('previewReady'),'Production preview did not finish loading');
  await b.run("nodes.BLMarketSection_all.events.onactivate();syncLayout();true");
  const initial=await b.run('JSON.stringify(PREVIEW_FIXTURE.commerce)');
  for(const id of ['u_coin','shop_points','all']){
   await b.run("nodes['BLMarketPurchaseType_"+id+"'].events.onactivate();syncLayout();true");
   await sleep(100);
   const state=await b.run(`(()=>{
    const p=nodes.BLMarketPurchaseType,win=nodes.BlackLionMarketWindow;
    const rect=el=>{const r=el.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom};};
    return {kind:'production_component_browser_preview',viewport:[innerWidth,innerHeight],inspect:cfg.SurvivalCommerceView.Inspect(),
      options:p.Children().map(b=>({id:b.id,label:b.el.textContent,selected:b.BHasClass('UISelected'),box:rect(b.el)})),
      balances:win.FindChildrenWithClassTraverse('BLMarketBalanceText').map(p=>p.text),
      recharge:!!nodes.BlackLionMarketRecharge,window:rect(win.el),control:rect(p.el),
      errors:previewErrors,orders:previewCalls.filter(c=>['purchase','create'].includes(c.payload&&c.payload.action)),
      sourceFixture:JSON.stringify(PREVIEW_FIXTURE.commerce)};
   })()`);
   assert.equal(state.inspect.purchaseType,id);
   assert.deepEqual(state.options.map(x=>[x.id,x.label]),[['BLMarketPurchaseType_u_coin','U币'],['BLMarketPurchaseType_shop_points','积分'],['BLMarketPurchaseType_all','全部']]);
   assert.deepEqual(state.options.filter(x=>x.selected).map(x=>x.id),['BLMarketPurchaseType_'+id]);
   assert.deepEqual(state.balances,['U币 20','积分 320']);assert(state.recharge);
   assert.deepEqual(state.errors,[]);assert.deepEqual(state.orders,[]);assert.equal(state.sourceFixture,initial);
   assert(state.window.x>=-1&&state.window.y>=-1&&state.window.right<=width+1&&state.window.bottom<=height+1,'Window outside viewport');
   for(const p of state.options)assert(p.box.x>=state.control.x-1&&p.box.right<=state.control.right+1&&p.box.y>=state.control.y-1&&p.box.bottom<=state.control.bottom+1,'Option outside control');
   delete state.sourceFixture;
   const screenshot='market_'+width+'x'+height+'_'+id+'.png';
   await b.shot(out+'/'+screenshot,width,height);results.push({...state,screenshot});
  }
 }
 fs.writeFileSync(out+'/acceptance.json',JSON.stringify({kind:'production_component_browser_preview',scope:'Local production XML/JS/CSS plus explicit fixture. HTTP/HTTPS blocked. Not a native-game screenshot.',results},null,2));
 console.log('MARKET_FILTER_BROWSER_PASS '+results.length+' screenshots, 2 viewports, all 3 filters, no orders or external network');
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
