-- Audit-only extension: no gameplay implementation or real player state is changed.
return function(c)
local check,near,private,set,unit,hero,bus,ev,totals=c.check,c.near,c.private,c.set,c.unit,c.hero,c.bus,c.ev,c.totals
check('vip_attack_efficiency_requires_base',function()
 set({hero_attribute_growth=0,hero_attributes_per_damage=59.5,hero_attack_attribute_efficiency_pct=15})
 local a=totals().hero_all_attributes_flat;bus.emit(ev.HERO_MAIN_ATTACK_LANDED,{player_id=0});near(totals().hero_all_attributes_flat-a,0)
 set({hero_attribute_growth=10,hero_attack_attribute_efficiency_pct=15});a=totals().hero_all_attributes_flat
 bus.emit(ev.HERO_MAIN_ATTACK_LANDED,{player_id=0});near(totals().hero_all_attributes_flat-a,11.5)
 return 'VIP9+10 +15% only multiplies attack-based attribute growth; damage-based attribute growth is a different field'
end)
check('vip_tower_flat_and_wall_reduction',function()
 local m=require('systems/building_upgrade_system');local apply=assert(private(m.init,'apply_research_technology'))
 local tower=unit(960);local state={unit=tower,player_id=0,building_id='arrow_tower',level=1,definition={levels={{attack=100,health=1000,armor=10}}},research_base_attack_damage=100}
 private(m.init,'buildings')[960]=state
 set({tower_attack_flat=300,tower_attack_bonus_pct=8});apply(state,'audit');near(tower.damage,432)
 local wall=unit(961);state={unit=wall,player_id=0,building_id='wall',level=1,definition={levels={{health=1000,war3_armor=10,armor=10}}}}
 private(m.init,'buildings')[961]=state
 set({wall_damage_reduction_pct=3});apply(state,'audit');near(wall.survival_gameplay_damage_reduction_pct,3)
 local enemy=unit(962);enemy.team=3;EntIndexToHScript=function(i)return i==962 and enemy or wall end
 local keys={damage=100,entindex_attacker_const=962,entindex_victim_const=961,damagetype_const=2}
 assert(require('combat/damage_filter_service')._filter_for_test(nil,keys));near(keys.damage,97)
 return 'VIP2 tower +300 enters actual damage (100+300)*1.08=432; VIP4 wall reduction 100->97'
end)
check('laser_cadence_from_saved_rewards',function()
 local m=require('systems/building_upgrade_system');local apply=assert(private(m.init,'apply_research_technology'))
 local tower=unit(970);local state={unit=tower,player_id=0,building_id='arrow_tower',level=1,definition={levels={{attack=100,health=1000,armor=10}}},research_base_attack_damage=100}
 private(m.init,'buildings')[970]=state
 local interval=require('systems/tower_laser_damage').interval
 set({});apply(state,'audit');local base=interval(tower,{damage_interval=1})
 set({tower_attack_speed_bonus_pct=10});apply(state,'audit');near(interval(tower,{damage_interval=1}),base/1.1)
 apply(state,'audit');near(interval(tower,{damage_interval=1}),base/1.1)
 set({tower_attack_speed_bonus_pct=15});apply(state,'audit');near(interval(tower,{damage_interval=1}),base/1.15)
 set({});apply(state,'audit');near(interval(tower,{damage_interval=1}),base)
 return 'saved VIP/welfare +10% and +15% haste changes actual laser cadence; repeated refresh does not stack again; removal restores baseline'
end)

end
