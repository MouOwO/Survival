-- Read-only offline audit: executes production Lua consumers with engine doubles.
package.path='scripts/vscripts/?.lua;'..package.path
local results={}
local function check(name,f)
 local ok,value=xpcall(f,debug.traceback);results[#results+1]={name=name,ok=ok,evidence=tostring(value or '')};print((ok and 'PASS ' or 'FAIL ')..name..' '..tostring(value or ''))
end
local function near(a,b)assert(type(a)=='number' and math.abs(a-b)<.0001,tostring(a)..' expected '..tostring(b))end
local function private(fn,wanted,seen)
 seen=seen or {};if seen[fn] then return end;seen[fn]=true
 for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==wanted then return v end end
 for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if type(v)=='function' then local r=private(v,wanted,seen);if r~=nil then return r end end end
end
class=function(t)return t end;LinkLuaModifier=function()end;IsServer=function()return true end
local tasks={};package.loaded['core/scheduler']={every=function(_,f,k)tasks[k or tostring(f)]=f end,after=function(_,f,k)tasks[k or tostring(f)]=f end,cancel=function(k)tasks[k]=nil end}
local stats={};local profile={mode='pure',revision=1,save={gameplay_stats=stats,permanent_effects={},match_boss_effects={}}}
package.loaded['systems/player_profile_service']={get_profile=function()return profile end}
package.loaded['systems/technology_stat_manager']={get=function()return {final={hero={},tower={},wall={},lumberjack={},gold_mine={}},growth={}}end}
package.loaded['core/modifier_registry']={ensure=function()return {}end}
local bus,ev=require('core/event_bus'),require('core/events')
local permanent=require('systems/permanent_reward_effect_service');permanent.init()
PlayerResource={GetTeam=function()return 2 end,GetPlayer=function()return nil end}
local function set(s)permanent.set_test_isolation(0,'audit_reset',true);permanent.clear_test_isolation(0,true);stats=s;profile.save.gameplay_stats=s;bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=0})end
local function totals()return bus.request(ev.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals end
local function unit(id)
 local u={id=id or 1,health=1000,maxhealth=1000,armor=0,team=2,mods={}}
 function u:IsNull()return false end;function u:IsAlive()return true end;function u:entindex()return self.id end
 function u:GetTeamNumber()return self.team end;function u:GetPlayerOwnerID()return 0 end;function u:IsRealHero()return false end
 function u:GetHealth()return self.health end;function u:GetMaxHealth()return self.maxhealth end
 function u:GetPhysicalArmorValue()return self.armor end;function u:SetPhysicalArmorBaseValue(x)self.armor=x end
 function u:SetHealth(x)self.health=x end;function u:SetBaseMaxHealth(x)self.maxhealth=x end;function u:SetMaxHealth(x)self.maxhealth=x end
 function u:SetBaseDamageMin(x)self.damage=x end;function u:SetBaseDamageMax(x)self.damageMax=x end
 function u:GetBaseDamageMin()return self.damage or 100 end;function u:GetBaseDamageMax()return self.damageMax or 100 end
 function u:SetBaseAttackTime(x)self.bat=x end;function u:CalculateStatBonus()end
 function u:HasModifier()return true end;function u:FindModifierByName(n)return self.mods[n] end
 function u:AddNewModifier(_,_,n,kv)self.lastModifier={name=n,kv=kv};return {}end
 function u:Script_SetAttackRange()end;function u:SetAcquisitionRange()end
 function u:GetLevel()return 1 end;function u:GetUnitName()return 'audit_unit' end
 return u
end
local hero=unit(1)
bus.handle_request(ev.HERO_SUMMON_GET_REQUEST,function()return {unit=hero}end)
check('resource_per_second',function()
 require('systems/resource_system').init();set({gold_per_second=80,wood_per_second=80})
 local before=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0});tasks['resource_income:0']();local after=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0})
 near(after.gold-before.gold,80);near(after.wood-before.wood,80);return 'actual resource accounts +80 gold/+80 wood per tick'
end)
check('hero_attack_attribute_efficiency',function()
 set({hero_attribute_growth=25,hero_attack_attribute_efficiency_pct=10});local old=totals().hero_all_attributes_flat
 bus.emit(ev.HERO_MAIN_ATTACK_LANDED,{player_id=0});near(totals().hero_all_attributes_flat-old,27.5);return 'one landed attack adds 27.5 all attributes'
end)
check('hero_damage_attack_growth',function()
 set({hero_damage_attack_growth=50});local old=totals().hero_attack_flat
 bus.emit(ev.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker=hero,final_damage=100});near(totals().hero_attack_flat-old,50);return 'one damage event +50 attack'
