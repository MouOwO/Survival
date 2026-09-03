local event_bus = require("core/event_bus")
local events = require("core/events")
local player_tower_limits = require("systems/player_tower_limit_service")

local M = {}

local function non_negative(value)
    return math.max(0, tonumber(value) or 0)
end

function M.bonus(player_id, building_id)
    if tostring(building_id or "") ~= "gold_mine" or player_id == nil then
        return 0
    end
    local ok, effects = pcall(
        event_bus.request,
        events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
        { player_id = tonumber(player_id) }
    )
    if not ok then return 0 end
    return non_negative(effects and effects.totals
        and effects.totals.gold_mine_build_cap)
end

-- Building definitions and Builder stage rows both store the base limit.
-- Profile field gold_mine_build_cap is an expansion amount, never a replacement.
function M.maximum(base_maximum, building_id, player_id)
    local base = tonumber(base_maximum) or 0
    if base <= 0 then return base end
    return base + M.bonus(player_id, building_id)
end

function M.reached(base_maximum, current, building_id, player_id)
    return player_tower_limits.limit_reached(
        M.maximum(base_maximum, building_id, player_id),
        current
    )
end

return M
