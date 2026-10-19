'use strict';
// Browser-only mapping of official textures used by the actual game controller.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),pack=path.join(root,'design_refs/collection_gold_refine_20261019'),out=path.join(root,'output/collection_gold_refine_20261019/runtime_preview');
const result=spawnSync(process.execPath,[path.join(root,'tools/collection_gw2/preview.cjs'),'--out',out],{cwd:root,encoding:'utf8',windowsHide:true});
if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);assert.equal(result.status,0);
const manifest=JSON.parse(fs.readFileSync(path.join(pack,'manifest.json'))),aliases={};
for(const a of manifest.assets){if(a.source.endsWith('.vtex_c'))aliases['s2r://'+a.source.slice(0,-2)]=pathToFileURL(path.join(pack,a.file)).href;}
const iconNames={close:'24px/x_close.svg',treasure:'24px/treasure.svg',friends:'friends.png',star:'24px/star.svg',rewards:'24px/rewards.svg',trophy:'24px/trophy.svg'};
for(const [key,file]of Object.entries(iconNames)){const a=manifest.assets.find(a=>a.key===key);assert(a,key);aliases['control_icons/'+file]=pathToFileURL(path.join(pack,a.file)).href;}
// Exact official 24px profile.svg; the game uses the built-in vector directly.
aliases['control_icons/24px/profile.svg']=pathToFileURL(path.join(pack,'assets/profile.svg')).href;
aliases['s2r://panorama/images/events/dark_carnival/overworld/inner_panel_border_png.vtex']=pathToFileURL(path.join(pack,'assets/native_sources/window.png')).href;
const file=path.join(out,'index.html'),tag=/<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>/;
let html=fs.readFileSync(file,'utf8');assert(tag.test(html));
const mapping=String.raw`<script>const nativeCollectionLayout=window.syncLayout;window.syncLayout=function(){nativeCollectionLayout();const panels=[root];for(let i=0;i<panels.length;i++){const p=panels[i];panels.push(...p.Children());const v=p._style||{};if(v.backgroundImage&&v.backgroundImage.includes("s2r://"))p.el.style.backgroundImage=v.backgroundImage.replace(/s2r:\/\/[^"\x27)]+/g,uri=>PREVIEW_ASSET_PATHS[uri]||uri);}};</script>`;
html=html.replace(tag,s=>'<script>Object.assign(window.PREVIEW_ASSET_PATHS,'+JSON.stringify(aliases)+');</script>'+s+mapping);fs.writeFileSync(file,html);
console.log('COLLECTION_GOLD_ACTUAL_COMPONENT_PREVIEW_BUILT '+path.relative(root,out));
