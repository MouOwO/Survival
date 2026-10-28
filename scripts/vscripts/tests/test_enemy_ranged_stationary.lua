-- Exercise the real opt-in helper AND wall AI lifecycle. Native attack
-- continuity/NextBot savings still require the paired Workshop capture.
package.path="scripts/vscripts/?.lua;"..package.path
local clock, tools, world = 0, true, {}
IsServer=function() return true end
IsInToolsMode=function() return tools end
GameRules={GetGameTime=function() return clock end,GetGameModeEntity=function() return world end}
LinkLuaModifier=function() end
class=function(t) return t end
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_CAP_MELEE_ATTACK,DOTA_UNIT_CAP_RANGED_ATTACK=1,2
DOTA_UNIT_ORDER_ATTACK_TARGET,DOTA_UNIT_ORDER_MOVE_TO_POSITION=2,3
MODIFIER_STATE_NO_UNIT_COLLISION,MODIFIER_STATE_DISARMED,MODIFIER_STATE_ROOTED=1,2,3
MODIFIER_EVENT_ON_TAKEDAMAGE,MODIFIER_EVENT_ON_ATTACK_START,MODIFIER_EVENT_ON_ATTACK,
    MODIFIER_EVENT_ON_ATTACK_FAIL,MODIFIER_EVENT_ON_ATTACK_LANDED=4,5,6,7,8
