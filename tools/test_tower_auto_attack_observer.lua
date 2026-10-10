-- Actual targeting + existing central native observer. No engine, polling,
-- synthetic damage, or declarations changed after an instance is created.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) t.__index = t; return t end
LinkLuaModifier = function() end
local server = true
IsServer = function() return server end
LUA_MODIFIER_MOTION_NONE, DOTA_TEAM_NEUTRALS = 0, 4
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK, MODIFIER_EVENT_ON_DEATH = 1, 2, 3
MODIFIER_PROPERTY_DISABLE_AUTOATTACK = 4
MODIFIER_EVENT_ON_TAKEDAMAGE, MODIFIER_EVENT_ON_ATTACK_FAIL, MODIFIER_EVENT_ON_ATTACK_LANDED = 5, 6, 7
MODIFIER_STATE_DISARMED = 8
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 1, 2
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER = 1, 0

local mt = {}
mt.__index = {Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end,
    Normalized=function(v) local n=math.sqrt(v.x*v.x+v.y*v.y);return setmetatable({x=v.x/n,y=v.y/n,z=0},mt) end}
mt.__sub = function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=0},mt) end
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local function unit(id,x,name)
    return {id=id,position=Vector(x,0,0),alive=true,survival_movement_type="flying",
        IsNull=function(self) return self.removed==true end,IsAlive=function(self) return self.alive end,
        entindex=function(self) return self.id end,GetTeamNumber=function() return 3 end,
        GetAbsOrigin=function(self) return self.position end,GetUnitName=function() return name or "wave_monster" end}
end
local wall = unit(900,1000)
package.loaded["systems/building_system"] = {wall_for_player=function() return wall end}
local candidates, queries = {}, 0
FindUnitsInRadius = function(_,_,_,_,_,_,_,order)
    assert(order==FIND_ANY_ORDER);queries=queries+1;return candidates
end
local world, created, holder, failing = {}, 0, nil, false
GameRules = {GetGameModeEntity=function() return world end}
CreateModifierThinker = function()
    created=created+1
    if failing then error("mock observer unavailable") end
    holder={IsNull=function(self) return self.removed==true end,
        HasModifier=function(self,name) return name=="modifier_tower_damage_observer" and not self.empty end}
    if _G.modifier_tower_damage_observer and _G.modifier_tower_damage_observer.OnCreated then
        _G.modifier_tower_damage_observer.OnCreated({GetParent=function() return holder end})
    end
    return holder
end
local service = require("systems/tower_damage_observer")
local auto = require("modifiers/modifier_tower_auto_attack")
require("modifiers/modifier_tower_damage_observer")
local function contains(list,value) for _,entry in ipairs(list) do if entry==value then return true end end return false end
local function fixture(id,definition)
    local tower=unit(id,0)
    tower.survival_player_id=0;tower.survival_building_id="arrow_tower"
    function tower:GetTeamNumber() return 2 end
    function tower:GetAttackRange() return 1000 end
    function tower:GetAttackTarget() return self.target end
    function tower:SetForceAttackTarget(target) self.forced=target end
    function tower:SetAcquisitionRange(value) self.acquisition=value end
    function tower:GetAcquisitionRange() return self.acquisition end
    function tower:SetIdleAcquire(value) self.idle_acquire=value end
    function tower:SetForwardVector(value) self.facing=value end
    function tower:Stop() self.stops=(self.stops or 0)+1;self.target=nil end
    function tower:MoveToTargetToAttack(target) self.orders=(self.orders or 0)+1;self.target=target end
    function tower:SetContextThink(_,callback) self.next_frame=callback end
    function tower:PerformAttack() error("observer must not grant an extra attack") end
    function tower:AttackNoEarlierThan() error("observer must not reset native attack cooldown") end
    local modifier=setmetatable({},definition or auto)
    function modifier:GetParent() return tower end
    function modifier:GetStackCount() return self.stack or 0 end
    function modifier:SetStackCount(value) self.stack=value end
    function modifier:ForceRefresh() auto.OnRefresh(self) end
    function modifier:StartIntervalThink(value) self.interval=value end
    function tower:FindModifierByName(name) if name=="modifier_tower_auto_attack" then return modifier end end
    modifier:OnCreated()
    return modifier,tower
end
local function observer(parent)
    return setmetatable({GetParent=function() return parent end},modifier_tower_damage_observer)
