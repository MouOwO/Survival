local event_bus = require("core/event_bus")
local events = require("core/events")
local catalog = require("systems/shop_catalog")
local grant_service = require("systems/shop_grant_service")

local M = {}
local state = {}

local function reset_state()
    state = {
        inventory_by_player = {},
        technology_by_player = {},
        purchased_count = {},
        processed_requests = {},
        opened_players = {},
        city_level_by_team = {},
        sequence_by_player = {},
    }
end

local function player_team(player_id)
    return PlayerResource:GetTeam(player_id)
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function snapshot_context(player_id, reason)
    local team = player_team(player_id)
    state.sequence_by_player[player_id] =
        (state.sequence_by_player[player_id] or 0) + 1
    return {
        sequence = state.sequence_by_player[player_id],
        reason = reason,
        resources = event_bus.request(events.RESOURCE_GET_REQUEST, { team = team }) or {},
        purchased_count = state.purchased_count,
        city_level = state.city_level_by_team[team] or 0,
    }
end

local function build_snapshot(player_id, reason)
    return catalog.build_snapshot(
        player_id,
        snapshot_context(player_id, reason or "open")
    )
end

local function push_snapshot(player_id, reason)
    if not state.opened_players[player_id] then return end
    event_bus.emit(events.SHOP_STATE_CHANGED, {
        player_id = player_id,
        snapshot = build_snapshot(player_id, reason),
    })
end

local function push_team(team, reason)
    for player_id, _ in pairs(state.opened_players) do
        if player_team(player_id) == team then push_snapshot(player_id, reason) end
    end
end

local function open_shop(payload)
    local player_id = payload.player_id
    state.opened_players[player_id] = true
    return { ok = true, snapshot = build_snapshot(player_id, "opened") }
end

local function close_shop(payload)
    state.opened_players[payload.player_id] = nil
    return { ok = true }
end

local function cached_result(player_id, request_id)
    if request_id == "" then return nil end
    local bucket = state.processed_requests[player_id]
    return bucket and bucket[request_id] or nil
end

local function remember_result(player_id, request_id, result)
    if request_id == "" then return end
    state.processed_requests[player_id] = state.processed_requests[player_id] or {}
    state.processed_requests[player_id][request_id] = result
end

local function purchase(payload)
    local player_id = payload.player_id
    local request_id = tostring(payload.request_id or "")
    local cached = cached_result(player_id, request_id)
    if cached then return cached end

    local entry = catalog.find_entry(tostring(payload.entry_id or ""))
    if not entry then return { ok = false, error = "shop_entry_invalid" } end

    local team = player_team(player_id)
    local context = snapshot_context(player_id, "purchase_validation")
    local purchasable, reason, definition = catalog.evaluate(player_id, entry, context)
    if not purchasable then return { ok = false, error = reason or "not_purchasable" } end

    local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = team,
        wood = math.max(0, entry.woodcost or 0),
        gold = math.max(0, entry.goldcost or 0),
        population = 0,
        reason = "shop_purchase:" .. entry.entryid,
    })
    if not spend or not spend.ok then
        notify(player_id, spend and spend.error or "购买失败", "error")
        return spend or { ok = false, error = "resource_error" }
    end

    local granted = grant_service.grant(player_id, team, entry, definition, state)
    if not granted or not granted.ok then
        grant_service.refund(team, entry)
        notify(player_id, granted and granted.error or "发放失败", "error")
        return granted or { ok = false, error = "grant_failed" }
    end

    state.purchased_count[player_id] = state.purchased_count[player_id] or {}
    state.purchased_count[player_id][entry.entryid] =
        (state.purchased_count[player_id][entry.entryid] or 0) + 1
    notify(player_id, "购买成功：" .. catalog.content_name(entry, definition))
    push_snapshot(player_id, "purchase_completed")

    local result = { ok = true, entry_id = entry.entryid }
    remember_result(player_id, request_id, result)
    return result
end

local function on_resource_changed(payload)
    push_team(payload.team, "resource_changed")
end

local function on_building_changed(payload)
    if payload.building_id ~= "main_city" then return end
    state.city_level_by_team[payload.team] = payload.level or 0
    push_team(payload.team, "city_level_changed")
end

local function on_building_destroyed(payload)
    if payload.building_id ~= "main_city" then return end
    state.city_level_by_team[payload.team] = 0
    push_team(payload.team, "city_destroyed")
end

function M.init()
    reset_state()
    event_bus.handle_request(events.SHOP_OPEN_REQUEST, open_shop)
    event_bus.handle_request(events.SHOP_CLOSE_REQUEST, close_shop)
    event_bus.handle_request(events.SHOP_PURCHASE_REQUEST, purchase)
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resource_changed)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
end

return M
