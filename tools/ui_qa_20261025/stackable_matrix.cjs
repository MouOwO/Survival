'use strict';
// Read-only production archive component QA in an isolated browser. All counts
// are explicit synthetic snapshots, never real purchases or player inventory.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {browser,sleep}=require('../archive_official_variants_20261019/browser.cjs');
const {seedStackableArchive}=require('./stackable_fixture.cjs');
const root=path.resolve(__dirname,'../..'),arg=(n,d)=>{const i=process.argv.indexOf(n);return i<0?d:process.argv[i+1];};
const label=arg('--label','after_stackable_v08'),reportName=arg('--report','stackable_matrix');
if(!/^[a-z0-9_-]{1,40}$/.test(label)||!/^[a-z0-9_-]{1,50}$/.test(reportName))throw Error('Invalid report label');
const folder=path.join(root,'output/ui_qa_20261025/browser',label),preview=path.join(folder,'preview/index.html');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex'),snapshot=JSON.parse(fs.readFileSync(path.join(folder,'preview/snapshot.json'),'utf8'));
const report={schema:1,label,sourceDigest:snapshot.sourceDigest,at:new Date().toISOString(),scope:'Chrome real production archive grid/tooltip/header with explicit synthetic authoritative-style inventory snapshots; no native Dota or payment',fixtureProvenance:{runnerSha256:sha(__filename),fixtureSha256:sha(path.join(__dirname,'stackable_fixture.cjs')),previewIndexSha256:sha(preview),styleSha256:sha(path.join(folder,'preview/style.css')),nativeIconManifestSha256:sha(path.join(folder,'native_icons.json'))},cases:[],passed:false,nativeGames:0,realAccounts:0,realPurchases:0,publicNetworkAllowed:false};
const filename=path.join(folder,reportName+'.json');
const stages=[
 {name:'zero',ember:0,zongzi:0,unique:0},
 {name:'one',ember:1,zongzi:1,unique:1},
 {name:'two',ember:2,zongzi:2,unique:1},
 {name:'unlimited151_and_capped150',ember:151,zongzi:150,unique:1},
 {name:'legacy_video_p103_alias',ember:2,zongzi:150,unique:1,legacyAlias:true},
 {name:'legacy_daily_unique',ember:151,zongzi:150,unique:1,legacyDaily:true}
];
function test(v,m){if(!v)throw Error(m);}
function save(){fs.writeFileSync(filename,JSON.stringify(report,null,2));}
let active;
const run=(fn,...args)=>active.run('('+fn.toString()+')('+args.map(x=>JSON.stringify(x)).join(',')+')');
async function inspect(){return run(()=>{
 const all=function walk(p){return [p,...p.Children().flatMap(walk)];}(root),find=id=>root.FindChildTraverse(id);
 const rows=all.filter(p=>p.__archiveCategory==='points'&&p.__archiveItem&&p.__v10&&p.visible).map(p=>({id:p.__archiveItem.id,count:p.__archiveItem.count,maxOwned:p.__archiveItem.max_owned,target:p.__archiveItem.target,countKnown:p.__archiveItem.count_known,badgeText:p.__v10.count.text,badgeVisible:p.__v10.countHost.visible,name:p.__v10.name.text,owned:p.BHasClass('ArchiveCommerceOwned'),unknown:p.BHasClass('ArchiveCommerceUnknown')}));
 return {rows,header:find('ArchiveV10Overview')?.text,title:find('ArchiveV10_page_title')?.text,layer:cfg.SurvivalUILayers?.Top(),font:cfg.SurvivalArchiveFontV36?.Inspect(),snapshotUnchanged:JSON.stringify(__uiqaStackableFixture.rows)===__uiqaStackableFixture.original,errors:previewErrors};
});}
function verify(view,stage){
 const expected=[{id:stage.legacyAlias?'video_p103':'lottery_ember_of_legacy',count:stage.ember,quantity:String(stage.ember),unique:false},{id:'welfare_zongzi',count:stage.zongzi,quantity:stage.zongzi+'/150',unique:false},{id:'daily_growth_gem',count:stage.unique,unique:true}];
 test(view.rows.length===3,'expected exactly the three supplied catalogue rows');
 for(const row of expected){const actual=view.rows.find(x=>x.id===row.id);test(actual,'row missing: '+row.id);test(actual.count===row.count,'quantity truncated or changed: '+row.id+' '+actual.count+' expected '+row.count);test(actual.owned===(row.count>0),'ownership state mismatch: '+row.id);if(row.unique)test(actual.badgeVisible===false,'unique item unexpectedly shows a count badge');else{test(actual.badgeText===row.quantity,'stack badge text mismatch: '+row.id);test(actual.badgeVisible,'stack quantity badge missing: '+row.id);}}
 const owned=expected.filter(r=>r.count>0).length;test(new RegExp(owned+'\\s*/\\s*3').test(view.header),'header must count owned item types, not total stack copies');
 test(view.snapshotUnchanged,'presentation mutated supplied authoritative-style snapshot');test(view.errors.length===0,'production component error');return expected;
}
async function hover(row){
 await active.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await sleep(80);
 const point=await run(id=>{const walk=function walk(p){return [p,...p.Children().flatMap(walk)];},all=walk(root),p=all.find(n=>n.__archiveCategory==='points'&&n.__archiveItem?.id===id&&n.__v10&&n.visible);if(!p)return null;const bound=p.events.onmouseover?p:walk(p).find(n=>n.events.onmouseover);if(!bound)return {handlerBound:false};const r=bound.el.getBoundingClientRect(),x=r.x+r.width/2,y=r.y+r.height/2,top=document.elementFromPoint(x,y);return {x,y,rect:r.toJSON(),handlerBound:true,hit:!!top&&(top===bound.el||bound.el.contains(top))};},row.id);
 test(point&&point.handlerBound&&point.hit,'stackable hover is unavailable or obstructed: '+row.id);const r=point.rect,attempts=[];let tooltip;
 for(const [x,y] of [[point.x,point.y],[r.x+5,r.y+5],[r.right-5,r.y+5],[r.x+5,r.bottom-5],[r.right-5,r.bottom-5]]){
  await active.move(2,2);await active.move(x,y);await sleep(250);
  tooltip=await run(()=>{syncLayout();const p=id=>root.FindChildTraverse('ArchiveV10Tooltip'+id),tip=p('');return {visible:tip?.visible,title:p('Title')?.text,metricVisible:p('Metric')?.visible,caption:p('MetricCaption')?.text,quantity:p('Quantity')?.text,condition:p('Condition')?.text,errors:previewErrors};});
  attempts.push({x,y,visible:tooltip.visible});if(tooltip.visible)break;
 }
 test(tooltip.visible,'physical pointer did not reveal tooltip: '+row.id);test(tooltip.errors.length===0,'tooltip component error');
 if(row.unique){test(!tooltip.metricVisible,'unique item must retain its unlock-only detail');test(tooltip.condition.includes('唯一持有'),'unique condition missing');}
 else{test(tooltip.metricVisible,'stackable tooltip hid the quantity metric');test(tooltip.quantity===row.quantity,'tooltip truncated stack quantity: '+row.id);test(tooltip.caption==='拥有数量','stackable tooltip mislabeled as unlock state');test(!tooltip.condition.includes('唯一持有'),'stackable inherited unique ownership claim');}
 return {id:row.id,point,attempts,tooltip};
}
async function main(){
 active=await browser({output:path.join(folder,'stackable_chrome')});
 try{
  await active.call('Network.enable');await active.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  const size=arg('--size',null),sizes=size?[size.split('x').map(Number)]:[[1280,720],[1600,900],[1920,1080],[2560,1440]],selection=arg('--case',null),chosen=selection?stages.filter(s=>s.name===selection):stages;
  test(chosen.length>0&&sizes.every(s=>s.length===2&&s.every(n=>Number.isInteger(n)&&n>=600&&n<=4096)),'invalid target case or size');
  for(const [width,height]of sizes){await active.viewport(width,height);await active.go(preview,'?page=archive&category=points&state=normal');let sequence=2000;
   for(const stage of chosen){const entry={name:stage.name,width,height,stage,passed:false};report.cases.push(entry);
    try{
     entry.input=await run(seedStackableArchive,stage,++sequence);entry.view=await inspect();const expected=verify(entry.view,stage);entry.hover=[];
     for(const row of expected)entry.hover.push(await hover(row));
     await run(()=>{const old=JSON.parse(__uiqaStackableFixture.original);old.forEach(r=>r.count=0);emit('survival_archive_snapshot',{ok:1,category_id:'points',sequence:__uiqaStackableFixture.sequence-1,chunk:1,chunks:1,categories:PREVIEW_FIXTURE.archiveCats,rows:old});syncLayout();});entry.afterStaleReply=await inspect();verify(entry.afterStaleReply,stage);
     await run(()=>{cfg.SurvivalArchive.Close();cfg.SurvivalArchive.Open();syncLayout();});entry.afterReopen=await inspect();verify(entry.afterReopen,stage);entry.passed=true;
    }catch(error){entry.error=String(error.message||error);try{entry.lastView=await inspect();}catch(_){} }
    const shot=path.join(folder,'screenshots',width+'x'+height+'_stackable_'+stage.name+'.png');await active.shot(shot,{x:0,y:0,width,height});entry.screenshot=path.relative(root,shot).replaceAll('\\','/');
    entry.networkAttempts=active.events.filter(e=>e.method==='Network.requestWillBeSent'&&/^https?:|^wss?:/.test(e.params.request.url)).map(e=>e.params.request.url.split('?')[0]);if(entry.networkAttempts.length){entry.error='forbidden network attempt';entry.passed=false;}active.events.length=0;save();console.log(JSON.stringify({case:stage.name,size:width+'x'+height,passed:entry.passed,error:entry.error||null}));
   }
  }
  report.passed=report.cases.every(c=>c.passed);report.finishedAt=new Date().toISOString();save();if(!report.passed)process.exitCode=1;
 }finally{await active.close();}
}
main().catch(error=>{report.infrastructureError=String(error.message||error);save();console.error(report.infrastructureError);process.exitCode=1;});
