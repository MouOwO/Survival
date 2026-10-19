'use strict';
// Decode a small set of official treasure illustrations for the review.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto'),cp=require('node:child_process');
const {open}=require('../vpk_inspect.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'design_refs/lottery_five_official_20261019'),work=path.join(root,'output/lottery_five_official_20261019');
const names=['crownfall_2024_collectors_cache','crownfall_2024_collectors_cache_2','dark_carnival_treasure_i','ti7_immortal_treasure_1','frostivus_chest','frostivus_2018_treasure_1','nemestice2021_cache','aghanim2021_immortal_treasure','10_years_treasure','fall_2020_treasure_large','plus_fall_2021_treasure_large','plus_fall_2022_treasure_large','plus_spring_2021_treasure_large','plus_spring_2022_treasure_large','plus_summer_2021_treasure_large','plus_summer_2022_treasure_large','plus_summer_2023_treasure_large','plus_winter_2020_treasure_large','plus_winter_2021_treasure_large','plus_winter_2022_treasure_large'];
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function prepare(){
 const vpk=open(path.resolve(root,'../../dota/pak01_dir.vpk')),temporary=fs.mkdtempSync(path.join(os.tmpdir(),'codex-lottery-five-20261019-')),records=[];
 try{
  for(const [i,name]of names.entries()){const resource='panorama/images/econ/tools/'+name+'_png.vtex_c',entry=vpk.entries.find(e=>e.path===resource);if(!entry)throw Error('Official treasure not found: '+resource);const bytes=vpk.read(entry);fs.writeFileSync(path.join(temporary,name+'_png.vtex_c'),bytes);records.push({id:'T'+String(i+1).padStart(2,'0'),name,sourcePath:resource,uri:'s2r://'+resource.slice(0,-2),sourceSha256:hash(bytes),original:'assets/native/'+name+'_png.png'});}
  fs.mkdirSync(path.join(out,'assets/native'),{recursive:true});fs.mkdirSync(work,{recursive:true});const log=fs.openSync(path.join(work,'extra_native.log'),'w');let result;
  try{result=cp.spawnSync(process.env.DOTA_UI_VIEWER||path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),['-i',temporary,'-o',path.join(out,'assets/native'),'-d','--recursive','--threads','4'],{windowsHide:true,stdio:['ignore',log,log]});}finally{fs.closeSync(log);}
  if(result.status!==0)throw Error('Official treasure decode failed');
  for(const record of records){const png=fs.readFileSync(path.join(out,record.original));if(png.subarray(1,4).toString()!=='PNG')throw Error('Decoder did not produce PNG');record.width=png.readUInt32BE(16);record.height=png.readUInt32BE(20);record.originalSha256=hash(png);}
  fs.writeFileSync(path.join(work,'extra_native.json'),JSON.stringify({records},null,2));console.log(JSON.stringify({status:'PASS',treasures:records.map(r=>({id:r.id,name:r.name,width:r.width,height:r.height}))}));return records;
 }finally{const resolved=fs.realpathSync(temporary),tmpRoot=fs.realpathSync(os.tmpdir());if(path.dirname(resolved).toLowerCase()!==tmpRoot.toLowerCase()||!/^codex-lottery-five-20261019-[A-Za-z0-9]+$/.test(path.basename(resolved)))throw Error('Unexpected temporary cleanup path');fs.rmSync(resolved,{recursive:true,force:true});}
}
module.exports={prepare};if(require.main===module)prepare();
