-- Offline native declaration/route lifecycle; accepts TEMP proposal root.
package.path=(arg[1] or 'scripts/vscripts')..'/?.lua;scripts/vscripts/?.lua;'..package.path
class=function(value) value.__index=value;return value end
IsServer=function() return true end
Vector=function(x,y,z) return {x=x,y=y,z=z} end
MODIFIER_EVENT_ON_ATTACK_START,MODIFIER_EVENT_ON_ATTACK_LANDED,MODIFIER_EVENT_ON_DEATH,MODIFIER_PROPERTY_ATTACK_RANGE_BONUS=1,2,3,4
DOTA_TEAM_NEUTRALS,DOTA_UNIT_CAP_MELEE_ATTACK,DOTA_UNIT_ORDER_ATTACK_TARGET=4,1,10
LUA_MODIFIER_MOTION_NONE=0
local mode={};GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return 0 end}
local created,release,stops,orders,handled=0,{},{},{},{}
local entities={}
local function entity(index)
    local u={index=index,force=false}
    function u:IsNull() return self.null==true end
    function u:IsAlive() return self.dead~=true end
    function u:entindex() return self.index end
    function u:GetAttackCapability() return 2 end
    function u:GetAbsOrigin() return Vector(0,0,0) end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(target) self.force=target;orders[#orders+1]={'force',self.index,target} end
    function u:Stop() stops[#stops+1]=self.index end
    entities[index]=u;return u
end
EntIndexToHScript=function(index) return entities[index] end
ExecuteOrderFromTable=function(order) orders[#orders+1]=order end
LinkLuaModifier=function() end
UTIL_Remove=function(u) u.null=true end
package.loaded['core/team_alignment']={}
package.loaded['systems/wall_navigation_service']={}
package.loaded['systems/wall_melee_contact']={release=function(wall,unit) release[#release+1]={wall,unit} end}
CreateModifierThinker=function(_,_,name)
    created=created+1;local u=entity(9000+created)
    function u:HasModifier(wanted) return wanted==name and not self.empty end
    local methods=require('modifiers/modifier_enemy_attack_observer')
    methods.OnCreated({GetParent=function() return u end})
    return u
end
local service=require('systems/enemy_attack_observer')
assert(service.init() and service.can_route_death())
local holder=mode.survival_enemy_attack_observer_holder
local observer_methods=require('modifiers/modifier_enemy_attack_observer')
local function observer_for(unit) return setmetatable({GetParent=function() return unit end},observer_methods) end
local observer=observer_for(holder)
local methods=require('modifiers/modifier_enemy_wall_ai')
local original_handle=methods.HandleDeath
methods.HandleDeath=function(self,event)
    handled[#handled+1]={owner=self,event=event}
    if self.on_death then self:on_death(event) end
    return original_handle(self,event)
end
local function ai(unit,wall)
    local m=setmetatable({GetParent=function() return unit end,stack=0,
        IsNull=function(self) return self.null==true end,
        GetStackCount=function(self) return self.stack end,SetStackCount=function(self,value) self.stack=value end,
        ForceRefresh=function(self) self:OnRefresh() end,StartIntervalThink=function() end,
        SetHasCustomTransmitterData=function() end},methods)
    m:OnCreated({wall_entindex=wall and wall:entindex() or -1})
    return m
end
local walls,owners={},{},{}
for id=0,3 do walls[id]=entity(2000+id) end
for index=1,244 do
    local wall=walls[math.floor((index-1)/61)];owners[index]=ai(entity(index),wall)
    assert(owners[index].shared_death_observer and #owners[index]:DeclareFunctions()==1)
end
local registry=mode.survival_enemy_death_observer_registry
assert(registry.version==1)
-- Each native enemy death routes exactly once, even if cached local callbacks
-- are still delivered. No unrelated worker/tree/hero death enters the AI.
for index,m in ipairs(owners) do
    local unit=m:GetParent();unit.dead=true
    observer:OnDeath({unit=unit})
    for _,other in ipairs(owners) do other:OnDeath({unit=unit}) end
    assert(#handled==index and handled[index].owner==m and release[index][2]==index)
end
for index=1,1000 do observer:OnDeath({unit=entity(10000+index)}) end
assert(#handled==244,'Unrelated deaths never traverse all managed enemies')
-- One wall callback snapshots just 61 relevant instances. HandleDeath clears
-- each binding during dispatch; all later nodes still receive the event once.
for id=0,3 do
    local before=#handled;observer:OnDeath({unit=walls[id]})
    assert(#handled-before==61 and not registry.walls[walls[id]])
    for offset=1,61 do
        local m=owners[id*61+offset]
        assert(handled[before+offset].owner==m and m.wall_entindex==-1 and m:GetParent().force==nil)
    end
end
-- Rebinds retain instance registration order, never stale wall indices.
local a,b=owners[1],owners[2]
a:SetWallEntIndex(walls[0]:entindex());b:SetWallEntIndex(walls[0]:entindex())
a:SetWallEntIndex(walls[1]:entindex());a:SetWallEntIndex(walls[0]:entindex())
local before=#handled;observer:OnDeath({unit=walls[0]})
assert(handled[before+1].owner==a and handled[before+2].owner==b)
a:SetWallEntIndex(walls[0]:entindex())
local reused_wall=entity(walls[0]:entindex())
a:EnterState('chase',a:GetParent(),reused_wall,nil)
before=#handled;observer:OnDeath({unit=walls[0]});assert(#handled==before)
observer:OnDeath({unit=reused_wall});assert(#handled==before+1 and a.wall_entindex==-1)
-- Callback failures do not suppress later relevant native owners.
a:SetWallEntIndex(reused_wall:entindex());b:SetWallEntIndex(reused_wall:entindex())
a.on_death=function() error('expected_one_owner_failure') end
before=#handled;observer:OnDeath({unit=reused_wall});assert(#handled==before+2 and b.wall_entindex==-1)
a.on_death=nil;a:SetWallEntIndex(-1)
-- A callback may rebind/delete the next record: its now-unrelated callback is
-- correctly a no-op, matching the old HandleDeath wall-index check.
a:SetWallEntIndex(reused_wall:entindex());b:SetWallEntIndex(reused_wall:entindex())
a.on_death=function() b:SetWallEntIndex(walls[1]:entindex()) end
before=#handled;observer:OnDeath({unit=reused_wall});assert(#handled==before+1 and b.wall_entindex==2001)
a.on_death=nil;observer:OnDeath({unit=walls[1]});assert(b.wall_entindex==-1)
-- Exact owner cleanup works even with an invalid parent. A late old instance
-- cannot unregister its replacement or the replacement's wall membership.
local parent=a:GetParent();local replacement=ai(parent,walls[1])
a:OnDestroy();assert(parent.survival_enemy_attack_owner==replacement)
before=#handled;observer:OnDeath({unit=parent});assert(#handled==before+1 and handled[#handled].owner==replacement)
parent.null=true;replacement:OnDestroy();assert(not registry.units[parent] and not registry.walls[walls[1]])
-- Engine OnDestroy may precede observer delivery. The original contact
-- cleanup already ran, so the subsequent native death must have no ghost hit.
local retired=ai(entity(29999),walls[2]);local retired_unit=retired:GetParent()
retired:OnDestroy();before=#handled;observer:OnDeath({unit=retired_unit})
assert(#handled==before and not registry.units[retired_unit] and not registry.walls[walls[2]])
-- Repeated registration/destruction has no holes, dead records or full scans.
for index=1,1000 do local u=entity(30000+index);local m=ai(u,walls[2]);m:OnDestroy() end
assert(not registry.walls[walls[2]])
-- Old native holder and old service APIs retain local Death declarations.
holder.survival_enemy_death_observer_version=nil
local fallback=ai(entity(40000),walls[3]);assert(not fallback.shared_death_observer)
local death=false;for _,value in ipairs(fallback:DeclareFunctions()) do if value==MODIFIER_EVENT_ON_DEATH then death=true end end;assert(death)
before=#handled;fallback:OnDeath({unit=fallback:GetParent()});assert(#handled==before+1)
-- A true newly created holder advertises the route. Existing fallback cannot
-- silently migrate on refresh; service reload reuses the current authority.
holder.empty=true;assert(service.init());holder=mode.survival_enemy_attack_observer_holder
observer=observer_for(holder)
fallback:OnRefresh();assert(not fallback.shared_death_observer)
package.loaded['systems/enemy_attack_observer']=nil
local reloaded=require('systems/enemy_attack_observer');assert(reloaded.init() and created==2)
local ready=reloaded.can_route_death;reloaded.can_route_death=nil
-- Old-module compatibility is also guarded at each declaration/creation.
local old_ready=service.can_route_death;service.can_route_death=nil
local legacy=ai(entity(40001),walls[3]);assert(not legacy.shared_death_observer)
service.can_route_death=old_ready;reloaded.can_route_death=ready
-- New map/stale duplicate holders cannot dispatch old registrations.
local old_mode,old_holder,old_observer=mode,holder,observer
mode={};assert(reloaded.init());holder=mode.survival_enemy_attack_observer_holder
observer=observer_for(holder)
local new_wall=entity(50000);local new_ai=ai(entity(50001),new_wall)
before=#handled;old_observer:OnDeath({unit=new_ai:GetParent()});assert(#handled==before)
observer:OnDeath({unit=owners[3]:GetParent()});assert(#handled==before)
observer:OnDeath({unit=new_ai:GetParent()});assert(#handled==before+1)
owners[3]:OnDestroy();assert(not old_mode.survival_enemy_death_observer_registry.units[owners[3]:GetParent()])
new_ai:OnDestroy();assert(not mode.survival_enemy_death_observer_registry.walls[new_wall])
assert(old_holder~=holder)
print('ENEMY_SHARED_DEATH_ROUTE_PASS: 244 own deaths instead of broadcasts, 61-per-wall ordered snapshot, rebind/index reuse, mutation/error isolation, exact disposal, no holes, old holder/module fallback, reload authority and new-map cleanup')
