'use strict';
// Isolated real production UI. Never connects to game, account, save or reward services.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const repo=path.resolve(__dirname,'../..'),out='output/archive_user_skin_20261019',preview=out+'/preview';process.chdir(repo);
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
fs.mkdirSync(out,{recursive:true});
const liveSource=fs.readFileSync('panorama/src/scripts/custom_game/archive_v10.js','utf8');
assert(liveSource.includes('s2r://panorama/images/custom_game/archive_user_skin_v1/background.vtex'),'Production source must contain the final native user background binding before snapshot');
assert(liveSource.includes('file://{images}/custom_game/archive_user_skin_v1/background_fade.svg'),'Production source must contain the final background mask before snapshot');
const child=spawnSync(process.execPath,['tools/archive_parchment/preview.cjs','--out',preview],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);assert.equal(child.status,0);
const entry=preview+'/index.html';let html=fs.readFileSync(entry,'utf8');
html=html.replace('<title>羊皮纸存档 · 实际组件隔离预览</title>','<title>存档背景与标题栏 · 生产组件离线预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1用户原图存档 · 生产 XML / JS / CSS · 离线样例 · 未连接游戏、账号或奖励$2');
const nativeManifest='output/archive_visual_alignment_20261018/native/manifest.json';assert(fs.existsSync(nativeManifest),'Reuse the installed native archive image exports');
const native=JSON.parse(fs.readFileSync(nativeManifest,'utf8'));
const supplement=out+'/native/manifest.json';if(fs.existsSync(supplement))Object.assign(native.aliases,JSON.parse(fs.readFileSync(supplement,'utf8')).aliases);
const maskAliases=Object.fromEntries(['background_fade','right_fade'].map(name=>['file://{images}/custom_game/archive_user_skin_v1/'+name+'.svg','data:image/svg+xml;base64,'+fs.readFileSync('art/ui/sources/custom_game/archive_user_skin_v1/'+name+'.svg').toString('base64')]));
html=html.replace(/(<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>)/,'<script>Object.assign(window.PREVIEW_ASSET_PATHS,'+JSON.stringify(native.aliases)+');window.PREVIEW_ARCHIVE_MASK_DATA='+JSON.stringify(maskAliases)+';</script>$1');
// Panorama opacity-mask corresponds to a browser alpha mask. Mirror the exact
// production value, including inline style.opacityMask, only inside this fixture.
html=html.replace(/opacity-mask\s*:/g,'mask-image:');
const adapterMask='<script>const archiveMaskLayout=window.syncLayout;window.syncLayout=function(){archiveMaskLayout();for(const row of Object.values(nodes)){const values=row._style||{};let mask=values.opacityMask;if(mask){for(const [uri,data]of Object.entries(PREVIEW_ARCHIVE_MASK_DATA))mask=mask.replace(uri,data);row.el.style.maskImage=cssValue(mask);row.el.style.maskSize="100% 100%";row.el.style.maskRepeat="no-repeat";}if(values.backgroundImage&&values.backgroundImage.includes("s2r://")){row.el.style.backgroundImage=values.backgroundImage.replace(/s2r:\\/\\/[^"\\x27)]+/g,uri=>PREVIEW_ASSET_PATHS[uri]||uri);}}};</script>';
html=html.replace(/(<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>)/,'$1'+adapterMask);fs.writeFileSync(entry,html);
const assemblyFile=preview+'/assembly.json',assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
const roots=['art/ui/sources/custom_game/archive_polish_v2','panorama/src/images/custom_game/archive_polish_v2','art/ui/sources/custom_game/archive_parchment_v1','panorama/src/images/custom_game/archive_parchment_v1','art/ui/sources/custom_game/archive_user_skin_v1','panorama/src/images/custom_game/archive_user_skin_v1'];
const files=[];function walk(dir){if(!fs.existsSync(dir))return;for(const row of fs.readdirSync(dir,{withFileTypes:true})){const file=dir+'/'+row.name;if(row.isDirectory())walk(file);else if(/\.(png|svg|vtex)$/.test(row.name))files.push({path:file,sha256:sha(file)});}}roots.forEach(walk);
const freeze={at:new Date().toISOString(),sources:assembly.sourceGraph.filter(row=>/archive|reward_presentation|item_resources|endless_leaderboard|vip_badges/.test(row.path)),assets:files};
assembly.nativePreviewExports={manifest:nativeManifest,sha256:sha(nativeManifest),note:'Exact exports of installed Dota VPK assets for Chrome only; production URIs stay native.'};
assembly.limitations.push('Panorama opacity-mask is mirrored to CSS mask-image using exact production SVG bytes as base64 data URIs (Chrome blocks file-origin alpha masks) and production inline style values. Native engine mask sampling remains a game verification concern.');
assembly.limitations.push('Inline native texture backgrounds use the assembly recipe-to-original-PNG alias in Chrome; production retains its original VTEX binding.');
fs.writeFileSync(out+'/snapshot.json',JSON.stringify(freeze,null,2));assembly.kind='archive_user_skin_production_component_offline_preview';assembly.snapshot=out+'/snapshot.json';assembly.notGameCapture=true;fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2));
console.log('ARCHIVE_USER_SKIN_PREVIEW_BUILT '+preview);
