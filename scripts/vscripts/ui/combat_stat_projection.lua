local armor_balance = require("config/armor_balance")

local M = {}

local function copy(snapshot)
    local projected = {}
    for key, value in pairs(snapshot or {}) do projected[key] = value end
    return projected
end

local function physical_reduction_pct(armor, mapping_version)
    if tonumber(mapping_version) == armor_balance.CUSTOM_WAR3_MAPPING_VERSION then
        return armor_balance.war3_physical_reduction_pct(armor)
    end
    return armor_balance.modern_physical_reduction_pct(armor)
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
            mapping_version = tonumber(projected.armor_mapping_version) or 1,
            physical_reduction_pct = physical_reduction_pct(
                tonumber(projected.armor_mapping_version)
                        == armor_balance.CUSTOM_WAR3_MAPPING_VERSION
                    and (tonumber(projected.armor) or 0)
                    or (tonumber(projected.runtime_armor) or 0),
                projected.armor_mapping_version
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
    if tonumber(projected.armor_mapping_version)
        == armor_balance.CUSTOM_WAR3_MAPPING_VERSION then
        projected.armor = tonumber(projected.armor)
            or tonumber(projected.effective_war3_armor)
            or tonumber(projected.war3_armor) or 0
        projected.runtime_armor = 0
        projected.armor_unit = "war3_display"
        projected.stat_units_version = 2
    end
    if tonumber(projected.stat_units_version) ~= 2 then
        local runtime_armor = tonumber(projected.runtime_armor)
            or tonumber(projected.armor)
            or 0
        projected.runtime_armor = runtime_armor
        local mapping_version = tonumber(projected.armor_mapping_version) or 1
        local display_armor = armor_balance.to_war3_for_mapping(
            runtime_armor,
            mapping_version
        )
        -- Modern equivalent armor has no finite War3 inverse at or above the
        -- asymptote. Keep the runtime value visible rather than fabricating a
        -- misleading finite display value.
        projected.armor = display_armor ~= nil and display_armor or runtime_armor
        projected.armor_mapping_version = mapping_version
        projected.armor_unit = "war3_display"
        projected.stat_units_version = 2
    end
    projected.stat_tooltips = stat_tooltips(projected)
    return projected
end

M.physical_reduction_pct = physical_reduction_pct

return M