local M = {}

function M.interval(tower, skill)
    local configured = math.max(0.1, tonumber(skill and skill.damage_interval) or 1)
    -- These project-owned values already include archive/research haste and interval reductions.
    -- Preserve the configured beam cadence at zero bonuses instead of replacing it with tower BAT.
    local base = tonumber(tower and tower.survival_research_base_attack_time)
    local current = tonumber(tower and tower.survival_attack_interval)
    local ratio = base and current and base > 0 and current > 0 and base / current or 1
    return math.max(0.01, configured / ratio)
end

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