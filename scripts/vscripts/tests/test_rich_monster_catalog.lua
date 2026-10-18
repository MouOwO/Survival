-- Independent CSV data through the real builders and profile resolver.
package.path = "scripts/vscripts/?.lua;" .. package.path
for _, name in ipairs({"config/generated/rich_wave_profiles", "config/generated/rich_monster_profiles"}) do
    package.preload[name] = function() error("legacy JSON module reached at runtime: " .. name) end
end
local rich_waves = require("config/generated/rich_wave_definitions")
local rich_variants = require("config/generated/rich_wave_stat_variants")
local rich_profiles = require("config/generated/rich_challenge_combat_profiles")
local source = require("config/generated/wave_definitions").rows
local ordinary_profiles = require("config/generated/challenge_combat_profiles")
local builder = require("systems/wave_difficulty_builder")
local encounters = require("config/challenge_combat_profile_config")

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
local function normalized(row)
    local result = {}
    for key, value in pairs(row) do if value ~= "" then result[key] = copy(value) end end
    return result
end
local function build(difficulty, mode) return assert(builder.build(source, difficulty, mode)) end
local original_waves, original_variants = copy(rich_waves), copy(rich_variants)
local original_profiles, original_source = copy(rich_profiles), copy(source)
local original_ordinary = copy(ordinary_profiles)
local wave_index, profile_index, variant_index = {}, {}, {}
for _, row in ipairs(rich_waves.rows) do
    if row.enabled ~= false then
        wave_index[row.difficulty_id] = wave_index[row.difficulty_id] or {}
        wave_index[row.difficulty_id][row.wave_id] = row
    end
end
for _, row in ipairs(rich_profiles.rows) do
    if row.enabled ~= false then
        profile_index[row.difficulty_id] = profile_index[row.difficulty_id] or {}
        profile_index[row.difficulty_id][row.member_id] = row
    end
end
for _, row in ipairs(rich_variants.rows) do
    if row.enabled ~= false then
        local key = row.difficulty_id .. ":" .. row.wave_number .. ":" .. row.batch_id
        variant_index[key] = variant_index[key] or {}
        variant_index[key][row.variant_index] = row
    end
end
local variant_fields = {"health", "attack", "war3_armor", "estimated", "stats_source",
    "source_record_id", "estimation_method", "field_sources"}
local preserved = {"wave_id", "difficulty_id", "wave_number", "batch_id", "archetype_id",
    "member_role", "is_boss", "boss_warning", "enabled", "attack_speed", "spawn_interval",
    "spawn_order", "movement_type_override", "model_scale_multiplier"}
