-- Keep all combat formulas configured while admitting only the initial four modes.
local M = {}
-- Acceptance testing: open configured tiers without changing saved clears or
-- mode admission. Set false to restore the normal sequential unlock policy.
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
