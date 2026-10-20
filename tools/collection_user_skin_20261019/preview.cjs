'use strict';
// Assemble actual collection sources with local synthetic ownership only.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const repo=path.resolve(__dirname,'../..'),out='output/collection_user_skin_20261019',preview=out+'/preview';process.chdir(repo);
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
fs.mkdirSync(out,{recursive:true});
const child=spawnSync(process.execPath,['tools/collection_gw2/preview.cjs','--out',preview],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);assert.equal(child.status,0,'Production component assembly succeeds');
const entry=preview+'/index.html';let html=fs.readFileSync(entry,'utf8');
html=html.replace(/<title>[^<]*<\/title>/,'<title>收藏背景与搜索移除 · 生产组件离线预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1收藏用户原图 · 生产 XML / JS / CSS · 离线样例 · 未连接游戏、账号或抽取$2');
// Source2's s2r backgrounds remain native in production. The base builder maps
// their authored VTEX recipes to the exact original PNG for the browser only.
const hook=/<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>/;
assert(hook.test(html),'Actual production preview adapter is present');
const nativeBackgroundAdapter=String.raw`<script>const collectionNativeBackgroundLayout=window.syncLayout;window.syncLayout=function(){collectionNativeBackgroundLayout();for(const panel of Object.values(nodes)){const values=panel._style||{};if(values.backgroundImage&&values.backgroundImage.includes("s2r://"))panel.el.style.backgroundImage=values.backgroundImage.replace(/s2r:\/\/[^"\x27)]+/g,uri=>PREVIEW_ASSET_PATHS[uri]||uri);}};</script>`;
html=html.replace(hook,tag=>tag+nativeBackgroundAdapter);
fs.writeFileSync(entry,html);
const assemblyFile=preview+'/assembly.json',assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
const files=[];function walk(dir){if(!fs.existsSync(dir))return;for(const row of fs.readdirSync(dir,{withFileTypes:true})){const file=dir+'/'+row.name;if(row.isDirectory())walk(file);else if(/\.(png|svg|vtex)$/.test(row.name))files.push({path:file,sha256:sha(file)});}}
['art/ui/sources/custom_game/collection_user_skin_v1','panorama/src/images/custom_game/collection_user_skin_v1','art/ui/sources/custom_game/collection_gw2_v2','panorama/src/images/custom_game/collection_gw2_v2'].forEach(walk);
const snapshot={at:new Date().toISOString(),sources:assembly.sourceGraph,assets:files};
fs.writeFileSync(out+'/snapshot.json',JSON.stringify(snapshot,null,2));
assembly.kind='collection_user_skin_production_component_offline_preview';assembly.notGameCapture=true;assembly.snapshot=out+'/snapshot.json';
assembly.limitations.push('Inline s2r texture backgrounds are mapped to their original recipe PNG in this browser-only adapter. Production keeps the native texture binding.');
fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2));
console.log('COLLECTION_USER_SKIN_PREVIEW_BUILT '+preview);
