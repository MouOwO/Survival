local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
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

local function source_player_id(payload)
    return tonumber(payload and payload.PlayerID)
end

local function on_start_request(_, payload)
    local player_id = source_player_id(payload)
    if not valid_player_id(player_id) then
        return
    end

    local result = event_bus.request(
        events.MONSTER_ENCOUNTER_START_REQUEST,
        {
            player_id = player_id,
            team = PlayerResource:GetTeam(player_id),
            encounter_id = tostring(payload.encounter_id or ""),
        }
    ) or {
        ok = false,
        error = "encounter_handler_missing",
    }

    send(player_id, "ui_monster_encounter_operation_result", result)
end

local function on_query_request(_, payload)
    local player_id = source_player_id(payload)
    if not valid_player_id(player_id) then
        return
    end

    local result = event_bus.request(
        events.MONSTER_ENCOUNTER_QUERY_REQUEST,
        {
            player_id = player_id,
            encounter_id = tostring(payload.encounter_id or ""),
        }
    ) or {
        ok = false,
        error = "encounter_handler_missing",
    }

    send(player_id, "ui_monster_encounter_operation_result", result)
end

local function on_encounter_changed(payload)
    send(
        tonumber(payload.player_id),
        "ui_monster_encounter_state",
        payload
    )
end

local function on_reward_granted(payload)
    send(
        tonumber(payload.player_id),
        "ui_monster_reward_granted",
        payload
    )
end

local function on_progression_changed(payload)
    send(
        tonumber(payload.player_id),
        "ui_hero_progression_state",
        payload
    )
end

function M.init()
    CustomGameEventManager:RegisterListener(
        "ui_monster_encounter_start_request",
        on_start_request
    )
    CustomGameEventManager:RegisterListener(
        "ui_monster_encounter_query_request",
        on_query_request
    )
    event_bus.subscribe(
        events.MONSTER_ENCOUNTER_CHANGED,
        on_encounter_changed
    )
    event_bus.subscribe(
        events.MONSTER_REWARD_GRANTED,
        on_reward_granted
    )
    event_bus.subscribe(
        events.HERO_PROGRESSION_CHANGED,
        on_progression_changed
    )
end

return M
