local hero_health_guard = require("core/hero_health_guard")

local M = {}

local function finite_number(value)
    local result = tonumber(value)
    if not result or result ~= result
        or result == math.huge or result == -math.huge then
        return nil
    end
    return result
end

function M.parse(argument)
    local text = tostring(argument or "")
    if text == "" or not string.match(text, "^[+-]") then
        return nil, "usage: blood <+amount|-amount|+percent%|-percent%>"
    end
    local percent = string.sub(text, -1) == "%"
    local numeric_text = percent and string.sub(text, 1, -2) or text
    local amount = finite_number(numeric_text)
    if not amount then
        return nil, "usage: blood <+amount|-amount|+percent%|-percent%>"
    end
    return { amount = amount, percent = percent }
end

function M.apply(unit, argument)
    local change, error_code = M.parse(argument)
    if not change then return nil, error_code end
    if not unit or unit:IsNull() or not unit.GetHealth
        or not unit.GetMaxHealth or not unit.SetHealth then
        return nil, "hero_not_summoned"
    end

    local maximum = math.max(1, finite_number(unit:GetMaxHealth()) or 1)
    local before = math.max(1, finite_number(unit:GetHealth()) or 1)
    local delta = change.percent
        and maximum * change.amount / 100 or change.amount
    local after = math.max(1, math.min(maximum, before + delta))
    if after > before then hero_health_guard.allow_healing(unit) end
    unit:SetHealth(after)
    return {
        before = before,
        after = after,
        maximum = maximum,
        delta = after - before,
        percent = change.percent,
    }
end

return M