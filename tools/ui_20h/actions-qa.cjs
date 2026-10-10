'use strict';
const fs=require('fs'),assert=require('assert'),{browser}=require('../shop_ui_12h/cdp.cjs');
const out='design_refs/ui_20h/work/qa';
(async()=>{const b=await browser(),checks=[];try{
 for(const [width,height] of [[1280,720],[1920,1080],[2560,1440],[2560,1080]]){
  await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
  for(const layout of ['A','B'])for(const state of ['idle','costs']){
   await b.go('design_refs/ui_20h/work/preview/index.html',`?layout=${layout}&state=${state}`);
   const info=await b.run(`(()=>{const p=nodes.SurvivalProductionPanel;return {height:p.style.height,costClips:[...document.querySelectorAll('.ProductionTrainingCost')].filter(x=>!x.closest('[hidden]')).map(x=>{const a=x.getBoundingClientRect(),r=x.parentElement.getBoundingClientRect();return a.bottom-r.bottom;})};})()`);
   assert(info.costClips.every(x=>x<=1),JSON.stringify({width,layout,state,info}));
   assert.equal(info.height,state==='costs'?'278px':'256px');
   checks.push({resolution:[width,height],layout,state,...info});
  }
 }
 await b.go('design_refs/ui_20h/work/preview/index.html','?state=complete');
 assert.deepEqual(await b.run('cfg.SurvivalProductionHUD.Inspect().slots'),['train_lumberjack_02','train_lumberjack_03','train_lumberjack_04','train_lumberjack_05']);
 await b.run('setQueueState("waiting");emit("ui_selected_unit_stats_snapshot",{success:1,player_id:0,entindex:42,refresh_sequence:10,attack_speed:10});true');
 assert.equal(await b.run('cfg.SurvivalProductionHUD.Inspect().snapshot.training.queued.length'),3);
 await b.run('previewCalls=[];nodes.ProductionQueueSlot1.events.onactivate();true');assert.equal(await b.run('previewCalls.length'),0);
 await b.run(`window.selectedEntity=43;window.researchFixture={researching:1,started_at:90,finish_at:110,duration:20,display_name:'攻击科技',level:2,technology_group:'attack',active_job:{job_id:'r0',technology_group:'attack'},queue_capacity:7,queued:[1,2,3].map(i=>({job_id:'r'+i,technology_group:'attack',target_level:i+2,display_name:'攻击科技'}))};emit('ui_selected_unit_stats_snapshot',{success:1,player_id:0,entindex:43,research:researchFixture});cfg.SurvivalProductionHUD.Refresh(previewGeometry(),43,true,[]);previewCalls=[];nodes.ProductionQueueSlot1.events.onactivate();true`);
 let events=await b.run('previewCalls');assert.equal(events.length,1);assert.equal(events[0].name,'ui_research_cancel_request');assert.equal(events[0].payload.job_id,'r2');assert.equal(events[0].payload.source_entindex,43);
 await b.run(`researchFixture.queued=researchFixture.queued.filter(x=>x.job_id!=='r2');emit('ui_selected_unit_stats_snapshot',{success:1,player_id:0,entindex:43,research:researchFixture});previewCalls=[];nodes.ProductionCancelCurrent.events.onactivate();true`);
 events=await b.run('previewCalls');assert.equal(events.length,1);assert.equal(events[0].payload.job_id,'r0');
 assert.deepEqual(await b.run('cfg.SurvivalProductionHUD.Inspect().snapshot.research.queued.map(x=>x.job_id)'),['r1','r3']);
 await b.shot(out+'/research_cancel_middle.png');
 const cell=await b.run('(()=>{const r=nodes.ProductionQueueSlot0.el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()');
 await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...cell});await b.shot(out+'/research_hover_cancel.png');
 await b.go('design_refs/ui_20h/work/preview/index.html','?page=archive&state=long');
 const bg=await b.run('getComputedStyle(nodes.ArchiveTooltip.el).backgroundColor');assert(bg.startsWith('rgba(23, 61, 70'),bg);
 const shared=await b.run('({tooltip:nodes.ArchiveTooltip.BHasClass("JadeTooltip"),action:nodes.ArchiveDraw.BHasClass("JadeAction"),glow:[...document.querySelectorAll(".ArchiveNavGlow")].length})');assert(shared.tooltip&&shared.action&&shared.glow===7);
 fs.writeFileSync(out+'/actions.json',JSON.stringify({at:new Date().toISOString(),scope:'Browser production components; authoritative research updates simulated; no backend mutation',checks:['A/B cost containment at four resolutions','completed-level replacement','stat-only update retains queue','worker item remains non-cancelable under existing API','research middle and current cancellation: one event, exact ID','server order retained','shared tooltip/action and independent navigation glow'],cases:checks,shared},null,2));
 console.log('UI20H_ACTION_QA_PASS',checks.length,'layout cases plus contract checks');
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
