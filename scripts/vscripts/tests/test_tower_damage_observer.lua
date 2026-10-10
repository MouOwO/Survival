-- The single native listener must dispatch each event to its current tower once.
package.path="scripts/vscripts/?.lua;"..package.path
class=function(base) base.__index=base;return base end
local server=true
IsServer=function() return server end
MODIFIER_EVENT_ON_TAKEDAMAGE=1
MODIFIER_EVENT_ON_ATTACK_START=2
MODIFIER_EVENT_ON_ATTACK=3
MODIFIER_EVENT_ON_ATTACK_FAIL=4
MODIFIER_EVENT_ON_ATTACK_LANDED=5
MODIFIER_STATE_INVULNERABLE=6
MODIFIER_STATE_UNSELECTABLE=7
MODIFIER_STATE_NO_HEALTH_BAR=8
MODIFIER_STATE_OUT_OF_GAME=9
LUA_MODIFIER_MOTION_NONE=0
DOTA_TEAM_NEUTRALS=4
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local world,created,linked={},0,0
GameRules={GetGameModeEntity=function() return world end}
LinkLuaModifier=function() linked=linked+1 end
local failing,last_holder=false,nil
CreateModifierThinker=function()
    created=created+1
    if failing then error("native observer unavailable") end
    last_holder={IsNull=function() return false end,HasModifier=function(_,name)
        assert(name=="modifier_tower_damage_observer");return true
    end}
    return last_holder
end
local bus=require("core/event_bus")
local damages={}
bus.subscribe("commerce.tower_damage",function(event) damages[#damages+1]=event end)
local service=require("systems/tower_damage_observer")
assert(not service.is_ready())
assert(service.init() and service.is_ready() and created==1)
assert(service.init() and created==1 and linked==1,"same world must reuse observer")
require("modifiers/modifier_tower_damage_observer")
local observer=setmetatable({GetParent=function() return last_holder end},modifier_tower_damage_observer)
assert(#observer:DeclareFunctions()==5)
local function unit(team)
    return {IsNull=function(self) return self.removed or false end,GetTeamNumber=function() return team end}
end
local a,b,target=unit(2),unit(2),unit(3)
local ownerA,ownerB,calls={},{},{}
modifier_tower_attack_effects={}
for _,name in ipairs({"OnAttackStart","OnAttack","OnAttackFail","OnAttackLanded"}) do
    modifier_tower_attack_effects[name]=function(owner,params)
        calls[#calls+1]={name=name,owner=owner,params=params}
    end
end
a.survival_global_tower_damage=true;a.survival_global_tower_damage_owner=ownerA
b.survival_global_tower_damage=true;b.survival_global_tower_damage_owner=ownerB
for _,name in ipairs({"OnAttackStart","OnAttack","OnAttackFail","OnAttackLanded"}) do
    local event={attacker=a,target=target,record=123}
    observer[name](observer,event)
    assert(calls[#calls].name==name and calls[#calls].owner==ownerA and calls[#calls].params==event)
end
assert(#calls==4,"each native event must be forwarded once without synthetic attacks")
observer:OnAttackLanded({attacker=b,target=target})
assert(#calls==5 and calls[5].owner==ownerB)
ownerA.IsNull=function() return true end
observer:OnAttack({attacker=a});a.survival_global_tower_damage=nil
observer:OnAttack({attacker=a});observer:OnAttack({attacker=target});observer:OnAttack(nil)
assert(#calls==5,"retired and unmanaged towers must not dispatch")
server=false;observer:OnAttack({attacker=b});server=true
assert(#calls==5,"client callbacks cannot dispatch server combat")
observer:OnTakeDamage({attacker=b,unit=target,damage=17.5})
assert(#damages==1 and damages[1].damage==17.5 and damages[1].tower==b and damages[1].target==target)
observer:OnTakeDamage({attacker=b,unit=target,damage=0})
observer:OnTakeDamage({attacker=b,unit=a,damage=20})
target.removed=true;observer:OnTakeDamage({attacker=b,unit=target,damage=20})
assert(#damages==1,"blocked, friendly and stale damage cannot be counted")
world={};failing=true
assert(not service.init() and not service.is_ready(),"failed native creation requires per-tower fallback")
failing=false;assert(service.init() and service.is_ready())
print("PASS tower observer exact dispatch, ownership, damage, lifecycle and fallback")
