local M = {}
local deferred_serial = 0
local generation_by_unit = setmetatable({}, { __mode = "k" })

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

local function next_generation(unit)
    local generation = (generation_by_unit[unit] or 0) + 1
    generation_by_unit[unit] = generation
    return generation
end

local function schedule_refill_checks(unit, health, source, generation)
    if not GameRules or not GameRules.GetGameTime then return end
    local ok, scheduler = pcall(require, "core/scheduler")
    if not ok or not scheduler or not scheduler.after then return end
    deferred_serial = deferred_serial + 1
    local prefix = "hero_health_guard_" .. tostring(deferred_serial)
    scheduler.after(0, function()
        if generation_by_unit[unit] ~= generation then return end
        restore_if_refilled(unit, health, source, "next_tick", true)
    end, prefix .. "_next")
    scheduler.after(0.12, function()
        if generation_by_unit[unit] ~= generation then return end
        restore_if_refilled(unit, health, source, "delayed", true)
    end, prefix .. "_delayed")
end

-- Dota may adjust current health after attributes or health-bonus modifiers are
-- recalculated, including one engine tick after CalculateStatBonus returns.
-- Never heal here: only lower an unexpected refill back to the captured value.
function M.protect_value(unit, health, source)
    if not valid(unit) then return false end
    -- A newer protection supersedes all deferred checks created by an older
    -- stat refresh. This also gives legitimate healing a way to invalidate a
    -- pending rollback before it changes the hero's health.
    local generation = next_generation(unit)
    local restored = restore_if_refilled(unit, health, source, "immediate", false)
    schedule_refill_checks(unit, health, source, generation)
    return restored
end

-- Call immediately before an intentional heal. A delayed stat-refresh guard
-- cannot distinguish an engine refill from lifesteal merely by seeing full HP,
-- so intentional healing explicitly invalidates older deferred checks.
function M.allow_healing(unit)
    if not valid(unit) then return false end
    next_generation(unit)
    return true
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

-- Preserve damage already taken while allowing a maximum-health bonus to add
-- the same amount to current health. A full-health hero therefore stays full,
-- while a hero missing 1000 HP remains missing exactly 1000 HP.
function M.preserve_missing(unit, callback, source)
    if not valid(unit) or type(callback) ~= "function" then return false end
    local alive = unit.IsAlive and unit:IsAlive()
    local health = alive and unit.GetHealth and unit:GetHealth() or nil
    local maximum = alive and unit.GetMaxHealth and unit:GetMaxHealth() or nil
    local missing = health and maximum
        and math.max(0, maximum - health) or nil
    local ok, result = pcall(callback)
    if alive and health and health > 0 and missing ~= nil
        and valid(unit) and unit.IsAlive and unit:IsAlive() then
        local next_maximum = math.max(1, tonumber(unit:GetMaxHealth()) or 1)
        local desired = math.max(1, math.min(next_maximum, next_maximum - missing))
        local current = math.max(0, tonumber(unit:GetHealth()) or 0)
        if math.abs(current - desired) > 0.5 then
            unit:SetHealth(desired)
        end
        M.protect_value(unit, desired, source or "preserve_missing")
    end
    if not ok then error(result) end
    return result
end

return M