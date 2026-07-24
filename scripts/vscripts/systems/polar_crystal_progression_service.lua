local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local SMALL_ID = "item_small_polar_crystal"
local LARGE_ID = "item_large_polar_crystal"
local TARGET = 200
local ICE_ENCOUNTER_ID = "encounter_challenge_06"

local remaining_by_player = {}

local function inventory_counts(player_id)
    local result = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot and result.snapshot.counts or nil
end

local function publish(player_id, reason, remaining_override)
    local remaining = remaining_override
    if remaining == nil then
        remaining = remaining_by_player[player_id] or TARGET
    end
    event_bus.emit(events.POLAR_CRYSTAL_PROGRESS_CHANGED, {
        player_id = player_id,
        reason = reason or "changed",
        remaining = remaining,
        target = TARGET,
        content_id = SMALL_ID,
    })
end

local function on_inventory_changed(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    local counts = payload.snapshot and payload.snapshot.counts or {}
    local owns_small = (tonumber(counts[SMALL_ID]) or 0) > 0
    if owns_small and remaining_by_player[player_id] == nil then
        remaining_by_player[player_id] = TARGET
        publish(player_id, "small_crystal_acquired")
    elseif not owns_small and remaining_by_player[player_id] ~= nil then
        remaining_by_player[player_id] = nil
        publish(player_id, "small_crystal_removed", 0)
    end
end

local function upgrade(player_id)
    local result = event_bus.request(
        events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,
        {
            player_id = player_id,
            request_id = "polar_crystal_upgrade:" .. tostring(player_id),
            consume = { [SMALL_ID] = 1 },
            grant = { [LARGE_ID] = 1 },
            reason = "polar_crystal_kill_progress_complete",
        }
    ) or { ok = false, error = "inventory_transaction_unavailable" }
    if result.ok then
        remaining_by_player[player_id] = nil
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "小极地晶石已自动升阶为大极地晶石",
            level = "success",
        })
    end
    return result
end

local function on_monster_killed(payload)
    if tostring(payload.encounter_id or "") ~= ICE_ENCOUNTER_ID then return end
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then return end
    local counts = inventory_counts(player_id)
    if not counts or (tonumber(counts[SMALL_ID]) or 0) < 1 then return end

    local remaining = remaining_by_player[player_id]
    if remaining == nil then remaining = TARGET end
    remaining = math.max(0, remaining - 1)
    remaining_by_player[player_id] = remaining
    publish(player_id, "ice_monster_killed")
    if remaining <= 0 then
        local result = upgrade(player_id)
        if not result.ok then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = "极地晶石自动升阶失败："
                    .. tostring(result.error or "unknown"),
                level = "error",
            })
        end
    end
end

local function get_progress(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    return {
        ok = true,
        remaining = remaining_by_player[player_id] or TARGET,
        target = TARGET,
        content_id = SMALL_ID,
    }
end

function M.init()
    remaining_by_player = {}
    event_bus.handle_request(
        events.POLAR_CRYSTAL_PROGRESS_GET_REQUEST,
        get_progress
    )
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_inventory_changed)
    event_bus.subscribe(events.MONSTER_KILLED, on_monster_killed)
    print("[POLAR_CRYSTAL_INIT] target=200 encounter=encounter_challenge_06")
end

return M