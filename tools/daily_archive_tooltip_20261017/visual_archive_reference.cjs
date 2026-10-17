'use strict';
// Open the real archive consumer in the same frozen assembly and compare its
// actual styles/materials with the already-captured daily tooltip consumer.
const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const base='output/daily_archive_tooltip_20261017',file=base+'/visual_report.json';
const report=JSON.parse(fs.readFileSync(file,'utf8'));
const verify=()=>report.frozenSources.forEach(r=>assert.equal(crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+r.path,'utf8').replace(/^\uFEFF/,'')).digest('hex'),r.sha256));
async function main(){
 assert.equal(report.status,'PASS_DAILY_ARCHIVE_SHARED_TOOLTIP_VISUAL');verify();const b=await browser(),references=[];
 try{for(const [width,height]of[[1920,1080],[1280,720]]){
  await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(base+'/visual_preview/index.html');assert(await b.run('previewReady'));
  await b.run(`(()=>{cfg.SurvivalDaily.Close();const categories=PREVIEW_FIXTURE.archiveCats,rows=structuredClone(PREVIEW_FIXTURE.v10.pages.clear);emit('survival_archive_snapshot',{ok:1,category_id:'clear',sequence:900,chunk:1,chunks:1,categories,rows,currencies:{gold:2881,points:320,tickets:20}});cfg.SurvivalArchive.Toggle();cfg.SurvivalArchive.SelectCategory('clear');syncLayout();return true;})()`);await sleep(350);
  await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(c=>c.visible&&c.__archiveItem&&c.events.onmouseover);if(!card)throw Error('Real archive card missing');card.events.onmouseover();syncLayout();return true;})()`);await sleep(900);
  const state=await b.run(`(()=>{const d=n=>{const s=getComputedStyle(n.el);return {id:n.id,text:n.text,classes:n.GetClasses(),backgroundColor:s.backgroundColor,backgroundImage:s.backgroundImage,display:s.display,fontFamily:s.fontFamily,fontSize:s.fontSize,color:s.color,bounds:n.el.getBoundingClientRect().toJSON()};};return {visible:nodes.ArchiveV10Tooltip.visible,backing:d(nodes.ArchiveV10TooltipBacking),frame:d(nodes.ArchiveV10TooltipFrame),backingArt:nodes.ArchiveV10TooltipBacking.FindChildrenWithClassTraverse('ArchiveSharedTooltipArt').map(d),title:d(nodes.ArchiveV10TooltipTitle),effect:d(nodes.ArchiveV10TooltipEffect),surface:d(nodes.ArchiveV10TooltipSurface),errors:previewErrors,calls:previewCalls};})()`);
  assert(state.visible);assert.deepEqual(state.errors,[]);assert.equal(state.backingArt.length,9);assert.equal(state.frame.display,'none');
  for(const daily of report.screens.filter(r=>r.width===width)){
   assert.deepEqual(daily.state.backingArt.map(n=>n.backgroundImage),state.backingArt.map(n=>n.backgroundImage),'Daily backing equals actual archive');
   assert.equal(daily.state.backing.backgroundColor,state.backing.backgroundColor);
   assert.equal(daily.state.frame.display,state.frame.display);
   for(const key of['fontFamily','fontSize','color']){assert.equal(daily.state.title[key],state.title[key],'Archive title '+key);assert.equal(daily.state.effect[key],state.effect[key],'Archive effect '+key);}
  }
  const image=base+'/visual_screens/archive_reference_'+width+'x'+height+'.png';await b.shot(image,{x:0,y:0,width,height});const r=state.surface.bounds,detail=base+'/visual_screens/archive_reference_'+width+'x'+height+'_detail.png';await b.shot(detail,{x:Math.floor(r.x-8),y:Math.floor(r.y-8),width:Math.ceil(r.width+16),height:Math.ceil(r.height+16)});references.push({width,height,image,detail,state});
 }
 verify();report.archiveConsumerReferences={status:'PASS_ACTUAL_ARCHIVE_DAILY_MATERIAL_AND_TYPOGRAPHY_EQUAL',references};report.checks.push('Both actual archive and actual daily consumers have identical backing pixels, frame visibility, title and effect typography');fs.writeFileSync(file,JSON.stringify(report,null,2)+'\n');console.log(report.archiveConsumerReferences.status+' '+file);
 }finally{b.close();}
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('ARCHIVE_REFERENCE_INCOMPLETE');process.exitCode=1;}});main().then(()=>{settled=true;},e=>{settled=true;console.error(e.stack||e);process.exitCode=1;});
