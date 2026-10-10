const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
const classify=source.slice(source.indexOf('    function statVisibility('),source.indexOf('    function buildingPresentation('));
let name='',building=false,hero=false,selected=1;
const env={cfg:{},Entities:{GetUnitName:()=>name,IsBuilding:()=>building,IsHero:()=>hero}};
env.updateTowerAuto=()=>{};vm.createContext(env);vm.runInContext(classify,env);
for(const n of ['npc_archive_challenge_1','npc_archive_challenge_2','npc_archive_challenge_3','building_main_city','building_research_lab','building_advanced_research_lab','building_gold_mine','building_farm','building_wall','building_arrow_tower','building_hero_altar','building_challenge','asset_proxy_tower_lina','asset_proxy_wall_tiny_large_form','npc_dota_unit_ultimate_tower']){
 name=n;assert.equal(env.statVisibility(1).combat,false,n);assert.equal(env.statVisibility(1).attributes,false,n);
}
name='unrecognized_native_building';building=true;assert.equal(env.statVisibility(1).combat,false);building=false;
for(const n of ['npc_survival_wave_monster','npc_survival_named_ten_sin_10','npc_survival_named_rebirth_boss_10','npc_survival_lumberjack','npc_survival_super_lumberjack_04','asset_proxy_monster_boss','npc_survival_builder_proxy']){
 name=n;hero=true;assert.equal(env.statVisibility(1).combat,true,n);assert.equal(env.statVisibility(1).attributes,false,n);
}
for(const n of ['npc_dota_hero_doom_bringer','npc_dota_hero_juggernaut','npc_dota_hero_axe','npc_dota_hero_drow_ranger','npc_dota_hero_monkey_king','npc_dota_hero_nevermore']){
 name=n;hero=true;assert.equal(env.statVisibility(1).combat,true,n);assert.equal(env.statVisibility(1).attributes,true,n);
}
assert.equal(env.statVisibility(-1).combat,false);
// Exercise the actual mirror writer across selection changes, including icons/captions.
const stats=[['attack','a'],['armor','b'],['attack_speed','c'],['strength','d'],['agility','e'],['intelligence','f']],nodes={};
for(const a of stats)for(const prefix of ['HandoffStatIcon_','HandoffStatName_','HandoffStat_','HandoffStatBonus_','HandoffStatPercent_'])nodes[prefix+a[0]]={style:{}};
let multi=false;
Object.assign(env,{generation:1,buildingPresentation(){},stats,nodes,cfg:{SurvivalMultiSelectionPortraits:{IsActive:()=>multi}},ctx:{FindChildTraverse:()=>null},root:{FindChildTraverse:()=>null},valid:p=>!!p,selectedUnit:()=>selected,text(){},topButtons:{vip:{style:{}}},available:()=>false,syncActiveNav(){},style:(p,v)=>{if(p)Object.assign(p.style,v);}});
nodes.HandoffNavIcon_vip={SetImage(){}};
vm.runInContext(source.slice(source.indexOf('    function findCached('),source.indexOf('    function style(')),env);
vm.runInContext(source.slice(source.indexOf('    function mirror()'),source.indexOf('    function compact(')),env);
for(const [n,isHero,expected] of [['npc_dota_hero_doom_bringer',true,[true,true]],['building_farm',false,[false,false]],['npc_survival_named_ten_sin_10',true,[true,false]],['npc_survival_super_lumberjack_04',false,[true,false]],['npc_survival_repairer',false,[false,false]],['npc_dota_hero_axe',true,[true,true]]]){
 name=n;hero=isHero;env.mirror();stats.forEach((a,i)=>{for(const prefix of ['HandoffStatIcon_','HandoffStatName_','HandoffStat_'])assert.equal(nodes[prefix+a[0]].style.visibility,prefix==='HandoffStatIcon_'?'collapse':(expected[i<3?0:1] && !(n.includes('lumberjack') && i===1))?'visible':'collapse',n+' '+prefix+a[0]);});
}
multi=true;env.mirror();assert.equal(nodes.HandoffStat_attack.style.visibility,'collapse');multi=false;env.mirror();assert.equal(nodes.HandoffStat_strength.style.visibility,'visible');
console.log('UNIT_STAT_VISIBILITY_PASS: all building/proxy variants, monsters/Bosses, worker levels, six heroes, live selection switching, all row elements and multiselect recovery');

