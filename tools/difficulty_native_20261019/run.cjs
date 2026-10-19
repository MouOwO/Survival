'use strict';
// Reproduce only local material previews. Never changes production sources or calls game services.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const repo=path.resolve(__dirname,'../..'),task=path.join(repo,'output/ui_native_finish_20261019'),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
process.chdir(repo);fs.mkdirSync(path.join(task,'tmp'),{recursive:true});
for(const file of ['build_difficulty.cjs','capture_difficulty.cjs','difficulty_state.js','preview_overlay.cjs','browser.cjs','difficulty_native_themes.json'])fs.copyFileSync(path.join(__dirname,file),path.join(task,file));
for(const file of ['panorama/src/scripts/custom_game/survival_ui.js','panorama/src/styles/custom_game/archive_difficulty.css']){const out=path.join(task,'owned_after',file);fs.mkdirSync(path.dirname(out),{recursive:true});fs.copyFileSync(path.join(repo,file),out);}
const themes=JSON.parse(fs.readFileSync(path.join(__dirname,'difficulty_native_themes.json'),'utf8')).themes,resources=new Map();
for(const theme of themes)for(const key of ['panel','normal','selected','accent'])if(theme[key])resources.set(theme[key].resource,theme[key]);
const missing=[...resources.values()].filter(row=>!fs.existsSync(row.path)||sha(fs.readFileSync(row.path))!==row.pngSha256);
if(missing.length){
 const decoder=process.env.SOURCE2VIEWER_CLI||path.join(repo,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
 if(!fs.existsSync(decoder))throw Error('Set SOURCE2VIEWER_CLI to Source2Viewer-CLI.exe to decode installed official textures.');
 const vpk=require('../vpk_inspect.cjs').open('../../dota/pak01_dir.vpk');
 for(const row of missing){
  const entry=vpk.entries.find(e=>e.path===row.resource);if(!entry)throw Error('Installed Valve resource missing '+row.resource);
  const raw=vpk.read(entry);if(sha(raw)!==row.sha256)throw Error('Installed Valve resource version differs; review before refreshing '+row.resource);
  const png=path.resolve(repo,row.path),input=png.replace(/\.png$/,'.vtex_c');fs.mkdirSync(path.dirname(png),{recursive:true});fs.writeFileSync(input,raw);
  const decoded=cp.spawnSync(decoder,['-i',input,'-o',png,'-d'],{windowsHide:true,stdio:'inherit',env:{...process.env,TEMP:path.join(task,'tmp'),TMP:path.join(task,'tmp')}});if(decoded.status!==0||sha(fs.readFileSync(png))!==row.pngSha256)throw Error('Official texture decode mismatch '+row.resource);
 }
}
for(const script of process.argv.includes('--build-only')?['build_difficulty.cjs']:['build_difficulty.cjs','capture_difficulty.cjs']){
 const result=cp.spawnSync(process.execPath,[path.join(task,script)],{cwd:repo,windowsHide:true,stdio:'inherit',env:{...process.env,TEMP:path.join(task,'tmp'),TMP:path.join(task,'tmp')}});if(result.status!==0)process.exit(result.status||1);
}