end)
check('growth_timers',function()
 set({wall_health_per_second=10,wall_armor_per_second=.1,tower_attack_per_second=20,hero_attributes_per_second=3000})
 local a=totals();tasks.star_blessing_effect_ticks();local b=totals()
 near(b.wall_health_growth_flat-a.wall_health_growth_flat,10);near(b.wall_armor_growth_flat-a.wall_armor_growth_flat,.1);near(b.tower_attack_flat-a.tower_attack_flat,20);near(b.hero_all_attributes_flat-a.hero_all_attributes_flat,3000)
 return 'scheduler tick: wall +10HP/+0.1armor, tower +20 attack, hero +3000 attributes'
end)
check('tower_hit_growth_and_armor',function()
 set({tower_damage_attack_growth=3,tower_attack_armor_reduction=.1})
 local tower=unit(2);tower.survival_player_id=0;local enemy=unit(3)
 bus.emit(ev.TOWER_ATTACK_LANDED,{tower=tower,target=enemy,damage=100})
 near(tower.survival_tower_personal_attack_growth,3);near(enemy.lastModifier.kv.armor_reduction_per_attack,1/30)
 return 'attacking tower +3 attack; target receives armor modifier, 0.1 War3 units'
end)
check('hero_hit_armor',function()
 local service=require('systems/research_armor_reduction_service');local hit=assert(private(service.init,'on_main_attack_landed'))
 set({hero_attack_armor_reduction=25});local enemy=unit(3);enemy.team=3
 hit({player_id=0,attacker=hero,target=enemy});near(enemy.lastModifier.kv.armor_reduction_per_attack,25/3)
 return 'target receives 25 War3 armor reduction'
end)
check('mine_production',function()
 local m=require('systems/gold_mine_system');local produce=assert(private(m.init,'produce_once'));RandomFloat=function()return 100 end
 local mine={player_id=0,team=2,unit=unit(4),mine_level=1};set({})
 local before=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).gold
 for i=1,4 do produce(mine)end
 local base=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).gold-before
 set({gold_mine_efficiency_pct=25});before=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).gold
 for i=1,4 do produce(mine)end
 near(bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).gold-before,base*1.25)
 return 'four real production payouts increase 25%, fractional carry preserved'
end)
check('building_stats',function()
 local m=require('systems/building_upgrade_system');local apply=assert(private(m.init,'apply_research_technology'))
 local tower=unit(2);local state={unit=tower,player_id=0,building_id='arrow_tower',level=1,definition={levels={{attack=100,health=1000,armor=10}}}}
 private(m.init,'buildings')[tower:entindex()]=state;state.research_base_attack_damage=100
 set({});apply(state,'audit');local attack=tower.damage;local bat=tower.bat
 set({tower_attack_bonus_pct=40,tower_attack_speed_bonus_pct=15,tower_final_damage_bonus_pct=40});apply(state,'audit')
 near(tower.damage,attack*1.4);near(tower.bat,bat/1.15);near(tower.survival_gameplay_final_damage_pct,40)
 local wall=unit(5);state={unit=wall,player_id=0,building_id='wall',level=1,definition={levels={{health=1000,war3_armor=10,armor=10}}}}
 private(m.init,'buildings')[wall:entindex()]=state
 set({wall_health_bonus_pct=10,wall_armor=30,wall_armor_bonus_pct=10});apply(state,'audit');near(wall.maxhealth,1100);near(wall.survival_war3_armor,41)
 return 'tower engine damage +40%, attack interval /1.15; wall engine maximum HP=1100; armor='..tostring(wall.survival_war3_armor)
end)
check('hero_stats',function()
 local m=require('systems/hero_combat_stat_service');local states=assert(private(m.init,'state_by_player'));local recalc=assert(private(m.init,'recalculate'))
 states[0]={unit=hero,hero_id='audit',definition={base_attack_time=2},base={strength=100,agility=100,intellect=100,attack_min=100,attack_max=100},damage_multiplier=1,engine_base_attack_min=100,engine_base_attack_max=100,engine_base_attack_time=2,refresh_version=0}
 set({});local base=recalc(0,'audit')
 set({hero_initial_attributes=300000,hero_attribute_bonus_pct=25,hero_attack_bonus_pct=25,hero_critical_damage_bonus_pct=200,hero_final_damage_bonus_pct=25});local a=recalc(0,'audit')
 near(a.strength,(base.strength+300000)*1.25);near(a.critical_damage_pct,base.critical_damage_pct+200);near(hero.survival_gameplay_final_damage_pct,25)
 local boosted=a.attack_max;set({hero_initial_attributes=300000,hero_attribute_bonus_pct=25,hero_critical_damage_bonus_pct=200,hero_final_damage_bonus_pct=25});local unboosted=recalc(0,'audit');near(boosted,unboosted.attack_max*1.25)
 assert(hero.damage>100);return 'real hero calculation and engine base-damage setters; STR='..a.strength..' crit='..a.critical_damage_pct
end)

