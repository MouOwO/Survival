local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function publish(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or not payload.snapshot then
        return
    end
    CustomNetTables:SetTableValue(
        "survival_combat_stats",
        "player_" .. tostring(player_id),
        payload.snapshot
    )
    local player = PlayerResource:GetPlayer(player_id)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(
            player,
            "ui_combat_stats_snapshot",
            payload.snapshot
        )
    end
end

function M.init()
    event_bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, publish)
end

return M
