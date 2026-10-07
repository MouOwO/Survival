return function(c)
local check,near,private,set,unit,hero,bus,ev,totals=c.check,c.near,c.private,c.set,c.unit,c.hero,c.bus,c.ev,c.totals
check('vip_decimal_damage_growth',function()
 set({hero_damage_attack_growth=1.5,hero_attributes_per_damage=1.5,tower_damage_attack_growth=1.5})
 local a=totals();bus.emit(ev.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker=hero,final_damage=100})
 local b=totals();near(b.hero_attack_flat-a.hero_attack_flat,1.5);near(b.hero_all_attributes_flat-a.hero_all_attributes_flat,1.5)
 local tower=unit(950);tower.survival_player_id=0;bus.emit(ev.TOWER_ATTACK_LANDED,{tower=tower,target=unit(951),damage=100})
 near(tower.survival_tower_personal_attack_growth,1.5)
 return 'real damage callbacks preserve V2 hero/tower +1.5 increments'
end)
check('vip_damage_wood_percentage',function()
 set({initial_wood=10,hero_damage_wood_flat=10,hero_damage_wood_bonus_pct=10})
 local a=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood
 bus.emit(ev.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker=hero,final_damage=100})
 near(bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood-a,11)
 set({initial_wood=10,hero_damage_wood_flat=0,hero_damage_wood_bonus_pct=10})
 a=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood
 bus.emit(ev.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker=hero,final_damage=100})
 near(bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood-a,0)
 return '10 base wood -> 11 credited; zero base remains zero'
end)
check('vip_wood_and_population_refresh',function()
 set({initial_wood=10,initial_population_cap=0})
 bus.request(ev.RESOURCE_ADD_REQUEST,{player_id=0,max_population=14,reason='test_building'})
 local a=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0})
 set({initial_wood=260,initial_population_cap=5})
 local b=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0});near(b.wood-a.wood,250);near(b.max_population-a.max_population,5)
 set({initial_wood=260,initial_population_cap=5})
 local d=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0});near(d.wood,b.wood);near(d.max_population,b.max_population)
 return 'real wallet +250 wood, building population +5, repeated profile refresh grants nothing'
end)
check('vip_lumber_critical_yield',function()
 local m=require('systems/worker_system');local workers=assert(private(m.init,'workers'));local refresh=assert(private(m.init,'refresh_worker_technology'))
 local ai_class=require('modifiers/modifier_lumberjack_ai');local u=unit(952)
 function u:GetUnitName()return 'npc_survival_lumberjack' end
 local ai=setmetatable({player_id=0,base_lumber_efficiency=20,tree_lumber_efficiency_buff=0,technology_lumber_efficiency=0,technology_armor_reduction=0},{__index=ai_class})
 function ai:GetParent()return u end
 u.mods.modifier_lumberjack_ai=ai
 workers[952]={unit=u,worker_type='lumberjack',player_id=0,base_attack_interval=2,base_damage_min=10,base_damage_max=10,base_lumber_efficiency=20}
 set({lumberjack_attack_efficiency=13,lumberjack_critical_chance_pct=10,lumberjack_critical_yield_bonus_pct=20});refresh(0,'vip_audit')
 near(ai.technology_crit_chance,10);near(ai.critical_yield_bonus_pct,20)
 local trees=require('systems/tree_system');local hit=assert(private(trees.init,'on_tree_hit'));local t=unit(953)
 function t:GetUnitName()return 'enemy_tree' end
 private(trees.init,'trees_by_entity')[t]={unit=t,player_id=0,level=1}
 require('core/sound_service').play=function()end
 bus.subscribe(ev.TREE_HIT,hit)
 local function harvest(roll)
  RandomFloat=function()return roll end
  local a=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood
  ai:OnAttackLanded({attacker=u,target=t})
  return bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood-a
 end
 local base=harvest(10);local critical=harvest(9.99);near(critical,math.floor(base*2.2))
 return 'VIP9+10 grants 10% crit and +20% yield through real worker -> AI -> tree -> resource wallet'
end)
end
