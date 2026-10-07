return function(c)
local check,near,private,set,unit,hero,bus,ev,totals=c.check,c.near,c.private,c.set,c.unit,c.hero,c.bus,c.ev,c.totals
check('starjoy_resource_and_hit_growth',function()
 set({initial_wood=10,hero_initial_gold=5000,hero_damage_wood_flat=8,hero_basic_attack_growth=64})
 local before=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0})
 bus.emit(ev.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker=hero,final_damage=100})
 near(bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood-before.wood,8)
 local attack=totals().hero_attack_flat
 bus.emit(ev.HERO_MAIN_ATTACK_LANDED,{player_id=0});near(totals().hero_attack_flat-attack,64)
 local tower=unit(901);tower.survival_player_id=0
 set({tower_basic_attack_growth=10,tower_damage_attack_growth=20})
 bus.emit(ev.TOWER_ATTACK_LANDED,{tower=tower,target=unit(902),damage=100})
 near(tower.survival_tower_personal_attack_growth,30)
 return 'actual resource wallet +8 wood on damage, hero +64 attack per hit, tower +30 personal attack'
end)
check('starjoy_tower_range_critical_and_cap',function()
 local m=require('systems/building_upgrade_system');local apply=assert(private(m.init,'apply_research_technology'))
 local tower=unit(903);function tower:Script_SetAttackRange(v)self.range=v end
 local state={unit=tower,player_id=0,building_id='arrow_tower',level=1,definition={levels={{attack=100,health=1000,armor=10}}},research_base_attack_damage=100}
 private(m.init,'buildings')[tower:entindex()]=state
 set({});apply(state,'audit');local range=tower.range
 set({tower_attack_range=500,tower_critical_chance_pct=8,tower_critical_damage_bonus_pct=25,gold_mine_build_cap=1})
 apply(state,'audit');near(tower.range,range+500);near(tower.survival_super_tower_crit_chance,8);near(tower.survival_gameplay_critical_damage_pct,225)
 apply(state,'audit');near(tower.survival_super_tower_crit_chance,8)
 near(require('systems/building_count_limit_service').maximum(2,'gold_mine',0),3)
 near(require('systems/building_count_limit_service').maximum(2,'arrow_tower',0),2)
 return 'engine tower range +500, crit 8% / 225% stable on refresh, mine build cap 2 -> 3'
end)
check('starjoy_worker_personal_growth',function()
 local m=require('systems/worker_system');local workers=assert(private(m.init,'workers'));local hit=assert(private(m.init,'on_tree_hit'))
 local u=unit(904);workers[904]={unit=u,worker_type='lumberjack',player_id=0,base_attack_interval=2,base_damage_min=10,base_damage_max=10,technology_multiplier=1}
 set({lumberjack_attack_growth=8});hit({source='lumberjack',player_id=0,attacker=u})
 near(workers[904].attack_growth,8);near(u.damage,18)
 return 'actual tree hit: individual worker attack 10 -> 18'
end)
check('starjoy_hero_health_armor_reduction',function()
 local m=require('systems/hero_combat_stat_service');local state=private(m.init,'state_by_player')[0];local recalc=assert(private(m.init,'recalculate'))
 state.definition.base_health=1000;state.definition.base_war3_armor=10
 set({});local base=recalc(0,'audit');local baseHealth=hero.survival_base_max_health
 set({hero_health_bonus_pct=20,hero_armor_bonus_pct=20,hero_damage_reduction_pct=5,hero_critical_chance_pct=25})
 local result=recalc(0,'audit');near(hero.survival_base_max_health,math.floor(baseHealth*1.2));near(result.armor,base.armor*1.2);near(result.critical_chance_pct,base.critical_chance_pct+25)
 near(hero.survival_gameplay_damage_reduction_pct,5)
 local filter=require('combat/damage_filter_service');local attacker=unit(905);local victim=unit(906);victim.team=3;victim.survival_gameplay_damage_reduction_pct=5
 EntIndexToHScript=function(i)return i==905 and attacker or victim end
 local keys={damage=100,entindex_attacker_const=905,entindex_victim_const=906,damagetype_const=2}
 assert(filter._filter_for_test(nil,keys));near(keys.damage,95)
 return 'configured health +20%, armor +20%, crit +25%; actual damage filter 100 -> 95'
end)
check('starjoy_training_room_multiplier',function()
 local old=package.loaded['systems/technology_stat_manager'];package.loaded['systems/technology_stat_manager']=nil
 local m=require('systems/technology_stat_manager');set({training_room_income_bonus_pct=23})
 local target=unit(907);target.survival_training_owner_player_id=0
 m.set_training_room_state(0,true,2,'audit')
 near(m.training_room_multiplier(0,target),2.46)
 target.survival_training_owner_player_id=1;near(m.training_room_multiplier(0,target),1)
 package.loaded['systems/technology_stat_manager']=old
 return 'real training reward multiplier 2 -> 2.46, outside owned room remains 1'
end)
end
