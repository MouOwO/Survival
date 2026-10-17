'use strict';
// Capture the named audit HTML only; this never sends an in-game request.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'output/wife_portraits_20261016/identity_preview');
async function main(){const b=await browser();try{
 await b.call('Emulation.setDeviceMetricsOverride',{width:1830,height:1110,deviceScaleFactor:1,mobile:false});
 await b.go(path.join(out,'index.html'));
 await b.run('document.fonts.ready.then(()=>Promise.all([...document.images].map(img=>img.decode()))).then(()=>true)');
 const rows=await b.run('Array.from(document.querySelectorAll("article")).map(card=>({id:card.dataset.id,name:card.querySelector("strong").textContent,decoded:!!card.querySelector("img").naturalWidth}))');
 assert.equal(rows.length,40);assert(rows.every(row=>row.decoded));
 const shot=await b.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});
 fs.writeFileSync(path.join(out,'all_40.png'),Buffer.from(shot.data,'base64'));
 fs.writeFileSync(path.join(out,'capture.json'),JSON.stringify({status:'PASS_IDENTITY_CONTACT_SHEET',notGameCapture:true,rows},null,2));
 console.log('PASS_IDENTITY_CONTACT_SHEET '+path.join(out,'all_40.png'));
 }finally{await b.close();}}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
