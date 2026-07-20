local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function source_player_id(payload)
    -- Panorama-to-server custom events inject PlayerID. Never trust a custom
    -- player_id field supplied by the client.
    return tonumber(payload and payload.PlayerID)
end

local function send_to_player(event_name, player_id, payload)
    if not valid_player_id(player_id) then return end
    local player = PlayerResource:GetPlayer(player_id)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, event_name, payload)
    end
end

local function register_snapshot_request()
    CustomGameEventManager:RegisterListener("ui_request_full_snapshot", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        event_bus.emit(events.UI_SNAPSHOT_REQUESTED, {
            player_id = player_id,
            request_id = payload.request_id,
        })
        send_to_player("ui_operation_result", player_id, {
            request_id = payload.request_id or "",
            success = 1,
            operation = "full_snapshot",
        })
    end)
end

local function register_shop_open_request()
    CustomGameEventManager:RegisterListener("ui_shop_open_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local result = event_bus.request(events.SHOP_OPEN_REQUEST, {
            player_id = player_id,
            request_id = payload.request_id,
            known_sequence = tonumber(payload.known_sequence) or 0,
        })
        if result and result.ok and result.snapshot then
            send_to_player("ui_shop_snapshot", player_id, result.snapshot)
            return
        end
        send_to_player("ui_operation_result", player_id, {
            request_id = payload.request_id or "",
            success = 0,
            operation = "shop_open",
            error = result and result.error or "shop_snapshot_failed",
        })
    end)
end

local function register_shop_close_request()
    CustomGameEventManager:RegisterListener("ui_shop_close_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        event_bus.request(events.SHOP_CLOSE_REQUEST, {
            player_id = player_id,
            request_id = payload.request_id,
        })
    end)
end

local function register_shop_purchase_request()
    CustomGameEventManager:RegisterListener("ui_shop_purchase_request", function(_, payload)
        local player_id = source_player_id(payload)
        if not valid_player_id(player_id) then return end
        local result = event_bus.request(events.SHOP_PURCHASE_REQUEST, {
            player_id = player_id,
            entry_id = tostring(payload.entry_id or ""),
            request_id = payload.request_id,
        })
        send_to_player("ui_operation_result", player_id, {
            request_id = payload.request_id or "",
            success = result and result.ok and 1 or 0,
            operation = "shop_purchase",
            entry_id = payload.entry_id or "",
            error = result and result.error or "unknown_error",
        })
    end)
end

local function on_notification(payload)
    send_to_player("ui_notification", payload.player_id, {
        message = payload.message or "",
        level = payload.level or "info",
    })
end

local function on_shop_state_changed(payload)
    if not payload or not payload.snapshot then return end
    send_to_player("ui_shop_snapshot", payload.player_id, payload.snapshot)
end

function M.init()
    register_snapshot_request()
    register_shop_open_request()
    register_shop_close_request()
    register_shop_purchase_request()
    event_bus.subscribe(events.UI_NOTIFICATION, on_notification)
    event_bus.subscribe(events.SHOP_STATE_CHANGED, on_shop_state_changed)
end

return M
