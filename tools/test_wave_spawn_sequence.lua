package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local archetypes = require("config/generated/monster_archetypes")
local wave_rows = require("config/generated/wave_definitions")
local wave_builder = require("systems/wave_difficulty_builder")
local sequence = require("systems/wave_spawn_sequence")

local function row(archetype_id, monster_count, member_role)
    return {
        archetype_id = archetype_id,
        monster_count = monster_count,
        member_role = member_role,
    }
end

local function ids(rows)
    local result = {}
    for _, entry in ipairs(rows) do
        result[#result + 1] = entry.archetype_id
    end
    return table.concat(result, ",")
end

local ground_a = row("ground_a", 3, "normal")
local ground_b = row("ground_b", 2, "normal")
local flying_c = row("flying_c", 2, "normal")
local movement = {
    ground_a = "ground",
    ground_b = "ground",
    flying_c = "flying",
    ground_only = "ground",
    flying_only = "flying",
}
local mixed_options = {
    enabled = true,
    movement_type = function(entry)
        return movement[entry.archetype_id] or "ground"
    end,
}

assert(ids(sequence.build({ ground_a, ground_b, flying_c }, mixed_options)) ==
        "ground_a,ground_b,flying_c,ground_a,ground_b,flying_c,ground_a",
    "two-ground one-flying wave did not use the ABC cycle")
assert(ids(sequence.build({ row("ground_a", 2), row("ground_b", 2),
        row("flying_c", 2) }, mixed_options)) ==
        "ground_a,ground_b,flying_c,ground_a,ground_b,flying_c",
    "three normal types with counts above one did not repeat one-per-type")
assert(ids(sequence.build({ row("ground_only", 4), row("flying_only", 2) },
        mixed_options)) ==
        "ground_only,ground_only,flying_only,ground_only,ground_only,flying_only",
    "mixed wave did not use the two-ground one-flying cycle")
assert(ids(sequence.build({ row("ground_only", 5), row("flying_only", 1) },
        mixed_options)) ==
        "ground_only,ground_only,flying_only,ground_only,ground_only,ground_only",
    "mixed wave did not preserve remaining monsters after one category ended")
assert(ids(sequence.build({ row("a", 2), row("b", 1) }, true)) == "a,b,a",
    "two-type wave did not use round-robin order")
assert(ids(sequence.build({ row("only", 3) }, true)) == "only,only,only",
    "single-type wave changed order or count")
assert(ids(sequence.build({ ground_a, ground_b, flying_c }, false)) ==
        "ground_a,ground_a,ground_a,ground_b,ground_b,flying_c,flying_c",
    "disabled rule did not preserve batch order")

local boss = row("assault_boss", 1, "assault_boss")
local leader = row("wave_leader", 1, "wave_leader")
assert(ids(sequence.build({ boss, leader, ground_a, ground_b, flying_c }, true)) ==
        "assault_boss,wave_leader,ground_a,ground_b,flying_c,ground_a,ground_b,flying_c,ground_a",
    "special members moved into the normal monster cycle")

local middle_boss = row("middle_boss", 1, "assault_boss")
assert(ids(sequence.build({ row("a", 2), row("b", 1), middle_boss,
        row("c", 2), row("d", 1) }, true)) ==
        "a,b,a,middle_boss,c,d,c",
    "special member did not preserve the normal-group boundary")

local function movement_type(entry)
    local definition = assert(archetypes.by_id[entry.archetype_id],
        "missing archetype: " .. tostring(entry.archetype_id))
    return entry.movement_type_override or definition.movement_type or "ground"
end

local function verify_group(difficulty_id, wave_number, group)
    local output = sequence.build(group, {
        enabled = true,
        movement_type = movement_type,
    })
    local expected_counts = {}
    local actual_counts = {}
    local ground_remaining = 0
    local flying_remaining = 0
    for _, entry in ipairs(group) do
        local count = math.max(0, math.floor(tonumber(entry.monster_count) or 0))
        expected_counts[entry] = count
        if movement_type(entry) == "flying" then
            flying_remaining = flying_remaining + count
        else
            ground_remaining = ground_remaining + count
        end
    end
    for _, entry in ipairs(output) do
        actual_counts[entry] = (actual_counts[entry] or 0) + 1
    end
    for entry, count in pairs(expected_counts) do
        assert(actual_counts[entry] == count, string.format(
            "%s W%d changed count for %s", difficulty_id, wave_number,
            tostring(entry.archetype_id)))
    end

    if ground_remaining <= 0 or flying_remaining <= 0 then return false end
    local output_index = 1
    while ground_remaining > 0 or flying_remaining > 0 do
        for _ = 1, 2 do
            if ground_remaining > 0 then
                assert(movement_type(output[output_index]) ~= "flying", string.format(
                    "%s W%d did not spawn two ground monsters before flying",
                    difficulty_id, wave_number))
                ground_remaining = ground_remaining - 1
                output_index = output_index + 1
            end
        end
        if flying_remaining > 0 then
            assert(movement_type(output[output_index]) == "flying", string.format(
                "%s W%d did not spawn a flying monster after two ground monsters",
                difficulty_id, wave_number))
            flying_remaining = flying_remaining - 1
            output_index = output_index + 1
        end
    end
    assert(output_index == #output + 1,
        difficulty_id .. " W" .. wave_number .. " output length mismatch")
    return true
end

local mixed_wave_count = 0
local special_mixed_wave_count = 0
for _, difficulty_id in ipairs({ "N1", "N2", "N3", "N4", "N5" }) do
    local built = assert(wave_builder.build(wave_rows.rows, difficulty_id))
    for wave_number, batches in pairs(built.waves) do
        local index = 1
        while index <= #batches do
            if sequence.is_normal(batches[index]) then
                local group = {}
                while index <= #batches and sequence.is_normal(batches[index]) do
                    group[#group + 1] = batches[index]
                    index = index + 1
                end
                if verify_group(difficulty_id, wave_number, group) then
                    mixed_wave_count = mixed_wave_count + 1
                    if wave_number == 11 or wave_number == 13 or wave_number == 24 then
                        local output = sequence.build(group, {
                            enabled = true,
                            movement_type = movement_type,
                        })
                        assert(#output == 59, string.format(
                            "%s W%d normal count is not 59", difficulty_id, wave_number))
                        for output_index = 1, 57 do
                            local expected_flying = output_index % 3 == 0
                            assert((movement_type(output[output_index]) == "flying") == expected_flying,
                                string.format("%s W%d mixed cycle changed at %d",
                                    difficulty_id, wave_number, output_index))
                        end
                        assert(movement_type(output[58]) ~= "flying"
                                and movement_type(output[59]) ~= "flying",
                            string.format("%s W%d final ground pair changed",
                                difficulty_id, wave_number))
                        special_mixed_wave_count = special_mixed_wave_count + 1
                    end
                end
            else
                index = index + 1
            end
        end
    end
end

assert(mixed_wave_count > 0, "generated wave configuration contains no mixed waves")
assert(special_mixed_wave_count == 15,
    "W11/W13/W24 are not mixed in all five difficulties")
print(string.format("WAVE_SPAWN_SEQUENCE_PASS mixed_waves=%d special_mixed_waves=%d",
    mixed_wave_count, special_mixed_wave_count))