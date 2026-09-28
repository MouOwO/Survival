-- Explicit units: percentage is presentation; frequency remains gameplay data.
local M = {}
local function sum(rows)
    local value = 0
    for _, row in ipairs(rows or {}) do value = value + (tonumber(row.value) or 0) end
    return value
end
function M.calculate(base, reductions, bonuses, floor)
    local reduced = math.max(floor or 0.05, base - sum(reductions))
    local pct = math.max(1, 100 + sum(bonuses))
    local interval = math.max(floor or 0.05, reduced * 100 / pct)
    return interval, {base_interval=base, reduced_interval=reduced,
        interval_reductions=reductions, speed_bonuses=bonuses, percentage=pct}
end
function M.project(detail, frequency)
    detail = detail or {}
    local rate = tonumber(frequency) or 0
    local pct = tonumber(detail.percentage) or 100
    local reduced = tonumber(detail.reduced_interval)
    if reduced and rate > 0 then pct = rate * reduced * 100 end
    return {percentage=pct, base_interval=tonumber(detail.base_interval),
        reduced_interval=reduced, attack_interval=rate > 0 and 1/rate or 0,
        attacks_per_second=rate, interval_reductions=detail.interval_reductions or {},
        speed_bonuses=detail.speed_bonuses or {},
        runtime_bonus_pct=pct-(tonumber(detail.percentage) or pct), unit="percent"}
end
return M
