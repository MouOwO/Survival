'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
process.chdir(path.resolve(__dirname,'../..'));
const base='design_refs/daily_stargold_polish_20261019',n=Number(process.argv[2]);assert(Number.isInteger(n)&&n>=1&&n<=5);
const info=JSON.parse(fs.readFileSync(base+'/R'+n+'_changes.json','utf8'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
assert.equal(sha(fs.readFileSync(base+'/'+info.html)),info.hashes.html);assert.equal(sha(fs.readFileSync(base+'/'+info.css)),info.hashes.css);
const interval=setInterval(()=>{},1000),timeout=setTimeout(()=>{console.error('ROUND_CAPTURE_TIMEOUT');process.exit(1)},80000);
const report={status:'STARTING',round:n,name:info.name,at:new Date().toISOString(),kind:'isolated_browser_composition_preview',nativeGameCapture:false,productionFilesChanged:false};
async function main(){const b=await browser();try{
 await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
 await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1000,deviceScaleFactor:1,mobile:false});
 await b.go(base+'/'+info.html);await sleep(120);assert.equal(await b.run('window.designReady'),true);
 const state=await b.run(`(()=>{const d=window.designInspect(),rect=e=>e.getBoundingClientRect().toJSON(),grid=rect(document.querySelector('.calendar'));return {...d,round:document.body.dataset.round,grid,cards:[...document.querySelectorAll('.day')].map(c=>({day:c.dataset.day,bounds:rect(c),quantity:rect(c.querySelector('.quantity')),quantities:c.querySelectorAll('.quantity').length,slot:rect(c.querySelector('.slot'))})),glyphs:[...document.querySelectorAll('.action')].map(b=>{const a=b.getBoundingClientRect(),r=document.createRange();r.selectNodeContents(b.querySelector('span'));const t=r.getBoundingClientRect();return {id:b.id,dx:t.x+t.width/2-a.x-a.width/2,dy:t.y+t.height/2-a.y-a.height/2}}),claimToCalendarDx:rect(document.querySelector('#claim')).x+rect(document.querySelector('#claim')).width/2-grid.x-grid.width/2};})()`);
 assert.equal(state.round,String(n));assert.equal(state.days,28);assert.equal(state.monthly,3);assert.equal(state.today,'9');assert.equal(state.claimed,8);
 assert(state.window.x>=0&&state.window.right<=1600&&state.window.y>=0&&state.window.bottom<=1000);
 assert.deepEqual(state.images.filter(i=>!i.ok),[]);
 for(const image of state.images.filter(i=>i.src.startsWith('rewards/')))assert(image.display[0]<=image.native[0]&&image.display[1]<=image.native[1]);
 const xs=new Set(state.cards.map(c=>Math.round(c.bounds.x))),ys=new Set(state.cards.map(c=>Math.round(c.bounds.y)));assert.equal(xs.size,7);assert.equal(ys.size,4);
 for(const c of state.cards){assert.equal(c.quantities,1);assert(c.bounds.x>=state.grid.x-1&&c.bounds.right<=state.grid.right+1&&c.bounds.y>=state.grid.y-1&&c.bounds.bottom<=state.grid.bottom+1);assert(c.quantity.x>=c.slot.x&&c.quantity.right<=c.slot.right&&c.quantity.bottom<=c.slot.bottom);}
 for(const g of state.glyphs){assert(Math.abs(g.dx)<=1.5);assert(Math.abs(g.dy)<=3);}assert(Math.abs(state.claimToCalendarDx)<1);
 await b.shot(base+'/'+info.png,{x:0,y:0,width:1600,height:1000});
 const hover=async(selector,text)=>{const r=await b.run('document.querySelector('+JSON.stringify(selector)+').getBoundingClientRect().toJSON()');await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:r.x+r.width/2,y:r.y+r.height/2});await sleep(70);const tip=await b.run('(()=>{const e=document.querySelector(".tooltip");return {visible:getComputedStyle(e).display!=="none",text:e.textContent,bounds:e.getBoundingClientRect().toJSON(),color:getComputedStyle(e).backgroundColor}})()');assert(tip.visible&&tip.text.includes(text));assert(tip.bounds.x>=0&&tip.bounds.right<=1600&&tip.bounds.y>=0&&tip.bounds.bottom<=1000);return tip;};
 const dayTip=await hover('.day[data-day="9"]','回血碎片');if(n===5)await b.shot(base+'/R5_每日奖励悬浮说明.png',{x:0,y:0,width:1600,height:1000});
 const monthlyTip=await hover('.milestone[data-monthly="14"]','古树眷顾');if(n>=4)assert.equal(monthlyTip.color,'rgb(16, 21, 15)');
 if(n===5)await b.shot(base+'/R5_月卡奖励悬浮说明.png',{x:0,y:0,width:1600,height:1000});
 const interaction=await b.run('(()=>{document.getElementById("claim").click();document.getElementById("buy").click();document.getElementById("rules").click();const open=document.querySelector("dialog").open;document.getElementById("closeRules").click();return {claimed:claimPreviewApplied,pass:passPreviewApplied,claimDisabled:document.getElementById("claim").disabled,rules:open}})()');assert.deepEqual(interaction,{claimed:true,pass:true,claimDisabled:true,rules:true});
 assert.equal(sha(fs.readFileSync(base+'/'+info.html)),info.hashes.html);assert.equal(sha(fs.readFileSync(base+'/'+info.css)),info.hashes.css);
 Object.assign(report,{status:'PASS',state,dayTip,monthlyTip,interaction,screenshot:info.png});
 }catch(e){report.status='FAIL';report.error=e.stack;try{await b.shot(base+'/R'+n+'_failure.png')}catch{}throw e;}
 finally{b.close();fs.writeFileSync(base+'/R'+n+'_verification.json',JSON.stringify(report,null,2)+'\n');}
 console.log(JSON.stringify({status:report.status,round:n,name:info.name,days:28,monthly:3,mainButtonCentered:true,nativeIconsNotUpscaled:true,screenshot:info.png}));}
main().catch(e=>{console.error(e.stack||e);process.exitCode=1}).finally(()=>{clearInterval(interval);clearTimeout(timeout)});
