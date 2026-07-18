local event_bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/entitlement_definitions")

local M = {}

local state_by_player = {}

local function default_state()
    local result = {}
    for _, definition in ipairs(definitions.rows or {}) do
        if definition.enabled ~= false then
            result[definition.entitlement_id] =
                definition.default_unlocked == true
        end
    end
    return result
end

local function ensure(player_id)
    if not state_by_player[player_id] then
        state_by_player[player_id] = default_state()
    end
    return state_by_player[player_id]
end

local function snapshot(player_id)
    local source = ensure(player_id)
    local values = {}
    for key, value in pairs(source) do
        values[key] = value and 1 or 0
    end
    return {
        player_id = player_id,
        values = values,
        vip = source.vip and 1 or 0,
    }
end

local function get_entitlements(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function set_entitlement(payload)
    local player_id = tonumber(payload.player_id)
    local entitlement_id = tostring(payload.entitlement_id or "")
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    if not definitions.by_id[entitlement_id] then
        return { ok = false, error = "entitlement_invalid" }
    end

    ensure(player_id)[entitlement_id] = payload.unlocked == true
        or tonumber(payload.unlocked) == 1
    local data = snapshot(player_id)
    data.reason = tostring(payload.reason or "server_update")
    event_bus.emit(events.PLAYER_ENTITLEMENT_CHANGED, data)
    return { ok = true, snapshot = data }
end

local function on_hero_ready(payload)
    if payload.player_id ~= nil then
        ensure(payload.player_id)
    end
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(
        events.PLAYER_ENTITLEMENT_GET_REQUEST,
        get_entitlements
    )
    event_bus.handle_request(
        events.PLAYER_ENTITLEMENT_SET_REQUEST,
        set_entitlement
    )
    event_bus.subscribe(events.HERO_READY, on_hero_ready)
end

return M
