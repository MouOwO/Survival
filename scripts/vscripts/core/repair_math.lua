local M = {}

function M.amount_for_interval(max_health, pct_per_second, interval)
    local health = math.max(0, tonumber(max_health) or 0)
    local pct = math.max(0, tonumber(pct_per_second) or 0)
    local seconds = math.max(0, tonumber(interval) or 0)
    return health * pct / 100 * seconds
end

function M.whole_amount_for_interval(
    max_health,
    pct_per_second,
    interval,
    remainder
)
    local pending = math.max(0, tonumber(remainder) or 0)
        + M.amount_for_interval(max_health, pct_per_second, interval)
    local whole = math.floor(pending + 0.000000001)
    return whole, math.max(0, pending - whole)
end

return M