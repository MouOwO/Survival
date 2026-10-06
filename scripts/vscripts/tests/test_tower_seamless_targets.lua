package.path="scripts/vscripts/?.lua;"..package.path
class=function(t) return t end
LinkLuaModifier=function() end
IsServer=function() return true end
DOTA_UNIT_TARGET_TEAM_ENEMY,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC=1,1,2
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,FIND_CLOSEST=1,0
FIND_ANY_ORDER=1
MODIFIER_EVENT_ON_ATTACK_START,MODIFIER_EVENT_ON_ATTACK,MODIFIER_EVENT_ON_DEATH=1,2,3
MODIFIER_PROPERTY_DISABLE_AUTOATTACK=4
local mt={}
mt.__index={Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end,
    Normalized=function(v) local n=math.sqrt(v.x*v.x+v.y*v.y);return setmetatable({x=v.x/n,y=v.y/n,z=0},mt) end}
mt.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=0},mt) end
local function vector(x) return setmetatable({x=x,y=0,z=0},mt) end
local function enemy(id,x,name)
    return {id=id,position=vector(x),alive=true,survival_movement_type="flying",
        IsNull=function() return false end,IsAlive=function(self) return self.alive end,
        entindex=function(self) return self.id end,GetTeamNumber=function() return 3 end,
        GetAbsOrigin=function(self) return self.position end,GetUnitName=function() return name or "wave_monster" end}
end
local candidates={}
FindUnitsInRadius=function(_,_,_,_,_,_,_,order)
    assert(order==FIND_ANY_ORDER,"selection must not request native nearest-to-tower sorting")
    return candidates
end
local wall=enemy(100,1000)
package.loaded["systems/building_system"]={wall_for_player=function(player_id)
    assert(player_id==0)
    return wall
end}
local auto=require("modifiers/modifier_tower_auto_attack")
for _,route in ipairs({"base","class_1","class_2","class_3","class_4","class_5","class_6","class_7","ultimate"}) do
    local tower=enemy(1,0)
    tower.survival_player_id=0
    tower.survival_building_id=route=="ultimate" and "ultimate_tower" or "arrow_tower"
    tower.survival_tower_class=route
    tower.survival_ultimate_tower=route=="ultimate" or nil
    function tower:GetTeamNumber() return 2 end
    function tower:GetAttackRange() return 1000 end
    function tower:GetAttackTarget() return self.target end
    function tower:SetForceAttackTarget(target) self.forced=target end
    function tower:SetAcquisitionRange(n) self.acquisition=n end
    function tower:GetAcquisitionRange() return self.acquisition end
    function tower:SetIdleAcquire() end
    function tower:SetForwardVector(v) self.facing=v end
    function tower:Stop() self.stops=(self.stops or 0)+1;self.target=nil end
    function tower:MoveToTargetToAttack(target) self.orders=(self.orders or 0)+1;self.target=target end
    function tower:SetContextThink(_,callback) self.next_frame=callback end
    function tower:AttackNoEarlierThan() error("switch must not rewrite native attack cooldown") end
    function tower:PerformAttack() error("switch must not grant an extra attack") end
    local m=setmetatable({},{__index=auto})
    function m:GetParent() return tower end
    function m:GetStackCount() return self.stack or 0 end
    function m:SetStackCount(n) self.stack=n end
    function m:ForceRefresh() end
    function m:StartIntervalThink() end
    m:OnCreated()
    local far,near,next_enemy=enemy(2,600),enemy(3,900),enemy(4,800)
    local closest_to_tower=enemy(6,50)
    local tree=enemy(5,10,"enemy_tree")
    candidates={closest_to_tower,tree,far}
    m:OnIntervalThink()
    assert(tower.target==far and tower.orders==1)
    local stops=tower.stops
    m:OnAttackStart({attacker=tower,target=far})
    candidates={closest_to_tower,far,near,tree}
    m:OnIntervalThink()
    assert(tower.target==far and tower.orders==1,"higher wall priority interrupted shot windup: "..route)
    m:OnAttack({attacker=tower,target=far})
    m:OnIntervalThink()
    assert(tower.target==near and tower.orders==2,"enemy nearest the wall did not win next attack: "..route)
    assert(tower.facing and tower.facing.x==1,"tower must face new target without turn-time delay")
    for tick=1,30 do m:OnIntervalThink() end
    assert(tower.orders==2 and tower.stops==stops,"stable attack repeatedly restarted")
    -- Engine may report IsAlive true until the death dispatch finishes.
    candidates={closest_to_tower,near,tree,next_enemy,far}
    m:OnDeath({unit=near})
    assert(tower.target==next_enemy and tower.orders==3,"death did not retarget in same callback")
    assert(tower.stops==stops and m:GetStackCount()==1,"retarget entered idle/disarm")
    near.alive=false
    tower.target=nil -- engine clears the dying order AFTER OnDeath handlers
    assert(tower.next_frame)
    tower.next_frame()
    assert(tower.target==next_enemy and tower.orders==4,"post-death clear must recover next frame")
    tower.next_frame()
    assert(tower.orders==4,"already accepted target must not be reordered")
    local callback=tower.next_frame
    m:OnDestroy()
    callback()
    assert(tower.orders==4,"deferred handoff resurrected destroyed tower AI")
end
print("TOWER_SEAMLESS_TARGETS_PASS: base, 7 routes, fusion; wall priority, protected windup, immediate kill switch, next-frame recovery, no cooldown reset or extra attack")
