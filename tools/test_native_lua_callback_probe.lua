-- Real Lua 5.1 debug hooks, independent simulated callbacks. No game/console.
package.path="scripts/vscripts/?.lua;"..package.path
local wall,world,tools,server,map=0,{},true,true,"template_map"
local clock_failed=false
IsServer=function() return server end
IsInToolsMode=function() return tools end
GetMapName=function() return map end
GameRules={GetGameModeEntity=function() return world end}
SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
Plat_FloatTime=function() if clock_failed then error("clock-private-error") end;return wall end
local original_gethook,original_sethook,original_getinfo=debug.gethook,debug.sethook,debug.getinfo
local getter_body_calls,callback_returns=0,{}
local function increment_wall(dt) wall=wall+dt end
modifier_callback_probe_test={}
function modifier_callback_probe_test:GetModifierAttackSpeedBonus_Constant(secret)
    getter_body_calls=getter_body_calls+1
    increment_wall(.002)
    local value=math.abs(-7) -- a real C call must not corrupt sampled timing.
    return value,secret,nil,11
end
function modifier_callback_probe_test:CheckState()
    increment_wall(.001)
    return {rooted=false}
end
function modifier_callback_probe_test:OnAttack()
    increment_wall(.003)
    local state=self:CheckState()
    return state.rooted
end
function modifier_callback_probe_test:OnTakeDamage()
    error("business-secret-unchanged",0)
end
local function tail_body() increment_wall(.001);return 13 end
function modifier_callback_probe_test:OnAttackLanded() return tail_body() end
local probe=require("tests/manual_native_lua_callback_probe")
assert(debug.gethook()==nil and probe.report().reason=="not_started","require installed a hook")
local function report_and_empty()
    local result=probe.report()
    assert(debug.gethook()==nil,"own hook not restored")
    assert(result.restore_status=="restored_empty_hook" or result.restore_status=="already_empty")
    assert(not result.active and not result.cleanup_pending)
    return result
end
local function detail(result,name)
    for _,row in ipairs(result.details) do if row.name==name then return row end end
end

-- Preconditions and limits never displace an existing debugger/profiler.
tools=false;assert(not probe.start());tools=true
server=false;assert(not probe.start());server=true
map="wrong_map";assert(not probe.start());map="template_map"
local saved_guard=SURVIVAL_REAL_GAME_STRESS_ISOLATION
SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode={}};assert(not probe.start())
SURVIVAL_REAL_GAME_STRESS_ISOLATION=saved_guard
assert(not probe.start({seconds=6}) and not probe.start({max_calls=100001}))
local foreign=function() end
debug.sethook(foreign,"c",17)
local ok,reason=probe.start()
assert(not ok and reason=="existing_hook_preserved")
local f,mask,count=debug.gethook();assert(f==foreign and mask=="c" and count==17)
debug.sethook()

-- Correct protected getinfo level: attribute the actual callback function,
-- not the hook, handler, pcall, or the caller's unrelated method name.
assert(probe.start({seconds=5}))
assert(not probe.start(),"second capture replaced first hook")
for _=1,3 do
    local a,b,c,d=modifier_callback_probe_test:GetModifierAttackSpeedBonus_Constant("private-token")
    assert(a==7 and b=="private-token" and c==nil and d==11,"hook changed callback returns")
end
-- Native-like C invocation is only a boundary inference, not engine proof.
ok=pcall(modifier_callback_probe_test.GetModifierAttackSpeedBonus_Constant,modifier_callback_probe_test,"private-token")
assert(ok)
modifier_callback_probe_test:OnAttack()
local result=report_and_empty()
local row=assert(detail(result,"GetModifierAttackSpeedBonus_Constant"))
assert(row.calls==4 and row.lua_caller_calls==3 and row.c_boundary_calls==1)
assert(row.source:match("test_native_lua_callback_probe%.lua$") and row.linedefined>0)
assert(result.coverage.native_modifier_calls>=1 and result.coverage.modifier_callback_calls>=6)
assert(result.native_engine_origin_not_proven and result.args_upvalues_profiles_inspected==false)
assert(result.sample_timings==false and result.samples_started==0 and row.timed_samples==0)
assert(getter_body_calls==4)

