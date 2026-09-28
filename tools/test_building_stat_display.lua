package.path="scripts/vscripts/?.lua;"..package.path
local display=require("ui/building_stat_display")
local cfg=require("config/buildings_config")
local routes=require("config/tower_route_config")
local wall={survival_building_id="wall",survival_level=1,survival_base_war3_armor=10,survival_hud_stat_bonuses={health_bonus=500,armor_bonus=7}}
local s=display.apply(wall,{level=1,max_health=2500,armor=17,effective_war3_armor=17})
assert(s.building_id=="wall" and s.building_stat_details.health_base==2000)
assert(s.building_stat_details.health_bonus==500 and s.building_stat_details.armor_bonus==7)
wall.survival_level=2;wall.survival_base_war3_armor=15;wall.survival_hud_stat_bonuses={health_bonus=1800,armor_bonus=10}
s=display.apply(wall,{level=2,max_health=4800,armor=25})
assert(s.building_stat_details.health_bonus==1800 and s.building_stat_details.armor_bonus==10)
for _,class in ipairs({false,"class_1","class_3","class_7"}) do
 local level=class and 6 or 1
 local row=routes.current({level=level,tower_class=class or nil})
 local unit={survival_building_id="arrow_tower",survival_level=level,survival_tower_class=class or nil,survival_hud_stat_bonuses={attack_bonus=123}}
 local snapshot=display.apply(unit,{attack_max=row.base_attack_damage+123})
 assert(snapshot.building_stat_details.attack_bonus==123)
 unit.survival_hud_base_attack=900;unit.survival_hud_stat_bonuses={attack_bonus=200}
 snapshot=display.apply(unit,{attack_max=1100})
 assert(snapshot.building_stat_details.attack_base==900 and snapshot.building_stat_details.attack_bonus==200)
 snapshot=display.apply(unit,{attack_max=800})
 assert(snapshot.building_stat_details.attack_bonus==200)
end
local hero={};s={attack_max=20};assert(display.apply(hero,s)==s and not s.building_id)
for id in pairs(cfg) do if type(cfg[id])=="table" and cfg[id].levels then
 local unit={survival_building_id=id,survival_level=1}
 assert(display.apply(unit,{}).building_id==id:gsub("^building_", ""))
end end
print("BUILDING_STAT_DETAILS_PASS: wall health/armor, upgrades, ordinary and routed tower bonuses, runtime base override, debuff and non-building isolation")
