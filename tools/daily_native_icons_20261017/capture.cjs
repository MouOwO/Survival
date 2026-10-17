'use strict';
// Account-free screenshots of actual production controls with formal CSV rewards.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../commerce_points_20261016/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base='output/daily_native_icons_20261017',out=base+'/visual_preview';
process.chdir(repo);
const sha=raw=>crypto.createHash('sha256').update(raw).digest('hex');
const assembly=JSON.parse(fs.readFileSync(out+'/assembly.json','utf8'));
const frozen=assembly.sourceGraph.filter(row=>/(?:common\/item_resources\.js|reward_presentation\.js|item_art_remaining_5d5c1152eb\.js|daily_remaining_5d5c1152eb\.js|daily_gw2\.css|layout\/custom_game\/archive\.xml)$/.test(row.path));
function verifyFrozen(){
 for(const row of frozen)assert.equal(sha(fs.readFileSync('panorama/src/'+row.path,'utf8').replace(/^\uFEFF/,'')),row.sha256,'Frozen source: '+row.path);
 assert.equal(sha(fs.readFileSync(assembly.dailyNativeResources.source)),assembly.dailyNativeResources.sha256,'Resource registry remained frozen');
 assert.equal(sha(fs.readFileSync(assembly.previewNativeAliases.nativeManifest)),assembly.previewNativeAliases.nativeManifestSha256,'Native PNG manifest remained frozen');
}
function inspect(){
 const shown=node=>!!node&&node.visible&&getComputedStyle(node.el).display!=='none'&&node.el.getBoundingClientRect().width>0;
 const describe=node=>({id:node.id,visible:shown(node),bounds:node.el.getBoundingClientRect().toJSON(),classes:node.GetClasses()});
 const canvas=nodes.DailyGW2Canvas,resources=cfg.SurvivalItemResources;
 const backgrounds=[],stack=[canvas];while(stack.length){const node=stack.pop();stack.push(...node.Children());if(node.el.dataset.dailyNativeResolvedBackground)backgrounds.push({uri:node.el.dataset.dailyNativeResolvedBackground,image:getComputedStyle(node.el).backgroundImage});}
 const icons=canvas.FindChildrenWithClassTraverse('DailyGW2ItemArt').map(node=>{
  const resource=resources.Lookup(node.__itemResourceId),style=getComputedStyle(node.el);
  return {...describe(node),resourceId:node.__itemResourceId,uri:resource?.uri,fit:resource?.fit||'cover',appliedFit:node.__survivalItemFill,
   image:node.el.currentSrc||node.el.src,complete:node.el.complete,naturalWidth:node.el.naturalWidth,naturalHeight:node.el.naturalHeight,
   objectFit:style.objectFit,filter:style.filter,saturation:Number(style.getPropertyValue('--pano-saturation').trim()||1),
   brightness:Number(style.getPropertyValue('--pano-brightness').trim()||1),browserWash:node.el.dataset.dailyNativePreviewWash};
 });
 return {ready:previewState.ready,errors:previewErrors,api:cfg.SurvivalDaily.Inspect(),window:describe(nodes.DailyWindow),canvas:describe(canvas),
  cards:nodes.DailyCards.GetChildCount(),specials:nodes.DailySpecials.Children().map(describe),icons,calls:previewCalls,
  transactionalCalls:previewCalls.filter(call=>/claim|purchase|checkout|draw/.test(call.name)||['create','purchase','checkout','claim','draw'].includes(call.payload?.action)),
  backgrounds,registryHash:resources.sourceHash,caption:document.getElementById('PreviewCaption').textContent};
}
function inViewport(rect,width,height,name){assert(rect.x>=-1&&rect.y>=-1&&rect.right<=width+1&&rect.bottom<=height+1,name+' stays in viewport: '+JSON.stringify(rect));}
async function main(){
 verifyFrozen();const b=await browser(),report={at:new Date().toISOString(),kind:'daily_native_icons_actual_source_browser_capture',notGameCapture:true,fixtureOnly:true,
  assembly:out+'/assembly.json',screens:[],checks:[],limitations:assembly.limitations};
 try{
  for(const [width,height,mode]of[[1920,1080,'normal'],[1280,720,'normal'],[1920,1080,'pass']]){
   verifyFrozen();await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(out+'/index.html','?state='+mode);assert.equal(await b.run('previewReady'),true,'Actual source fixture initializes');
   await b.run('syncLayout();Promise.all([...document.querySelectorAll("#DailyGW2Canvas img")].map(image=>image.decode().catch(()=>false))).then(()=>true)');await sleep(120);
   const state=await b.run('('+inspect.toString()+')()');
   assert.equal(state.ready,true);assert.deepEqual(state.errors,[]);assert.equal(state.cards,28);assert.equal(state.specials.length,3);
   assert.equal(state.registryHash,assembly.dailyNativeResources.sha256);assert.deepEqual(state.transactionalCalls,[],'Screenshot never claims rewards or buys anything');
   assert(state.backgrounds.some(asset=>asset.uri.includes('window_background_v10.vtex')),'Exact grey-brown window artwork is rendered');
   assert(state.backgrounds.some(asset=>asset.uri.includes('button_v10.vtex')),'Exact production button artwork is rendered');
   assert(state.backgrounds.every(asset=>asset.image.includes('file:')),'Browser resolves dynamic native texture backgrounds to existing PNG aliases');
   inViewport(state.canvas.bounds,width,height,'Daily window');
   for(const special of state.specials){assert(special.visible,'Monthly reward column remains visible');inViewport(special.bounds,width,height,special.id);}
   const expected=new Map(assembly.dailyNativeResources.items.map(row=>[row.id,row]));
   assert.deepEqual([...new Set(state.icons.map(icon=>icon.resourceId))].sort(),[...expected.keys()].sort(),'All 12 actual reward identities are displayed');
   for(const icon of state.icons){
    const resource=expected.get(icon.resourceId);assert(icon.visible,icon.resourceId+' is visible');assert(icon.complete&&icon.naturalWidth>0,icon.resourceId+' decoded exact native PNG');
    assert.equal(icon.uri,resource.uri);assert.equal(icon.fit,resource.fit);assert.equal(icon.appliedFit,resource.fit);
    assert.equal(icon.naturalWidth,resource.sourceSize[0]);assert.equal(icon.naturalHeight,resource.sourceSize[1]);
    assert(icon.saturation<1,icon.resourceId+' uses the authored reduced saturation');
    assert.equal(icon.browserWash,assembly.dailyWashBrowserApproximation.washColor);
    assert(icon.filter.includes('DailyNativePreviewWash'),icon.resourceId+' uses the explicit browser-only warm wash approximation');
    if(resource.fit==='contain')assert.equal(icon.objectFit,'contain',icon.resourceId+' retains its complete native shape');
    inViewport(icon.bounds,width,height,icon.resourceId);
   }
   const file=out+'/daily_native_'+mode+'_'+width+'x'+height+'.png';await b.shot(file,{x:0,y:0,width,height});
   const r=state.canvas.bounds,x=Math.max(0,Math.floor(r.x-6)),y=Math.max(0,Math.floor(r.y-6));
   const crop=out+'/daily_native_'+mode+'_'+width+'x'+height+'_window.png';
   await b.shot(crop,{x,y,width:Math.min(width-x,Math.ceil(r.width+12)),height:Math.min(height-y,Math.ceil(r.height+12))});
   report.screens.push({width,height,mode,file,crop,...state});
  }
  verifyFrozen();report.status='PASS_DAILY_NATIVE_ICONS_VISUAL';
  report.checks=['Actual production XML/JS/CSS with formal CSV reward fixture','All 12 daily resources use reviewed exact native PNGs','28 ordinary reward cells and three month-card rewards remain visible','Explicit contain preserves full native image shape','1920x1080 and 1280x720 views stay within viewport','No claim, purchase, checkout, game/account or server mutation'];
 }catch(error){
  report.status='FAIL_DAILY_NATIVE_ICONS_VISUAL';report.failure=error.stack||String(error);
  try{report.failureSnapshot=await b.run('('+inspect.toString()+')()');await b.shot(out+'/failure.png');}catch{}
  throw error;
 }finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2)+'\n');b.close();}
 console.log(report.status+' '+out+'/visual_report.json');
}
let settled=false;
process.on('beforeExit',()=>{if(!settled){console.error('DAILY_NATIVE_ICONS_CAPTURE_INCOMPLETE');process.exitCode=1;}});
main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
