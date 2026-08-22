package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local source = require("config/generated/wave_definitions")
local builder = require("systems/wave_difficulty_builder")

local function batches(result, wave_number)
    local rows = assert(result.waves[wave_number], "missing wave " .. wave_number)
    assert(#rows > 0, "empty wave " .. wave_number)
    return rows
end

local n1 = assert(builder.build(source.rows, "N1"))
assert(n1.total_waves == 25, "N1 total wave count changed")
assert(#batches(n1, 25) == 2, "N1 final wave batches changed")
assert(batches(n1, 1)[1].health == 200, "N1 health changed")
assert(batches(n1, 1)[1].attack == 2, "N1 attack changed")
assert(batches(n1, 1)[1].war3_armor == 2, "N1 armor changed")

local n2 = assert(builder.build(source.rows, "N2"))
assert(n2.total_waves == 30, "N2 must contain 30 waves")
local n1_wave_21 = batches(n1, 21)
local n2_wave_21 = batches(n2, 21)
assert(n2_wave_21[1].health == n1_wave_21[1].health * 1.5,
    "N2 regular health multiplier is incorrect")
assert(n2_wave_21[1].attack == n1_wave_21[1].attack * 1.5,
    "N2 regular attack multiplier is incorrect")
assert(n2_wave_21[1].war3_armor == n1_wave_21[1].war3_armor * 1.5,
    "N2 regular armor multiplier is incorrect")
assert(n2_wave_21[1].monster_count == n1_wave_21[1].monster_count,
    "N2 changed monster count")
assert(n2_wave_21[1].archetype_id == n1_wave_21[1].archetype_id,
    "N2 changed monster archetype")
assert(n2_wave_21[1].attack_speed == n1_wave_21[1].attack_speed,
    "N2 changed attack speed")

for target = 25, 30 do
    local source_wave = target - 5
    local target_batches = batches(n2, target)
    local source_batches = batches(n2, source_wave)
    assert(#target_batches == #source_batches,
        "special N2 wave changed batch count")
    for index, target_row in ipairs(target_batches) do
        local source_row = source_batches[index]
        assert(target_row.health == source_row.health * 2,
            "special N2 health mapping is incorrect")
        assert(target_row.attack == source_row.attack * 2,
            "special N2 attack mapping is incorrect")
        assert(target_row.war3_armor == source_row.war3_armor * 2,
            "special N2 armor mapping is incorrect")
        for _, field in ipairs({
            "archetype_id", "monster_count", "wait_seconds", "spawn_interval",
            "attack_speed", "is_boss", "boss_warning", "enabled", "notes",
        }) do
            assert(target_row[field] == source_row[field],
                "special N2 wave changed non-scaled field " .. field)
        end
    end
end

assert(batches(n2, 30)[1].health == batches(n1, 20)[1].health * 6,
    "N2 wave 30 must recursively use enhanced N2 wave 25")
assert(source.rows[1].health == 200 and source.rows[1].difficulty_id == "N1",
    "difficulty building mutated generated N1 data")
assert(builder.build(source.rows, "N3") == nil,
    "unconfigured reserved difficulty must be rejected")

print("WAVE_DIFFICULTY_BUILDER_PASS")