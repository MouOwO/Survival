'use strict';
// Freeze the current production assembly using the established Panorama host.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..');process.chdir(root);
const out='design_refs/shop_icon_clarity_20261017/survival_preview';
const arg=name=>{const i=process.argv.indexOf(name);return i<0?null:process.argv[i+1];};
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const master=fs.readFileSync('data/ui/item_resources.json'),expected=arg('--expected-hash');
if(expected&&sha(master)!==expected)throw Error('Frozen registry changed before the preview build.');
const build=cp.spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',out],{cwd:root,encoding:'utf8',windowsHide:true});
if(build.status!==0)throw Error(build.stdout+'\n'+build.stderr);
const filename=path.join(out,'index.html');let html=fs.readFileSync(filename,'utf8');
const key='window.PREVIEW_ASSET_PATHS=',next=';window.PREVIEW_BASELINE=';
const start=html.indexOf(key)+key.length,end=html.indexOf(next,start);
if(start<key.length||end<start)throw Error('Established preview asset map changed.');
const aliases=JSON.parse(html.slice(start,end)),extra=arg('--native-aliases'),compiled=arg('--compiled-aliases'),added=[];
function add(uri,png){
 if(!uri||!png)return;
 if(!String(png).startsWith('file:')&&!fs.existsSync(png))throw Error('Missing exact native export '+png);
 aliases[uri]=String(png).startsWith('file:')?png:pathToFileURL(path.resolve(png)).href;added.push({uri,png});
}
for(const file of [extra,compiled].filter(Boolean)){const manifest=JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
 for(const[uri,value]of Object.entries(manifest.aliases||{}))add(uri,typeof value==='string'?value:value.path||value.png);
 for(const row of manifest.records||manifest.rows||[])add(row.uri||row.native_uri,row.previewPng||row.export_png||row.png||row.path||row.source);
}
// PNG and vtex URIs resolving to the same frozen registry source are equivalent.
for(const row of JSON.parse(master).items){
 const uri=row.uri||'',m=uri.match(/^file:\/\/\{images\}\/(.+)\.png$/);
 if(m&&fs.existsSync('panorama/src/images/'+m[1]+'.png'))add(uri,'panorama/src/images/'+m[1]+'.png');
}
html=html.slice(0,start)+JSON.stringify(aliases)+html.slice(end);
const adapter=pathToFileURL(path.resolve('tools/archive_v10/adapter.js')).href;
html=html.replace(adapter,'adapter.js').replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,
 '$1生存商店商品清晰度 · 真实生产组件 · 本地正式表样例 · 非游戏截图$2');
fs.writeFileSync(path.join(out,'adapter.js'),fs.readFileSync('tools/archive_v10/adapter.js','utf8')
 .replace("v==='stretch-to-fit'?'fill':'contain'","v==='stretch-to-fit'?'fill':v==='stretch-to-cover-preserve-aspect'?'cover':'contain'"));
fs.writeFileSync(filename,html);
const assemblyFile=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
Object.assign(assembly,{kind:'survival_shop_icon_clarity_current_production',registryHash:sha(master),addedAliases:added,
 artworkChecks:'Only visible product card and tooltip images are judged in this preview; other menus are not part of this task.',
 nativeAliasManifest:extra,compiledAliasManifest:compiled,adapterCoverMapping:true});
fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2)+'\n');
console.log('SURVIVAL_ICON_PREVIEW_READY '+filename+' registry='+sha(master));