end
local starts, releases = 0, 0
local original_start, original_release = auto.HandleAttackStart, auto.HandleAttack
auto.HandleAttackStart = function(self,params) starts=starts+1;return original_start(self,params) end
auto.HandleAttack = function(self,params) releases=releases+1;return original_release(self,params) end
local first, second, tree = unit(20,600),unit(21,800),unit(22,10,"enemy_tree")

-- Unavailable observer retains an immutable native fallback, including an
-- auto-only fixture. Later explicit observer init must not migrate it twice.
local fallback,fallback_tower=fixture(1)
assert(fallback.shared_attack_observer==false and fallback_tower.survival_tower_auto_attack_owner==nil)
assert(contains(fallback:DeclareFunctions(),MODIFIER_EVENT_ON_ATTACK_START))
assert(contains(fallback:DeclareFunctions(),MODIFIER_EVENT_ON_ATTACK))
candidates={tree,first};fallback:OnIntervalThink()
fallback:OnAttackStart({attacker=fallback_tower,target=first});assert(fallback.windup_target==first)
fallback:OnAttack({attacker=fallback_tower,target=first});assert(fallback.windup_target==nil)
assert(service.init() and created==1)
assert(service.can_route_auto_attack(),"only actual observer OnCreated advertises the new native route")
fallback:OnRefresh();assert(fallback.shared_attack_observer==false)
assert(contains(fallback:DeclareFunctions(),MODIFIER_EVENT_ON_ATTACK_START))
assert(fallback_tower.survival_tower_auto_attack_owner==nil)

-- Reproduce lazy loading the new auto class while require still returns an
-- old service module with is_ready() but no registration/capability methods.
local old_module={is_ready=function() return true end,init=service.init,
    is_authoritative=service.is_authoritative}
