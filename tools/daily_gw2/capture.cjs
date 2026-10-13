'use strict';
// Lightweight final visual check; the full isolated interaction suite is separate.
const fs=require('fs'),crypto=require('crypto'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs'),{inspect,validate,inViewport,ready}=require('./acceptance.cjs');
const base='design_refs/daily_gw2_v1/work',out=base+'/final';
async function main(){
 fs.mkdirSync(out,{recursive:true});const manifest=fs.readFileSync('tools/daily_gw2/asset_manifest.json'),assetCount=Object.keys(JSON.parse(manifest).assets).length;
 const report={at:new Date().toISOString(),kind:'daily_gw2_final_visual_regression',notGameCapture:true,fixtureOnly:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),businessValidation:base+'/browser/report.json',assetManifestSha256:crypto.createHash('sha256').update(manifest).digest('hex'),screens:[]};
 const b=await browser();
 try{
  for(const [width,height,mode] of [[1280,720,'normal'],[1920,1080,'normal'],[2560,1440,'normal'],[2560,1080,'normal'],[960,720,'normal'],[1920,1080,'pass']]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b,mode);
   const state=await b.run('('+inspect.toString()+')()');validate(state,width,height,assetCount);
   const name=(mode==='pass'?'pass':'daily')+'_'+width+'x'+height;await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(state,null,2));report.screens.push({name,width,height,mode,canvas:state.canvas.bounds,blueFrames:state.blueFrames.map(frame=>frame.bounds),notice:state.notice.bounds,decodedAssets:state.assets.length});
  }
  for(const [width,height,mode,day] of [[1920,1080,'normal',3],[960,720,'normal',28]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b,mode);await b.run('nodes.DailyGW2Day_'+day+'.events.onmouseover();syncLayout();true');await new Promise(resolve=>setTimeout(resolve,430));
   const state=await b.run('('+inspect.toString()+')()');assert(state.tooltip.visible);inViewport(state.tooltip.bounds,width,height,'Daily reward tooltip');assert(state.tooltipTitle.text.includes('第'+day+'天'));await b.shot(out+'/tooltip_'+width+'x'+height+'.png',{x:0,y:0,width,height});report.screens.push({name:'tooltip_'+width+'x'+height,width,height,tooltip:state.tooltip.bounds});
  }
  report.changedSinceSnapshot=report.assembly.sourceGraph.filter(item=>/daily_|layout\/custom_game\/archive\.xml/.test(item.path)).filter(item=>crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+item.path,'utf8').replace(/^\uFEFF/,'')).digest('hex')!==item.sha256).map(item=>item.path);assert.deepEqual(report.changedSinceSnapshot,[],'Final daily production sources remained frozen');assert.equal(crypto.createHash('sha256').update(fs.readFileSync('tools/daily_gw2/asset_manifest.json')).digest('hex'),report.assetManifestSha256,'Final assets remained frozen');report.status='PASS_BROWSER_DAILY_GW2_FINAL_VISUAL';
 }catch(error){report.status='FAIL_BROWSER_DAILY_GW2_FINAL_VISUAL';report.failure=error.stack||String(error);try{report.failureSnapshot=await b.run('('+inspect.toString()+')()');await b.shot(out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2));b.close();}
 console.log('DAILY_GW2_FINAL_VISUAL_PASS '+out+'/visual_report.json');
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('DAILY_GW2_FINAL_VISUAL_INCOMPLETE: Chrome/CDP ended before capture finished.');process.exitCode=1;}});main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
