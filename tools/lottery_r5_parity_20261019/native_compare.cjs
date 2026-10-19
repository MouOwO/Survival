'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {browser,sleep}=require('../lottery_emerald_game_20261019/browser.cjs');
const repo=process.cwd(),out=path.resolve('output/lottery_r5_parity_20261019/native_review');
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const rel=file=>path.relative(repo,file).replaceAll('\\','/');
const reference=path.resolve('design_refs/lottery_emerald_buttons_20261019/round_5.html');
async function prepareReferences(b){
 const before=hash(reference);await b.call('Emulation.setDeviceMetricsOverride',{width:1725,height:1200,deviceScaleFactor:1,mobile:false});
 for(const count of [1,10]){
  await b.go(reference,'?scheme=r5');
  await b.run('lotteryDemoAPI.setScheme("r5");lotteryDemoAPI.setPool("map");lotteryDemoAPI.setSkipAnimation(true);lotteryDemoAPI.draw('+count+');lotteryDemoAPI.finishAnimation()');
  await b.run('document.fonts.ready.then(()=>Promise.all([...document.querySelectorAll("#mainCanvas img")].map(i=>i.decode().catch(()=>false))))');await sleep(250);
  const state=await b.run('(()=>{const r=document.querySelector("#mainCanvas .lottery-scene").getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height,results:document.querySelectorAll("#mainCanvas .result-item").length}})()');
  assert.equal(state.results,count,'Reference uses its real local result layout');
  const shot=await b.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:state.x,y:state.y,width:state.width,height:state.height,scale:1672/state.width}});
  fs.writeFileSync(path.join(out,'reference_result_'+count+'.png'),Buffer.from(shot.data,'base64'));
 }
 assert.equal(hash(reference),before,'Approved HTML unchanged');
}
async function compare(b,native,kind){
 native=path.resolve(native);assert(native.startsWith(repo+path.sep),'Native screenshot inside workspace');
 const data=fs.readFileSync(native),width=data.readUInt32BE(16),height=data.readUInt32BE(20);
 const result=kind!=='main',scale=Math.min(width/(result?1672:1920),height/(result?941:1080));
 const crop={x:(width-1672*scale)/2,y:(height-941*scale)/2,width:1672*scale,height:941*scale};
 const ref=result?path.join(out,'reference_result_'+(kind==='single'?1:10)+'.png'):path.resolve('output/lottery_r5_parity_20261019/reference_stage_disabled.png');
 assert(fs.existsSync(ref));
 const configuration={native:pathToFileURL(native).href,reference:pathToFileURL(ref).href,crop,kind};
 const html='<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#0e1915}canvas{display:block}</style><canvas id="c" width="3344" height="981"></canvas><script>const cfg='+JSON.stringify(configuration)+';Promise.all([cfg.reference,cfg.native].map(src=>new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=reject;i.src=src}))).then(([r,n])=>{const c=document.getElementById("c").getContext("2d");c.fillStyle="#101c17";c.fillRect(0,0,3344,981);c.fillStyle="#e5eadb";c.font="22px Microsoft YaHei,Arial";c.fillText("批准 R5 参考",18,29);c.fillText("原生实机 · "+cfg.kind+" · 原背景 / 实际券数状态",1690,29);c.drawImage(r,0,40,1672,941);const p=cfg.crop;c.drawImage(n,p.x,p.y,p.width,p.height,1672,40,1672,941);window.comparisonReady=true}).catch(e=>window.comparisonError=String(e))</script>';
 const htmlPath=path.join(out,'compare_'+kind+'.html');fs.writeFileSync(htmlPath,html);
 await b.call('Emulation.setDeviceMetricsOverride',{width:3344,height:981,deviceScaleFactor:1,mobile:false});await b.go(htmlPath);assert(await b.run('window.comparisonReady===true'),'Comparison images decoded');
 const output=path.join(out,'native_vs_R5_'+kind+'.png');await b.shot(output,3344,981);
 return {kind,native:rel(native),nativeSha256:hash(native),reference:rel(ref),referenceSha256:hash(ref),output:rel(output),outputSha256:hash(output),nativeCanvasCrop:crop,method:'Crop and uniform scaling only; native pixels are not redrawn, retouched or recolored.',status:'REQUIRES_VISUAL_REVIEW',limitations:['Original scene retained; the large T10 is intentionally absent.','Actual zero tickets keep native actions unavailable.','Result samples do not deduct tickets or issue rewards.']};
}
async function main(){fs.mkdirSync(out,{recursive:true});const args=process.argv.slice(2);assert(args.length&&args.length%2===0,'Pairs: main|single|ten native.png');const pairs=[];for(let i=0;i<args.length;i+=2){assert(['main','single','ten'].includes(args[i]));pairs.push([args[i],args[i+1]]);}const b=await browser();try{await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});if(pairs.some(p=>p[0]!=='main'))await prepareReferences(b);const records=[];for(const [kind,file]of pairs)records.push(await compare(b,file,kind));const sources=['panorama/src/scripts/custom_game/lottery_gw2.js','panorama/src/styles/custom_game/lottery_gw2.css'].map(file=>({path:file,sha256:hash(file)}));fs.writeFileSync(path.join(out,'comparison_manifest.json'),JSON.stringify({at:new Date().toISOString(),referenceHtml:rel(reference),referenceHtmlSha256:hash(reference),sourceAtComparisonTime:sources,records},null,2));console.log('NATIVE_REFERENCE_COMPARISON_READY '+records.map(r=>r.output).join(' '));}finally{b.close();}}
main().catch(e=>{console.error(e.stack||e);process.exitCode=1});
