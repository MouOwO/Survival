-- Offline contract checks only. Never starts Dota or changes the live match.
package.path = "scripts/vscripts/?.lua;" .. package.path

local tools_mode, server = false, true
local wall_ms, cpu_seconds, clock_reads = 1000, 0, 0
local heap_kib, heap_reads = 100, 0
local original_print, original_clock, original_time = print, os.clock, os.time
local original_gc = collectgarbage
local lines, commands, installed_thinks = {}, {}, {}

local function advance(ms)
    wall_ms = wall_ms + ms
    cpu_seconds = cpu_seconds + ms / 1000
end

IsServer = function() return server end
IsInToolsMode = function() return tools_mode end
Time = function() error("Frame-constant Time() is not a profiling clock") end
GetSystemTimeMS = function() clock_reads = clock_reads + 1; return wall_ms end
os.clock = function() clock_reads = clock_reads + 1; return cpu_seconds end
os.time = function() return math.floor(wall_ms / 1000) end
collectgarbage = function(action)
    assert(action == "count", "Live profiling must never force or tune garbage collection")
    heap_reads = heap_reads + 1
    return heap_kib
end
print = function(line) lines[#lines + 1] = tostring(line) end
Convars = { RegisterCommand = function(_, name, callback)
    commands[name] = callback
end }

local think
local mode = { SetContextThink = function(_, _, callback)
    think = callback
    installed_thinks[#installed_thinks + 1] = callback
end }
GameRules = {
    GetGameModeEntity = function() return mode end,
    GetGameTime = function() return wall_ms / 1000 end,
    IsGamePaused = function() return false end,
}

local failure = { name = "exact_original_error" }
local radius_original = function(first, second)
    advance(6)
    return first, nil, second, nil
end
local entities_original = function(_, name)
    advance(3)
    return { name }, nil, "entity_tail"
end
FindUnitsInRadius = radius_original
Entities = { FindAllByClassname = entities_original }
modifier_tower_attack_effects = {
    OnIntervalThink = function(self)
        advance(2.5)
        return self, nil, "native_tail", nil
    end,
    OnAttack = function() error("This native callback is deliberately not invoked") end,
}
local interval_original = modifier_tower_attack_effects.OnIntervalThink
local attack_original = modifier_tower_attack_effects.OnAttack

local bus = require("core/event_bus")
bus.reset()
local delivered = 0
local subscriber_original = function(payload)
    advance(12)
    if payload.fail then error(failure, 0) end
    delivered = delivered + 1
    return payload, nil, "subscriber_tail", nil
end
local request_original = function(payload)
    advance(7)
    if payload.fail then error(failure, 0) end
    return payload, nil, "request_tail", nil
end
local subscription = bus.subscribe("fixture.subscriber", subscriber_original)
bus.handle_request("fixture.request", request_original)
local emit_original, bus_request_original = bus.emit, bus.request

local function upvalue(fn, wanted)
    for index = 1, 40 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("Actual event bus did not expose expected upvalue: " .. wanted)
end
local subscriber_slots = upvalue(emit_original, "subscribers")
local request_slots = upvalue(bus_request_original, "request_handlers")

local function find_named(values, fragment)
    if values and values[fragment] ~= nil then return values[fragment], fragment end
    local found, label
    for name, value in pairs(values or {}) do
        if tostring(name):find(fragment, 1, true) then
            assert(not found, "Ambiguous profiling label: " .. fragment)
            found, label = value, name
        end
    end
    assert(found, "Missing profiling row/status: " .. fragment)
    return found, label
end
local function near(actual, expected, why)
    assert(math.abs(actual - expected) < 0.00001, why or "Unexpected measured duration")
end
local function result_count(...)
    return select("#", ...), ...
end

local profile = require("tests/manual_extreme_profile")
assert(commands.survival_extreme_profile == nil,
    "The command must not register outside Tools mode")
assert(not profile.snapshot().active and bus.emit == emit_original,
    "Requiring the module must never start a capture")
assert(clock_reads == 0 and heap_reads == 0 and #installed_thinks == 0,
    "Disabled profiling must not read measurement clocks, sample the heap, or install a thinker")
assert(not profile.run(15) and bus.emit == emit_original)
tools_mode, server = true, false
assert(not profile.run(15) and clock_reads == 0)

-- Require in its valid engine context to test command registration separately
-- from run() gating. There is still no automatic capture.
server = true
package.loaded["tests/manual_extreme_profile"] = nil
profile = require("tests/manual_extreme_profile")
assert(type(commands.survival_extreme_profile) == "function")
assert(not profile.snapshot().active and clock_reads == 0 and #installed_thinks == 0)
local saved_mode = mode
mode = {}
local started, reason = profile.run(15)
assert(not started and reason == "context_think_unavailable")
assert(bus.emit == emit_original and FindUnitsInRadius == radius_original)
mode = saved_mode

-- A real match has already emitted events before sampling begins. Prime the
-- dispatch cache so wrapping only the private slot cannot yield false zeros.
bus.emit('fixture.subscriber',{})
delivered=0
assert(profile.run(1))
local first_capture_think = assert(think)
local initial = profile.snapshot()
assert(initial.active and initial.duration == 15, "Capture duration has a 15 second lower bound")
assert(initial.row_count==0 and next(initial.rows)==nil and initial.max_hooks==2048,
    "Installing uncalled callbacks consumes no measured rows")
assert(initial.frames.wall_available == true)
local subscriber_wrapper = subscriber_slots[subscription.event_name][subscription.token]
local request_wrapper = request_slots["fixture.request"]
assert(subscriber_wrapper ~= subscriber_original and request_wrapper ~= request_original,
    "Capture must instrument actual existing event subscribers and request handlers")
assert(bus.emit ~= emit_original and bus.request ~= bus_request_original)
assert(not profile.run(15), "A second capture must not replace active wrappers")

local payload = { value = 99 }
bus.emit("fixture.subscriber", payload)
assert(delivered == 1)
local count, first, middle, tail, last = result_count(subscriber_wrapper(payload))
assert(count == 4 and first == payload and middle == nil and tail == "subscriber_tail" and last == nil,
    "Subscriber wrappers preserve all return values including trailing nil")
count, first, middle, tail, last = result_count(request_wrapper(payload))
assert(count == 4 and first == payload and middle == nil and tail == "request_tail" and last == nil)
local reply, request_error = bus.request("fixture.request", payload)
assert(reply == payload and request_error == nil, "Exported request wrapping preserves actual bus semantics")
count, first, middle, tail, last = result_count(FindUnitsInRadius("radius_head", "radius_tail"))
assert(count == 4 and first == "radius_head" and middle == nil and tail == "radius_tail" and last == nil)
local entities, blank, entity_tail = Entities:FindAllByClassname("creature")
assert(entities[1] == "creature" and blank == nil and entity_tail == "entity_tail")
local owner = {}
count, first, middle, tail, last = result_count(modifier_tower_attack_effects.OnIntervalThink(owner))
assert(count == 4 and first == owner and middle == nil and tail == "native_tail" and last == nil)
local ok, err = pcall(subscriber_wrapper, { fail = true })
assert(not ok and err == failure, "Instrumentation must preserve the exact thrown error object")

local active = profile.snapshot()
local subscriber_row = find_named(active.rows, "fixture.subscriber")
assert(subscriber_row.calls == 3 and subscriber_row.slow_calls == 3 and subscriber_row.errors == 1)
near(subscriber_row.total_ms, 36)
near(subscriber_row.max_ms, 12)
local request_row = find_named(active.rows, "fixture.request")
assert(request_row.calls == 2 and request_row.errors == 0)
near(request_row.total_ms, 14)
local radius_row = find_named(active.rows, "FindUnitsInRadius")
assert(radius_row.calls == 1)
near(radius_row.total_ms, 6)
local entity_row = find_named(active.rows, "Entities.FindAllByClassname")
assert(entity_row.calls == 1)
near(entity_row.total_ms, 3)
local uncalled_status = find_named(active.hook_status, "modifier_tower_attack_effects.OnAttack")
assert(uncalled_status == "unconfirmed_native_hook",
    "A native Lua table hook with no captured invocation is unconfirmed, not a zero-cost claim")

-- The profiler thinker observes natural scheduling gaps and only reads heap size.
advance(16)
assert(type(think()) == "number")
heap_kib = 130
advance(550)
assert(type(think()) == "number")
advance(600)
assert(type(think()) == "number")
active = profile.snapshot()
assert(active.frames.samples >= 2 and active.frames.max_gap_ms >= 550)
assert(active.frames.over_50_ms >= 1 and active.frames.over_100_ms >= 1
    and active.frames.over_250_ms >= 1 and active.frames.over_500_ms >= 1)
assert(active.memory.samples >= 2 and active.memory.start_kib == 100 and active.memory.max_kib == 130)
local lines_before_stop = #lines
for i = 1, 30 do subscriber_wrapper(payload) end
assert(#lines == lines_before_stop, "Slow callbacks aggregate silently; no per-call diagnostic output")
assert(profile.stop("test_complete"))
assert(upvalue(emit_original,'dispatch_snapshots')['fixture.subscriber']==nil,
    'Stopping must discard cached wrapper references, not just restore slots')
assert(bus.emit == emit_original and bus.request == bus_request_original)
assert(subscriber_slots[subscription.event_name][subscription.token] == subscriber_original)
assert(request_slots["fixture.request"] == request_original)
assert(FindUnitsInRadius == radius_original and Entities.FindAllByClassname == entities_original)
assert(modifier_tower_attack_effects.OnIntervalThink == interval_original
    and modifier_tower_attack_effects.OnAttack == attack_original)
assert(not profile.snapshot().active and not profile.stop() and first_capture_think() == nil)
local slow_details = 0
for _, line in ipairs(lines) do
    if line:find("[EXTREME_SLOW]", 1, true) then slow_details = slow_details + 1 end
end
assert(slow_details > 0 and slow_details <= 12, "Stop emits at most twelve slow-call details")
local disabled_reads = clock_reads
FindUnitsInRadius("after", "disabled")
bus.emit("fixture.subscriber", payload)
assert(clock_reads == disabled_reads, "Restored callbacks incur no diagnostic clock reads")

-- Script reloads/new callback owners must survive old capture cleanup.
assert(profile.run(999) and profile.snapshot().duration == 120)
local reloaded_radius = function() return "reloaded" end
local reloaded_subscriber = function() return "new_subscriber" end
local reloaded_request = function() return "new_request" end
FindUnitsInRadius = reloaded_radius
subscriber_slots[subscription.event_name][subscription.token] = reloaded_subscriber
request_slots["fixture.request"] = reloaded_request
assert(profile.stop("script_reload"))
assert(FindUnitsInRadius == reloaded_radius)
assert(subscriber_slots[subscription.event_name][subscription.token] == reloaded_subscriber
    and request_slots["fixture.request"] == reloaded_request)
FindUnitsInRadius = radius_original
subscriber_slots[subscription.event_name][subscription.token] = subscriber_original
request_slots["fixture.request"] = request_original

-- Existing handlers are hooked immediately; registrations during capture join
-- at the next one-second discovery pass and are restored in their real slots.
local dynamic_delivered = 0
local dynamic_original = function(payload)
    advance(11)
    dynamic_delivered = dynamic_delivered + 1
    return payload
end
local dynamic_request_original = function(payload) advance(4); return payload end
assert(profile.run(15))
local dynamic_subscription = bus.subscribe("fixture.dynamic_subscriber", dynamic_original)
bus.handle_request("fixture.dynamic_request", dynamic_request_original)
assert(subscriber_slots[dynamic_subscription.event_name][dynamic_subscription.token] == dynamic_original)
assert(request_slots["fixture.dynamic_request"] == dynamic_request_original)
advance(1100)
assert(type(think()) == "number")
assert(subscriber_slots[dynamic_subscription.event_name][dynamic_subscription.token] ~= dynamic_original)
assert(request_slots["fixture.dynamic_request"] ~= dynamic_request_original)
bus.emit("fixture.dynamic_subscriber", payload)
assert(bus.request("fixture.dynamic_request", payload) == payload and dynamic_delivered == 1)
active = profile.snapshot()
local dynamic_row = find_named(active.rows, "fixture.dynamic_subscriber")
assert(dynamic_row.calls == 1 and dynamic_row.timed_calls == 1)
near(dynamic_row.total_ms, 11)
near(find_named(active.rows, "fixture.dynamic_request").total_ms, 4)
assert(profile.stop("dynamic_registration"))
assert(subscriber_slots[dynamic_subscription.event_name][dynamic_subscription.token] == dynamic_original)
assert(request_slots["fixture.dynamic_request"] == dynamic_request_original)

-- reset() replaces the bus's private tables. Discovery must follow those new
-- upvalues; cleanup may not resurrect old registrations or erase the new ones.
local old_subscriber_slots, old_request_slots = subscriber_slots, request_slots
assert(profile.run(15))
bus.reset()
subscriber_slots = upvalue(emit_original, "subscribers")
request_slots = upvalue(bus_request_original, "request_handlers")
assert(subscriber_slots ~= old_subscriber_slots and request_slots ~= old_request_slots)
local reset_delivered = 0
local reset_original = function() advance(5); reset_delivered = reset_delivered + 1 end
local reset_request_original = function(payload) advance(2); return payload end
local reset_subscription = bus.subscribe("fixture.reset_subscriber", reset_original)
bus.handle_request("fixture.reset_request", reset_request_original)
advance(1100)
assert(type(think()) == "number")
assert(subscriber_slots[reset_subscription.event_name][reset_subscription.token] ~= reset_original,
    "Discovery must hook subscribers in the bus's replacement upvalue table")
assert(request_slots["fixture.reset_request"] ~= reset_request_original)
bus.emit("fixture.reset_subscriber", payload)
assert(reset_delivered == 1 and bus.request("fixture.reset_request", payload) == payload)
active = profile.snapshot()
assert(find_named(active.rows, "fixture.reset_subscriber").calls == 1)
assert(find_named(active.rows, "fixture.reset_request").calls == 1)
assert(profile.stop("bus_reset"))
assert(subscriber_slots[reset_subscription.event_name][reset_subscription.token] == reset_original)
assert(request_slots["fixture.reset_request"] == reset_request_original)
assert(subscriber_slots["fixture.subscriber"] == nil and request_slots["fixture.request"] == nil,
    "Stopping a capture must not resurrect handlers removed by reset")
assert(old_subscriber_slots[subscription.event_name][subscription.token] == subscriber_original)
assert(old_request_slots["fixture.request"] == request_original)

-- High-volume native broadcasts count every invocation, while cost samples are
-- explicit. Selecting sample_every=1 permits a fully timed confirmation pass.
local native_broadcast_original = function(value)
    advance(2)
    return value, nil, "broadcast_tail", nil
end
modifier_tower_damage_observer = { OnAttack = native_broadcast_original }
assert(profile.run(15))
for i = 1, 32 do
    count, first, middle, tail, last = result_count(modifier_tower_damage_observer.OnAttack(i))
    assert(count == 4 and first == i and middle == nil and tail == "broadcast_tail" and last == nil)
end
active = profile.snapshot()
local broadcast_row = find_named(active.rows, "modifier_tower_damage_observer.OnAttack")
assert(broadcast_row.calls == 32 and broadcast_row.timed_calls == 1 and broadcast_row.sample_every == 32)
near(broadcast_row.total_ms, 2, "Sample sum must not masquerade as fully measured native duration")
assert(find_named(active.hook_status, "modifier_tower_damage_observer.OnAttack") == "observed_native_callback")
assert(profile.stop("sampled_native"))
assert(modifier_tower_damage_observer.OnAttack == native_broadcast_original)
assert(profile.run(15, { native_sample_every = 1 }))
for i = 1, 3 do modifier_tower_damage_observer.OnAttack(i) end
broadcast_row = find_named(profile.snapshot().rows, "modifier_tower_damage_observer.OnAttack")
assert(broadcast_row.calls == 3 and broadcast_row.timed_calls == 3 and broadcast_row.sample_every == 1)
near(broadcast_row.total_ms, 6)
assert(profile.stop("fully_timed_native"))

-- More than 512 real callbacks must be covered. Uncalled callbacks consume no
-- rows; repeated discovery must identify wrappers instead of wrapping them again.
bus.reset()
subscriber_slots=upvalue(emit_original,"subscribers")
request_slots=upvalue(bus_request_original,"request_handlers")
local extra_delivered = 0
local extra_originals={}
for i = 1, 1000 do
    local callback=function() extra_delivered=extra_delivered+1 end
    local token=bus.subscribe("fixture.bounded_"..i,callback)
    extra_originals[#extra_originals+1]={subscription=token,callback=callback}
end
assert(profile.run(15,{top=1}))
local installed=profile.snapshot()
assert(installed.hook_count>512 and installed.coverage.omitted_callbacks==0 and installed.row_count==0)
for pass=1,3 do
    advance(1100);assert(type(think())=="number")
    assert(profile.snapshot().hook_count==installed.hook_count,"Discovery cannot wrap the same callback again")
end
for i = 1, 180 do bus.emit("fixture.bounded_" .. i, {}) end
active = profile.snapshot()
local row_count = 0
for _ in pairs(active.rows) do row_count = row_count + 1 end
assert(extra_delivered==180 and row_count==181 and not active.rows['<other>'],"Only called sources allocate distinct bounded rows")
local slow_first_line=#lines+1
for i=1,30 do
    local index=i
    bus.subscribe('fixture.distinct_slow_'..i,function() advance(index==1 and 80 or 11) end)
end
advance(1100);assert(type(think())=='number')
for i=1,30 do bus.emit('fixture.distinct_slow_'..i,{}) end
assert(profile.stop("bounded_rows"))
local distinct_slow={}
for i=slow_first_line,#lines do
    if lines[i]:find('[EXTREME_SLOW_SOURCE]',1,true) then
        local source=lines[i]:match('fixture%.distinct_slow_(%d+)@')
        if source then distinct_slow[tonumber(source)]=true end
    end
end
for i=1,30 do assert(distinct_slow[i],"All observed >10ms event sources are reported independently of TOP1/twelve spikes") end
for _,entry in ipairs(extra_originals) do
    local token=entry.subscription
    assert(subscriber_slots[token.event_name][token.token]==entry.callback,"Every real wrapper is restored after large captures")
end

-- The fixed hook bound must explicitly disclose omissions without truncating
-- dispatch, growing the source cache, or claiming the missing callback was timed.
bus.reset()
subscriber_slots=upvalue(emit_original,"subscribers")
local overflow_originals={}
extra_delivered=0
for i=1,2200 do
    local callback=function() extra_delivered=extra_delivered+1 end
    overflow_originals[#overflow_originals+1]={subscription=bus.subscribe('fixture.overflow_'..i,callback),callback=callback}
end
assert(profile.run(15))
active=profile.snapshot()
assert(active.hook_count==2048 and active.coverage.omitted_callbacks>0 and #active.coverage.omitted_examples<=64)
assert(active.coverage.instrumented_callbacks+active.coverage.omitted_callbacks==2200)
for pass=1,2 do
    advance(1100);assert(type(think())=='number')
    assert(profile.snapshot().hook_count==2048,"Hook limit is stable across rediscovery")
end
local source_count=0
for _ in pairs(SURVIVAL_EXTREME_PERFORMANCE_CAPTURE.sources) do source_count=source_count+1 end
assert(source_count<=2048,"Omitted callbacks cannot grow an unbounded source cache")
for i=1,2200 do bus.emit('fixture.overflow_'..i,{}) end
assert(extra_delivered==2200 and profile.snapshot().row_count<=2048)
local overflow_output_start=#lines+1
assert(profile.stop('hook_limit'))
local overflow_output=table.concat(lines,'\n',overflow_output_start)
assert(overflow_output:find('omitted_slots_not_listed=',1,true) and overflow_output:find('omitted_callback name=',1,true),"Omissions are explicit with bounded source examples and unlisted-slot totals")
for _,entry in ipairs(overflow_originals) do
    local token=entry.subscription;assert(subscriber_slots[token.event_name][token.token]==entry.callback)
end
bus.reset()

-- Scan diagnostics preserve actual caller files and only primitive class/radius
-- inputs; entity userdata is never inspected, stringified, or retained.
local scan_radius_original=function() advance(2);return {1,2},nil,'radius_tail',nil end
local scan_entities_original=function() advance(3);return {1,2,3},nil,'class_tail',nil end
FindUnitsInRadius=scan_radius_original
Entities.FindAllByClassname=scan_entities_original
FIND_UNITS_EVERYWHERE=-1
local opaque=newproxy(true)
getmetatable(opaque).__index=function() error('Profiler cannot inspect entity userdata fields') end
getmetatable(opaque).__tostring=function() error('Profiler cannot stringify entity userdata') end
local scan_caller=assert(loadstring([[return function(entity,radius,classname)
    local nearby=FindUnitsInRadius(2,entity,entity,radius)
    local classes=Entities:FindAllByClassname(classname)
    return nearby,classes
end]],'@fixture_actual_scan_caller.lua'))()
assert(profile.run(15,{top=1}))
scan_caller(opaque,600,'npc_dota_creature');scan_caller(opaque,600,'npc_dota_creature')
scan_caller(opaque,5000,'npc_dota_building');scan_caller(opaque,FIND_UNITS_EVERYWHERE,'npc_dota_creature')
active=profile.snapshot()
local radius_scan,class_scan=active.scans.FindUnitsInRadius,active.scans['Entities.FindAllByClassname']
assert(radius_scan.calls==4 and radius_scan.row_count==3 and radius_scan.large_radius_calls==2 and radius_scan.everywhere_calls==1)
assert(class_scan.calls==4 and class_scan.row_count==2)
local ordinary,global_scan
for _,row in ipairs(radius_scan.rows) do
    assert(row.caller:find('fixture_actual_scan_caller.lua:',1,true) and not row.caller:find('manual_extreme_profile',1,true),'Scan caller belongs to business code, not the instrumenter')
    if row.radius==600 then ordinary=row end
    if row.everywhere then global_scan=row end
end
assert(ordinary.calls==2 and ordinary.result_units==4 and global_scan.large_radius and global_scan.result_units==2)
near(ordinary.total_ms,4)
for i=1,70 do scan_caller(opaque,6000+i,'fixture_class_'..i) end
active=profile.snapshot();radius_scan=active.scans.FindUnitsInRadius;class_scan=active.scans['Entities.FindAllByClassname']
assert(radius_scan.row_count==64 and class_scan.row_count==64 and radius_scan.omitted.calls>0 and class_scan.omitted.calls>0)
assert(radius_scan.omitted.large_radius_calls==radius_scan.omitted.calls,'Omitted large scans remain explicitly counted')
local scan_output_start=#lines+1
assert(profile.stop('scan_sources'))
local radius_lines,class_lines=0,0
for i=scan_output_start,#lines do
    if lines[i]:find('scan_source api=FindUnitsInRadius',1,true) then radius_lines=radius_lines+1 end
    if lines[i]:find('scan_source api=Entities.FindAllByClassname',1,true) then class_lines=class_lines+1 end
end
assert(radius_lines==64 and class_lines==64,'All retained scan sources print independently of TOP1')
assert(FindUnitsInRadius==scan_radius_original and Entities.FindAllByClassname==scan_entities_original)
local debug_original,disabled_debug_reads=debug.getinfo,0
debug.getinfo=function(...) disabled_debug_reads=disabled_debug_reads+1;return debug_original(...) end
scan_caller(opaque,7000,'disabled')
assert(disabled_debug_reads==0,'Stopped scans perform no debug caller reads')
debug.getinfo=debug_original
FindUnitsInRadius=radius_original;Entities.FindAllByClassname=entities_original

-- Short native API probes retain primitive resource/CP names and real callers,
-- never entity userdata, and preserve native return tuples and thrown objects.
local create_original=function(_,particle)
    advance(27)
    if particle=='fail.vpcf' then error(failure,0) end
    return 123,nil,'particle_tail',nil
end
local control_original=function() advance(3.5) end
local apply_original=function() advance(11);return 999,nil,'damage_tail',nil end
local sound_original=function() advance(2) end
ParticleManager={CreateParticle=create_original,SetParticleControl=control_original}
ApplyDamage=apply_original;EmitSoundOn=sound_original
CBaseEntity=setmetatable({}, {__index={EmitSound=sound_original},__newindex=function() error('native read-only') end})
local adapter_call=assert(loadstring([[return function(entity,particle)
    local id=ParticleManager:CreateParticle(particle,1,entity)
    ParticleManager:SetParticleControl(id,0,entity)
    return id
end]],'@fixture_native_adapter.lua'))()
local feature_call=assert(loadstring([[return function(adapter,entity)
    local id=adapter(entity,'particles/fixture/lightning.vpcf')
    local damage=ApplyDamage(entity)
    EmitSoundOn('Fixture.Lightning',entity)
    return id,damage
end]],'@fixture_native_feature.lua'))()
local untouched_create=ParticleManager.CreateParticle
assert(profile.run(15,{native_api=false}))
assert(ParticleManager.CreateParticle==untouched_create and ApplyDamage==apply_original,'Native API detail is explicitly suppressible')
assert(profile.stop('native_disabled'))
assert(profile.run(15,{top=1}))
assert(ParticleManager.CreateParticle~=create_original and ApplyDamage~=apply_original)
local id,damage=feature_call(adapter_call,opaque)
assert(id==123 and damage==999)
count,first,middle,tail,last=result_count(ParticleManager:CreateParticle('tuple.vpcf',1,opaque))
assert(count==4 and first==123 and middle==nil and tail=='particle_tail' and last==nil)
local native_ok,native_error=pcall(ParticleManager.CreateParticle,ParticleManager,'fail.vpcf',1,opaque)
assert(not native_ok and native_error==failure,'Native thrown object identity must survive profiling')
active=profile.snapshot()
local native_particles=active.native_apis['ParticleManager.CreateParticle']
assert(native_particles.calls==3 and #native_particles.rows==3)
local created_row
for _,row in ipairs(native_particles.rows) do
    if row.parameter:find('fixture/lightning.vpcf',1,true) then created_row=row end
end
assert(created_row and created_row.caller:find('fixture_native_adapter.lua:',1,true))
assert(created_row.origin:find('fixture_native_feature.lua:',1,true),'Native adapter and outer feature call sites are separate')
near(created_row.total_ms,27);near(created_row.max_ms,27)
near(active.rows['ApplyDamage'].total_ms,11)
near(active.rows['EmitSoundOn'].total_ms,2)
near(active.rows['ParticleManager.SetParticleControl'].total_ms,3.5)
assert(active.hook_status['CBaseEntity.EmitSound']=='unwritable','Read-only native methods are diagnosed without altering them')
assert(active.hook_status['ParticleManager.CreateParticle']=='observed_native_api')
assert(active.native_apis['ParticleManager.SetParticleControl'].rows[1].parameter=='0')
assert(active.native_apis.EmitSoundOn.rows[1].parameter=='"Fixture.Lightning"')
for i=1,70 do ParticleManager:CreateParticle('bounded_'..i..'.vpcf',1,opaque) end
native_particles=profile.snapshot().native_apis['ParticleManager.CreateParticle']
assert(#native_particles.rows==64 and native_particles.omitted.calls>0,'Per-API resource/caller attribution has a fixed bound')
local native_output_start=#lines+1
assert(profile.stop('native_api_sources'))
local native_output=table.concat(lines,'\n',native_output_start)
assert(native_output:find('native_api_source name=ParticleManager.CreateParticle',1,true),'Native API sources are printed independently of TOP1')
assert(native_output:find('fixture_native_feature.lua:',1,true))
assert(ParticleManager.CreateParticle==create_original and ParticleManager.SetParticleControl==control_original)
assert(ApplyDamage==apply_original and EmitSoundOn==sound_original and CBaseEntity.EmitSound==sound_original)
ParticleManager,ApplyDamage,EmitSoundOn,CBaseEntity=nil,nil,nil,nil

assert(profile.run(90) and profile.snapshot().duration==90)
advance(89000)
assert(type(think())=='number' and profile.snapshot().active, 'Long captures do not stop at the former 30s ceiling')
advance(1100)
assert(think()==nil and not profile.snapshot().active, '90s wall deadline restores all hooks')
assert(profile.run(0/0) and profile.snapshot().duration==20)
assert(profile.stop('invalid_duration_default'))

-- Shared death routing has distinct native ingress/real handler counters.
-- Merely installing the cached per-enemy callback cannot claim it was observed.
local saved_enemy_ai,saved_enemy_observer=modifier_enemy_wall_ai,modifier_enemy_attack_observer
local death_event={unit={}}
local death_handler_original=function(self,event) advance(.2);return self,nil,event,nil end
local death_callback_original=function() error('shared enemies must not broadcast local death') end
modifier_enemy_wall_ai={HandleDeath=death_handler_original,OnDeath=death_callback_original}
local death_ingress_original=function(self,event) return modifier_enemy_wall_ai.HandleDeath(self,event) end
modifier_enemy_attack_observer={OnDeath=death_ingress_original}
assert(profile.run(15,{top=1}))
for i=1,244 do
    count,first,middle,tail,last=result_count(modifier_enemy_attack_observer.OnDeath(owner,death_event))
    assert(count==4 and first==owner and middle==nil and tail==death_event and last==nil)
end
active=profile.snapshot()
assert(active.rows['modifier_enemy_attack_observer.OnDeath'].calls==244)
assert(active.rows['modifier_enemy_wall_ai.HandleDeath'].calls==244)
assert(active.rows['modifier_enemy_wall_ai.OnDeath']==nil)
assert(active.hook_status['modifier_enemy_attack_observer.OnDeath']=='observed_native_callback')
assert(active.hook_status['modifier_enemy_wall_ai.HandleDeath']=='observed_native_callback')
assert(active.hook_status['modifier_enemy_wall_ai.OnDeath']=='unconfirmed_native_hook')
assert(profile.stop('shared_enemy_death'))
assert(modifier_enemy_wall_ai.HandleDeath==death_handler_original and modifier_enemy_wall_ai.OnDeath==death_callback_original)
assert(modifier_enemy_attack_observer.OnDeath==death_ingress_original)
modifier_enemy_wall_ai,modifier_enemy_attack_observer=saved_enemy_ai,saved_enemy_observer

-- CPU fallback can measure callback cost but cannot report wall-frame gaps.
GetSystemTimeMS = nil
assert(profile.run(15))
assert(profile.snapshot().frames.wall_available == false)
advance(6)
assert(type(think()) == "number")
advance(16000)
assert(think() == nil and not profile.snapshot().active, "Duration expiry restores hooks without an extra request")
assert(FindUnitsInRadius == radius_original and bus.emit == emit_original)
local output = table.concat(lines, "\n")
assert(output:find("os.clock", 1, true) or output:find("os_clock", 1, true),
    "CPU fallback must identify its clock in captured output")

print, os.clock, os.time, collectgarbage = original_print, original_clock, original_time, original_gc
print("EXTREME_PROFILE_CAPTURE_PASS: opt-in gates, real/dynamic/reset callbacks, exact returns/errors, native sampling, 2048 hook bound, lazy rows, stable discovery, all slow sources, bounded caller/class/radius attribution, explicit omissions, frame gaps, heap samples and restoration")
