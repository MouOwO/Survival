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

local function register_choice_request()
    CustomGameEventManager:RegisterListener(
        "ui_hero_skill_choice_select",
        function(_, payload)
            local player_id = tonumber(payload.PlayerID)
            if require("systems/player_context_service").is_defeated(player_id) then return end
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

local function register_upgrade_request()
    CustomGameEventManager:RegisterListener(
        "ui_hero_skill_upgrade_request",
        function(_, payload)
            payload = payload or {}
            local player_id = tonumber(payload.PlayerID)
            if not valid_player(player_id) or require("systems/player_context_service").is_defeated(player_id) then return end
            -- The button is anchored to a specific owned hero/skill level.
            -- Reject stale HUD requests and retries before spending a point.
            if tonumber(payload.unit_entindex) == nil
                or tonumber(payload.expected_level) == nil then
                send(player_id, "ui_hero_skill_upgrade_result", {
                    ok = false, error = "skill_request_invalid",
                    request_id = tostring(payload.request_id or ""),
                })
                return
            end
            local result = event_bus.request(
                events.HERO_SKILL_POINT_UPGRADE_REQUEST,
                {
                    player_id = player_id,
                    skill_id = tostring(payload.skill_id or ""),
                    unit_entindex = tonumber(payload.unit_entindex),
                    expected_level = tonumber(payload.expected_level),
                }
            ) or { ok = false, error = "handler_missing" }
            result.request_id = tostring(payload.request_id or "")
            send(player_id, "ui_hero_skill_upgrade_result", result)
        end
    )
end

local function on_choice_changed(payload)
    send(payload.player_id, "ui_hero_skill_choice", payload)
end

function M.init()
    register_choice_request()
    register_upgrade_request()
    event_bus.subscribe(
        events.HERO_SKILL_CHOICE_CHANGED,
        on_choice_changed
    )
end

return M
