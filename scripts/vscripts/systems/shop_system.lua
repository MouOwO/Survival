local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local catalog = require("systems/shop_catalog")
local grant_service = require("systems/shop_grant_service")
local challenge_definitions = require("config/generated/challenge_definitions")
local rebirth_challenges = require("config/generated/rebirth_challenges")
local research_config = require("config/research_technology_config")
local research_events = require("research/research_event_names")
local research_abilities = require("config/generated/research_lab_abilities")
local ability_by_research_group = {}
for _, mapping in ipairs(research_abilities.rows or {}) do
    ability_by_research_group[mapping.technology_group] = mapping.ability_name
end
local M = {}
local state = {}
local TECHNOLOGY_RESEARCH_DURATION = 2
local AUTO_RESEARCH_RETRY_INTERVAL = 1
local RESEARCH_QUEUE_CAPACITY = 7
local queue_auto_research
local enqueue_research
local run_research_queue
local queue_research
local push_snapshot

local function game_time()
    return GameRules and GameRules.GetGameTime
        and tonumber(GameRules:GetGameTime()) or 0
end

local function reset_state()
    state = {
        technology_by_player = {},
        research_unlocked = {},
        advanced_researcher_unlocked = {},
        purchased_count = {},
        processed_requests = {},
        opened_players = {},
        city_level_by_team = {},
        building_counts_by_team = {},
        sequence_by_player = {},
        snapshot_cache_by_player = {},
        pending_push_reason = {},
        debug_all_unlocked = {},
        research_lanes = {},
        auto_research_next_at_by_player = {},
        research_scope_by_player = {},
        research_source_entindex_by_player = {},
        purchase_cooldown_until_by_player = {},
        purchase_cooldown_total_by_player = {},
        stock_by_player = {},
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
-- Each player has an independent production slot at each research building.
-- Public advanced labs retain team access without sharing another player's timer.
local function research_lane(player_id, source_entindex, create)
    local key = tostring(player_id) .. ":" .. tostring(tonumber(source_entindex) or -1)
    local lane = state.research_lanes[key]
    if not lane and create then
        lane = { key = key, player_id = player_id,
            source_entindex = tonumber(source_entindex) or -1,
            auto_research = {}, next_start_at = 0, sequence = 0,
            queued = {}, next_job_id = 0, blocked_reason = "" }
        state.research_lanes[key] = lane
    end
    return lane
end
local function auto_research_start_at(lane, group)
    local deadlines = state.auto_research_next_at_by_player[lane.player_id] or {}
    return math.max(lane.next_start_at or 0, deadlines[group] or 0)
end
local function project_research_job(job)
    if not job then return {} end
    return { job_id = job.job_id, group = job.technology_group,
        technology_group = job.technology_group, display_name = job.display_name,
        target_level = job.target_level, icon_name = job.icon_name or "",
        ability_name = ability_by_research_group[job.technology_group] or "",
        entry_id = job.entry_id }
end
local function research_job_count(lane)
    return (lane.pending and 1 or 0) + #(lane.queued or {})
end
local function research_snapshot(player_id, source_entindex)
    local lane = research_lane(player_id, source_entindex, false) or {}
    local blocked_head = not lane.pending and (lane.queued or {})[1] or nil
    local pending = lane.pending or blocked_head or {}
    local queued, reserved_levels = {}, {}
    if lane.pending then
        reserved_levels[lane.pending.technology_group] = lane.pending.target_level
    end
    for index, job in ipairs(lane.queued or {}) do
        reserved_levels[job.technology_group] = math.max(
            reserved_levels[job.technology_group] or 0, job.target_level)
        if not blocked_head or index > 1 then
            queued[#queued + 1] = project_research_job(job)
        end
    end
    local enabled, next_start_at = {}, nil
    for group in pairs(lane.auto_research or {}) do
        enabled[group] = 1
        local deadline = auto_research_start_at(lane, group)
        next_start_at = next_start_at and math.min(next_start_at, deadline) or deadline
    end
    return {
        player_id = player_id, team = player_team(player_id),
        source_entindex = tonumber(source_entindex) or -1,
        researching = lane.pending and 1 or 0,
        research_group = pending.technology_group or "",
        display_name = pending.display_name or "",
        target_level = pending.target_level or 0,
        research_target_level = pending.target_level or 0,
        started_at = pending.started_at or 0,
        finish_at = pending.finish_at or 0,
        duration = TECHNOLOGY_RESEARCH_DURATION,
        auto_enabled = next(enabled) and 1 or 0,
        auto_research = enabled,
        next_start_at = next_start_at or 0,
        sequence = lane.sequence or 0,
        entry_id = pending.entry_id or "",
        icon_name = pending.icon_name or "",
        ability_name = ability_by_research_group[pending.technology_group] or "",
        active_job = project_research_job(lane.pending),
        blocked_head = project_research_job(blocked_head),
        blocked_reason = lane.blocked_reason or "",
        queued = queued,
        queued_count = #queued,
        queue_count = research_job_count(lane),
        capacity = RESEARCH_QUEUE_CAPACITY,
        queue_capacity = RESEARCH_QUEUE_CAPACITY,
        reserved_levels = reserved_levels,
        cost_timing_text = "开始研究时扣费，排队未扣费",
    }
end
local function publish_research(lane)
    event_bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED,
        research_snapshot(lane.player_id, lane.source_entindex))
end
local function cancel_research(lane, reason)
    scheduler.cancel("shop_technology_research:" .. lane.key)
    scheduler.cancel("shop_auto_research:" .. lane.key)
    scheduler.cancel("shop_research_queue:" .. lane.key)
    local pending = lane.pending
    lane.pending = nil
    lane.auto_research = {}
    lane.queued = {}
    lane.blocked_reason = ""
    lane.next_start_at = 0
    if pending then
        event_bus.request(research_events.UPGRADE_ROLLBACK_REQUESTED, {
            transaction_id = pending.transaction_id,
            error_code = reason or "research_source_removed",
        })
    end
    publish_research(lane)
end
local function building_counts(team)
    state.building_counts_by_team[team] =
        state.building_counts_by_team[team] or {}
    return state.building_counts_by_team[team]
end
local function owned_content(player_id)
    local result = {}
    local inventory = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts = inventory and inventory.snapshot
        and inventory.snapshot.counts or {}
    for content_id, count in pairs(counts) do
        if count > 0 then
            result[content_id] = count
        end
    end
    for content_id, value in pairs(
        state.technology_by_player[player_id] or {}
    ) do
        if value then
            result[content_id] = 1
        end
    end
    return result
end
local function purchase_cooldown_remaining(player_id, entry)
    local by_entry = state.purchase_cooldown_until_by_player[player_id] or {}
    return math.max(0, (by_entry[entry.entryid] or 0) - game_time())
end
local function set_purchase_cooldown(player_id, entry, override_duration)
    local duration = tonumber(override_duration)
        or tonumber(entry and entry.purchase_cooldown_seconds) or 0
    if duration <= 0 then return end
    state.purchase_cooldown_until_by_player[player_id] =
        state.purchase_cooldown_until_by_player[player_id] or {}
    state.purchase_cooldown_until_by_player[player_id][entry.entryid] =
        game_time() + duration
    state.purchase_cooldown_total_by_player[player_id] =
        state.purchase_cooldown_total_by_player[player_id] or {}
    state.purchase_cooldown_total_by_player[player_id][entry.entryid] = duration
    scheduler.after(duration, function()
        if purchase_cooldown_remaining(player_id, entry) <= 0
            and state.opened_players[player_id] then
            push_snapshot(player_id, "purchase_cooldown_finished")
        end
    end, "shop_purchase_cooldown:" .. tostring(player_id)
        .. ":" .. tostring(entry.entryid))
end
local function purchase_cooldown_snapshot(player_id)
    local result = {}
    for _, entry in ipairs(catalog.entries()) do
        local remaining = purchase_cooldown_remaining(player_id, entry)
        if remaining > 0 then
            result[entry.entryid] = {
                remaining = remaining,
                total = (state.purchase_cooldown_total_by_player[player_id] or {})
                    [entry.entryid] or tonumber(entry.purchase_cooldown_seconds) or 0,
                until_time = game_time() + remaining,
            }
        end
    end
    return result
end
local function stock_state(player_id, entry)
    local maximum = math.max(0, tonumber(entry and entry.stock_max) or 0)
    if maximum <= 0 then return nil end
    state.stock_by_player[player_id] = state.stock_by_player[player_id] or {}
    local stock = state.stock_by_player[player_id][entry.entryid]
    if not stock then
        stock = { count = maximum, next_replenish_at = 0 }
        state.stock_by_player[player_id][entry.entryid] = stock
    end
    stock.count = math.max(0, math.min(maximum, tonumber(stock.count) or maximum))
    return stock, maximum
end
local function stock_snapshot(player_id)
    local result = {}
    for _, entry in ipairs(catalog.entries()) do
        local stock, maximum = stock_state(player_id, entry)
        if stock then
            result[entry.entryid] = {
                count = stock.count,
                maximum = maximum,
                replenish_seconds = tonumber(entry.stock_replenish_seconds) or 0,
                replenish_remaining = stock.next_replenish_at > 0
                    and math.max(0, stock.next_replenish_at - game_time()) or 0,
            }
        end
    end
    return result
end
local function replenish_stock(player_id, entry)
    local stock, maximum = stock_state(player_id, entry)
    if not stock or stock.count >= maximum then return end
    stock.count = stock.count + 1
    stock.next_replenish_at = 0
    local duration = tonumber(entry.stock_replenish_seconds) or 0
    if stock.count < maximum and duration > 0 then
        stock.next_replenish_at = game_time() + duration
        scheduler.after(duration, function() replenish_stock(player_id, entry) end,
            "shop_stock_replenish:" .. tostring(player_id) .. ":" .. tostring(entry.entryid))
    end
    push_snapshot(player_id, "shop_stock_replenished")
end
local function consume_stock(player_id, entry)
    local stock, maximum = stock_state(player_id, entry)
    if not stock then return true end
    if stock.count <= 0 then return false end
    stock.count = stock.count - 1
    local duration = tonumber(entry.stock_replenish_seconds) or 0
    if stock.count < maximum and duration > 0 and stock.next_replenish_at <= game_time() then
        stock.next_replenish_at = game_time() + duration
        scheduler.after(duration, function() replenish_stock(player_id, entry) end,
            "shop_stock_replenish:" .. tostring(player_id) .. ":" .. tostring(entry.entryid))
    end
    return true
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
local function merge_technology_levels(player_id, incoming)
    state.technology_by_player[player_id] =
        state.technology_by_player[player_id] or {}
    local levels = state.technology_by_player[player_id]
    for group, level in pairs(incoming or {}) do
        levels[group] = level
    end
    return levels
end
local function active_challenge_encounters(player_id)
    local result = {}
    for _, definitions in ipairs({ challenge_definitions, rebirth_challenges }) do
        for _, challenge in ipairs(definitions.rows or {}) do
            local encounter_id = tostring(challenge.encounter_id or "")
            if challenge.enabled ~= false and encounter_id ~= "" then
                local current = event_bus.request(
                    events.MONSTER_ENCOUNTER_QUERY_REQUEST,
                    {
                        player_id = player_id,
                        encounter_id = encounter_id,
                    }
                )
                if current and current.ok and current.active then
                    result[encounter_id] = true
                end
            end
        end
    end
    return result
end
local function snapshot_context(player_id, reason, mode, source_entindex)
    local team = player_team(player_id)
    local summon = summon_snapshot(player_id)
    local entitlement = entitlement_snapshot(player_id)
    local progression = progression_snapshot(player_id)
    local research_state = event_bus.request(
        research_events.STATE_GET_REQUESTED,
        { player_id = player_id }
    )
    if research_state and research_state.ok == true then
        -- Research and gold-mine technologies share the legacy projection.
        -- The research repository only returns groups it owns, so replacing
        -- this table would erase gold-mine levels before purchase validation.
        merge_technology_levels(player_id, research_state.legacy_levels)
    end
    state.sequence_by_player[player_id] =
        (state.sequence_by_player[player_id] or 0) + 1
    local wave_state = event_bus.request(events.WAVE_STATE_GET_REQUEST, {}) or {}
    source_entindex = tonumber(source_entindex)
        or state.research_source_entindex_by_player[player_id]
    local research = research_snapshot(player_id, source_entindex)
    return {
        sequence = state.sequence_by_player[player_id],
        reason = reason,
        resources = event_bus.request(
            events.RESOURCE_GET_REQUEST,
            {
        player_id = player_id, team = team }
        ) or {},
        purchased_count = state.purchased_count,
        city_level = state.city_level_by_team[team] or 0,
        building_counts = building_counts(team),
        hero_summoned = summon.hero_summoned == 1,
        vip = entitlement.vip == 1,
        rebirth_level = tonumber(progression.rebirth_level) or 0,
        owned_content = owned_content(player_id),
        active_challenge_encounters = active_challenge_encounters(player_id),
        technology_levels = state.technology_by_player,
        research_unlocked = state.research_unlocked[player_id] == true,
        advanced_researcher_unlocked = state.advanced_researcher_unlocked[player_id] == true,
        debug_all_unlocked = state.debug_all_unlocked[player_id] == true,
        technology_cooldown_remaining = math.max(0, research.finish_at - game_time()),
        technology_cooldown_total = research.duration,
        technology_cooldown_until = research.finish_at,
        technology_cooldown_source_group = research.research_group,
        technology_cooldown_source_entry = research.entry_id,
        technology_cooldown_sequence = research.sequence,
        auto_research = research.auto_research,
        research = research,
        wave_state = wave_state,
        ui_mode = mode or state.opened_players[player_id] or "shop",
        research_scope = state.research_scope_by_player[player_id] or "",
        research_source_entindex =
            state.research_source_entindex_by_player[player_id] or -1,
        purchase_cooldowns = purchase_cooldown_snapshot(player_id),
        shop_stock = stock_snapshot(player_id),
    }
end
local function build_snapshot(player_id, reason, mode)
    return catalog.build_snapshot(
        player_id,
        snapshot_context(player_id, reason or "open", mode)
    )
end

local function values_equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not values_equal(value, right[key]) then return false end
    end
    for key, _ in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function entries_by_id(entries)
    local result = {}
    for _, entry in ipairs(entries or {}) do
        result[tostring(entry.entry_id or "")] = entry
    end
    return result
end

local function build_patch(previous, current)
    local old_entries = entries_by_id(previous.entries)
    local new_entries = entries_by_id(current.entries)
    local changed = {}
    local removed = {}
    for entry_id, entry in pairs(new_entries) do
        if not values_equal(entry, old_entries[entry_id]) then
            table.insert(changed, entry)
        end
    end
    for entry_id, _ in pairs(old_entries) do
        if not new_entries[entry_id] then
            table.insert(removed, entry_id)
        end
    end
    table.sort(changed, function(left, right)
        return (tonumber(left.sort_order) or 0)
            < (tonumber(right.sort_order) or 0)
    end)
    table.sort(removed)

    local patch = {
        schema_version = current.schema_version,
        config_version = current.config_version,
        full = 0,
        sequence = current.sequence,
        base_sequence = previous.sequence,
        reason = current.reason,
        player_id = current.player_id,
        ui_mode = current.ui_mode,
        changed_entries = changed,
        removed_entry_ids = removed,
        technology_cooldown_remaining = current.technology_cooldown_remaining,
        technology_cooldown_total = current.technology_cooldown_total,
        technology_cooldown_until = current.technology_cooldown_until,
        technology_cooldown_source_group = current.technology_cooldown_source_group,
        technology_cooldown_source_entry = current.technology_cooldown_source_entry,
        technology_cooldown_sequence = current.technology_cooldown_sequence,
        research = current.research,
        purchase_cooldowns = current.purchase_cooldowns,
        shop_stock = current.shop_stock,
    }
    if not values_equal(previous.resources or {}, current.resources or {}) then
        patch.resources = current.resources
    end
    if not values_equal(previous.purchase_cooldowns or {}, current.purchase_cooldowns or {}) then
        patch.purchase_cooldowns = current.purchase_cooldowns
    end
    if not values_equal(previous.shop_stock or {}, current.shop_stock or {}) then
        patch.shop_stock = current.shop_stock
    end
    if previous.ui_mode ~= current.ui_mode
        or previous.config_version ~= current.config_version
        or not values_equal(previous.categories or {}, current.categories or {}) then
        patch.categories = current.categories
    end
    local changed_any = not values_equal(previous.research, current.research)
        or patch.resources ~= nil or patch.categories ~= nil
        or patch.purchase_cooldowns ~= nil
        or patch.shop_stock ~= nil
        or #changed > 0 or #removed > 0
    return changed_any and patch or nil
end

local function publish_snapshot(player_id, reason)
    if not state.opened_players[player_id] then
        return
    end
    local current = build_snapshot(
        player_id,
        reason,
        state.opened_players[player_id]
    )
    local previous = state.snapshot_cache_by_player[player_id]
    local outgoing = previous and build_patch(previous, current) or current
    current.full = 1
    if not outgoing then return end
    state.snapshot_cache_by_player[player_id] = current
    if outgoing == current then outgoing.full = 1 end
    event_bus.emit(events.SHOP_STATE_CHANGED, {
        player_id = player_id,
        snapshot = outgoing,
    })
end
push_snapshot = function(player_id, reason)
    if not state.opened_players[player_id] then return end
    local queued = state.pending_push_reason[player_id] ~= nil
    state.pending_push_reason[player_id] = reason or "changed"
    if queued then return end
    local current_state = state
    scheduler.after(0.05, function()
        if current_state ~= state then return end
        local pending_reason = state.pending_push_reason[player_id]
        state.pending_push_reason[player_id] = nil
        if pending_reason then publish_snapshot(player_id, pending_reason) end
    end, "shop_snapshot_push_" .. tostring(player_id))
end
local function push_team(team, reason)
    for player_id, _ in pairs(state.opened_players) do
        if player_team(player_id) == team then
            push_snapshot(player_id, reason)
        end
    end
end
local function research_building_id(definition)
    if not definition then return nil end
    if definition.building_id == "research_lab" then
        return "building_research_lab"
    end
    if definition.building_id == "advanced_research_lab" then
        return "building_advanced_research_lab"
    end
    return nil
end

local function validate_research_source(player_id, source_entindex, definition)
    source_entindex = tonumber(source_entindex)
    if not source_entindex or source_entindex <= 0 then
        return nil, "research_source_required"
    end
    local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
        entindex = source_entindex,
    })
    local expected = research_building_id(definition)
    if not building or not expected or building.building_id ~= expected
        or tonumber(building.team) ~= tonumber(player_team(player_id)) then
        return nil, "research_source_invalid"
    end
    if expected == "building_research_lab"
        and tonumber(building.player_id) ~= tonumber(player_id) then
        return nil, "research_source_invalid"
    end
    return building, nil
