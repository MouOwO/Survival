'use strict';
// Exact resource export for review. Source2Viewer decodes installed pixels.
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/shop_icon_quality_20261017/native');
const v=require('../vpk_inspect.cjs').open(path.resolve(root,'../../dota/pak01_dir.vpk'));
const selected=[
 'econ/tools/redemptiontoken_png.vtex_c','econ/tools/ti7_collectors_cache_redemption_token_png.vtex_c',
 'econ/tools/nested_cache_redemption_token_2015_transparent_png.vtex_c',
 'econ/tools/crownfall_coin_econ_png.vtex_c','econ/tools/treasure_chest_gold_icon_png.vtex_c',
 'econ/tools/compendium_2015_charm_coins_750_png.vtex_c',
 'econ/tools/fall_major_2015_coins_750_png.vtex_c',
 'cointosscoin_psd.vtex_c','hud/reborn/gold_large_png.vtex_c',
 'econ/tools/seasonal_ti10_soccerball_png.vtex_c',
 'econ/crafting/crafting_recipe_scroll_common_png.vtex_c',
 'econ/crafting/crafting_recipe_scroll_evergreen_png.vtex_c',
 'econ/items/alchemist/alchemeyerflask/alchemeyerflask_png.vtex_c',
 'econ/items/alchemist/flask/flask_png.vtex_c',
 'econ/artifacts/winter_embrace_png.vtex_c','econ/artifacts/longclaws_amulet_png.vtex_c',
 'econ/artifacts/oblivions_locket_png.vtex_c','econ/artifacts/precious_egg_png.vtex_c',
 'econ/artifacts/amorphotic_shell_png.vtex_c','econ/artifacts/craggy_coat_png.vtex_c',
 'econ/heroes/omniknight/shoulder_png.vtex_c',
 'spellicons/tinker_keen_teleport_png.vtex_c',
 ...['undying','bloodseeker','dragon_knight','sven','bane','life_stealer','dark_willow','grimstroke','spectre_alt1','doom_bringer'].map(n=>'heroes/selection/npc_dota_hero_'+n+'_png.vtex_c')
];
fs.mkdirSync(out,{recursive:true});const manifest=[];
for(const relative of selected){const resource='panorama/images/'+relative,entry=v.entries.find(e=>e.path===resource);if(!entry)throw Error('Exact native resource missing: '+resource);const bytes=v.read(entry),base=relative.replaceAll('/','__').replace(/\.vtex_c$/,''),compiled=path.join(out,base+'.vtex_c'),png=path.join(out,base+'.png');fs.writeFileSync(compiled,bytes);if(!fs.existsSync(png))cp.execFileSync(path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),['-i',compiled,'-o',png,'-d'],{windowsHide:true,stdio:'pipe'});const b=fs.readFileSync(png);manifest.push({resource,uri:relative.endsWith('_png.vtex_c')?'file://{images}/'+relative.replace(/_png\.vtex_c$/,'.png'):'s2r://panorama/images/'+relative.replace(/\.vtex_c$/,'.vtex'),previewPng:path.relative(root,png).replaceAll('\\','/'),width:b.readUInt32BE(16),height:b.readUInt32BE(20),resourceSha256:crypto.createHash('sha256').update(bytes).digest('hex'),previewSha256:crypto.createHash('sha256').update(b).digest('hex')});}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({records:manifest},null,2)+'\n');
console.log('EXACT_NATIVE_EXPORTED '+manifest.length);
