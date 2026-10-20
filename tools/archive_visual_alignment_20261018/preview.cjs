'use strict';
// Isolated real production UI. Never connects to game, account, save or reward services.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const repo=path.resolve(__dirname,'../..'),out='output/archive_visual_alignment_20261018',preview=out+'/preview';process.chdir(repo);
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
fs.mkdirSync(out,{recursive:true});
const child=spawnSync(process.execPath,['tools/archive_parchment/preview.cjs','--out',preview],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);assert.equal(child.status,0);
const entry=preview+'/index.html';let html=fs.readFileSync(entry,'utf8');
html=html.replace('<title>羊皮纸存档 · 实际组件隔离预览</title>','<title>存档标题与图标修缮 · 生产组件离线预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1存档修缮 · 生产 XML / JS / CSS · 离线样例 · 未连接游戏、账号或奖励$2');fs.writeFileSync(entry,html);
const nativeManifest=out+'/native/manifest.json';if(fs.existsSync(nativeManifest)){const native=JSON.parse(fs.readFileSync(nativeManifest,'utf8'));html=html.replace(/(<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>)/,'<script>Object.assign(window.PREVIEW_ASSET_PATHS,'+JSON.stringify(native.aliases)+');</script>$1');fs.writeFileSync(entry,html);}
const assemblyFile=preview+'/assembly.json',assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
const roots=['art/ui/sources/custom_game/archive_polish_v2','panorama/src/images/custom_game/archive_polish_v2','art/ui/sources/custom_game/archive_parchment_v1','panorama/src/images/custom_game/archive_parchment_v1'];
const files=[];function walk(dir){if(!fs.existsSync(dir))return;for(const row of fs.readdirSync(dir,{withFileTypes:true})){const file=dir+'/'+row.name;if(row.isDirectory())walk(file);else if(/\.(png|svg|vtex)$/.test(row.name))files.push({path:file,sha256:sha(file)});}}roots.forEach(walk);
const freeze={at:new Date().toISOString(),sources:assembly.sourceGraph.filter(row=>/archive|reward_presentation|item_resources|endless_leaderboard|vip_badges/.test(row.path)),assets:files};
if(fs.existsSync(nativeManifest)){assembly.nativePreviewExports={manifest:nativeManifest,sha256:sha(nativeManifest),note:'Exact exports of installed Dota VPK assets for Chrome only; production URIs stay native.'};}
fs.writeFileSync(out+'/snapshot.json',JSON.stringify(freeze,null,2));assembly.kind='archive_visual_alignment_production_component_offline_preview';assembly.snapshot=out+'/snapshot.json';assembly.notGameCapture=true;fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2));
console.log('ARCHIVE_VISUAL_ALIGNMENT_PREVIEW_BUILT '+preview);
