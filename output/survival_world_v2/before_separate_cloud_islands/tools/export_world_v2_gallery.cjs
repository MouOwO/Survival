const fs=require('fs'),path=require('path'),cp=require('child_process');
const dir='D:/steam/steamapps/common/dota 2 beta/game/dota/screenshots';
const out=path.resolve(__dirname,'../output/survival_world_v2');
const keys=['overview','central_island','upper_training','lower_training','snow_camps','boss_islands','tree_close','shallow_lake','volcanic_arena','camp_transition','mountain_canopy','grass_paving','prison_floor'];
keys.push('hot_spring','camp_boundary','grass_detail');
keys.push('island_levels','island_stairs');
keys.push('training_close','boss_close','original_challenge');
keys.push('tower_stairs');
keys.push('cloud_edge','cloud_band');
const result=[];
for(const key of keys){const matches=fs.readdirSync(dir).filter(n=>n.startsWith('world_v2_'+key+'_')&&n.endsWith('.tga')).sort((a,b)=>fs.statSync(path.join(dir,b)).mtimeMs-fs.statSync(path.join(dir,a)).mtimeMs);if(!matches.length)throw Error('No actual screenshot: '+key);const file=matches[0];cp.execFileSync(process.execPath,[path.join(__dirname,'capture_dota_image.cjs'),file,path.join(out,key+'.png')]);result.push({view:key,source:file,timestamp:fs.statSync(path.join(dir,file)).mtime.toISOString()});}
fs.writeFileSync(path.join(out,'screenshot_manifest.json'),JSON.stringify(result,null,2));
console.log(result);
