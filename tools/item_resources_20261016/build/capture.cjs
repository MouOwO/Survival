'use strict';
// Executes the production assemblies. No account, save, purchase or draw runs.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {browser,sleep}=require('../../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../../..'),out='design_refs/item_resources_20261016/build',preview=out+'/preview/index.html';
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const targets=[{name:'妖刀村正',sku:'video_p042',archive:'commerce_p042',lottery:'lottery_muramasa'},
 {name:'王之财宝',sku:'video_p043',archive:'commerce_p043',lottery:'lottery_kings_treasure'},
 {name:'朗基努斯枪',sku:'video_p048',archive:'commerce_p048',lottery:'lottery_spear_of_longinus'}];
const comparison={name:'斩魄刀',sku:'video_p151',archive:'commerce_p151'},allTargets=targets.concat(comparison);
function hash(file){return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');}
const inspectIcon=`function inspectIcon(panel,item){
 const resource=cfg.SurvivalItemResources&&cfg.SurvivalItemResources.Lookup(item);
 const element=panel&&panel.el,images=element?[...(element.matches('img')?[element]:element.querySelectorAll('img'))].filter(i=>i.getBoundingClientRect().width>0&&getComputedStyle(i).display!=='none').map(i=>({src:i.src,decoded:i.complete&&i.naturalWidth>0,natural:[i.naturalWidth,i.naturalHeight],bounds:i.getBoundingClientRect().toJSON()})):[];
 return {identity:item.item_id||item.id||item.sku,resource,images};
}`;
async function main(){const b=await browser(),report={at:new Date().toISOString(),kind:'production_panorama_component_browser_assembly',notGameCapture:true,syntheticOwnership:true,noAccountSavePurchaseOrDraw:true,registry:{tableSha256:hash('data/ui/item_resources.json'),resolverSha256:hash('panorama/src/scripts/custom_game/common/item_resources.js')},targets,views:{},screens:[],checks:[]};try{
 async function load(query,width=1920,height=1080){await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(preview,query);assert.equal(await b.run('itemResourceReady'),true);await sleep(150);assert.deepEqual(await b.run('previewErrors'),[]);}
 async function shot(name,width=1920,height=1080){const file=out+'/'+name+'.png';await b.shot(file,{x:0,y:0,width,height});report.screens.push({path:file,sha256:hash(file),width,height});}
 await load('?page=archive&category=commerce_goods');
 report.views.archive=await b.run(`(()=>{${inspectIcon}return nodes.ArchiveGrid.Children().filter(c=>c.visible&&c.__archiveCategory==='commerce_goods').map(c=>({id:c.__archiveItem.id,name:c.__archiveItem.name,...inspectIcon(c.__v10.art,c.__archiveItem)}));})()`);
 assert.equal(report.views.archive.length,await b.run('PREVIEW_FIXTURE.v10.pages.commerce_goods.length'));
 for(const t of allTargets){
  await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(c=>c.__archiveItem?.id===${JSON.stringify(t.archive)});if(!card)throw Error('Missing archive card');nodes.ArchiveGrid.el.scrollTop=card.el.offsetTop-120;card.events.onmouseover();syncLayout();return true;})()`);await sleep(180);await shot('archive_'+(t.lottery||t.sku));
 }
 await load('?page=commerce&category=all');
 report.views.commerce=[];
 const total=await b.run('cfg.SurvivalCommerceView.Inspect().visibleSkus.length');
 for(let page=0;page<Math.ceil(total/40);page++){
  if(page)await b.run(`(()=>{const market=cfg.SurvivalBlackLionMarket.GetWindow();market.actions.FindChildrenWithClassTraverse('CJPageAction')[1].events.onactivate();syncLayout();return true;})()`);
  await b.run('Promise.all([...document.images].map(i=>i.decode().catch(()=>false))).then(()=>true)');
  const rows=await b.run(`(()=>{${inspectIcon}const state=cfg.SurvivalCommerceView.Inspect(),skus=state.visibleSkus.slice(state.page*40,(state.page+1)*40),market=cfg.SurvivalBlackLionMarket.GetWindow(),items=PREVIEW_FIXTURE.commerce.wallet.products.concat(PREVIEW_FIXTURE.commerce.paid.products);return market.content.FindChildrenWithClassTraverse('BLMarketRow').map((c,i)=>({sku:skus[i],name:c.__menuCell.namePanel.text,...inspectIcon(c.__menuCell.iconPanel,items.find(p=>p.sku===skus[i])||{})}));})()`);
  report.views.commerce.push(...rows);
  for(const t of allTargets.filter(t=>rows.some(r=>r.sku===t.sku))){
   await b.run(`(()=>{const market=cfg.SurvivalBlackLionMarket.GetWindow(),state=cfg.SurvivalCommerceView.Inspect(),row=market.content.FindChildrenWithClassTraverse('BLMarketRow')[state.visibleSkus.indexOf(${JSON.stringify(t.sku)})%40];market.content.el.scrollTop=row.el.offsetTop-140;row.events.onmouseover();syncLayout();return true;})()`);await sleep(180);await shot('commerce_'+(t.lottery||t.sku));
  }
 }
 await load('?page=lottery&state=details&pool=summer');
 report.views.lottery=await b.run(`(()=>{${inspectIcon}return nodes.LotteryInfoList.Children().filter(c=>c.visible&&c.__lotteryItem).map(c=>({id:c.__lotteryItem.id,name:c.__lotteryItem.name,...inspectIcon(c.__lotteryPrizeFace?.host||c.__lotteryGW2Cell?.host||c,c.__lotteryItem)}));})()`);
 assert.equal(report.views.lottery.length,await b.run("PREVIEW_FIXTURE.lottery.members.filter(x=>x.pool_id==='summer').length"));
 for(const t of targets){
  await b.run(`(()=>{const card=nodes.LotteryInfoList.Children().find(c=>c.__lotteryItem?.id===${JSON.stringify(t.lottery)});if(!card)throw Error('Missing formal summer pool reward');nodes.LotteryInfoList.el.scrollTop=card.el.offsetTop-180;card.events.onmouseover();syncLayout();return true;})()`);await sleep(180);await shot('lottery_'+t.lottery);
 }
 for(const t of targets){
  const a=report.views.archive.find(r=>r.id===t.archive),c=report.views.commerce.find(r=>r.sku===t.sku),l=report.views.lottery.find(r=>r.id===t.lottery);
  assert(a&&c&&l,'Every target appears in all three real UI renderers: '+t.name);
  for(const row of[a,c,l]){assert(row.resource&&row.resource.uri,'Target has registered canonical resource');assert(row.images.length,'Target actual image node exists');assert(row.images.every(i=>i.decoded),'Target image bytes decode');}
  assert.equal(a.resource.id,c.resource.id);assert.equal(a.resource.id,l.resource.id);
  assert.equal(a.resource.uri,c.resource.uri);assert.equal(a.resource.uri,l.resource.uri);
  assert.equal(a.images[0].src,c.images[0].src);assert.equal(a.images[0].src,l.images[0].src);
  report.checks.push({name:t.name,canonical:a.resource.id,uri:a.resource.uri,actualDecodedImage:a.images[0].src,status:'PASS'});
 }
 const blade=report.views.archive.find(r=>r.id===comparison.archive),sword=report.views.commerce.find(r=>r.sku===comparison.sku),muramasa=report.views.archive.find(r=>r.id===targets[0].archive);
 assert(blade&&sword&&blade.resource&&sword.resource);assert.equal(blade.resource.id,sword.resource.id);assert.equal(blade.images[0].src,sword.images[0].src);assert.notEqual(blade.resource.id,muramasa.resource.id);assert.notEqual(blade.images[0].src,muramasa.images[0].src);
 report.checks.push({name:'P151 斩魄刀与 P042 妖刀村正分别保留独立图标',spiritKatana:{id:blade.resource.id,uri:blade.resource.uri},muramasa:{id:muramasa.resource.id,uri:muramasa.resource.uri},status:'PASS'});
 await load('?page=archive&category=commerce_goods',1280,720);await shot('archive_1280x720',1280,720);
 report.outboundEvents=await b.run('previewCalls.filter(c=>c.method===\'wallet\'||c.method===\'paid\'||c.name===\'ui_lottery_draw\')');assert.deepEqual(report.outboundEvents,[]);
 report.assemblySha256=hash(out+'/preview/assembly.json');report.status='PASS';
 }catch(e){report.status='FAIL';report.failure=e.stack;try{report.previewErrors=await b.run('previewErrors');await b.shot(out+'/failure.png');}catch{}throw e;}finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2)+'\n');b.close();}
 console.log('ITEM_RESOURCE_VISUAL_PASS '+report.checks.length+' cross-UI targets, '+report.screens.length+' screenshots');}
main().catch(e=>{console.error(e);process.exitCode=1;});
