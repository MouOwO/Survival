-- Match-local projections of owned privileges. Never add EX multipliers to
-- saved percentage stats: they multiply the complete live hero independently.
local commerce = require("systems/commerce_effects")
local M = {}
local GRIEF_SEED = "commerce_p147"

function M.for_player(player_id)
    local owned = commerce.owned(player_id, GRIEF_SEED)
    return {
        attribute_multiplier = owned and 1.08 or 1,
        final_damage_multiplier = owned and 1.08 or 1,
        skill_rerolls = owned and 5 or 0,
    }
end

return M
