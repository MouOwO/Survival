-- Keep all combat formulas configured while admitting only the initial four modes.
local M = {}
local released = { standard = true, cold = true, rich = true, pure = true }
local known = { standard = true, cold = true, rich = true, pure = true,
    scourge = true, ruins = true, celestial = true, fishing = true }
function M.is_released(mode) return released[mode] == true end
function M.is_known(mode) return known[mode] == true end
return M
