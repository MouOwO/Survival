local global_rules = require("config/global_rules")

local M = {}

function M.attack_range(technology_bonus)
    return (tonumber(global_rules.tower_attack_range) or 1000)
        + (tonumber(technology_bonus) or 0)
end

function M.projectile_speed(base_speed)
    base_speed = tonumber(base_speed)
    if not base_speed then return nil end
    local multiplier = math.max(
        0,
        tonumber(global_rules.tower_projectile_speed_multiplier) or 1
    )
    return base_speed * multiplier
end

return M