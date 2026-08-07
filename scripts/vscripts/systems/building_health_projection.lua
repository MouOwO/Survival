local M = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function M.apply_preserved_ratio(unit, apply_maximum_health)
    local old_maximum = math.max(1, tonumber(unit:GetMaxHealth()) or 1)
    local old_current = clamp(tonumber(unit:GetHealth()) or 1, 1, old_maximum)
    local ratio = old_current / old_maximum

    apply_maximum_health()

    local new_maximum = math.max(1, tonumber(unit:GetMaxHealth()) or 1)
    local new_current = clamp(math.floor(new_maximum * ratio + 0.5), 1, new_maximum)
    unit:SetHealth(new_current)
    return new_current, new_maximum, ratio
end

return M