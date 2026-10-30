const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const reference=JSON.parse(fs.readFileSync('data/balance/original_map_20261025/reference.json','utf8'));
const original=reference.nonwave_units.filter(x=>x.class==='ten_commandments').sort((a,b)=>a.order-b.order);
assert.equal(original.length,10);assert.equal(new Set(original.map(x=>x.name)).size,10);
const t=setup({portrait:true});
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_scenes.js','utf8'),{GameUI:{CustomUIConfig:()=>t.cfg}});
for(const row of original){
 const key='ten_sin_'+String(row.order).padStart(2,'0'),unit='npc_survival_named_'+key;
 assert.equal(t.api.resolveUnitDisplayName(unit,'进入七罪深渊（十宗罪）'),row.name,'old server label cannot overwrite original name');
 assert.equal(t.api.resolveUnitDisplayName(unit,''),row.name);
 for(const file of ['resource/addon_schinese.txt','resource/localization/addon_schinese.txt']){
  assert(fs.readFileSync(file,'utf8').includes('"'+unit+'" "'+row.name+'"'));
 }
 const lua=fs.readFileSync('scripts/vscripts/config/generated/monster_archetypes.lua','utf8');
 assert(lua.split('\n').some(line=>line.includes('archetype_id = "'+key+'"')&&line.includes('display_name = "'+row.name+'"')));
}
console.log('TEN_COMMANDMENT_NAMES_PASS: all ten original ordered names agree with generated config, localization and actual HUD resolver');
