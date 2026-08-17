local runtime = require("systems/rogue_effect_runtime_service")

local M = {}
local next_compat_grant = 0

function M.apply(player_id, card_id)
    next_compat_grant = next_compat_grant + 1
    return runtime.grant(player_id, card_id,
        "compat:" .. tostring(player_id) .. ":" .. tostring(next_compat_grant))
end

function M.init()
    next_compat_grant = 0
    runtime.init()
end

M.grant = runtime.grant
M.snapshot = runtime.snapshot

return M