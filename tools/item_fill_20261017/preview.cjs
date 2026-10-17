'use strict';
// Snapshot actual production XML/JS/CSS. Fixture accounts never leave this preview.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);
const mode=process.argv[2]||'after';if(!['before','after'].includes(mode))throw Error('Expected before/after');
const out='design_refs/item_fill_20261017/'+mode;
let source=fs.readFileSync('tools/item_resources_20261016/build/preview.cjs','utf8');
source=source.replace("const repo=path.resolve(__dirname,'../../..'),out=path.join(repo,'design_refs/item_resources_20261016/build/preview');",`const repo=process.cwd(),out=path.join(repo,${JSON.stringify(out)});`);
source=source.replace('统一物品资源 · 真实 XML / JS / CSS 与正式数据 · 离线持有样例 · 未连接游戏、账号、抽奖或支付',`图标铺满 ${mode==='before'?'修改前':'修改后'} · 真实 XML / JS / CSS 与正式数据 · 本地持有样例 · 非游戏截图`);
fs.mkdirSync(out,{recursive:true});
const temporary=path.join(out,'build_preview.cjs');fs.writeFileSync(temporary,source);
const run=cp.spawnSync(process.execPath,[temporary],{cwd:repo,encoding:'utf8',windowsHide:true});
if(run.stdout)process.stdout.write(run.stdout);if(run.stderr)process.stderr.write(run.stderr);if(run.status!==0)process.exit(run.status||1);
const filename=path.join(out,'index.html'),adapter='tools/archive_v10/adapter.js';
let html=fs.readFileSync(filename,'utf8');
html=html.replace(require('node:url').pathToFileURL(path.resolve(adapter)).href,'adapter.js');
const aliasesKey='window.PREVIEW_ASSET_PATHS=',aliasesEnd=';window.PREVIEW_BASELINE=',aliasesStart=html.indexOf(aliasesKey)+aliasesKey.length,aliasesStop=html.indexOf(aliasesEnd,aliasesStart),aliases=JSON.parse(html.slice(aliasesStart,aliasesStop)),nativePngAliases=[];
for(const row of JSON.parse(fs.readFileSync('data/ui/item_resources.json','utf8').replace(/^\uFEFF/,'')).items){const match=String(row.uri||'').match(/^s2r:\/\/panorama\/images\/(.+)_png\.vtex$/);if(!match||aliases[row.uri])continue;const relative=match[1]+'.png',source=['art/ui/sources/','panorama/src/images/'].map(prefix=>prefix+relative).find(f=>fs.existsSync(f));if(source){aliases[row.uri]=require('node:url').pathToFileURL(path.resolve(source)).href;nativePngAliases.push({uri:row.uri,source});}}
html=html.slice(0,aliasesStart)+JSON.stringify(aliases)+html.slice(aliasesStop);
fs.writeFileSync(path.join(out,'adapter.js'),fs.readFileSync(adapter,'utf8').replace("v==='stretch-to-fit'?'fill':'contain'","v==='stretch-to-fit'?'fill':v==='stretch-to-cover-preserve-aspect'?'cover':'contain'"));
fs.writeFileSync(filename,html);
{const assemblyFile=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));assembly.localNativePngAliases=nativePngAliases;assembly.scalingAdapter='Native stretch-to-cover-preserve-aspect maps to browser object-fit:cover';assembly.additionalInactiveSources=[];
 const baseline='design_refs/item_fill_20261017/baseline/panorama/src';
 function visit(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const absolute=path.join(dir,entry.name);if(entry.isDirectory())visit(absolute);else if(entry.name.endsWith('.js')){const relative=path.relative(baseline,absolute).replaceAll('\\','/');if(!assembly.sourceGraph.some(row=>row.path===relative)){const contents=fs.readFileSync(mode==='before'?absolute:'panorama/src/'+relative);assembly.additionalInactiveSources.push({path:relative,sha256:require('node:crypto').createHash('sha256').update(contents).digest('hex'),reason:'Legacy module is not included by the current active HUD XML; syntax/native compilation only.'});fs.mkdirSync(path.dirname(path.join(out,'inactive_sources',relative)),{recursive:true});fs.writeFileSync(path.join(out,'inactive_sources',relative),contents);}}}}
 if(fs.existsSync(baseline))visit(baseline);
 fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2)+'\n');}
if(mode==='before'){
 const baseline='design_refs/item_fill_20261017/baseline',key='window.PREVIEW_SOURCES=',endKey=';window.PREVIEW_FIXTURE=';
 const start=html.indexOf(key)+key.length,end=html.indexOf(endKey,start),sources=JSON.parse(html.slice(start,end));
 const assemblyFile=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
 for(const row of assembly.sourceGraph){const backup=path.join(baseline,'panorama/src',row.path);if(fs.existsSync(backup)){sources[row.path]=fs.readFileSync(backup,'utf8').replace(/^\uFEFF/,'');row.sha256=require('node:crypto').createHash('sha256').update(sources[row.path]).digest('hex');}}
 html=html.slice(0,start)+JSON.stringify(sources).replaceAll('</script','<\\/script')+html.slice(end);
 fs.writeFileSync(filename,html);fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2)+'\n');
}
