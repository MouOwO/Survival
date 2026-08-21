local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

function M.grant_level(state, level, reason)
    local levels = state and state.definition and state.definition.levels or {}
    local data = levels[tonumber(level) or 1] or {}
    local amount = math.max(0, tonumber(data.add_population) or 0)
    if amount <= 0 then return 0 end

    event_bus.request(events.RESOURCE_ADD_REQUEST, {
        player_id = state.player_id,
        team = state.team,
        max_population = amount,
        reason = reason or "building_level_population",
    })
    return amount
end

return M