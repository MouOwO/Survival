'use strict';
// Focused final visual regression after footer/scrollbar-only adjustments.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const {inspect,validate,inViewport}=require('./acceptance.cjs');
const repo=path.resolve(__dirname,'../..'),base='design_refs/archive_parchment_v1/work',out=base+'/final';
function checkFooter(state){
 const outer=state.canvas.bounds;
 for(const field of ['footer','status']){
  const label=state[field];if(!label?.visible||!String(label.text||'').trim())continue;
  const rect=label.bounds;
  assert(rect.x>=outer.x-1&&rect.y>=outer.y-1&&rect.right<=outer.right+1&&rect.bottom<=outer.bottom+1,field+' text stays inside the archive canvas');
  const logicalBottom=(rect.bottom-outer.y)/(outer.height/900);
  assert(logicalBottom<=840.5,field+' text stays inside the visible paper safe area (logical bottom <= 840), not its transparent canvas margin');
  label.paperSafeArea={logicalBottom,maximumBottom:840};
 }
}
async function main(){
 fs.mkdirSync(out,{recursive:true});
 const report={at:new Date().toISOString(),kind:'archive_parchment_final_visual_regression',notGameCapture:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),businessValidation:base+'/browser/report.json',footerPaperSafeArea:{canvasHeight:900,maximumLogicalBottom:840},screens:[],limitations:['Final layout/asset/footer checks supplement the earlier full isolated business-interaction suite.','Screenshots execute production UI code with synthetic progress in Chrome; native-game rendering is separate.']};
 const b=await browser();
 try{
  for(const [width,height,category] of [[1280,720,'shadow'],[1920,1080,'shadow'],[2560,1440,'shadow'],[2560,1080,'shadow'],[960,720,'shadow'],[1920,1080,'clear']]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(base+'/preview/index.html','?category='+category);assert(await b.run('previewReady'));await b.run('syncLayout();true');
   const state=await b.run('('+inspect.toString()+')()');validate(state,width,height);checkFooter(state);
   const name=category+'_'+width+'x'+height;await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(state,null,2));
   report.screens.push({name,width,height,category,canvas:state.canvas.bounds,footer:state.footer,status:state.status,scrollbarThumbImage:state.grid.scrollbarThumbImage});
  }
  await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(panel=>panel.visible&&panel.BHasClass('ArchiveCard'));card.events.onmouseover();syncLayout();return true;})()`);await new Promise(resolve=>setTimeout(resolve,300));
  const tip=await b.run('('+inspect.toString()+')()');assert(tip.tooltip?.visible);inViewport(tip.tooltip.bounds,1920,1080,'Final tooltip');checkFooter(tip);await b.shot(out+'/clear_tooltip.png',{x:0,y:0,width:1920,height:1080});
  report.changedSinceSnapshot=report.assembly.sourceGraph.filter(item=>/archive_v10|archive_parchment|layout\/custom_game\/archive\.xml/.test(item.path)).filter(item=>crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+item.path,'utf8').replace(/^\uFEFF/,'')).digest('hex')!==item.sha256).map(item=>item.path);
  assert.deepEqual(report.changedSinceSnapshot,[],'Final source files stayed frozen throughout capture');report.status='PASS_BROWSER_ARCHIVE_PARCHMENT_FINAL_VISUAL';
 }catch(error){report.status='FAIL_BROWSER_ARCHIVE_PARCHMENT_FINAL_VISUAL';report.failure=error.stack||String(error);try{report.failureSnapshot=await b.run('('+inspect.toString()+')()');await b.shot(out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2));b.close();}
 console.log('ARCHIVE_PARCHMENT_FINAL_VISUAL_PASS '+out+'/visual_report.json');
}
let settled=false;
process.on('beforeExit',()=>{if(!settled){console.error('ARCHIVE_PARCHMENT_FINAL_VISUAL_INCOMPLETE: Chrome/CDP exited before capture finished.');process.exitCode=1;}});
main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
