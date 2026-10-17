-- Actual v3 stationary firing proof plus read-only inspection. Entity APIs are
-- simulated; native attack continuity and getter storage semantics are unknown.
package.path = "scripts/vscripts/?.lua;" .. package.path
local mutations, orders, calls, now = 0, 0, 0, 0
local tools, server, map, world = true, true, "template_map", {}
IsServer=function() return server end;IsInToolsMode=function() return tools end
GetMapName=function() return map end
GameRules={GetGameModeEntity=function() return world end,GetGameTime=function() return now end}
DOTA_TEAM_BADGUYS,DOTA_TEAM_GOODGUYS=3,2
DOTA_UNIT_CAP_RANGED_ATTACK=2
MODIFIER_STATE_ROOTED=3
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
package.loaded["core/team_alignment"]={are_enemies=function(a,b) return a.team~=b.team end}
local inspector=require("tests/manual_ranged_idle_acquire_inspector")
assert(_G.SURVIVAL_RANGED_STATIONARY_PROBE==nil and mutations==0 and calls==0,
    "require must not read/mutate native state or enable v3")
local v3=require("systems/enemy_ranged_stationary")
local function unit(index,team,x)
    local u={index=index,team=team,p={x=x,y=0,z=0},hull=32,range=600,alive=true,idle=true,
        survival_is_wave_monster=true,survival_wave_movement_type="ground"}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:GetClassname() return "npc_dota_creature" end
    function u:GetTeamNumber() return self.team end
    function u:GetAttackCapability() return DOTA_UNIT_CAP_RANGED_ATTACK end
    function u:GetAbsOrigin() return self.p end
    function u:Script_GetAttackRange() return self.range end
    function u:GetHullRadius() return self.hull end
    function u:GetForceAttackTarget() return self.force end
    function u:GetAttackTarget() return self.target end
    function u:CanEntityBeSeenByMyTeam() return true end
    function u:FindAllModifiers() return self.modifiers end
    function u:IsRooted() return self.owner and self.owner.contact_mode==6 or false end
    function u:GetAttacksPerSecond() return 1 end
    function u:ShouldIdleAcquire() calls=calls+1;return self.idle end
    function u:SetIdleAcquire() mutations=mutations+1;error("readonly inspection called setter") end
    function u:Stop() orders=orders+1;error("readonly inspection stopped attack") end
    return u
end
local wall=unit(1,2,0);wall.hull=128
local parent=unit(2,3,-735);parent.force,parent.target=wall,wall
local owner={contact_mode=0,wall_entindex=1,goal_wall=wall,ai_state="chase",
    GetParent=function() return parent end,SetContactMode=function(self,value) self.contact_mode=value end}
parent.owner=owner;parent.modifiers={owner}
local before=inspector.inspect(owner,parent,wall)
assert(before.api.observed_idle_boolean==true and not before.readonly_reversibility_test_prerequisites)
assert(before.stored_original_value_contract_verified==false and before.mutation_admission_granted==false)
assert(v3.set_probe_enabled(true))
v3.observe(owner,parent,wall,"start",{record=nil})
assert(not inspector.inspect(owner,parent,wall).proof.v3_own_hold)
v3.observe(owner,parent,wall,"fired",{record=901})
now=.3
v3.observe(owner,parent,wall,"landed",{record=902})
assert(not inspector.inspect(owner,parent,wall).readonly_reversibility_test_prerequisites,
    "mismatched actual v3 native records cannot establish readiness")
v3.observe(owner,parent,wall,"landed",{record=901})
assert(owner.ranged_stationary_hold)
local snapshot=v3.snapshot();local ready=inspector.inspect(owner,parent,wall)
assert(ready.readonly_reversibility_test_prerequisites and ready.proof.native_fired_landed_record)
assert(not ready.api.get_idle_acquire_function and ready.api.should_idle_acquire_function)
assert(v3.snapshot().entered==snapshot.entered and v3.snapshot().exited==snapshot.exited,
    "inspector cannot call v3 observe/release or modify counters")
