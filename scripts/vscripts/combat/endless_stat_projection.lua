-- The workbook exceeds native integer health and float damage limits. Keep
-- authored values in Lua doubles and project combat into bounded engine values.
local M = {}
local CAP = 100000000
function M.prepare(unit, row)
    unit.survival_endless_health_scale = math.max(1, row.health / CAP)
    unit.survival_endless_attack_scale = math.max(1, row.attack / CAP)
    unit.survival_endless_health = row.health
    unit.survival_endless_attack = row.attack
    local result = {}
    for key, value in pairs(row) do result[key] = value end
    result.health = row.health / unit.survival_endless_health_scale
    result.attack = row.attack / unit.survival_endless_attack_scale
    return result
end
function M.outgoing(unit, damage, basic)
    if not basic then return damage end
    return damage * (tonumber(unit.survival_endless_attack_scale) or 1)
end
function M.incoming(unit, damage)
    return damage / (tonumber(unit.survival_endless_health_scale) or 1)
end
-- Strings preserve large logical values across engine network serialization.
-- Ordinary units keep their existing numeric payloads.
function M.for_ui(unit, value, stat)
    local scale = tonumber(unit["survival_endless_" .. stat .. "_scale"])
    if not scale then return value end
    return string.format("%.17g", value * scale)
end
return M
