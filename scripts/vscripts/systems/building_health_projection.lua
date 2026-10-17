local M = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function M.maximum_with_flat_bonus(base_health, bonus_pct, flat_bonus)
    local base = tonumber(base_health) or 1
    -- Adding the base separately avoids losing an integer HP to the binary
    -- rounding of (1 + percent / 100) before floor is applied.
    local percentage = base * (tonumber(bonus_pct) or 0) / 100
    local flat = math.max(0, tonumber(flat_bonus) or 0)
    local projected = base + percentage + flat
    if projected == projected and projected ~= math.huge and projected ~= -math.huge then
        local next_integer = math.floor(projected) + 1
        local shortfall = next_integer - projected
        -- Correct only a few floating-point rounding units immediately below
        -- an integer. The absolute cap keeps large values from rounding away
        -- legitimate fractions; all other results retain floor semantics.
        local tolerance = math.min(1e-9, 4 * 2^-52 * math.max(
            1, math.abs(base), math.abs(percentage), flat, math.abs(projected)))
        if shortfall > 0 and shortfall <= tolerance then projected = next_integer end
    end
    return math.max(1, math.floor(projected))
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
