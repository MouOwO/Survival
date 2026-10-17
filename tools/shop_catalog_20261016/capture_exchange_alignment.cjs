'use strict';
// Focused production-UI layout proof. Balances/eligibility are explicit local
// fixtures; no checkout is invoked and native engine messages are not emulated.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'design_refs/shop_catalog_20261016/ui/exchange_button_fix');
const base=path.join(repo,'design_refs/shop_catalog_20261016/ui/preview'),production=['black_lion_market.js','black_lion_market_model.js','commerce_wallet.js'].map(file=>'panorama/src/scripts/custom_game/'+file);
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')).digest('hex');
process.chdir(repo);
async function main(){
 const reuseFrozen=process.argv.includes('--reuse-frozen-preview');
 if(!reuseFrozen){const built=spawnSync(process.execPath,['tools/shop_catalog_20261016/preview.cjs'],{encoding:'utf8',windowsHide:true});if(built.status!==0)throw Error(built.stdout+built.stderr);fs.mkdirSync(out,{recursive:true});fs.cpSync(base,path.join(out,'preview'),{recursive:true});}
 const assembly=JSON.parse(fs.readFileSync(path.join(out,'preview/assembly.json'),'utf8')),graph=Object.fromEntries(assembly.sourceGraph.map(row=>[row.path,row.sha256]));
 const sourceHashes=production.map(file=>({path:file,sha256:hash(file)}));for(const row of sourceHashes)assert.equal(graph[row.path.replace('panorama/src/','')],row.sha256,'Frozen browser source matches production '+row.path);
 const report={at:new Date().toISOString(),kind:'shop_exchange_row_alignment',notNativeGameCapture:true,outboundStubs:true,reusedFrozenSnapshot:reuseFrozen,sourceHashes,assembly,checks:[],limitations:['The production XML/JS/CSS runs in a local browser Panorama adapter. Product definitions come from formal compiled catalogs; eligibility and balances are labeled offline samples.','No checkout is clicked or sent. The native insufficient-points message is covered separately by wallet tests, not claimed as a native engine visual check here.','The adapter resolves the existing ticket_illustrated_png and gift_light_png native textures to nonexistent PNG aliases. These exact browser-only bitmap misses are recorded without altering source icons; source PNGs without the _png suffix exist and the action-column geometry remains measurable.',...(reuseFrozen?['The existing frozen snapshot was reused because another concurrent task temporarily added a missing common/item_resources.js include to the full HUD graph. All three relevant market/model/wallet source hashes are verified against the frozen assembly.']:[])]};
 const scenarios=[[1600,900,'vip0','home'],[1600,900,'vip0','all'],[1600,900,'insufficient','all'],[960,720,'insufficient','all'],[1600,900,'vip0','vip'],[1600,900,'vip12','vip']];
 const b=await browser();try{
  for(const [width,height,state,category]of scenarios){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(path.join(out,'preview/index.html'),'?page=commerce&state='+state+'&category='+category);assert(await b.run('marketReady'),'Production component preview loads');
   if(category==='all')await b.run(String.raw`(()=>{const view=cfg.SurvivalCommerceView.Inspect(),index=view.visibleSkus.findIndex(sku=>marketFixture.catalog.products.some(item=>item.sku===sku&&item.currency==='shop_points'));if(index<0)throw Error('Formal point exchange is absent');for(let step=0;step<Math.floor(index/40);step++){const next=cfg.SurvivalBlackLionMarket.GetWindow().actions.FindChildrenWithClassTraverse('CJPageAction')[1];if(!next||!next.enabled)throw Error('Exchange page is not accessible');next.events.onactivate();}syncLayout();const market=cfg.SurvivalBlackLionMarket.GetWindow(),target=market.content.FindChildrenWithClassTraverse('BLMarketRow')[index%40];market.content.el.scrollTop=target.el.offsetTop;syncLayout();return true;})()`);
   await b.run('Promise.all([...document.querySelectorAll(".BLMarketWindow img")].map(image=>image.decode().catch(()=>false))).then(()=>{syncLayout();return true;})');
   const check=await b.run(String.raw`(()=>{
    syncLayout();const market=cfg.SurvivalBlackLionMarket.GetWindow(),windowBounds=market.panel.el.getBoundingClientRect(),listBounds=market.content.el.getBoundingClientRect(),scale=windowBounds.width/1120,view=cfg.SurvivalCommerceView.Inspect(),skus=view.visibleSkus.slice(view.page*40,(view.page+1)*40);
    const rows=market.content.FindChildrenWithClassTraverse('BLMarketRow').map((row,index)=>{
     const item=marketFixture.catalog.products.find(item=>item.sku===skus[index]),button=row.FindChildrenWithClassTraverse('BLMarketBuy')[0],caption=button.FindChildrenWithClassTraverse('BLMarketBuyText')[0],reason=row.FindChildrenWithClassTraverse('BLMarketDisabledReason')[0];
     const rb=row.el.getBoundingClientRect(),bb=button.el.getBoundingClientRect(),cb=caption.el.getBoundingClientRect(),reasonBounds=reason.el.getBoundingClientRect();
     return {sku:skus[index],name:row.__menuCell.namePanel.text,method:item&&item.purchase_method,currency:item&&item.currency,disabledReason:item&&item.disabled_reason,buyText:caption.text,enabled:button.enabled,reasonVisible:reason.visible,reason:reason.visible?reason.text:'',rowHeight:rb.height/scale,buttonY:(bb.y-rb.y)/scale,buttonHeight:bb.height/scale,buttonCenterDelta:((bb.top+bb.bottom)-(rb.top+rb.bottom))/2/scale,captionCenterDelta:[((cb.left+cb.right)-(bb.left+bb.right))/2/scale,((cb.top+cb.bottom)-(bb.top+bb.bottom))/2/scale],reasonOverflow:reason.visible&&(reasonBounds.top<bb.bottom-.1||reasonBounds.bottom>rb.bottom+.1),rowBounds:rb.toJSON(),buttonBounds:bb.toJSON()};
    });
    return {windowBounds:windowBounds.toJSON(),listBounds:listBounds.toJSON(),rows,tabs:document.querySelectorAll('.BLMarketTab').length,errors:previewErrors,missingImages:[...document.querySelectorAll('.BLMarketWindow img')].filter(image=>!image.complete||!image.naturalWidth).map(image=>image.src),checkoutCalls:previewCalls.filter(call=>call.method==='paid'||call.method==='wallet'||call.payload&&/purchase|checkout/.test(call.payload.action||'')),fixture:marketFixture.note};
   })()`);
   assert.deepEqual(check.errors,[]);check.knownNativeTextureAliases=check.missingImages.filter(file=>/\/custom_game\/(?:lottery_handoff_v1\/ticket_illustrated_png|commerce_jade_v1\/gift_light_png)\.png$/.test(file));assert.deepEqual(check.missingImages.filter(file=>!check.knownNativeTextureAliases.includes(file)),[],'No new or unrelated missing preview assets');assert.equal(check.tabs,5);assert.deepEqual(check.checkoutCalls,[]);assert(check.rows.length>0);
   assert(check.windowBounds.x>=-.1&&check.windowBounds.y>=-.1&&check.windowBounds.right<=width+.1&&check.windowBounds.bottom<=height+.1,'Market remains within the viewport');
   for(const row of check.rows){
    assert(row.captionCenterDelta.every(value=>Math.abs(value)<.12),'Button caption stays centered for '+row.sku);assert(!row.reasonOverflow,'VIP reason does not overlap or clip');
    if(!row.reasonVisible){assert(Math.abs(row.rowHeight-64)<.12,'Reason-free rows use 64px');assert(Math.abs(row.buttonY-14)<.12,'Reason-free buttons use y=14');assert(Math.abs(row.buttonCenterDelta)<.12,'Button is vertically centered inside its row');}
   }
   const insufficient=check.rows.filter(row=>row.method==='wallet'&&row.currency==='shop_points'&&['insufficient_balance','commerce_balance_insufficient'].includes(row.disabledReason));
   if(state==='insufficient'){assert(insufficient.length>0,'Formal exchange rows exercise the typed insufficient-balance scenario');for(const row of insufficient){assert.equal(row.reasonVisible,false,'No permanent insufficient-points label');assert.equal(row.reason,'');assert.equal(row.buyText,'兑换');assert.equal(row.enabled,true,'Exchange remains clickable for local native feedback');}}
   if(category==='vip'&&state==='vip0'){assert(check.rows.every(row=>!row.enabled&&row.reasonVisible&&row.reason.includes('VIP')),'VIP restrictions retain their existing reason and disabled action');}
   if(category==='vip'&&state==='vip12')assert(check.rows.every(row=>row.enabled&&!row.reasonVisible),'Eligible VIP rows retain ordinary centered actions');
   const screenshot=category+'_'+state+'_'+width+'x'+height+'.png';await b.shot(path.join(out,screenshot),{x:0,y:0,width,height});
   if(state==='insufficient'&&width===1600){const first=insufficient[0].buttonBounds,clip={x:Math.floor(first.x-18),y:Math.floor(check.listBounds.y),width:Math.ceil(first.width+36),height:Math.ceil(check.listBounds.height)};await b.shot(path.join(out,'exchange_button_right_column.png'),clip);check.buttonColumnCrop={file:'exchange_button_right_column.png',clip};}
   report.checks.push({viewport:[width,height],state,category,screenshot,typedInsufficientRows:insufficient.length,...check});
  }
  const normal=report.checks.find(row=>row.state==='vip0'&&row.category==='all'),insufficient=report.checks.find(row=>row.state==='insufficient'&&row.viewport[0]===1600);
  report.comparison=insufficient.rows.filter(row=>row.method==='wallet'&&row.currency==='shop_points'&&!row.reasonVisible).map(row=>{const before=normal.rows.find(item=>item.sku===row.sku);assert(before,'Comparable normal exchange row exists');assert(Math.abs(row.rowHeight-before.rowHeight)<.12&&Math.abs(row.buttonY-before.buttonY)<.12,'Low balance does not move the exchange action');return {sku:row.sku,normalHeight:before.rowHeight,insufficientHeight:row.rowHeight,normalButtonY:before.buttonY,insufficientButtonY:row.buttonY};});
  report.sourceChanged=sourceHashes.filter(row=>hash(row.path)!==row.sha256).map(row=>row.path);assert.deepEqual(report.sourceChanged,[],'Relevant production sources stayed frozen');report.status='PASS_EXCHANGE_BUTTON_ALIGNMENT';
 }catch(error){report.status='FAIL_EXCHANGE_BUTTON_ALIGNMENT';report.failure=error.stack||String(error);throw error;}
 finally{b.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));}
 console.log('EXCHANGE_BUTTON_ALIGNMENT_PASS '+path.relative(repo,path.join(out,'report.json')));
}
if(require.main===module)main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