end

local function open_shop(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local requested_mode = tostring(payload.mode or "shop")
    local mode = requested_mode == "research" and "research"
        or requested_mode == "challenge" and "challenge" or "shop"
    if mode == "research" then
        local source_entindex = tonumber(payload.source_entindex)
        if not source_entindex or source_entindex <= 0 then
            return { ok = false, error = "research_source_required" }
        end
        local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
            entindex = source_entindex,
        })
        if not building or building.building_id ~= "building_advanced_research_lab"
            or tonumber(building.team) ~= tonumber(player_team(player_id)) then
            return { ok = false, error = "research_source_invalid" }
        end
        state.research_scope_by_player[player_id] = "advanced"
        state.research_source_entindex_by_player[player_id] = source_entindex
    end
    state.opened_players[player_id] = mode
    local snapshot = build_snapshot(player_id, "opened", mode)
    snapshot.full = 1
    state.snapshot_cache_by_player[player_id] = snapshot
    return {
        ok = true,
        snapshot = snapshot,
    }
end
local function close_shop(payload)
    state.opened_players[payload.player_id] = nil
    state.snapshot_cache_by_player[payload.player_id] = nil
    state.pending_push_reason[payload.player_id] = nil
    state.research_scope_by_player[payload.player_id] = nil
    state.research_source_entindex_by_player[payload.player_id] = nil
    scheduler.cancel("shop_snapshot_push_" .. tostring(payload.player_id))
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
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local request_id = tostring(payload.request_id or "")
    local silent_notification = payload.silent_notification == true
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
    local cooldown_remaining = purchase_cooldown_remaining(player_id, entry)
    if cooldown_remaining > 0 then
        return {
            ok = false,
            error = "purchase_cooldown",
            error_code = "purchase_cooldown",
            cooldown_remaining = cooldown_remaining,
        }
    end
    local stock = stock_state(player_id, entry)
    if stock and stock.count <= 0 then
        return { ok = false, error = "shop_stock_empty", error_code = "shop_stock_empty" }
    end
    local technology_group = entry.definition
        and entry.definition.technology_group or ""
    local research_definition = research_config.by_legacy_group[technology_group]
    local research_source = payload.source == "research_lab_ability"
        or payload.source == "advanced_auto_research"
        or (state.opened_players[player_id] == "research")
    local validated_research_source = false
    if entry.contenttype == "technology" and research_definition
        and not (technology_group == "gold_mine_efficiency"
            or technology_group == "gold_mine_crit") then
        local _, source_error = validate_research_source(
            player_id,
            payload.source_entindex,
            research_definition
        )
        if source_error then return { ok = false, error = source_error } end
        validated_research_source = true
    end
    local gold_mine_ability = payload.source == "gold_mine_ability"
    local gold_mine_source_entindex = tonumber(
        payload.source_entindex or payload.entindex
    )
    local mode = state.opened_players[player_id] or "shop"
    if not gold_mine_ability and not research_source then
        local allowed, mode_error = catalog.allowed_in_mode(entry, mode)
        if not allowed then
            return { ok = false, error = mode_error or "shop_mode_invalid" }
        end
    end
    if gold_mine_ability then
        local group = entry.definition and entry.definition.technology_group
        if group ~= "gold_mine_efficiency" and group ~= "gold_mine_crit" then
            return { ok = false, error = "gold_mine_technology_invalid" }
        end
        local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
            entindex = gold_mine_source_entindex,
        })
        if not building or building.building_id ~= "gold_mine"
            or tonumber(building.player_id) ~= player_id then
            return { ok = false, error = "gold_mine_not_owned" }
        end
    elseif entry.definition
        and (entry.definition.technology_group == "gold_mine_efficiency"
            or entry.definition.technology_group == "gold_mine_crit") then
        return { ok = false, error = "金矿科技只能通过金矿技能升级" }
    end
    local team = player_team(player_id)
    local active_rebirth = false
    if entry.contenttype == "rebirth"
        and entry.grant_type == "start_encounter" then
        local current = event_bus.request(
            events.MONSTER_ENCOUNTER_QUERY_REQUEST,
            {
                player_id = player_id,
                encounter_id = entry.encounter_id,
            }
        )
        active_rebirth = current and current.ok and current.active == true
    end
    -- Normal challenge sessions retain their existing free re-entry behavior.
    -- Rebirth sessions use the paid, ownership-checked branch below.
    if entry.contenttype == "challenge"
        and entry.grant_type == "start_encounter" then
        local current = event_bus.request(
            events.MONSTER_ENCOUNTER_QUERY_REQUEST,
            {
                player_id = player_id,
                encounter_id = entry.encounter_id,
            }
        )
        if current and current.ok and current.active then
            local resumed = grant_service.grant(player_id, team, entry, state)
            return resumed and resumed.ok and {
                ok = true,
                entry_id = entry.entryid,
                grant_result = resumed,
                resumed_without_charge = true,
            } or (resumed or { ok = false, error = "encounter_resume_failed" })
        end
    end
    if entry.contenttype == "technology" and research_definition
        and payload.source ~= "advanced_auto_research"
        and payload.research_queue_start ~= true then
        return enqueue_research({ player_id = player_id,
            source_entindex = payload.source_entindex,
            technology_group = technology_group, request_id = request_id })
    end
    local lane
    if entry.contenttype == "technology" and research_definition then
        lane = research_lane(player_id, payload.source_entindex, true)
        local conflicting = lane.pending
        for _, other in pairs(state.research_lanes) do
            if other.player_id == player_id then
                if other.pending and other.pending.technology_group == technology_group then
                    conflicting = other.pending
                end
                if other ~= lane then
                    for _, job in ipairs(other.queued or {}) do
                        if job.technology_group == technology_group then conflicting = job end
                    end
                end
            end
        end
        if conflicting then
            return { ok = false, error = "该研究所已有科技正在研究中",
                error_code = "technology_research_in_progress",
                cooldown_remaining = math.max(0, (conflicting.finish_at or 0) - game_time()) }
        end
    end
    local context = snapshot_context(
        player_id,
        "purchase_validation",
        gold_mine_ability and "gold_mine"
            or state.opened_players[player_id] or "shop",
        payload.source_entindex
    )
    context.gold_mine_ability = gold_mine_ability
    context.validated_research_source = validated_research_source
    local purchasable, reason = catalog.evaluate(
        player_id,
        entry,
        context
    )
    if not purchasable then
        return { ok = false, error = reason or "not_purchasable" }
    end
    if active_rebirth then
        local spend = event_bus.request(
            events.RESOURCE_TRY_SPEND_REQUEST,
            {
                player_id = player_id,
                team = team,
                wood = entry.woodcost,
                gold = entry.goldcost,
                population = 0,
                reason = "shop_rebirth_reentry:" .. entry.entryid,
            }
        )
        if not spend or not spend.ok then
            local result = spend or { ok = false, error = "resource_error" }
            remember_result(player_id, request_id, result)
            return result
        end
        local resumed = event_bus.request(
            events.MONSTER_ENCOUNTER_REENTER_REQUEST,
            {
                player_id = player_id,
                encounter_id = entry.encounter_id,
            }
        ) or { ok = false, error = "encounter_reentry_handler_missing" }
        if not resumed.ok then
            local refund = grant_service.refund(player_id, team, entry)
            local result = {
                ok = false,
                error = resumed.error or "encounter_reentry_failed",
                refunded = refund and refund.ok == true,
            }
            remember_result(player_id, request_id, result)
            return result
        end
        notify(player_id, "已返回转职挑战：" .. catalog.content_name(entry))
        push_snapshot(player_id, "rebirth_challenge_reentered")
        local result = {
            ok = true,
            entry_id = entry.entryid,
            grant_result = resumed,
            rebirth_reentered = true,
        }
        remember_result(player_id, request_id, result)
        return result
    end
    if entry.contenttype == "technology" and research_definition then
        local current_level = tonumber((state.technology_by_player[player_id]
            or {})[technology_group]) or 0
        local requested_level = tonumber(entry.definition.level) or 0
        if requested_level ~= current_level + 1 then
            return { ok = false, error = "technology_level_invalid" }
        end
        local started = event_bus.request(
            research_events.UPGRADE_BEGIN_REQUESTED,
            {
            player_id = player_id,
            tech_id = research_definition.tech_id,
            }
        )
        if not started or started.success ~= true then
            local failure = started and started.error_code
                or "resource_commit_failed"
            if not silent_notification then notify(player_id, failure, "error") end
            return { ok = false, error = failure, research_result = started }
        end
        lane.sequence = lane.sequence + 1
        local research_sequence = lane.sequence
        local current_state = state
        lane.pending = {
            transaction_id = started.transaction_id,
            player_id = player_id,
            entry_id = entry.entryid,
            technology_group = technology_group,
            display_name = research_definition.display_name,
            target_level = started.new_level,
            sequence = research_sequence,
            started_at = game_time(),
            finish_at = game_time() + TECHNOLOGY_RESEARCH_DURATION,
            icon_name = entry.icon or "",
            job_id = payload.research_job_id,
            manual = payload.research_queue_start == true,
        }
        lane.blocked_reason = ""
        publish_research(lane)
        notify(player_id, "正在研究：" .. research_definition.display_name
            .. " Lv." .. tostring(started.new_level))
        push_snapshot(player_id, "technology_research_started")
        scheduler.after(TECHNOLOGY_RESEARCH_DURATION, function()
            if current_state ~= state then return end
            local pending = lane.pending
            if not pending or pending.sequence ~= research_sequence
                or pending.transaction_id ~= started.transaction_id then return end
            local source = validate_research_source(player_id,
                lane.source_entindex, research_definition)
            if not source then
                cancel_research(lane, "research_source_removed")
                push_snapshot(player_id, "research_source_removed")
                return
            end
            -- This absolute deadline cannot be bypassed by a resource event,
            -- another right click, or a previously scheduled retry.
            lane.next_start_at = game_time() + AUTO_RESEARCH_RETRY_INTERVAL
            state.auto_research_next_at_by_player[player_id] =
                state.auto_research_next_at_by_player[player_id] or {}
            state.auto_research_next_at_by_player[player_id][technology_group] =
                lane.next_start_at
            local completed = event_bus.request(research_events.UPGRADE_COMMIT_REQUESTED,
                { transaction_id = pending.transaction_id })
            if not completed then
                event_bus.request(research_events.UPGRADE_ROLLBACK_REQUESTED, {
                    transaction_id = pending.transaction_id,
                    error_code = "research_completion_failed",
                })
            end
            lane.pending = nil
            if completed and completed.success == true then
                state.purchased_count[player_id] = state.purchased_count[player_id] or {}
                state.purchased_count[player_id][pending.entry_id] = 1
                merge_technology_levels(player_id, {
                    [technology_group] = completed.new_level or pending.target_level })
                if (tonumber(completed.new_level) or pending.target_level)
                    >= (tonumber(research_definition.max_level) or 0) then
                    lane.auto_research[technology_group] = nil
                end
                notify(player_id, "已完成研究：" .. pending.display_name
                    .. " Lv." .. tostring(completed.new_level))
            else
                if pending.manual then
                    table.insert(lane.queued, 1, {
                        job_id = pending.job_id, technology_group = pending.technology_group,
                        display_name = pending.display_name, target_level = pending.target_level,
                        entry_id = pending.entry_id, icon_name = pending.icon_name,
                    })
                    lane.blocked_reason = "研究失败已退款，等待重试；开始研究时扣费"
                end
                notify(player_id, "研究失败："
                    .. tostring(completed and completed.error_code
                        or "research_completion_failed"), "error")
            end
            publish_research(lane)
            -- Other public labs may have this player's same technology enabled.
            -- Publish their shared per-technology deadline even when selected
            -- there, so switching buildings cannot hide or bypass the pause.
            for _, other in pairs(state.research_lanes) do
                if other ~= lane and other.player_id == player_id
                    and other.auto_research[technology_group] then
                    if completed and completed.success == true
                        and (tonumber(completed.new_level) or pending.target_level)
                            >= (tonumber(research_definition.max_level) or 0) then
                        other.auto_research[technology_group] = nil
                    end
                    publish_research(other)
                end
            end
            push_snapshot(player_id, "research_upgrade_completed")
            if #lane.queued > 0 then
                if completed and completed.success == true then
                    run_research_queue(lane.key)
                else
                    queue_research(lane.key, AUTO_RESEARCH_RETRY_INTERVAL)
                end
            elseif next(lane.auto_research) then
                queue_auto_research(lane.key, AUTO_RESEARCH_RETRY_INTERVAL)
            end
        end, "shop_technology_research:" .. lane.key)
        local result = { ok = true, entry_id = entry.entryid,
            research_started = true, research_result = started }
        remember_result(player_id, request_id, result)
        return result
    end
    local spend = event_bus.request(
        events.RESOURCE_TRY_SPEND_REQUEST,
        {
            player_id = player_id,
            team = team,
            wood = entry.woodcost,
            gold = entry.goldcost,
            population = 0,
            reason = "shop_purchase:" .. entry.entryid,
        }
    )
    if not spend or not spend.ok then
        if not silent_notification then
            notify(
                player_id,
                spend and spend.error or "购买失败",
                "error"
            )
        end
        return spend or { ok = false, error = "resource_error" }
    end
    local granted = grant_service.grant(
        player_id,
        team,
        entry,
        state
    )
    if not granted or not granted.ok then
        grant_service.refund(player_id, team, entry)
        if not silent_notification then
            notify(
                player_id,
                granted and granted.error or "发放失败",
                "error"
            )
        end
        return granted or { ok = false, error = "grant_failed" }
    end
    state.purchased_count[player_id] =
        state.purchased_count[player_id] or {}
    local counts = state.purchased_count[player_id]
    counts[entry.entryid] = (counts[entry.entryid] or 0) + 1
    consume_stock(player_id, entry)
    set_purchase_cooldown(player_id, entry)
    if not silent_notification then
        notify(player_id, "购买成功：" .. catalog.content_name(entry))
    end
    push_snapshot(player_id, "purchase_completed")
    local result = {
        ok = true,
        entry_id = entry.entryid,
        grant_result = granted,
    }
    remember_result(player_id, request_id, result)
    return result
