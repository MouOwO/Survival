'use strict';
// Read-only acceptance of the production pass header and full shared tooltip.
const fs=require('node:fs'),assert=require('node:assert/strict'),{browser}=require('../shop_ui_12h/cdp.cjs');
const input=process.argv[2]||'design_refs/menus_v10/work/pass_milestones_preview',out=process.argv[3]||'design_refs/menus_v10/work/pass_milestones';
(async()=>{const b=await browser(),results=[];try{
for(const [width,height]of [[1280,720],[1920,1080]]){
await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(input+'/index.html','?page=daily&state=pass');assert(await b.run('previewReady'));await b.run('syncLayout();true');
const result=await b.run(`(()=>{const title=[...document.querySelectorAll('.DailyV10Milestone')],status=[...document.querySelectorAll('.DailyV10MilestoneStatus')],bounds=p=>p.getBoundingClientRect().toJSON();return {errors:previewErrors,content:bounds(nodes.DailySpecials.el),titles:title.map(p=>({text:p.textContent,rect:bounds(p),width:p.scrollWidth,client:p.clientWidth})),states:status.map(p=>({text:p.textContent,rect:bounds(p)}))};})()`);
assert.deepEqual(result.errors,[]);assert.deepEqual(result.titles.map(p=>p.text),['7次奖励','14次奖励','21次奖励']);assert.deepEqual(result.states.map(p=>p.text),['未领取','未领取','未领取']);
for(let i=0;i<result.titles.length;i++){const title=result.titles[i],state=result.states[i];assert(title.width<=title.client,'short milestone fits the fixed cell');assert(title.rect.top>=result.content.top,'title stays within the scrolling content');assert(title.rect.bottom<=state.rect.top,'title and claim state have separate lines');if(i)assert(result.titles[i-1].rect.right<=title.rect.left+6,'fixed columns remain separate');}
await b.shot(out+'/pass_'+width+'x'+height+'.png',{x:0,y:0,width,height});results.push({width,height,...result});
if(width===1920){await b.run(`(()=>{nodes.DailySpecials.Children()[0].events.onmouseover();syncLayout();return true;})()`);await b.run('new Promise(r=>setTimeout(r,200)).then(()=>{syncLayout();return true;})');const text=await b.run('nodes.DailyTooltipEffect.text');assert(text.includes('领取条件：累计签到7次'));assert(text.includes('领取状态：未领取'));await b.shot(out+'/pass_tooltip.png',{x:0,y:0,width,height});results.push({kind:'full_tooltip',text});}
}
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(out+'/report.json',JSON.stringify({at:new Date().toISOString(),kind:'production_component_browser_preview',notGameCapture:true,sourceAssembly:input+'/assembly.json',results},null,2));console.log('PASS_MILESTONE_REVIEW_PASS '+out);
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
