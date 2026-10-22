-- The workbook exceeds native integer health and float damage limits. Keep
-- authored values in Lua doubles and project combat into bounded engine values.
local M = {}
local CAP = 100000000
function M.is_finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end
local function finite(value, label)
    value = tonumber(value) or 0
    assert(M.is_finite(value), "invalid finite " .. tostring(label))
    return value
end
-- Some summons already own a separate health projection. Limit only their
-- native attack setters and let the shared damage filter restore each hit.
function M.prepare_attack(unit, minimum, maximum, critical_multiplier)
    minimum = math.max(0, finite(minimum, "attack minimum"))
    maximum = math.max(minimum, finite(maximum or minimum, "attack maximum"))
    local critical = math.max(1, finite(critical_multiplier or 1, "critical multiplier"))
    local scale = math.max(1, maximum / math.max(1, math.floor(CAP / critical)))
    assert(M.is_finite(scale), "invalid finite attack scale")
    unit.survival_endless_attack_scale = scale
    unit.survival_endless_attack = maximum
    return minimum / scale, maximum / scale
end

-- Every native component uses the same scale, including equipment's separate
-- modifier. Absolute values protect native intermediate sums when a final
-- debug override cancels a large equipment bonus with a negative weapon bonus.
function M.prepare_attack_components(unit, minimum, maximum, weapon, research,
        equipment, critical_multiplier)
    minimum, maximum = finite(minimum, "base attack minimum"), finite(maximum, "base attack maximum")
    weapon, research = finite(weapon, "weapon attack"), finite(research, "research attack")
    equipment = finite(equipment, "equipment attack")
    local critical = math.max(1, finite(critical_multiplier or 1, "critical multiplier"))
    local capacity = math.max(math.abs(minimum), math.abs(maximum))
        + math.abs(weapon) + math.abs(research) + math.abs(equipment)
    assert(M.is_finite(capacity), "invalid finite total attack")
    -- Base-damage setters store integers. Reserve one native point for their
    -- midpoint remainder so neither endpoint plus a critical exceeds CAP.
    local scale = math.max(1, capacity / math.max(1, math.floor(CAP / critical) - 1))
    assert(M.is_finite(scale), "invalid finite attack scale")
    unit.survival_endless_attack_scale = scale
    unit.survival_endless_attack = math.max(minimum, maximum) + weapon + research + equipment
    local projected_min, projected_max = minimum / scale, maximum / scale
    local native_min, native_max = math.floor(projected_min), math.floor(projected_max)
    -- A single bonus preserves the exact midpoint despite integer setters.
    -- The endpoints retain at most half a native point of range error.
    local remainder = scale > 1
        and ((projected_min - native_min) + (projected_max - native_max)) * 0.5 or 0
    return { scale = scale, minimum = native_min, maximum = native_max,
        weapon = weapon / scale + remainder,
        research = research / scale, equipment = equipment / scale }
end

function M.prepare(unit, row)
    local health, attack = finite(row.health, "health"), finite(row.attack, "attack")
    assert(health > 0 and attack >= 0, "invalid health or attack")
    unit.survival_exact_stat_projection = nil
    unit.survival_endless_health_scale = math.max(1, health / CAP)
    unit.survival_endless_attack_scale = math.max(1, attack / CAP)
    unit.survival_endless_health = health
    unit.survival_endless_attack = attack
    local result = {}
    for key, value in pairs(row) do result[key] = value end
    result.health = health / unit.survival_endless_health_scale
    result.attack = attack / unit.survival_endless_attack_scale
    return result
end

-- Authored formulas keep their Lua doubles even when a native setter stores
-- integers. Recover that logical value in DamageFilter/UI through the same
-- scale boundary as endless units, including ordinary-sized fractional stats.
function M.prepare_exact(unit, row)
    local health, attack = tonumber(row.health), tonumber(row.attack)
    assert(M.is_finite(health) and M.is_finite(attack)
        and health > 0 and attack >= 0, "invalid health or attack")
    local native_health = math.min(CAP, math.max(1, math.floor(health)))
    -- Native damage events use floats: every integer through 2^24 is exact.
    local native_attack = attack == 0 and 0
        or math.min(16777216, math.max(1, math.floor(attack)))
    unit.survival_exact_stat_projection = true
    unit.survival_endless_health_scale = health / native_health
    unit.survival_endless_attack_scale = attack == 0 and 1 or attack / native_attack
    unit.survival_endless_health = health
    unit.survival_endless_attack = attack
    local result = {}
    for key, value in pairs(row) do result[key] = value end
    result.health, result.attack = native_health, native_attack
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
