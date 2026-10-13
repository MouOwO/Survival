'use strict';
// Reuse the actual active XML graph without altering other menu preview tools.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{spawnSync}=require('child_process'),{pathToFileURL}=require('url');
const repo=path.resolve(__dirname,'../..'),arg=process.argv.indexOf('--out');
const out=path.resolve(repo,arg<0?'design_refs/daily_gw2_v1/work/preview':process.argv[arg+1]);
if(!out.startsWith(repo+path.sep))throw Error('Preview output must remain inside the workspace.');
const child=spawnSync(process.execPath,[path.join(repo,'tools/menus_v10/preview.cjs'),'--out',out],{cwd:repo,encoding:'utf8',windowsHide:true});
if(child.stdout)process.stdout.write(child.stdout);if(child.stderr)process.stderr.write(child.stderr);if(child.status!==0)throw Error('Production source assembly failed.');
process.chdir(repo);
const fixture=require('./fixture.cjs').fixture(),entry=path.join(out,'index.html');
let html=fs.readFileSync(entry,'utf8');
const oldState=pathToFileURL(path.join(repo,'tools/menus_v10/state.js')).href,newState=pathToFileURL(path.join(__dirname,'state.js')).href;
if(!html.includes('<script src="'+oldState+'"></script>'))throw Error('Expected shared preview state entry was not found.');
html=html.replace('<script src="'+oldState+'"></script>','<script>window.DAILY_GW2_FIXTURE='+JSON.stringify(fixture).replaceAll('</script','<\\/script')+';</script><script src="'+newState+'"></script>');
html=html.replace(/<title>[^<]*<\/title>/,'<title>每日登录 · 实际组件隔离预览</title>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1每日登录 · 真实 XML / JS / CSS · 隔离样例进度 · 未连接游戏、账号或奖励$2');
fs.writeFileSync(entry,html);
fs.writeFileSync(path.join(out,'daily_fixture.json'),JSON.stringify(fixture,null,2));
const file=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(file,'utf8'));
assembly.kind='daily_gw2_production_component_browser_preview';assembly.notGameCapture=true;assembly.fixtureRuntimeValues=fixture.runtimeValues;assembly.dailyFixtureSource=fixture.source;
// Correct the inherited manifest's historical helper names to the executed harness.
assembly.previewHarness=['tools/menus_v10/preview.cjs','tools/archive_v10/adapter.js','tools/daily_gw2/preview.cjs','tools/daily_gw2/fixture.cjs','tools/daily_gw2/state.js'].map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(repo,file))).digest('hex')}));
assembly.limitations.push('The independent daily window is tested in isolation; other active layouts initialize only as their normal source dependencies. Every outbound GameEvents call is an in-memory stub.');
fs.writeFileSync(file,JSON.stringify(assembly,null,2));
console.log('DAILY_GW2_PREVIEW_BUILT '+path.relative(repo,out));
