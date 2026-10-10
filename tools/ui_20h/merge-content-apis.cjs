const fs=require('fs'),path=require('path'),cp=require('child_process');
const content='D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival';
const files=['scripts/custom_game/archive_handoff_180de7e38b.js','scripts/custom_game/reward_presentation.js','scripts/custom_game/item_art_remaining_5d5c1152eb.js','scripts/custom_game/icons_remaining_5d5c1152eb.js','scripts/custom_game/world_health_bar_anchor.js'];
const out='output/ui_20h/content_api_merge';for(const rel of files){const target='panorama/src/'+rel,saved=out+'/'+rel;fs.mkdirSync(path.dirname(saved),{recursive:true});if(!fs.existsSync(saved))fs.copyFileSync(target,saved);const bytes=cp.execFileSync('git',['-c','safe.directory='+content,'show','HEAD:panorama/'+rel],{cwd:content,maxBuffer:8*1024*1024});fs.writeFileSync(target,bytes);}
console.log('MERGED_CONTENT_PRESENTATION_APIS',files.length,'(includes CardProgress and ApplyPalette; merged health sentinel fix retained)');
