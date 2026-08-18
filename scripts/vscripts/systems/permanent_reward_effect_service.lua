local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local totals_by_player = {}

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[tostring(key)] = tonumber(value) or 0
    end
    return result
end

local function refresh(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    local profile_service = require("systems/player_profile_service")
    local profile = profile_service.get_profile(player_id)
    totals_by_player[player_id] = copy(
        profile and profile.save and profile.save.permanent_effects or {}
    )
    event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
        player_id = player_id,
        totals = copy(totals_by_player[player_id]),
        revision = profile and profile.revision or 0,
    })
end

local function get(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, totals = copy(totals_by_player[player_id]) }
end

function M.value(player_id, effect_key)
    return tonumber((totals_by_player[tonumber(player_id)] or {})[effect_key]) or 0
end

function M.init()
    totals_by_player = {}
    event_bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, get)
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, refresh)
end

return M