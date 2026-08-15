local generated = require("config/generated/global_rules")

local M = {}

function M.number(rule_id, fallback)
    local row = (generated.by_id or {})[rule_id]
    if not row or row.enabled == false then return fallback end
    local value = tonumber(row.value)
    return value ~= nil and value or fallback
end

M.tower_attack_range = M.number("tower_attack_range", 1000)
M.tower_acquisition_range = M.number(
    "tower_acquisition_range",
    M.tower_attack_range
)
M.tower_base_projectile_speed = M.number(
    "tower_base_projectile_speed",
    5000
)
M.tower_route_default_projectile_speed = M.number(
    "tower_route_default_projectile_speed",
    1250
)
M.tower_class_max_count = M.number("tower_class_max_count", 5)
M.tower_projectile_speed_multiplier = M.number(
    "tower_projectile_speed_multiplier",
    1
)
M.wave_monster_round_robin_enabled = M.number(
    "wave_monster_round_robin_enabled",
    1
)
M.repair_detection_range = M.number(
    "repair_detection_range",
    FIND_UNITS_EVERYWHERE or 99999
)
--M.dev_wall_health = M.number("dev_wall_health", 10000000)
--M.dev_wall_war3_armor = M.number("dev_wall_war3_armor", 1000)

return M