end

local function research_wait_reason(result)
    local code = result and (result.error_code or result.error) or "research_start_failed"
    local messages = {
        insufficient_gold = "金币不足", insufficient_wood = "木材不足",
        prerequisite_not_met = "前置科技未满足", reincarnation_not_met = "转职要求未满足",
        research_access_not_met = "研究所不可用", resource_commit_failed = "资源不足或扣费失败",
        technology_research_in_progress = "同科技正在其他研究所处理",
    }
    return (messages[code] or tostring(code)) .. "；开始研究时扣费"
end

queue_research = function(key, delay)
    local current_state = state
    scheduler.after(delay or 0, function()
        if state == current_state then run_research_queue(key) end
    end, "shop_research_queue:" .. key)
end

run_research_queue = function(key)
    local lane = state.research_lanes[key]
    if not lane or lane.pending then return end
    local current_state = event_bus.request(research_events.STATE_GET_REQUESTED,
        { player_id = lane.player_id })
    merge_technology_levels(lane.player_id,
        current_state and current_state.legacy_levels or {})
    while #lane.queued > 0 do
        local job = lane.queued[1]
        local definition = research_config.by_legacy_group[job.technology_group]
        if not validate_research_source(lane.player_id, lane.source_entindex, definition) then
            cancel_research(lane, "research_source_removed")
            push_snapshot(lane.player_id, "research_source_removed")
            return
        end
        local current = tonumber((state.technology_by_player[lane.player_id] or {})
            [job.technology_group]) or 0
        if current >= job.target_level then
            -- A debug/external upgrade may already have completed a queued target.
            table.remove(lane.queued, 1)
        else
            table.remove(lane.queued, 1)
            local result = purchase({ player_id = lane.player_id,
                source_entindex = lane.source_entindex, entry_id = job.entry_id,
                source = "research_lab_ability", silent_notification = true,
                research_queue_start = true, research_job_id = job.job_id })
            if result and result.ok then return end
            table.insert(lane.queued, 1, job)
            lane.blocked_reason = research_wait_reason(result)
            publish_research(lane)
            push_snapshot(lane.player_id, "research_queue_waiting")
            queue_research(key, AUTO_RESEARCH_RETRY_INTERVAL)
            return
        end
    end
    lane.blocked_reason = ""
    publish_research(lane)
    push_snapshot(lane.player_id, "research_queue_empty")
    if next(lane.auto_research) then queue_auto_research(key, 0) end
