'use strict';
const fs=require('fs'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs'),{info,validate,validateTooltip,validateRewardArt,ready,assertFrozen,reportBase,sizes}=require('./acceptance.cjs');
const out='design_refs/lottery_gw2_v1/work/final';
async function main(){
 fs.mkdirSync(out,{recursive:true});const report=reportBase('lottery_gw2_final_visual_regression'),b=await browser(),artIds=new Set();
 try{
  const cases=[...sizes.map(([w,h])=>[w,h,'map','normal']),...[['cultivation','normal'],['dragon_knight','normal'],['summer','normal'],['map','details'],['cultivation','details'],['dragon_knight','details'],['summer','details'],['map','history'],['map','notice'],['map','result'],['cultivation','locked']].map(([pool,state])=>[1920,1080,pool,state])];
  for(const [width,height,pool,mode]of cases){await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b,pool,mode);const state=await info(b);validate(state,width,height,report.assetCount);if(mode==='details'){validateRewardArt(state.details);state.details.forEach(card=>artIds.add(card.item.id));}if(mode==='result')validateRewardArt(state.results);const name=pool+'_'+mode+'_'+width+'x'+height;await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(state,null,2));report.screens.push({name,width,height,pool,mode,canvas:state.canvas.bounds,assets:state.assets.length,detailRows:state.details.length,resultRows:state.results.length});}
  const expectedIds=[...new Set(require('./fixture.cjs').fixture().members.map(row=>row.item_id))].sort();assert.deepEqual([...artIds].sort(),expectedIds,'Every current formal reward uses its existing production art');report.rewardArt={uniqueItems:artIds.size,itemIds:[...artIds].sort(),scope:'Four active pools, actual renderer, unmodified formal fixture art IDs'};
  for(const [width,height]of [[1920,1080],[960,720]]){await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b,'map','details');await b.run('nodes.LotteryInfoList.Children().find(card=>card.BHasClass("LotteryDetailRow")).events.onmouseover();syncLayout();true');await sleep(300);const state=await info(b);validateTooltip(state,width,height);await b.shot(out+'/tooltip_'+width+'x'+height+'.png',{x:0,y:0,width,height});report.screens.push({name:'tooltip_'+width+'x'+height,bounds:state.tooltip.bounds,paint:state.tooltipPaint});}
  assertFrozen(report);report.status='PASS_BROWSER_LOTTERY_GW2_FINAL_VISUAL';
 }catch(error){report.status='FAIL_BROWSER_LOTTERY_GW2_FINAL_VISUAL';report.failure=error.stack||String(error);try{report.failureSnapshot=await info(b);await b.shot(out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2));b.close();}console.log('LOTTERY_GW2_FINAL_VISUAL_PASS '+out+'/visual_report.json');
}
let done=false;process.on('beforeExit',()=>{if(!done){console.error('LOTTERY_GW2_FINAL_VISUAL_INCOMPLETE');process.exitCode=1;}});main().then(()=>{done=true;},error=>{done=true;console.error(error.stack||error);process.exitCode=1;});
