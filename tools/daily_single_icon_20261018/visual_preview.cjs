'use strict';
// Freeze actual daily XML / JS / CSS and alias exact installed-native PNGs.
// Progress is the existing formal-CSV fixture; no game/account API is contacted.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {pathToFileURL,fileURLToPath}=require('node:url');
const repo=path.resolve(__dirname,'../..'),out='output/daily_single_icon_20261018/visual_preview';
const nativeManifest='output/daily_native_icons_20261017/manifest.json',registry='data/ui/item_resources.json';
process.chdir(repo);
const sha=raw=>crypto.createHash('sha256').update(raw).digest('hex');
const nativeBytes=fs.readFileSync(nativeManifest),native=JSON.parse(nativeBytes.toString('utf8').replace(/^\uFEFF/,''));
const registryBytes=fs.readFileSync(registry),table=JSON.parse(registryBytes.toString('utf8').replace(/^\uFEFF/,''));
const daily=table.items.filter(row=>row.id.startsWith('daily_'));
if(daily.length!==12)throw Error('Expected the 12 actual daily reward resource identities');
const nativeRows=native.records||native.rows||[];
for(const row of daily)if(!nativeRows.some(asset=>(asset.uri||asset.native_uri)===row.uri))
 throw Error('Daily registry has not been generated with reviewed native art: '+row.id+' '+row.uri);
