local rules = require("config/generated/archive_endless_rules").by_id.default
local groups = require("config/generated/archive_endless_groups")
local waves = require("config/generated/archive_endless_waves")
local M = { rules = rules }
function M.group(difficulty)
    for _, row in ipairs(groups.rows) do
        if row.enabled and difficulty >= row.min_difficulty and difficulty <= row.max_difficulty then return row end
    end
end
function M.wave(difficulty, number)
    local group = M.group(difficulty)
    local row = group and waves.by_id[group.wave_group .. "_" .. number]
    return row and row.enabled and row or nil
end
function M.score(number)
    return rules.score_multiplier * (math.floor((number - 1) / rules.score_block_size) + 1) + rules.score_offset
end
return M
