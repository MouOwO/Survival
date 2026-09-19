package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local archetypes = require("config/generated/monster_archetypes")
local encounters = require("config/generated/monster_encounters")
local members = require("config/generated/encounter_members")
local buildings = require("config/generated/building_challenge_definitions")
local names = {}
for _, module in ipairs({"challenge_definitions", "rebirth_challenges"}) do
    for _, row in ipairs(require("config/generated/" .. module).rows) do
        names[row.encounter_id] = row.name
    end
end
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"); file:close(); return text
end
local kv = read("scripts/npc/npc_units_custom.txt")
local locales = {read("resource/addon_schinese.txt"), read("resource/localization/addon_schinese.txt")}
local count = 0
local function check(row, expected)
    assert(row.display_name == expected, row.display_name)
    assert(row.unit_name ~= "npc_survival_wave_monster", expected)
    assert(kv:find('"' .. row.unit_name .. '"', 1, true), row.unit_name)
    for _, text in ipairs(locales) do
        assert(text:find('"' .. row.unit_name .. '" "' .. expected .. '"', 1, true), expected)
    end
    count = count + 1
end
for _, row in ipairs(encounters.rows) do
    if names[row.encounter_id] then
        assert(row.display_name == names[row.encounter_id])
        if row.archetype_id then check(archetypes.by_id[row.archetype_id], row.display_name) end
    end
end
for _, member in ipairs(members.rows) do
    local row = archetypes.by_id[member.archetype_id]
    if row and (row.display_group == "boss" or row.display_group == "challenge") then
        check(row, assert(names[member.encounter_id]))
    end
end
for _, row in ipairs(buildings.rows) do check(row, row.display_name) end
for id, name in pairs({practice_wood_spirit="木头精",practice_gold_spirit="金币精",practice_attribute_spirit="属性精",practice_greater_attribute_spirit="大属性精"}) do
    check(archetypes.by_id[id], name)
end
check(archetypes.by_id.humanoid_white_melee, "白发人形近战怪")
assert(count == 36, tostring(count))
print("CHALLENGE_UNIT_NAMES_PASS: 35 challenge names preserved, wave name follows archetype")
local waves_checked = 0
for _, wave in ipairs(require("config/generated/wave_definitions").rows) do
    local definition = assert(archetypes.by_id[wave.archetype_id])
    local boss = wave.member_role == "assault_boss" or wave.is_boss == true
    check(definition, boss and ("波次" .. wave.wave_number .. "BOSS") or definition.display_name)
    if boss then
        local base_id = definition.archetype_id:gsub("_wave_name_%d+$", "")
        local source = assert(archetypes.by_id[base_id])
        for key, value in pairs(source) do
            if key ~= "archetype_id" and key ~= "display_name" and key ~= "unit_name" then
                if type(value) == "table" then
                    assert(table.concat(value, "|") == table.concat(definition[key], "|"), key)
                else
                    assert(definition[key] == value, key)
                end
            end
        end
    end
    waves_checked = waves_checked + 1
end
assert(waves_checked > 0)
print("WAVE_UNIT_NAMES_PASS: " .. waves_checked .. " rows, native names, boss wave labels, combat/visual fields preserved")