MODIFIER_EVENT_ON_DEATH=9
local entities, orders, sequence = {}, {}, 10
EntIndexToHScript=function(i) return entities[i] end
ExecuteOrderFromTable=function(order) orders[#orders+1]=order end
package.loaded["core/team_alignment"]={are_enemies=function(a,b) return a.team~=b.team end,
    enforce=function() error("unexpected alignment repair") end}
package.loaded["systems/wall_melee_contact"]={release=function() end,resolve=function() return nil end}
package.loaded["systems/wall_navigation_service"]={}
package.loaded["systems/wall_target_service"]={}
package.loaded["systems/enemy_attack_observer"]={is_ready=function() return true end}
local probe=require("systems/enemy_ranged_stationary")
local AI=require("modifiers/modifier_enemy_wall_ai")
local tower_observer=require("systems/tower_damage_observer")
require("modifiers/modifier_tower_damage_observer")
local holder={IsNull=function() return false end,
    HasModifier=function(_,name) return name=="modifier_tower_damage_observer" end}
world.survival_tower_damage_observer_holder=holder
local central=setmetatable({GetParent=function() return holder end},{__index=modifier_tower_damage_observer})
assert(#central:DeclareFunctions()==5,"enemy routing added a native event declaration")
local function safe_modifier(name)
    return {GetName=function() return name end}
end
local function unit(index,team,x)
    local u={index=index,team=team,p={x=x,y=0,z=0},alive=true,hull=32,
        attack_cap=2,range=600,bat=1.7,rate=1,stops=0,force_writes=0,
        survival_is_wave_monster=true,survival_wave_movement_type="ground"}
    function u:entindex() return self.index end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return self.alive end
    function u:GetClassname() return self.classname or "npc_dota_creature" end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.hull end
    function u:GetTeamNumber() return self.team end
    function u:GetAttackCapability() return self.attack_cap end
    -- Deliberately no GetMoveCapability/GetMovementCapability: real native
    -- npc_dota_creature does not expose these getters.
    function u:SetMoveCapability() error("experiment changed movement capability") end
    function u:Script_GetAttackRange() return self.range end
    function u:GetBaseAttackTime() return self.bat end
    function u:GetAttacksPerSecond() return self.rate end
    function u:GetAttackTarget() return self.target end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(value) self.force=value;self.force_writes=self.force_writes+1 end
    function u:FindAllModifiers() return self.modifiers or {} end
    function u:CanEntityBeSeenByMyTeam() return not self.hidden end
    function u:IsInvulnerable() return self.protected or false end
    function u:IsAttackImmune() return self.attack_immune or false end
    function u:IsIdle() return self.idle or false end
    function u:IsStunned() return self.stun or false end
    function u:IsCommandRestricted() return self.restricted or false end
    function u:IsRooted()
        if self.root then return true end
        if self.ai and not self.delay_own_root and self.ai:CheckState()[MODIFIER_STATE_ROOTED] then return true end
        for _,modifier in pairs(self.modifiers or {}) do
            if modifier~=self.ai and modifier.CheckState and modifier:CheckState()[MODIFIER_STATE_ROOTED] then return true end
        end
        return false
    end
    function u:IsDisarmed() return self.disarm or false end
    function u:IsCurrentlyHorizontalMotionControlled() return self.horizontal or false end
    function u:IsCurrentlyVerticalMotionControlled() return self.vertical or false end
    function u:IsControllableByAnyPlayer() return self.player_controlled or false end
    function u:Stop() self.stops=self.stops+1 end
    entities[index]=u
    return u
end
local wall=unit(1,2,0)
wall.survival_building_id="wall"
wall.hull=128
local wall2=unit(2,2,1000)
wall2.survival_building_id="wall"
local function fixture()
    sequence=sequence+1
    -- The native shooter can fire past the center-distance range because of
    -- hulls. The experiment must use actual stationary firing evidence.
    local parent=unit(sequence,3,-735)
    local ai=setmetatable({GetParent=function() return parent end,
        GetName=function() return "modifier_enemy_wall_ai" end,
        GetStackCount=function(self) return self.stack or 0 end,
        SetStackCount=function(self,value) self.stack=value;self.stack_writes=(self.stack_writes or 0)+1 end,
        ForceRefresh=function(self) self:OnRefresh() end,
        StartIntervalThink=function(self,dt) self.dt=dt end},{__index=AI})
    parent.ai=ai
    parent.modifiers={ai,safe_modifier("modifier_survival_hero_attack_range"),
        safe_modifier("modifier_debug_attack_cap"),safe_modifier("modifier_single_health_bar")}
    ai:OnCreated({wall_entindex=1,wall_target_player_id=0})
    ai:OnIntervalThink()
    parent.force,parent.target=wall,wall
    return parent,ai
end
local function tick(ai,dt) clock=clock+(dt or .5);ai:OnIntervalThink() end
local function event(ai,parent,kind,target,record)
    local params={attacker=parent,target=target or wall,record=record}
    if kind=="fired" then central:OnAttack(params)
    else ai[kind=="landed" and "HandleAttackLanded" or "HandleAttackStart"](ai,params) end
end
local native_record=1000
local function enable() assert(probe.set_probe_enabled(true));probe.reset_counters() end
local function enter(record)
    local parent,ai=fixture()
    native_record=native_record+1;record=record or native_record
    event(ai,parent,"start") -- native windup has no release record
    assert(not ai.ranged_stationary_hold,"start alone cannot prove completed stationary fire")
    event(ai,parent,"fired",nil,record)
    assert(not ai.ranged_stationary_hold,"fired alone cannot prove landed stationary fire")
    clock=clock+.3;event(ai,parent,"landed",nil,record)
    assert(ai.ranged_stationary_hold and ai.contact_mode==6 and parent:IsRooted(),"stationary pair did not hold")
    return parent,ai
end
local function clean(parent,ai)
    ai:OnDestroy()
    assert(ai.contact_mode==0 and not ai.ranged_stationary_hold)
end

-- Default-off and non-Tools loads retain the normal FSM and native state.
assert(not probe.enabled() and _G.SURVIVAL_RANGED_STATIONARY_PROBE==nil)
local p,a=fixture();event(a,p);event(a,p,"landed");tick(a)
assert(not p:IsRooted() and probe.snapshot().entered==0)
assert(probe.set_probe_enabled(true));tools=false
event(a,p);event(a,p,"landed");tick(a)
assert(not p:IsRooted(),"non-Tools flag must stay inert")
assert(not probe.set_probe_enabled(true))
tools=true;enable()

-- A forced target, a start, or a landed notification alone is insufficient.
p,a=fixture();tick(a);event(a,p,"landed")
assert(not a.ranged_stationary_hold)
a:HandleAttackStart({attacker=p})
assert(not a.ranged_stationary_hold,"missing target is not firing proof")
local before_orders,before_stops,before_force=#orders,p.stops,p.force_writes
event(a,p,"start");event(a,p,"fired",nil,17);clock=clock+.3;event(a,p,"landed",nil,17)
assert(a.ranged_stationary_hold and a.contact_mode==6)
assert(#orders==before_orders and p.stops==before_stops and p.force_writes==before_force)
assert(p.bat==1.7 and p.range==600 and p.hull==32 and wall.hull==128)
local states=a:CheckState()
assert(states[MODIFIER_STATE_ROOTED] and not states[MODIFIER_STATE_DISARMED]
    and not states[MODIFIER_STATE_NO_UNIT_COLLISION],"mode 6 must add only ROOTED")
-- The same stack must yield the same ROOTED-only state in the client VM.
local client=setmetatable({GetStackCount=function() return 6 end},{__index=AI})
states=client:CheckState()
assert(states[MODIFIER_STATE_ROOTED] and not states[MODIFIER_STATE_DISARMED] and not states[MODIFIER_STATE_NO_UNIT_COLLISION])
client.no_unit_collision=true
states=client:CheckState()
assert(states[MODIFIER_STATE_ROOTED] and not states[MODIFIER_STATE_DISARMED]
    and not states[MODIFIER_STATE_NO_UNIT_COLLISION],
    "legacy collision flag must not phase a stationary wall attacker")

-- A nil native attack target during cooldown retains the hold. Owner rooting
-- must not trigger target_controlled and suppress normal state observations.
for i=1,60 do
    p.target=wall;event(a,p,"start")
    p.target=nil;event(a,p,"fired",nil,100+i)
    clock=clock+.3;event(a,p,"landed",nil,100+i);tick(a,.2)
end
assert(a.contact_mode==6 and #orders==before_orders and p.stops==before_stops)
local c=probe.snapshot()
assert(c.attack_start_free==2 and c.attack_start_held==60 and c.attack_landed_held==60)
assert(c.entered==1 and c.active_holds==1 and c.stationary_pairs==61 and c.pairs_with_record==61)
assert(c.attack_fired_free==1 and c.attack_fired_held==60 and c.fired_record_present==61)
assert(c.start_record_missing==62 and c.pairs_without_record==0,"windup records were treated as release proof")
assert(c.movement_capability_mutations==false)
clean(p,a)
c=probe.snapshot()
assert(c.exited==1 and c.active_holds==0 and c.bat_samples[1].bat_before==1.7
    and c.bat_samples[1].bat_after==1.7 and c.bat_samples[1].restored)
assert(c.bat_samples[1].attack_start_held==60 and c.bat_samples[1].attack_fired_held==60
    and c.bat_samples[1].attack_landed_held==60)

-- Start lacks a record in real native callbacks. Only matching release and
-- landed records can provide proof; missing/asymmetric records never use FIFO.
-- Exercise the real two existing global native carriers, not synthetic helper
-- invocations. Tower events/effects remain independent and exact once.
enable()
local enemy_service=assert(loadfile("scripts/vscripts/systems/enemy_attack_observer.lua"))()
package.loaded["systems/enemy_attack_observer"]=enemy_service
require("modifiers/modifier_enemy_attack_observer")
local enemy_holder={IsNull=function() return false end,
    HasModifier=function(_,name) return name=="modifier_enemy_attack_observer" end}
world.survival_enemy_attack_observer_holder=enemy_holder
local enemy_central=setmetatable({GetParent=function() return enemy_holder end},
    {__index=modifier_enemy_attack_observer})
assert(#enemy_central:DeclareFunctions()==3 and modifier_enemy_attack_observer.OnAttack==nil,
    "experiment introduced a second native release listener")
p,a=fixture()
local native_params={attacker=p,target=wall,record=nil}
enemy_central:OnAttackStart(native_params);central:OnAttackStart(native_params)
assert(probe.snapshot().attack_start_free==1,"global carriers duplicated windup")
native_params.record=501;central:OnAttack(native_params);central:OnAttack(native_params)
c=probe.snapshot()
assert(c.attack_fired_free==1 and c.duplicate_fired==1 and #a.ranged_stationary_pending==1,
    "duplicate native release created another firing proof")
local unauthorized=setmetatable({GetParent=function() return {IsNull=function() return false end} end},
    {__index=modifier_tower_damage_observer})
unauthorized:OnAttack({attacker=p,target=wall,record=502})
assert(probe.snapshot().attack_fired_free==1,"non-authoritative holder routed native release")
enemy_central:OnAttackLanded(native_params)
assert(a.ranged_stationary_hold and probe.snapshot().attack_start_free==1
    and probe.snapshot().attack_landed_free==1,"landed event duplicated windup or failed record match")
clean(p,a)

local auto_calls,effect_calls=0,0
modifier_tower_auto_attack={HandleAttack=function() auto_calls=auto_calls+1 end}
modifier_tower_attack_effects={OnAttack=function() effect_calls=effect_calls+1 end}
local normal_tower=unit(700,2,0)
normal_tower.survival_is_wave_monster=false
normal_tower.survival_tower_auto_attack_owner={shared_attack_observer=true}
normal_tower.survival_global_tower_damage=true
normal_tower.survival_global_tower_damage_owner={}
central:OnAttack({attacker=normal_tower,target=p,record=503})
assert(auto_calls==1 and effect_calls==1 and probe.snapshot().attack_fired_free==1,
    "enemy route changed existing tower event semantics")
p,a=fixture();central:OnAttack({attacker=p,target=wall,record=504})
assert(auto_calls==1 and effect_calls==1,"enemy release invoked tower gameplay effects")
local owner=p.survival_enemy_attack_owner;p.survival_enemy_attack_owner={GetParent=function() return normal_tower end,
    shared_attack_observer=true}
central:OnAttack({attacker=p,target=wall,record=505})
assert(probe.snapshot().attack_fired_free==2,"foreign owner was routed")
p.survival_enemy_attack_owner=owner
assert(probe.set_probe_enabled(false))
local original_route=tower_observer.route_enemy_fired
tower_observer.route_enemy_fired=function() error("default-off native release entered probe route") end
central:OnAttack({attacker=normal_tower,target=p,record=506})
assert(auto_calls==2 and effect_calls==2,"default-off route suppressed normal tower gameplay")
tower_observer.route_enemy_fired=original_route
assert(probe.set_probe_enabled(true));tools=false
central:OnAttack({attacker=p,target=wall,record=507})
tools=true
assert(probe.snapshot().attack_fired_free==2,"non-Tools global native carrier entered experiment")
clean(p,a)

enable();p,a=enter();assert(probe.snapshot().pairs_with_record==1);clean(p,a)
p,a=fixture();event(a,p,"start",nil,101);event(a,p,"landed",nil,101)
assert(not a.ranged_stationary_hold,"windup record was treated as fired proof");clean(p,a)
p,a=fixture();event(a,p,"start");event(a,p,"fired",nil,101);event(a,p,"landed",nil,102)
assert(not a.ranged_stationary_hold,"different native records were paired");clean(p,a)
p,a=fixture();event(a,p,"start");event(a,p,"fired");event(a,p,"landed",nil,103)
assert(not a.ranged_stationary_hold,"missing fired record fell back to FIFO");clean(p,a)
p,a=fixture();event(a,p,"fired",nil,104);event(a,p,"landed")
assert(not a.ranged_stationary_hold,"missing landed record fell back to FIFO");clean(p,a)
p,a=fixture();p.target=nil;event(a,p,"fired",nil,105);tick(a,.1);event(a,p,"landed",nil,105)
assert(a.ranged_stationary_hold,"nil native target invalidated exact same-wall fired/landed proof");clean(p,a)
for _,change in ipairs({function(u) u.p.x=u.p.x+.01 end,
    function(u) u.p.z=u.p.z+1 end,function(u) u.range=u.range+1 end,
    function(u) u.hull=u.hull+1 end,function() wall.p.y=1 end,
    function() wall.hull=129 end}) do
    p,a=fixture();event(a,p);event(a,p,"fired",nil,201);change(p);event(a,p,"landed",nil,201)
    assert(not a.ranged_stationary_hold,"changed geometry was treated as stationary firing")
    wall.p.y,wall.hull=0,128;clean(p,a)
end
p,a=fixture();event(a,p,"fired",nil,203)
p.p.x=p.p.x+1;tick(a,.1);p.p.x=p.p.x-1;event(a,p,"landed",nil,203)
assert(not a.ranged_stationary_hold,"observed move-away-and-back reused invalid firing proof");clean(p,a)
p,a=fixture();event(a,p,"fired",nil,204)
assert(probe.set_probe_enabled(false));assert(probe.set_probe_enabled(true))
event(a,p,"landed",nil,204)
assert(not a.ranged_stationary_hold,"previous probe generation reused firing proof");clean(p,a)

-- Existing external control is never cancelled and blocks entry/re-entry.
for _,field in ipairs({"stun","restricted","disarm","horizontal","vertical"}) do
    p,a=enter();p[field]=true;tick(a)
    assert(a.contact_mode==0 and not a.ranged_stationary_hold,"control did not release: "..field)
    event(a,p);event(a,p,"fired",nil,205);event(a,p,"landed",nil,205);assert(a.contact_mode==0,"controlled fire reentered")
    p[field]=false;clean(p,a)
end
p,a=enter();local external_root={GetName=function() return "external_root" end,
    CheckState=function() return {[MODIFIER_STATE_ROOTED]=true} end}
p.modifiers[#p.modifiers+1]=external_root
before_orders,before_stops=#orders,p.stops;tick(a)
assert(not a.ranged_stationary_hold and a.contact_mode==0 and p:IsRooted())
assert(#orders==before_orders and p.stops==before_stops,"release overrode external root control")
event(a,p);event(a,p,"landed");assert(not a.ranged_stationary_hold)
p.modifiers[#p.modifiers]=nil;clean(p,a)

-- Unknown native modifiers are conservative: even while IsRooted also
-- contains our own state, they release and preserve external root ownership.
p,a=enter();p.root=true;p.modifiers[#p.modifiers+1]=safe_modifier("unknown_native_root")
before_orders=#orders;tick(a)
assert(not a.ranged_stationary_hold and p:IsRooted() and #orders==before_orders)
assert(probe.snapshot().reasons.unknown_modifier>=1)
p.root=false;p.modifiers[#p.modifiers]=nil;clean(p,a)

-- Applying a native stack may take one frame. Entry does not require IsRooted
-- to change synchronously, but geometry changes before that frame release.
p,a=fixture();p.delay_own_root=true;event(a,p);event(a,p,"fired",nil,206);event(a,p,"landed",nil,206)
assert(a.ranged_stationary_hold and not p:IsRooted())
p.p.x=p.p.x+1;probe.observe(a,p,wall)
assert(not a.ranged_stationary_hold and a.contact_mode==0);clean(p,a)

-- Reject unsupported formal identity, native targets, geometry or modifiers.
for _,change in ipairs({function(u) u.target=wall2 end,function(u) u.hidden=true end,
    function(u) u.player_controlled=true end,function(u) u.attack_cap=1 end,
    function(u) u.survival_is_wave_monster=false end,function(u) u.survival_wave_movement_type="flying" end,
    function(u) u.classname="npc_dota_hero" end,function(u) u.CanEntityBeSeenByMyTeam=nil end,
    function(u) u.GetHullRadius=nil end,function(u) u.FindAllModifiers=nil end,
    function(u) u.modifiers[#u.modifiers+1]=safe_modifier("unknown_native") end}) do
    p,a=fixture();change(p);event(a,p);event(a,p,"fired",nil,207);event(a,p,"landed",nil,207)
    assert(not a.ranged_stationary_hold,"unsafe ranged entry");clean(p,a)
end

-- Every held geometry/target/control condition remains observed at the old
-- half-second cadence. An explicit foreign target releases on that event.
for _,change in ipairs({function(u) u.p.x=u.p.x-1 end,
    function(u) u.range=u.range+100 end,function(u) u.hull=u.hull+1 end,
    function(u) u.hidden=true end,function(u) u.force=wall2 end,
    function(u) u.target=wall2 end,function(u) u.team=2 end,
    function(u) u.attack_cap=1 end,function(u) u.player_controlled=true end}) do
    p,a=enter();change(p);probe.observe(a,p,wall)
    assert(a.contact_mode==0 and not a.ranged_stationary_hold,"changed condition did not release")
    a:OnDestroy()
end
p,a=enter();wall.p.x=1;tick(a);assert(a.contact_mode==0);wall.p.x=0;clean(p,a)
p,a=enter();wall.hull=129;tick(a);assert(a.contact_mode==0);wall.hull=128;clean(p,a)
p,a=enter();wall.protected=true;tick(a);assert(a.contact_mode==0);wall.protected=false;clean(p,a)
p,a=enter();wall.attack_immune=true;tick(a);assert(a.contact_mode==0);wall.attack_immune=false;clean(p,a)
p,a=enter();p.target=wall2;event(a,p,"start",wall2)
assert(not a.ranged_stationary_hold and a.contact_mode==0);clean(p,a)

-- Replacement contact modes are external ownership; a release cannot reset
-- those modes. A target change releases once and then the original FSM owns it.
p,a=enter();a:SetContactMode(2);local writes=a.stack_writes;probe.observe(a,p,wall)
assert(a.contact_mode==2 and a.stack_writes==writes and not a.ranged_stationary_hold);a:OnDestroy()
p,a=enter();writes=a.stack_writes;a:SetWallEntIndex(2)
assert(a.contact_mode==0 and a.stack_writes==writes+1 and not a.ranged_stationary_hold)
a:SetWallEntIndex(2);assert(a.stack_writes==writes+1);a:OnDestroy()
p,a=enter();wall.alive=false;a:HandleDeath({unit=wall})
assert(a.contact_mode==0 and not a.ranged_stationary_hold);wall.alive=true;a:OnDestroy()
p,a=enter();p.alive=false;tick(a)
assert(a.contact_mode==0 and not a.ranged_stationary_hold);a:OnDestroy()

-- Slow native attack intervals retain sufficient grace without changing BAT.
p,a=enter();p.rate=.2;tick(a,5);assert(a.contact_mode==6,"slow fire prematurely released")
tick(a,6);assert(a.contact_mode==0 and not a.ranged_stationary_hold,"stalled fire remained rooted")
assert(p.bat==1.7);a:OnDestroy()
p,a=enter();probe.set_probe_enabled(false);tick(a)
assert(a.contact_mode==0 and not a.ranged_stationary_hold);a:OnDestroy()
enable();p,a=enter();local previous_world=world;world={};tick(a)
assert(a.contact_mode==0 and not a.ranged_stationary_hold and not probe.enabled(),"old-map flag leaked")
world=previous_world;a:OnDestroy()

-- Start history and diagnostic history remain bounded under sustained load.
enable();p,a=fixture()
for i=1,100 do event(a,p,"fired",nil,i) end
assert(#a.ranged_stationary_pending==probe.snapshot().pending_limit)
event(a,p,"landed",nil,1);assert(not a.ranged_stationary_hold,"evicted start was paired")
event(a,p,"landed",nil,100);assert(a.ranged_stationary_hold);clean(p,a)
enable()
for _=1,100 do p,a=enter();clean(p,a) end
c=probe.snapshot()
assert(c.entered==100 and c.exited==100 and c.active_holds==0)
assert(#c.bat_samples==32 and c.samples_overwritten==68)
assert(c.observation_interval_seconds==.5 and c.native_attack_continuity_verified==false)
probe.set_probe_enabled(false)
print("ENEMY_RANGED_STATIONARY_PASS default-off Tools world, ROOTED-only client/server, exact Fired(record)/Landed(record) firing pairs, native hull reach, 60 stable ticks, external control ownership, geometry/targets/death, bounded diagnostics; native continuity UNVERIFIED")
