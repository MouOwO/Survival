-- Runtime challenge lifecycle rules. Rebirth encounters are intentionally not
-- listed: they remain one-time progression challenges.
local M = {}

M.rows = {}
M.by_id = {}

local function add(challenge_id, completion_limit)
    local row = {
        challenge_id = challenge_id,
        repeatable = true,
        respawn_seconds = 2,
        completion_limit = completion_limit or 0,
    }
    M.rows[#M.rows + 1] = row
    M.by_id[challenge_id] = row
end

for index = 1, 10 do
    add(string.format("challenge_%02d", index))
end
add("challenge_11", 10)

function M.apply(config)
    for _, challenge in ipairs(config and config.rows or {}) do
        local rule = M.by_id[challenge.challenge_id]
        if rule then
            challenge.repeatable = rule.repeatable
            challenge.respawn_seconds = rule.respawn_seconds
            challenge.completion_limit = rule.completion_limit
        end
    end
    return config
end

return M