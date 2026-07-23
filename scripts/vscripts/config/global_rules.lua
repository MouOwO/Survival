local generated = require("config/generated/global_rules")

local M = {}

function M.number(rule_id, fallback)
    local row = (generated.by_id or {})[rule_id]
    if not row or row.enabled == false then return fallback end
    local value = tonumber(row.value)
    return value ~= nil and value or fallback
end

M.tower_attack_range = M.number("tower_attack_range", 2500)
M.tower_acquisition_range = M.number(
    "tower_acquisition_range",
    M.tower_attack_range
)
M.repair_detection_range = M.number(
    "repair_detection_range",
    FIND_UNITS_EVERYWHERE or 99999
)

return M