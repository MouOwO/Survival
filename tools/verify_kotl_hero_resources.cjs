'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/kotl_hero/audit');
fs.mkdirSync(out,{recursive:true});
const packs=['dota','core'].map(n=>new Vpk(path.resolve(root,'../../'+n+'/pak01_dir.vpk')));
const seen=new Map();
function bytes(resource){
 const local=path.join(root,resource+'_c');if(fs.existsSync(local))return fs.readFileSync(local);
 const pack=packs.find(p=>p.entries.has(resource+'_c'));assert(pack,'Missing resource '+resource);return pack.read(resource+'_c');
}
function inspect(resource){
 if(seen.has(resource))return seen.get(resource);
 const data=bytes(resource);seen.set(resource,'');
 if(!/\.(vpcf|vsndevts)$/.test(resource))return '';
 const file=path.join(out,seen.size+path.extname(resource)+'_c');fs.writeFileSync(file,data);
 let text=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
 text=text.slice(text.indexOf(' block DATA'));seen.set(resource,text);
 for(const m of text.matchAll(/resource:"([^"]+)"/g))if(m[1])inspect(m[1]);
 return text;
}
const line=fs.readFileSync(path.join(root,'data/csv/资源系统/asset_catalog.csv'),'utf8').split(/\r?\n/).find(l=>l.startsWith('hero_permanent_hero_shadow_fiend,'));
assert(line&&line.includes('npc_dota_hero_keeper_of_the_light')&&!line.includes('shadow_fiend.vmdl'));
for(const m of line.matchAll(/(?:models|particles)\/[^"|,\s]+\.(?:vmdl|vpcf)/g))inspect(m[0]);
const ground=seen.get('particles/units/heroes/hero_keeper_of_the_light/keeper_blinding_light_ground.vpcf');
assert(ground&&ground.includes('m_nControlPoint = 2')&&ground.includes('m_flOutput1 = 2000.0'),'ground radius must accept CP2.x in world units');
const sound=inspect('soundevents/game_sounds_heroes/game_sounds_keeper_of_the_light.vsndevts');
assert(sound.includes('Hero_KeeperOfTheLight.BlindingLight ='));
bytes('panorama/images/spellicons/keeper_of_the_light_blinding_light_png.vtex');
const native=bytes('panorama/images/heroes/npc_dota_hero_keeper_of_the_light_png.vtex');
assert(native.equals(bytes('panorama/images/spellicons/survival/native/portrait_keeper_of_the_light_png.vtex')));
fs.writeFileSync(path.join(out,'../resource_audit.json'),JSON.stringify({status:'PASS',resources:[...seen.keys()],native_icon_identical:true,radius_cp:2,in_game_visual_verified:false},null,2)+'\n');
console.log('KOTL_RESOURCES_PASS dependencies='+seen.size+'; body, default wearables, native attack/AoE, CP2 radius, sound and exact native portrait');
