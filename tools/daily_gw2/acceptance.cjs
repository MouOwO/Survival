'use strict';
// Browser execution of production daily XML/JS/CSS; every request stays in memory.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base='design_refs/daily_gw2_v1/work',out=base+'/browser',input=base+'/preview/index.html';
process.chdir(repo);
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function inspect(){
 const visible=element=>{if(!element)return false;const rect=element.getBoundingClientRect(),style=getComputedStyle(element);return !element.hidden&&style.display!=='none'&&style.visibility!=='hidden'&&rect.width>0&&rect.height>0;};
 const describe=panel=>panel?{id:panel.id,visible:visible(panel.el),bounds:panel.el.getBoundingClientRect().toJSON(),text:panel.text,enabled:panel.enabled,classes:panel.GetClasses()}:null;
 const canvas=nodes.DailyGW2Canvas,dayPanels=nodes.DailyCards?.Children()||[],specialPanels=nodes.DailySpecials?.Children()||[];
 const decode=async src=>{const img=new Image();img.src=src;try{await img.decode();return {src,decoded:img.naturalWidth>0,width:img.naturalWidth,height:img.naturalHeight};}catch{return {src,decoded:false};}};
 const assets=await Promise.all(Object.entries(cfg.DailyGW2Data?.assets||{}).map(async([key,asset])=>({key,...await decode(cssValue(asset.file))})));
 const images=canvas?[...canvas.el.querySelectorAll('img')].filter(visible).map(element=>({src:element.src,decoded:element.complete&&element.naturalWidth>0,bounds:element.getBoundingClientRect().toJSON()})):[];
 const layoutChain=[];for(let panel=canvas;panel;panel=panel.GetParent()){const style=getComputedStyle(panel.el);layoutChain.push({id:panel.id,bounds:panel.el.getBoundingClientRect().toJSON(),sourceStyle:panel._style,computed:{width:style.width,height:style.height,left:style.left,top:style.top,margin:style.margin,transform:style.transform,transformOrigin:style.transformOrigin,translate:style.translate}});}
 return {errors:previewErrors,api:cfg.SurvivalDaily?.Inspect(),layoutChain,canvas:describe(canvas),background:describe(nodes.DailyGW2Background),grid:describe(nodes.DailyCards),days:dayPanels.map(panel=>({...describe(panel),rewardImages:[...panel.el.querySelectorAll('img')].filter(visible).map(element=>({src:element.src,bounds:element.getBoundingClientRect().toJSON()}))})),specials:specialPanels.map(describe),assets,images,
  tooltip:describe(nodes.DailyGW2Tooltip),tooltipBody:describe(nodes.DailyGW2TooltipBody),tooltipTitle:describe(nodes.DailyGW2TooltipTitle),rules:describe(nodes.DailyRulesText),notice:describe(nodes.DailyNotice),claim:describe(nodes.DailyClaim),claimText:describe(nodes.DailyClaimText),purchase:describe(nodes.PassPurchase),purchaseText:describe(nodes.PassPurchaseText),makeup:describe(nodes.DailyMakeup),
  blueFrames:specialPanels.flatMap(panel=>panel.FindChildrenWithClassTraverse('DailyGW2SpecialFrame')).map(describe),sharedDailyViews:cfg.SurvivalMenuV10?cfg.SurvivalMenuV10.Entries().filter(view=>view.panel?.id==='DailyWindow').length:0,subscriptions:subscribers.size,calls:previewCalls};
}
function inside(inner,outer,label){assert(inner&&outer,label+' bounds exist');assert(inner.x>=outer.x-1&&inner.y>=outer.y-1&&inner.right<=outer.right+1&&inner.bottom<=outer.bottom+1,label+' remains inside its container');}
function inViewport(rect,width,height,label){assert(rect&&rect.width>0&&rect.height>0,label+' has visible geometry');inside(rect,{x:0,y:0,right:width,bottom:height},label+' at '+width+'x'+height);}
function validate(state,width,height,assetCount){
 assert.deepEqual(state.errors,[],'Production and adapter have no script errors');assert.equal(state.api?.layout,'daily_gw2');assert(state.api.open,'Independent daily window is open');assert.equal(state.sharedDailyViews,0,'Daily window does not create the old shared menu shell');
 assert(state.canvas?.visible);inViewport(state.canvas.bounds,width,height,'Daily canvas');assert.equal(state.days.length,28,'Exactly 28 free calendar cells');
 assert.equal(state.assets.length,assetCount,'Every manifest component exists in runtime data');assert(state.assets.every(asset=>asset.decoded),'All component PNGs decode');assert(state.images.every(asset=>asset.decoded),'All visible formal reward icons decode');
 const formal=require('./fixture.cjs').fixture().rewards;
 state.days.forEach((day,index)=>{assert.equal(day.id,'DailyGW2Day_'+(index+1));assert(day.visible);inside(day.bounds,state.grid.bounds,'Day '+(index+1));if(index%7)assert(day.bounds.left>=state.days[index-1].bounds.right+1,'Free reward columns do not overlap');if(index>=7)assert(day.bounds.top>=state.days[index-7].bounds.bottom+1,'Free reward rows do not overlap');if(index%7)assert(Math.abs(day.bounds.y-state.days[index-index%7].bounds.y)<1,'Seven cells share each row');for(const reward of formal[index%7].rewards)assert(day.text.includes(reward.name),'Every formal reward name remains represented on day '+(index+1));assert(day.rewardImages.length>=formal[index%7].rewards.length,'All formal reward icons appear, including multi-reward days');for(const image of day.rewardImages)inside(image.bounds,day.bounds,'Reward icon on day '+(index+1));});
 inside(state.grid.bounds,state.background.bounds,'Free calendar');if(state.notice?.visible){inside(state.notice.bounds,state.background.bounds,'Status text');const bottom=(state.notice.bounds.bottom-state.canvas.bounds.y)/(state.canvas.bounds.height/900);assert(bottom<=840.5,'Status text stays above the artwork bottom fade (logical bottom <= 840)');}
 assert.equal(state.specials.length,3,'Only the three configured one-time battle-pass rewards');state.specials.forEach(row=>{assert(row.bounds.x>state.grid.bounds.right,'Battle-pass rewards remain right of the free calendar');inside(row.bounds,state.background.bounds,'Battle-pass reward');});
 assert.equal(state.blueFrames.length,3,'Each configured battle-pass reward has its own blue frame');state.blueFrames.forEach(frame=>assert(Math.abs(frame.bounds.width-frame.bounds.height)<1,'Blue battle-pass reward frames stay square'));
 assert(!state.purchase.enabled,'Unconfigured server purchase stays disabled');
 assert(!state.calls.some(call=>/^(survival_daily_claim|survival_pass_purchase)$/.test(call.name)),'Visual checks never send a claim or purchase event');
}
async function ready(b,state='normal'){
 await b.go(input,'?state='+state);assert.equal(await b.run('previewReady'),true,'Production daily preview initializes');await b.run('document.fonts.ready.then(()=>true)');await b.run('Promise.all([...document.images].map(image=>image.decode().catch(()=>false))).then(()=>true)');await b.run('syncLayout();true');
}
async function info(b){await b.run('syncLayout();true');return b.run('('+inspect.toString()+')()');}
async function shot(b,name,width,height){const state=await info(b);await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(state,null,2));return state;}
async function main(){
 fs.mkdirSync(out,{recursive:true});const manifestBytes=fs.readFileSync('tools/daily_gw2/asset_manifest.json'),manifest=JSON.parse(manifestBytes),assetCount=Object.keys(manifest.assets).length;
 const report={at:new Date().toISOString(),kind:'daily_gw2_production_component_browser_preview',notGameCapture:true,fixtureOnly:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),assetManifestSha256:crypto.createHash('sha256').update(manifestBytes).digest('hex'),sizes:[],states:[],interactions:[],limitations:['Real production XML, JS and CSS run in a browser Panorama adapter.','Formal CSV rewards retain their existing seven-claim cycle; 28 cells display that authoritative sequence with explicitly synthetic progress.','Browser layout and font rendering approximate native Panorama. Native compilation and actual game captures are separate.','All outgoing events are local stubs; no account, reward, purchase or persistence service is connected.']};
 const b=await browser();
 try{
  for(const [width,height] of [[1280,720],[1920,1080],[2560,1440],[2560,1080],[960,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b);const state=await shot(b,'daily_'+width+'x'+height,width,height);validate(state,width,height,assetCount);assert.equal(state.api.calendarDay,3);assert.equal(state.days.filter(day=>day.classes.includes('DailyGW2Claimed')).length,2);report.sizes.push({width,height,canvas:state.canvas.bounds,grid:state.grid.bounds,days:state.days.length,decodedComponents:state.assets.length,decodedRewardIcons:state.images.length});
  }
  await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:1,mobile:false});
  for(const mode of ['pass','claimed','rollover','unavailable']){
   await ready(b,mode);const state=await shot(b,'state_'+mode,1920,1080);validate(state,1920,1080,assetCount);
   if(mode==='pass'){assert(state.api.hasPass);assert(state.makeup.visible&&state.makeup.enabled);assert.equal(state.api.calendarDay,9);assert.equal(state.specials.filter(row=>row.classes.includes('DailyGW2Locked')).length,0);}
   if(mode==='claimed'){assert.equal(state.api.calendarDay,28);assert.equal(state.days.filter(day=>day.classes.includes('DailyGW2Claimed')).length,28);assert(!state.claim.enabled);}
   if(mode==='rollover'){assert.equal(state.api.calendarDay,1);assert.equal(state.days.filter(day=>day.classes.includes('DailyGW2Claimed')).length,0);assert(state.claim.enabled);}
   if(mode==='unavailable')assert(!state.claim.enabled);
   report.states.push({mode,api:state.api,claim:state.claimText.text,purchase:state.purchaseText.text});
  }
  await ready(b);await b.run('nodes.DailyGW2Day_3.events.onmouseover();syncLayout();true');await sleep(420);
  const tooltip=await shot(b,'daily_tooltip',1920,1080);assert(tooltip.tooltip.visible,'Actual day hover opens tooltip');inViewport(tooltip.tooltip.bounds,1920,1080,'Daily tooltip');assert(tooltip.tooltipTitle.text.includes('第3天'));assert(tooltip.tooltipBody.text.includes('数量')||tooltip.tooltipBody.text.includes('×3'));report.interactions.push({kind:'day_tooltip',title:tooltip.tooltipTitle.text,bounds:tooltip.tooltip.bounds});
  await b.run('nodes.DailySpecials.Children()[0].events.onmouseover();syncLayout();true');await sleep(420);const passTooltip=await shot(b,'pass_tooltip',1920,1080);assert(passTooltip.tooltip.visible);assert(passTooltip.tooltipBody.text.includes('累计签到7次'));assert(passTooltip.tooltipBody.text.includes('购买战令后解锁'));report.interactions.push({kind:'pass_tooltip',body:passTooltip.tooltipBody.text});
  await b.run('nodes.DailyRules.events.onactivate();syncLayout();true');const rules=await info(b);assert(rules.rules.visible);assert(!rules.tooltip.visible);inViewport(rules.rules.bounds,1920,1080,'Rules popup');await b.run('nodes.DailyGW2RulesClose.events.onactivate();syncLayout();true');assert(!(await info(b)).rules.visible);
  const lifecycle=await b.run(`(()=>{const canvas=nodes.DailyGW2Canvas,first=nodes.DailyGW2Day_1,before=subscribers.size;for(let i=0;i<12;i++){nodes.DailyGW2Close.events.onactivate();if(cfg.SurvivalDaily.Inspect().open)throw Error('Window remained open');cfg.SurvivalDaily.Open(false);dailyPreviewSend();if(!cfg.SurvivalDaily.Inspect().open)throw Error('Window failed to reopen');}for(let i=0;i<30;i++)dailyPreviewSend();syncLayout();return {before,after:subscribers.size,sameCanvas:canvas===nodes.DailyGW2Canvas,sameFirstCard:first===nodes.DailyGW2Day_1,days:nodes.DailyCards.GetChildCount(),mutationEvents:previewCalls.filter(call=>/^(survival_daily_claim|survival_pass_purchase)$/.test(call.name))};})()`);
  assert.equal(lifecycle.before,lifecycle.after);assert(lifecycle.sameCanvas&&lifecycle.sameFirstCard,'Reopen and equivalent snapshots reuse calendar components');assert.equal(lifecycle.days,28);assert.deepEqual(lifecycle.mutationEvents,[]);report.interactions.push({kind:'repeated_open_close_and_snapshots',cycles:12,snapshots:30,...lifecycle});
  const final=await info(b);validate(final,1920,1080,assetCount);
  report.changedSinceSnapshot=report.assembly.sourceGraph.filter(record=>/daily_|layout\/custom_game\/archive\.xml/.test(record.path)).filter(record=>crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+record.path,'utf8').replace(/^\uFEFF/,'')).digest('hex')!==record.sha256).map(record=>record.path);assert.deepEqual(report.changedSinceSnapshot,[],'Daily source files stay frozen throughout capture');
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync('tools/daily_gw2/asset_manifest.json')).digest('hex'),report.assetManifestSha256,'Assets stay frozen throughout capture');report.status='PASS_BROWSER_DAILY_GW2';
 }catch(error){report.status='FAIL_BROWSER_DAILY_GW2';report.failure=error.stack||String(error);try{report.failureSnapshot=await info(b);await b.shot(out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('DAILY_GW2_BROWSER_PASS '+out+'/report.json');
}
module.exports={inspect,validate,inViewport,ready};
if(require.main===module){let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('DAILY_GW2_BROWSER_INCOMPLETE: Chrome/CDP exited before validation completed.');process.exitCode=1;}});main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});}
