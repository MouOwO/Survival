local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local state = {}

local function instances(player_id)
    state[player_id] = state[player_id] or {}
    return state[player_id]
end

local function on_inventory(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    local current = instances(player_id)
    for id, count in pairs((payload.snapshot and payload.snapshot.counts) or {}) do
        current[id] = { content_id = id, quantity = math.max(0, math.floor(tonumber(count) or 0)) }
    end
    for id in pairs(current) do
        if not ((payload.snapshot and payload.snapshot.counts) or {})[id] then current[id] = nil end
    end
    event_bus.emit(events.EQUIPMENT_INSTANCE_CHANGED, {
        player_id = player_id, reason = payload.reason, instances = current,
    })
end

local function get(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "equipment_instance_player_invalid" }
    end
    return { ok = true, instances = instances(player_id) }
end

function M.init()
    state = {}
    event_bus.handle_request(events.EQUIPMENT_INSTANCE_GET_REQUEST, get)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_inventory)
    print("[EQUIPMENT_INSTANCE_INIT] compatibility_projection_ready")
end

return M