assert(owner.contact_mode==6 and mutations==0 and orders==0)
parent.target=nil
local niltarget=inspector.inspect(owner,parent,wall)
assert(niltarget.proof.native_attack_target_nil and not niltarget.readonly_reversibility_test_prerequisites,
    "nil cooldown target is allowed by v3 but not sufficient to start acquisition mutation")
parent.target=wall
local target_getter=parent.GetAttackTarget
parent.GetAttackTarget=function() error("native getter failed") end
local failedtarget=inspector.inspect(owner,parent,wall)
assert(not failedtarget.proof.native_attack_target_nil
    and failedtarget.proof.native_attack_target_read_error=="read_failed",
    "an API failure is not proof of a native transient nil target")
parent.GetAttackTarget=target_getter
parent.idle=false
local falsevalue=inspector.inspect(owner,parent,wall)
assert(falsevalue.api.should_idle_acquire_boolean_readable and falsevalue.api.observed_idle_boolean==false,
    "false native observation stays distinct from unknown")
local original=parent.ShouldIdleAcquire
for _,value in ipairs({0,1,"false",{}}) do
    parent.ShouldIdleAcquire=function() return value end
    local invalid=inspector.inspect(owner,parent,wall)
    assert(not invalid.api.should_idle_acquire_boolean_readable and invalid.api.observed_idle_boolean==nil)
    assert(not invalid.readonly_reversibility_test_prerequisites)
end
parent.ShouldIdleAcquire=function() error("getter unavailable") end
assert(inspector.inspect(owner,parent,wall).api.read_failure=="read_failed")
parent.ShouldIdleAcquire=nil
assert(inspector.inspect(owner,parent,wall).api.read_failure=="unavailable")
parent.ShouldIdleAcquire=original;parent.idle=true
parent.SetIdleAcquire=nil
assert(not inspector.inspect(owner,parent,wall).readonly_reversibility_test_prerequisites)
parent.SetIdleAcquire=function() mutations=mutations+1;error("forbidden setter") end
parent.p.x=parent.p.x+1
assert(not inspector.inspect(owner,parent,wall).proof.geometry_matches);parent.p.x=parent.p.x-1
local native_foreign=unit(3,2,0)
parent.target=native_foreign
assert(not inspector.inspect(owner,parent,wall).readonly_reversibility_test_prerequisites);parent.target=wall
parent.force=native_foreign
assert(not inspector.inspect(owner,parent,wall).readonly_reversibility_test_prerequisites);parent.force=wall
local savedcalls=calls
tools=false;assert(not inspector.inspect(owner,parent,wall).authorized);tools=true
server=false;assert(not inspector.inspect(owner,parent,wall).authorized);server=true
map="other_map";assert(not inspector.inspect(owner,parent,wall).authorized);map="template_map"
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode={}}
assert(not inspector.inspect(owner,parent,wall).authorized)
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
local previous=world;world={}
assert(not inspector.inspect(owner,parent,wall).authorized);world=previous
assert(calls==savedcalls,"unauthorized inspection does not even call native getters")
wall.alive=false
assert(not inspector.inspect(owner,parent,wall).readonly_reversibility_test_prerequisites);wall.alive=true
parent.survival_is_wave_monster=false
assert(inspector.inspect(owner,parent,wall).reason=="not_formal_owned_ground_ranged")
parent.survival_is_wave_monster=true
assert(mutations==0 and orders==0 and owner.ranged_stationary_hold,
    "inspection never changes root, attacks or acquisition regardless of readiness")
print("PASS readonly idle acquisition inspector: real v3 Fired/Landed record proof, strict native wall target, bool false versus unknown, missing/failing APIs, geometry/identity, Tools/world authorization, no getters when unauthorized, zero setters/orders/probe mutations; stored getter contract/native continuity remain unverified")