-- File-labelled fixtures simulate existing anonymous native bindings without
-- installing/wrapping any production callback. Labels are not file provenance.
-- pcall is deliberately only C ancestry, not evidence of a Dota engine caller.
local function file_fixture(body,path)
    return assert(loadstring("return function(helper, value) "..body.." end","@"..path))()
end
local helper=file_fixture("local result=21; return result", "scripts/vscripts/core/probe_plain_helper.lua")
local anonymous_filter=file_fixture("local result=helper(); return result,value,nil,11", "scripts/vscripts/combat/damage_filter_service.lua")
local anonymous_order=file_fixture("local result=helper(); return result", "scripts/vscripts/systems/tree_attack_order_filter.lua")
local anonymous_ai=file_fixture("local result=helper(); return result", "scripts/vscripts/core/scheduler.lua")
local anonymous_ability=file_fixture("local result=helper(); return result", "scripts/vscripts/abilities/probe_ability.lua")
local outside=file_fixture("local result=21; return result", "C:/outside/scripts/vscripts/combat/probe_outside.lua")
local traversal=file_fixture("local result=21; return result", "scripts/vscripts/../private/probe_traversal.lua")
local dynamic=assert(loadstring("return function() local secret='inline-boundary-private-token'; return 21 end"))()
local filter_module,order_module=package.loaded["combat/damage_filter_service"],package.loaded["systems/tree_attack_order_filter"]
package.loaded["combat/damage_filter_service"]={_filter_for_test=anonymous_filter}
package.loaded["systems/tree_attack_order_filter"]={_filter_for_test=anonymous_order}
assert(probe.start())
local native_ok,a,b,c,d=pcall(anonymous_filter,helper,"boundary-private-token")
assert(native_ok and a==21 and b=="boundary-private-token" and c==nil and d==11)
assert(pcall(anonymous_order,helper) and pcall(anonymous_ai,helper) and pcall(anonymous_ability,helper))
helper() -- Ordinary Lua helper has no boundary entry, including inside bindings.
anonymous_filter(helper) -- Exported identity alone does not prove a C boundary.
assert(pcall(outside) and pcall(traversal) and pcall(dynamic))
result=report_and_empty()
assert(result.boundary_classification_enabled and result.boundary_export_metadata_entries==2)
assert(result.coverage.native_boundary_calls==4 and result.coverage.workspace_c_caller_calls==4
    and result.coverage.workspace_no_lua_caller_calls==0 and result.coverage.boundary_export_identity_calls==2)
assert(result.coverage.modifier_callback_calls==0 and result.coverage.native_modifier_calls==0,
    "new boundary counts must not pollute compatible modifier counters")
