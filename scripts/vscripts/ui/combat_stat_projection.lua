local armor_balance = require("config/armor_balance")

local M = {}

local function copy(snapshot)
    local projected = {}
    for key, value in pairs(snapshot or {}) do projected[key] = value end
    return projected
end

local function physical_reduction_pct(runtime_armor)
    local armor = tonumber(runtime_armor) or 0
    return 100 * (0.06 * armor) / (1 + 0.06 * math.abs(armor))
end

local function stat_tooltips(projected)
    local attack_speed = tonumber(projected.attack_speed) or 0
    return {
        attack = {
            minimum = tonumber(projected.attack_min) or 0,
            maximum = tonumber(projected.attack_max)
                or tonumber(projected.attack_min)
                or 0,
            unit = "logical_damage",
        },
        armor = {
            display_value = tonumber(projected.armor) or 0,
            runtime_value = tonumber(projected.runtime_armor) or 0,
            unit = "war3_display",
            physical_reduction_pct = physical_reduction_pct(
                projected.runtime_armor
            ),
        },
        attack_speed = {
            attacks_per_second = attack_speed,
            attack_interval = attack_speed > 0 and (1 / attack_speed) or 0,
            unit = "attacks_per_second",
        },
        attributes = {
            strength = tonumber(projected.strength) or 0,
            agility = tonumber(projected.agility) or 0,
            intellect = tonumber(projected.intellect) or 0,
            unit = "logical_attribute",
        },
    }
end

function M.for_ui(snapshot)
    local projected = copy(snapshot)
    if tonumber(projected.stat_units_version) ~= 2 then
        local runtime_armor = tonumber(projected.runtime_armor)
            or tonumber(projected.armor)
            or 0
        projected.runtime_armor = runtime_armor
        projected.armor = armor_balance.to_war3(runtime_armor)
        projected.armor_unit = "war3_display"
        projected.stat_units_version = 2
    end
    projected.stat_tooltips = stat_tooltips(projected)
    return projected
end

M.physical_reduction_pct = physical_reduction_pct

return M