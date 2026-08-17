local M = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function M.maximum_with_flat_bonus(base_health, bonus_pct, flat_bonus)
    return math.max(1, math.floor(
        (tonumber(base_health) or 1) * (1 + (tonumber(bonus_pct) or 0) / 100)
            + math.max(0, tonumber(flat_bonus) or 0)
    ))
end

function M.apply_maximum_health_increase(unit, apply_maximum_health)
    local old_maximum = math.max(1, tonumber(unit:GetMaxHealth()) or 1)
    local old_current = clamp(tonumber(unit:GetHealth()) or 1, 1, old_maximum)

    apply_maximum_health()

    local new_maximum = math.max(1, tonumber(unit:GetMaxHealth()) or 1)
    local maximum_increase = new_maximum - old_maximum
    local new_current = clamp(old_current + maximum_increase, 1, new_maximum)
    unit:SetHealth(new_current)
    return new_current, new_maximum, maximum_increase
end

return M