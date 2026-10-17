-- Read-only production-consumer negative controls. No game or source changes.
package.path='scripts/vscripts/?.lua;'..package.path
class=function(t) return t end
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3
local bus,events=require('core/event_bus'),require('core/events')
local frame,scans=0,0
GameRules={GetGameTime=function() return frame end}
PlayerResource={GetTeam=function() return 2 end,GetPlayer=function() return {} end}
local tasks={}
package.loaded['core/scheduler']={after=function(_,f,k) tasks[k or tostring(f)]=f end,cancel=function(k) tasks[k]=nil end}
package.loaded['systems/rogue_effect_state_service']={add_effect=function() end,numeric=function(_,key)
    return key=='builder_peaceful_wood_per_hit' and 2 or 0 end}
package.loaded['systems/harvest_feedback_service']={reset=function() end,add=function() end,queue=function() end}
package.loaded['core/particle_manager']={show_green_number=function() end}
package.loaded['systems/tree_damage_rules']={is_allowed_tree_attacker=function(u) return u.allowed==true end}
local function unit(class_name)
    local u={class=class_name,alive=true,mods={},survival_is_wave_monster=true}
    function u:IsNull() return false end;function u:IsAlive() return self.alive end
    function u:GetClassname() return self.class end;function u:GetTeamNumber() return 3 end
    function u:GetAttackTarget() return self.target end;function u:HasModifier(name) return self.mods[name]~=nil end
    function u:AddNewModifier(_,_,name,p) self.mods[name]=p;return p end
    function u:ForceKill() self.kills=(self.kills or 0)+1;self.alive=false end
    return u
end
local creature,lane=unit('npc_dota_creature'),unit('npc_dota_creep_lane')
local all={creature,lane}
Entities={FindAllByClassname=function(_,name)
    assert(name=='npc_dota_creature');scans=scans+1
    local out={};for _,u in ipairs(all) do if u.class==name then out[#out+1]=u end end;return out
end}
local registry=require('systems/rogue_effect_registry')
local instance={player_id=0,effect={effect_type='owned_target_attacker_armor_reduction'},params={value=-1}}
local corrosive=assert(registry.get(instance.effect.effect_type))
assert(corrosive.apply(instance))
assert(creature.mods.modifier_rogue_corrosive_shield_attack and not lane.mods.modifier_rogue_corrosive_shield_attack,
    'Current class scan must reproduce missed already-born lane')
corrosive.recompute(instance,{unit=lane,player_id=0,monster_source='wave'})
assert(lane.mods.modifier_rogue_corrosive_shield_attack,'Existing real recompute accepts lane payload')
local slow=assert(registry.get('wall_attacker_attack_speed_pct'))
slow.apply({player_id=0,params={value=-15}})
assert(creature.mods.modifier_rogue_enemy_attack_speed and not lane.mods.modifier_rogue_enemy_attack_speed)
slow.recompute({player_id=0,params={value=-15}},{unit=lane})
assert(lane.mods.modifier_rogue_enemy_attack_speed,'Existing slow recompute is not classname restricted')

-- Real peaceful-tree consumer: an omitted lane attack incorrectly retains +2.
local tree={IsNull=function() return false end,GetHealth=function() return 1000 end};local worker={allowed=true,IsNull=function() return false end}
local wall={IsNull=function() return false end};local wood=0
bus.handle_request(events.BUILDING_LIST_REQUEST,function() return {buildings={{building_id='wall',unit=wall}}} end)
bus.handle_request(events.GRID_OCCUPY_REQUEST,function() return {ok=true} end)
bus.handle_request(events.RESOURCE_ADD_REQUEST,function(p) wood=wood+p.wood;return {ok=true} end)
RandomFloat=function() return 99 end
local trees=require('systems/tree_system');trees.init();trees._reset_for_test(1,tree,0)
lane.target=wall;creature.target=nil
local function harvest()
    frame=frame+.1
    bus.emit(events.TREE_HIT,{player_id=0,team=2,attacker=worker,target=tree,source='lumberjack',base_lumber_efficiency=3})
end
harvest();assert(wood==5,'Actual lane attacker omitted by class scan produces erroneous peaceful yield')
creature.target=wall;harvest();assert(wood==8,'Creature positive control suppresses peaceful bonus')

-- Actual nuclear target collection omits live lane, without inventing death.
require('items/item_survival_rogue_actions')
creature.target=nil;creature.alive=true;lane.alive=true
local caster={IsNull=function() return false end,RemoveItem=function() end}
local item=setmetatable({},{__index=item_survival_rogue_nuclear_bomb})
function item:SetActivated() end;function item:GetCaster() return caster end;function item:IsNull() return false end
function item:entindex() return 888 end
item:OnSpellStart();assert(tasks['rogue_nuclear_bomb:888'])
tasks['rogue_nuclear_bomb:888']()
assert(creature.kills==1 and lane.kills==nil,'Real nuclear consumer excludes registered-shape lane from its class scan')
print('LANE_BUSINESS_NEGATIVE_PASS actual consumers: existing-lane corrosive/slow miss then payload recompute works; peaceful yield5 vs3; nuclear creature1/lane0; engine is simulated')
