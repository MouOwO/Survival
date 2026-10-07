package.path='scripts/vscripts/?.lua;'..package.path
local bus,ev=require('core/event_bus'),require('core/events')
local rewards=require('systems/archive_starjoy_rewards')
local guard=require('systems/gameplay_phase_guard')
local definition=require('config/generated/player_gameplay_stats')
local profile={mode='pure',revision=1,save={gameplay_stats={},permanent_effects={},match_boss_effects={}}}
package.loaded['systems/player_profile_service']={get_profile=function()return profile end}
package.loaded['core/scheduler']={every=function()end}
local permanent=require('systems/permanent_reward_effect_service');permanent.init()
class=function(t)return t end;IsServer=function()return true end;DAMAGE_TYPE_PHYSICAL=1
require('modifiers/modifier_weapon_stat_projection')
modifier_weapon_stat_projection.ShowFinalAttackDamage=function()end
modifier_weapon_stat_projection.ShowFinalAbilityDamage=function()end
local serial=100
local function unit(team,health,maximum)
 serial=serial+1
 local u={team=team or 3,health=health or 100,maximum=maximum or 1000,alive=true,index=serial,kills=0}
 function u:IsNull()return false end
 function u:IsAlive()return self.alive end
 function u:IsIllusion()return self.illusion==true end
 function u:IsBuilding()return false end
 function u:GetTeamNumber()return self.team end
 function u:GetHealth()return self.health end
 function u:GetMaxHealth()return self.maximum end
 function u:entindex()return self.index end
 function u:GetUnitName()return self.name or 'enemy_boss' end
 function u:HasModifier(name)return self.modifier==name end
 function u:Kill(ability,killer)
  self.kills=self.kills+1;self.killer=killer;self.ability=ability;self.alive=false
 end
 function u:ForceKill()error('Judgment must use credited Kill, not ForceKill')end
 return u
end
local hero=unit(2);local mod=setmetatable({player_id=0},{__index=modifier_weapon_stat_projection})
function mod:GetParent()return hero end
local function load(points)
 local s={};for _,r in ipairs(definition.rows)do s[r.field_id]=r.default_value end
 s.starjoy_points=points;rewards.reconcile(s);profile.save.gameplay_stats=s
 profile.revision=profile.revision+1;bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=0})
 return s
end
local ability={IsNull=function()return false end,GetAbilityName=function()return 'hero_test_spell' end}
local function hit(target,attacker,damage,skill)
 mod:OnTakeDamage({attacker=attacker or hero,unit=target,damage=damage==nil and 1 or damage,inflictor=skill and ability or nil,damage_type=1})
end
load(7499);local locked=unit();hit(locked);assert(locked.alive)
local s=load(7500);assert(s.starjoy_reward_level==17 and s.hero_execute_health_threshold_pct==15)
for _,skill in ipairs({false,true})do
 for _,health in ipairs({149,150,151})do
  local target=unit(3,health,1000);target.survival_monster_role='boss'
  hit(target,nil,1,skill)
  assert(target.alive==(health>=150),'strict threshold failed')
  if health<150 then
   assert(target.kills==1 and target.killer==hero and target.ability==nil)
   hit(target,nil,1,skill);assert(target.kills==1,'dead target processed twice')
  end
 end
end
local large=unit(3,149999999,1000000000);large.survival_is_boss=true;hit(large,nil,10,true);assert(not large.alive)
print('PASS real OnTakeDamage -> reward projection -> Judgment; LV17 gating, attack and ability, strict 15%, large-HP boss, hero kill credit')
for _,kind in ipairs({'zero','ally','other_attacker','illusion','tree','training','dummy','dead','building'})do
 local target=unit();local attacker=hero;local damage=1
 if kind=='zero'then damage=0 end
 if kind=='ally'then target.team=2 end
 if kind=='other_attacker'then attacker=unit(2)end
 if kind=='illusion'then hero.illusion=true end
 if kind=='tree'then target.name='enemy_tree'end
 if kind=='training'then target.survival_training_owner_player_id=0 end
 if kind=='dummy'then target.modifier='modifier_rogue_training_dummy'end
 if kind=='dead'then target.alive=false end
 if kind=='building'then target.survival_is_building=true end
 hit(target,attacker,damage);assert(target.kills==0,kind..' incorrectly executed');hero.illusion=false
end
local live=unit(3,160,1000);hit(live);assert(live.alive)
live.health=149;hit(live);assert(not live.alive,'crossing threshold must execute')
rewards.change(s,7500,0);bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=0})
local afterExchange=unit();hit(afterExchange);assert(not afterExchange.alive)
guard.set_post_clear_frozen(true)
local postClearBoss=unit();hit(postClearBoss);assert(not postClearBoss.alive,'archive challenge after clear must retain Judgment')
guard.reset()
print('PASS no zero-damage/friendly/worker/illusion/tree/training kills; threshold crossing, exchanged balance and post-clear bosses')
-- Reentrant death callbacks cannot execute the same still-alive target twice.
local execution=require('systems/hero_execution_service');local target=unit()
local payload={owner_hero=hero,attacker=hero,target=target,final_damage=1}
function target:Kill(_,killer)
 self.kills=self.kills+1;assert(not execution.try_execute(payload,15));self.killer=killer;self.alive=false
end
assert(execution.try_execute(payload,15));assert(target.kills==1)
print('PASS reentrant kill guard')
-- Migrate tiers claimed before Judgment was implemented, without replaying stats.
local old=load(8000);old.hero_execute_health_threshold_pct=0
local before={};for k,v in pairs(old)do before[k]=v end
assert(rewards.needs_reconcile(old));rewards.reconcile(old)
assert(old.hero_execute_health_threshold_pct==15 and not rewards.needs_reconcile(old))
for k,v in pairs(before)do if k~='hero_execute_health_threshold_pct'then assert(old[k]==v,k..' duplicated during migration')end end
for i=1,5 do rewards.reconcile(old);assert(old.hero_execute_health_threshold_pct==15)end
print('PASS existing LV17+ saves receive Judgment once without re-awarding tier attributes')
-- Each threshold adds the next tier, with same-field bonuses summed, never replaced.
local levels=require('config/generated/archive_starjoy_levels').rows
local stepped={starjoy_points=0};local expected={}
for _,row in ipairs(levels)do
 rewards.change(stepped,stepped.starjoy_points,row.required_points)
 for i,field in ipairs(row.effect_ids)do expected[field]=(expected[field] or tonumber(definition.by_id[field].default_value) or 0)+tonumber(row.effect_values[i])end
 for field,value in pairs(expected)do assert(math.abs(stepped[field]-value)<1e-8,'noncumulative '..field..' at LV'..row.level)end
end
assert(stepped.hero_final_damage_bonus_pct==77 and stepped.hero_critical_damage_bonus_pct==320)
assert(stepped.wall_health_bonus_pct==83 and stepped.tower_attack_bonus_pct==68)
rewards.change(stepped,13000,0)
for field,value in pairs(expected)do assert(math.abs(stepped[field]-value)<1e-8,'exchange removed '..field)end
print('PASS all 24 tiers incrementally sum every field and preserve every reward after spending all points')
