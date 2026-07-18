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
        building_counts_by_team = {},
        sequence_by_player = {},
    }
end
local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
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
local function building_counts(team)
    state.building_counts_by_team[team] =
        state.building_counts_by_team[team] or {}
    return state.building_counts_by_team[team]
end
local function owned_content(player_id)
    local result = {}
    for content_id, count in pairs(
        state.inventory_by_player[player_id] or {}
    ) do
        if count > 0 then
            result[content_id] = true
        end
    end
    for content_id, value in pairs(
        state.technology_by_player[player_id] or {}
    ) do
        if value then
            result[content_id] = true
        end
    end
    return result
end
local function summon_snapshot(player_id)
    local result = event_bus.request(
        events.HERO_SUMMON_SNAPSHOT_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or {}
end
local function entitlement_snapshot(player_id)
    local result = event_bus.request(
        events.PLAYER_ENTITLEMENT_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or {}
end
local function progression_snapshot(player_id)
    local result = event_bus.request(
        events.HERO_PROGRESSION_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or {}
end
local function snapshot_context(player_id, reason)
    local team = player_team(player_id)
    local summon = summon_snapshot(player_id)
    local entitlement = entitlement_snapshot(player_id)
    local progression = progression_snapshot(player_id)
    state.sequence_by_player[player_id] =
        (state.sequence_by_player[player_id] or 0) + 1
    return {
        sequence = state.sequence_by_player[player_id],
        reason = reason,
        resources = event_bus.request(
            events.RESOURCE_GET_REQUEST,
            { team = team }
        ) or {},
        purchased_count = state.purchased_count,
        city_level = state.city_level_by_team[team] or 0,
        building_counts = building_counts(team),
        hero_summoned = summon.hero_summoned == 1,
        vip = entitlement.vip == 1,
        rebirth_level = tonumber(progression.rebirth_level) or 0,
        owned_content = owned_content(player_id),
    }
end
local function build_snapshot(player_id, reason)
    return catalog.build_snapshot(
        player_id,
        snapshot_context(player_id, reason or "open")
    )
end
local function push_snapshot(player_id, reason)
    if not state.opened_players[player_id] then
        return
    end
    event_bus.emit(events.SHOP_STATE_CHANGED, {
        player_id = player_id,
        snapshot = build_snapshot(player_id, reason),
    })
end
local function push_team(team, reason)
    for player_id, _ in pairs(state.opened_players) do
        if player_team(player_id) == team then
            push_snapshot(player_id, reason)
        end
    end
end
local function open_shop(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local summon = summon_snapshot(player_id)
    if summon.hero_summoned ~= 1 then
        return { ok = false, error = "请先在英雄祭坛召唤英雄" }
    end
    state.opened_players[player_id] = true
    return {
        ok = true,
        snapshot = build_snapshot(player_id, "opened"),
    }
end
local function close_shop(payload)
    state.opened_players[payload.player_id] = nil
    return { ok = true }
end
local function cached_result(player_id, request_id)
    if request_id == "" then
        return nil
    end
    local bucket = state.processed_requests[player_id]
    return bucket and bucket[request_id] or nil
end
local function remember_result(player_id, request_id, result)
    if request_id == "" then
        return
    end
    state.processed_requests[player_id] =
        state.processed_requests[player_id] or {}
    state.processed_requests[player_id][request_id] = result
end
local function purchase(payload)
    local player_id = tonumber(payload.player_id)
    local request_id = tostring(payload.request_id or "")
    local cached = cached_result(player_id, request_id)
    if cached then
        return cached
    end
    local entry = catalog.find_entry(
        tostring(payload.entry_id or "")
    )
    if not entry then
        return { ok = false, error = "shop_entry_invalid" }
    end
    local team = player_team(player_id)
    local context = snapshot_context(
        player_id,
        "purchase_validation"
    )
    local purchasable, reason = catalog.evaluate(
        player_id,
        entry,
        context
    )
    if not purchasable then
        return { ok = false, error = reason or "not_purchasable" }
    end
    local spend = event_bus.request(
        events.RESOURCE_TRY_SPEND_REQUEST,
        {
            team = team,
            wood = entry.woodcost,
            gold = entry.goldcost,
            population = 0,
            reason = "shop_purchase:" .. entry.entryid,
        }
    )
    if not spend or not spend.ok then
        notify(
            player_id,
            spend and spend.error or "购买失败",
            "error"
        )
        return spend or { ok = false, error = "resource_error" }
    end
    local granted = grant_service.grant(
        player_id,
        team,
        entry,
        state
    )
    if not granted or not granted.ok then
        grant_service.refund(team, entry)
        notify(
            player_id,
            granted and granted.error or "发放失败",
            "error"
        )
        return granted or { ok = false, error = "grant_failed" }
    end
    state.purchased_count[player_id] =
        state.purchased_count[player_id] or {}
    local counts = state.purchased_count[player_id]
    counts[entry.entryid] = (counts[entry.entryid] or 0) + 1
    notify(player_id, "购买成功：" .. catalog.content_name(entry))
    push_snapshot(player_id, "purchase_completed")
    local result = {
        ok = true,
        entry_id = entry.entryid,
        grant_result = granted,
    }
    remember_result(player_id, request_id, result)
    return result
end
local function change_building_count(payload, delta)
    local counts = building_counts(payload.team)
    local building_id = tostring(payload.building_id or "")
    counts[building_id] = math.max(
        0,
        (counts[building_id] or 0) + delta
    )
end
local function on_building_created(payload)
    change_building_count(payload, 1)
    if payload.building_id == "main_city" then
        state.city_level_by_team[payload.team] =
            tonumber(payload.level) or 1
    end
    push_team(payload.team, "building_created")
end
local function on_building_changed(payload)
    if payload.building_id == "main_city" then
        state.city_level_by_team[payload.team] =
            tonumber(payload.level) or 0
    end
    push_team(payload.team, "building_changed")
end
local function on_building_destroyed(payload)
    change_building_count(payload, -1)
    if payload.building_id == "main_city" then
        state.city_level_by_team[payload.team] = 0
    end
    push_team(payload.team, "building_destroyed")
end
local function on_player_changed(payload)
    push_snapshot(payload.player_id, payload.reason or "player_changed")
end
local function on_resource_changed(payload)
    push_team(payload.team, "resource_changed")
end
function M.init()
    reset_state()
    event_bus.handle_request(events.SHOP_OPEN_REQUEST, open_shop)
    event_bus.handle_request(events.SHOP_CLOSE_REQUEST, close_shop)
    event_bus.handle_request(events.SHOP_PURCHASE_REQUEST, purchase)
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resource_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.HERO_SUMMON_STATE_CHANGED, on_player_changed)
    event_bus.subscribe(events.PLAYER_ENTITLEMENT_CHANGED, on_player_changed)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, on_player_changed)
end
return M