assert(#result.details==4 and result.samples_started==0)
local found_filter,found_ai,found_ability=false,false,false
for _,entry in ipairs(result.details) do
    assert(entry.calls==1 and entry.c_boundary_calls==1 and entry.native_boundary_calls==1
        and not entry.is_modifier_callback and entry.lua_caller_calls==0 and entry.linedefined>0)
    assert(entry.source==entry.workspace_source and entry.source:match("^scripts/vscripts/"))
    assert(entry.match=="workspace_lua_c_or_no_lua_caller_boundary")
    if entry.source=="scripts/vscripts/combat/damage_filter_service.lua" then
        found_filter=true; assert(entry.export_aliases[1]=="combat/damage_filter_service:_filter_for_test"
            and entry.export_identity_calls==1)
        entry.export_aliases[1]="mutated copy"
    elseif entry.source=="scripts/vscripts/core/scheduler.lua" then found_ai=true
    elseif entry.source=="scripts/vscripts/abilities/probe_ability.lua" then found_ability=true end
end
assert(found_filter and found_ai and found_ability)
local detached=probe.report()
for _,entry in ipairs(detached.details) do
    if entry.source=="scripts/vscripts/combat/damage_filter_service.lua" then
        assert(entry.export_aliases[1]=="combat/damage_filter_service:_filter_for_test")
    end
end
local boundary_json=require("core/json_encoder").encode(detached)
assert(not boundary_json:find("private%-token") and not boundary_json:find("outside")
    and not boundary_json:find("traversal") and detached.native_engine_origin_not_proven
    and detached.source_labels_not_authenticated and not detached.self_time_measured)
package.loaded["combat/damage_filter_service"],package.loaded["systems/tree_attack_order_filter"]=filter_module,order_module

-- The probe itself is loaded via a relative path, while native class callbacks
-- can have absolute file sources. Accept only the explicitly declared root.
local absolute_root="D:/SteamLibrary/steamapps/common/dota 2 beta/game/dota_addons/survival/scripts/vscripts/"
local absolute_filter=file_fixture("local result=helper(); return result",absolute_root.."combat/probe_absolute_filter.lua")
local absolute_ai=file_fixture("local result=helper(); return result",absolute_root.."modifiers/probe_absolute_ai.lua")
modifier_absolute_boundary_probe={CheckState=file_fixture("local result=21; return result",absolute_root.."modifiers/probe_absolute_class.lua")}
assert(probe.start())
assert(pcall(absolute_filter,helper) and pcall(absolute_ai,helper))
assert(pcall(modifier_absolute_boundary_probe.CheckState))
result=report_and_empty()
assert(result.coverage.native_boundary_calls==0 and result.coverage.native_modifier_calls==1,
    "default relative probe root must not broadly accept arbitrary absolute vscripts paths")
assert(not result.declared_root and result.source_scope.origin=="derived_relative_probe_source")
for _,bad in ipairs({"scripts/vscripts", "D:relative/scripts/vscripts", "D:/repo/../scripts/vscripts",
    "D:/repo/./scripts/vscripts", "https://secret.example/scripts/vscripts", "D://repo/scripts/vscripts",
    "D:/repo/scripts/other", "D:/repo\n/scripts/vscripts", string.rep("x",513)}) do
    local accepted,why=probe.start({vscripts_root=bad})
    assert(not accepted and why=="invalid_declared_vscripts_root" and debug.gethook()==nil)
end
assert(probe.start({vscripts_root=absolute_root:sub(1,-2):gsub("/","\\")}))
assert(pcall(absolute_filter,helper) and pcall(absolute_ai,helper)
    and pcall(modifier_absolute_boundary_probe.CheckState) and pcall(anonymous_filter,helper))
assert(pcall(outside) and pcall(traversal))
result=report_and_empty()
assert(result.declared_root==absolute_root and result.source_scope.root==absolute_root
    and result.source_scope.origin=="explicit_tools_option"
    and result.source_scope.accepts_arbitrary_absolute_vscripts_paths==false)
assert(result.coverage.native_boundary_calls==4 and result.coverage.native_modifier_calls==1
    and result.coverage.workspace_legacy_modifier_boundary_calls==1 and result.coverage.workspace_other_boundary_calls==3)
assert(#result.details==4 and result.count_definitions.totals_overlap_do_not_sum
    and result.declared_root_not_independently_authenticated and result.source_labels_not_authenticated)
local classified=assert(detail(result,"CheckState"))
assert(classified.is_modifier_callback and classified.callback_classification=="legacy_modifier_callback"
    and classified.native_boundary_calls==1 and classified.workspace_source=="scripts/vscripts/modifiers/probe_absolute_class.lua")
for _,entry in ipairs(result.details) do
    assert(not entry.source:find("outside",1,true))
    if not entry.is_modifier_callback then
        assert(entry.callback_classification=="workspace_boundary_unclassified" and entry.c_boundary_calls==1)
    end
end

-- New anonymous entries share the original 64-row cap, without growing an
-- unbounded metadata cache per source/function or changing hard call limits.
local closures={}
for i=1,90 do closures[i]=file_fixture("local result=21; return result", "scripts/vscripts/systems/probe_many_"..i..".lua") end
assert(probe.start())
for _,fn in ipairs(closures) do assert(pcall(fn)) end
result=report_and_empty()
assert(result.coverage.native_boundary_calls==90 and #result.details==64
    and result.boundary_detail_omitted_calls==26 and result.callback_metadata_entries<4096)
-- A hundred instance closures from one file/template form one bounded row.
closures={}
for i=1,100 do closures[i]=file_fixture("local result=21; return result", "scripts/vscripts/core/probe_repeated_think.lua") end
assert(probe.start())
for _,fn in ipairs(closures) do assert(pcall(fn)) end
result=report_and_empty()
assert(result.coverage.native_boundary_calls==100 and #result.details==1
    and result.details[1].calls==100 and result.details[1].aggregation=="source_definition_span"
    and result.boundary_detail_omitted_calls==0)

-- Sample inclusive timing remains bounded and preserves nested C/Lua calls.
assert(probe.start({sample_timings=true,sample_every=1}))
modifier_callback_probe_test:GetModifierAttackSpeedBonus_Constant()
modifier_callback_probe_test:OnAttack()
result=report_and_empty()
row=assert(detail(result,"GetModifierAttackSpeedBonus_Constant"))
assert(row.timed_samples==1 and math.abs(row.inclusive_wall_ms-2)<.000001,
    "C or protected-hook frames corrupted callback timing")
row=assert(detail(result,"OnAttack"))
assert(row.timed_samples==1 and math.abs(row.inclusive_wall_ms-4)<.000001,
    "nested callback inclusive time was attributed as self time")
assert(not result.self_time_measured and not result.engine_cpp_body_time_measured)

-- Tail returns have invalid debug info: count callback entry, discard timing.
assert(probe.start({sample_timings=true,sample_every=1}))
assert(modifier_callback_probe_test:OnAttackLanded()==13)
result=report_and_empty()
assert(detail(result,"OnAttackLanded").calls==1 and result.tail_returns>0 and result.samples_discarded>=1)
assert(detail(result,"OnAttackLanded").timed_samples==0)

-- Business errors keep exact original error behavior; unwind stops timing
-- immediately, discarding open spans instead of inventing a large duration.
assert(probe.start({sample_timings=true,sample_every=1}))
ok,reason=pcall(modifier_callback_probe_test.OnTakeDamage,modifier_callback_probe_test)
assert(not ok and reason=="business-secret-unchanged")
result=report_and_empty()
assert(result.reason=="stack_unwind_detected" and result.samples_discarded>=1)
assert(detail(result,"OnTakeDamage").calls==1 and detail(result,"OnTakeDamage").timed_samples==0)

-- Clock failure is contained by the hook, never leaked into callback body.
assert(probe.start())
clock_failed=true
local value=modifier_callback_probe_test:GetModifierAttackSpeedBonus_Constant()
clock_failed=false
assert(value==7)
result=report_and_empty()
assert(result.reason=="clock_failed")

-- Errors in the hook's own metadata/context code are swallowed and cause
-- immediate own-hook restoration. No raw exception string enters report.
assert(probe.start())
local original_map=GetMapName
GetMapName=function() error("hook-private-error") end
value=modifier_callback_probe_test:GetModifierAttackSpeedBonus_Constant()
GetMapName=original_map
assert(value==7)
result=report_and_empty()
assert(result.reason=="hook_processing_failed" and result.hook_errors==1)
local info_failed=false
debug.getinfo=function(...)
    if info_failed then error("info-private-error") end
    return original_getinfo(...)
end
assert(probe.start())
info_failed=true
value=modifier_callback_probe_test:GetModifierAttackSpeedBonus_Constant()
info_failed=false;debug.getinfo=original_getinfo
assert(value==7)
result=report_and_empty()
assert(result.reason=="hook_processing_failed" and result.hook_errors==1)

-- An external later hook must win; stop must not remove or replace it.
assert(probe.start())
debug.sethook(foreign,"c",19)
assert(probe.stop())
result=probe.report()
f,mask,count=debug.gethook();assert(f==foreign and mask=="c" and count==19)
assert(result.restore_status=="external_hook_preserved")
debug.sethook()

-- Main-thread Lua 5.1 has no thread handle. Stop from a coroutine defers its
-- own cleanup until the next installing-thread event, touching no foreign hook.
assert(probe.start())
local co=coroutine.create(function() return probe.stop() end)
local resumed=coroutine.resume(co)
assert(resumed)
result=report_and_empty()
assert(result.reason=="stopped")

-- World/guard changes remove our own installing-thread hook without gameplay.
assert(probe.start())
local old_world=world;world={}
modifier_callback_probe_test:CheckState()
result=report_and_empty();assert(result.reason=="world_or_guard_changed")
world=old_world
assert(probe.start())
local old_guard=SURVIVAL_REAL_GAME_STRESS_ISOLATION
SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
modifier_callback_probe_test:CheckState()
result=report_and_empty();assert(result.reason=="world_or_guard_changed")
SURVIVAL_REAL_GAME_STRESS_ISOLATION=old_guard

-- Any next event after realtime limit stops; no native timer is registered.
assert(probe.start({seconds=.1}))
wall=wall+.1
modifier_callback_probe_test:CheckState()
result=report_and_empty();assert(result.reason=="time_limit" and result.elapsed_realtime_seconds>=.1)
assert(probe.start({max_calls=20}))
for _=1,100 do modifier_callback_probe_test:CheckState() end
result=report_and_empty();assert(result.reason=="call_limit" and result.call_events<=20)
assert(probe.start({max_calls=1}))
result=report_and_empty();assert(result.reason=="call_limit" and result.call_events==1)

-- Detail and sample storage are fixed even under hundreds of callback funcs.
for i=1,100 do
    local name="modifier_callback_probe_many_"..i
    _G[name]={CheckState=function() increment_wall(.00001);return {} end}
end
assert(probe.start({sample_timings=true,sample_every=1}))
for i=1,100 do _G["modifier_callback_probe_many_"..i]:CheckState() end
for _=1,400 do modifier_callback_probe_test:CheckState() end
result=report_and_empty()
assert(#result.details==64 and result.detail_omitted_calls>0 and result.samples_started<=256)

-- Dynamic source and error strings must not expose program/argument secrets.
modifier_callback_probe_dynamic={CheckState=assert(loadstring("return function() local secret='inline-private-token'; return {} end"))()}
assert(probe.start())
modifier_callback_probe_dynamic:CheckState()
result=report_and_empty()
row=assert(detail(result,"CheckState"))
assert(row.source=="dynamic_source_omitted")
local json=require("core/json_encoder").encode(result)
assert(not json:find("private%-token") and not json:find("business%-secret") and not json:find("clock%-private"))

assert(debug.gethook()==nil and debug.gethook==original_gethook and debug.sethook==original_sethook
    and debug.getinfo==original_getinfo,"probe mutated debug APIs")
print("NATIVE_LUA_CALLBACK_PROBE_PASS real debug hook + protected getinfo identity, anonymous filter/AI/ability C boundaries, exported identity counts, Lua-helper/outside/traversal/dynamic exclusion, source-span aggregation, compatible modifier counts, exact returns, optional timing unchanged, tail/error discard, own restoration/foreign hook preservation, world/clock/5s/100k/64/256 bounds, no args/private-source leakage; engine coverage UNVERIFIED")