end

enqueue_research = function(payload)
    local player_id = tonumber(payload.player_id)
    local group = tostring(payload.technology_group or "")
    local request_id = tostring(payload.request_id or "")
    if not valid_player_id(player_id) then return { ok = false, error = "player_id_invalid" } end
    local cached = cached_result(player_id, request_id)
    if cached then return cached end
    local definition = research_config.by_legacy_group[group]
    local source = tonumber(payload.source_entindex or payload.entindex)
    local building, source_error = validate_research_source(player_id, source, definition)
    if not building then return { ok = false, error = source_error } end
    local lane = research_lane(player_id, source, true)
    if research_job_count(lane) >= RESEARCH_QUEUE_CAPACITY then
        return { ok = false, error = "研究队列已满（1个研究中＋6个等待）",
            error_code = "research_queue_full" }
    end
    for _, other in pairs(state.research_lanes) do
        if other ~= lane and other.player_id == player_id then
            local occupied = other.pending and other.pending.technology_group == group
            for _, job in ipairs(other.queued or {}) do
                occupied = occupied or job.technology_group == group
            end
            if occupied then return { ok = false, error = "同科技已在其他研究所排队或研究",
                error_code = "technology_research_in_progress" } end
        end
    end
    local current_state = event_bus.request(research_events.STATE_GET_REQUESTED,
        { player_id = player_id })
    merge_technology_levels(player_id, current_state and current_state.legacy_levels or {})
    local target = tonumber((state.technology_by_player[player_id] or {})[group]) or 0
    if lane.pending and lane.pending.technology_group == group then
        target = math.max(target, lane.pending.target_level)
    end
    for _, job in ipairs(lane.queued) do
        if job.technology_group == group then target = math.max(target, job.target_level) end
    end
    target = target + 1
    if target > (tonumber(definition.max_level) or 0) then
        return { ok = false, error = "该科技已研究或排队至最高等级", error_code = "max_level_reached" }
    end
    local entry = catalog.find_technology_entry(group, target)
    if not entry or entry.enabled == false then
        return { ok = false, error = "研究配置不可用", error_code = "research_config_invalid" }
    end
    lane.next_job_id = lane.next_job_id + 1
    local job = { job_id = lane.key .. ":" .. tostring(lane.next_job_id),
        technology_group = group, display_name = definition.display_name,
        target_level = target, entry_id = entry.entryid, icon_name = entry.icon or "" }
    lane.queued[#lane.queued + 1] = job
    if not lane.pending then run_research_queue(lane.key) else publish_research(lane) end
    local result = { ok = true, queued = true, job_id = job.job_id, target_level = target,
        entry_id = entry.entryid, research_started = lane.pending
            and lane.pending.job_id == job.job_id or false,
        research = research_snapshot(player_id, source) }
    remember_result(player_id, request_id, result)
    push_snapshot(player_id, "research_enqueued")
    return result
end

local function purchase_next_technology(payload)
    local player_id = tonumber(payload.player_id)
    local group = tostring(payload.technology_group or "")
    if not valid_player_id(player_id) or group == "" then
        return { ok = false, error = "technology_request_invalid" }
    end
    if research_config.by_legacy_group[group]
        and payload.source ~= "advanced_auto_research" then
        return enqueue_research(payload)
    end
    local research_state = event_bus.request(research_events.STATE_GET_REQUESTED, {
        player_id = player_id,
    })
    if research_state and research_state.ok == true then
        merge_technology_levels(player_id, research_state.legacy_levels)
    end
    local levels = state.technology_by_player[player_id] or {}
    local target_level = (tonumber(levels[group]) or 0) + 1
    local entry = catalog.find_technology_entry(group, target_level)
    if not entry then
        local max_level = catalog.max_technology_level(group)
        if max_level > 0 and target_level > max_level then
            return { ok = false, error = "科技已满级" }
        end
        return {
            ok = false,
            error = "升级配置缺失：" .. group
                .. " Lv." .. tostring(target_level),
        }
    end
    return purchase({
        player_id = player_id,
        entry_id = entry.entryid,
        request_id = tostring(payload.request_id or ""),
        source = payload.source,
        source_entindex = tonumber(payload.source_entindex or payload.entindex),
        silent_notification = payload.silent_notification,
    })
end

local function run_auto_research(key)
    local lane = state.research_lanes[key]
    if not lane or not next(lane.auto_research) then return end
    if lane.pending then return end -- Completion schedules the next attempt.
    if #lane.queued > 0 then run_research_queue(key); return end
    if game_time() < lane.next_start_at then
        queue_auto_research(key, lane.next_start_at - game_time())
        return
    end
    local player_id = lane.player_id
    local research_state = event_bus.request(research_events.STATE_GET_REQUESTED,
        { player_id = player_id })
    merge_technology_levels(player_id,
        research_state and research_state.legacy_levels or {})
    local retry_delay = AUTO_RESEARCH_RETRY_INTERVAL
    for _, definition in ipairs(research_config.technologies) do
        local group = definition.legacy_group
        if lane.auto_research[group] then
            local building = validate_research_source(player_id,
                lane.source_entindex, definition)
            if not building then
                cancel_research(lane, "research_source_removed")
                push_snapshot(player_id, "research_source_removed")
                return
            end
            local current = tonumber((state.technology_by_player[player_id] or {})[group]) or 0
            if current >= (tonumber(definition.max_level) or 0) then
                lane.auto_research[group] = nil
                publish_research(lane)
                push_snapshot(player_id, "auto_research_max_level")
            elseif game_time() < auto_research_start_at(lane, group) then
                retry_delay = math.min(retry_delay,
                    auto_research_start_at(lane, group) - game_time())
            else
                local result = purchase_next_technology({
                    player_id = player_id, technology_group = group,
                    source_entindex = lane.source_entindex,
                    source = "advanced_auto_research", silent_notification = true,
                })
                if result and result.ok == true then return end
                -- Keep the choice enabled while waiting for resources or prerequisites.
                -- Other enabled technologies at this building may still be affordable.
            end
        end
    end
    if next(lane.auto_research) then
        queue_auto_research(key, retry_delay)
    end
end

queue_auto_research = function(key, delay)
    local current_state = state
    scheduler.after(delay or 0, function()
        if current_state == state then run_auto_research(key) end
    end, "shop_auto_research:" .. key)
end

local function toggle_auto_research(payload)
    local player_id = tonumber(payload and payload.player_id)
    local group = tostring(payload and payload.technology_group or "")
    local definition = research_config.by_legacy_group[group]
    if not valid_player_id(player_id) or not definition
        or not research_building_id(definition) then
        return { ok = false, error = "auto_research_request_invalid" }
    end
    local building, source_error = validate_research_source(player_id,
        payload.source_entindex, definition)
    if not building then return { ok = false, error = source_error } end
    local lane = research_lane(player_id, payload.source_entindex, true)
    if lane.auto_research[group] then
        lane.auto_research[group] = nil
    else
        local research_state = event_bus.request(research_events.STATE_GET_REQUESTED,
            { player_id = player_id })
        merge_technology_levels(player_id,
            research_state and research_state.legacy_levels or {})
        if (tonumber((state.technology_by_player[player_id] or {})[group]) or 0)
            >= (tonumber(definition.max_level) or 0) then
            return { ok = false, error = "科技已满级", error_code = "max_level_reached" }
        end
        lane.auto_research[group] = true
        local next_at = research_snapshot(player_id, lane.source_entindex).next_start_at
        queue_auto_research(lane.key, math.max(0, next_at - game_time()))
    end
    if not next(lane.auto_research) then
        scheduler.cancel("shop_auto_research:" .. lane.key)
    end
    publish_research(lane)
    push_snapshot(player_id, "auto_research_toggled")
    return { ok = true, enabled = lane.auto_research[group] == true,
        research = research_snapshot(player_id, payload.source_entindex) }
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
    if payload.building_id == "building_research_lab" then
        local player_id = tonumber(payload.player_id)
        if valid_player_id(player_id) then
            state.research_unlocked[player_id] = true
        end
    end
    if payload.building_id == "building_advanced_research_lab" then
        local player_id = tonumber(payload.player_id)
        if valid_player_id(player_id) then
            state.advanced_researcher_unlocked[player_id] = true
        end
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
    for _, lane in pairs(state.research_lanes) do
        if tonumber(lane.source_entindex) == tonumber(payload.entindex) then
            cancel_research(lane, "research_source_destroyed")
        end
    end
    change_building_count(payload, -1)
    if payload.building_id == "main_city" then
        state.city_level_by_team[payload.team] = 0
    end
    if payload.building_id == "building_research_lab" then
        local player_id = tonumber(payload.player_id)
        if valid_player_id(player_id) then
            state.research_unlocked[player_id] = false
        end
    end
    if payload.building_id == "building_advanced_research_lab" then
        local player_id = tonumber(payload.player_id)
        if valid_player_id(player_id) then
            state.advanced_researcher_unlocked[player_id] = false
        end
    end
    push_team(payload.team, "building_destroyed")
end
local function on_player_removed(payload)
    local player_id = tonumber(payload and payload.player_id)
    for _, lane in pairs(state.research_lanes) do
        if lane.player_id == player_id then
            cancel_research(lane, "research_player_removed")
        end
    end
    if player_id then close_shop({ player_id = player_id }) end
end
local function on_player_changed(payload)
    -- Abyss weapon synthesis happens synchronously on the boss kill. Delay its
    -- shop projection to the configured two-second kill refresh instead of
    -- changing the entrance while the teleport/purchase flow is still closing.
    if tostring(payload and payload.reason or ""):find(
        "challenge_material_synthesis:",
        1,
        true
    ) == 1 then
        return
    end
    push_snapshot(payload.player_id, payload.reason or "player_changed")
end
local function on_resource_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if valid_player_id(player_id) then
        push_snapshot(player_id, "resource_changed")
    elseif payload and payload.team then
        push_team(payload.team, "resource_changed")
    end
end
local function on_monster_killed(payload)
    local player_id = tonumber(payload and payload.player_id)
    local encounter_id = tostring(payload and payload.encounter_id or "")
    if not valid_player_id(player_id)
        or not encounter_id:find("encounter_challenge_", 1, true) then
        return
    end
    local victim = payload and payload.victim
    local kill_id = victim and victim.entindex
        and tostring(victim:entindex()) or DoUniqueString("challenge_kill")
    scheduler.after(2, function()
        push_snapshot(player_id, "challenge_kill_refresh")
    end, "shop_challenge_kill_refresh:" .. tostring(player_id)
        .. ":" .. encounter_id .. ":" .. kill_id)
end
local function get_technology_state(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local team = player_team(player_id)
    local buildings = event_bus.request(events.BUILDING_LIST_REQUEST, {})
    for _, building in ipairs(buildings and buildings.buildings or {}) do
        if building.building_id == "building_research_lab"
            and tonumber(building.player_id) == player_id then
            state.research_unlocked[player_id] = true
        elseif building.building_id == "building_advanced_research_lab"
            and tonumber(building.team) == tonumber(team) then
            state.advanced_researcher_unlocked[player_id] = true
        end
    end
    return {
        ok = true,
        research_unlocked = state.research_unlocked[player_id] == true,
        advanced_researcher_unlocked =
            state.advanced_researcher_unlocked[player_id] == true,
        levels = state.technology_by_player[player_id] or {},
        research = research_snapshot(player_id, payload.source_entindex),
    }
end

local function set_debug_unlock(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    state.debug_all_unlocked[player_id] = payload.unlocked ~= false
    push_snapshot(player_id, "cheat_shop_unlock")
    print(string.format("[SHOP_DEBUG_UNLOCK] player=%s unlocked=%s",
        tostring(player_id), tostring(state.debug_all_unlocked[player_id])))
    return {
        ok = true,
        player_id = player_id,
        unlocked = state.debug_all_unlocked[player_id],
    }
end

local function on_research_level_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not valid_player_id(player_id) then return end
    merge_technology_levels(player_id, payload.legacy_levels)
    push_snapshot(player_id, "research_level_changed")
end

function M.init()
    for _, lane in pairs(state.research_lanes or {}) do
        cancel_research(lane, "research_session_reset")
    end
    for player_id in pairs(state.pending_push_reason or {}) do
        scheduler.cancel("shop_snapshot_push_" .. tostring(player_id))
    end
    reset_state()
    require("systems/book_auto_purchase_service").init(purchase)
    require("debug/technology_cheat_handler").register(
        state, push_snapshot
    )
    event_bus.handle_request(events.SHOP_OPEN_REQUEST, open_shop)
    event_bus.handle_request(events.SHOP_CLOSE_REQUEST, close_shop)
    event_bus.handle_request(events.SHOP_PURCHASE_REQUEST, purchase)
    event_bus.handle_request(events.SHOP_DEBUG_UNLOCK_REQUEST, set_debug_unlock)
    event_bus.handle_request(
        events.SHOP_AUTO_RESEARCH_TOGGLE_REQUEST,
        toggle_auto_research
    )
    event_bus.handle_request(
        events.TECHNOLOGY_PURCHASE_NEXT_REQUEST,
        purchase_next_technology
    )
    event_bus.handle_request(
        events.TECHNOLOGY_STATE_GET_REQUEST,
        get_technology_state
    )
    event_bus.subscribe(events.PLAYER_DISCONNECTED, on_player_removed)
    event_bus.subscribe(events.PLAYER_DEFEATED, on_player_removed)
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resource_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.HERO_SUMMON_STATE_CHANGED, on_player_changed)
    event_bus.subscribe(events.PLAYER_ENTITLEMENT_CHANGED, on_player_changed)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, on_player_changed)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_player_changed)
    event_bus.subscribe(events.MONSTER_KILLED, on_monster_killed)
    event_bus.subscribe(events.MONSTER_ENCOUNTER_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if not valid_player_id(player_id) then return end
        if payload.status ~= "cancelled" and payload.status ~= "retry_ready" then
            return
        end
        local encounter_id = payload.encounter and payload.encounter.encounter_id
        for _, entry in ipairs(catalog.entries()) do
            if entry.contenttype == "rebirth" and entry.encounter_id == encounter_id then
                if payload.status == "cancelled" then
                    set_purchase_cooldown(player_id, entry, payload.retry_cooldown_seconds)
                end
                push_snapshot(player_id, "rebirth_" .. payload.status)
                return
            end
        end
    end)
    event_bus.subscribe(research_events.LEVEL_CHANGED, on_research_level_changed)
    event_bus.subscribe(events.GAME_STARTED, function()
        scheduler.after(0.1, function()
            for player_id, _ in pairs(state.opened_players) do
                push_snapshot(player_id, "early_final_cooldown_started")
            end
        end, "shop_early_final_cooldown_start")
        scheduler.after(1 * 60, function()
            for player_id, _ in pairs(state.opened_players) do
                push_snapshot(player_id, "early_final_unlocked")
            end
        end, "shop_early_final_unlock")
    end)
end
M._advanced_research_for_test = {
    open_shop = open_shop,
    purchase_next = purchase_next_technology,
    toggle = toggle_auto_research,
    run = run_auto_research,
    state = function() return state end,
}
return M
