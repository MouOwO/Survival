'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..');
require('./dump_layout.cjs');
const out=path.join(root,'output/survival_shop_nav_20261017'),dump=JSON.parse(fs.readFileSync(path.join(out,'layout_states.json'),'utf8'));
const fileURL=file=>pathToFileURL(file).href;
const escapeJSON=value=>JSON.stringify(value).replaceAll('<','\\u003c');
const sources=['tools/archive_v10/adapter.js','panorama/src/styles/custom_game/handoff_v1.css','panorama/src/styles/custom_game/topnav_refinement_v5.css'];
const sourceHashes={...dump.sources};
for(const name of sources)sourceHashes[name]=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex');
const html=`<!doctype html><meta charset="utf-8"><title>生存商店导航 · 本地布局预览</title>
<style>
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#233b3f}body{background:linear-gradient(130deg,#1a343b,#3b5154)}
.panel{position:absolute;display:block;box-sizing:border-box;flex:none}.label{margin:0;line-height:normal}img.panel{object-fit:contain}
[hidden]{display:none!important}#PreviewRoot{position:absolute;left:0;top:0;transform-origin:0 0}
</style>
<link rel="stylesheet" href="${fileURL(path.join(root,sources[1]))}"><link rel="stylesheet" href="${fileURL(path.join(root,sources[2]))}">
<div id="PreviewRoot"></div>
<script>const PREVIEW_ASSET_PATHS={},IMAGE_ROOT=${escapeJSON(fileURL(path.join(root,'panorama/src/images'))+'/')},IMAGE_FALLBACK_ROOT=IMAGE_ROOT,PREVIEW_FIXTURE={nativeBitmaps:[]},PREVIEW_LAYOUTS=[],PREVIEW_SOURCES=null,PREVIEW_SOURCE_ROOT='';window.LAYOUT_DUMP=${escapeJSON(dump)};</script>
<script src="${fileURL(path.join(root,sources[0]))}"></script>
<script>
window.previewScale=1;root.style.transform='none';root.style.width=innerWidth+'px';root.style.height=innerHeight+'px';
const state=LAYOUT_DUMP.states.find(s=>s.name===new URLSearchParams(location.search).get('state'))||LAYOUT_DUMP.states[0];
function render(source,parent){
 const panel=new Panel(source.type,parent,source.id);for(const cls of source.classes)panel.AddClass(cls);
 for(const [key,value]of Object.entries(source.style))panel.style[key]=value;
 if(source.image)panel.SetImage(source.image);if(source.text)panel.text=source.text;
 panel.enabled=source.enabled;panel.visible=source.visible!==false;
 for(const child of source.children)render(child,panel);return panel;
}
render(state.top,root);render(state.collection,root);const shortcut=render(state.heroShortcut,root);
// The model ScenePanel has no bitmap in the native API double. Keep its exact
// production rectangle, with an explicitly labelled preview-only placeholder.
shortcut.el.style.border='1px dashed #a5b6b3';shortcut.el.style.background='#17323a';shortcut.el.style.color='#a5b6b3';shortcut.el.style.font='14px Microsoft YaHei';shortcut.el.style.display='grid';shortcut.el.style.placeItems='center';shortcut.el.textContent='英雄头像';
syncLayout();window.previewState=state.name;window.previewReady=true;
</script>`;
fs.writeFileSync(path.join(out,'preview.html'),html);
fs.writeFileSync(path.join(out,'preview_assembly.json'),JSON.stringify({scope:'Production-created panel dump rendered through existing local Panorama adapter. Native SVGs are original project assets. Not a live-game capture.',sourceHashes,heroShortcut:'64×64 labelled placeholder preserves production geometry; model rendering is outside this local preview.',noAccountOrGameOperations:true},null,2)+'\n');
console.log(path.join(out,'preview.html'));
