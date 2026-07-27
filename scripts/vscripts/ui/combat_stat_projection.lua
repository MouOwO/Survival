local armor_balance = require("config/armor_balance")

local M = {}

local function copy(snapshot)
    local projected = {}
    for key, value in pairs(snapshot or {}) do projected[key] = value end
    return projected
end

function M.for_ui(snapshot)
    local projected = copy(snapshot)
    if tonumber(projected.stat_units_version) == 2 then return projected end

    local runtime_armor = tonumber(projected.runtime_armor)
        or tonumber(projected.armor)
        or 0
    projected.runtime_armor = runtime_armor
    projected.armor = armor_balance.to_war3(runtime_armor)
    projected.armor_unit = "war3_display"
    projected.stat_units_version = 2
    return projected
end

return M