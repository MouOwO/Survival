'use strict';
// Browser assemblies use real production factories; no client/process/save calls.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const{browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);
const mode=process.argv[2]||'after';if(!['before','after'].includes(mode))throw Error('Expected before/after');
const out='design_refs/item_fill_20261017/'+mode,preview=out+'/index.html';fs.mkdirSync(out,{recursive:true});
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const inspect=`function imageInfo(panel){const box=panel.el.getBoundingClientRect(),images=[...(panel.el.matches('img')?[panel.el]:panel.el.querySelectorAll('img'))].filter(i=>{const r=i.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(i).display!=='none';}).map(i=>{const r=i.getBoundingClientRect(),s=getComputedStyle(i);return {uri:i.src,decoded:i.complete&&i.naturalWidth>0,natural:[i.naturalWidth,i.naturalHeight],bounds:r.toJSON(),fit:s.objectFit,padding:s.padding,resourceId:i.dataset.itemResourceId||null};});return{bounds:box.toJSON(),images};}`;
async function main(){const b=await browser(),report={at:new Date().toISOString(),mode,kind:'real_source_browser_assembly',notGameCapture:true,noAccountSavePurchaseOrDraw:true,views:{},screens:[],checks:[]};try{
 async function load(query,width=1920,height=1080){await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(preview,query);assert.equal(await b.run('itemResourceReady'),true);await sleep(180);assert.deepEqual(await b.run('previewErrors'),[]);}
 async function shot(name,width=1920,height=1080){const file=out+'/'+name+'.png';await b.shot(file,{x:0,y:0,width,height});report.screens.push({path:file,sha256:hash(file),width,height});}
 async function rows(expression){await b.run('Promise.all([...document.images].map(i=>i.decode().catch(()=>false))).then(()=>true)');return b.run(`(()=>{${inspect}return ${expression};})()`);}
 await load('?page=archive&category=commerce_goods');
 report.views.archive=await rows(`nodes.ArchiveGrid.Children().filter(c=>c.visible&&c.__archiveCategory==='commerce_goods').map(c=>({id:c.__archiveItem.id,name:c.__archiveItem.name,kind:cfg.SurvivalItemResources.Lookup(c.__archiveItem)?.kind,...imageInfo(c.__v10.art)}))`);
 for(const id of['commerce_p027','commerce_p016','commerce_p042','vip_privilege_11']){
  const found=await b.run(`(()=>{const c=nodes.ArchiveGrid.Children().find(c=>c.__archiveItem?.id===${JSON.stringify(id)});if(!c)return false;nodes.ArchiveGrid.el.scrollTop=c.el.offsetTop-120;c.events.onmouseover();syncLayout();return true;})()`);
  if(found){await sleep(140);await shot('archive_'+id);}
 }
 await load('?page=commerce&category=all');report.views.commerce=[];
 const total=await b.run('cfg.SurvivalCommerceView.Inspect().visibleSkus.length');
 for(let page=0;page<Math.ceil(total/40);page++){
  if(page)await b.run(`(()=>{cfg.SurvivalBlackLionMarket.GetWindow().actions.FindChildrenWithClassTraverse('CJPageAction')[1].events.onactivate();syncLayout();return true;})()`);
  const data=await rows(`(()=>{const s=cfg.SurvivalCommerceView.Inspect(),skus=s.visibleSkus.slice(s.page*40,(s.page+1)*40),m=cfg.SurvivalBlackLionMarket.GetWindow(),all=PREVIEW_FIXTURE.commerce.wallet.products.concat(PREVIEW_FIXTURE.commerce.paid.products);return m.content.FindChildrenWithClassTraverse('BLMarketRow').map((c,i)=>({id:skus[i],kind:cfg.SurvivalItemResources.Lookup(all.find(p=>p.sku===skus[i]))?.kind,...imageInfo(c.__menuCell.iconPanel)}));})()`);
  report.views.commerce.push(...data);
  for(const id of['video_p027','video_p016','video_p042','video_vip_11'].filter(id=>data.some(r=>r.id===id))){await b.run(`(()=>{const m=cfg.SurvivalBlackLionMarket.GetWindow(),s=cfg.SurvivalCommerceView.Inspect(),r=m.content.FindChildrenWithClassTraverse('BLMarketRow')[s.visibleSkus.indexOf(${JSON.stringify(id)})%40];m.content.el.scrollTop=r.el.offsetTop-120;r.events.onmouseover();syncLayout();return true;})()`);await sleep(140);await shot('commerce_'+id);}
 }
 await load('?page=lottery&state=details&pool=summer');
 report.views.lottery=await rows(`nodes.LotteryInfoList.Children().filter(c=>c.visible&&c.__lotteryItem).map(c=>({id:c.__lotteryItem.id,name:c.__lotteryItem.name,kind:cfg.SurvivalItemResources.Lookup(c.__lotteryItem)?.kind,...imageInfo(c.__lotteryPrizeFace?.host||c.__lotteryGW2Cell?.host||c)}))`);
 await shot('lottery_pool');
 for(const id of['lottery_muramasa','lottery_gathering_grimoire']){const found=await b.run(`(()=>{const c=nodes.LotteryInfoList.Children().find(c=>c.__lotteryItem?.id===${JSON.stringify(id)});if(!c)return false;nodes.LotteryInfoList.el.scrollTop=c.el.offsetTop-180;c.events.onmouseover();syncLayout();return true;})()`);if(found){await sleep(140);await shot('lottery_'+id);}}
 await load('?page=shop&category=other');report.views.shop=await rows(`(nodes.ShopItemList?.Children()||[]).map(c=>({name:c.el.textContent,...imageInfo(c)}))`);await shot('survival_shop');
 await load('?page=shop');report.views.shopEquipment=await rows(`(nodes.ShopItemList?.Children()||[]).map(c=>({name:c.el.textContent,...imageInfo(c)}))`);await shot('survival_shop_equipment');
 await load('?page=treasure');report.views.treasure=await rows(`(nodes.PreviewContext_archive||root).FindChildrenWithClassTraverse('TreasureCard').map(c=>({name:c.el.textContent,...imageInfo(c)}))`);await shot('treasure');
 await load('?page=archive&category=friend');
 await b.run(`(()=>{if(cfg.SurvivalCollection&&!cfg.SurvivalCollection.IsOpen())cfg.SurvivalCollection.Open('friend');const rows=PREVIEW_FIXTURE.archiveData.social.filter(r=>r.pool_id==='friend').map((r,i)=>({id:r.item_id,name:r.display_name,description:r.description,target:Number(r.max_owned),quality:r.quality,count:i===0?7:0,count_known:1,unlocked:i===0?1:0}));emit('survival_archive_snapshot',{ok:1,category_id:'friend',sequence:900,chunk:1,chunks:1,rows,social:{tickets:20,draw_cost:1,currency_name:'收藏券'}});syncLayout();return true;})()`);
 report.views.collection=await rows(`(nodes.PreviewContext_archive||root).FindChildrenWithClassTraverse('CollectionGW2Portrait').map((c,i)=>({id:cfg.SurvivalCollection.Inspect().rows[i]?.id,...imageInfo(c)}))`);await shot('collection');
 await load('?page=archive&category=commerce_goods',1280,720);await shot('archive_1280x720',1280,720);
 report.views.actualFactories=await b.run(`(()=>{${inspect}const host=$.CreatePanel('Panel',root,'FillValidationFactoryHost');host.style.position='24px 24px 0px';host.style.width='900px';host.style.height='170px';host.style.backgroundColor='#161a20';host.style.zIndex='2000001';const results=[];['video_p027','video_p016','video_p042','shop_equipment_iron_armor_01','vip_privilege_11'].forEach((id,index)=>{const cell=$.CreatePanel('Panel',host,'');cell.style.position=(index*170+10)+'px 10px 0px';cell.style.width='150px';cell.style.height='150px';cell.style.overflow='clip';const icon=cfg.SurvivalRewardPresentation.CreateRegisteredIcon(cell,{id},'',{width:150,height:150});if(!icon)throw Error('Missing factory '+id);icon.style.width='150px';icon.style.height='150px';results.push({id,kind:cfg.SurvivalItemResources.Lookup(id)?.kind,icon:icon.paneltype,vipNumber:icon.__survivalVIPBadge?.number?.text,...imageInfo(cell)});});syncLayout();return results;})()`);
 await b.run('Promise.all([...document.images].map(i=>i.decode().catch(()=>false))).then(()=>true)');
 report.views.actualFactories=await rows(`nodes.FillValidationFactoryHost.Children().map((c,i)=>({id:['video_p027','video_p016','video_p042','shop_equipment_iron_armor_01','vip_privilege_11'][i],kind:cfg.SurvivalItemResources.Lookup(['video_p027','video_p016','video_p042','shop_equipment_iron_armor_01','vip_privilege_11'][i])?.kind,vipNumber:c.Children()[0]?.__survivalVIPBadge?.number?.text,...imageInfo(c)}))`);
 await shot('factory_strip_1280x720',1280,720);
 await load('?page=archive&category=commerce_goods');
 report.views.inventory=await b.run(`(()=>{${inspect}const host=$.CreatePanel('Panel',root,'FillInventoryValidation');host.style.position='24px 24px 0px';host.style.width='700px';host.style.height='170px';host.style.backgroundColor='#161a20';host.style.zIndex='2000001';const items=['item_survival_growth_sword_01','item_survival_attack_gloves_shell','item_survival_iron_armor_shell'];const inventory=$.CreatePanel('Panel',host,'');inventory.style.width='700px';inventory.style.height='170px';for(let i=0;i<9;i++){const slot=$.CreatePanel('Panel',inventory,'inventory_slot_'+i);slot.style.position=(i*136)+'px 10px 0px';slot.style.width='126px';slot.style.height='126px';slot.visible=i<3;slot.style.overflow='clip';const image=$.CreatePanel('Panel',slot,'ItemImage');image.style.width='126px';image.style.height='126px';for(const id of['ItemCharges','ItemAltCharges']){const n=$.CreatePanel('Label',slot,id);n.text='7';n.style.zIndex='10';}}const source=PREVIEW_SOURCES['scripts/custom_game/topnav_remaining_5d5c1152eb.js'],body=source.slice(source.indexOf('    function refreshInventoryPresentation()'),source.indexOf('    function layoutMinimap('));if(!body)throw Error('Actual inventory function missing');const run=new Function('cfg','$','native','selectedUnit','valid','Entities','Abilities','CustomNetTables','style','findCached',body+';return refreshInventoryPresentation;')(cfg,$,()=>inventory,()=>7,p=>p&&p.IsValid(),{GetItemInSlot:(_,i)=>items[i]?i:-1},{GetAbilityName:i=>items[i]},{GetTableValue:()=>null},(p,v)=>Object.keys(v).forEach(k=>p.style[k]=v[k]),(p,id)=>p.FindChildTraverse(id));run();run();syncLayout();window.fillInventorySample={inventory,items,run};return inventory.Children().filter(c=>c.visible).map((c,i)=>({id:items[i],counter:c.FindChildTraverse('ItemCharges').el.style.opacity,...imageInfo(c.FindChildTraverse('ItemImage'))}));})()`);
 await b.run('Promise.all([...document.images].map(i=>i.decode().catch(()=>false))).then(()=>true)');
 report.views.inventory=await rows(`fillInventorySample.inventory.Children().filter(c=>c.visible).map((c,i)=>({id:fillInventorySample.items[i],counter:c.FindChildTraverse('ItemCharges').el.style.opacity,...imageInfo(c.FindChildTraverse('ItemImage'))}))`);
 await shot('inventory_actual_function');
 if(mode==='after'){
  for(const [view,data]of Object.entries(report.views)){
   if(!['archive','commerce','lottery','actualFactories','inventory','collection','shop','shopEquipment','treasure'].includes(view))continue;
   assert(data.length>0,'Actual production view has test rows: '+view);
   for(const row of data){if(['vip','hero','endless_emblem','layered_title'].includes(row.kind))continue;
    const image=row.images.find(i=>i.decoded);assert(image,view+' decoded '+row.id);assert.equal(image.fit,'cover',view+' fills with aspect-cover '+row.id);
   }
  }
  const vip=report.views.actualFactories.find(r=>r.id==='vip_privilege_11');assert.equal(vip.vipNumber,'11','VIP independent number retained');
  assert.deepEqual(report.views.inventory.map(r=>r.counter),['1','0','0'],'Native charges retained except equipment counters intentionally hidden');
  report.checks.push('All archive/commerce/lottery ordinary icons use native aspect-cover','Dota rectangular assault/platemail and dedicated art use shared factory','VIP11 number remains independent text','1280×720 and1920×1080 real source assemblies');
 }
 report.outboundEvents=await b.run("previewCalls.filter(c=>c.method==='wallet'||c.method==='paid'||c.name==='ui_lottery_draw')");assert.deepEqual(report.outboundEvents,[]);
 report.assemblySha256=hash(out+'/assembly.json');report.status='PASS';
 }catch(e){report.status='FAIL';report.failure=e.stack;try{report.previewErrors=await b.run('previewErrors');await b.shot(out+'/failure.png');}catch{}throw e;}finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2)+'\n');b.close();}
 console.log('ITEM_FILL_VISUAL_PASS '+mode+' '+report.screens.length+' screenshots');}
main().catch(e=>{console.error(e);process.exitCode=1;});
