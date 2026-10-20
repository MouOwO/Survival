'use strict';
// Read-only production-component preview. All state changes below are local fixtures.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {fileURLToPath}=require('node:url');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base='design_refs/points_daily_unique_20261019',out=base+'/browser';
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
function inspect(){
 const bounds=el=>el.getBoundingClientRect().toJSON();
 const shown=el=>{for(let node=el;node;node=node.parentElement){const style=getComputedStyle(node);if(node.hidden||style.display==='none'||style.visibility==='hidden')return false;}const r=el.getBoundingClientRect();return r.width>0&&r.height>0;};
 const image=el=>({src:el.currentSrc||el.src,decoded:el.complete&&el.naturalWidth>0,width:el.naturalWidth,height:el.naturalHeight,bounds:bounds(el)});
 const label=node=>({text:node.text,bounds:bounds(node.el),align:getComputedStyle(node.el).textAlign,scrollWidth:node.el.scrollWidth,clientWidth:node.el.clientWidth,scrollHeight:node.el.scrollHeight,clientHeight:node.el.clientHeight});
 const canvas=nodes.ArchiveV10Canvas,grid=nodes.ArchiveGrid;
 const cards=grid.Children().filter(card=>card.visible&&card.__v10).map(card=>({id:card.__archiveItem.id,sourceCount:previewFixturePages.points.find(row=>row.id===card.__archiveItem.id)?.count,sourceTarget:previewFixturePages.points.find(row=>row.id===card.__archiveItem.id)?.target,count:card.__archiveItem.count,target:card.__archiveItem.target,maxOwned:card.__archiveItem.max_owned,state:cfg.ArchiveV10Semantics.State(card.__archiveItem,'points'),unique:cfg.ArchiveV10Semantics.IsUnlockItem(card.__archiveItem,'points'),bounds:bounds(card.el),name:label(card.__v10.name),status:label(card.__v10.count),statusVisible:shown(card.__v10.count.el),images:[...card.el.querySelectorAll('img')].filter(shown).map(image)}));
 const backgrounds=[...new Set([...canvas.el.querySelectorAll('*'),canvas.el].filter(shown).flatMap(el=>[...getComputedStyle(el).backgroundImage.matchAll(/url\(["']?([^"')]+)["']?\)/g)].map(match=>match[1])))];
 const background=getComputedStyle(nodes.ArchiveV10Shell_Background.el),header=getComputedStyle(nodes.ArchiveV10Shell_Header.el);
 return {ready:previewState.ready,errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),canvas:bounds(canvas.el),grid:{bounds:bounds(grid.el),scrollTop:grid.el.scrollTop,clientHeight:grid.el.clientHeight,scrollHeight:grid.el.scrollHeight},images:[...canvas.el.querySelectorAll('img')].filter(shown).map(image),cards,backgrounds,skin:{background:background.backgroundImage,mask:background.maskImage,headerMask:header.maskImage},calls:previewCalls,tooltip:{visible:nodes.ArchiveV10Tooltip.visible,title:nodes.ArchiveV10TooltipTitle.text,state:nodes.ArchiveV10TooltipState.text,quantity:nodes.ArchiveV10TooltipQuantity.text,effect:nodes.ArchiveV10TooltipEffect.text,condition:nodes.ArchiveV10TooltipCondition.text,bounds:bounds(nodes.ArchiveV10Tooltip.el)}};
}
function contained(parent,child){return child.x>=parent.x-1&&child.y>=parent.y-1&&child.right<=parent.right+1&&child.bottom<=parent.bottom+1;}
function validate(info,width,height){
 assert(info.ready);assert.deepEqual(info.errors,[],'The production UI has no script errors');
 assert.equal(info.api.category,'points');assert.equal(info.api.layout,'points_goods_grid');
 assert(contained({x:0,y:0,right:width,bottom:height},info.canvas),'The archive fits the viewport');
 assert.equal(info.cards.length,109,'All 97 lottery point items and 12 configured daily items remain available');
 assert.equal(info.cards.filter(card=>card.id.startsWith('lottery_')).length,97);
 assert.equal(info.cards.filter(card=>card.id.startsWith('daily_')&&card.unique).length,12,'All twelve daily entries are unique unlocks');
 assert(info.images.length&&info.images.every(image=>image.decoded),'Every visible image decodes');
 assert(info.cards.every(card=>card.images.length&&card.images.every(image=>image.decoded)),'Every grid item image decodes, including offscreen rows');
 assert.deepEqual(info.api.missingIcons,[],'No missing icon fallback');
 assert(info.skin.background.includes('archive_user_skin_v1/background.png'),'The current user-selected background is transported unchanged');
 assert(info.skin.mask.includes('data:image/svg+xml;base64,'),'Exact source alpha-mask bytes are available without Chrome file mask restrictions');
 assert(info.skin.headerMask.includes('data:image/svg+xml;base64,'));
 const uris=[...new Set(info.images.map(image=>image.src).concat(info.backgrounds))];
 assert.deepEqual(uris.filter(uri=>!uri.startsWith('data:')&&(!uri.startsWith('file:')||!fs.existsSync(fileURLToPath(uri)))),[],'All image and background files exist');
 for(const card of info.cards){
  assert(contained(card.bounds,card.name.bounds));assert(contained(card.bounds,card.status.bounds));
  assert.equal(card.name.align,'center');assert.equal(card.status.align,'center');
  assert(card.statusVisible);assert(card.status.scrollWidth<=card.status.clientWidth+1,'Status fits the full cell width');
  assert(card.status.scrollHeight<=card.status.clientHeight+1,'Status fits its line');
  assert(card.unique,'Every points entry uses the same unique ownership rule');
  assert([undefined,0,1].includes(card.count));assert.equal(card.target,1);assert.equal(card.maxOwned,1);
  assert.equal(card.status.text,card.state===null?'状态待同步':card.state?'已解锁':'未解锁');
  assert(!/\d\s*\/\s*\d|999999/.test(card.status.text),'No count ratio or legacy cap appears on any points card');
 }
 assert(info.calls.every(call=>['survival_archive_request','survival_vip_request','survival_daily_request'].includes(call.name)),'Only stubbed read-only UI queries occur');
}
async function main(){
 const report={at:new Date().toISOString(),kind:'isolated_points_unique_production_component_browser',notGameCapture:true,networkBlocked:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),cases:[],limitations:['Chrome emulates Panorama layout and APIs. Screenshots are isolated component previews, not native game captures.','IDs, names, caps, effects and icons use repository CSV; ownership/progress are explicit browser fixtures.','HTTP, HTTPS and WebSocket page requests are blocked. No game console, account, backend, payment, draw or reward calls.']};
 report.status='STARTING';fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));
 console.log('POINTS_GOODS_BROWSER_START '+report.at);
 const b=await browser();
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const[width,height]of[[960,720],[1920,1080],[2560,1440]]){
   const name='points_'+width+'x'+height;
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(base+'/preview/index.html','?category=points');assert.equal(await b.run('previewReady'),true);
   const ids=await b.run(`(()=>{const formal=new Map(PREVIEW_FIXTURE.lottery.items.map(row=>[row.item_id,row]));const points=previewFixturePages.points.filter(row=>formal.get(row.id)?.item_type==='积分道具');points[2].count=7;points[3].count_known=0;for(const row of points){const source=formal.get(row.id);row.duplicate_points=Number(source.duplicate_points);row.duplicate_currency='shop_points';}const growth=previewFixturePages.points.find(row=>row.id==='daily_growth_gem'),dailyLocked=previewFixturePages.points.find(row=>row.id==='daily_health_gem'),dailyUnknown=previewFixturePages.points.find(row=>row.id==='daily_regen_shard');Object.assign(growth,{count:3,count_known:1,target:999999,max_owned:999999});Object.assign(dailyLocked,{count:0,count_known:1,target:999999,max_owned:999999});Object.assign(dailyUnknown,{count:9,count_known:0,target:999999,max_owned:999999});emit('survival_archive_snapshot',previewSnapshot('points'));syncLayout();return {locked:points[0].id,owned:points[1].id,legacy:points[2].id,unknown:points[3].id,dailyOwned:growth.id,dailyLocked:dailyLocked.id,dailyUnknown:dailyUnknown.id,last:points.at(-1).id};})()`);
   await sleep(140);await b.run('syncLayout();true');
   const initial=await b.run('('+inspect.toString()+')()');validate(initial,width,height);
   const backgroundDecode=await b.run(`Promise.all(${JSON.stringify(initial.backgrounds)}.map(async src=>{const image=new Image();image.src=src;try{await image.decode();return {src,decoded:true,width:image.naturalWidth,height:image.naturalHeight};}catch{return {src,decoded:false};}}))`);
   assert(backgroundDecode.every(image=>image.decoded),'All backgrounds, including the current skin, decode');
   assert.equal(initial.cards.find(card=>card.id===ids.legacy).count,1);
   assert.equal(initial.cards.find(card=>card.id===ids.unknown).state,null);
   const growth=initial.cards.find(card=>card.id===ids.dailyOwned);
   assert.equal(growth.sourceCount,3);assert.equal(growth.sourceTarget,999999);assert.equal(growth.count,1);assert.equal(growth.status.text,'已解锁');
   assert.equal(initial.cards.find(card=>card.id===ids.dailyUnknown).state,null);
   fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(initial,null,2));await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});
   const entry={name,width,height,rows:initial.cards.length,uniqueLotteryItems:97,uniqueDailyItems:12,allImagesDecoded:true,backgroundDecode,screenshot:out+'/'+name+'.png',canvas:initial.canvas,screenshotRegression:{id:growth.id,rawCount:growth.sourceCount,rawTarget:growth.sourceTarget,viewCount:growth.count,text:growth.status.text}};
   await b.run('cfg.SurvivalArchive.Filter("unlocked");syncLayout();true');await sleep(70);
   const unlocked=await b.run('('+inspect.toString()+')()');assert(unlocked.cards.length&&unlocked.cards.every(card=>card.state===true));
   await b.run('cfg.SurvivalArchive.Filter("locked");syncLayout();true');await sleep(70);
   const locked=await b.run('('+inspect.toString()+')()');assert(locked.cards.length&&locked.cards.every(card=>card.state===false));
   assert(!locked.cards.some(card=>card.id===ids.unknown));
   assert(!locked.cards.some(card=>card.id===ids.dailyUnknown));
   entry.filters={unlocked:unlocked.cards.length,locked:locked.cards.length,unknownExcluded:true};
   await b.run('cfg.SurvivalArchive.Filter("all");nodes.ArchiveGrid.ScrollToTop();syncLayout();true');await sleep(90);
   const hover=await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(card=>card.visible&&card.__archiveItem?.id===${JSON.stringify(ids.dailyOwned)});const r=card.el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+40*cfg.SurvivalArchiveV10.Inspect().geometry.firstCount.width/102};})()`);
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:hover.x,y:hover.y});await sleep(170);await b.run('syncLayout();true');
   const tooltip=await b.run('('+inspect.toString()+')()');assert(tooltip.tooltip.visible,'Moving the actual pointer over a retained item opens its tooltip');
   assert.equal(tooltip.tooltip.state,'积分道具 · 已解锁');assert.equal(tooltip.tooltip.quantity,'已解锁');
   assert.equal(tooltip.tooltip.title,'成长宝石');assert(tooltip.tooltip.condition.includes('唯一持有'));
   assert(!/999999|3\s*\/\s*999999/.test(Object.values(tooltip.tooltip).filter(value=>typeof value==='string').join('\n')),'The actual growth-gem hover has no stack count or legacy cap');
   assert(contained(tooltip.canvas,tooltip.tooltip.bounds),'Tooltip remains inside the archive');entry.tooltip=tooltip.tooltip;
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await sleep(100);
   const update=await b.run(`(()=>{const find=id=>nodes.ArchiveGrid.Children().find(card=>card.visible&&card.__archiveItem?.id===id),read=card=>({text:card.__v10.count.text,owned:card.BHasClass('ArchiveCommerceOwned'),count:card.__archiveItem.count});const lotteryId=${JSON.stringify(ids.locked)},dailyId=${JSON.stringify(ids.dailyLocked)},growthId=${JSON.stringify(ids.dailyOwned)};const before=find(lotteryId),dailyBefore=find(dailyId),growthBefore=find(growthId);for(const row of previewFixturePages.points){if([lotteryId,dailyId].includes(row.id)){row.count=1;row.unlocked=1;}if(row.id===growthId)row.count=9;}emit('survival_archive_snapshot',previewSnapshot('points'));syncLayout();const after=find(lotteryId),dailyAfter=find(dailyId),growthAfter=find(growthId);return {lottery:{sameCard:before===after,...read(after)},daily:{sameCard:dailyBefore===dailyAfter,...read(dailyAfter)},growth:{sameCard:growthBefore===growthAfter,...read(growthAfter)}};})()`);
   for(const item of Object.values(update))assert.deepEqual(item,{sameCard:true,text:'已解锁',owned:true,count:1});entry.liveUnlock=update;
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
// Keep the CDP WebSocket alive on Node builds that otherwise exit while awaiting
// an unreferenced connection. A fresh STARTING report must never resemble a pass.
const keepAlive=setInterval(()=>{},1000);
const deadline=setTimeout(()=>{console.error('POINTS_GOODS_BROWSER_TIMEOUT');process.exit(1);},90000);
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;}).finally(()=>{clearInterval(keepAlive);clearTimeout(deadline);});