package.loaded["systems/tower_damage_observer"]=old_module
local lazy_auto=assert(loadfile("scripts/vscripts/modifiers/modifier_tower_auto_attack.lua"))()
package.loaded["systems/tower_damage_observer"]=service
_G.modifier_tower_auto_attack=auto
assert(#lazy_auto.DeclareFunctions({})==4,"old module readiness cannot omit the new native events")
local lazy,lazy_tower=fixture(70,lazy_auto)
assert(lazy.shared_attack_observer==false and lazy.interval==0.25,
    "old service must not interrupt OnCreated before StartIntervalThink")
assert(lazy_tower.survival_tower_auto_attack_owner==nil and #lazy:DeclareFunctions()==4)
candidates={tree,first};lazy:OnIntervalThink()
lazy:OnAttackStart({attacker=lazy_tower,target=first});assert(lazy.windup_target==first)
lazy:OnAttack({attacker=lazy_tower,target=first});assert(lazy.windup_target==nil)
assert(lazy_tower.orders==1 and created==1)
lazy:OnDestroy();assert(lazy.destroyed,"old service without unregister must also destroy safely")

-- New service code plus an old installed holder/native callback is equally
-- incapable. Module reload/init may reuse it, but must never invent a marker
-- or create another observer to repair the declaration after construction.
holder.survival_tower_auto_attack_observer_version=nil
assert(service.is_ready() and not service.can_route_auto_attack())
assert(#auto.DeclareFunctions({})==4)
package.loaded["systems/tower_damage_observer"]=nil
local reloaded_service=require("systems/tower_damage_observer")
assert(reloaded_service.init() and created==1 and not reloaded_service.can_route_auto_attack())
package.loaded["systems/tower_damage_observer"]=service
local old_holder_auto,old_holder_tower=fixture(71)
assert(old_holder_auto.shared_attack_observer==false and old_holder_auto.interval==0.25)
assert(old_holder_tower.survival_tower_auto_attack_owner==nil and #old_holder_auto:DeclareFunctions()==4)
candidates={tree,first};old_holder_auto:OnIntervalThink()
old_holder_auto:OnAttackStart({attacker=old_holder_tower,target=first})
old_holder_auto:OnAttack({attacker=old_holder_tower,target=first})
assert(old_holder_tower.target==first and old_holder_tower.orders==1)
-- A fresh modifier's real creation callback can advertise support. Existing
-- fallback owners stay immutable even when the holder now has the new route.
modifier_tower_damage_observer.OnCreated({GetParent=function() return holder end})
assert(service.can_route_auto_attack() and reloaded_service.can_route_auto_attack())
old_holder_auto:OnRefresh();assert(old_holder_auto.shared_attack_observer==false)
assert(old_holder_tower.survival_tower_auto_attack_owner==nil)
assert(#auto.DeclareFunctions({})==2,"new native holder can omit Start/Attack even before auto OnCreated")

-- New shared instances have only Death + the replicated disable-autoattack
-- property. The same central holder handles a targeting-only tower directly.
local shared,tower=fixture(2)
assert(shared.shared_attack_observer and tower.survival_tower_auto_attack_owner==shared)
assert(#shared:DeclareFunctions()==2 and contains(shared:DeclareFunctions(),MODIFIER_EVENT_ON_DEATH))
assert(contains(shared:DeclareFunctions(),MODIFIER_PROPERTY_DISABLE_AUTOATTACK))
assert(not contains(shared:DeclareFunctions(),MODIFIER_EVENT_ON_ATTACK_START))
assert(not contains(shared:DeclareFunctions(),MODIFIER_EVENT_ON_ATTACK))
assert(tower.survival_global_tower_damage==nil,"auto registration must not depend on effects construction order")
local central=observer(holder)
candidates={tree,first};shared:OnIntervalThink()
local params={attacker=tower,target=first,record=100}
local start_before,release_before=starts,releases
shared:OnAttackStart(params);central:OnAttackStart(params);shared:OnAttackStart(params)
assert(starts-start_before==1 and shared.windup_target==first,"engine-cached local declaration must not duplicate shared start")
central:OnAttack(params);shared:OnAttack(params)
assert(releases-release_before==1 and shared.windup_target==nil)

-- Execute the production effects bridge itself. All later damage/audio paths
-- are disabled in this fixture; those are covered by the tower skill tests.
local effects_file=assert(io.open("scripts/vscripts/modifiers/modifier_tower_attack_effects.lua","r"))
local effects_source=effects_file:read("*a");effects_file:close()
local effect_start=assert(effects_source:match("(function modifier_tower_attack_effects:OnAttackStart%(params%).-)%s*function modifier_tower_attack_effects:OnAttack%(params%)"))
local effect_attack=assert(effects_source:match("(function modifier_tower_attack_effects:OnAttack%(params%).-)%s*function modifier_tower_attack_effects:OnAttackFail%(params%)"))
local bus,events=require("core/event_bus"),require("core/events")
local skill_events=0
bus.subscribe(events.TOWER_ATTACK_START,function(payload)
    skill_events=skill_events+1
    assert(shared.windup_target==payload.target,"auto must record windup before effects publish the skill event")
end)
local environment=setmetatable({modifier_tower_attack_effects={},
    valid=function(target) return target and target:IsAlive() end,
    uses_machine_gun_attack=function() return true end,
    event_bus=bus,events=events,tower_skills={get=function() return {} end},
    skill_matching=function() return nil end,laser_config=function() return nil end}, {__index=_G})
local chunk=assert(loadstring(effect_start));setfenv(chunk,environment);chunk()
-- For OnAttack, deliberately return before independent effect damage branches.
local attack_environment=setmetatable({modifier_tower_attack_effects=environment.modifier_tower_attack_effects,
    valid=function() return false end},{__index=_G})
chunk=assert(loadstring(effect_attack));setfenv(chunk,attack_environment);chunk()
_G.modifier_tower_attack_effects=environment.modifier_tower_attack_effects
local effect={GetParent=function() return tower end}
tower.survival_global_tower_damage=true;tower.survival_global_tower_damage_owner=effect
start_before,release_before=starts,releases
central:OnAttackStart(params);central:OnAttack(params)
assert(starts-start_before==1 and releases-release_before==1 and skill_events==1,
    "shared effects bridge must not call auto a second time")
assert(shared.windup_target==nil)
effect.GetParent=function() return fallback_tower end
fallback_tower.survival_global_tower_damage=true;fallback_tower.survival_global_tower_damage_owner=effect
fallback.windup_target=first;release_before=releases
central:OnAttack({attacker=fallback_tower,target=first})
assert(releases-release_before==1 and fallback.windup_target==nil,"non-shared effects bridge remains available")

-- Secondary no-cooldown attacks must never overwrite/release the main windup.
tower.survival_global_tower_damage=nil
for _,no_cooldown in ipairs({true,1}) do
    shared.windup_target=first
    local secondary={attacker=tower,target=second,no_attack_cooldown=no_cooldown}
    central:OnAttackStart(secondary);central:OnAttack(secondary)
    assert(shared.windup_target==first)
end
shared.windup_target=nil
local orders,stops,searches=tower.orders,tower.stops,queries
for i=1,1000 do
    central:OnAttackStart(params);central:OnAttack(params);shared:OnIntervalThink()
end
assert(tower.orders==orders and tower.stops==stops and queries==searches,
    "shared callbacks must not interrupt healthy attacks or rescan locked targets")
assert(created==1 and shared.interval==0.25,"no observer polling or extra native holder")

-- The Death path remains local, including a different attacker's lethal hit
-- and the native order being cleared after the synchronous handoff.
candidates={tree,first,second}
shared:OnDeath({unit=first,attacker=unit(99,500)})
assert(tower.target==second and tower.orders==orders+1 and tower.stops==stops)
first.alive=false;tower.target=nil;tower.next_frame()
assert(tower.target==second and tower.orders==orders+2)
tower:Stop();shared:OnIntervalThink();assert(tower.target==second,"external Stop recovers on the original next interval")
candidates={tree};second.alive=false;shared:OnDeath({unit=second})
assert(shared:GetStackCount()==0 and tower.target==nil)
second.alive=true;candidates={tree,second};shared:OnIntervalThink();assert(tower.target==second)
central:OnAttackStart({attacker=tower,target=tree})
assert(shared:GetStackCount()==0 and tower.target==nil,"independent shared start still rejects forbidden tree attacks")

-- Authority still rejects duplicate holders, stale maps and missing modifier.
local before=starts
observer({IsNull=function() return false end,HasModifier=function() return true end}):OnAttackStart(params)
assert(starts==before)
holder.empty=true;central:OnAttackStart(params);assert(starts==before and not service.is_ready())
local lost,lost_tower=fixture(3)
assert(lost.shared_attack_observer==false and #lost:DeclareFunctions()==4)
assert(#shared:DeclareFunctions()==2,"lost observer must not mutate an existing shared declaration")
assert(service.init() and created==2)
local replacement=observer(holder)
central:OnAttackStart(params);assert(starts==before,"retired native holder must not dispatch")
replacement:OnAttackStart(params);assert(starts==before+1)
assert(lost_tower.survival_tower_auto_attack_owner==nil)
local current_world=world;world={}
replacement:OnAttackStart(params);assert(starts==before+1)
assert(service.init() and created==3 and current_world.survival_tower_damage_observer_holder~=holder)
replacement:OnAttackStart(params);assert(starts==before+1)
central=observer(holder)
server=false;central:OnAttackStart(params);server=true;assert(starts==before+1)

-- Old engine instances refreshed after class reload keep their native events;
-- registry cleanup may not remove a replacement owner's pointer.
local legacy,legacy_tower=fixture(4)
service.unregister_auto_attack(legacy_tower,legacy);legacy.shared_attack_observer=nil
legacy:OnRefresh();assert(legacy.shared_attack_observer==false and #legacy:DeclareFunctions()==4)
assert(legacy_tower.survival_tower_auto_attack_owner==nil)
local newer={shared_attack_observer=true}
assert(service.register_auto_attack(legacy_tower,newer))
service.unregister_auto_attack(legacy_tower,legacy)
assert(legacy_tower.survival_tower_auto_attack_owner==newer)
service.unregister_auto_attack(legacy_tower,newer)
shared:OnDestroy();assert(tower.survival_tower_auto_attack_owner==nil)
before=starts;central:OnAttackStart(params);assert(starts==before)

-- Count the production declaration boundary for a 28-tower scene: worker
-- events no longer enter each shared auto modifier. This is not an FPS claim.
local tower_count,local_attack_entries=28,0
for id=100,100+tower_count-1 do
    local modifier=fixture(id)
    local list=modifier:DeclareFunctions()
    if contains(list,MODIFIER_EVENT_ON_ATTACK_START) then local_attack_entries=local_attack_entries+1000 end
    if contains(list,MODIFIER_EVENT_ON_ATTACK) then local_attack_entries=local_attack_entries+1000 end
end
before=starts;local releases_before=releases
for i=1,1000 do local unmanaged={attacker=unit(10000+i,0)};central:OnAttackStart(unmanaged);central:OnAttack(unmanaged) end
assert(local_attack_entries==0 and starts==before and releases==releases_before)
assert(created==3,"standalone tower registration must reuse the existing central observer")
print("TOWER_AUTO_ATTACK_OBSERVER_PASS: old-module lazy load, old native holder/new service, immutable fallback/capability, independent shared registration, exact Start/Attack routing, effects order, 1000 stable cycles, local Death/next-frame recovery, authority/reload/disposal; 28 towers x 2000 unrelated attack events local entries=0 (previous declaration=56000)")
