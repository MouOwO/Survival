-- Run from addon root: lua5.1.exe <this test> <candidate module path>
package.path = "scripts/vscripts/?.lua;" .. package.path
local path = arg[1] or "scripts/vscripts/tests/manual_native_damage_filter_profile.lua"
local wall, clock_reads, setter_calls, original_calls = 1000, 0, 0, 0
local tools_mode, server_mode, clock_fail = false, true, false
local repository_action, setter_error, watchdog_error, restore_error
local exact_error = { kind = "exact original error" }
local modes, entities = {}, {}
local current
IsInToolsMode = function() return tools_mode end
IsServer = function() return server_mode end
GetSystemTimeMS = function()
    clock_reads = clock_reads + 1
    if clock_fail then clock_fail = false; error("clock failure") end
    return wall
end
GameRules = { GetGameModeEntity = function() return current end }
DAMAGE_TYPE_PHYSICAL, DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 1, 16384
local function mode()
    local value = { timers = {} }
    function value:SetDamageFilter(fn, context)
        setter_calls = setter_calls + 1
        self.binding, self.context = fn, context
        if setter_error then setter_error = false; error("partial install failure") end
        if restore_error and fn == self.private then error("restore failure") end
    end
    function value:SetContextThink(name, fn, delay)
        self.timers[name] = fn
        if watchdog_error and fn then watchdog_error = false; error("partial watchdog failure") end
    end
    modes[#modes + 1] = value
    return value
end
local function unit(index)
    local value = { index = index }
    function value:IsNull() return false end
    function value:entindex() return self.index end
    function value:IsInvulnerable() wall = wall + 0.2; return self.invulnerable == true end
    function value:HasModifier() wall = wall + 0.4; return false end
    function value:IsRealHero() wall = wall + 0.2; return false end
    function value:GetHealth() wall = wall + 0.1; return 200 end
    function value:GetUnitName() return "mock_unit" end
    entities[index] = value
    return value
end
local attacker, victim = unit(1), unit(2)
attacker.survival_player_id = 0
attacker.survival_gameplay_damage_bonus_flat = 5
attacker.survival_research_final_damage_pct = 20
victim.survival_gameplay_damage_reduction_pct = 25
EntIndexToHScript = function(index) wall = wall + 0.1; return entities[index] end
local trees = {
    is_tree = function(value) return value.tree == true end,
    is_allowed_tree_attacker = function() return true end,
    is_basic_attack_category = function(value) return tonumber(value) == 1 end,
    consume_basic_attack = function() return true end,
    allows_damage = function() return true end,
    reset_pending_attacks = function() end,
}
package.loaded["systems/tree_damage_rules"] = trees
package.loaded["systems/anti_air_rules"] = {
    can_attack = function() return true end, has_damage_taken_aura = function() return false end,
}
package.loaded["config/generated/global_rules"] = { by_id = {} }
package.loaded["config/armor_balance"] = { CUSTOM_WAR3_MAPPING_VERSION = 3 }
package.loaded["systems/rogue_effect_state_service"] = {
    has_effect = function() return false end, numeric = function() return 0 end,
}
local emitted = {}
local repository = { consume_pending = function(a, v)
    original_calls = original_calls + 1
    wall = wall + 1
    if repository_action then return repository_action(a, v) end
    return nil
end }
local function service()
    package.loaded["combat/damage_filter_service"] = nil
    local result = require("combat/damage_filter_service")
    result.init({ event_bus = { emit = function(event, payload)
        emitted[#emitted + 1] = { event, payload }
    end }, events = { DAMAGE_BLOCKED = "blocked", DAMAGE_FILTERED = "filtered", DAMAGE_RESOLVED = "resolved" },
        repository = repository, config = { global_post_bonus_pct = 0.1, minimum_post_multiplier = 0,
        boss_rules = { enabled = true, default_damage_taken_multiplier = 2 } } })
    assert(result.register())
    current.private = result._filter_for_test
    assert(current.binding == result._filter_for_test and current.context == result)
    return result
end
local function keys()
    return { entindex_attacker_const = 1, entindex_victim_const = 2, damage = 100,
        damagetype_const = 2, damage_category_const = 1 }
end
local function invoke(fn, owner, k) return fn(owner, k or keys()) end
local function close(a, b) assert(math.abs(a - b) < 0.000001, tostring(a) .. " vs " .. tostring(b)) end
local function start(profile, options)
    options = options or { owned_binding = true, expected_mode = current }
    local ok, why = profile.start(8, options)
    assert(ok, tostring(why))
    return current.binding
end
local function tick()
    local fn = assert(current.timers.SurvivalNativeDamageFilterProfile)
    return fn()
end
current = mode()
local filter = service()
local profile = assert(loadfile(path))()
local initial_reads, initial_setters = clock_reads, setter_calls
assert(not profile.start(8, { owned_binding = true }))
assert(clock_reads == initial_reads and setter_calls == initial_setters and not next(current.timers))
tools_mode = true
assert(not profile.start(8))
server_mode = false
assert(not profile.start(8, { owned_binding = true }))
server_mode = true
assert(not profile.start(8, { owned_binding = true, expected_mode = {} }))
assert(not profile.start(8, { owned_binding = true, expected_service = {} }))
local expected_keys = keys()
assert(invoke(filter._filter_for_test, filter, expected_keys))
local wrapper = start(profile)
assert(filter._filter_for_test == current.private)
assert(not profile.start(8, { owned_binding = true }))
local measured_keys = keys()
assert(invoke(wrapper, filter, measured_keys))
close(measured_keys.damage, expected_keys.damage)
close(measured_keys.damage, 102.375)
local stats = profile.snapshot()
assert(stats.calls == 1 and stats.measured_calls == 1 and stats.positive_duration_calls == 1
    and stats.observed and stats.timing_valid and stats.inclusive_ms > 0)
assert(stats.private_filter_verified and not stats.native_binding_readback_available)
victim.invulnerable = true
assert(not invoke(wrapper, filter))
victim.invulnerable = false
repository_action = function() return { blocked = "contract" } end
assert(not invoke(wrapper, filter))
repository_action = nil
local report = profile.stop("test")
assert(report.calls == 3 and report.restored and current.binding == current.private
    and current.context == filter and current.SetDamageFilter ~= rawget(_G, "SURVIVAL_NATIVE_DAMAGE_FILTER_PROFILE"))
assert(not next(current.timers) and not rawget(_G, "SURVIVAL_NATIVE_DAMAGE_FILTER_PROFILE"))
local inactive_reads = clock_reads
for _ = 1, 500 do assert(invoke(wrapper, filter)) end
assert(clock_reads == inactive_reads, "Cached retired native wrapper must not read the clock")

-- Many captures, cached old native callbacks, and module reload cannot stack timers.
local cached = { wrapper }
for _ = 1, 30 do
    local before = current.SetDamageFilter
    cached[#cached + 1] = start(profile)
    invoke(current.binding, filter)
    profile = assert(loadfile(path))()
    assert(profile.stop("reload").restored)
    assert(current.binding == current.private and current.SetDamageFilter == before)
end
inactive_reads = clock_reads
for _, old in ipairs(cached) do for _ = 1, 10 do invoke(old, filter) end end
assert(clock_reads == inactive_reads)
wrapper = start(profile)
inactive_reads = clock_reads
invoke(cached[1], filter)
assert(clock_reads == inactive_reads and profile.snapshot().calls == 0)
wall = wall + 8000
assert(tick() == nil)
assert(profile.snapshot().reason == "deadline" and profile.snapshot().restored
    and current.binding == current.private)
inactive_reads = clock_reads
invoke(wrapper, filter)
assert(clock_reads == inactive_reads)

-- Setter ownership: foreign filter/foreign method and a new mode are never overwritten.
wrapper = start(profile)
local foreign_context = {}
local foreign = function() return false end
current:SetDamageFilter(foreign, foreign_context)
assert(not rawget(_G, "SURVIVAL_NATIVE_DAMAGE_FILTER_PROFILE")
    and current.binding == foreign and current.context == foreign_context
    and profile.snapshot().restore_skipped == "external_filter_replaced")
profile.stop()
assert(current.binding == foreign)
current:SetDamageFilter(current.private, filter)
wrapper = start(profile)
local saved_setter = rawget(_G, "SURVIVAL_NATIVE_DAMAGE_FILTER_PROFILE").original_setter
local foreign_setter = function() end
current.SetDamageFilter = foreign_setter
profile.stop()
assert(current.SetDamageFilter == foreign_setter and profile.snapshot().restore_skipped == "setter_replaced")
current.SetDamageFilter = saved_setter
current:SetDamageFilter(current.private, filter)
wrapper = start(profile)
local previous_mode = current
current = mode()
current:SetDamageFilter(foreign, foreign_context)
local old_calls = original_calls
assert(invoke(wrapper, filter))
assert(original_calls == old_calls + 1 and current.binding == foreign
    and profile.snapshot().restore_skipped == "game_mode_changed")
current = previous_mode
current:SetDamageFilter(current.private, filter)

-- Installation errors and partial writes always retire and roll back the actual closure.
setter_error = true
assert(not profile.start(8, { owned_binding = true }))
assert(current.binding == current.private and profile.snapshot().restored and not next(current.timers))
watchdog_error = true
assert(not profile.start(8, { owned_binding = true }))
assert(current.binding == current.private and profile.snapshot().restored and not next(current.timers))
wrapper = start(profile)
repository_action = function() error(exact_error, 0) end
old_calls = original_calls
local ok, err = pcall(invoke, wrapper, filter)
repository_action = nil
assert(not ok and err == exact_error and original_calls == old_calls + 1)
assert(current.binding == current.private and profile.snapshot().errors == 1 and profile.snapshot().restored)
wrapper = start(profile)
restore_error = true
profile.stop()
restore_error = nil
assert(profile.snapshot().restore_error and not profile.snapshot().restored)
inactive_reads = clock_reads
invoke(wrapper, filter)
assert(clock_reads == inactive_reads)
current:SetDamageFilter(current.private, filter)

-- Clock failures preserve exact gameplay semantics and never call original twice.
wrapper = start(profile)
clock_fail = true
old_calls = original_calls
local clock_keys = keys()
assert(invoke(wrapper, filter, clock_keys))
assert(original_calls == old_calls + 1 and current.binding == current.private
    and not profile.snapshot().timing_valid)
close(clock_keys.damage, expected_keys.damage)
wrapper = start(profile)
repository_action = function() clock_fail = true; return nil end
old_calls = original_calls
assert(invoke(wrapper, filter))
repository_action = nil
assert(original_calls == old_calls + 1 and current.binding == current.private
    and not profile.snapshot().timing_valid)

-- Reentry is counted as inclusive (not additive self), with safe stop inside original.
wrapper = start(profile)
local entered = false
repository_action = function()
    if not entered then entered = true; invoke(wrapper, filter) end
    return nil
end
assert(invoke(wrapper, filter))
repository_action = nil
assert(profile.snapshot().calls == 2 and profile.snapshot().nested_calls == 1)
profile.stop()
wrapper = start(profile)
repository_action = function() profile.stop("inside_original"); return nil end
assert(invoke(wrapper, filter))
repository_action = nil
assert(profile.snapshot().calls == 1 and profile.snapshot().measured_calls == 1 and profile.snapshot().restored)

-- Fail closed on stale export/registration, known boss/other capture ownership.
local original_export = filter._filter_for_test
filter._filter_for_test = function() end
assert(not profile.start(8, { owned_binding = true }))
filter._filter_for_test = original_export
package.loaded["tests/manual_boss_performance"] = {}
assert(not profile.start(8, { owned_binding = true }))
package.loaded["tests/manual_boss_performance"] = nil
rawset(_G, "SURVIVAL_EXTREME_PERFORMANCE_CAPTURE", {})
assert(not profile.start(8, { owned_binding = true }))
rawset(_G, "SURVIVAL_EXTREME_PERFORMANCE_CAPTURE", nil)
filter.init({})
assert(not profile.start(8, { owned_binding = true }))
filter = service()

-- A native userdata-like setter that cannot be written must never be taken over.
local actual_mode = current
local opaque = setmetatable({}, { __index = actual_mode, __newindex = function() error("read-only userdata") end })
current = opaque
initial_setters = setter_calls
assert(not profile.start(8, { owned_binding = true }))
assert(setter_calls == initial_setters and not rawget(_G, "SURVIVAL_NATIVE_DAMAGE_FILTER_PROFILE"))
current = actual_mode

-- Preserve arbitrary tuple arity and exact context through the wrapper as well.
local actual_service = filter
local synthetic = {}
local registered = true
local filter = function(owner, value, ...) assert(owner == synthetic and value == 7); return 1, nil, "tail", nil end
synthetic._filter_for_test = filter
synthetic.register = function() if registered then return true end; return filter end
package.loaded["combat/damage_filter_service"] = synthetic
current:SetDamageFilter(filter, synthetic)
current.private = filter
wrapper = start(profile)
local function pack(...) return { n = select("#", ...), ... } end
local tuple = pack(wrapper(synthetic, 7, nil, "input"))
assert(tuple.n == 4 and tuple[1] == 1 and tuple[2] == nil and tuple[3] == "tail" and tuple[4] == nil)
assert(profile.snapshot().zero_duration_calls == 1 and profile.snapshot().positive_duration_calls == 0)
profile.stop()
assert(current.binding == filter and current.context == synthetic)
package.loaded["combat/damage_filter_service"] = actual_service
print("native damage filter profile: PASS (actual private filter, 30 reload rounds, cached callbacks, replacement, rollback, clock/error/reentry, exact tuples)")
