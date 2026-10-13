'use strict';
// Final lightweight visual checks; full interactions are covered by acceptance.
const fs=require('fs'),crypto=require('crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs'),{info,validate,validateTooltip,assetMetrics,ready,shot,assertFrozen,sizes}=require('./acceptance.cjs');
const base='design_refs/collection_gw2_v2/work',out=base+'/final';
async function main(){
 fs.mkdirSync(out,{recursive:true});const manifest=fs.readFileSync('tools/collection_gw2/asset_manifest.json'),assetCount=Object.keys(JSON.parse(manifest).assets).length;
 const report={at:new Date().toISOString(),kind:'collection_gw2_final_visual_regression',notGameCapture:true,fixtureOnly:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),businessValidation:base+'/browser/report.json',assetManifestSha256:crypto.createHash('sha256').update(manifest).digest('hex'),screens:[]};
 report.harnessCaptionOmittedWhenOverlayingCanvas=true;report.assetMetrics=assetMetrics();const b=await browser();
 try{
  for(const [width,height,category]of [...sizes.map(size=>[...size,'ex']),[1920,1080,'friend'],[1920,1080,'wife']]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b,category);const state=await info(b);validate(state,width,height,assetCount,category==='wife'?0:40);const name=category+'_'+width+'x'+height;await shot(b,out+'/'+name+'.png',{x:0,y:0,width,height});fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(state,null,2));report.screens.push({name,width,height,category,canvas:state.canvas.bounds,slots:state.slots.length,portraits:state.images.length,decodedAssets:state.assets.length,backgroundOpacity:state.background.opacity,effectiveBackgroundAlpha:state.background.opacity*report.assetMetrics.window_background.center.alphaMean/255});
  }
  for(const [width,height]of [[1920,1080],[960,720],[815,528]]){await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b,'ex');await b.run('nodes.CollectionGW2Item_ex_14.events.onmouseover();syncLayout();true');await sleep(300);const state=await info(b);validateTooltip(state,width,height);await shot(b,out+'/tooltip_'+width+'x'+height+'.png',{x:0,y:0,width,height});report.screens.push({name:'tooltip_'+width+'x'+height,width,height,bounds:state.tooltip.bounds,paint:state.tooltipPaint});}
  assertFrozen(report);report.status='PASS_BROWSER_COLLECTION_GW2_FINAL_VISUAL';
 }catch(error){report.status='FAIL_BROWSER_COLLECTION_GW2_FINAL_VISUAL';report.failure=error.stack||String(error);try{report.failureSnapshot=await info(b);await shot(b,out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2));b.close();}
 console.log('COLLECTION_GW2_FINAL_VISUAL_PASS '+out+'/visual_report.json');
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('COLLECTION_GW2_FINAL_VISUAL_INCOMPLETE: Chrome/CDP ended before capture.');process.exitCode=1;}});main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
