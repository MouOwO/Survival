'use strict';
// Execute the actual archive component chain; topnav_remaining is never loaded.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{spawnSync}=require('child_process'),{pathToFileURL}=require('url');
const repo=path.resolve(__dirname,'../..'),arg=process.argv.indexOf('--out');
const out=path.resolve(repo,arg<0?'design_refs/collection_gw2_v1/work/preview':process.argv[arg+1]);
if(!out.startsWith(repo+path.sep))throw Error('Preview output must remain inside the workspace.');
process.chdir(repo);
const child=spawnSync(process.execPath,[path.join(repo,'tools/archive_v10/preview.cjs'),'--out',out],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);if(child.status!==0)throw Error('Production source assembly failed.');
const fixture=require('./fixture.cjs').fixture(),entry=path.join(out,'index.html');
let html=fs.readFileSync(entry,'utf8');
const oldState=pathToFileURL(path.join(repo,'tools/archive_v10/state.js')).href,newState=pathToFileURL(path.join(__dirname,'state.js')).href,compat=pathToFileURL(path.join(__dirname,'browser_compat.js')).href;
if(!html.includes('<script src="'+oldState+'"></script>'))throw Error('Expected archive preview state entry was not found.');
// The reusable builder snapshots all active layouts; remove unrelated source text
// so this isolated artifact cannot accidentally execute the user's dirty topnav.
const prefix='window.PREVIEW_SOURCES=',suffix=';window.PREVIEW_FIXTURE=',start=html.indexOf(prefix)+prefix.length,end=html.indexOf(suffix,start);
if(start<prefix.length||end<start)throw Error('Production source snapshot was not found.');
const sources=JSON.parse(html.slice(start,end)),excluded=Object.keys(sources).filter(file=>/topnav_remaining/.test(file));
for(const file of excluded)delete sources[file];
if(!sources['scripts/custom_game/collection_nav.js'])throw Error('Active HUD graph does not provide collection_nav.js.');
html=html.slice(0,start)+JSON.stringify(sources).replaceAll('</script','<\\/script')+html.slice(end);
html=html.replace('<script src="'+oldState+'"></script>','<script>window.COLLECTION_GW2_FIXTURE='+JSON.stringify(fixture).replaceAll('</script','<\\/script')+';</script><script src="'+compat+'"></script><script src="'+newState+'"></script>');
html=html.replace(/<title>[^<]*<\/title>/,'<title>收藏 · 实际组件隔离预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1收藏 · 真实 XML / JS / CSS · 隔离样例 · 导航为最小 HUD 夹具 · 未连接游戏或抽取$2');
// Native scrollbar panels are CSS pseudo-elements in Chrome. Copy their authored
// declarations only; geometry, portraits and all component textures remain real.
const collectionCss=fs.readFileSync(path.join(repo,'panorama/src/styles/custom_game/collection_gw2.css'),'utf8');
const track=collectionCss.match(/#CollectionWindow VerticalScrollBar\s*\{([^}]+)\}/),thumb=collectionCss.match(/#CollectionWindow VerticalScrollBar \.ScrollThumb\s*\{([^}]+)\}/);
if(!track||!thumb)throw Error('Production collection scrollbar declarations are missing.');
html=html.replace('<div id="PreviewRoot">','<style>#CollectionWindow .panel::-webkit-scrollbar{'+track[1]+'}#CollectionWindow .panel::-webkit-scrollbar-track{'+track[1]+'}#CollectionWindow .panel::-webkit-scrollbar-thumb{'+thumb[1]+'}</style><div id="PreviewRoot">');
fs.writeFileSync(entry,html);fs.writeFileSync(path.join(out,'collection_fixture.json'),JSON.stringify(fixture,null,2));
const file=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(file,'utf8'));
assembly.kind='collection_gw2_production_component_browser_preview';assembly.notGameCapture=true;assembly.fixtureRuntimeValues=fixture.runtimeValues;assembly.collectionFixtureSource=fixture.source;assembly.excludedUserEditedSources=excluded;assembly.sourceGraph=assembly.sourceGraph.filter(record=>!excluded.includes(record.path));
assembly.previewHarness=['tools/archive_v10/preview.cjs','tools/archive_v10/adapter.js',...['preview.cjs','browser_compat.js','fixture.cjs','state.js'].map(name=>'tools/collection_gw2/'+name)].map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(repo,file))).digest('hex')}));
assembly.limitations.push('The independent collection and actual collection_nav extension run against a minimal HandoffHUD/HandoffTop fixture. This is not a full HUD or native game capture. The pre-existing user-edited topnav_remaining script is excluded from the snapshot and execution.');
assembly.limitations.push('Every outbound GameEvents call is a memory-only stub. Formal portraits/names/effects come from repository CSV; ownership and ticket balances are synthetic. Wife remains unconfigured and never sends a pool request.');
fs.writeFileSync(file,JSON.stringify(assembly,null,2));
console.log('COLLECTION_GW2_PREVIEW_BUILT '+path.relative(repo,out));
