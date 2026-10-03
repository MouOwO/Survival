-- UI-only next-hit forecasts. Never applies damage or mutates health.
local M = {}
local function exists(unit) return unit and (not unit.IsNull or not unit:IsNull()) end
local function changed(unit)
    unit.survival_laser_forecast_revision = (unit.survival_laser_forecast_revision or 0) + 1
end
function M.clear(owner)
    local target = owner.laser_forecast_target
    owner.laser_forecast_target = nil
    if not exists(target) then return end
    local entries = target.survival_laser_forecasts
    if entries and entries[owner] then entries[owner] = nil; changed(target) end
end
function M.record(owner, target, health_before, multiplier, next_multiplier, interval)
    M.clear(owner)
    if not exists(target) or not target:IsAlive() or owner.laser_target ~= target
        or not target.GetHealth or not health_before or multiplier <= 0 then return end
    -- Native health delta includes armor, shields and endless-stat projection.
    -- Extrapolate only the next hit, correcting on every real settlement.
    local lost = math.max(0, health_before - target:GetHealth())
    if lost <= 0 then return end
    local now = GameRules:GetGameTime()
    local due = math.max(now + 0.001,
        (owner.last_interval_time or now) + interval - (owner.laser_elapsed or 0))
    local entries = target.survival_laser_forecasts or {}
    target.survival_laser_forecasts = entries
    entries[owner] = {start=now, due=due, damage=lost * next_multiplier / multiplier}
    owner.laser_forecast_target = target
    changed(target)
end
function M.snapshot(unit, maximum, now)
    local result = {}
    for owner, entry in pairs(unit.survival_laser_forecasts or {}) do
        if now > entry.due + 0.15 or not unit:IsAlive() then
            unit.survival_laser_forecasts[owner] = nil
            if owner.laser_forecast_target == unit then owner.laser_forecast_target = nil end
            changed(unit)
        else
            result[#result+1] = {start=entry.start, due=entry.due, fraction=entry.damage / maximum}
        end
    end
    return result, unit.survival_laser_forecast_revision or 0
end
return M
