local event_bus = require("core/event_bus")
local events = require("core/events")
local compact_transport = require("ui/compact_ui_transport")

local M = {}
local shop_unlocked_by_player = {}
local legacy_players = {}
local initialized_generation

local function generation()
    return event_bus.get_generation()
end

local function current(expected)
    return initialized_generation == expected and generation() == expected
end

local function guarded(expected, callback)
    return function(...)
        if current(expected) then return callback(...) end
    end
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function source_player_id(payload)
    return tonumber(payload and payload.PlayerID)
end

-- The loaded HUD uses the altar's real native abilities and private ability
-- NetTables. No current UI consumes the old six-hero catalogue. Only an actual
-- old-protocol request subscribes; profile/altar events before Hello do not.
local function legacy_subscribed(player_id)
    if not valid_player_id(player_id) then return false end
    if compact_transport.is_bound(player_id) then
        legacy_players[player_id] = nil
        return false
    end
    local player = PlayerResource:GetPlayer(player_id)
    if player and legacy_players[player_id] == player then return true end
    legacy_players[player_id] = nil
    return false
end

local function subscribe_legacy(player_id)
    if not valid_player_id(player_id) then return false end
    if compact_transport.is_bound(player_id) then
        legacy_players[player_id] = nil
        return false
    end
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return false end
    legacy_players[player_id] = player
    return true
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

local function send_legacy(player_id, event_name, payload)
    if legacy_subscribed(player_id) then send(player_id, event_name, payload) end
end

local function register_snapshot(expected)
    CustomGameEventManager:RegisterListener(
        "ui_hero_summon_snapshot_request",
        guarded(expected, function(_, payload)
            local player_id = source_player_id(payload)
            if not subscribe_legacy(player_id) then
                return
            end
            local owner = legacy_players[player_id]
            local result = snapshot(player_id)
            if not current(expected) or PlayerResource:GetPlayer(player_id) ~= owner then return end
            send_legacy(
                player_id,
                "ui_hero_summon_state",
                result and result.snapshot or {
                    hero_summoned = 0,
                    shop_unlocked = 0,
                    heroes = {},
                }
            )
        end)
    )
end

local function register_summon(expected)
    CustomGameEventManager:RegisterListener(
        "ui_hero_summon_request",
        guarded(expected, function(_, payload)
            local player_id = source_player_id(payload)
            if not valid_player_id(player_id) then
                return
            end
            subscribe_legacy(player_id)
            local owner = PlayerResource:GetPlayer(player_id)
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
            if not current(expected) or PlayerResource:GetPlayer(player_id) ~= owner then return end
            send_legacy(player_id, "ui_hero_summon_operation_result", result)
            if result.snapshot then
                send_legacy(
                    player_id,
                    "ui_hero_summon_state",
                    result.snapshot
                )
            end
        end)
    )
end

local function on_altar_open(payload)
    local expected = generation()
    local player_id = tonumber(payload.player_id)
    if not legacy_subscribed(player_id) then
        return
    end
    local owner = legacy_players[player_id]
    local result = snapshot(player_id)
    if not current(expected) or PlayerResource:GetPlayer(player_id) ~= owner then return end
    send_legacy(player_id, "ui_hero_altar_open", {
        snapshot = result and result.snapshot or {},
    })
end

local function on_state_changed(payload)
    send_legacy(payload.player_id, "ui_hero_summon_state", payload)
end

local function on_shop_unlock(payload)
    local player_id = tonumber(payload and payload.player_id)
    local unlocked = tonumber(payload and payload.unlocked) == 1
    if not valid_player_id(player_id) then return end
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return end
    local previous = shop_unlocked_by_player[player_id]
    if previous and previous.player == player and previous.unlocked == unlocked then return end
    local was_unlocked = previous and previous.player == player and previous.unlocked == true
    shop_unlocked_by_player[player_id] = { player = player, unlocked = unlocked }
    send(player_id, "ui_shop_unlock_state", payload)
    if unlocked and not was_unlocked then
        send(payload.player_id, "ui_notification", {
            message = "英雄已召唤，装备商店已解锁",
            level = "info",
        })
    end
end

function M.init()
    local expected = generation()
    if initialized_generation == expected then return end
    initialized_generation = expected
    shop_unlocked_by_player = {}
    legacy_players = {}
    register_snapshot(expected)
    register_summon(expected)
    event_bus.subscribe(events.HERO_ALTAR_OPEN_REQUEST, guarded(expected, on_altar_open))
    event_bus.subscribe(
        events.HERO_SUMMON_STATE_CHANGED,
        guarded(expected, on_state_changed)
    )
    event_bus.subscribe(events.SHOP_UNLOCK_CHANGED, guarded(expected, on_shop_unlock))
end

return M