const result=cp.spawnSync(process.execPath,['tools/daily_gw2/preview.cjs','--out',out],{encoding:'utf8',windowsHide:true});
if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);
if(result.status!==0)process.exit(result.status||1);
const input=path.join(out,'index.html');let html=fs.readFileSync(input,'utf8');
const startKey='window.PREVIEW_ASSET_PATHS=',endKey=';window.PREVIEW_BASELINE=';
const start=html.indexOf(startKey)+startKey.length,end=html.indexOf(endKey,start);
if(start<startKey.length||end<start)throw Error('Actual source preview asset-map anchor unavailable');
const aliases=JSON.parse(html.slice(start,end)),added=[];
const manifests=[
 'output/shop_icon_quality_20261017/native/manifest.json',
 'output/shop_icon_quality_20261017/native_compiled/manifest.json',
 'design_refs/vip_bundle_icons_20261017/native_candidates/manifest.json',
 'design_refs/archive_reward_icons_20261017/native/manifest.json',
 nativeManifest
].filter(file=>fs.existsSync(file));
function alias(uri,file,expectedHash,override=false){
 if(!uri||!file||aliases[uri]&&!override)return;
 if(String(file).startsWith('data:image/')){aliases[uri]=file;return;}
 const source=String(file).startsWith('file:')?fileURLToPath(file):path.resolve(file);
 if(!fs.existsSync(source))throw Error('Missing exact native preview PNG: '+source);
 const actual=sha(fs.readFileSync(source));
 if(expectedHash&&actual!==expectedHash)throw Error('Native PNG fingerprint changed: '+source);
 aliases[uri]=pathToFileURL(source).href;added.push({uri,file:path.relative(repo,source),sha256:actual});
}
for(const manifest of manifests){
 const data=JSON.parse(fs.readFileSync(manifest,'utf8').replace(/^\uFEFF/,'')),override=manifest===nativeManifest;
 for(const row of data.records||data.rows||[]){
  const uri=row.uri||row.native_uri,file=row.previewPng||row.export_png||row.png||row.path||row.source;
  const fingerprint=row.png_sha256||row.previewPngSha256||row.export_png_sha256;
  alias(uri,file,fingerprint,override);
  if(override&&uri?.startsWith('file://{images}/'))alias(uri.slice('file://{images}/'.length),file,fingerprint,true);
  if(override&&row.resource?.endsWith('.vtex_c'))alias('s2r://'+row.resource.slice(0,-2),file,fingerprint,true);
 }
 for(const [uri,value]of Object.entries(data.aliases||{}))alias(uri,typeof value==='string'?value:value.path||value.png,undefined,override);
}
html=html.slice(0,start)+JSON.stringify(aliases)+html.slice(end);
html=html.replace(/<title>[^<]*<\/title>/,'<title>签到原生图标 · 实际组件隔离预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1签到原生图标 · 真实 XML / JS / CSS · 本地样例进度 · 非游戏截图$2');
// The shared browser adapter handles native saturation/brightness but ignores
// wash-color. Approximate only this authored daily wash with an SVG RGB
// multiplier after its normal layout sync; native PNG bytes remain unchanged.
const dailyCss=fs.readFileSync('panorama/src/styles/custom_game/daily_gw2.css','utf8');
const wash=dailyCss.match(/\.DailyGW2ItemArt\s*\{[^}]*\bwash-color:\s*(#[0-9a-f]{6})/i)?.[1];
if(!wash)throw Error('Actual production daily icon wash-color is unavailable');
const rgb=wash.slice(1).match(/../g).map(value=>parseInt(value,16)/255);
const stateTag='<script src="'+pathToFileURL(path.join(repo,'tools/daily_gw2/state.js')).href+'"></script>';
if(!html.includes(stateTag))throw Error('Daily fixture bootstrap anchor unavailable');
const washShim='<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0" aria-hidden="true" style="position:absolute;pointer-events:none"><defs><filter id="DailyNativePreviewWash" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="'+rgb[0]+' 0 0 0 0 0 '+rgb[1]+' 0 0 0 0 0 '+rgb[2]+' 0 0 0 0 0 1 0"/></filter></defs></svg>'+
 '<script>(function(){var original=window.syncLayout;window.dailyNativePreviewWash='+JSON.stringify(wash)+';window.syncLayout=function(){original();var canvas=nodes.DailyGW2Canvas,stack=canvas?[canvas]:[];while(stack.length){var node=stack.pop();stack.push.apply(stack,node.Children());var image=node._style&&node._style.backgroundImage,match=image&&String(image).match(/url\\(["\x27]?(s2r:\\/\\/[^"\x27)]+)["\x27]?\\)/),uri=match&&match[1],source=uri&&PREVIEW_ASSET_PATHS[uri];if(source){node.el.style.backgroundImage="url(\\\""+source+"\\\")";node.el.dataset.dailyNativeResolvedBackground=uri;}if(node.__survivalItemFill)node.el.style.objectFit=node.__survivalItemFill==="cover"?"cover":"contain";}document.querySelectorAll("#DailyGW2Canvas .DailyGW2ItemArt").forEach(function(image){var style=getComputedStyle(image),brightness=style.getPropertyValue("--pano-brightness").trim()||"1",saturation=style.getPropertyValue("--pano-saturation").trim()||"1";image.style.filter="brightness("+brightness+") saturate("+saturation+") url(#DailyNativePreviewWash)";image.dataset.dailyNativePreviewWash=window.dailyNativePreviewWash;});};})();</script>';
html=html.replace(stateTag,washShim+stateTag);
fs.writeFileSync(input,html);
const assemblyFile=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
assembly.kind='daily_single_icon_actual_source_browser_fixture';assembly.notGameCapture=true;assembly.fixtureOnly=true;
assembly.previewNativeAliases={manifests,added,nativeManifest,nativeManifestSha256:sha(nativeBytes),originalPixelsUnchanged:true};
assembly.dailyNativeResources={source:registry,sha256:sha(registryBytes),items:daily.map(row=>{
 const asset=nativeRows.find(asset=>(asset.uri||asset.native_uri)===row.uri);
 return {id:row.id,uri:row.uri,fit:row.fit||'cover',sourceSize:[asset.width,asset.height],png:asset.png||asset.previewPng||asset.export_png};
})};
assembly.visualBuilder={path:'tools/daily_single_icon_20261018/visual_preview.cjs',sha256:sha(fs.readFileSync(__filename))};
assembly.dailyWashBrowserApproximation={source:'panorama/src/styles/custom_game/daily_gw2.css',washColor:wash,rgbMultipliers:rgb,method:'Browser-only SVG RGB multiplication; saturation/brightness use the adapter CSS cascade.',originalNativePngBytesUnchanged:true};
assembly.dailyBackgroundBrowserAliases={scope:'Daily canvas dynamic Panel backgroundImage only',method:'Resolve existing s2r texture URI aliases to exact existing recipe PNGs; no artwork or production-source edits.'};
assembly.dailyBrowserScaling={scope:'Daily item images only',method:'Map production __survivalItemFill cover/contain to CSS object-fit; shared adapter otherwise treats every preserve-aspect scaling as contain.'};
assembly.limitations.push('Native PNG pixels are unchanged. Chrome approximates Panorama saturation/brightness and uses an explicit SVG RGB multiplication for the authored daily wash-color; exact native tone/font rendering requires game verification.');
fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2)+'\n');
console.log('DAILY_SINGLE_ICON_VISUAL_READY '+input+' daily_resources='+daily.length);
