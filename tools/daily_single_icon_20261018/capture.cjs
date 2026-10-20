'use strict';
// Actual source + authoritative CSV fixture. No game/account, claims or payment.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('./browser.cjs');
const repo=path.resolve(__dirname,'../..'),base='output/daily_single_icon_20261018',out=base+'/visual_preview';
process.chdir(repo);
const sha=raw=>crypto.createHash('sha256').update(raw).digest('hex');
const assembly=JSON.parse(fs.readFileSync(out+'/assembly.json','utf8'));
const fixture=JSON.parse(fs.readFileSync(out+'/daily_fixture.json','utf8'));
const frozen=assembly.sourceGraph.filter(row=>/(?:common\/item_resources\.js|reward_presentation\.js|item_art_remaining_5d5c1152eb\.js|daily_remaining_5d5c1152eb\.js|daily_gw2\.css|common\/archive_tooltip\.(?:js|css)|layout\/custom_game\/archive\.xml)$/.test(row.path));
function verifyFrozen(){
 for(const row of frozen)assert.equal(sha(fs.readFileSync('panorama/src/'+row.path,'utf8').replace(/^\uFEFF/,'')),row.sha256,'Frozen source: '+row.path);
 assert.equal(sha(fs.readFileSync(assembly.dailyNativeResources.source)),assembly.dailyNativeResources.sha256,'Frozen reward registry');
 assert.equal(sha(fs.readFileSync(assembly.previewNativeAliases.nativeManifest)),assembly.previewNativeAliases.nativeManifestSha256,'Frozen native manifest');
 for(const row of assembly.previewNativeAliases.added)assert.equal(sha(fs.readFileSync(row.file)),row.sha256,'Exact original preview PNG: '+row.file);
}
function inspect(){
 const shown=node=>!!node&&node.visible&&getComputedStyle(node.el).display!=='none'&&node.el.getBoundingClientRect().width>0;
 const describe=node=>({id:node.id,visible:shown(node),bounds:node.el.getBoundingClientRect().toJSON(),classes:node.GetClasses(),hittest:node.hittest});
 const canvas=nodes.DailyGW2Canvas,resources=cfg.SurvivalItemResources;
 const backgrounds=[],stack=[canvas];while(stack.length){const node=stack.pop();stack.push(...node.Children());if(node.el.dataset.dailyNativeResolvedBackground)backgrounds.push({uri:node.el.dataset.dailyNativeResolvedBackground,image:getComputedStyle(node.el).backgroundImage});}
 const icons=canvas.FindChildrenWithClassTraverse('DailyGW2ItemArt').map(node=>{
  const resource=resources.Lookup(node.__itemResourceId),style=getComputedStyle(node.el);
  return {...describe(node),resourceId:node.__itemResourceId,uri:resource?.uri,fit:resource?.fit||'cover',appliedFit:node.__survivalItemFill,
   authoredWidth:parseFloat(node.style.width),authoredHeight:parseFloat(node.style.height),
   image:node.el.currentSrc||node.el.src,complete:node.el.complete,naturalWidth:node.el.naturalWidth,naturalHeight:node.el.naturalHeight,
   objectFit:style.objectFit,filter:style.filter,saturation:Number(style.getPropertyValue('--pano-saturation').trim()||1),
   brightness:Number(style.getPropertyValue('--pano-brightness').trim()||1),browserWash:node.el.dataset.dailyNativePreviewWash};
 });
 const cards=nodes.DailyCards.Children().map(card=>({...describe(card),tooltip:card.__dailyGW2Tooltip,
  slots:card.FindChildrenWithClassTraverse('DailyGW2Reward').map(node=>({...describe(node),width:parseFloat(node.style.width),height:parseFloat(node.style.height)})),
  icons:card.FindChildrenWithClassTraverse('DailyGW2ItemArt').map(node=>({id:node.__itemResourceId,width:parseFloat(node.style.width),height:parseFloat(node.style.height)})),
  quantities:card.FindChildrenWithClassTraverse('DailyGW2Quantity').map(node=>node.text),
  kinds:card.FindChildrenWithClassTraverse('DailyGW2RewardKinds').map(node=>({text:node.text,fontSize:node.style.fontSize,height:node.style.height}))}));
 const host=canvas.FindChildrenWithClassTraverse('ArchiveSharedTooltipHost').find(shown),prefix=host?.id;
 const tip=prefix?{...describe(host),title:nodes[prefix+'Title']?.text,effect:nodes[prefix+'Effect']?.text,
  body:nodes[prefix+'Body']?.text,surface:describe(nodes[prefix+'Surface'])}:null;
 return {ready:previewState.ready,errors:previewErrors,api:cfg.SurvivalDaily.Inspect(),window:describe(nodes.DailyWindow),canvas:describe(canvas),
  cards,specials:nodes.DailySpecials.Children().map(describe),icons,tip,calls:previewCalls,
  transactionalCalls:previewCalls.filter(call=>/claim|purchase|checkout|draw/.test(call.name)||['create','purchase','checkout','claim','draw'].includes(call.payload?.action)),
  backgrounds,registryHash:resources.sourceHash,caption:document.getElementById('PreviewCaption').textContent};
}
const stateOf=b=>b.run('('+inspect.toString()+')()');
function inViewport(rect,width,height,name){assert(rect.x>=-1&&rect.y>=-1&&rect.right<=width+1&&rect.bottom<=height+1,name+' stays in viewport: '+JSON.stringify(rect));}
function cropRect(rect,width,height,pad=6){const x=Math.max(0,Math.floor(rect.x-pad)),y=Math.max(0,Math.floor(rect.y-pad));return {x,y,width:Math.min(width-x,Math.ceil(rect.right+pad)-x),height:Math.min(height-y,Math.ceil(rect.bottom+pad)-y)};}
function checkNormal(state,width,height){
 assert.equal(state.ready,true);assert.deepEqual(state.errors,[]);assert.equal(state.cards.length,28);assert.equal(state.specials.length,3);
 assert.equal(state.icons.length,31,'Exactly one image in each of the 28 day cells and three monthly cells');
 assert.equal(state.registryHash,assembly.dailyNativeResources.sha256);assert.deepEqual(state.transactionalCalls,[],'No claim, purchase or draw');
 assert(state.backgrounds.some(asset=>asset.uri.includes('window_background_v10.vtex')),'Original window art retained');
 assert(state.backgrounds.some(asset=>asset.uri.includes('button_v10.vtex')),'Original button art retained');
 assert(state.backgrounds.every(asset=>asset.image.includes('file:')),'Real texture aliases resolve');
 inViewport(state.canvas.bounds,width,height,'Daily window');
 for(const special of state.specials){assert(special.visible);inViewport(special.bounds,width,height,special.id);}
 const expected=new Map(assembly.dailyNativeResources.items.map(row=>[row.id,row]));
 const displayed=new Set([...fixture.rewards.map(day=>day.rewards[0].id),...fixture.specials.map(item=>item.id)]);
 assert.deepEqual([...new Set(state.icons.map(icon=>icon.resourceId))].sort(),[...displayed].sort(),'Primary daily and all monthly identities are rendered');
 for(const [index,card]of state.cards.entries()){
  const rewards=fixture.rewards[index%7].rewards;
  assert.equal(card.slots.length,1,'One full slot in day '+(index+1));assert.equal(card.icons.length,1,'One image in day '+(index+1));
  assert.deepEqual([card.slots[0].width,card.slots[0].height],[114,115],'Full-width slot, no half-image composition');
  assert.equal(card.slots[0].hittest,false,'Image defers tooltip hover to full day card');
  assert.equal(card.icons[0].id,rewards[0].id,'Uses a real primary reward');
  assert.deepEqual(card.quantities,[String(rewards[0].count)],'Primary image carries its own true count');
  assert.deepEqual(card.kinds.map(kind=>kind.text),rewards.length>1?[rewards.length+'种']:[],'Multiple reward kinds remain visible');
  if(rewards.length>1){assert.equal(card.kinds[0].fontSize,'18px');assert.equal(card.kinds[0].height,'27px');}
  for(const reward of rewards){assert(card.tooltip.body.includes(reward.name),'Tooltip retains '+reward.name);assert(card.tooltip.body.includes(String(reward.count)),'Tooltip retains true count');assert(card.tooltip.body.includes(reward.description),'Tooltip retains effect');}
  inViewport(card.bounds,width,height,card.id);
 }
 for(const icon of state.icons){
  const resource=expected.get(icon.resourceId);assert(resource);assert(icon.visible);assert(icon.complete&&icon.naturalWidth>0,'Original native PNG decoded');
  assert.equal(icon.uri,resource.uri);assert.equal(icon.naturalWidth,resource.sourceSize[0]);assert.equal(icon.naturalHeight,resource.sourceSize[1]);
  assert.equal(icon.appliedFit,'cover','Retains the established full-square cover style');assert.equal(icon.objectFit,'cover');
  assert.deepEqual([icon.authoredWidth,icon.authoredHeight],[114,115]);assert(icon.saturation<1);
  assert.equal(icon.browserWash,assembly.dailyWashBrowserApproximation.washColor);assert(icon.filter.includes('DailyNativePreviewWash'));
  inViewport(icon.bounds,width,height,icon.resourceId);
 }
}
async function hoverDay(b,day,width,height){
 const point=await b.run('(()=>{const r=nodes.DailyGW2Day_'+day+'.el.getBoundingClientRect(),p=[r.x+r.width/2,r.y+r.height/2];GameUI.GetCursorPosition=()=>p;return {x:p[0],y:p[1]};})()');
 await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...point});await sleep(240);await b.run('syncLayout();true');
 const state=await stateOf(b);assert(state.tip?.visible,'Real mouse hover displays the day tooltip');assert(state.tip.title.includes('第'+day+'天'));
 inViewport(state.tip.surface.bounds,width,height,'Complete daily reward tooltip');assert.deepEqual(state.errors,[]);assert.deepEqual(state.transactionalCalls,[]);
 return state;
}
async function main(){
 verifyFrozen();const b=await browser(),report={at:new Date().toISOString(),kind:'daily_single_icon_actual_source_browser_capture',notGameCapture:true,fixtureOnly:true,
  assembly:out+'/assembly.json',frozenSources:frozen,screens:[],hoverChecks:[],checks:[],limitations:assembly.limitations};
 try{
  for(const [width,height]of[[1920,1080],[1280,720]]){
   verifyFrozen();await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(out+'/index.html','?state=normal');assert.equal(await b.run('previewReady'),true);
   await b.run('syncLayout();Promise.all([...document.querySelectorAll("#DailyGW2Canvas img")].map(image=>image.decode().catch(()=>false))).then(()=>true)');await sleep(120);
   const state=await stateOf(b);checkNormal(state,width,height);
   const file=out+'/daily_single_icon_'+width+'x'+height+'.png';await b.shot(file,{x:0,y:0,width,height});
   const crop=out+'/daily_single_icon_'+width+'x'+height+'_window.png';await b.shot(crop,cropRect(state.canvas.bounds,width,height));
   const a=state.cards[4].bounds,z=state.cards[5].bounds;
   const pair={x:a.x,y:Math.min(a.y,z.y),right:z.right,bottom:Math.max(a.bottom,z.bottom)};
   const pairCrop=out+'/daily_single_icon_'+width+'x'+height+'_days5_6.png';await b.shot(pairCrop,cropRect(pair,width,height));
   report.screens.push({width,height,file,crop,pairCrop,state});
   for(const day of[5,6]){
    const hovered=await hoverDay(b,day,width,height),rewards=fixture.rewards[day-1].rewards;
    for(const reward of rewards){assert(hovered.tip.body.includes(reward.name));assert(hovered.tip.body.includes(reward.description));assert(hovered.tip.body.includes(String(reward.count)));}
    const tipFile=out+'/daily_single_icon_'+width+'x'+height+'_day'+day+'_tooltip.png';await b.shot(tipFile,{x:0,y:0,width,height});
    report.hoverChecks.push({width,height,day,file:tipFile,tip:hovered.tip});
    await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:1,y:1});await sleep(180);
   }
   // Only local snapshot data changes. A future schedule with unequal counts
   // must retain the visible primary quantity and both exact tooltip counts.
   await b.run('(()=>{const days=structuredClone(dailyCurrentSnapshot.calendar28);days[4].rewards[0].count=17;days[4].rewards[1].count=123;dailyPreviewSend({calendar28:days});return true;})()');
   const unequal=await hoverDay(b,5,width,height);assert.deepEqual(unequal.cards[4].quantities,['17']);
   for(const reward of[{...fixture.rewards[4].rewards[0],count:17},{...fixture.rewards[4].rewards[1],count:123}]){
    assert(unequal.tip.body.includes(reward.name));assert(unequal.tip.body.includes(String(reward.count)));assert(unequal.tip.body.includes(reward.description));
   }
   const unequalFile=out+'/daily_single_icon_'+width+'x'+height+'_unequal_counts_tooltip.png';await b.shot(unequalFile,{x:0,y:0,width,height});
   report.hoverChecks.push({width,height,day:5,fixtureUnequalCounts:[17,123],file:unequalFile,tip:unequal.tip,quantities:unequal.cards[4].quantities});
   await b.run('cfg.SurvivalDaily.Close();syncLayout();true');assert.equal((await stateOf(b)).tip,null,'Close hides shared tooltip');
  }
  verifyFrozen();report.status='PASS_DAILY_SINGLE_ICON_VISUAL';
  report.checks=['Actual production XML/JS/CSS and formal CSV reward fixture','28 full-width daily images and all three monthly images; no split halves','Days 5/6/12/13/19/20/26/27 show two reward kinds','Primary real reward ID and quantity remain associated','Real pointer hover exposes every scheduled name, exact quantity and effect','Unequal 17/123 fixture retains primary 17 and both tooltip quantities','Two viewport screenshots and direct screenshot clips; no image editing','Exact native PNG bytes, original background, monthly layout and warm tint retained','No claim, purchase, checkout, draw, game/account or server mutation'];
 }catch(error){
  report.status='FAIL_DAILY_SINGLE_ICON_VISUAL';report.failure=error.stack||String(error);
  try{report.failureSnapshot=await stateOf(b);await b.shot(out+'/failure.png');}catch{}
  throw error;
 }finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2)+'\n');b.close();}
 console.log(report.status+' '+out+'/visual_report.json');
}
let settled=false;
process.on('beforeExit',()=>{if(!settled){console.error('DAILY_SINGLE_ICON_CAPTURE_INCOMPLETE');process.exitCode=1;}});
main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
