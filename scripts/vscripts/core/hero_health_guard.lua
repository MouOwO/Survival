local M = {}
local deferred_serial = 0

local function valid(unit)
    return unit and not unit:IsNull()
end

local function restore_if_refilled(unit, health, source, phase, full_only)
    if not valid(unit) or not unit.IsAlive or not unit:IsAlive()
        or not unit.GetHealth or not unit.GetMaxHealth or not unit.SetHealth
        or not health or health <= 0 then return false end
    local maximum = math.max(1, tonumber(unit:GetMaxHealth()) or 1)
    local current = math.max(0, tonumber(unit:GetHealth()) or 0)
    local desired = math.max(1, math.min(health, maximum))
    if current <= desired + 0.5 then return false end
    -- Deferred checks only undo the reported engine refill-to-full behavior.
    -- They must not erase normal regeneration or lifesteal that happens later.
    if full_only and current < maximum - 0.5 then return false end
    print(string.format(
        "[HERO_HEALTH_GUARD] source=%s phase=%s entindex=%s "
            .. "health=%.1f->%.1f max=%.1f",
        tostring(source or "unknown"), tostring(phase or "immediate"),
        tostring(unit.entindex and unit:entindex() or -1),
        current, desired, maximum
    ))
    unit:SetHealth(desired)
    return true
end

local function schedule_refill_checks(unit, health, source)
    if not GameRules or not GameRules.GetGameTime then return end
    local ok, scheduler = pcall(require, "core/scheduler")
    if not ok or not scheduler or not scheduler.after then return end
    deferred_serial = deferred_serial + 1
    local prefix = "hero_health_guard_" .. tostring(deferred_serial)
    scheduler.after(0, function()
        restore_if_refilled(unit, health, source, "next_tick", true)
    end, prefix .. "_next")
    scheduler.after(0.12, function()
        restore_if_refilled(unit, health, source, "delayed", true)
    end, prefix .. "_delayed")
end

-- Dota may adjust current health after attributes or health-bonus modifiers are
-- recalculated, including one engine tick after CalculateStatBonus returns.
-- Never heal here: only lower an unexpected refill back to the captured value.
function M.protect_value(unit, health, source)
    if not valid(unit) then return false end
    local restored = restore_if_refilled(unit, health, source, "immediate", false)
    schedule_refill_checks(unit, health, source)
    return restored
end

function M.preserve_current(unit, callback, source)
    if not valid(unit) or type(callback) ~= "function" then return false end
    local alive = unit.IsAlive and unit:IsAlive()
    local health = alive and unit.GetHealth and unit:GetHealth() or nil
    local ok, result = pcall(callback)
    if alive and health and health > 0 then
        M.protect_value(unit, health, source or "preserve_current")
    end
    if not ok then error(result) end
    return result
end

return M