package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local buildings = require("config/buildings_config")
local farm = assert(buildings.building_farm)
local expected_model = "models/props_structures/radiant_ancient001.vmdl"
local expected_scale = 0.34
local expected_wood = { [1] = 100, [2] = 500, [3] = 2000, [4] = 10000, [5] = 50000 }
local expected_gold = { [1] = 0, [2] = 0, [3] = 0, [4] = 1000, [5] = 5000 }

for level = 1, 5 do
    local row = assert(farm.levels[level], "missing farm level " .. tostring(level))
    assert(row.model_name == expected_model,
        "farm level " .. tostring(level) .. " changed model")
    assert(row.model_scale == expected_scale,
        "farm level " .. tostring(level) .. " changed model scale")
    assert(row.model_yaw == 0,
        "farm level " .. tostring(level) .. " changed model yaw")
    assert(row.wood_cost == expected_wood[level],
        "farm level " .. tostring(level) .. " lost wood cost")
    assert(row.gold_cost == expected_gold[level],
        "farm level " .. tostring(level) .. " lost gold cost")
end

print("FARM_FIXED_VISUAL_PASS")
