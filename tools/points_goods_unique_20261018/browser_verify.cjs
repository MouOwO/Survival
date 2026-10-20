'use strict';
// Read-only production-component preview. All state changes below are local fixtures.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {fileURLToPath}=require('node:url');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base='design_refs/points_goods_unique_20261018',out=base+'/browser';
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
function inspect(){
 const bounds=el=>el.getBoundingClientRect().toJSON();
 const shown=el=>{for(let node=el;node;node=node.parentElement){const style=getComputedStyle(node);if(node.hidden||style.display==='none'||style.visibility==='hidden')return false;}const r=el.getBoundingClientRect();return r.width>0&&r.height>0;};
 const image=el=>({src:el.currentSrc||el.src,decoded:el.complete&&el.naturalWidth>0,width:el.naturalWidth,height:el.naturalHeight,bounds:bounds(el)});
 const label=node=>({text:node.text,bounds:bounds(node.el),align:getComputedStyle(node.el).textAlign,scrollWidth:node.el.scrollWidth,clientWidth:node.el.clientWidth,scrollHeight:node.el.scrollHeight,clientHeight:node.el.clientHeight});
 const canvas=nodes.ArchiveV10Canvas,grid=nodes.ArchiveGrid;
 const cards=grid.Children().filter(card=>card.visible&&card.__v10).map(card=>({id:card.__archiveItem.id,sourceCount:previewFixturePages.points.find(row=>row.id===card.__archiveItem.id)?.count,count:card.__archiveItem.count,state:cfg.ArchiveV10Semantics.State(card.__archiveItem,'points'),unique:cfg.ArchiveV10Semantics.IsUnlockItem(card.__archiveItem,'points'),bounds:bounds(card.el),name:label(card.__v10.name),status:label(card.__v10.count),statusVisible:shown(card.__v10.count.el),images:[...card.el.querySelectorAll('img')].filter(shown).map(image)}));
 const backgrounds=[...new Set([...canvas.el.querySelectorAll('*'),canvas.el].filter(shown).flatMap(el=>[...getComputedStyle(el).backgroundImage.matchAll(/url\(["']?([^"')]+)["']?\)/g)].map(match=>match[1])))];
 return {ready:previewState.ready,errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),canvas:bounds(canvas.el),grid:{bounds:bounds(grid.el),scrollTop:grid.el.scrollTop,clientHeight:grid.el.clientHeight,scrollHeight:grid.el.scrollHeight},images:[...canvas.el.querySelectorAll('img')].filter(shown).map(image),cards,backgrounds,calls:previewCalls,tooltip:{visible:nodes.ArchiveV10Tooltip.visible,state:nodes.ArchiveV10TooltipState.text,quantity:nodes.ArchiveV10TooltipQuantity.text,condition:nodes.ArchiveV10TooltipCondition.text,bounds:bounds(nodes.ArchiveV10Tooltip.el)}};
}
function contained(parent,child){return child.x>=parent.x-1&&child.y>=parent.y-1&&child.right<=parent.right+1&&child.bottom<=parent.bottom+1;}
function validate(info,width,height){
 assert(info.ready);assert.deepEqual(info.errors,[],'The production UI has no script errors');
 assert.equal(info.api.category,'points');assert.equal(info.api.layout,'points_goods_grid');
 assert(contained({x:0,y:0,right:width,bottom:height},info.canvas),'The archive fits the viewport');
 assert.equal(info.cards.length,109,'All 97 lottery point items and 12 configured daily items remain available');
 assert.equal(info.cards.filter(card=>card.id.startsWith('lottery_')).length,97);
 assert.equal(info.cards.filter(card=>card.id.startsWith('daily_')&&!card.unique).length,9,'Nine daily material stacks remain independent');
 assert(info.images.length&&info.images.every(image=>image.decoded),'Every visible image decodes');
 assert(info.cards.every(card=>card.images.length&&card.images.every(image=>image.decoded)),'Every grid item image decodes, including offscreen rows');
 assert.deepEqual(info.api.missingIcons,[],'No missing icon fallback');
 const uris=[...new Set(info.images.map(image=>image.src).concat(info.backgrounds))];
 assert.deepEqual(uris.filter(uri=>!uri.startsWith('data:')&&(!uri.startsWith('file:')||!fs.existsSync(fileURLToPath(uri)))),[],'All image and background files exist');
 for(const card of info.cards){
  assert(contained(card.bounds,card.name.bounds));assert(contained(card.bounds,card.status.bounds));
  assert.equal(card.name.align,'center');assert.equal(card.status.align,'center');
  assert(card.statusVisible);assert(card.status.scrollWidth<=card.status.clientWidth+1,'Status fits the full cell width');
  assert(card.status.scrollHeight<=card.status.clientHeight+1,'Status fits its line');
  if(card.unique){assert([undefined,0,1].includes(card.count));assert.equal(card.status.text,card.state===null?'状态待同步':card.state?'已解锁':'未解锁');}
  else assert.equal(card.status.text,card.sourceCount+'/999999','Daily materials preserve their actual quantity');
 }
 assert(info.calls.every(call=>['survival_archive_request','survival_vip_request','survival_daily_request'].includes(call.name)),'Only stubbed read-only UI queries occur');
}
async function main(){
 const report={at:new Date().toISOString(),kind:'isolated_points_unique_production_component_browser',notGameCapture:true,networkBlocked:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),cases:[],limitations:['Chrome emulates Panorama layout and APIs. Screenshots are isolated component previews, not native game captures.','IDs, names, caps, effects and icons use repository CSV; ownership/progress are explicit browser fixtures.','HTTP, HTTPS and WebSocket page requests are blocked. No game console, account, backend, payment, draw or reward calls.']};
 const b=await browser();
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const[width,height]of[[960,720],[1920,1080],[2560,1440]]){
   const name='points_'+width+'x'+height;
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(base+'/preview/index.html','?category=points');assert.equal(await b.run('previewReady'),true);
   const ids=await b.run(`(()=>{const formal=new Map(PREVIEW_FIXTURE.lottery.items.map(row=>[row.item_id,row]));const points=previewFixturePages.points.filter(row=>formal.get(row.id)?.item_type==='积分道具');points[2].count=7;points[3].count_known=0;for(const row of points){const source=formal.get(row.id);row.duplicate_points=Number(source.duplicate_points);row.duplicate_currency='shop_points';}emit('survival_archive_snapshot',previewSnapshot('points'));syncLayout();return {locked:points[0].id,owned:points[1].id,legacy:points[2].id,unknown:points[3].id,last:points.at(-1).id};})()`);
   await sleep(140);await b.run('syncLayout();true');
   const initial=await b.run('('+inspect.toString()+')()');validate(initial,width,height);
   assert.equal(initial.cards.find(card=>card.id===ids.legacy).count,1);
   assert.equal(initial.cards.find(card=>card.id===ids.unknown).state,null);
   fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(initial,null,2));await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});
   const entry={name,width,height,rows:initial.cards.length,uniqueLotteryItems:97,dailyMaterials:9,allImagesDecoded:true,screenshot:out+'/'+name+'.png',canvas:initial.canvas};
   await b.run('cfg.SurvivalArchive.Filter("unlocked");syncLayout();true');await sleep(70);
   const unlocked=await b.run('('+inspect.toString()+')()');assert(unlocked.cards.length&&unlocked.cards.every(card=>card.state===true));
   await b.run('cfg.SurvivalArchive.Filter("locked");syncLayout();true');await sleep(70);
   const locked=await b.run('('+inspect.toString()+')()');assert(locked.cards.length&&locked.cards.every(card=>card.state===false));
   assert(!locked.cards.some(card=>card.id===ids.unknown));
   entry.filters={unlocked:unlocked.cards.length,locked:locked.cards.length,unknownExcluded:true};
   await b.run('cfg.SurvivalArchive.Filter("all");nodes.ArchiveGrid.ScrollToTop();syncLayout();true');await sleep(90);
   const hover=await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(card=>card.visible&&card.__archiveItem?.id===${JSON.stringify(ids.owned)});const r=card.el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+40*cfg.SurvivalArchiveV10.Inspect().geometry.firstCount.width/102};})()`);
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:hover.x,y:hover.y});await sleep(170);await b.run('syncLayout();true');
   const tooltip=await b.run('('+inspect.toString()+')()');assert(tooltip.tooltip.visible,'Moving the actual pointer over a retained item opens its tooltip');
   assert.equal(tooltip.tooltip.state,'积分道具 · 已解锁');assert.equal(tooltip.tooltip.quantity,'已解锁');
   assert(tooltip.tooltip.condition.includes('唯一持有'));assert(tooltip.tooltip.condition.includes('商城积分'));
   assert(contained(tooltip.canvas,tooltip.tooltip.bounds),'Tooltip remains inside the archive');entry.tooltip=tooltip.tooltip;
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await sleep(100);
   const update=await b.run(`(()=>{const find=()=>nodes.ArchiveGrid.Children().find(card=>card.visible&&card.__archiveItem?.id===${JSON.stringify(ids.locked)});const before=find(),row=previewFixturePages.points.find(row=>row.id===${JSON.stringify(ids.locked)});row.count=1;row.unlocked=1;emit('survival_archive_snapshot',previewSnapshot('points'));syncLayout();const after=find();return {sameCard:before===after,text:after.__v10.count.text,owned:after.BHasClass('ArchiveCommerceOwned'),count:after.__archiveItem.count};})()`);
   assert.deepEqual(update,{sameCard:true,text:'已解锁',owned:true,count:1});entry.liveUnlock=update;
   await b.run('nodes.ArchiveGrid.ScrollToBottom();syncLayout();true');await sleep(100);
   const bottom=await b.run('('+inspect.toString()+')()');validate(bottom,width,height);assert(bottom.grid.scrollTop>0);
   const last=bottom.cards.find(card=>card.id===ids.last);assert(last&&contained(bottom.grid.bounds,last.bounds),'The final configured lottery item is fully reachable at the bottom');
   fs.writeFileSync(out+'/'+name+'_bottom.json',JSON.stringify(bottom,null,2));await b.shot(out+'/'+name+'_bottom.png',{x:0,y:0,width,height});
   entry.bottomScreenshot=out+'/'+name+'_bottom.png';entry.lastItem=last.id;entry.scrollTop=bottom.grid.scrollTop;
   report.cases.push(entry);console.log('POINTS_GOODS_BROWSER_PASS '+name+' rows='+initial.cards.length);
  }
  const selected=/^(scripts\/custom_game\/(archive_v10|archive_v10_semantics|reward_presentation|common\/item_resources|common\/archive_tooltip)\.js|styles\/custom_game\/archive_v10\.css)$/;
  report.changedCriticalSources=report.assembly.sourceGraph.filter(item=>selected.test(item.path)).filter(item=>crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+item.path,'utf8').replace(/^\uFEFF/,'')).digest('hex')!==item.sha256).map(item=>item.path);
  assert.deepEqual(report.changedCriticalSources,[],'Critical sources stay frozen during capture');report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureState=await b.run('('+inspect.toString()+')()');await b.shot(out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('POINTS_GOODS_BROWSER_COMPLETE '+out+'/report.json');
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
