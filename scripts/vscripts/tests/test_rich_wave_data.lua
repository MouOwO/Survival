-- Exercise the real difficulty builder and immutable production source table.
-- Numeric fixtures are independent OCR observations, including mixed-wave types.
package.path = "scripts/vscripts/?.lua;" .. package.path
local builder = require("systems/wave_difficulty_builder")
local source = require("config/generated/wave_definitions").rows

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
local original_source = copy(source)
local function build(id, mode)
    local result, reason = builder.build(source, id, mode)
    assert(result, tostring(id) .. "/" .. tostring(mode) .. ": " .. tostring(reason))
    return result
end
local function role(row) return row.member_role or "normal" end
local function index_batches(batches)
    local result = {}
    for _, row in ipairs(batches) do
        assert(not result[row.batch_id], "duplicate batch " .. tostring(row.batch_id))
        result[row.batch_id] = row
    end
    return result
end
local function one(built, wave, wanted_role, archetype)
    local result = nil
    for _, row in ipairs(assert(built.waves[wave], "wave missing: " .. wave)) do
        if role(row) == wanted_role and (not archetype or row.archetype_id == archetype) then
            assert(not result, "ambiguous fixture selector: " .. wave .. "/" .. wanted_role)
            result = row
        end
    end
    return assert(result, "fixture batch missing: " .. wave .. "/" .. tostring(archetype or wanted_role))
end
local function stats(row, attack, health, armor, label)
    assert(row.attack == attack, label .. " attack: " .. tostring(row.attack))
    assert(row.health == health, label .. " maximum health: " .. tostring(row.health))
    assert(row.war3_armor == armor, label .. " War3 armor: " .. tostring(row.war3_armor))
end

local difficulties = {"N1", "N2", "N5", "N10"}
local legacy, rich = {}, {}
for _, id in ipairs(difficulties) do legacy[id] = copy(build(id)) end
for _, id in ipairs(difficulties) do rich[id] = build(id, "rich") end
assert(rich.N1.total_waves == 25 and rich.N1.waves[26] == nil,
    "recorded rich N1 ends at wave 25")

local preserved = {"archetype_id", "member_role", "movement_type_override",
    "model_scale_multiplier", "attack_speed", "spawn_interval", "spawn_order",
    "is_boss", "boss_warning", "enabled"}
