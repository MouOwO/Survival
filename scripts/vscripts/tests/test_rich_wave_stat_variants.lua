-- Real formal/debug spawn loops, real N2/N3 profiles and existing engine doubles.
local file = assert(io.open("scripts/vscripts/tests/test_wave_population_endgame.lua", "rb"))
local fixture = file:read("*a"); file:close()
local boundary = assert(fixture:find("-- The real rules admit", 1, true))
local cases = [=[
IsInToolsMode = function() return true end
package.loaded["systems/player_context_service"].max_players = function() return 4 end
package.loaded["config/asset_catalog"].for_model = function(path) return {asset_id = "fixture:" .. path} end
local preload = package.loaded["systems/asset_preload_service"]
preload.STATE = {READY = "ready", FAILED = "failed", RETIRED = "retired"}
preload.queue = function() return true end
preload.status = function() return {status = preload.STATE.READY} end
package.loaded["systems/monster_visual_service"].queue_wave = noop
package.loaded["systems/rich_region_service"] = {wave_spawn = function(id) return Vector(id * 2000, 100, 32) end}
local find_marker = Entities.FindByName
Entities.FindByName = function(self, previous, name)
    if name == "rich_start" then return marker(0) end
    return find_marker(self, previous, name)
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local recorded = require("config/generated/rich_wave_stat_variants")
local source = require("config/generated/wave_definitions").rows
local original_recorded, original_source = copy(recorded), copy(source)
local variant_rows = require("systems/rich_stat_variant_row")
local plain = {health = 10, attack = 2, war3_armor = 3, member_role = "normal"}
assert(variant_rows.resolve(plain) == plain and plain.rich_variant_index == nil,
    "ordinary rows must retain their identity and gain no variant metadata")
local built = assert(require("systems/wave_difficulty_builder").build(nil, "N2", "rich"))
local variants
for _, row in ipairs(built.waves[6]) do
    if row.batch_id == "6N1" then variants = row.rich_stat_variants end
end
local input = {health = 10, attack = 2, war3_armor = 3, member_role = "normal",
    rich_stat_variants = copy(assert(variants))}
local before_input = copy(input)
local selected = variant_rows.resolve(input, 2)
assert(selected.health == 32000 and selected.attack == 3522 and selected.war3_armor == 75)
assert(selected.rich_variant_index == 2 and selected.rich_variant_count == 2
    and equal(selected.rich_field_sources, input.rich_stat_variants[2].field_sources))
selected.rich_field_sources.health.method = "caller_mutation"
selected.rich_stat_variants[1].field_sources.health.method = "caller_mutation"
assert(equal(input, before_input), "resolved variant rows and nested provenance must not mutate input")

local create = CreateUnitByName
CreateUnitByName = function(name, position, ...)
    local value = create(name, position, ...)
    value.applied = {}
    function value:GetUnitName() return self.name end
    for method, key in pairs({SetBaseMaxHealth = "base_health", SetMaxHealth = "max_health",
        SetHealth = "health", SetBaseDamageMin = "attack_min", SetBaseDamageMax = "attack_max",
        SetPhysicalArmorBaseValue = "native_armor", SetModel = "model", SetOriginalModel = "original_model",
        SetModelScale = "model_scale", SetBaseAttackTime = "bat"}) do
        local field = key
        value[method] = function(self, argument) self.applied[field] = argument end
    end
    return value
end
local callback_delays = {}
local after = package.loaded["core/scheduler"].after
package.loaded["core/scheduler"].after = function(delay, callback, key)
    callback_delays[callback] = delay
    return after(delay, callback, key)
end
local function captured(callback, wanted)
    for index = 1, math.huge do
        local name, value = debug.getupvalue(callback, index)
        if not name then break end
        if name == wanted then return value end
    end
end
local function collect_callbacks()
    local result = {}
    for id, callback in pairs(scheduled) do
        if type(id) == "number" then
            result[#result + 1] = {id = id, callback = callback,
                row = captured(callback, "row"), channel = captured(callback, "channel"),
                delay = callback_delays[callback]}
            scheduled[id] = nil
        end
    end
    -- Native timers need not complete in insertion order. Distribution is
    -- decided by the scheduling slot, never a global callback-time counter.
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end
local verified = 0
local archetypes = require("config/generated/monster_archetypes").by_id
local fixtures = {N2 = {health = 32000, attack = 3522, armor = {50, 75}},
    N3 = {health = 72000, attack = 7922, armor = {70, 105}}}
local function run(difficulty, mode, path, multiple_batches)
    local state = restart(difficulty, true, {0, 1}, mode)
    prepare_lanes()
    local wave_row = assert(upvalue("waves")[6])
    if multiple_batches then
        local ordinary
        for _, row in ipairs(wave_row.batches) do if row.member_role == "normal" then ordinary = row end end
        local first, second = copy(ordinary), copy(ordinary)
        first.monster_count, second.monster_count = 3, 3
        second.batch_id = "independent_test_batch"
        for index, variant in ipairs(second.rich_stat_variants) do
            variant.war3_armor = fixtures[difficulty].armor[index] + 100
        end
        wave_row.batches = {first, second}
    end
    local original_batches, templates = copy(wave_row.batches), {}
    local expected_per_owner = 0
    for _, row in ipairs(wave_row.batches) do
        templates[row.batch_id] = row
        expected_per_owner = expected_per_owner + row.monster_count
        if mode ~= "rich" then assert(row.rich_stat_variants == nil, "another mode gained rich variants") end
    end
    callback_delays = {}
    if path == "formal" then
        state.current_wave = 5
        bus.emit(events.WAVE_START_NEXT, {})
        assert(state.current_wave == 6 and state.status == "countdown")
    else
        assert(wave.debug_spawn_wave_for_players(6, {0, 1}))
        clock = 100
        assert(scheduled.dev_wave_preload)()
        scheduled.dev_wave_preload = nil
        assert(state.current_wave == 6 and state.status == "dev_spawn")
    end
    local callbacks = collect_callbacks()
    local counts, slots = {[0] = {}, [1] = {}}, {}
    for _, task in ipairs(callbacks) do
        local before = #created
        task.callback()
        assert(task.row and task.channel and #created == before + 1,
            "each real scheduling slot must complete precisely one birth")
        local value, row = created[#created], task.row
        local template = assert(templates[row.batch_id])
        local owner = task.channel.player_id
        assert(value.survival_player_id == owner and value.survival_is_wave_monster
            and value.survival_monster_role == row.member_role)
        local actual = value.applied
        assert(actual.base_health == row.health and actual.health == row.health and actual.max_health == row.health
            and actual.attack_min == row.attack and actual.attack_max == row.attack
            and actual.native_armor == 0 and value.survival_base_war3_armor == row.war3_armor,
            "resolved attributes must reach the real production setters/custom armor")
        local definition = archetypes[row.archetype_id]
        assert(actual.model == definition.model_path and actual.original_model == actual.model
            and actual.model_scale == definition.model_scale * (row.model_scale_multiplier or 1)
            and actual.bat == 1 / row.attack_speed, "stat variants changed model, scale or attack speed")
        for _, field in ipairs({"archetype_id", "member_role", "movement_type_override", "model_scale_multiplier",
            "attack_speed", "spawn_interval", "spawn_order", "monster_count", "is_boss"}) do
            assert(row[field] == template[field], "stat variant changed " .. field)
        end
        local key = row.batch_id .. ":" .. tostring(row.rich_variant_index or 0)
        counts[owner][key] = (counts[owner][key] or 0) + 1
        if mode == "rich" and row.member_role == "normal" then
            local index = assert(row.rich_variant_index)
            assert(row.rich_variant_count == 2 and index >= 1 and index <= 2)
            local observed = fixtures[difficulty]
            local offset = row.batch_id == "independent_test_batch" and 100 or 0
            assert(row.health == observed.health and row.attack == observed.attack
                and row.war3_armor == observed.armor[index] + offset,
                "actual born W6 groups must match independent video panel fixtures")
            assert(equal(row.rich_field_sources, template.rich_stat_variants[index].field_sources),
                "chosen variant lost its complete field provenance")
            local slot = row.batch_id .. ":" .. tostring(task.delay)
            slots[slot] = slots[slot] or {}
            slots[slot][owner] = index
        else
            assert(row.rich_variant_index == nil and row.rich_variant_count == nil
                and row.health == template.health and row.attack == template.attack
                and row.war3_armor == template.war3_armor,
                "ordinary modes and rich leaders must keep their original row stats")
        end
    end
    assert(#created == expected_per_owner * 2 and state.planned == #created
        and state.spawned == #created and state.failed_spawn == 0 and state.pending == 0)
    assert(equal(counts[0], counts[1]), "both owners must receive identical per-batch variant distribution")
    for _, owners in pairs(slots) do assert(owners[0] == owners[1], "same slot changed variant across owners") end
    if mode == "rich" then
        local first, second = multiple_batches and 2 or 30, multiple_batches and 1 or 29
        assert(counts[0]["6N1:1"] == first and counts[0]["6N1:2"] == second,
            "W6 normal count must split deterministically without adding units")
        if multiple_batches then
            assert(counts[0]["independent_test_batch:1"] == 2 and counts[0]["independent_test_batch:2"] == 1,
                "interleaved batches must each advance their own ordinal, not a global visual index")
        else assert(expected_per_owner == 60, "the original leader remains included in the 60 budget") end
    end
    assert(equal(wave_row.batches, original_batches), "actual spawn loops mutated their source batches")
    assert(equal(recorded, original_recorded) and equal(source, original_source))
    verified = verified + #created
end
for _, difficulty in ipairs({"N2", "N3"}) do
    for _, path in ipairs({"formal", "debug"}) do
        run(difficulty, "rich", path)
        run(difficulty, "standard", path)
    end
end
run("N2", "pure", "formal")
run("N2", "rich", "formal", true)
run("N2", "rich", "debug", true)
restart(false, true, {0, 1}, "fishing")
local ok, reason = wave.debug_spawn_wave_for_players(6, {0, 1})
assert(not ok and reason == "fishing_mode_no_waves" and #created == 0,
    "variant support must retain fishing's no-wave contract")
print("RICH_WAVE_STAT_VARIANTS_PASS: " .. verified .. " real births, N2/N3 observed W6 variants, formal/debug two-owner slots, 30/29 split, independent batch ordinals, reversed callbacks and other-mode isolation")
]=]
assert(loadstring(fixture:sub(1, boundary - 1) .. cases, "test_rich_wave_stat_variants"))()
