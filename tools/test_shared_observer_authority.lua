-- Offline native observer lifecycle: current GameMode identity is the sole
-- authority even when a Lua module or modifier class is reloaded separately.
package.path="scripts/vscripts/?.lua;"..package.path
class=function(value) value.__index=value;return value end
IsServer=function() return true end
Vector=function(x,y,z) return {x=x,y=y,z=z} end
LUA_MODIFIER_MOTION_NONE,DOTA_TEAM_NEUTRALS=0,4
local world,created,removed,last_holder,failure,link_failure={},0,0,nil,nil,false
GameRules={GetGameModeEntity=function() return world end}
LinkLuaModifier=function() if link_failure then error("mock link failure") end end
UTIL_Remove=function(unit) unit.removed=true;removed=removed+1 end
local function holder(name)
    return {name=name,IsNull=function(self) return self.removed==true end,
        HasModifier=function(self,wanted) return self.name==wanted and not self.empty end}
end
CreateModifierThinker=function(_,_,name)
    created=created+1
    if failure=="throw" then error("mock create failure") end
    last_holder=holder(name)
    last_holder.empty=failure=="empty"
    return last_holder
end
local bus=require("core/event_bus")
local forwarded=0
local function count() forwarded=forwarded+1 end
bus.subscribe("commerce.tower_damage",count)
modifier_lumberjack_ai={OnHarvestLanded=count}
modifier_enemy_wall_ai={HandleAttackStart=count,HandleAttackLanded=count}
modifier_tower_attack_effects={OnAttackStart=count,OnAttack=count,OnAttackFail=count,OnAttackLanded=count}
local cases={
    {role="lumberjack_attack",field="survival_lumberjack_attack_owner",events={"OnAttackLanded"}},
    {role="enemy_attack",field="survival_enemy_attack_owner",events={"OnAttackStart","OnAttackLanded"}},
    {role="tower_damage",field="survival_global_tower_damage_owner",
        events={"OnAttackStart","OnAttack","OnAttackFail","OnAttackLanded","OnTakeDamage"}},
}
for _,case in ipairs(cases) do
    local module="systems/"..case.role.."_observer"
    local modifier="modifier_"..case.role.."_observer"
    local key="survival_"..case.role.."_observer_holder"
    world={};created,removed,last_holder,failure=0,0,nil,nil
    package.loaded[module]=nil
    local original=require(module)
    assert(not original.is_ready() and not original.is_authoritative(nil))
    assert(original.init() and created==1 and world[key]==last_holder)
    local original_holder=last_holder
    package.loaded["modifiers/"..modifier]=nil
    local methods=require("modifiers/"..modifier)
    if type(methods)~="table" then methods=_G[modifier] end
    local function observer(unit)
        return setmetatable({GetParent=function() return unit end},methods)
    end
    local first=observer(original_holder)
    local owner={shared_attack_observer=true}
    local attacker={IsNull=function() return false end,GetTeamNumber=function() return 2 end,
        survival_global_tower_damage=true,[case.field]=owner}
    local target={IsNull=function() return false end,GetTeamNumber=function() return 3 end}
    local params={attacker=attacker,target=target,unit=target,damage=10}
    local function dispatch(instance,expected)
        local before=forwarded
        for _,name in ipairs(case.events) do instance[name](instance,params) end
        assert(forwarded-before==expected,case.role.." dispatched from the wrong holder")
    end
    dispatch(first,#case.events)
    assert(original.init() and created==1)
    -- Existing modifier closure retains the original module object. The new
    -- module must reuse that same thinker instead of adding a second listener.
    package.loaded[module]=nil
    local reloaded=require(module)
    assert(reloaded.init() and reloaded.is_ready() and created==1)
    assert(original.is_ready() and reloaded.is_authoritative(original_holder))
    dispatch(first,#case.events)
    local duplicate=holder(modifier)
    dispatch(observer(duplicate),0)
    assert(not reloaded.is_authoritative(duplicate))
    -- Lost modifier alone is not a healthy thinker. No implicit timer or
    -- destruction callback creates a replacement before explicit init.
    original_holder.empty=true
    assert(not original.is_ready() and not reloaded.is_authoritative(original_holder))
    dispatch(first,0);assert(created==1)
    assert(reloaded.init() and created==2 and last_holder~=original_holder)
    local second=observer(last_holder)
    original_holder.empty=false -- stale duplicate revives, but cannot dispatch
    dispatch(first,0);dispatch(second,#case.events)
    last_holder.removed=true
    assert(not original.is_ready() and created==2)
    dispatch(second,0)
    assert(original.init() and created==3 and reloaded.is_ready())
    local current=observer(last_holder)
    dispatch(current,#case.events)
    -- Another map has another GameMode. Never reuse/delete the old map's
    -- thinker by index; both old module closures consult the current owner.
    local previous_world=world
    world={}
    assert(not reloaded.is_ready());dispatch(current,0)
    assert(reloaded.init() and created==4)
    assert(previous_world[key]~=world[key] and not previous_world[key].removed)
    dispatch(current,0);dispatch(observer(last_holder),#case.events)
    -- A valid empty thinker and throwing native/link APIs must all report
    -- failure, leaving new combat modifiers on their original native fallback.
    world={};failure="empty"
    local discarded=removed
    assert(not reloaded.init() and not original.is_ready() and removed==discarded+1)
    assert(world[key]==nil);dispatch(observer(last_holder),0)
    failure="throw";assert(not reloaded.init() and not original.is_ready())
    failure=nil;link_failure=true
    assert(not reloaded.init() and not original.is_ready())
    link_failure=false;assert(reloaded.init() and original.is_ready())
    dispatch(observer(last_holder),#case.events)
    world=nil
    assert(not original.is_ready() and not original.init())
    dispatch(observer(last_holder),0)
    print("SHARED_OBSERVER_AUTHORITY_PASS "..case.role.." reload/reuse, stale duplicates, missing modifier, explicit recovery, new map, creation failures")
end