local waves_verified, encounters_verified = 0, 0
for number = 1, 10 do
    local difficulty = "N" .. number
    local standard = copy(build(difficulty, "standard"))
    local expected_waves = assert(wave_index[difficulty])
    for _, mode in ipairs({"rich", "standard", "rich", "pure", "fishing", "rich", "standard"}) do
        local result = build(difficulty, mode)
        if mode ~= "rich" then
            assert(equal(result, standard), difficulty .. "/" .. mode .. " inherited rich values or metadata")
        else
            assert(result.total_waves == (number == 1 and 25 or 30))
            local flattened = {}
            for _, row in ipairs(result.rows) do
                assert(not flattened[row.wave_id], "duplicate flattened wave row")
                flattened[row.wave_id] = row
            end
            for wave_number = 1, result.total_waves do
                local before, after = standard.waves[wave_number], result.waves[wave_number]
                assert(#after == #before, "independent rich rows must preserve every existing model/role batch")
                local total = 0
                for index, row in ipairs(after) do
                    local expected = normalized(assert(expected_waves[row.wave_id]))
                    local variants = variant_index[difficulty .. ":" .. wave_number .. ":" .. row.batch_id]
                    if variants then
                        expected.rich_stat_variants = {}
                        for _, variant in ipairs(variants) do
                            local value = {}
                            for _, field in ipairs(variant_fields) do
                                if variant[field] ~= "" then value[field] = copy(variant[field]) end
                            end
                            expected.rich_stat_variants[#expected.rich_stat_variants + 1] = value
                        end
                    end
                    assert(equal(row, expected), difficulty .. "/" .. row.batch_id .. " changed authored rich values/provenance")
                    for _, field in ipairs(preserved) do
                        assert(row[field] == before[index][field], "rich rows changed template " .. field)
                    end
                    if row.rich_field_sources then
                        for _, field in ipairs({"health", "attack", "war3_armor"}) do
                            assert(type(row.rich_field_sources[field].method) == "string",
                                "final recorded stats must retain their field-level provenance")
                        end
                    end
                    if number == 2 or number == 3 then
                        assert(row.rich_difficulty_scaled == false and row.rich_reference_wave == wave_number,
                            "recorded N2/N3 final values must bypass difficulty scaling")
                    end
                    assert(row.monster_count > 0 and row.monster_count == math.floor(row.monster_count))
                    total = total + row.monster_count
                    assert(equal(row, flattened[row.wave_id]), "flattened and spawned batches disagree")
                    waves_verified = waves_verified + 1
                end
                assert(total == 60, "rich waves must retain 60 monsters per owner, all roles included")
            end
            result.rows[1].health = -1
            if result.rows[1].rich_field_sources then
                result.rows[1].rich_field_sources.health.method = "caller_mutation"
            end
            assert(equal(rich_waves, original_waves) and equal(rich_variants, original_variants)
                and equal(source, original_source), "caller mutation escaped the independent rich plan")
        end
    end
    local count = 0
    for id, expected in pairs(assert(profile_index[difficulty])) do
        local ordinary = assert(encounters.resolve(id, difficulty))
        for _, mode in ipairs({"rich", "standard", "rich", "pure", "fishing", "standard"}) do
            local value = assert(encounters.resolve(id, difficulty, mode))
            if mode == "rich" then
                assert(equal(value, normalized(expected)), "rich encounter row changed authored values/provenance")
                assert(value ~= expected and value ~= ordinary, "rich encounter returns must be isolated clones")
                value.health = -1
                if value.field_sources then value.field_sources.health.method = "caller_mutation" end
            else
                assert(value == ordinary, "ordinary encounter lookup inherited rich mode state")
            end
            assert(equal(rich_profiles, original_profiles) and equal(ordinary_profiles, original_ordinary))
        end
        count, encounters_verified = count + 1, encounters_verified + 1
    end
    assert(count == 30, "every rich difficulty needs all four rooms and every wilderness member")
end
assert(waves_verified == #rich_waves.rows * 3 and encounters_verified == 300,
    "all independent N1-N10 wave rows and encounter profiles must be consumed")
local missing, reason = encounters.resolve("practice_wood", "N999", "rich")
assert(missing == nil and reason == "challenge_combat_profile_missing:practice_wood:N999")
local saved = encounters.rich_by_member.practice_wood.N6
encounters.rich_by_member.practice_wood.N6 = nil
missing, reason = encounters.resolve("practice_wood", "N6", "rich")
assert(missing == nil and reason == "challenge_combat_profile_missing:practice_wood:N6",
    "rich profiles must reject missing explicit difficulty rows instead of inheriting N5")
encounters.rich_by_member.practice_wood.N6 = saved
local ordinary_member = encounters.by_member.practice_wood
encounters.by_member.practice_wood = nil
for number = 1, 10 do
    local difficulty = "N" .. number
    assert(equal(assert(encounters.resolve("practice_wood", difficulty, "rich")),
        normalized(profile_index[difficulty].practice_wood)),
        "rich profiles must resolve without an ordinary member entry: " .. difficulty)
end
encounters.by_member.practice_wood = ordinary_member
local authored = rich_profiles.rows[1]
local health = authored.health
authored.health = health + 123
assert(encounters.resolve(authored.member_id, authored.difficulty_id, "rich").health == authored.health,
    "independent rich encounter table must be authoritative")
authored.health = health
assert(equal(rich_profiles, original_profiles) and equal(rich_waves, original_waves)
    and equal(rich_variants, original_variants) and equal(source, original_source)
    and equal(ordinary_profiles, original_ordinary))
print("RICH_MONSTER_CATALOG_PASS: all N1-N10 CSV wave batches and 300 encounters, final values/provenance, explicit difficulty rows, immutable sources and alternating modes")
