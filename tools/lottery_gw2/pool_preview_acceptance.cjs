'use strict';
// Production UI in a local stub browser. No live draws, exchanges or purchases.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const {ready,info,validate,validateTooltip,validateRewardArt,assertFrozen,reportBase}=require('./acceptance.cjs');
const repo=path.resolve(__dirname,'../..'),out='design_refs/lottery_pool_preview_v1/final';
process.chdir(repo);
const sizes=[[960,720],[1280,720],[1600,900],[1920,1080],[2560,1440]],pools=['map','cultivation','dragon_knight','summer'];
const counts={map:{n:10,r:5,sr:5,ssr:10},cultivation:{r:5,sr:5,ssr:9,ur:7},dragon_knight:{r:5,sr:5,ssr:10,ur:6},summer:{r:5,sr:5,ssr:8,ur:5}};
function prizeInspect(){
 const host=nodes.LotteryInfoList,api=cfg.SurvivalPurpleLottery.Inspect();
 const cards=host.Children().filter(panel=>panel.BHasClass('LotteryDetailRow')),bars=host.Children().filter(panel=>panel.BHasClass('LotteryGW2PrizeBar'));
 const quality=item=>{const q=String(item?.quality||'').toLowerCase();return ['n','r','sr','ssr','ur'].includes(q)?q:'unknown';};
 const describe=card=>({id:card.__lotteryItem?.id,quality:quality(card.__lotteryItem),visible:card.visible,selected:card.BHasClass('Selected'),quantity:card.__lotteryPrizeFace?.count?.text,unowned:card.BHasClass('LotteryGW2PrizeUnowned'),bounds:card.el.getBoundingClientRect().toJSON()});
 return {api,groups:api.prizeGroups.map((meta,index)=>({...meta,title:bars[index]?.text||'',cards:cards.filter(card=>quality(card.__lotteryItem)===meta.id).map(describe)})),cards:cards.map(describe),rules:nodes.LotteryInfoRules.text,selectedName:nodes.LotterySelectedName.text,hostText:host.text,scroll:{height:host.el.scrollHeight,client:host.el.clientHeight,top:host.el.scrollTop},calls:previewCalls,errors:previewErrors,
  tooltipScroll:{height:nodes.LotteryGW2TooltipScroll.el.scrollHeight,client:nodes.LotteryGW2TooltipScroll.el.clientHeight,overflow:getComputedStyle(nodes.LotteryGW2TooltipScroll.el).overflowY}};
}
async function prizes(b){await b.run('syncLayout();true');return b.run('('+prizeInspect.toString()+')()');}
function safety(state){assert.deepEqual(state.errors,[]);assert(!state.calls.some(call=>/ui_lottery_(draw|exchange)_request|survival_payment|survival_commerce/.test(call.name||'')),'All browser requests stay read-only and stubbed');}
function validatePage(state,width,height,assetCount){
 // Details intentionally collapse the main draw content; validate the actual
 // visible details viewport with the existing geometry/assets/safety validator.
 assert(state.detailHost?.visible,'The active details viewport is visible');
 validate({...state,content:state.detailHost},width,height,assetCount);
}
function groupsValid(state,pool){
 safety(state);assert.equal(state.api.mode,'details');
 assert.deepEqual(Object.fromEntries(state.groups.map(group=>[group.id,group.count])),counts[pool],'Every real member appears in the right quality group: '+pool);
 assert.equal(state.cards.length,Object.values(counts[pool]).reduce((a,b)=>a+b,0));
 for(const group of state.groups){assert.equal(group.cards.length,group.count);assert(group.title.includes(String(group.count)+' 种奖励'),'Group heading retains its real member count');}
 if(pool==='map')assert.deepEqual(Object.fromEntries(state.groups.map(group=>[group.id,group.percent])),{n:69.5,r:25,sr:4,ssr:1.5},'Only formally published map percentages appear');
 else for(const group of state.groups){assert(!Object.hasOwn(group,'percent'));assert(!group.title.includes('%'),'Another pool never inherits map odds');assert(group.title.includes('未公布'));}
 assert.match(state.rules,pool==='map'||pool==='cultivation'?/十连保底 SSR/:/十连保底 UR/);assert.match(state.rules,/连续十次单抽不触发/);assert(!state.rules.includes('%'));
}
async function dimensions(b,width,height){await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});}
async function settle(b){await b.run('Promise.all([...document.images].map(image=>image.decode().catch(()=>false))).then(()=>true)');await b.run('syncLayout();true');}
async function point(b,expression){
 const at=await b.run(`(()=>{const panel=${expression};if(!panel||!panel.IsValid())throw Error('Missing actual control');panel.el.scrollIntoView({block:'center',inline:'nearest'});syncLayout();const r=panel.el.getBoundingClientRect(),x=r.x+r.width/2,y=r.y+r.height/2,front=document.elementFromPoint(x,y);return {x,y,hit:!!front&&panel.el.contains(front),bounds:r.toJSON()};})()`);
 assert(at.hit,'Actual browser pointer reaches the intended production control');return at;
}
async function click(b,expression){const at=await point(b,expression);await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:at.x,y:at.y});await b.call('Input.dispatchMouseEvent',{type:'mousePressed',x:at.x,y:at.y,button:'left',clickCount:1});await b.call('Input.dispatchMouseEvent',{type:'mouseReleased',x:at.x,y:at.y,button:'left',clickCount:1});await sleep(45);await b.run('syncLayout();true');return at;}
function bar(index){return 'nodes.LotteryInfoList.Children().filter(panel=>panel.BHasClass("LotteryGW2PrizeBar"))['+index+']';}
function card(index){return 'nodes.LotteryInfoList.Children().filter(panel=>panel.BHasClass("LotteryDetailRow"))['+index+']';}
async function hover(b,expression){const at=await point(b,expression);await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:at.x,y:at.y});await sleep(150);await b.run('syncLayout();true');return at;}
async function screen(b,report,name,width,height,state){await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(state,null,2));report.screens.push({name,width,height,file:name+'.png'});}
async function main(){
 fs.mkdirSync(out,{recursive:true});
 if(fs.existsSync(out+'/report.json')){const prior=JSON.parse(fs.readFileSync(out+'/report.json','utf8'));if(prior.status?.startsWith('FAIL')){const tag=Date.now();fs.copyFileSync(out+'/report.json',out+'/failed_attempt_'+tag+'.json');if(fs.existsSync(out+'/failure.png'))fs.copyFileSync(out+'/failure.png',out+'/failed_attempt_'+tag+'.png');}}
 const report=reportBase('lottery_pool_preview_group_browser_acceptance');report.input='design_refs/lottery_gw2_v1/work/preview/index.html';report.forbiddenRequests='draw/exchange/payment/commerce';report.sizes=sizes;let b;
 try{
  assertFrozen(report);b=await browser();
  for(const [width,height]of sizes)for(const pool of pools){
   await dimensions(b,width,height);await ready(b,pool,'details');await settle(b);
   const state=await info(b),groupState=await prizes(b);validatePage(state,width,height,report.assetCount);validateRewardArt(state.details);groupsValid(groupState,pool);
   for(const row of state.details){assert(row.bounds.x>=state.detailHost.bounds.x-1&&row.bounds.right<=state.detailHost.bounds.right+1,'Compact reward grid stays inside the content width');}
   await screen(b,report,pool+'_details_'+width+'x'+height,width,height,{production:state,groups:groupState});
  }
  console.log('POOL_PREVIEW_GEOMETRY_PASS: all four real pools at five resolutions');
  await dimensions(b,1920,1080);
  for(const pool of pools){
   await ready(b,pool,'details');const initial=await prizes(b);groupsValid(initial,pool);
   for(let index=0;index<initial.groups.length;index++){
    const ids=initial.groups[index].cards.map(row=>row.id);
    await click(b,bar(index));let folded=await prizes(b);safety(folded);assert(folded.groups[index].collapsed);assert(folded.groups[index].cards.every(row=>row.visible===false),'Collapsed groups hide every original business card');
    await click(b,bar(index));const reopened=await prizes(b);safety(reopened);assert(!reopened.groups[index].collapsed);assert(reopened.groups[index].cards.every(row=>row.visible===true),'Expanding restores the original cards');assert.deepEqual(reopened.groups[index].cards.map(row=>row.id),ids);
    report.checks.push({kind:'fold_unfold',pool,group:initial.groups[index].id,rows:ids.length,realPointer:true});
   }
   await click(b,card(0));const selected=await prizes(b);assert(selected.cards[0].selected,'Actual onactivate still invokes original SelectReward');assert.equal(selected.selectedName,(await info(b)).details[0].item.name);safety(selected);
   report.checks.push({kind:'original_select_reward',pool,item:selected.cards[0].id});
  }
  await ready(b,'map','details');let state=await prizes(b),rIndex=state.groups.findIndex(group=>group.id==='r');await click(b,bar(rIndex));assert((await prizes(b)).groups[rIndex].collapsed);
  await b.run('lotteryPreviewSelect("cultivation")');state=await prizes(b);groupsValid(state,'cultivation');assert(state.groups.every(group=>!group.collapsed),'Map folding does not fold another pool');
  await b.run('lotteryPreviewSelect("map")');state=await prizes(b);groupsValid(state,'map');rIndex=state.groups.findIndex(group=>group.id==='r');assert(state.groups[rIndex].collapsed,'Map retains only its own folded group');await click(b,bar(rIndex));
  report.checks.push({kind:'cross_pool_fold_isolation',from:'map',to:'cultivation',quality:'r'});
  // A fresh uncached pool preserves loading, rejects a stale reply, then uses the matching reply.
  await ready(b,'map','details');await b.run('cfg.SurvivalLottery.SelectPool("summer");syncLayout();true');state=await prizes(b);assert.equal(state.cards.length,0);assert.match(state.hostText,/正在读取奖池/);assert(!state.groups.length);
  await b.run(`(()=>{const request=previewCalls.findLast(call=>call.name==='ui_lottery_snapshot_request'&&call.payload.snapshot_scope==='details');lotteryPreviewSend('map','details',request.payload.snapshot_request_id-1);return true;})()`);assert.equal((await prizes(b)).cards.length,0,'A late wrong-pool reply does not expose stale cards or odds');
  await b.run('lotteryPreviewFlushDetails();syncLayout();true');groupsValid(await prizes(b),'summer');report.checks.push({kind:'uncached_loading_and_late_reply',staleRejected:true});
  await ready(b,'map','unknown');state=await prizes(b);groupsValid(state,'map');assert(state.cards.every(row=>row.quantity==='—'&&!row.unowned),'Unknown ownership does not become zero or an unowned state');await screen(b,report,'map_unknown_1920x1080',1920,1080,{production:await info(b),groups:state});
  await b.run(`(()=>{const snapshot=lotteryPreviewSnapshot('map');snapshot.items[0].quality='new_server_quality';emit('ui_lottery_snapshot',snapshot);syncLayout();return true;})()`);state=await prizes(b);assert.equal(state.cards.length,30);assert.equal(state.groups.at(-1).id,'unknown');assert.equal(state.groups.at(-1).count,1,'Unknown quality stays visible at the end');safety(state);report.checks.push({kind:'unknown_ownership_and_quality',items:30,unknownItems:1});
  await ready(b,'map','empty');state=await prizes(b);assert.equal(state.cards.length,0);assert.equal(state.groups.length,0);assert.match(state.hostText,/当前奖池暂无奖励/);safety(state);await screen(b,report,'map_empty_1920x1080',1920,1080,{production:await info(b),groups:state});report.checks.push({kind:'empty_no_stale_group_or_odds'});
  for(const [width,height]of [[960,720],[2560,1440]]){
   await dimensions(b,width,height);await ready(b,'map','details');await hover(b,card(0));let production=await info(b);validatePage(production,width,height,report.assetCount);validateTooltip(production,width,height);await screen(b,report,'map_tooltip_'+width+'x'+height,width,height,production);report.checks.push({kind:'tooltip',width,height,bounds:production.tooltip.bounds});
   await ready(b,'map','long');const longIndex=await b.run('nodes.LotteryInfoList.Children().filter(panel=>panel.BHasClass("LotteryDetailRow")).findIndex(panel=>panel.__lotteryItem.description.length>1000)');assert(longIndex>=0);await hover(b,card(longIndex));production=await info(b);validatePage(production,width,height,report.assetCount);validateTooltip(production,width,height);assert(production.tooltipDescription.text.length>1000,'Long authoritative effects are not truncated');const detail=await prizes(b);assert(detail.tooltipScroll.height>detail.tooltipScroll.client,'Long effects retain a bounded scrolling viewport');assert(/auto|scroll/.test(detail.tooltipScroll.overflow));await screen(b,report,'map_long_tooltip_'+width+'x'+height,width,height,{production,groups:detail});report.checks.push({kind:'long_tooltip',width,height,length:production.tooltipDescription.text.length,scroll:detail.tooltipScroll});
  }
  await dimensions(b,1920,1080);await ready(b,'map','details');const lifecycle=await b.run(`(()=>{const before=cfg.SurvivalPurpleLottery.Inspect(),listeners=subscribers.size;for(let index=0;index<8;index++)cfg.SurvivalLottery.Feature('details');syncLayout();const after=cfg.SurvivalPurpleLottery.Inspect();return {listeners,afterListeners:subscribers.size,before,after};})()`);assert.equal(lifecycle.listeners,lifecycle.afterListeners);assert(lifecycle.after.trackedOwned<=lifecycle.before.trackedOwned,'Deleted group decorations do not accumulate');assert(lifecycle.after.trackedMoved<=lifecycle.before.trackedMoved,'Moved reward icons are pruned');groupsValid(await prizes(b),'map');report.checks.push({kind:'rebuild_lifecycle',cycles:8,...lifecycle});
  assertFrozen(report);report.status='PASS_BROWSER_LOTTERY_POOL_PREVIEW';
 }catch(error){report.status='FAIL_BROWSER_LOTTERY_POOL_PREVIEW';report.failure=error.stack||String(error);if(b)try{report.failureSnapshot=await info(b);report.failureGroups=await prizes(b);await b.shot(out+'/failure.png');}catch{}throw error;
 }finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));if(b)b.close();}
 console.log('LOTTERY_POOL_PREVIEW_BROWSER_PASS '+out+'/report.json');
}
module.exports={prizeInspect,groupsValid,safety,main};
if(require.main===module){let done=false;process.on('beforeExit',()=>{if(!done){console.error('LOTTERY_POOL_PREVIEW_BROWSER_INCOMPLETE');process.exitCode=1;}});main().then(()=>{done=true;},error=>{done=true;console.error(error.stack||error);process.exitCode=1;});}
