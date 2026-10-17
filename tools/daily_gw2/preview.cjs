'use strict';
// Reuse the actual active XML graph without altering other menu preview tools.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{spawnSync}=require('child_process'),{pathToFileURL}=require('url');
const repo=path.resolve(__dirname,'../..'),arg=process.argv.indexOf('--out');
const out=path.resolve(repo,arg<0?'design_refs/daily_gw2_v2/work/preview':process.argv[arg+1]);
if(!out.startsWith(repo+path.sep))throw Error('Preview output must remain inside the workspace.');
const child=spawnSync(process.execPath,[path.join(repo,'tools/menus_v10/preview.cjs'),'--out',out],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);if(child.status!==0)throw Error('Production source assembly failed.');
process.chdir(repo);
const fixture=require('./fixture.cjs').fixture(),entry=path.join(out,'index.html');
let html=fs.readFileSync(entry,'utf8');
const oldState=pathToFileURL(path.join(repo,'tools/menus_v10/state.js')).href,newState=pathToFileURL(path.join(__dirname,'state.js')).href;
if(!html.includes('<script src="'+oldState+'"></script>'))throw Error('Expected shared preview state entry was not found.');
const maskManifestFile='design_refs/daily_gw2_v2/work/native_masks/manifest.json';
const maskManifest=JSON.parse(fs.readFileSync(path.join(repo,maskManifestFile),'utf8'));
const browserMasks={};
for(const record of maskManifest.records){
 const bytes=fs.readFileSync(path.join(repo,record.previewPng));
 if(crypto.createHash('sha256').update(bytes).digest('hex')!==record.previewPngSha256)throw Error('Native mask export changed');
 // CSS masks cannot load from file origins in Chromium, unlike normal img.
 // Data URLs contain the exact exported bytes, with no image modification.
 browserMasks[record.uri]='data:image/png;base64,'+bytes.toString('base64');
}
// Daily-only emulation of Panorama's alpha opacity mask, using exact exported
// Valve resources. It leaves the shared adapter and production art untouched.
const maskShim=`<script>(function(){var aliases=${JSON.stringify(browserMasks)};
Object.assign(window.PREVIEW_ASSET_PATHS,aliases);var original=window.syncLayout;
window.syncLayout=function(){original();Object.keys(nodes).forEach(function(id){var n=nodes[id],mask=n._style&&n._style.opacityMask;
if(!mask||!n.el)return;var match=String(mask).match(/url\\(["']?([^"')]+)["']?\\)/);if(!match)return;
var source=aliases[match[1]];if(!source)throw Error('No exact native daily opacity-mask alias: '+match[1]);
n.el.style.maskImage='url("'+source+'")';n.el.style.maskSize='100% 100%';n.el.style.maskRepeat='no-repeat';n.el.style.maskMode='alpha';});};})();</script>`;
html=html.replace('<script src="'+oldState+'"></script>','<script>window.DAILY_GW2_FIXTURE='+JSON.stringify(fixture).replaceAll('</script','<\\/script')+';</script>'+maskShim+'<script src="'+newState+'"></script>');
html=html.replace(/<title>[^<]*<\/title>/,'<title>每日登录 · 实际组件隔离预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1每日登录 · 真实 XML / JS / CSS · 隔离样例进度 · 未连接游戏、账号或奖励$2');
fs.writeFileSync(entry,html);
fs.writeFileSync(path.join(out,'daily_fixture.json'),JSON.stringify(fixture,null,2));
const file=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(file,'utf8'));
assembly.kind='daily_gw2_production_component_browser_preview';assembly.notGameCapture=true;assembly.fixtureRuntimeValues=fixture.runtimeValues;assembly.dailyFixtureSource=fixture.source;
// Correct the inherited manifest's historical helper names to the executed harness.
assembly.previewHarness=['tools/menus_v10/preview.cjs','tools/archive_v10/adapter.js','tools/daily_gw2/preview.cjs','tools/daily_gw2/fixture.cjs','tools/daily_gw2/state.js'].map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(repo,file))).digest('hex')}));
assembly.dailyOpacityMask={nativeManifest:maskManifestFile,exactNativeResources:true,browserAlphaEmulation:true,exactPngDataUrisForFileOrigin:true,aliases:maskManifest.aliases};
assembly.limitations.push('The independent daily window is tested in isolation; other active layouts initialize only as their normal source dependencies. Every outbound GameEvents call is an in-memory stub.');
fs.writeFileSync(file,JSON.stringify(assembly,null,2));
console.log('DAILY_GW2_PREVIEW_BUILT '+path.relative(repo,out));