check('final_damage_filter',function()
 local m=require('combat/damage_filter_service');m.init({event_bus=bus,events=ev,repository={consume_pending=function()end},config={boss_rules={enabled=false},minimum_post_multiplier=0}})
 local victim=unit(33);victim.team=3;local attacker=unit(32)
 EntIndexToHScript=function(i)return i==32 and attacker or victim end
 DAMAGE_TYPE_PHYSICAL=1;DAMAGE_TYPE_MAGICAL=2
 for _,pct in ipairs({25,40,15})do
  attacker.survival_gameplay_final_damage_pct=pct
  local keys={damage=100,entindex_attacker_const=32,entindex_victim_const=33,damagetype_const=2}
  assert(m._filter_for_test(nil,keys));near(keys.damage,100+pct)
 end
 return 'actual final damage filter: 100 -> 125/140/115'
end)
check('critical_damage_callback',function()
 require('modifiers/modifier_weapon_stat_projection')
 local a=unit(40);local object=setmetatable({server_snapshot={critical_chance_pct=100,critical_damage_pct=400}}, {__index=modifier_weapon_stat_projection})
 function object:GetParent()return a end
 RandomFloat=function()return 0 end
 object:OnAttackRecord({attacker=a,record=1001})
 near(object:GetModifierDamageOutgoing_Percentage(),300)
 object.server_snapshot.critical_chance_pct=0
 object:OnAttackRecord({attacker=a,record=1002})
 near(object:GetModifierDamageOutgoing_Percentage(),0)
 return 'engine outgoing callback +300% on crit (4x); +200% crit damage does NOT supply crit chance'
end)
check('worker_speed_efficiency',function()
 local m=require('systems/worker_system');local workers=assert(private(m.init,'workers'));local refresh=assert(private(m.init,'refresh_worker_technology'))
 local u=unit(41);local ai={SetTechnologyLumberEfficiency=function(self,v)self.efficiency=v end}
 u.mods.modifier_lumberjack_ai=ai
 workers[41]={unit=u,worker_type='lumberjack',player_id=0,base_attack_interval=2,base_attack_min=10,base_attack_max=10}
 set({lumberjack_attack_efficiency=13});refresh(0,'audit');local base=u.bat
 set({lumberjack_attack_efficiency=13,lumberjack_attack_speed_bonus_pct=10,lumberjack_efficiency=2});refresh(0,'audit')
 near(u.bat,base/1.1);near(ai.efficiency,2)
 return 'real worker engine attack interval /1.1; +2 forwarded to harvesting AI'
end)
check('map_level_single_application',function()
 local config=require('config/lottery_config');local settle=require('systems/lottery_http_settlement')
 local item=config.by_id.lottery_kings_treasure;local pool=config.pools.summer
 local index=1;for i,v in ipairs(pool.by_quality.ur)do if v.id==item.id then index=i end end
 RandomInt=function(a,b)if b==10000 then return 10000 end;return math.floor((index-.5)/#pool.by_quality.ur*1000000000)+1 end
 local r=settle.settle({save={content_inventory={special_lottery_ticket=1},gameplay_stats={wall_initial_health=1000,wall_health_regen_per_second=0,map_level=0},archive={}}},{kind='lottery_draw',pool_id='summer',count=1})
 assert(r.ok and r.response.results[1].id==item.id)
 near(r.gameplay_stats.map_level,1)
 set(r.gameplay_stats);local t=totals()
 assert(t.wall_initial_health==1100 and t.wall_health_regen_per_second==5,
  'map +1 grants saved HP='..tostring(r.gameplay_stats.wall_initial_health)..'/regen='..tostring(r.gameplay_stats.wall_health_regen_per_second)..'; gameplay projection HP='..tostring(t.wall_initial_health)..'/regen='..tostring(t.wall_health_regen_per_second)..'; expected 1100/5 including baseline HP=1000')
 return 'one level adds 100 HP/5 regeneration to baseline once'
end)


check('worker_actual_wood_credit',function()
 local particles=require('core/particle_manager');particles.show_green_number=function()end
 local m=require('systems/tree_system');local hit=assert(private(m.init,'on_tree_hit'));local trees=assert(private(m.init,'trees_by_entity'))
 local tree=unit(50);function tree:GetUnitName()return 'enemy_tree' end
 local worker=unit(51);function worker:GetUnitName()return 'npc_survival_lumberjack' end
 trees[tree]={unit=tree,player_id=0,level=1}
 RandomFloat=function()return 100 end
 local before=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood
 hit({target=tree,attacker=worker,source='lumberjack',player_id=0,team=2,base_lumber_efficiency=13})
 local base=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood-before
 before=bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood
 hit({target=tree,attacker=worker,source='lumberjack',player_id=0,team=2,base_lumber_efficiency=15})
 near(bus.request(ev.RESOURCE_GET_REQUEST,{player_id=0}).wood-before,base+2)
 return 'harvest execution: same hit deposits 2 extra wood to actual resource account'
end)
check('armor_actual_modifier',function()
 require('modifiers/modifier_research_technology')
 local target=unit(61);require('systems/war3_armor_target').apply(target,100,0)
 local obj=setmetatable({stack=0},{__index=modifier_research_armor_reduction})
 function obj:GetParent()return target end;function obj:GetStackCount()return self.stack end;function obj:SetStackCount(x)self.stack=x end
 obj:OnCreated({armor_reduction_per_attack=25/3})
 near(target.survival_effective_war3_armor,75)
 obj:OnRefresh({armor_reduction_per_attack=.1/3})
 near(target.survival_effective_war3_armor,74.9)
 return 'real modifier changes custom physical-mitigation armor: 100 -> 75 -> 74.9'
end)

AUDIT_RESULTS=results