local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local inventory_by_player = {}

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function bucket(player_id)
    inventory_by_player[player_id] = inventory_by_player[player_id] or {}
    return inventory_by_player[player_id]
end

local function snapshot(player_id)
    local counts = {}
    for content_id, count in pairs(bucket(player_id)) do
        if count > 0 then
            counts[content_id] = count
        end
    end
    return { player_id = player_id, counts = counts }
end

local function publish(player_id, reason, changes)
    event_bus.emit(events.CONTENT_INVENTORY_CHANGED, {
        player_id = player_id,
        reason = reason or "changed",
        changes = changes or {},
        snapshot = snapshot(player_id),
    })
end

local function normalize_map(value)
    local result = {}
    for content_id, count in pairs(value or {}) do
        local amount = math.floor(tonumber(count) or 0)
        if content_id ~= "" and amount > 0 then
            result[tostring(content_id)] = amount
        end
    end
    return result
end

local function grant(payload)
    local player_id = tonumber(payload.player_id)
    local content_id = tostring(payload.content_id or "")
    local count = math.floor(tonumber(payload.count) or 1)
    if not valid_player_id(player_id) or content_id == "" or count <= 0 then
        return { ok = false, error = "inventory_grant_invalid" }
    end
    local counts = bucket(player_id)
    counts[content_id] = (counts[content_id] or 0) + count
    local changes = { [content_id] = count }
    publish(player_id, payload.reason or "grant", changes)
    return { ok = true, snapshot = snapshot(player_id), changes = changes }
end

local function transaction(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local consume = normalize_map(payload.consume)
    local grant_map = normalize_map(payload.grant)
    local counts = bucket(player_id)
    for content_id, count in pairs(consume) do
        if (counts[content_id] or 0) < count then
            return {
                ok = false,
                error = "inventory_missing:" .. content_id,
            }
        end
    end
    local changes = {}
    for content_id, count in pairs(consume) do
        counts[content_id] = (counts[content_id] or 0) - count
        changes[content_id] = (changes[content_id] or 0) - count
    end
    for content_id, count in pairs(grant_map) do
        counts[content_id] = (counts[content_id] or 0) + count
        changes[content_id] = (changes[content_id] or 0) + count
    end
    publish(player_id, payload.reason or "transaction", changes)
    return { ok = true, snapshot = snapshot(player_id), changes = changes }
end

local function get_inventory(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

function M.init()
    inventory_by_player = {}
    event_bus.handle_request(events.CONTENT_INVENTORY_GRANT_REQUEST, grant)
    event_bus.handle_request(
        events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
        transaction
    )
    event_bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, get_inventory)
end

return M
