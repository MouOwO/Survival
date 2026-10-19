'use strict';
// Isolated real production UI. Never connects to game, account, save or reward services.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const repo=path.resolve(__dirname,'../..'),out='output/archive_blackgold_refine_20261019',preview=out+'/preview';process.chdir(repo);
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
fs.mkdirSync(out,{recursive:true});
const child=spawnSync(process.execPath,['tools/archive_parchment/preview.cjs','--out',preview],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);assert.equal(child.status,0);
const entry=preview+'/index.html';let html=fs.readFileSync(entry,'utf8');
html=html.replace('<title>羊皮纸存档 · 实际组件隔离预览</title>','<title>黑金存档 · 现有布局五轮优化</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1黑金存档 · 现有真实组件 · 五轮渐进优化 · 样例状态$2');
const nativeManifest='output/archive_visual_alignment_20261018/native/manifest.json';assert(fs.existsSync(nativeManifest),'Reuse the installed native archive image exports');
const native=JSON.parse(fs.readFileSync(nativeManifest,'utf8'));
const supplement=out+'/native/manifest.json';if(fs.existsSync(supplement))Object.assign(native.aliases,JSON.parse(fs.readFileSync(supplement,'utf8')).aliases);
const catalogRoot=path.join(repo,'design_refs/official_ui_catalog_20261019'),catalog=JSON.parse(fs.readFileSync(path.join(catalogRoot,'catalog.json'),'utf8'));
const officialPaths=['panorama/images/dota_plus/dota_plus_background_texture_large_png.vtex_c','panorama/images/dota_plus/dota_plus_horizontal_banner_background_png.vtex_c','panorama/images/textures/header_texture_png.vtex_c','panorama/images/hud/reborn/bg_item_breakdown_psd.vtex_c','panorama/images/control_icons/24px/x_close.vsvg_c'];
const officialRecords=[];for(const resource of officialPaths){const row=catalog.assets.find(a=>a.sourcePath===resource);assert(row,'Missing official image '+resource);const file=path.join(catalogRoot,row.original);assert.equal(sha(file),row.originalSha256);const fileUri=require('url').pathToFileURL(file).href;native.aliases[row.uri]=fileUri;native.aliases[resource.slice('panorama/images/'.length).replace(/\.vsvg_c$/,'.svg')]=fileUri;officialRecords.push({uri:row.uri,sourcePath:row.sourcePath,path:file,sha256:sha(file)});}
fs.writeFileSync(out+'/official_assets.json',JSON.stringify(officialRecords,null,2));
const maskAliases=Object.fromEntries(['background_fade','right_fade'].filter(name=>fs.existsSync('art/ui/sources/custom_game/archive_user_skin_v1/'+name+'.svg')).map(name=>['file://{images}/custom_game/archive_user_skin_v1/'+name+'.svg','data:image/svg+xml;base64,'+fs.readFileSync('art/ui/sources/custom_game/archive_user_skin_v1/'+name+'.svg').toString('base64')]));
html=html.replace(/(<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>)/,'<script>Object.assign(window.PREVIEW_ASSET_PATHS,'+JSON.stringify(native.aliases)+');window.PREVIEW_ARCHIVE_MASK_DATA='+JSON.stringify(maskAliases)+';</script>$1');
// Panorama opacity-mask corresponds to a browser alpha mask. Mirror the exact
// production value, including inline style.opacityMask, only inside this fixture.
html=html.replace(/opacity-mask\s*:/g,'mask-image:');
const adapterMask='<script>const archiveMaskLayout=window.syncLayout;window.syncLayout=function(){archiveMaskLayout();for(const row of Object.values(nodes)){const values=row._style||{};let mask=values.opacityMask;if(mask){for(const [uri,data]of Object.entries(PREVIEW_ARCHIVE_MASK_DATA))mask=mask.replace(uri,data);row.el.style.maskImage=cssValue(mask);row.el.style.maskSize="100% 100%";row.el.style.maskRepeat="no-repeat";}if(values.backgroundImage&&values.backgroundImage.includes("s2r://")){row.el.style.backgroundImage=values.backgroundImage.replace(/s2r:\\/\\/[^"\\x27)]+/g,uri=>PREVIEW_ASSET_PATHS[uri]||uri);}}};</script>';
html=html.replace(/(<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>)/,'$1'+adapterMask);const adapterTag=/(<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>)/;
const setup='<script>const refineParams=new URLSearchParams(location.search);cfg.ArchiveBlackGoldDisabled=refineParams.get("baseline")==="1";cfg.ArchiveBlackGoldStage=Number(refineParams.get("round"))||5;const previousCssValue=cssValue;cssValue=function(value){return previousCssValue(typeof value==="string"?value.replace(/s2r:\\/\\/[^"\\x27)]+/g,uri=>PREVIEW_ASSET_PATHS[uri]||uri):value);};</script>';
html=html.replace(adapterTag,'$1'+setup);
// Mirror the exact native scrollbar paint rules as Chrome pseudo-elements.
const finishCss=fs.readFileSync('panorama/src/styles/custom_game/archive_blackgold_v1.css','utf8');
const browserTrackCss=[...finishCss.matchAll(/([^{}]+)\{([^{}]+)\}/g)].filter(m=>m[1].includes('VerticalScrollBar')).map(m=>m[1].replace(/\s+VerticalScrollBar\s+\.ScrollThumb/g,'::-webkit-scrollbar-thumb').replace(/\s+VerticalScrollBar/g,'::-webkit-scrollbar-track')+'{'+m[2].replace(/background-color:\s*gradient\(linear,0% 0%,100% 0%,from\((#[0-9a-f]+)\),to\((#[0-9a-f]+)\)\)/gi,'background-image:linear-gradient(90deg,$1,$2)')+'}').join('\n');
html=html.replace('<div id="PreviewRoot">','<style>'+browserTrackCss+'</style><div id="PreviewRoot">');
fs.writeFileSync(entry,html);
const assemblyFile=preview+'/assembly.json',assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
const roots=['art/ui/sources/custom_game/archive_polish_v2','panorama/src/images/custom_game/archive_polish_v2','art/ui/sources/custom_game/archive_parchment_v1','panorama/src/images/custom_game/archive_parchment_v1','art/ui/sources/custom_game/archive_user_skin_v1','panorama/src/images/custom_game/archive_user_skin_v1'];
const files=[];function walk(dir){if(!fs.existsSync(dir))return;for(const row of fs.readdirSync(dir,{withFileTypes:true})){const file=dir+'/'+row.name;if(row.isDirectory())walk(file);else if(/\.(png|svg|vtex)$/.test(row.name))files.push({path:file,sha256:sha(file)});}}roots.forEach(walk);
const freeze={at:new Date().toISOString(),sources:assembly.sourceGraph.filter(row=>/archive|reward_presentation|item_resources|endless_leaderboard|vip_badges/.test(row.path)),assets:files};
assembly.nativePreviewExports={manifest:nativeManifest,sha256:sha(nativeManifest),note:'Exact exports of installed Dota VPK assets for Chrome only; production URIs stay native.'};
assembly.limitations.push('Panorama opacity-mask is mirrored to CSS mask-image using exact production SVG bytes as base64 data URIs (Chrome blocks file-origin alpha masks) and production inline style values. Native engine mask sampling remains a game verification concern.');
assembly.limitations.push('Inline native texture backgrounds use the assembly recipe-to-original-PNG alias in Chrome; production retains its original VTEX binding.');
fs.writeFileSync(out+'/snapshot.json',JSON.stringify(freeze,null,2));assembly.kind='archive_blackgold_existing_layout_five_rounds';assembly.snapshot=out+'/snapshot.json';assembly.notGameCapture=true;fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2));
console.log('ARCHIVE_BLACKGOLD_PREVIEW_BUILT '+preview);
