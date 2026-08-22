local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function source_player_id(payload)
    return tonumber(payload and payload.PlayerID)
end

local function send(player_id, event_name, payload)
    if not valid_player_id(player_id) then
        return
    end
    local player = PlayerResource:GetPlayer(player_id)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(
            player,
            event_name,
            payload
        )
    end
end

local function snapshot(player_id)
    return event_bus.request(
        events.HERO_SUMMON_SNAPSHOT_REQUEST,
        { player_id = player_id }
    )
end

local function register_snapshot()
    CustomGameEventManager:RegisterListener(
        "ui_hero_summon_snapshot_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then
                return
            end
            local result = snapshot(player_id)
            send(
                player_id,
                "ui_hero_summon_state",
                result and result.snapshot or {
                    hero_summoned = 0,
                    shop_unlocked = 0,
                    heroes = {},
                }
            )
        end
    )
end

local function register_summon()
    CustomGameEventManager:RegisterListener(
        "ui_hero_summon_request",
        function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then
                return
            end
            local result = event_bus.request(
                events.HERO_SUMMON_REQUEST,
                {
                    player_id = player_id,
                    hero_id = tostring(payload.hero_id or ""),
                }
            ) or {
                ok = false,
                error = "hero_summon_handler_missing",
            }
            send(player_id, "ui_hero_summon_operation_result", result)
            if result.snapshot then
                send(
                    player_id,
                    "ui_hero_summon_state",
                    result.snapshot
                )
            end
        end
    )
end

local function on_altar_open(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return
    end
    local result = snapshot(player_id)
    send(player_id, "ui_hero_altar_open", {
        snapshot = result and result.snapshot or {},
    })
end

local function on_state_changed(payload)
    send(payload.player_id, "ui_hero_summon_state", payload)
end

local function on_shop_unlock(payload)
    send(payload.player_id, "ui_shop_unlock_state", payload)
    if tonumber(payload.unlocked) == 1 then
        send(payload.player_id, "ui_notification", {
            message = "英雄已召唤，装备商店已解锁",
            level = "info",
        })
    end
end

function M.init()
    register_snapshot()
    register_summon()
    event_bus.subscribe(events.HERO_ALTAR_OPEN_REQUEST, on_altar_open)
    event_bus.subscribe(
        events.HERO_SUMMON_STATE_CHANGED,
        on_state_changed
    )
    event_bus.subscribe(events.SHOP_UNLOCK_CHANGED, on_shop_unlock)
end

return M
