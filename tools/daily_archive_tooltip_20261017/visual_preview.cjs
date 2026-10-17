'use strict';
// Freeze the active daily XML / JS / CSS in an isolated, account-free browser
// fixture. Asset aliases reference exact existing PNGs; no artwork is edited.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process'),{pathToFileURL}=require('node:url');
const repo=path.resolve(__dirname,'../..'),out='output/daily_archive_tooltip_20261017/visual_preview';
process.chdir(repo);
const result=cp.spawnSync(process.execPath,['tools/daily_gw2/preview.cjs','--out',out],{encoding:'utf8',windowsHide:true});
if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);if(result.status!==0)process.exit(result.status||1);
const input=path.join(out,'index.html');let html=fs.readFileSync(input,'utf8');
const startKey='window.PREVIEW_ASSET_PATHS=',endKey=';window.PREVIEW_BASELINE=',start=html.indexOf(startKey)+startKey.length,end=html.indexOf(endKey,start);
if(start<startKey.length||end<start)throw Error('Actual production preview asset map unavailable');
const aliases=JSON.parse(html.slice(start,end)),added=[];
const manifests=[
 'output/shop_icon_quality_20261017/native/manifest.json',
 'output/shop_icon_quality_20261017/native_compiled/manifest.json',
 'design_refs/vip_bundle_icons_20261017/native_candidates/manifest.json',
 'design_refs/archive_reward_icons_20261017/native/manifest.json'
].filter(f=>fs.existsSync(f));
function alias(uri,file){
 if(!uri||!file||aliases[uri])return;
 if(String(file).startsWith('file:')){aliases[uri]=file;return;}
 if(!fs.existsSync(file))throw Error('Missing exact native preview PNG: '+file);
 aliases[uri]=pathToFileURL(path.resolve(file)).href;added.push({uri,file});
}
for(const manifest of manifests){const data=JSON.parse(fs.readFileSync(manifest,'utf8').replace(/^\uFEFF/,''));
 for(const row of data.records||data.rows||[])alias(row.uri||row.native_uri,row.previewPng||row.export_png||row.png||row.path||row.source);
 for(const [uri,value]of Object.entries(data.aliases||{}))alias(uri,typeof value==='string'?value:value.path||value.png);
}
html=html.slice(0,start)+JSON.stringify(aliases)+html.slice(end);fs.writeFileSync(input,html);
const assemblyFile=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
assembly.kind='daily_archive_shared_tooltip_actual_source_browser_fixture';assembly.previewNativeAliases={manifests,added};
assembly.visualBuilder={path:'tools/daily_archive_tooltip_20261017/visual_preview.cjs',sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex')};
fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2)+'\n');
console.log('DAILY_ARCHIVE_TOOLTIP_VISUAL_READY '+input);
