'use strict';
// Actual market controls, frozen local fixture. Never sends a purchase/order.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser}=require('../commerce_points_20261016/cdp.cjs');
const root=path.resolve(__dirname,'../..'),out='output/shop_promo_gcoin_20261018';process.chdir(root);
function inspect(){
 const menu=cfg.SurvivalBlackLionMarket.GetWindow(),view=cfg.SurvivalCommerceView.Inspect();
 const rect=node=>node.el.getBoundingClientRect().toJSON();
 const rows=menu.content.FindChildrenWithClassTraverse('BLMarketRow').map(row=>{
  const first=cls=>row.FindChildrenWithClassTraverse(cls)[0];
  const main=first('BLMarketPriceMain'),reference=first('BLMarketPriceReference'),buy=first('BLMarketBuy');
  return {name:row.__menuCell.namePanel.text,bounds:rect(row),main:main?.text,mainBounds:main&&rect(main),mainSize:main&&parseFloat(getComputedStyle(main.el).fontSize),
   reference:reference?.text,referenceBounds:reference&&rect(reference),referenceSize:reference&&parseFloat(getComputedStyle(reference.el).fontSize),
   decoration:reference&&getComputedStyle(reference.el).textDecorationLine,buyBounds:buy&&rect(buy)};
 });
 const visibleLabels=[...menu.panel.el.querySelectorAll('[data-panel-type="Label"],.pano-label')].filter(el=>{const r=el.getBoundingClientRect();return r.width>0&&r.height>0;}).map(el=>el.textContent);
 return {view,rows,visibleLabels,errors:previewErrors,transactionCalls:previewCalls.filter(row=>row.name==='survival_commerce_request'&&row.payload.action==='purchase'||row.name==='survival_payment_request'&&row.payload.action==='create'),window:rect(menu.panel)};
}
(async()=>{
 const b=await browser(),report={kind:'actual_source_browser_preview',notGameCapture:true,scenes:[]};
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*']});
  for(const [width,height]of[[1920,1080],[1280,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(out+'/preview/index.html','?page=commerce&category=promotions');assert.equal(await b.run('iconClarityReady'),true);
   await b.run('syncLayout();document.fonts.ready.then(()=>true)');
   const state=await b.run('('+inspect.toString()+')()');assert.deepEqual(state.errors,[]);assert.deepEqual(state.transactionCalls,[]);
   assert(state.rows.length>0);assert(state.rows.every(row=>row.reference),'Every listed promotion has the requested comparison');
   for(const row of state.rows){
    assert(!/U币/.test(row.main+' '+row.reference),row.name+' uses G币');
    const current=Number(row.main.replace(/[^\d.]/g,'')),original=Number(row.reference.replace(/[^\d.]/g,''));
    assert.equal(original,current*1.5,row.name+' comparison is current × 1.5');
    assert(row.referenceSize<row.mainSize,row.name+' comparison font is smaller');assert(row.decoration.includes('line-through'));
    assert(row.mainBounds.right<=row.referenceBounds.left+1,row.name+' current/reference do not overlap');
    assert(row.referenceBounds.right<=row.buyBounds.left-1,row.name+' comparison clears purchase button');
   }
   const file=out+'/shop_promotions_'+width+'x'+height+'.png';await b.shot(file,{x:0,y:0,width,height});
   const first=state.rows.find(row=>row.bounds.y>=0&&row.bounds.bottom<=height);
   const crop=out+'/shop_promotion_row_'+width+'x'+height+'.png';await b.shot(crop,{x:Math.max(0,first.bounds.x),y:first.bounds.y,width:Math.min(width-first.bounds.x,first.bounds.width),height:first.bounds.height});
   report.scenes.push({width,height,file,crop,...state});
  }
  report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack;try{await b.shot(out+'/preview_failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/visual_validation.json',JSON.stringify(report,null,2)+'\n');b.close();}
 console.log('SHOP_PROMO_GCOIN_VISUAL_PASS '+report.scenes.length+' resolutions');
})().catch(error=>{console.error(error);process.exitCode=1;});
