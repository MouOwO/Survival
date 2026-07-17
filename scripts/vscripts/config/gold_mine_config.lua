local M = {
    max_level = 10,
    base_gold_per_efficiency = 5,
    production_interval = 1.0,

    -- Temporary economy curve. Centralized here for later balance changes.
    efficiency_upgrade_gold_per_level = 50,

    max_crit_level = 10,
    crit_chance_per_level = 2,
    crit_multiplier = 1.5,
    crit_upgrade_gold_per_level = 10,
}

function M.efficiency_upgrade_cost(current_level)
    local next_level = math.min(M.max_level, current_level + 1)
    return {
        wood = 0,
        gold = M.efficiency_upgrade_gold_per_level * math.max(1, next_level - 1),
    }
end

function M.crit_upgrade_cost(current_level)
    local next_level = math.min(M.max_crit_level, current_level + 1)
    return {
        wood = 0,
        gold = M.crit_upgrade_gold_per_level * next_level,
    }
end

function M.normal_income(efficiency_level)
    return M.base_gold_per_efficiency * math.max(1, efficiency_level or 1)
end

function M.crit_chance(crit_level)
    return M.crit_chance_per_level * math.max(0, crit_level or 0)
end

return M
