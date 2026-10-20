'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
process.chdir(path.resolve(__dirname,'../..'));
const base='design_refs/daily_stargold_polish_20261019';
const keepAlive=setInterval(()=>{},1000),timeout=setTimeout(()=>{console.error('GALLERY_CAPTURE_TIMEOUT');process.exit(1)},80000);
async function main(){const b=await browser();try{
await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
await b.call('Emulation.setDeviceMetricsOverride',{width:1800,height:1100,deviceScaleFactor:1,mobile:false});
const sheets=[];
for(const [html,png,count] of [['overview.html','五轮优化对比总览.png',6],['before_after.html','原版与第5轮对比.png',2]]){
 await b.go(base+'/'+html);
 const data=await b.run('({width:document.documentElement.scrollWidth,height:document.documentElement.scrollHeight,images:[...document.images].map(i=>({ok:i.complete&&i.naturalWidth===1600&&i.naturalHeight===1000,src:i.getAttribute("src")})),cards:document.querySelectorAll(".card").length})');
 assert.equal(data.cards,count);assert.equal(data.images.length,count);assert(data.images.every(i=>i.ok));assert.equal(data.width,1800);
 await b.shot(base+'/'+png,{x:0,y:0,width:data.width,height:data.height});sheets.push({html,png,width:data.width,height:data.height});
}
await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1150,deviceScaleFactor:1,mobile:false});
await b.go(base+'/index.html');
const waitPreview=async n=>{for(let i=0;i<80;i++){
 const tree=await b.call('Page.getFrameTree');const child=tree.frameTree.childFrames?.[0]?.frame;
 if(child&&child.url==='about:srcdoc'){
  const ctx=await b.call('Page.createIsolatedWorld',{frameId:child.id,worldName:'gallery_verification'});
  const r=await b.call('Runtime.evaluate',{contextId:ctx.executionContextId,expression:'({ready:document.readyState,round:document.body.dataset.round||"0",days:document.querySelectorAll(".day").length,images:[...document.images].every(i=>i.complete&&i.naturalWidth>0),body:document.body.getBoundingClientRect().toJSON()})',returnByValue:true});
  const v=r.result?.value;if(v?.ready==='complete'&&v.round===String(n)&&v.images&&(n?v.days===28:true)){await sleep(150);return v;}
 }
 await sleep(80);
}throw new Error('Preview iframe did not load for round '+n);};
await waitPreview(5);
const initial=await b.run('({ready:window.galleryReady,round:document.body.dataset.round,buttons:document.querySelectorAll(".tabs button").length,selected:document.querySelector(".tabs .selected").dataset.round,src:document.querySelector("iframe").dataset.source,images:[...document.images].every(i=>i.complete&&i.naturalWidth>0),width:document.documentElement.scrollWidth,clientWidth:document.documentElement.clientWidth})');
assert(initial.ready&&initial.images);assert.equal(initial.round,'5');assert.equal(initial.selected,'5');assert.equal(initial.buttons,6);assert.equal(initial.src,'R5_星穹鎏金.html');assert.equal(initial.width,initial.clientWidth);
const switches=[];
for(const n of [0,1,2,3,4,5]){await b.run('document.querySelector(\'.tabs button[data-round="'+n+'"]\').click()');const preview=await waitPreview(n);const d=await b.run('({round:document.body.dataset.round,selected:document.querySelector(".tabs .selected").dataset.round,src:document.querySelector("iframe").dataset.source,link:document.getElementById("single").getAttribute("href")})');assert.equal(d.round,String(n));assert.equal(d.selected,String(n));assert.equal(d.src,d.link);switches.push({...d,preview});}
await sleep(150);
const frameGeometry=await b.run('(()=>{const e=document.querySelector("iframe"),h=document.querySelector(".frame");return {frame:e.getBoundingClientRect().toJSON(),host:h.getBoundingClientRect().toJSON(),transform:e.style.transform,scrollY,frameDisplay:getComputedStyle(e).display,frameVisibility:getComputedStyle(e).visibility}})()');
assert.equal(frameGeometry.frameDisplay,'block');assert.equal(frameGeometry.frameVisibility,'visible');assert(frameGeometry.frame.width>1500&&frameGeometry.frame.height>900);
await b.shot(base+'/交互对比页.png',{x:0,y:0,width:1600,height:Math.ceil(frameGeometry.host.bottom)+16});
const report={status:'PASS',at:new Date().toISOString(),initial,switches,sheets,frameGeometry};fs.writeFileSync(base+'/gallery_verification.json',JSON.stringify(report,null,2)+'\n');
const completion=JSON.parse(fs.readFileSync(base+'/completion.json','utf8'));completion.status='PASS';completion.galleryVerification='gallery_verification.json';fs.writeFileSync(base+'/completion.json',JSON.stringify(completion,null,2)+'\n');
console.log(JSON.stringify({status:'PASS',rounds:5,selectors:6,defaultRound:5,contactSheets:sheets}));
}finally{b.close();}}
main().catch(e=>{console.error(e.stack||e);process.exitCode=1}).finally(()=>{clearInterval(keepAlive);clearTimeout(timeout)});
