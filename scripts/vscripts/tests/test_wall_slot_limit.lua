package.path="scripts/vscripts/?.lua;"..package.path
local mt={}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},mt) end
mt.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
local entities,orders={},{}
EntIndexToHScript=function(i) return entities[i] end
local function entity(i)
    local u={live=true,position=Vector(0,-500,0),range=128,capability=1}
    function u:entindex() return i end
    function u:IsNull() return false end
    function u:IsAlive() return self.live end
    function u:GetAbsOrigin() return self.position end
    function u:GetForwardVector() return Vector(0,1,0) end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(target) self.force=target end
    function u:GetAttackTarget() return self.target end
    function u:IsIdle() return false end
    function u:GetAttackCapability() return self.capability end
    function u:Script_GetAttackRange() return self.range+(self.ai and self.ai:GetModifierAttackRangeBonus() or 0) end
    function u:Script_SetAttackRange(v) self.range=v end
    function u:Stop() self.target=nil end
    entities[i]=u;return u
end
IsServer=function() return true end
class=function(t) return t end
DOTA_UNIT_CAP_MELEE_ATTACK=1
DOTA_UNIT_ORDER_MOVE_TO_POSITION=1
DOTA_UNIT_ORDER_ATTACK_TARGET=2
MODIFIER_STATE_DISARMED=3
MODIFIER_STATE_NO_UNIT_COLLISION=4
ExecuteOrderFromTable=function(o)
    orders[o.UnitIndex]=o
    entities[o.UnitIndex].target=o.TargetIndex and entities[o.TargetIndex] or nil
end
package.loaded["core/team_alignment"]={enforce=function() end,are_enemies=function() return true end}
package.loaded["systems/wall_melee_contact"]={resolve=function() return nil end,release=function() end}
local ai=require("modifiers/modifier_enemy_wall_ai")
local wall=entity(1);wall.position=Vector(0,0,0)
local units,controllers={},{}
for i=1,8 do
    local u=entity(10+i);units[i]=u
    u.position=Vector((i%2==0 and 1 or -1)*300, i*60, 0)
    local m=setmetatable({GetParent=function() return u end,StartIntervalThink=function() end},{__index=ai})
    u.ai=m;controllers[i]=m;m:OnCreated({wall_entindex=1})
    assert(not m:CheckState()[MODIFIER_STATE_DISARMED],"native approach must not disarm monsters")
    m:OnIntervalThink()
    assert(u:Script_GetAttackRange()==128,"outside contact keeps native chase range")
    assert(orders[10+i].OrderType==DOTA_UNIT_ORDER_ATTACK_TARGET,"all monsters use native attack pathfinding")
    assert(orders[10+i].Position==nil and u.force==wall,"no fixed queue/slot destination")
end
for pass=1,4 do
    for i,m in ipairs(controllers) do
        local previous=orders[10+i]
        m:OnIntervalThink()
        assert(orders[10+i]==previous,"ongoing native attacks must not restart")
    end
end
-- A ranged monster keeps its weapon reach; melee buffs are restored on exit.
units[8].capability=2;units[8].range=550
controllers[8]:OnIntervalThink()
assert(units[8]:Script_GetAttackRange()==550,"ranged attacks must not be shortened")
units[1].range=160;controllers[1]:OnIntervalThink()
assert(units[1]:Script_GetAttackRange()==160,"unengaged melee keeps range buffs")
wall.live=false
for i,m in ipairs(controllers) do
    m:OnIntervalThink()
    assert(units[i]:Script_GetAttackRange()==units[i].range,"normal range restored when wall dies")
    assert(units[i].force==nil and m.wall_entindex==-1,"destroyed wall releases native target")
end
MODIFIER_STATE_INVULNERABLE=5;MODIFIER_STATE_UNSELECTABLE=6;MODIFIER_STATE_NO_HEALTH_BAR=7
local construction=require("modifiers/modifier_building_under_construction")
assert(not construction:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION],"construction must collide immediately")
-- Retired collision units are removed, unrelated invisible units survive.
local legacy=entity(100);legacy.survival_wall_collision_barrier=true;legacy.survival_wall_entindex=1
local orphan=entity(101);orphan.GetUnitName=function() return "npc_survival_wall_collision_barrier" end
Entities={FindAllByClassname=function(_,c) return c=="npc_dota_creature" and {wall,legacy,orphan} or {} end}
local removed={}
UTIL_Remove=function(u) removed[u:entindex()]=true end
CreateUnitByName=function() error("no invisible barrier creation allowed") end
local barriers=require("systems/wall_collision_barrier_service")
barriers.clear_all()
assert(removed[100] and removed[101] and not removed[1])
assert(#barriers.create(wall)==0 and barriers.count(wall)==0)
print("WALL_NATIVE_PATH_PASS eight native attackers, no queue/disarm, no repeated orders, death release, immediate collision, legacy cleanup")