// Green fixed bonuses never leak into a different unit or multiselect.
let snapshot={entindex:1,attack_max:500,display_attack_bonus:60.7,display_attack_pct:10,armor:12,display_armor_bonus:14,display_armor_pct:20};
env.cfg.HandoffCombat={Snapshot:()=>snapshot};env.compact=n=>String(n);env.text=(id,value)=>{if(nodes[id])nodes[id].text=String(value);};
name='npc_dota_hero_doom_bringer';hero=true;env.mirror();
assert.equal(nodes.HandoffStat_attack.text,'439.3');assert.equal(nodes.HandoffStat_armor.text,'-2');
assert.equal(nodes.HandoffStatBonus_attack.style.visibility,'visible');assert(nodes.HandoffStatPercent_attack.text.includes('10%'));
name='npc_survival_named_ten_sin_10';env.mirror();assert.equal(nodes.HandoffStatBonus_attack.style.visibility,'collapse');
name='npc_dota_hero_doom_bringer';snapshot=null;env.mirror();assert.equal(nodes.HandoffStatBonus_attack.style.visibility,'collapse');
console.log('HERO_BONUS_HUD_PASS: fixed amount + actual percentage, negative armor, monster and stale snapshot isolation');

assert(!nodes.HandoffStatBonus_attack.text.includes('%'));assert(!nodes.HandoffStatBonus_attack.text.includes('('));
name='enemy_tree';env.cfg.HandoffCombat.Snapshot=()=>null;hero=false;
assert.equal(env.statVisibility(1).tree,true);assert.equal(env.statVisibility(1).building,false);
assert.equal(env.statVisibility(1).combat,false);assert.equal(env.statVisibility(1).attributes,false);
env.mirror();for(const a of stats)for(const prefix of ['HandoffStatName_','HandoffStat_','HandoffStatBonus_','HandoffStatPercent_'])assert.equal(nodes[prefix+a[0]].style.visibility,'collapse');
name='unknown_resource_proxy';env.cfg.HandoffCombat.Snapshot=()=>({is_resource_tree:1});assert.equal(env.statVisibility(1).tree,true);assert.equal(env.statVisibility(1).building,false);
name='npc_dota_hero_axe';hero=true;env.cfg.HandoffCombat.Snapshot=()=>null;env.mirror();assert.equal(nodes.HandoffStat_strength.style.visibility,'visible');
console.log('RESOURCE_TREE_CLASSIFICATION_PASS: engine name, resource metadata, no friendly classification, hero recovery');

name='npc_survival_lumberjack';hero=false;multi=true;env.mirror();
assert.equal(nodes.HandoffStat_attack.style.visibility,'visible');
assert.equal(nodes.HandoffStat_attack_speed.style.visibility,'visible');
assert.equal(nodes.HandoffStat_armor.style.visibility,'collapse');
name='npc_survival_repairer';env.mirror();
for(const a of stats)assert.equal(nodes['HandoffStat_'+a[0]].style.visibility,'collapse');
console.log('WORKER_STATS_PASS: repairers none, lumberjacks attack/speed only, including selection queue');

// Cover the actual named wave/practice/challenge definitions, not only examples.
const unitDefinitions=fs.readFileSync('scripts/npc/npc_units_custom.txt','utf8');
const monsterNames=[...unitDefinitions.matchAll(/^    "((?:npc_survival_(?:wave_|named_|rogue_training_dummy)|asset_proxy_(?:monster_|wave_)|zombie_)[^"]*)"/gm)].map(m=>m[1]);
assert(monsterNames.length>50);
env.cfg.HandoffCombat.Snapshot=()=>null;building=false;hero=false;multi=false;
for(const n of monsterNames){
 name=n;const shown=env.statVisibility(1);
 assert.equal(shown.monster,true,n);assert.equal(shown.attributes,false,n);assert.equal(shown.combat,true,n);
 env.mirror();
 for(let i=0;i<stats.length;i++)assert.equal(nodes['HandoffStat_'+stats[i][0]].style.visibility,i<3?'visible':'collapse',n);
}
name='npc_dota_hero_axe';hero=true;
env.Entities.GetTeamNumber=()=>3;
assert.equal(env.statVisibility(1).monster,true);
env.mirror();assert.equal(nodes.HandoffStat_strength.style.visibility,'collapse');
env.Entities.GetTeamNumber=()=>2;
assert.equal(env.statVisibility(1).monster,false);
env.mirror();assert.equal(nodes.HandoffStat_strength.style.visibility,'visible');
for(const n of ['enemy_tree','npc_survival_lumberjack','npc_survival_repairer','npc_survival_doom_infernal','npc_survival_drow_companion','npc_archive_challenge_1']){
 name=n;hero=false;assert(!env.statVisibility(1).monster,n+' must retain its own presentation');
}
console.log('MONSTER_CLASSIFICATION_PASS: '+monsterNames.length+' wave/challenge definitions, native hero enemies, friendly units and selection recovery');
