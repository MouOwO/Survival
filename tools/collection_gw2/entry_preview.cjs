'use strict';
// Read-only execution snapshot of the active HUD navigation and archive chains.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{pathToFileURL}=require('url');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'design_refs/collection_gw2_v2/work/entry_preview');
process.chdir(repo);process.argv=['node',__filename,'--out',out];
const {convertCss}=require('../archive_v10/preview.cjs');
const uri=file=>pathToFileURL(path.join(repo,file)).href,hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const entry=path.join(out,'index.html');let html=fs.readFileSync(entry,'utf8');
function readVariable(name,next){const prefix='window.'+name+'=',start=html.indexOf(prefix)+prefix.length,end=html.indexOf(';window.'+next+'=',start);if(start<prefix.length||end<start)throw Error('Missing variable '+name);return JSON.parse(html.slice(start,end));}
const sources=readVariable('PREVIEW_SOURCES','PREVIEW_FIXTURE'),layouts=readVariable('PREVIEW_LAYOUTS','PREVIEW_SOURCES');
const hudRel='layout/custom_game/survival_hud.xml',hud=sources[hudRel],section=name=>(hud.match(new RegExp('<'+name+'>([\\s\\S]*?)</'+name+'>'))||[])[1]||'';
const includes=text=>[...text.matchAll(/<include\b[^>]*src="file:\/\/\{resources\}\/([^"]+)"/g)].map(match=>match[1]);
const allowed=new Set(['ui_snapshot_cache.js','handoff_boot.js','common/ui_typography.js','common/ui_registry.js','common/ui_components.js','common/tooltip_dismiss.js','ui_layers.js','archive_v10_data.js','common/menu_v10.js','common/purple_shell.js','handoff_assets.js','geometry_remaining_5d5c1152eb.js','topnav_remaining_5d5c1152eb.js','collection_nav.js'].map(file=>'scripts/custom_game/'+file));
const scripts=includes(section('scripts')).filter(file=>allowed.has(file));
for(const file of allowed)if(!scripts.includes(file))throw Error('Active HUD chain missing '+file);
// Preserve the authored root classes and HandoffHUD node, filtering unrelated
// static HUD branches whose controllers are deliberately not executed here.
const rootTag=hud.match(/<Panel class="SurvivalHUDRoot[^>]*>/)?.[0],host=hud.match(/<Panel id="HandoffHUD"[^>]*\/>/)?.[0];
if(!rootTag||!host)throw Error('Active authored HUD anchors not found');
const hudLayout={rel:hudRel,xml:'<root>'+rootTag+host+'</Panel></root>',styles:includes(section('styles')),scripts};
layouts.unshift(hudLayout);
html=html.replace(/window\.PREVIEW_LAYOUTS=[\s\S]*?;window\.PREVIEW_SOURCES=/,'window.PREVIEW_LAYOUTS='+JSON.stringify(layouts).replaceAll('</script','<\\/script')+';window.PREVIEW_SOURCES=');
const css=hudLayout.styles.map(file=>'/* '+file+' */\n'+convertCss(sources[file])).join('\n')+'\n'+fs.readFileSync(path.join(out,'style.css'),'utf8');
fs.writeFileSync(path.join(out,'style.css'),css);
const oldState=uri('tools/archive_v10/state.js'),fixture=require('./fixture.cjs').fixture();
// Browser-only cursor mock: production policy reads the coordinates of actual
// DOM pointer movement. Capture mouseover too, before per-panel mouseenter.
const cursorMock='<script>window.previewCursorMock={kind:"DOM mouse coordinates",native:false,position:[-10000,-10000]};["mousemove","mouseover"].forEach(function(type){document.addEventListener(type,function(event){previewCursorMock.position=[event.clientX,event.clientY];},true);});GameUI.GetCursorPosition=function(){return previewCursorMock.position.slice();};</script>';
html=html.replace('<script src="'+oldState+'"></script>','<script>window.COLLECTION_GW2_FIXTURE='+JSON.stringify(fixture).replaceAll('</script','<\\/script')+';</script>'+cursorMock+'<script src="'+uri('tools/collection_gw2/browser_compat.js')+'"></script><script src="'+uri('tools/collection_gw2/entry_state.js')+'"></script>');
html=html.replace(/<title>[^<]*<\/title>/,'<title>收藏入口 · 真实导航源码隔离预览</title>').replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1真实导航 / 收藏源码 · native HUD 占位 / 数值样例 · 未连接游戏或账号$2');
// The old battlefield reference has baked HUD pixels. Use a neutral harness
// background so it cannot be confused with a second set of live controls.
html=html.replace(/body\{background:#151127 url\([^}]+\}/,'body{background:#202830}');
fs.writeFileSync(entry,html);
const assembly=JSON.parse(fs.readFileSync(path.join(out,'assembly.json'),'utf8'));
Object.assign(assembly,{kind:'collection_entry_actual_topnav_browser_preview',notGameCapture:true,nativeFixture:true,outboundStubs:true,cursorMock:{api:'GameUI.GetCursorPosition',source:'DOM mousemove/mouseover capture',native:false},layouts:layouts.map(({rel,scripts,styles})=>({rel,scripts,styles})),readOnlyUserSource:{path:'panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js',sha256:hash('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js'),compiled:false,edited:false},hudMarkupFiltering:'Authored root classes and HandoffHUD node retained; unrelated static HUD branches omitted. Full original XML is frozen in PREVIEW_SOURCES.',omittedHudScripts:includes(section('scripts')).filter(file=>!allowed.has(file))});
assembly.previewHarness=['tools/archive_v10/preview.cjs','tools/archive_v10/adapter.js','tools/collection_gw2/browser_compat.js','tools/collection_gw2/fixture.cjs','tools/collection_gw2/entry_preview.cjs','tools/collection_gw2/entry_state.js'].map(file=>({path:file,sha256:hash(file)}));
assembly.assets=['art/ui/sources/custom_game/topnav_reference_v2/collection.svg'].filter(file=>fs.existsSync(file)).map(file=>({path:file,sha256:hash(file)}));
assembly.limitations.push('Actual current topnav is executed read-only, including its stable-frame reveal. Native panel hierarchy, selected entity and resource snapshot are explicit fixtures; this is not a native HUD/game capture. Outbound events only append to local memory. A neutral browser background replaces the old screenshot containing baked HUD pixels.');
fs.writeFileSync(path.join(out,'assembly.json'),JSON.stringify(assembly,null,2));
console.log('COLLECTION_ENTRY_PREVIEW_BUILT '+path.relative(repo,out));