for _, id in ipairs(difficulties) do
    local expected_waves = id == "N1" and 25 or 30
    assert(rich[id].total_waves == expected_waves and legacy[id].total_waves == expected_waves,
        "rich overlay cannot change existing difficulty length: " .. id)
    local flattened = {}
    for _, row in ipairs(rich[id].rows) do
        assert(not flattened[row.wave_id], "flattened rich wave IDs must be unique")
        flattened[row.wave_id] = row
    end
    local wave_rows = 0
    for number = 1, expected_waves do
        local before = assert(legacy[id].waves[number])
        local after = assert(rich[id].waves[number])
        assert(#after == #before, id .. " must retain every model batch in wave " .. number)
        local by_batch = index_batches(after)
        local total, original_normal, rich_normal = 0, 0, 0
        for _, row in ipairs(before) do
            if role(row) == "normal" then original_normal = original_normal + row.monster_count end
        end
        for _, row in ipairs(after) do
            assert(row.monster_count >= 1 and row.monster_count == math.floor(row.monster_count),
                "all existing batches remain represented by whole monsters")
            total = total + row.monster_count
            if role(row) == "normal" then rich_normal = rich_normal + row.monster_count end
            local flat = assert(flattened[row.wave_id], "rich waves and flattened rows must agree")
            for _, field in ipairs({"attack", "health", "war3_armor", "monster_count"}) do
                assert(flat[field] == row[field], "flattened stats disagree: " .. row.wave_id .. "/" .. field)
            end
            wave_rows = wave_rows + 1
        end
        assert(total == 60, id .. " W" .. number .. " must total 60 including leaders and assault bosses")
        for _, row in ipairs(before) do
            local updated = assert(by_batch[row.batch_id], "original model batch was dropped")
            for _, field in ipairs(preserved) do
                assert(updated[field] == row[field], id .. " W" .. number .. " changed " .. field)
            end
            if role(row) == "normal" then
                local quota = row.monster_count * rich_normal / original_normal
                assert(math.abs(updated.monster_count - quota) <= 1.000001,
                    "normal batch proportions must remain within one monster of their original share")
            else
                assert(updated.monster_count == row.monster_count,
                    "special members keep their original count while ordinary monsters fill the quota")
            end
        end
    end
    assert(wave_rows == #rich[id].rows, "flattened rows must not contain unspawned extra waves")
end

stats(one(rich.N1, 1, "normal"), 7, 700, 6, "N1 W1")
for _, archetype in ipairs({"beast_green_large", "skeleton_bone"}) do
    stats(one(rich.N1, 11, "normal", archetype), 7002, 70000, 120, "N1 W11 ground " .. archetype)
end
stats(one(rich.N1, 11, "normal", "flying_red_gargoyle"), 3502, 70000, 120, "N1 W11 flying")
stats(one(rich.N1, 11, "wave_leader"), 28002, 700000, 240, "N1 W11 leader")
for _, archetype in ipairs({"orc_brown_large", "orc_brown_small"}) do
    stats(one(rich.N1, 13, "normal", archetype), 9802, 210000, 180, "N1 W13 ground " .. archetype)
end
stats(one(rich.N1, 13, "normal", "flying_green_head"), 7002, 105000, 180, "N1 W13 flying")
stats(one(rich.N1, 13, "wave_leader"), 39202, 2100000, 360, "N1 W13 leader")
stats(one(rich.N1, 16, "normal", "flying_carpet_mage"), 24502, 350000, 270, "N1 W16 mage")
for _, archetype in ipairs({"stitcher_large", "stitcher_small"}) do
    stats(one(rich.N1, 24, "normal", archetype), 140002, 2100000, 450, "N1 W24 stitcher " .. archetype)
end
stats(one(rich.N1, 24, "normal", "humanoid_red_sword"), 161002, 2100000, 465, "N1 W24 swordsman")
stats(one(rich.N1, 24, "normal", "flying_black_bone"), 63002, 2450000, 435, "N1 W24 flying")
stats(one(rich.N1, 24, "wave_leader"), 560002, 21000000, 900, "N1 W24 leader")

local bosses = {
    [5] = {4552, 70030, 294}, [10] = {54777, 560035, 1644},
    [15] = {105002, 1050040, 2994}, [20] = {402502, 11025035, 2994},
    [25] = {700002, 21000030, 2994},
}
for number, expected in pairs(bosses) do
    local boss = one(rich.N1, number, "assault_boss")
    stats(boss, expected[1], expected[2], expected[3], "N1 assault boss " .. number)
    if number == 10 or number == 20 then
        assert(boss.rich_stats_estimated == true
            and boss.rich_estimation_method == "linear_between_bosses"
            and boss.rich_stats_source == "boss_interpolation",
            "unrecorded bosses must retain explicit interpolation provenance")
    else
        assert(boss.rich_stats_estimated ~= true and boss.rich_stats_source == "ocr",
            "confirmed boss observations cannot be mislabeled as estimates")
    end
end

-- Higher difficulties retain their original per-batch relation to N1. The
-- comparison uses source difficulty data, not a multiplier supplied by overlay.
local fields = {"attack", "health", "war3_armor"}
for _, id in ipairs({"N2", "N5", "N10"}) do
    for number = 1, 25 do
        local n1_old = index_batches(legacy.N1.waves[number])
        local n1_new = index_batches(rich.N1.waves[number])
        local old = index_batches(legacy[id].waves[number])
        for _, row in ipairs(rich[id].waves[number]) do
            local old_n1, new_n1 = n1_old[row.batch_id], n1_new[row.batch_id]
            assert(old[row.batch_id], "higher difficulty template must be traceable")
            assert(row.rich_difficulty_scaled == true, "higher difficulty scaling must be explicit")
            if not old_n1 or not new_n1 then
                -- Existing higher difficulties have W4 4L, whereas the N1
                -- production template has only ordinary W4 members. Apply the
                -- ordinary difficulty ratio to the observed leader once.
                assert(number == 4 and row.batch_id == "4L" and role(row) == "wave_leader",
                    "a new unmatched template needs an explicit independent regression case")
                local old_ordinary = one(legacy.N1, 4, "normal", row.archetype_id)
                local higher_ordinary = one(legacy[id], 4, "normal", row.archetype_id)
                local observed_leader = {attack = 842, health = 35000, war3_armor = 48}
                assert(row.rich_difficulty_reference_role == "normal",
                    "missing N1 leader must trace its ordinary difficulty reference")
                for _, field in ipairs(fields) do
                    local expected = observed_leader[field] * higher_ordinary[field] / old_ordinary[field]
                    assert(math.abs(row[field] - expected) <= 0.500001,
                        id .. " W4 leader applied its elite ratio twice for " .. field)
                end
            else
                local old_ordinary, new_ordinary = nil, nil
                if new_n1.rich_stats_source == "existing_leader_ratio" then
                    -- Do not amplify rounding already applied to the N1
                    -- derived leader. Use the matching ordinary observation,
                    -- including its model-specific override, and round once.
                    for _, candidate in ipairs(legacy.N1.waves[number]) do
                        if role(candidate) == "normal" then
                            old_ordinary = old_ordinary or candidate
                            if candidate.archetype_id == row.archetype_id then
                                old_ordinary = candidate
                                break
                            end
                        end
                    end
                    new_ordinary = assert(old_ordinary and n1_new[old_ordinary.batch_id],
                        "derived leader must have an ordinary observation reference")
                end
                for _, field in ipairs(fields) do
                    local expected = old[row.batch_id][field] * new_n1[field] / old_n1[field]
                    if old_ordinary then
                        expected = old[row.batch_id][field] * new_ordinary[field] / old_ordinary[field]
                    end
                    assert(math.abs(row[field] - expected) <= 0.500001,
                        id .. " W" .. number .. "/" .. row.batch_id .. " lost source difficulty relation for " .. field)
                end
            end
        end
    end
    for number = 26, 30 do
        local old = index_batches(legacy[id].waves[number])
        for _, row in ipairs(rich[id].waves[number]) do
            local old_ref = one(legacy.N1, 25, role(row))
            local rich_ref = one(rich.N1, 25, role(row))
            assert(row.rich_reference_wave == 25 and row.rich_difficulty_scaled == true,
                "unrecorded tail waves must identify the recorded W25 reference")
            for _, field in ipairs(fields) do
                local expected = old[row.batch_id][field] * rich_ref[field] / old_ref[field]
                assert(math.abs(row[field] - expected) <= 0.500001,
                    id .. " tail W" .. number .. " must retain its own template and W25 enrichment")
            end
        end
    end
end

-- Alternating mode calls cannot leak rich counts, stats or metadata into other
-- modes, even when all calls reuse the same generated table and builder module.
for _, mode in ipairs({"standard", "rich", "pure", "fishing", "standard"}) do
    for _, id in ipairs(difficulties) do
        local result = build(id, mode)
        if mode ~= "rich" then assert(equal(result, legacy[id]), mode .. " was contaminated by rich data") end
    end
end
assert(equal(source, original_source), "rich building mutated shared generated source rows")
local changed = one(rich.N1, 1, "normal")
changed.attack, changed.monster_count = -999, 999
stats(one(build("N1", "rich"), 1, "normal"), 7, 700, 6, "fresh rich build after caller mutation")
assert(equal(build("N1"), legacy.N1), "mutating a returned rich table contaminated the legacy builder")
assert(equal(source, original_source), "caller mutation escaped into the generated source")
print("RICH_WAVE_DATA_PASS: OCR variants and bosses, estimate provenance, 60 per owner, immutable models/source, difficulty ratios and W25 tail extension, mixed-mode isolation")
