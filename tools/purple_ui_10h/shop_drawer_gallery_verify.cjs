'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert'),crypto=require('crypto');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const base='design_refs/purple_ui_10h/work/shop_reference_drawer',input=base+'/Comparison.html';
let completed=false;process.on('beforeExit',()=>{if(!completed){console.error('SHOP_GALLERY_INCOMPLETE');process.exitCode=1;}});
(async()=>{
 const b=await browser();
 try{
  await b.call('Emulation.setDeviceMetricsOverride',{width:1440,height:1080,deviceScaleFactor:1,mobile:false});await b.go(input);
  const data=await b.run('D');assert.equal(data.records.length,48);
  const files=[...new Set(data.records.flatMap(r=>[r.image,r.before].filter(Boolean)))];assert.equal(files.length,72);
  for(const file of files)assert(fs.existsSync(path.join(base,file)),'Missing local gallery image '+file);
  const decoded=await b.run(`(async()=>{const files=${JSON.stringify(files)},rows=[];for(const src of files){const i=new Image();i.src=src;let error=null;try{await i.decode();}catch(e){error=String(e);}rows.push({src,complete:i.complete,width:i.naturalWidth,height:i.naturalHeight,error});}return rows;})()`);
  assert(decoded.every(r=>r.complete&&r.width>0&&r.height>0&&!r.error),'Gallery images failed actual Chrome decode');
  const selections=[];
  for(const record of data.records){
   const result=await b.run(`(async()=>{const r=${JSON.stringify(record)};byId('viewport').value=r.width+'x'+r.height;byId('category').value=r.category;byId('state').value=r.state;render();await Promise.all([...byId('stage').querySelectorAll('img')].map(i=>i.decode()));return {images:[...byId('stage').querySelectorAll('img')].map(i=>({src:i.getAttribute('src'),complete:i.complete,width:i.naturalWidth,height:i.naturalHeight})),slider:!!byId('slider').querySelector('input'),caption:byId('caption').textContent,scope:byId('scope').textContent};})()`);
   assert.deepEqual(result.images.map(i=>i.src),[record.image,...(record.before?[record.before]:[])]);assert(result.images.every(i=>i.complete&&i.width===record.width&&i.height===record.height));assert.equal(result.slider,!!record.before);
   if(record.before){const slider=await b.run(`(()=>{const i=byId('slider').querySelector('input');i.value=80;i.dispatchEvent(new Event('input'));return {line:byId('stage').querySelector('.line').style.left,clip:byId('stage').querySelector('.layer').style.clipPath};})()`);assert.equal(slider.line,'80%');assert(slider.clip.includes('20%'));result.sliderGeometry=slider;}
   selections.push({width:record.width,height:record.height,category:record.category,state:record.state,...result});
  }
  const links=await b.run('[...document.querySelectorAll("a")].map(a=>a.getAttribute("href"))');for(const href of links)assert(fs.existsSync(path.resolve(base,href)),'Missing local gallery link '+href);
  await b.run(`byId('viewport').value='1920x1080';byId('category').value='equipment';byId('state').value='normal';render();Promise.all([...byId('stage').querySelectorAll('img')].map(i=>i.decode())).then(()=>true)`);await b.shot(base+'/gallery_default_verified.png',{x:0,y:0,width:1440,height:1080});
  await b.run(`byId('viewport').value='1280x720';byId('category').value='challenge';byId('state').value='hover';render();Promise.all([...byId('stage').querySelectorAll('img')].map(i=>i.decode())).then(()=>true)`);await b.shot(base+'/gallery_720_challenge_verified.png',{x:0,y:0,width:1440,height:1080});
  const report={at:new Date().toISOString(),status:'PASS_ACTUAL_CHROME_SHOP_GALLERY',kind:'local browser production-component preview, not native game',html:input,htmlSha256:crypto.createHash('sha256').update(fs.readFileSync(input)).digest('hex'),currentSourceDigest:data.currentDigest,previousSourceDigest:data.previousDigest,uniqueDecodedImages:decoded.length,stateSelections:selections.length,pairedSameStateSelections:selections.filter(r=>r.slider).length,decoded,selections,localLinks:links,limitations:['Only normal/hover have truthful same-state previous images; slide states are new-only','Native game acceptance is separate and owned by root','Original conversation reference file is unavailable locally; no invented reference image']};
  fs.writeFileSync(base+'/gallery_verification.json',JSON.stringify(report,null,2));completed=true;console.log('SHOP_GALLERY_PASS images='+decoded.length+' selections='+selections.length+' sha='+report.htmlSha256);
 }finally{b.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
