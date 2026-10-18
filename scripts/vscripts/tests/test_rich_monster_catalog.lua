-- Real generated data and production builders/resolver; no config substitutes.
package.path = "scripts/vscripts/?.lua;" .. package.path
local recorded = require("config/generated/rich_monster_profiles")
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
local function role(row)
    if row.is_boss or row.member_role == "assault_boss" then return "boss" end
    return row.member_role == "wave_leader" and "leader" or "normal"
end
local function build(difficulty, mode) return assert(builder.build(source, difficulty, mode)) end
local original_recorded, original_source = copy(recorded), copy(source)
local original_profiles = copy(ordinary_profiles)
local preserved = {"wave_id", "difficulty_id", "wave_number", "batch_id", "archetype_id",
    "member_role", "is_boss", "boss_warning", "enabled", "attack_speed", "spawn_interval",
    "spawn_order", "movement_type_override", "model_scale_multiplier"}
local waves_verified, encounters_verified = 0, 0
for _, difficulty in ipairs({"N2", "N3"}) do
    local standard = copy(build(difficulty, "standard"))
    local profiles = assert(recorded.difficulties[difficulty])
    for _, mode in ipairs({"rich", "standard", "rich", "pure", "fishing", "rich", "standard"}) do
        local result = build(difficulty, mode)
        if mode ~= "rich" then
            assert(equal(result, standard), difficulty .. "/" .. mode .. " inherited rich values or metadata")
        else
            assert(result.total_waves == 30)
            local flattened = {}
            for _, row in ipairs(result.rows) do
                assert(not flattened[row.wave_id], "duplicate flattened wave row")
                flattened[row.wave_id] = row
            end
            for wave_number = 1, 30 do
                local before, after = standard.waves[wave_number], result.waves[wave_number]
                assert(#after == #before, "recorded profiles must preserve every model/role batch")
                local total = 0
                for index, row in ipairs(after) do
                    local expected = assert(profiles.waves[wave_number].batches[row.batch_id])
                    for _, field in ipairs({"health", "attack", "war3_armor"}) do
                        assert(row[field] == expected[field], difficulty .. "/" .. row.batch_id
                            .. "/" .. field .. " applied a difficulty multiplier to a final value")
                        assert(type(expected.field_sources[field].method) == "string",
                            "every final stat must retain its field-level provenance")
                    end
                    for _, field in ipairs(preserved) do
                        assert(row[field] == before[index][field], "recorded stats changed template " .. field)
                    end
                    assert(equal(row.rich_field_sources, expected.field_sources)
                        and row.rich_stats_source == expected.stats_source
                        and row.rich_stats_estimated == (expected.estimated == true)
                        and row.rich_source_record_id == expected.source_record_id,
                        "observations and estimates must keep their complete identity/provenance")
                    assert(row.rich_difficulty_scaled == false and row.rich_reference_wave == wave_number,
                        "direct N2/N3 rows must bypass old N1 ratios and W25 tail references")
                    assert(row.monster_count > 0 and row.monster_count == math.floor(row.monster_count))
                    if role(row) ~= "normal" then
                        assert(row.monster_count == before[index].monster_count,
                            "recorded overlay must retain every special-member count")
                    end
                    total = total + row.monster_count
                    assert(equal(row, flattened[row.wave_id]), "flattened and spawned batches disagree")
                    if mode == "rich" then waves_verified = waves_verified + 1 end
                end
                assert(total == 60, "rich waves must retain 60 monsters per owner, all roles included")
            end
            -- A caller can mutate a returned plan without modifying the
            -- generated observations or another mode's plan.
            result.rows[1].health = -1
            result.rows[1].rich_field_sources.health.method = "caller_mutation"
            assert(equal(recorded, original_recorded) and equal(source, original_source))
        end
    end
    local ordinary_count, seen = 0, {}
    for _, row in ipairs(ordinary_profiles.rows) do
        if row.enabled ~= false and row.difficulty_id == difficulty then
            local id = row.member_id
            assert(not seen[id], "duplicate ordinary member profile")
            seen[id], ordinary_count = true, ordinary_count + 1
            local expected = assert(profiles.encounters[id], "configured member missing rich data: " .. id)
            local ordinary = assert(encounters.resolve(id, difficulty))
            for _, mode in ipairs({"rich", "standard", "rich", "pure", "fishing", "standard"}) do
                local value = assert(encounters.resolve(id, difficulty, mode))
                if mode == "rich" then
                    assert(equal(value, expected), "real generated encounter profile was altered")
                    value.health, value.field_sources.health.method = -1, "caller_mutation"
                else
                    assert(value == ordinary, "ordinary encounter lookup inherited rich mode state")
                end
                assert(equal(recorded, original_recorded) and equal(ordinary_profiles, original_profiles))
            end
            encounters_verified = encounters_verified + 1
        end
    end
    local rich_count = 0
    for id in pairs(profiles.encounters) do
        assert(seen[id], "unexpected rich-only gameplay member: " .. id)
        rich_count = rich_count + 1
    end
    assert(ordinary_count == 30 and rich_count == ordinary_count)
end
assert(waves_verified == 178 * 3 and encounters_verified == 60,
    "all 178 wave batches and 60 encounter profiles must be consumed")
local missing, reason = encounters.resolve("practice_wood", "N999", "rich")
assert(missing == nil and reason == "challenge_combat_profile_missing:practice_wood:N999")
for _, difficulty in ipairs({"N1", "N4", "N5", "N10"}) do
    assert(encounters.resolve("practice_wood", difficulty, "rich")
        == encounters.resolve("practice_wood", difficulty), "unrecorded difficulties changed")
end
assert(equal(recorded, original_recorded) and equal(source, original_source)
    and equal(ordinary_profiles, original_profiles))
print("RICH_MONSTER_CATALOG_PASS: real generated 178 wave batches and 60 encounters, final stats once, provenance, counts, immutable sources and alternating modes")
