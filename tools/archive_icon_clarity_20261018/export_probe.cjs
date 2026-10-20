'use strict';
// Decode exact reviewed native A/B resources for offline inspection only.
// No resizing, sharpening, cropping, runtime swap or game-window operation.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {checked}=require('./build_textures.cjs');
const {decode}=require('../collection_gw2/portrait_quality_preview.cjs');
const root=path.resolve(__dirname,'../..'),task='archive_icon_clarity_20261018';
const report=JSON.parse(fs.readFileSync(checked(root,'design_refs/'+task+'/texture_probe.json'),'utf8'));
const previous=JSON.parse(fs.readFileSync(checked(root,'design_refs/'+task+'/same_uri_probe.json'),'utf8')).records[0];
const viewer=checked(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');assert(fs.existsSync(viewer),'existing native texture decoder unavailable');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),records=[];
for(const row of report.records){
 const paths=[{name:'baseline_dxt5',source:previous.baseline_runtime,sha256:previous.before.sha256},{name:'candidate_bgra8888',source:'panorama/images/custom_game/archive_icons_hd_v1/'+row.id+'.vtex_c',sha256:row.sha256}];
 for(const item of paths){
  const source=checked(root,item.source),png='design_refs/'+task+'/pixels/'+row.id+'_'+item.name+'.png',destination=checked(root,png),bytes=fs.readFileSync(source);assert.equal(hash(bytes),item.sha256,'frozen native A/B identity');fs.mkdirSync(path.dirname(destination),{recursive:true});
  if(item.name==='candidate_bgra8888')fs.writeFileSync(destination,decode(source).png);
  else {const result=cp.spawnSync(viewer,['-i',source,'-o',destination,'-d'],{encoding:'utf8',windowsHide:true,timeout:120000});assert.equal(result.status,0,'native decode failed: '+item.name);if(!fs.existsSync(destination)){const emitted=path.join(path.dirname(destination),path.basename(source,'.vtex_c')+'.png');assert(emitted.startsWith(path.dirname(destination)+path.sep));assert(fs.existsSync(emitted),'decoder did not produce PNG');fs.renameSync(emitted,destination);}}
  const b=fs.readFileSync(destination);assert.equal(b.subarray(0,8).toString('hex'),'89504e470d0a1a0a');assert.deepEqual([b.readUInt32BE(16),b.readUInt32BE(20)],[256,256]);records.push({id:row.id,kind:item.name,native:item.source,native_sha256:item.sha256,png,png_sha256:hash(b),dimensions:[256,256],conversion_only:true});
 }
}
const destination=checked(root,'design_refs/'+task+'/pixels/manifest.json');fs.writeFileSync(destination,JSON.stringify({status:'PASS',kind:'exact_native_texture_decode_only',not_game_capture:true,records},null,2)+'\n');console.log(JSON.stringify({status:'PASS_NATIVE_DECODE',count:records.length,manifest:path.relative(root,destination).replaceAll('\\','/')}));
