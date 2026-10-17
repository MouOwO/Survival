'use strict';
// Exact installed artwork only. No resize, recolor, generated art or production writes.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'output/shop_icon_quality_20261017/axe_candidates');
const vpk=require('../vpk_inspect.cjs').open(path.resolve(repo,'../../dota/pak01_dir.vpk'));
const selected=['axe/axe_dragonaxe','axe/axe_executioner','axe/blacksmith_weapon','axe/greek_weapon','axe/weapon_heavy_cutter',
 'axe/axeweapon_conq/axeweapon_conq','axe/axe_oryxset_weapon/axe_oryxset_weapon','axe/axe_practos_weapon/axe_practos_weapon',
 'axe/barbarian_of_the_outlands_weapon/barbarian_of_the_outlands_weapon','axe/guillotine_weapon/guillotine_weapon',
 'axe/redguard_weapon/redguard_weapon','axe/redstone_axe/redstone_axe','axe/soulsplitter_weapon/soulsplitter_weapon',
 'axe/torrid_armor_weapon/torrid_armor_weapon','axe/axe_dressed_to_cull_weapon/axe_dressed_to_cull_weapon',
 'beastmaster/double_axe_karroch/double_axe_karroch','beastmaster/legacy_of_the_nords_weapon/legacy_of_the_nords_weapon',
 'beastmaster/chimeras_rage_weapon/chimeras_rage_weapon','beastmaster/korosh_peaks_weapon/korosh_peaks_weapon'];
fs.mkdirSync(out,{recursive:true});const records=[];
for(const item of selected){const resource='panorama/images/econ/items/'+item+'_png.vtex_c',entry=vpk.entries.find(row=>row.path===resource);if(!entry)throw Error('Exact axe resource missing '+resource);const bytes=vpk.read(entry),name=item.replaceAll('/','__'),compiled=path.join(out,name+'.vtex_c'),png=path.join(out,name+'.png');fs.writeFileSync(compiled,bytes);if(!fs.existsSync(png))cp.execFileSync(path.join(repo,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),['-i',compiled,'-o',png,'-d'],{windowsHide:true,stdio:'pipe'});const b=fs.readFileSync(png);records.push({name,resource,uri:'file://{images}/econ/items/'+item+'.png',previewPng:path.relative(repo,png).replaceAll('\\','/'),width:b.readUInt32BE(16),height:b.readUInt32BE(20),resourceSha256:crypto.createHash('sha256').update(bytes).digest('hex'),pngSha256:crypto.createHash('sha256').update(b).digest('hex')});}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({scope:'exact installed native axe candidates; no image editing',records},null,2)+'\n');console.log('AXE_CANDIDATES_EXPORTED '+records.length);
