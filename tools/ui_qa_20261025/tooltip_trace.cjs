'use strict';
// Real Chrome mouse dispatch against frozen production lottery components.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {browser,sleep}=require('../archive_official_variants_20261019/browser.cjs');
const {seedLotteryLayout}=require('./lottery_fixture.cjs');
const root=path.resolve(__dirname,'../..'),arg=(name,fallback)=>{const i=process.argv.indexOf(name);return i<0?fallback:process.argv[i+1];};
const label=arg('--label','after');if(!/^[a-z0-9_-]{1,40}$/.test(label))throw Error('Invalid label');
const folder=path.join(root,'output/ui_qa_20261025/browser',label),snapshot=JSON.parse(fs.readFileSync(path.join(folder,'preview/snapshot.json'),'utf8'));
const shaFile=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const report={schema:1,label,sourceDigest:snapshot.sourceDigest,runnerSha256:shaFile(__filename),fixtureProvenance:{previewIndexSha256:shaFile(path.join(folder,'preview/index.html')),styleSha256:shaFile(path.join(folder,'preview/style.css')),nativeIconManifestSha256:shaFile(path.join(folder,'native_icons.json')),lotteryFixtureSha256:shaFile(path.join(__dirname,'lottery_fixture.cjs'))},at:new Date().toISOString(),scope:'Chrome_physical_pointer_not_native_Dota',syntheticLongDescriptionOnly:true,realOrdersOrAccounts:false,publicNetworkAllowed:false,cases:[],passed:false};
const reportName=arg('--report','tooltip_trace');if(!/^[a-z0-9_-]{1,50}$/.test(reportName))throw Error('Invalid report name');
const filename=path.join(folder,reportName+'.json');
function save(){fs.writeFileSync(filename,JSON.stringify(report,null,2));}
function test(value,message){if(!value)throw Error(message);}
let active;
const run=(fn,...args)=>active.run('('+fn.toString()+')('+args.map(x=>JSON.stringify(x)).join(',')+')');
const move=(x,y)=>active.call('Input.dispatchMouseEvent',{type:'mouseMoved',x,y});
async function view(){return run(()=>{const p=nodes.LotteryGW2Tooltip,scroll=nodes.LotteryGW2TooltipScroll,description=nodes.LotteryGW2TooltipDescription;return {at:performance.now(),shown:!!p&&p.visible,box:p?.el.getBoundingClientRect().toJSON(),descriptionLength:description?.text.length,overflow:!!description&&!!scroll&&description.actuallayoutheight>scroll.actuallayoutheight+1,scrollTop:scroll?.el.scrollTop,scrollHeight:scroll?.el.scrollHeight,scrollClientHeight:scroll?.el.clientHeight,dismiss:cfg.SurvivalTooltipDismiss.Inspect()};});}
async function prepare(long){
 await active.go(path.join(folder,'preview/index.html'),'?page=lottery&state=hover'+(long?'&tooltip_fixture=long':''));test(await active.run('previewReady'),'lottery fixture failed');
 const layoutFixture=long?await run(seedLotteryLayout,'long'):null;
 await move(2,2);await sleep(100);
 const anchor=await run(()=>{const panelList=function all(p){return [p,...p.Children().flatMap(all)];}(root),rows=[...document.querySelectorAll('.LotteryDetailRow')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.x>=0&&r.right<=innerWidth&&r.y>=0&&r.bottom<=innerHeight;});for(const row of rows){const owner=panelList.find(p=>p.el===row),bound=owner&&panelList.find(p=>p.events.onmouseover&&(p===owner||owner.el.contains(p.el)));if(!bound)continue;const r=bound.el.getBoundingClientRect(),x=r.x+5,y=r.y+5,hit=document.elementFromPoint(x,y);if(hit===bound.el||bound.el.contains(hit)){window.__uiqaTipAnchor=bound;window.__uiqaTipEvents=[];for(const name of ['mouseenter','mouseleave'])bound.el.addEventListener(name,()=>__uiqaTipEvents.push({name,at:performance.now(),shown:nodes.LotteryGW2Tooltip.visible}));return {x,y,bounds:r.toJSON(),id:bound.id,classes:bound.el.className,centerHit:true};}}return null;});
 test(anchor,'actual lottery hover handler is unavailable');await move(anchor.x,anchor.y);await sleep(250);
 const first=await view();test(first.shown,'initial physical hover did not reveal lottery tooltip');test(first.overflow===long,'tooltip does not match short/long layout fixture');
 return {anchor,first,layoutFixture};
}
async function one(width,height,long){
 const entry={width,height,kind:long?'long_scrollable':'short_dismissible',roundTrips:[],passed:false};report.cases.push(entry);
 try{
  await active.viewport(width,height);const {anchor,first,layoutFixture}=await prepare(long);entry.anchor=anchor;entry.first=first;entry.layoutFixture=layoutFixture;
  if(!long){await run(()=>{window.__uiqaStableLayout=syncLayout;syncLayout=function(){};});entry.fixtureTimingNote='Only the old browser adapter global full-page syncLayout hook is paused after stable geometry; production pointer handlers and actual DOM/style updates stay active. This removes adapter-only O(all panels) work from the fast-return timing probe.';}
  for(let i=0;i<50;i++){
   const before=await view();test(before.shown,'tooltip missing before round trip '+i);
   const r=before.box,points=[[r.x+r.width/2,r.y+r.height/2],[r.x+5,r.y+5],[r.right-5,r.bottom-5]],a=anchor.bounds;
   const destination=points.find(([x,y])=>!(x>=a.x&&x<a.right&&y>=a.y&&y<a.bottom));test(destination,'tooltip has no independent hover region');
   await move(destination[0],destination[1]);const inside=await view();
   // No sleep or helper move() delay occurs before the immediate return.
   await move(anchor.x,anchor.y);const returned=await view();
   const row={index:i,insideShown:inside.shown,returnedShown:returned.shown,returnDelayMs:returned.at-inside.at,immediateUnder30ms:returned.at-inside.at<30,dismiss:returned.dismiss};entry.roundTrips.push(row);
   test(long?inside.shown:!inside.shown,'incorrect tooltip hover policy at round trip '+i);test(returned.shown,'same icon did not rearm immediately at round trip '+i);
  }
  entry.immediateUnder30msCount=entry.roundTrips.filter(x=>x.immediateUnder30ms).length;if(!long)test(entry.immediateUnder30msCount>0,'all short immediate-return probes exceeded timing budget; rerun on a quieter browser');
  if(long){const before=await view(),r=before.box,x=r.x+r.width/2,y=r.y+r.height/2;await move(x,y);await sleep(50);await active.call('Input.dispatchMouseEvent',{type:'mouseWheel',x,y,deltaX:0,deltaY:460});await sleep(150);entry.scroll=await view();test(entry.scroll.shown&&entry.scroll.scrollTop>0,'long tooltip could not retain pointer and scroll');const file=path.join(folder,'screenshots',width+'x'+height+'_lottery_long_scrolled.png');await active.shot(file,{x:0,y:0,width,height});entry.longScrollScreenshot=path.relative(root,file).replaceAll('\\','/');await move(2,2);await sleep(250);entry.leftAll=await view();test(!entry.leftAll.shown,'long tooltip did not close after leaving both source and tooltip');}
  if(!long)await run(()=>{syncLayout=window.__uiqaStableLayout;syncLayout();});
  entry.browserErrors=await run(()=>previewErrors);test(entry.browserErrors.length===0,'component script error during pointer trace');entry.passed=true;
 }catch(error){entry.error=String(error.message||error);try{entry.lastView=await view();entry.browserErrors=await run(()=>previewErrors);}catch(_){} }
 try{entry.nativeEvents=await run(()=>window.__uiqaTipEvents||[]);const file=path.join(folder,'screenshots',width+'x'+height+'_lottery_'+entry.kind+'_trace.png');await active.shot(file,{x:0,y:0,width,height});entry.screenshot=path.relative(root,file).replaceAll('\\','/');}catch(error){entry.screenshotError=String(error.message||error);entry.passed=false;}
 entry.networkAttempts=active.events.filter(e=>e.method==='Network.requestWillBeSent'&&/^https?:|^wss?:/.test(e.params.request.url)).map(e=>({method:e.params.request.method,url:e.params.request.url.split('?')[0]}));if(entry.networkAttempts.length){entry.error='forbidden network attempt';entry.passed=false;}
 active.events.length=0;save();console.log(JSON.stringify({kind:entry.kind,size:width+'x'+height,passed:entry.passed,roundTrips:entry.roundTrips.length,under30ms:entry.immediateUnder30msCount,error:entry.error||null}));
}
async function main(){
 active=await browser({output:path.join(folder,'trace_chrome'),width:1600,height:900});
 try{await active.call('Network.enable');await active.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});const selected=arg('--size',null),sizes=selected?[selected.split('x').map(Number)]:[[1280,720],[1600,900],[1920,1080],[2560,1440]],kind=arg('--kind','both');test(['short','long','both'].includes(kind),'Invalid tooltip kind');test(sizes.every(s=>s.length===2&&s.every(v=>Number.isInteger(v)&&v>=600&&v<=4096)),'Invalid viewport');for(const [w,h]of sizes)for(const long of kind==='short'?[false]:kind==='long'?[true]:[false,true])await one(w,h,long);report.passed=report.cases.every(c=>c.passed);report.finishedAt=new Date().toISOString();save();if(!report.passed)process.exitCode=1;console.log(JSON.stringify({status:'TOOLTIP_TRACE_COMPLETE',cases:report.cases.length,passed:report.passed,report:path.relative(root,filename)}));}finally{await active.close();}
}
process.on('beforeExit',()=>{if(!report.finishedAt&&!report.infrastructureError){report.infrastructureError='browser_trace_incomplete';save();process.exitCode=1;}});
main().catch(error=>{report.infrastructureError=String(error.message||error);save();console.error(report.infrastructureError);process.exitCode=1;});
