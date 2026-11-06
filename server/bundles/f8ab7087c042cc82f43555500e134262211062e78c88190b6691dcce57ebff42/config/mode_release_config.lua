-- Keep all combat formulas configured while admitting only the initial four modes.
local M = {}
-- Temporary read-only acceptance: each new match opens all released-mode tiers,
-- bypasses entry clears/quotas, and isolates account writes. Set false and start
-- a new match to restore normal admission, progression and settlement.
M.all_difficulties_unlocked = true
local released = { standard = true, cold = true, rich = true, pure = true }
local known = { standard = true, cold = true, rich = true, pure = true,
    scourge = true, ruins = true, celestial = true, fishing = true }
function M.is_released(mode) return released[mode] == true end
function M.is_known(mode) return known[mode] == true end
function M.is_difficulty_open(mode)
    return M.all_difficulties_unlocked == true and M.is_released(mode)
end
return M
