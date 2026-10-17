'use strict';
// Actual production daily component and shared archive tooltip in the existing
// local Panorama adapter. Progress is a fixture; no account or reward is touched.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base='output/daily_archive_tooltip_20261017',entry=base+'/visual_preview/index.html';
process.chdir(repo);fs.mkdirSync(base+'/visual_screens',{recursive:true});
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const assembly=JSON.parse(fs.readFileSync(base+'/visual_preview/assembly.json','utf8'));
const frozen=assembly.sourceGraph.filter(r=>/(?:daily_remaining_5d5c1152eb\.js|daily_gw2\.css|common\/archive_tooltip\.(?:js|css)|layout\/custom_game\/archive\.xml)$/.test(r.path));
function verifyFrozen(){for(const r of frozen)assert.equal(sha(fs.readFileSync('panorama/src/'+r.path,'utf8').replace(/^\uFEFF/,'')),r.sha256,'Frozen actual production source '+r.path);}
function inspect(){
 const shown=n=>!!n&&n.visible&&getComputedStyle(n.el).display!=='none'&&n.el.getBoundingClientRect().width>0;
 const describe=n=>{if(!n)return null;const s=getComputedStyle(n.el);return {id:n.id,classes:n.GetClasses(),visible:shown(n),bounds:n.el.getBoundingClientRect().toJSON(),text:n.text,style:n._style,backgroundImage:s.backgroundImage,backgroundColor:s.backgroundColor,color:s.color,fontSize:s.fontSize,fontFamily:s.fontFamily,overflowY:s.overflowY,display:s.display,scrollHeight:n.el.scrollHeight,clientHeight:n.el.clientHeight,scrollTop:n.el.scrollTop};};
 const hosts=nodes.DailyGW2Canvas.FindChildrenWithClassTraverse('ArchiveSharedTooltipHost'),tip=hosts.find(shown)||hosts[0],prefix=tip&&tip.id;
 const find=role=>prefix&&nodes[prefix+role];
 const art=role=>{const host=find(role);return host?host.FindChildrenWithClassTraverse('ArchiveSharedTooltipArt').map(describe):[];};
 const reference=nodes.ArchiveV10Tooltip;
 return {errors:previewErrors,ready:previewState.ready,api:cfg.SurvivalDaily.Inspect(),calls:previewCalls,sharedHosts:hosts.length,tip:describe(tip),surface:describe(find('Surface')),viewport:describe(find('Viewport')),body:describe(find('Body')),title:describe(find('Title')),effect:describe(find('Effect')),state:describe(find('State')),condition:describe(find('Condition')),metric:describe(find('Metric')),frame:describe(find('Frame')),backing:describe(find('Backing')),backingArt:art('Backing'),frameArt:art('Frame'),separator:describe(find('Separator')),archiveReference:reference?{classes:reference.GetClasses(),backing:describe(nodes.ArchiveV10TooltipBacking),frame:describe(nodes.ArchiveV10TooltipFrame),backingArt:nodes.ArchiveV10TooltipBacking.FindChildrenWithClassTraverse('ArchiveSharedTooltipArt').map(describe)}:null};
}
const stateOf=b=>b.run('('+inspect.toString()+')()');
function inViewport(rect,width,height){assert(rect.x>=-1&&rect.y>=-1&&rect.right<=width+1&&rect.bottom<=height+1,'Tooltip surface stays in viewport '+JSON.stringify(rect));}
async function main(){
 verifyFrozen();const b=await browser(),report={at:new Date().toISOString(),kind:'actual_daily_archive_shared_tooltip_browser_check',notGameCapture:true,fixtureOnly:true,assembly:base+'/visual_preview/assembly.json',frozenSources:frozen,screens:[],checks:[],limitations:['Chrome Panorama adapter approximates native font and layout rendering.','Only local formal-CSV fixtures are emitted; no game, account, save or server operation occurs.']};
 try{
  for(const [width,height]of[[1920,1080],[1280,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   for(const scene of[
    {name:'ordinary_day',mode:'normal',expression:'nodes.DailyGW2Day_3',title:'第3天'},
    {name:'ordinary_icon',mode:'normal',expression:'nodes.DailyGW2Day_3.Children().find(n=>n.BHasClass("DailyGW2Reward"))'},
    {name:'month_locked',mode:'normal',expression:'nodes.DailySpecials.Children()[0]',title:'聚财古符',contains:['领取条件','累计签到7次','开通月卡后解锁']},
    {name:'month_active',mode:'pass',expression:'nodes.DailySpecials.Children()[2]',title:'森罗本源',contains:['开局木材+200','英雄全属性加成+8%','星悦积分+88']},
    {name:'long_description',mode:'long',expression:'nodes.DailyGW2Day_3',long:true,contains:['隔离长文本布局样例']}
   ]){
    await b.go(entry,'?state='+scene.mode);assert.equal(await b.run('previewReady'),true,'Actual source preview initializes');
    await b.run('window.visualBeforeTransactions=JSON.stringify(previewCalls.filter(c=>/claim|purchase|checkout|draw/.test(c.name)));window.visualAnchor='+scene.expression+';if(!visualAnchor?.events.onmouseover)throw Error("Missing real reward hover handler");visualAnchor.events.onmouseover();syncLayout();true');await sleep(900);await b.run('syncLayout();true');
    let state=await stateOf(b);assert.deepEqual(state.errors,[]);assert.equal(state.sharedHosts,1,'Daily owns one shared archive tooltip');assert(state.tip?.visible,'Real daily hover opens the shared tooltip');assert(state.tip.classes.includes('ArchiveSharedTooltipHost'));assert.equal(state.backingArt.length,9,'Archive backing nine-slice is reused');assert.equal(state.frameArt.length,9,'Archive frame renderer is reused');assert(state.backingArt.every(n=>/gw2_tooltip_v1\/background\.png/.test(n.backgroundImage)),'The exact archive clean backing is reused');assert.equal(state.frame.display,'none','Legacy blue ornate frame is not painted');
    assert(state.frameArt.every(n=>!/daily_gw2|daily_accepted/.test(n.backgroundImage)),'No daily blue frame asset is rendered');
    inViewport(state.surface.bounds,width,height);assert.equal(await b.run('JSON.stringify(previewCalls.filter(c=>/claim|purchase|checkout|draw/.test(c.name)))===visualBeforeTransactions'),true,'Hover emits no claim, purchase or draw request');
    if(scene.title)assert(state.title.text.includes(scene.title),'Correct reward title');
    const text=state.body.text;for(const line of scene.contains||[])assert(text.includes(line),'Original daily text retained: '+line);
    if(state.archiveReference){assert.equal(state.backing.backgroundColor,state.archiveReference.backing.backgroundColor,'Same backing colour as archive');assert.deepEqual(state.backingArt.map(n=>n.backgroundImage),state.archiveReference.backingArt.map(n=>n.backgroundImage),'Same nine-slice imagery as archive');assert.equal(state.frame.display,state.archiveReference.frame.display,'Same archive frame visibility');}
    if(scene.long){
     assert(state.viewport.scrollHeight>state.viewport.clientHeight+1,'Long daily description keeps a bounded scroll viewport');await b.run('nodes['+JSON.stringify(state.viewport.id)+'].el.scrollTop=999999;true');state=await stateOf(b);assert(state.viewport.scrollTop>0,'The final lines remain reachable');
    }
    const file=base+'/visual_screens/'+scene.name+'_'+width+'x'+height+'.png';await b.shot(file,{x:0,y:0,width,height});
    const crop=base+'/visual_screens/'+scene.name+'_'+width+'x'+height+'_detail.png',r=state.surface.bounds,pad=8;
    await b.shot(crop,{x:Math.max(0,Math.floor(r.x-pad)),y:Math.max(0,Math.floor(r.y-pad)),width:Math.min(width-Math.max(0,Math.floor(r.x-pad)),Math.ceil(r.width+2*pad)),height:Math.min(height-Math.max(0,Math.floor(r.y-pad)),Math.ceil(r.height+2*pad))});
    report.screens.push({scene:scene.name,mode:scene.mode,width,height,file,crop,state});
    await b.run('cfg.SurvivalDaily.Close();syncLayout();true');assert.equal((await stateOf(b)).tip.visible,false,'Close hides the shared tooltip');
   }
  }
  verifyFrozen();report.status='PASS_DAILY_ARCHIVE_SHARED_TOOLTIP_VISUAL';report.checks=['Actual calendar and icon hover use one shared archive tooltip instance','Month-card effects, conditions and statuses retain current text','Archive backing / frame / type styling is reused with no blue daily frame','Normal and long content remains within 1920×1080 and1280×720 viewports','Long content can scroll to the final line','Hover and tooltip close never send a claim or purchase request'];
 }catch(error){report.status='FAIL_DAILY_ARCHIVE_SHARED_TOOLTIP_VISUAL';report.failure=error.stack||String(error);try{report.failureSnapshot=await stateOf(b);await b.shot(base+'/visual_screens/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(base+'/visual_report.json',JSON.stringify(report,null,2)+'\n');b.close();}
 console.log(report.status+' '+base+'/visual_report.json');
}
let settled=false;
process.on('beforeExit',()=>{if(!settled){console.error('DAILY_ARCHIVE_TOOLTIP_VISUAL_INCOMPLETE: Chrome/CDP ended before capture finished.');process.exitCode=1;}});
main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
