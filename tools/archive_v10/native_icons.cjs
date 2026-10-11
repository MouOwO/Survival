'use strict';
// Exact native texture exports used only by the browser; game keeps native URI.
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),{pathToFileURL}=require('url');
const {open}=require('../vpk_inspect.cjs');
const base=path.resolve('design_refs/archive_v10/work/native_icons');fs.mkdirSync(base,{recursive:true});
const viewer=path.resolve('output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
if(!fs.existsSync(viewer))throw Error('Installed local Source2Viewer CLI unavailable: '+viewer);
const vpk=open(path.resolve('../../dota/pak01_dir.vpk')),aliases={},records=[],missing=[];
for(const name of ['claymore','bloodstone','octarine_core','abyssal_blade','arcane_boots']){
 const uri='file://{images}/items/'+name+'.png',resource='panorama/images/items/'+name+'_png.vtex_c',entry=vpk.entries.find(e=>e.path===resource);
 if(!entry){missing.push({uri,resource});continue;}
 const bytes=vpk.read(entry),input=path.join(base,name+'_png.vtex_c'),output=path.join(base,name+'_png.png');
 fs.writeFileSync(input,bytes);if(!fs.existsSync(output))cp.execFileSync(viewer,['-i',input,'-o',output,'-d'],{windowsHide:true,stdio:'pipe'});
 if(!fs.existsSync(output))throw Error('Native export returned no PNG: '+resource);
 aliases[uri]=pathToFileURL(output).href;records.push({uri,resource,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),previewPng:path.relative(process.cwd(),output)});
}
fs.writeFileSync(path.join(base,'manifest.json'),JSON.stringify({kind:'exact_official_dota_vpk_preview_only',aliases,records,missing},null,2));
console.log('ARCHIVE_V10_NATIVE_PREVIEW_ICONS '+records.length+' missing='+missing.length);
