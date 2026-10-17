-- Lifecycle/event probe invariants, independent of native FPS measurements.
package.path="scripts/vscripts/?.lua;"..package.path
local clock,tools,world=0,true,{}
local timers={}
IsServer=function() return true end
IsInToolsMode=function() return tools end
GetSystemTimeMS=function() return clock*1000 end
GameRules={GetGameModeEntity=function() return world end}
function world:SetContextThink(key,fn,delay) timers[key]=fn end
MODIFIER_EVENT_ON_ATTACK_START=1;MODIFIER_EVENT_ON_TAKEDAMAGE=2
MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT=77
local declarations,created,hits=0,0,0
local list={MODIFIER_EVENT_ON_ATTACK_START,MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT}
local params={value=10}
local original_decl=function(self,...)
    declarations=declarations+1
    return list,nil,"declaration_return"
end
local original_created=function(self,value,extra)
    created=created+1;assert(value==params and extra=="extra")
    self.shared_attack_observer=true
    return nil,value,extra
end
local original_attack=function(self,event,extra)
    hits=hits+1;assert(extra=="unchanged")
    if event.fail then error("expected_original_error") end
    return event,nil,"attack_return"
end
modifier_lumberjack_ai={DeclareFunctions=original_decl,OnCreated=original_created,OnAttackStart=original_attack}
package.loaded["systems/lumberjack_attack_observer"]={is_ready=function() return true end}
local unit={entindex=function() return 123 end,GetUnitName=function() return "npc_survival_lumberjack" end}
local function instance()
    return setmetatable({GetParent=function() return unit end},{__index=modifier_lumberjack_ai})
end
local probe=require("tests/manual_modifier_declaration_probe")
assert(modifier_lumberjack_ai.DeclareFunctions==original_decl and next(timers)==nil)
assert(probe.snapshot().status=="not_started" and declarations==0)
tools=false;assert(not probe.start(20));tools=true
assert(not probe.start(21) and not probe.start(0))
assert(probe.start(20));assert(not probe.start(20))
assert(declarations==0 and created==0 and hits==0,"start invoked gameplay callbacks")
local before=instance()
local returned,nothing,last=before:DeclareFunctions()
assert(returned==list and nothing==nil and last=="declaration_return")
local a,b,c=before:OnCreated(params,"extra")
assert(a==nil and b==params and c=="extra")
before:DeclareFunctions() -- Repeat must not overwrite first native observation.
local after=instance();after:OnCreated(params,"extra");after:DeclareFunctions()
local unrelated={attacker={},target={}}
local related={attacker=unit,target={}}
for _=1,65 do
    local value,n,z=before:OnAttackStart(unrelated,"unchanged")
    assert(value==unrelated and n==nil and z=="attack_return")
end
before:OnAttackStart(related,"unchanged")
local ok,error_message=pcall(function() before:OnAttackStart({fail=true},"unchanged") end)
assert(not ok and error_message:find("expected_original_error",1,true))
assert(hits==67 and declarations==3 and created==2)
local snapshot=probe.snapshot()
local stats=snapshot.classes[1]
assert(stats.first_declarations==2 and stats.first_phase.before_created_enter==1
    and stats.first_phase.after_created_enter==1)
assert(stats.first_global_events.OnAttackStart==2 and stats.created_instances==2)
assert(stats.callbacks.OnAttackStart.calls==67 and stats.callbacks.OnAttackStart.self_related==1
    and stats.callbacks.OnAttackStart.unrelated==66 and stats.callbacks.OnAttackStart.sampled_caller_reads==3)
assert(snapshot.examples[1].observer_ready_at_first.is_ready==true)
assert(snapshot.examples[1].flags_at_first.shared_attack_observer==nil
    and snapshot.examples[1].flags_after_created.shared_attack_observer==true)
assert(snapshot.metadata_errors==0 and snapshot.example_limit==32)
-- Fixed report-size and metadata capacity, without modifying declarations.
for _=1,1100 do local x=instance();x:DeclareFunctions();x:OnCreated(params,"extra") end
snapshot=probe.snapshot()
assert(#snapshot.examples==32 and snapshot.instances_tracked==1024
    and snapshot.instance_overflow_observations>0)
snapshot.examples[1].class="tampered"
assert(probe.snapshot().examples[1].class=="modifier_lumberjack_ai","report exposed live state")
local own=modifier_lumberjack_ai.OnAttackStart
local newer=function() return "newer_owner" end
modifier_lumberjack_ai.OnAttackStart=newer
clock=20
local timer=assert(timers.survival_modifier_declaration_probe)
assert(timer()==nil)
snapshot=probe.snapshot()
assert(snapshot.status=="stopped" and snapshot.reason=="complete" and snapshot.elapsed_seconds==20)
assert(modifier_lumberjack_ai.DeclareFunctions==original_decl
    and modifier_lumberjack_ai.OnCreated==original_created
    and modifier_lumberjack_ai.OnAttackStart==newer and snapshot.restore_skipped==1)
assert(timers.survival_modifier_declaration_probe==nil)
local stopped_calls=probe.snapshot().classes[1].callbacks.OnAttackStart.calls
own(before,related,"unchanged") -- An already queued wrapper is inert after Stop.
assert(probe.snapshot().classes[1].callbacks.OnAttackStart.calls==stopped_calls)
assert(probe.stop("again").reason=="complete")
modifier_lumberjack_ai.OnAttackStart=original_attack
assert(probe.start(1));world={}
local world_timer=assert(timers.survival_modifier_declaration_probe)
assert(world_timer()==nil and probe.snapshot().reason=="world_changed")
assert(modifier_lumberjack_ai.DeclareFunctions==original_decl)
print("MODIFIER_DECLARATION_PROBE_PASS inert require, Tools wall-time opt-in, first-before/after lifecycle, exact args/returns/errors, real callback relevance, bounded examples/instances, ownership-safe timer/restore; native origin UNVERIFIED")
