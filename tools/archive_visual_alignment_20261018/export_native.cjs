'use strict';
// Exact installed Dota VPK exports for browser preview only. Production keeps its native URIs.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto'),{pathToFileURL}=require('node:url');
const {open}=require('../vpk_inspect.cjs');
const out='output/archive_visual_alignment_20261018',dest=out+'/native',fixture=JSON.parse(fs.readFileSync(out+'/preview/fixture.json','utf8'));
const viewer=path.resolve('output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');if(!fs.existsSync(viewer))throw Error('Existing Source2Viewer unavailable');
const names=new Set();for(const rows of [...Object.values(fixture.v10.pages),fixture.commerce.paid.products,fixture.commerce.wallet.products])for(const row of rows){const icon=String(row.icon||'');if(icon.startsWith('item_'))names.add(icon.slice(5));else if(icon.includes('/items/'))names.add(icon.split('/').pop().replace(/\.png$/,''));}
const required=new Set();if(fs.existsSync(out+'/report.json')){const failure=JSON.parse(fs.readFileSync(out+'/report.json','utf8')).failureState;for(const row of failure?.images||[])if(!row.decoded&&row.src.includes('/panorama/src/images/')){const relative=decodeURIComponent(row.src.split('/panorama/src/images/')[1]);if(!/^[A-Za-z0-9_/-]+\.png$/.test(relative)||relative.includes('..'))throw Error('Unexpected native preview URI '+row.src);required.add(relative);}}
const priorManifest=dest+'/manifest.json';if(fs.existsSync(priorManifest))for(const row of JSON.parse(fs.readFileSync(priorManifest,'utf8')).records){const relative=row.relative||(row.uri||'').replace(/^file:\/\/\{images\}\//,'');if(/^[A-Za-z0-9_/-]+\.png$/.test(relative)&&!relative.includes('..'))required.add(relative);}
const vpk=open(path.resolve('../../dota/pak01_dir.vpk')),records=[],missing=[],aliases={};fs.mkdirSync(dest,{recursive:true});
const candidates=new Set([...names].map(name=>'items/'+name+'.png'));for(const relative of required)candidates.add(relative);
for(const relative of [...candidates].sort()){
 const stem=relative.slice(0,-4),name=stem.replaceAll('/','_'),resources=['panorama/images/'+stem+'_png.vtex_c','panorama/images/'+stem+'.vtex_c'],entry=vpk.entries.find(row=>resources.includes(row.path)),resource=entry?.path||resources[0];if(!entry){if(required.has(relative))throw Error('Actual visible native texture missing from VPK: '+resources.join(' or '));missing.push({relative,resource,note:'Candidate inventory name only; may be replaced by an authored registered icon. Final visible-resource decode remains mandatory.'});continue;}
 const bytes=vpk.read(entry),input=path.resolve(dest,name+'_png.vtex_c'),png=path.resolve(dest,name+'_png.png');fs.writeFileSync(input,bytes);
 if(!fs.existsSync(png))cp.execFileSync(viewer,['-i',input,'-o',png,'-d'],{windowsHide:true,stdio:'pipe'});if(!fs.existsSync(png))throw Error('No decoded PNG: '+resource);
 const image=fs.readFileSync(png),uri='file://{images}/'+relative,local=pathToFileURL(png).href;
 aliases[uri]=local;aliases[relative]=local;aliases['s2r://'+resource.replace(/\.vtex_c$/,'.vtex')]=local;
 records.push({name,relative,uri,resource,resourceSha256:crypto.createHash('sha256').update(bytes).digest('hex'),previewPng:path.relative(process.cwd(),png).replaceAll('\\','/'),pngSha256:crypto.createHash('sha256').update(image).digest('hex'),width:image.readUInt32BE(16),height:image.readUInt32BE(20)});
}
fs.writeFileSync(dest+'/manifest.json',JSON.stringify({kind:'exact_installed_dota_vpk_original_exports_preview_only',notProductionChange:true,sourceVpk:path.resolve('../../dota/pak01_dir.vpk'),aliases,records,unusedCandidateMisses:missing},null,2));
console.log('ARCHIVE_VISUAL_ALIGNMENT_NATIVE_EXPORTED '+records.length+' original PNGs; candidate-only misses='+missing.length);
