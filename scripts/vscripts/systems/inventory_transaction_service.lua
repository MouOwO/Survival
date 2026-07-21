local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local locked = {}
local completed = {}

local function clean_map(source)
    local out = {}
    for id, raw in pairs(source or {}) do
        local n = math.floor(tonumber(raw) or 0)
        if tostring(id) ~= "" and n > 0 then out[tostring(id)] = n end
    end
    return out
end

local function remember(player_id, request_id, result)
    if request_id == "" then return end
    completed[player_id] = completed[player_id] or {}
    completed[player_id][request_id] = result
end

local function execute(payload)
    local player_id = tonumber(payload.player_id)
    local request_id = tostring(payload.request_id or "")
    if player_id == nil or player_id < 0 or request_id == "" then
        return { ok = false, error = "inventory_tx_invalid_identity" }
    end
    local cached = completed[player_id] and completed[player_id][request_id]
    if cached then
        print("[INV_TX_IDEMPOTENT] player=" .. player_id .. " request=" .. request_id)
        return cached
    end
    if locked[player_id] then return { ok = false, error = "inventory_tx_player_locked" } end
    locked[player_id] = true
    local consume, grant = clean_map(payload.consume), clean_map(payload.grant)
    local before = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST, { player_id = player_id })
    local counts = before and before.snapshot and before.snapshot.counts
    if not counts then
        locked[player_id] = nil
        return { ok = false, error = "inventory_tx_snapshot_unavailable" }
    end
    for id, n in pairs(consume) do
        if (tonumber(counts[id]) or 0) < n then
            locked[player_id] = nil
            local failed = { ok = false, error = "inventory_tx_missing:" .. id }
            remember(player_id, request_id, failed)
            return failed
        end
    end
    -- The legacy inventory handler applies consume+grant in one synchronous
    -- mutation, so output failure cannot leave inputs consumed.
    local result = event_bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST, {
        player_id = player_id, consume = consume, grant = grant,
        reason = payload.reason or "runtime_transaction",
    }) or { ok = false, error = "inventory_tx_handler_missing" }
    locked[player_id] = nil
    remember(player_id, request_id, result)
    print(string.format("[INV_TX_COMMIT] player=%s request=%s ok=%s",
        tostring(player_id), request_id, tostring(result.ok == true)))
    return result
end

function M.init()
    locked, completed = {}, {}
    event_bus.handle_request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST, execute)
    print("[INV_TX_INIT] ready")
end

return M
