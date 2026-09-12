const fs=require('fs'),path=require('path'),crypto=require('crypto'),vm=require('vm');
const base=process.argv[2]||'D:/新建文件夹/daily_rewards_ui_v1/daily_rewards_ui_v1';
const out='art/ui/development/daily_rewards_import',src='panorama/src';fs.mkdirSync(out,{recursive:true});
const manifest=JSON.parse(fs.readFileSync(path.join(base,'specs/asset_manifest.json'),'utf8'));
const cfg={};vm.runInNewContext(fs.readFileSync(src+'/scripts/custom_game/common/ui_registry.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const assets={},report=[];
for(const [id,a] of Object.entries(manifest.assets)) {
 const bytes=fs.readFileSync(path.join(base,a.file));
 if(crypto.createHash('sha256').update(bytes).digest('hex')!==a.sha256)throw Error('Asset hash mismatch: '+id);
 if(a.file.startsWith('shared/')) {
  if(!cfg.SurvivalUIRegistry.assets[id])throw Error('Shared ID missing: '+id);
  report.push({id,action:'reuse_existing',quality:a.quality});continue;
 }
 if(!a.file.startsWith('runtime/'))continue;
 const runtime='ui/daily_rewards/'+a.file.slice(8),dest=src+'/images/'+runtime;
 fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,bytes);
 assets[id]={runtime,size:a.size_px,source_sha256:a.sha256,quality:a.quality};
 report.push({id,action:'local_skin',file:runtime,quality:a.quality});
}
fs.writeFileSync(src+'/scripts/custom_game/daily_resources.js','(function(){var r=GameUI.CustomUIConfig().SurvivalUIRegistry;var a='+JSON.stringify(assets)+';Object.keys(a).forEach(function(id){if(r.assets[id]&&JSON.stringify(r.assets[id])!==JSON.stringify(a[id]))throw new Error("Daily ID collision: "+id);r.assets[id]=a[id];});})();\n');
fs.writeFileSync(out+'/assets.json',JSON.stringify(assets,null,2));fs.writeFileSync(out+'/reuse_mapping.json',JSON.stringify(report,null,2));
for(const file of ['layout.json','reuse_map.json','state_matrix.json','asset_manifest.json','motion.json'])fs.copyFileSync(path.join(base,'specs',file),out+'/'+file);
let css='/* Generated from supplied runtime assets; no exact/baked labels. */\n';
const url=id=>'url("file://{images}/'+assets[id].runtime+'")';
for(const [selector,baseId] of [['.DailyClaimSkin','daily.button.claim'],['.DailyNormalCard','daily.card.empty'],['.DailyWeekCard','daily.card.week_end']]) {
 const normal=assets[baseId+'.normal']?baseId+'.normal':baseId;
 css+=`${selector} { background-image: ${url(normal)}; background-size: 100% 100%; }\n`;
 for(const state of ['hover','pressed','disabled'])css+=`${selector}${state==='pressed'?':active':':'+state} { background-image: ${url(baseId+'.'+state)}; }\n`;
}
for(const name of ['close_local','rules_local','pass'])for(const state of ['normal','hover','pressed','disabled']) {
 const sel=state==='normal'?'':state==='pressed'?':active':':'+state;
 css+=`.DailyIcon_${name}${sel} .DailyIconArt { background-image: ${url('daily.icon.'+name+'.'+state)}; }\n`;
}
// Native compiler discovers PNG textures via CSS dependencies, not raw PNG -i.
for(const id of Object.keys(assets))css+=`.DailyPreload_${id.replaceAll('.','_')} { background-image: ${url(id)}; }\n`;
fs.writeFileSync(src+'/styles/custom_game/daily_assets.css',css);
console.log('DAILY_IMPORT_PASS: '+Object.keys(assets).length+' verified runtime assets; shared IDs retained.');
