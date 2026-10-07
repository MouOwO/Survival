'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {browser}=require('./cdp.cjs');
const root=path.resolve('design_refs/shop_ui_12h'),dest=root+'/Delivery';
(async()=>{const b=await browser();try{
 await b.go(dest+'/index.html');
 await b.run(`document.querySelector('#reveal').value='27';document.querySelector('#reveal').dispatchEvent(new Event('input'));`);
 assert(await b.run(`document.querySelector('#compare').style.getPropertyValue('--reveal')==='27%'`));
 await b.run(`document.querySelector('[data-state="long"]').click();document.querySelector('#resolution').value='2560x1080';document.querySelector('#resolution').dispatchEvent(new Event('change'));`);
 assert(await b.run(`document.querySelector('#resolutionImage').src.endsWith('qa_2560x1080_long.png')`));
 await b.run(`document.querySelector('#resolutionImage').decode()`);
 // PNG crops come from the native capture, without repainting or retouching the game UI.
 const crops={native_header:[315,93,858,126],native_sidebar:[294,175,66,527],native_card_normal:[333,207,206,241],native_card_hover:[541,207,206,241]};
 for(const [id,[x,y,w,h]]of Object.entries(crops)){
  const name=id==='native_card_hover'?'native_final_hover':'native_final_normal';
  const source='data:image/png;base64,'+fs.readFileSync(root+'/work/production/'+name+'.png').toString('base64');
  const png=await b.run(`(async()=>{const i=new Image();i.src=${JSON.stringify(source)};await i.decode();const c=document.createElement('canvas');c.width=${w};c.height=${h};c.getContext('2d').drawImage(i,${x},${y},${w},${h},0,0,${w},${h});return c.toDataURL('image/png').split(',')[1]})()`);
  fs.writeFileSync(root+'/work/production/'+id+'.png',Buffer.from(png,'base64'));
 }
 await b.go(dest+'/index.html');
 const images=await b.run(`Promise.all([...document.images].map(async i=>{i.loading='eager';try{await i.decode();return true;}catch(e){return i.src;}}))`);
 assert(images.every(v=>v===true),'Gallery missing image: '+JSON.stringify(images.filter(v=>v!==true)));
 fs.writeFileSync(dest+'/compare-export.html',`<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#f7f7ef;color:#244554;font:24px system-ui}.board{display:flex;gap:24px;padding:24px}.side{width:1280px}.side p{margin:0 0 12px}img{display:block;width:1280px;height:800px}</style><div class="board"><div class="side"><p>修改前 · 同一测试局 / 科技首屏</p><img src="../work/production/native_before.png"></div><div class="side"><p>最佳版 B17 + L21 + T23 · 真实游戏 1280×800 / 无订单</p><img src="../work/production/native_final_normal.png"></div></div>`);
 await b.call('Emulation.setDeviceMetricsOverride',{width:2632,height:902,deviceScaleFactor:1,mobile:false});await b.go(dest+'/compare-export.html');await b.shot(dest+'/native_before_after.png');
 // Render a compact sheet for human inspection of every required viewport.
 const sizes=['1280x720','1920x1080','2560x1440','2560x1080'];
 fs.writeFileSync(dest+'/viewport-export.html',`<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#f7f7ef;color:#244554;font:21px system-ui}.grid{display:grid;grid-template-columns:1fr 1fr;gap:22px;padding:24px}p{margin:0 0 10px}img{display:block;width:924px;height:520px;object-fit:contain;background:#173944}</style><div class="grid">${sizes.map(r=>`<div><p>${r} · 浏览器生产组件预览</p><img src="../work/production/qa_${r}_normal.png"></div>`).join('')}</div>`);
 await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1180,deviceScaleFactor:1,mobile:false});await b.go(dest+'/viewport-export.html');await b.shot(dest+'/viewport_contact_sheet.png');
 await b.call('Emulation.setDeviceMetricsOverride',{width:1440,height:1080,deviceScaleFactor:1,mobile:false});await b.go(dest+'/index.html');await b.shot(dest+'/gallery_preview.png',{x:0,y:0,width:1440,height:1000});
 fs.writeFileSync(dest+'/gallery_checks.json',JSON.stringify({at:new Date().toISOString(),images:'PASS',compareSlider:'PASS',resolutionStateTabs:'PASS',nativeCrops:'unmodified source pixels',viewportSheet:'browser only'},null,2));
 console.log('DELIVERY_IMAGES_PASS: native comparison/crops, 4 viewport sheet, gallery images/controls');
 }finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
