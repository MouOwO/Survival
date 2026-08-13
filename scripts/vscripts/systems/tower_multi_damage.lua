local anti_air_rules = require("systems/anti_air_rules")
local damage_rules = require("config/generated/tower_skill_damage_rules")

local M = {}

function M.multiplier(skill, target)
    local rule = damage_rules.by_id[skill.skill_id]
    local multiplier = tonumber(skill.damage_multiplier) or 1
    if target and not target:IsNull() and target:IsAlive()
        and not anti_air_rules.is_flying(target) then
        multiplier = multiplier * (tonumber(rule and rule.ground_damage_multiplier) or 1)
    end
    return multiplier
end

return M