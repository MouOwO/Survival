local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function valid_player(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function send(player_id, event_name, payload)
    if not valid_player(player_id) then
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

local function register_state_request()
    CustomGameEventManager:RegisterListener(
        "ui_hero_skill_state_request",
        function(_, payload)
            local player_id = tonumber(payload.PlayerID)
            local result = event_bus.request(
                events.HERO_SKILL_STATE_GET_REQUEST,
                { player_id = player_id }
            )
            send(
                player_id,
                "ui_hero_skill_state",
                result and result.snapshot or {}
            )
        end
    )
end

local function register_choice_request()
    CustomGameEventManager:RegisterListener(
        "ui_hero_skill_choice_select",
        function(_, payload)
            local player_id = tonumber(payload.PlayerID)
            local result = event_bus.request(
                events.HERO_SKILL_CHOICE_SELECT_REQUEST,
                {
                    player_id = player_id,
                    choice_token = tostring(
                        payload.choice_token or ""
                    ),
                    skill_id = tostring(payload.skill_id or ""),
                }
            ) or { ok = false, error = "handler_missing" }
            send(player_id, "ui_hero_skill_choice_result", result)
        end
    )
end

local function on_skill_changed(payload)
    send(payload.player_id, "ui_hero_skill_state", payload)
end

local function on_choice_changed(payload)
    send(payload.player_id, "ui_hero_skill_choice", payload)
end

function M.init()
    register_state_request()
    register_choice_request()
    event_bus.subscribe(events.HERO_SKILL_CHANGED, on_skill_changed)
    event_bus.subscribe(
        events.HERO_SKILL_CHOICE_CHANGED,
        on_choice_changed
    )
end

return M
