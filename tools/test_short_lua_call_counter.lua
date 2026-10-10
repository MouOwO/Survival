-- Real Lua5.1 debug-hook contracts, entirely offline. Never opens Dota.
local function run_tests()
package.path = 'scripts/vscripts/?.lua;' .. package.path
local real_print, lines = print, {}
print = function(value) lines[#lines+1] = value end
local tools_mode, server, wall_ms = false, true, 1000
IsInToolsMode = function() return tools_mode end
IsServer = function() return server end
GetSystemTimeMS = function() return wall_ms end
local watchdog, registrations = nil, 0
local mode = {SetContextThink = function(_,_,callback)
    watchdog=callback;registrations=registrations+1
end}
GameRules = {GetGameModeEntity = function() return mode end}
local counter = require('tests/manual_lua_call_counter')
assert(debug.gethook()==nil and registrations==0 and not counter.snapshot().active)
assert(not counter.run())
tools_mode,server = true,false
assert(not counter.run() and registrations==0)
server = true
local stock_create,stock_probes=coroutine.create,{}
coroutine.create=function(body)
    local thread=stock_create(body);stock_probes[#stock_probes+1]=thread;return thread
end
local refused,reason=counter.run()
coroutine.create=stock_create
assert(not refused and reason=='unsafe_thread_hook_inheritance',
    'Stock Lua5.1 native hook-mask inheritance must disable capture')
assert(debug.gethook()==nil and registrations==0 and not counter.snapshot().active)
assert(#stock_probes==2,'Preflight creates only its owned probe and child')
for _,thread in ipairs(stock_probes) do
    local fn,mask,count=debug.gethook(thread)
    assert(fn==nil and mask=='' and count==0,'Unsafe inheritance refusal clears both owned probe masks')
end

-- Only this offline harness simulates a runtime whose thread constructor
-- clears inherited masks. The production counter supplies no unsafe override.
local native_create,native_gethook,native_sethook=coroutine.create,debug.gethook,debug.sethook
coroutine.create=function(body)
    local child=native_create(body)
    local fn,mask,count=native_gethook(child)
    if fn==nil and (mask~='' or count~=0) then native_sethook(child) end
    return child
end
local fixture=assert(loadstring([[
local M = {}
function M:CheckState() return self,nil,'tail',nil end
function M:GetModifierAttackRangeBonus() return 35 end
function M:GetModifierIgnoreAttackSpeedLimit() return 1 end
function M:GetModifierAttackSpeedAbsoluteMax() return 500 end
function M:Throw(failure) error(failure,0) end
return M
]],'@scripts/vscripts/modifiers/fixture_cached_property.lua'))()
modifier_counter_fixture=fixture
local old_cached=fixture.CheckState
fixture.CheckState=function() return 'new_definition' end
local function count(...) return select('#',...),... end
local function row_by_line(rows,line)
    for _,row in ipairs(rows) do
        if row.source=='scripts/vscripts/modifiers/fixture_cached_property.lua' and row.line==line then return row end
    end
    error('Missing actual cached function source line '..line)
end

assert(counter.run({max_calls=50000,wall_seconds=0.15}))
local capture_hook=debug.gethook()
assert(type(capture_hook)=='function')
assert(not counter.run(), 'Cannot nest captures')
local before_lines=#lines
for _=1,12 do old_cached(fixture) end
local n,first,middle,tail,last=count(old_cached(fixture))
assert(n==4 and first==fixture and middle==nil and tail=='tail' and last==nil)
for _=1,6 do assert(fixture:GetModifierAttackRangeBonus()==35) end
for _=1,4 do assert(fixture:GetModifierIgnoreAttackSpeedLimit()==1) end
for _=1,3 do assert(fixture:GetModifierAttackSpeedAbsoluteMax()==500) end
local failure={message='untouched_gameplay_error'}
local ok,err=pcall(fixture.Throw,fixture,failure)
assert(not ok and err==failure and debug.gethook()==capture_hook)
assert(#lines==before_lines, 'No per-call output')
assert(counter.stop('fixture_complete'))
assert(debug.gethook()==nil and watchdog==nil)
local result=counter.snapshot()
assert(result.restore_status=='restored' and result.restore_confirmed and result.thread_addressed
    and result.timing_valid==false and result.scope=='captured_lua_thread')
assert(result.hook_verified, 'Validate getinfo stack semantics in the installed hook')
assert(row_by_line(result.rows,2).calls==13 and row_by_line(result.rows,2).label==nil,
    'A cached old function remains observable even after its class slot is replaced')
assert(row_by_line(result.rows,3).calls==6 and row_by_line(result.rows,3).label=='modifier_counter_fixture.GetModifierAttackRangeBonus')
assert(row_by_line(result.rows,4).calls==4 and row_by_line(result.rows,5).calls==3)
row_by_line(result.rows,2).calls=900
assert(row_by_line(counter.snapshot().rows,2).calls==13, 'Snapshots cannot mutate retained counts')
local previous_lines=#lines
counter.stop('second_stop')
assert(#lines==previous_lines, 'Only one report')

-- All property names are discovered, along with the engine's non-GetModifier
-- state/health/animation callbacks. Sample real Lua callers and a C bridge.
local all_getters={
    'GetModifierHealthBonus','GetModifierPhysicalArmorBonus','GetModifierPreAttack_BonusDamage',
    'GetDisableAutoAttack','GetMinHealth','GetOverrideAnimation','GetOverrideAnimationRate',
    'GetOverrideAnimationWeight','GetActivityTranslationModifiers','GetPlaybackRateOverride',
}
local getter_factory=assert(loadstring('return function() return function() return 1 end end',
    '@scripts/vscripts/modifiers/fixture_property_factory.lua'))()
fixture.GetModifierFactoryAttack=getter_factory()
fixture.GetModifierFactoryArmor=getter_factory()
for index,name in ipairs(all_getters) do
    fixture[name]=assert(loadstring('return function(self) return '..index..' end',
        '@scripts/vscripts/modifiers/fixture_'..name..'.lua'))()
end
local caller_one=assert(loadstring('return function(object) return object:GetModifierHealthBonus() end',
    '@scripts/vscripts/systems/counter_caller_one.lua'))()
local caller_two=assert(loadstring('return function(object) return pcall(object.GetModifierHealthBonus,object) end',
    '@scripts/vscripts/systems/counter_caller_two.lua'))()
assert(counter.run({max_calls=50000,wall_seconds=0.15}))
caller_one(fixture)
local bridge_ok,bridge_result=caller_two(fixture)
assert(bridge_ok and bridge_result==1)
for _=1,10 do caller_one(fixture) end
for _,name in ipairs(all_getters) do assert(type(fixture[name](fixture))=='number') end
for _=1,2 do fixture:GetModifierFactoryAttack() end
for _=1,3 do fixture:GetModifierFactoryArmor() end
counter.stop('expanded_getters')
result=counter.snapshot()
local labelled={}
for _,row in ipairs(result.rows) do labelled[row.label or '']=row end
for _,name in ipairs(all_getters) do
    assert(labelled['modifier_counter_fixture.'..name], 'Missing property label '..name)
end
assert(labelled['modifier_counter_fixture.GetModifierFactoryAttack'].calls==2
    and labelled['modifier_counter_fixture.GetModifierFactoryArmor'].calls==3,
    'Factory closures at the same file/definition line keep distinct counts and labels')
local origins={}
for _,entry in ipairs(result.ancestors) do
    if entry.getter=='modifier_counter_fixture.GetModifierHealthBonus' then origins[#origins+1]=entry end
    assert(not entry.source:find('manual_lua_call_counter',1,true),'The profiler must not be its own caller')
end
assert(#origins==2 and origins[1].source=='scripts/vscripts/systems/counter_caller_one.lua'
    and origins[1].line==1 and not origins[1].native_bridge,
    'Attribute the getter to the real immediate Lua caller')
assert(origins[2].source=='scripts/vscripts/systems/counter_caller_two.lua'
    and origins[2].line==1 and origins[2].native_bridge,'Retain a native bridge without printing its name/arguments')
assert(result.ancestor_samples<=32 and result.max_function_samples==2 and result.ancestor_skipped_calls>0)
origins[1].source='mutated'
local isolated=counter.snapshot()
for _,entry in ipairs(isolated.ancestors) do assert(entry.source~='mutated','Ancestry snapshots are copies') end

-- Neither anonymous getter source nor an anonymous/console caller may reveal
-- the code, including when a chunk has a descriptive '=' console name.
local secret='NEVER_PRINT_TEST_COMMAND_SOURCE'
local private_getter=assert(loadstring('return function() local token="'..secret..'" return #token end'))()
fixture.GetModifierPrivateOne=private_getter
fixture.GetModifierPrivateTwo=assert(loadstring('return function() return 42 end'))()
local private_caller=assert(loadstring('local token="'..secret..'"; return function(object) return object:GetModifierPrivateOne() end'))()
local console_caller=assert(loadstring('local token="'..secret..'"; return function(object) return object:GetModifierHealthBonus() end',
    '=console '..secret))()
local reports_before=#lines
assert(counter.run({max_calls=50000,wall_seconds=0.15}))
private_caller(fixture)
console_caller(fixture)
fixture:GetModifierPrivateTwo()
counter.stop('private_sources')
result=counter.snapshot()
local private_labels={}
for _,row in ipairs(result.rows) do
    assert(not row.source:find(secret,1,true))
    private_labels[row.label or '']=true
end
assert(private_labels['modifier_counter_fixture.GetModifierPrivateOne']
    and private_labels['modifier_counter_fixture.GetModifierPrivateTwo'],
    'Anonymous chunks with the same line keep separate function counts/labels')
for _,entry in ipairs(result.ancestors) do
    assert(not entry.function_source:find(secret,1,true) and not entry.source:find(secret,1,true))
    if entry.getter=='modifier_counter_fixture.GetModifierPrivateOne'
        or entry.getter=='modifier_counter_fixture.GetModifierHealthBonus' then
        assert(entry.source=='anonymous','Private caller metadata is opaque')
    end
end
for index=reports_before+1,#lines do assert(not lines[index]:find(secret,1,true),'No command source in any output') end

-- Bounds apply to samples and output globally, as well as each function. Once
-- exhausted, more getters are counted without further ancestor introspection.
local capacity={}
for index=1,24 do
    capacity['GetModifierBound'..index]=assert(loadstring('return function() return '..index..' end',
        '@scripts/vscripts/modifiers/counter_ancestor_'..index..'.lua'))()
end
modifier_counter_ancestor_capacity=capacity
assert(counter.run({max_calls=50000,wall_seconds=0.15}))
for _,fn in pairs(capacity) do for _=1,3 do fn() end end
counter.stop('bounded_ancestors')
result=counter.snapshot()
assert(result.ancestor_samples==32 and #result.ancestors<=32 and result.ancestor_skipped_calls>=40)
local samples={}
for _,entry in ipairs(result.ancestors) do
    samples[entry.getter]=(samples[entry.getter] or 0)+entry.samples
    assert(samples[entry.getter]<=2,'At most two samples per function')
end
modifier_counter_ancestor_capacity=nil

-- The safety cap counts all call events, including C calls. Hitting it removes
-- the hook inside that event, even if the caller never requests a report.
assert(counter.run({max_calls=100,wall_seconds=0.15}))
local cap_watchdog=watchdog
for _=1,300 do old_cached(fixture) end
assert(debug.gethook()==nil)
result=counter.snapshot()
assert(not result.active and result.reason=='call_limit' and result.events==100)
cap_watchdog()
assert(counter.snapshot().restore_status=='already_clear_verified' and watchdog==nil)

assert(counter.run({max_calls=50000,wall_seconds=0.005}))
wall_ms=wall_ms+7
old_cached(fixture)
assert(debug.gethook()==nil and counter.snapshot().reason=='wall_limit')
watchdog()
assert(watchdog==nil)

-- Watchdog works independently of wall progress and ensures reporting/cleanup
-- when the engine resumes Lua after an idle period.
assert(counter.run({max_calls=50000,wall_seconds=0.15}))
watchdog()
assert(debug.gethook()==nil and counter.snapshot().reason=='watchdog' and watchdog==nil)

local external_calls=0
local external=function() external_calls=external_calls+1 end
debug.sethook(external,'c',0)
local refused,reason=counter.run()
assert(not refused and reason=='existing_hook_preserved' and debug.gethook()==external)
debug.sethook()

-- A watchdog on a different Lua thread must clear the retained origin handle,
-- while leaving the watchdog caller's unrelated hook intact.
local origin=coroutine.create(function()
    assert(counter.run({max_calls=50000,wall_seconds=0.15}))
    coroutine.yield(debug.gethook())
end)
local resumed,origin_hook=coroutine.resume(origin)
assert(resumed and type(origin_hook)=='function' and debug.gethook(origin)==origin_hook)
debug.sethook(external,'c',0)
watchdog()
assert(debug.gethook()==external,'Never remove the watchdog caller\'s foreign hook')
local origin_fn,origin_mask,origin_count=debug.gethook(origin)
assert(origin_fn==nil and origin_mask=='' and origin_count==0)
result=counter.snapshot()
assert(result.restore_confirmed and result.watchdog_thread_differs and result.restore_status=='restored')
debug.sethook()
assert(coroutine.resume(origin))

-- A nil hook function with an inherited native mask is not a clear thread.
debug.sethook(external,'c',0)
local inherited=native_create(function()
    local accepted,why=counter.run()
    assert(not accepted and why=='existing_hook_preserved')
end)
debug.sethook()
local inherited_fn,inherited_mask=debug.gethook(inherited)
assert(inherited_fn==nil and inherited_mask=='c')
assert(coroutine.resume(inherited))
debug.sethook(inherited)
assert(external_calls>0)

assert(counter.run())
debug.sethook(external,'c',0)
counter.stop('external_replacement')
assert(debug.gethook()==external and counter.snapshot().restore_status=='replacement_preserved')
debug.sethook()

-- A failed targeted clear retains the original owner and blocks another
-- capture. Retrying may succeed, but never report the failed attempt as clear.
assert(counter.run({max_calls=50000,wall_seconds=0.15}))
local capture_key='SURVIVAL_SHORT_LUA_CALL_COUNTER'
local retained_owner=_G[capture_key]
local retained_sethook=retained_owner.sethook
retained_owner.sethook=function() end
local stopped,status=counter.stop('failed_targeted_clear')
assert(not stopped and status=='restore_failed')
assert(debug.gethook(retained_owner.thread)==retained_owner.hook)
assert(counter.snapshot().restart_required and not counter.snapshot().restore_confirmed)
local blocked_thread=coroutine.create(function() return counter.run() end)
local attempted,accepted,why=coroutine.resume(blocked_thread)
assert(attempted and not accepted and why=='previous_capture_unverified_restart_required')
assert(_G[capture_key]==retained_owner,'Never abandon the uncleared thread handle')
retained_owner.sethook=retained_sethook
assert(counter.stop('retry_targeted_clear'))
local cleared_fn,cleared_mask,cleared_count=debug.gethook(retained_owner.thread)
assert(cleared_fn==nil and cleared_mask=='' and cleared_count==0)
assert(counter.snapshot().restore_confirmed and not counter.snapshot().restart_required)

-- Pre-upgrade records do not identify their originating thread. A watchdog
-- thread's hook must not be queried/cleared as a substitute for that owner.
local legacy={}
for key,value in pairs(retained_owner) do legacy[key]=value end
legacy.thread=nil;legacy.restore_confirmed=nil;legacy.restart_required=nil
legacy.restore_status='already_clear';legacy.reported=true
_G[capture_key]=legacy
debug.sethook(external,'c',0)
stopped,status=counter.stop('legacy_record')
assert(not stopped and status=='legacy_owner_unknown_restart_required')
assert(debug.gethook()==external and counter.snapshot().restart_required)
accepted,why=counter.run()
assert(not accepted and why=='previous_capture_unverified_restart_required')
debug.sethook()
_G[capture_key]=retained_owner

SURVIVAL_EXTREME_PERFORMANCE_CAPTURE={}
refused,reason=counter.run()
assert(not refused and reason=='timing_capture_active')
SURVIVAL_EXTREME_PERFORMANCE_CAPTURE=nil
local original_gethook,original_sethook,original_clock=debug.gethook,debug.sethook,GetSystemTimeMS
debug.sethook=nil
refused,reason=counter.run()
assert(not refused and reason=='debug_hook_unavailable')
debug.sethook=original_sethook
GetSystemTimeMS=nil
refused,reason=counter.run()
assert(not refused and reason=='native_wall_clock_unavailable')
GetSystemTimeMS=original_clock
debug.gethook=function() error('not available in engine') end
refused,reason=counter.run()
assert(not refused and reason=='gethook_failed')
debug.gethook=original_gethook
debug.sethook=function() error('read only') end
refused,reason=counter.run()
assert(not refused and reason=='thread_hook_preflight_failed' and debug.gethook()==nil and watchdog==nil)
debug.sethook=original_sethook

-- A clock failure while capturing disables the diagnostic and never escapes
-- into the game function being called.
local clock_fail=false
GetSystemTimeMS=function() if clock_fail then error('clock failure') end return wall_ms end
assert(counter.run())
clock_fail=true
n,first,middle,tail,last=count(old_cached(fixture))
assert(n==4 and first==fixture and tail=='tail')
assert(debug.gethook()==nil and counter.snapshot().reason=='diagnostic_error')
watchdog()
GetSystemTimeMS=original_clock

local original_getinfo=debug.getinfo
local info_fail=false
debug.getinfo=function(...)
    if info_fail then error('metadata unavailable') end
    -- This wrapper would change numeric stack levels, so reject it in the
    -- handshake instead of silently attributing calls to the wrong function.
    return original_getinfo(...)
end
refused,reason=counter.run()
assert(not refused and reason=='hook_callback_unverified' and debug.gethook()==nil)
debug.getinfo=original_getinfo

-- Metadata failures in the additional ancestry walk restore the hook before
-- returning to the original gameplay getter, preserving its result.
local ancestor_fail=false
debug.getinfo=function(subject,...)
    if type(subject)=='number' then
        if ancestor_fail and subject>=4 then error('ancestor metadata unavailable') end
        return original_getinfo(subject+1,...)
    end
    return original_getinfo(subject,...)
end
assert(counter.run())
ancestor_fail=true
assert(fixture:GetModifierHealthBonus()==1)
assert(debug.gethook()==nil and counter.snapshot().reason=='ancestor_info_failed')
watchdog()
debug.getinfo=original_getinfo

local fake_functions={}
for index=1,620 do
    fake_functions[index]=assert(loadstring('return function() return 1 end',
        '@scripts/vscripts/modifiers/counter_capacity_'..index..'.lua'))()
end
local printed_before=#lines
assert(counter.run({max_calls=50000,wall_seconds=0.15}))
for _,fn in ipairs(fake_functions) do fn() end
counter.stop('bounded_rows')
result=counter.snapshot()
assert(#result.rows==512 and result.omitted_calls>=108)
local retained=0
for _,row in ipairs(result.rows) do retained=retained+row.calls end
assert(retained+result.omitted_calls==result.lua_calls)
assert(#lines-printed_before<=131, 'Start, summary, at most 128 rows and coverage')

assert(counter.run({max_calls=math.huge,wall_seconds=999}))
result=counter.snapshot()
assert(result.max_calls==10000 and result.wall_ms==150)
counter.stop('limits')
assert(counter.run({max_calls=999999,wall_seconds=0}))
result=counter.snapshot()
assert(result.max_calls==50000 and result.wall_ms==5)
counter.stop('limits')

-- The hook survives a module reload through the shared capture owner and is
-- safely removable by the re-required manual module, with no second install.
assert(counter.run())
capture_hook=debug.gethook()
package.loaded['tests/manual_lua_call_counter']=nil
counter=require('tests/manual_lua_call_counter')
assert(debug.gethook()==capture_hook)
assert(not counter.run())
counter.stop('module_reload')
assert(debug.gethook()==nil)
coroutine.create=native_create
print=real_print
return counter
end

local test_thread=coroutine.create(run_tests)
local ok,counter=coroutine.resume(test_thread)
assert(ok,counter)
local hook,mask,count=debug.gethook(test_thread)
assert(hook==nil and mask=='' and count==0,'Offline origin is fully clear, including native mask/count')
local accepted,reason=counter.run()
assert(not accepted and reason=='main_thread_unaddressable','Main nil cannot be cleared from a foreign watchdog')
hook,mask,count=debug.gethook()
assert(hook==nil and mask=='' and count==0)
print('short Lua call counter: PASS (addressed-thread clear, cross-thread watchdog/foreign hook safety, failed-clear/legacy refusal, main/inherited-mask refusal, all labels/bounded ancestry/privacy, cap/time/restoration, no timings)')
