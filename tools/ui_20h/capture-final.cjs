'use strict';
const fs=require('fs'),{browser}=require('../shop_ui_12h/cdp.cjs');
const base='design_refs/ui_20h/work',report=[];
(async()=>{const b=await browser();try{
 for(const edition of ['before','best'])for(const area of ['queue','archive'])for(const state of area==='queue'?['idle','waiting']:['normal','long']){
  await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:1910,y:1070});
  await b.go(`${base}/${edition==='before'?'preview_before':'preview'}/index.html`,`?page=${area==='archive'?'archive':''}&state=${state}`);
  const prefix=`${base}/final/${edition}_${area}_${state}`;
  await b.shot(prefix+'.png');
  const clip=await b.run(`(()=>{const r=nodes.${area==='queue'?'SurvivalProductionPanel':'ArchiveWindow'}.el.getBoundingClientRect();return {x:Math.max(0,r.x-8),y:Math.max(0,r.y-8),width:r.width+16,height:r.height+16};})()`);
  await b.shot(prefix+'_crop.png',clip);
  const target=await b.run(`(()=>{const r=document.querySelector('${area==='queue'?'.ProductionTrainingSlot':'.ArchiveCard'}').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...target});await b.shot(prefix+'_hover.png');
  report.push({edition,area,state,resolution:[1920,1080],kind:'production component preview on native battle backdrop',clip});
 }
 for(const state of ['single','full','types','costs','locked','complete','hero']){
  await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:1910,y:1070});await b.go(`${base}/preview/index.html`,'?state='+state);
  await b.shot(`${base}/final/best_queue_${state}.png`);
 }
 fs.writeFileSync(base+'/final/captures.json',JSON.stringify({at:new Date().toISOString(),scope:'Same viewport, sample data and background for before/after. Engine owned HUD/tooltip are stand-ins; native captures stored separately.',captures:report},null,2));
 console.log('UI20H_FINAL_COMPONENT_CAPTURES',report.length,'comparisons plus seven states');
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
