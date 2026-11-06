-- The backend supplies a secret-derived event seed. Local providers use the
-- same event ID for every recipient without touching the game's global RNG.
local rule = require("config/generated/archive_cooperative_reward_rules").by_id.default
local M = {}
assert(rule and rule.version == 1, "archive_cooperative_policy_invalid")

function M.shared_challenge_roll()
    return rule.enabled == true and rule.shared_challenge_roll == true
end

function M.local_seed(event_id)
    local seed = 1
    for i = 1, #event_id do seed = (seed * 131 + event_id:byte(i)) % 2147483646 end
    return seed + 1
end

function M.random_int(seed)
    assert(type(seed) == "number" and seed >= 1 and seed < 2147483647
        and seed == math.floor(seed), "archive_cooperative_seed_invalid")
    return function(low, high)
        seed = (seed * 48271) % 2147483647
        return low + math.floor((seed / 2147483647) * (high - low + 1))
    end
end

return M
