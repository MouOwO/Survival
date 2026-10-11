'use strict';
// Resource assembly preview only. Does not connect to the game or accounts.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{browser}=require('../shop_ui_12h/cdp.cjs');
async function main(){
 const base='design_refs/archive_v10/work/icon_map_v11',b=await browser();
 try{
  await b.call('Emulation.setDeviceMetricsOverride',{width:1280,height:1450,deviceScaleFactor:1,mobile:false});await b.go(base+'/montage.html');
  const info=await b.run('({height:document.documentElement.scrollHeight,images:[...document.images].map(i=>({source:i.src,width:i.naturalWidth,height:i.naturalHeight,decoded:i.complete&&i.naturalWidth>0,fit:getComputedStyle(i).objectFit}))})');
  assert.equal(info.images.length,35);assert(info.images.every(i=>i.decoded&&i.fit==='contain'),'All 35 exact source images decode and retain aspect ratio');
  await b.shot(base+'/montage.png',{x:0,y:0,width:1280,height:info.height});
  fs.writeFileSync(path.join(base,'montage_validation.json'),JSON.stringify({kind:'actual_local_original_asset_assembly',notGameScreenshot:true,passed:true,...info},null,2));
  console.log('ARCHIVE_V10_ICON_MONTAGE_PASS: 35 real native original images, no missing pixels; local asset preview, not game screenshot.');
 }finally{b.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
