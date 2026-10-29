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
function M.is_offline_preview()
    -- Only the already-configured, guarded memory-only Tools provider can
    -- open unreleased modes. A convar or generic debug unlock is insufficient.
    local offline = package.loaded["debug/offline_logic_test"]
    return type(offline) == "table" and type(offline.is_enabled) == "function"
        and offline.is_enabled() == true
end
function M.is_available(mode)
    return M.is_released(mode) or M.is_offline_preview() and M.is_known(mode)
end
function M.is_difficulty_open(mode)
    return M.all_difficulties_unlocked == true and M.is_released(mode)
        or M.is_offline_preview() and M.is_known(mode)
end
return M
