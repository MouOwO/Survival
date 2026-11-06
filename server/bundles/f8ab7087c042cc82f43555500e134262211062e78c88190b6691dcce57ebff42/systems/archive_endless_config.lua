local rules = require("config/generated/archive_endless_rules").by_id.default
local groups = require("config/generated/archive_endless_groups")
local waves = require("config/generated/archive_endless_waves")
local difficulties = require("config/difficulty_config")
local M = { rules = rules }
function M.allowed(difficulty, mode)
    return type(difficulty) == "number" and difficulty == math.floor(difficulty)
        and difficulty >= 1 and type(mode) == "string"
        and difficulties.get("N" .. difficulty, mode) ~= nil
end
function M.allowed_variant(difficulty, mode, variant)
    variant = variant or "endless"
    return M.allowed(difficulty, mode) and (variant == "endless"
        or variant == "tower" and (mode == "cold" or mode == "scourge") and difficulty >= 10)
end
local function queryable(difficulty, mode)
    if mode then return M.allowed(difficulty, mode) end
    -- The standalone settlement worker queries fixed values without admitting
    -- a match. Runtime admission and HTTP session checks supply the real mode.
    for id in pairs(difficulties.by_mode) do
        if M.allowed(difficulty, id) then return true end
    end
    return false
end
function M.group(difficulty, mode)
    if not queryable(difficulty, mode) then return nil end
    for _, row in ipairs(groups.rows) do
        if row.enabled and difficulty >= row.min_difficulty and difficulty <= row.max_difficulty then return row end
    end
    -- All configured difficulties use the same authored endless attributes.
    -- High tiers reuse that group, without relabelling the match as N20.
    for _, row in ipairs(groups.rows) do
        if row.enabled and row.wave_group == "tier1" then return row end
    end
end
function M.wave(difficulty, number, mode)
    local group = M.group(difficulty, mode)
    local row = group and waves.by_id[group.wave_group .. "_" .. number]
    return row and row.enabled and row or nil
end
function M.score(number, variant)
    local base = rules.score_multiplier * (math.floor((number - 1) / rules.score_block_size) + 1) + rules.score_offset
    return base * (variant == "tower" and (tonumber(rules.tower_score_multiplier) or 2) or 1)
end
return M
