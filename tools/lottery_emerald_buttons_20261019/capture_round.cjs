'use strict';
const fs=require('node:fs'),path=require('node:path');
const {browser,sleep}=require('../market_filter_20261017/browser.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/lottery_emerald_buttons_20261019/rounds'),html=path.join(root,'design_refs/lottery_emerald_buttons_20261019/幽林翡翠_按钮五轮优化.html');
async function capture(){
 const round=process.argv[2]||'r1',preview=process.argv[3]||'normal',suffix=preview==='normal'?round:round+'_'+preview,b=await browser();fs.mkdirSync(out,{recursive:true});
 try{
  await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:1,mobile:false});await b.go(html,'?scheme='+round);await sleep(100);
  if(preview!=='normal'){await b.run('emeraldReviewAPI.setButtonState('+JSON.stringify(preview)+')');await sleep(180);}
  const state=await b.run(`(()=>{const r=e=>e.getBoundingClientRect().toJSON(),s=e=>getComputedStyle(e),root=document.querySelector('#mainCanvas .lottery-scene'),buttons=[...root.querySelectorAll('.draw-action')];return{errors:[],round:lotteryDemoAPI.getState().scheme,stage:r(document.getElementById('stageHost')),buttons:buttons.map(e=>({rect:r(e),width:s(e).width,height:s(e).height,text:e.innerText,label:s(e.querySelector('.draw-label')).fontSize,cost:s(e.querySelector('.draw-cost')).fontSize,image:r(e.querySelector('.draw-cost img')),background:s(e).backgroundImage})),rewardRects:[...root.querySelectorAll('.preview-reward')].map(r)};})()`);
  if(state.buttons.length!==2||state.buttons.some(b=>b.height!=='84px'))throw Error('Button height incorrect');
  const [single,ten]=state.buttons;if(single.rect.right>=ten.rect.x||Math.abs(single.rect.bottom-ten.rect.bottom)>1)throw Error('Button alignment failure');
  if(state.rewardRects.some(r=>r.right>single.rect.x&&r.y<single.rect.bottom&&r.bottom>single.rect.y))throw Error('Button overlaps rewards');
  const clip=state.stage,shot=await b.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:clip.x,y:clip.y,width:clip.width,height:clip.height,scale:1}});fs.writeFileSync(path.join(out,suffix+'_stage.png'),Buffer.from(shot.data,'base64'));
  const left=single.rect.x-14,top=Math.min(single.rect.y,ten.rect.y)-42,right=ten.rect.right+14,bottom=Math.max(single.rect.bottom,ten.rect.bottom)+14;
  const close=await b.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:left,y:top,width:right-left,height:bottom-top,scale:2}});fs.writeFileSync(path.join(out,suffix+'_buttons.png'),Buffer.from(close.data,'base64'));
  fs.writeFileSync(path.join(out,suffix+'.json'),JSON.stringify({...state,preview},null,2));console.log('EMERALD_ROUND_CAPTURE_PASS '+suffix);
 }finally{b.close();}
}
let settled=false;process.on('beforeExit',()=>{if(!settled)process.exitCode=1;});capture().then(()=>{settled=true;},e=>{settled=true;console.error(e.stack||e);process.exitCode=1;});
