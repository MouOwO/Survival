local armor_balance = require("config/armor_balance")

local M = {}

function M.apply(unit, base_war3_armor, bonus_war3_armor)
    if not unit or (unit.IsNull and unit:IsNull()) then return false end
    local base = tonumber(base_war3_armor) or 0
    local bonus = tonumber(bonus_war3_armor) or 0
    local effective = base + bonus

    unit.survival_war3_armor_target = true
    unit.survival_armor_mapping_version = armor_balance.CUSTOM_WAR3_MAPPING_VERSION
    unit.survival_base_war3_armor = base
    unit.survival_war3_armor = effective
    unit.survival_effective_war3_armor = effective
    unit.survival_armor = effective
    if unit.SetPhysicalArmorBaseValue then
        unit:SetPhysicalArmorBaseValue(0)
    end
    return true, effective
end

return M