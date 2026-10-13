'use strict';
// Assemble the real archive XML/CSS/JS using the existing read-only browser harness.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {spawnSync}=require('child_process');
const {pathToFileURL}=require('url');
const repo=path.resolve(__dirname,'../..');
const index=process.argv.indexOf('--out');
const out=path.resolve(repo,index<0?'design_refs/archive_parchment_v1/work/preview':process.argv[index+1]);
if(!out.startsWith(repo+path.sep))throw Error('Preview output must remain inside the workspace.');
const child=spawnSync(process.execPath,[path.join(repo,'tools/archive_v10/preview.cjs'),'--out',out],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);
if(child.stderr)process.stderr.write(child.stderr);
if(child.status!==0)throw Error('Production archive preview assembly failed.');
const entry=path.join(out,'index.html');
let html=fs.readFileSync(entry,'utf8');
html=html.replace('<title>存档 V10 · 生产组件浏览器预览</title>','<title>羊皮纸存档 · 实际组件隔离预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1羊皮纸存档 · 真实 XML / JS / CSS · 隔离样例进度 · 未连接游戏、账号或奖励$2');
const stateUri=pathToFileURL(path.join(repo,'tools/archive_v10/state.js')).href;
const compatUri=pathToFileURL(path.join(__dirname,'browser_compat.js')).href;
if(!html.includes('<script src="'+stateUri+'"></script>'))throw Error('Existing preview state entry was not found.');
html=html.replace('<script src="'+stateUri+'"></script>','<script src="'+compatUri+'"></script><script src="'+stateUri+'"></script>');
// Chrome exposes scrollbars as pseudo-elements; Panorama uses VerticalScrollBar panels.
// Mirror the current production declarations and their actual textures in this adapter only.
const productionCss=fs.readFileSync(path.join(repo,'panorama/src/styles/custom_game/archive_v10.css'),'utf8');
function scrollbarBody(thumb){
 const selector='#ArchiveV10TooltipViewport VerticalScrollBar'+(thumb?' .ScrollThumb':'');
 const start=productionCss.indexOf(selector+' {');
 if(start<0)throw Error('Production parchment scrollbar declarations are missing.');
 const open=productionCss.indexOf('{',start),lineEnd=productionCss.indexOf('\n',open),end=productionCss.lastIndexOf('}',lineEnd<0?productionCss.length:lineEnd);
 if(end<=open)throw Error('Production scrollbar rule is incomplete.');
 return productionCss.slice(open+1,end).replace(/file:\/\/\{images\}\/([^"')\s]+)/g,(_,relative)=>pathToFileURL(path.join(repo,'art/ui/sources',relative)).href);
}
const browserScrollbar='<style>.ArchiveParchmentPage .panel::-webkit-scrollbar{width:13px;height:13px}.ArchiveParchmentPage .panel::-webkit-scrollbar-track{'+scrollbarBody(false)+'}.ArchiveParchmentPage .panel::-webkit-scrollbar-thumb{'+scrollbarBody(true)+'}</style>';
html=html.replace('<div id="PreviewRoot">',browserScrollbar+'<div id="PreviewRoot">');
fs.writeFileSync(entry,html);
const manifestPath=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(manifestPath,'utf8'));
assembly.kind='archive_parchment_production_component_browser_preview';
assembly.notGameCapture=true;
assembly.fixtureRuntimeValues=JSON.parse(fs.readFileSync(path.join(out,'fixture.json'),'utf8')).v10.runtimeValues;
assembly.previewHarness.push(...['preview.cjs','browser_compat.js'].map(name=>{const file=path.join(__dirname,name);return {path:path.relative(repo,file).replaceAll('\\','/'),sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')};}));
assembly.limitations.push('TextEntry input/value and input event compatibility is scoped to this preview only; actual Panorama input requires game verification.');
assembly.limitations.push('Chrome scrollbar pseudo-elements mirror the current production VerticalScrollBar declarations and original textures; native scrollbar rendering is separately verified in-game.');
fs.writeFileSync(manifestPath,JSON.stringify(assembly,null,2));
console.log('ARCHIVE_PARCHMENT_PREVIEW_BUILT '+path.relative(repo,out));
