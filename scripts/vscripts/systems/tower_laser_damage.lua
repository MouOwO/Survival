local M = {}

function M.multiplier(base_multiplier, increment, maximum, completed_ticks,
        interval)
    local completed_seconds = math.floor(
        math.max(0, completed_ticks or 0) * interval + 0.001
    )
    return math.min(
        maximum, base_multiplier + completed_seconds * increment
    )
end

return M