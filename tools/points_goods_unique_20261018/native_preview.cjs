'use strict';
// Export exact installed item textures solely for the isolated browser transport.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {pathToFileURL}=require('node:url'),{open}=require('../vpk_inspect.cjs');
const repo=path.resolve(__dirname,'../..'),base=path.join(repo,'design_refs/points_goods_unique_20261018'),out=path.join(base,'preview/native');
const viewer=path.join(repo,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const vpk=open(path.resolve(repo,'../../dota/pak01_dir.vpk')),aliases={},records=[];
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
fs.mkdirSync(out,{recursive:true});
for(const relative of ['items/ring_of_health','items/stout_shield','items/circlet','items/furion_gold_bag','items/tango','econ/tools/ti10_seasonal_item_background']){
 const name=relative.split('/').at(-1),uri='file://{images}/'+relative+'.png',resource='panorama/images/'+relative+'_png.vtex_c';
 const entry=vpk.entries.find(entry=>entry.path===resource);if(!entry)throw Error('Missing installed texture: '+resource);
 const bytes=vpk.read(entry),input=path.join(out,name+'_png.vtex_c'),png=path.join(out,name+'_png.png');
 fs.writeFileSync(input,bytes);cp.execFileSync(viewer,['-i',input,'-o',png,'-d'],{windowsHide:true,stdio:'pipe'});
 const decoded=fs.readFileSync(png);aliases[uri]=pathToFileURL(png).href;aliases[relative+'.png']=pathToFileURL(png).href;
 records.push({uri,resource,sourceSha256:sha(bytes),previewPng:path.relative(repo,png).replaceAll('\\','/'),previewSha256:sha(decoded),width:decoded.readUInt32BE(16),height:decoded.readUInt32BE(20),method:'Exact installed Dota item texture decoded by Source2Viewer; no resampling or visual edits'});
}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({kind:'exact_installed_dota_textures_for_isolated_browser_only',records,aliases},null,2));
const htmlFile=path.join(base,'preview/index.html'),needle='<script src="'+pathToFileURL(path.join(repo,'tools/archive_v10/adapter.js')).href+'"></script>';
let html=fs.readFileSync(htmlFile,'utf8');if(!html.includes(needle))throw Error('Preview transport injection point missing');
html=html.replace(needle,'<script>Object.assign(window.PREVIEW_ASSET_PATHS,'+JSON.stringify(aliases)+');</script>'+needle);fs.writeFileSync(htmlFile,html);
const assemblyFile=path.join(base,'preview/assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
assembly.pointsNativeTextureTransport={manifest:'design_refs/points_goods_unique_20261018/preview/native/manifest.json',records};
assembly.previewHarness.push({path:path.relative(repo,__filename).replaceAll('\\','/'),sha256:sha(fs.readFileSync(__filename))});
fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2));
console.log('POINTS_NATIVE_PREVIEW_PASS '+records.length+' exact installed item textures');
