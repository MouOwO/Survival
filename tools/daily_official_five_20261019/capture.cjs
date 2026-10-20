'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
process.chdir(path.resolve(__dirname,'../..'));
const base='design_refs/daily_official_five_20261019';
const manifest=JSON.parse(fs.readFileSync(base+'/manifest.json','utf8'));
const keepAlive=setInterval(()=>{},1000),deadline=setTimeout(()=>{console.error('DAILY_FIVE_CAPTURE_TIMEOUT');process.exit(1);},160000);
const report={status:'STARTING',at:new Date().toISOString(),kind:'isolated_official_component_design_previews',nativeGameCapture:false,productionFilesChanged:false,cases:[]};
fs.writeFileSync(base+'/verification.json',JSON.stringify(report,null,2));
async function main(){const b=await browser();
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1000,deviceScaleFactor:1,mobile:false});
  for(const design of manifest.designs){
   await b.go(base+'/'+design.html);await sleep(180);
   const state=await b.run('window.designInspect()');
   assert.equal(state.theme,design.key);assert.equal(state.days,28);assert.equal(state.monthly,3);assert.equal(state.claimed,8);assert.equal(state.today,'9');
   assert(state.window.x>=0&&state.window.y>=0&&state.window.right<=1600&&state.window.bottom<=1000);
   assert.deepEqual(state.images.filter(i=>!i.ok),[],'Every native reward/control icon decodes');
   for(const img of state.images.filter(i=>i.src.startsWith('rewards/'))){assert(img.display[0]<=img.native[0]&&img.display[1]<=img.native[1],'Native reward art is never upscaled');}
   for(const button of state.buttons){assert.equal(button.centerDx,0);assert.equal(button.centerDy,0);}
   const layout=await b.run(`(()=>{const nodes=[...document.querySelectorAll('.day')],rect=n=>n.getBoundingClientRect().toJSON(),grid=rect(document.querySelector('.calendar'));return {grid,days:nodes.map(n=>({day:n.dataset.day,bounds:rect(n)})),glyphs:[...document.querySelectorAll('.action')].map(b=>{const r=b.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(b.querySelector('span'));const t=range.getBoundingClientRect();return {id:b.id,dx:t.x+t.width/2-r.x-r.width/2,dy:t.y+t.height/2-r.y-r.height/2}})};})()`);
   for(const day of layout.days){assert(day.bounds.x>=layout.grid.x-1&&day.bounds.right<=layout.grid.right+1);assert(day.bounds.y>=layout.grid.y-1&&day.bounds.bottom<=layout.grid.bottom+1);}
   const xs=new Set(layout.days.map(d=>Math.round(d.bounds.x))),ys=new Set(layout.days.map(d=>Math.round(d.bounds.y)));assert.equal(xs.size,7);assert.equal(ys.size,4);
   for(const glyph of layout.glyphs){assert(Math.abs(glyph.dx)<=1.5,'Button text is centered horizontally');assert(Math.abs(glyph.dy)<=3,'Button text is centered vertically');}
   await b.shot(base+'/'+design.screenshot,{x:0,y:0,width:1600,height:1000});
   const anchor=layout.days.find(d=>d.day==='9').bounds;
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:anchor.x+anchor.width/2,y:anchor.y+anchor.height/2});await sleep(70);
   const tooltip=await b.run(`(()=>{const p=document.querySelector('.tooltip'),r=p.getBoundingClientRect();return {visible:getComputedStyle(p).display!=='none',text:p.textContent,bounds:r.toJSON()};})()`);
   assert(tooltip.visible&&tooltip.text.includes('回血碎片'));assert(tooltip.bounds.x>=0&&tooltip.bounds.right<=1600&&tooltip.bounds.y>=0&&tooltip.bounds.bottom<=1000);
   if(design.key==='crownfall')await b.shot(base+'/02_倾天秘卷_悬浮说明.png',{x:0,y:0,width:1600,height:1000});
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:20,y:20});
   const interactions=await b.run(`(()=>{document.getElementById('claim').click();document.getElementById('buy').click();document.getElementById('rules').click();const rules=document.querySelector('dialog').open;document.getElementById('closeRules').click();return {claimed:window.claimPreviewApplied,pass:window.passPreviewApplied,claimDisabled:document.getElementById('claim').disabled,passActive:document.querySelector('.pass-panel').classList.contains('pass-active'),rules};})()`);
   assert.deepEqual(interactions,{claimed:true,pass:true,claimDisabled:true,passActive:true,rules:true});
   report.cases.push({id:design.id,name:design.name,...state,layout,tooltip,interactions,screenshot:design.screenshot});
   console.log('DAILY_OFFICIAL_DESIGN_PASS '+design.id+' '+design.name);
  }
  const overview='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><style>*{box-sizing:border-box}body{margin:0;background:#101820;color:#e6e1d4;font-family:"Microsoft YaHei",sans-serif}header{padding:22px 26px 10px}h1{margin:0 0 5px;font-size:25px;font-weight:500}p{margin:0;font-size:13px;color:#b6c2c9}.grid{padding:18px 22px 24px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.card{margin:0;border:1px solid #53616a;background:#172530;overflow:hidden}.card img{display:block;width:100%;aspect-ratio:8/5;object-fit:contain}.card figcaption{padding:9px 13px;display:flex;justify-content:space-between;align-items:center}.card b{font-size:17px;font-weight:500;color:#e7c78e}.card span{font-size:11px;color:#b4c3cb}.card:last-child{grid-column:1 / -1;width:calc(50% - 9px);justify-self:center}</style><header><h1>每日登录奖励 · 五套官方组件方案</h1><p>相同奖励、相同签到进度、相同 7 × 4 日历与月卡结构，选择你喜欢的组件风格。</p></header><div class="grid">'+manifest.designs.map(d=>'<figure class="card"><img src="'+d.screenshot+'" alt="'+d.name+'"><figcaption><b>'+d.id+' · '+d.name+'</b><span>'+d.subtitle+'</span></figcaption></figure>').join('')+'</div></html>';
  fs.writeFileSync(base+'/overview.html',overview);await b.go(base+'/overview.html');
  const overviewState=await b.run('({width:document.documentElement.clientWidth,height:document.body.scrollHeight,decoded:[...document.images].every(i=>i.complete&&i.naturalWidth>0)})');assert(overviewState.decoded);await b.shot(base+'/五套方案对比总览.png',{x:0,y:0,width:1600,height:overviewState.height});report.overview=overviewState;
  await b.go(base+'/index.html');
  const gallery=await b.run(`(()=>{const buttons=[...document.querySelectorAll('[data-theme]')];buttons[4].click();return {count:buttons.length,selected:document.querySelector('[data-theme].selected').dataset.theme,src:document.querySelector('iframe').getAttribute('src'),width:document.querySelector('.frame').getBoundingClientRect().width};})()`);assert.equal(gallery.count,5);assert.equal(gallery.selected,'05');assert(gallery.src.startsWith('05_'));report.gallery=gallery;
  report.status='PASS';
 }catch(error){report.status='FAIL';report.error=error.stack;try{await b.shot(base+'/capture_failure.png');}catch{}throw error;}
 finally{b.close();fs.writeFileSync(base+'/verification.json',JSON.stringify(report,null,2)+'\n');}
 console.log(JSON.stringify({status:report.status,designs:report.cases.length,nativeRewardsNeverUpscaled:true,buttonsCentered:true,overview:base+'/五套方案对比总览.png'}));
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;}).finally(()=>{clearInterval(keepAlive);clearTimeout(deadline);});
