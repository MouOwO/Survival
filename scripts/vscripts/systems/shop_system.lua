local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local catalog = require("systems/shop_catalog")
local grant_service = require("systems/shop_grant_service")
local challenge_definitions = require("config/generated/challenge_definitions")
local rebirth_challenges = require("config/generated/rebirth_challenges")
local research_config = require("config/research_technology_config")
local research_events = require("research/research_event_names")
local M = {}
local state = {}
local TECHNOLOGY_RESEARCH_DURATION = 2
local AUTO_RESEARCH_RETRY_INTERVAL = 1
local queue_auto_research
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
        technology_cooldown_until_by_team = {},
        technology_cooldown_source_group_by_team = {},
        technology_cooldown_source_entry_by_team = {},
        technology_cooldown_sequence_by_team = {},
        technology_research_transaction_by_team = {},
        research_scope_by_player = {},
        research_source_entindex_by_player = {},
        auto_research_by_team = {},
        purchase_cooldown_until_by_player = {},
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
local function team_player(team)
    local limit = tonumber(DOTA_MAX_TEAM_PLAYERS) or 24
    for player_id = 0, limit - 1 do
        if valid_player_id(player_id) and player_team(player_id) == team then
            return player_id
        end
    end
    return nil
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
    local duration = tonumber(entry and entry.purchase_cooldown_seconds) or 0
    if duration <= 0 then return 0 end
    local by_entry = state.purchase_cooldown_until_by_player[player_id] or {}
    return math.max(0, (by_entry[entry.entryid] or 0) - game_time())
end
local function set_purchase_cooldown(player_id, entry)
    local duration = tonumber(entry and entry.purchase_cooldown_seconds) or 0
    if duration <= 0 then return end
    state.purchase_cooldown_until_by_player[player_id] =
        state.purchase_cooldown_until_by_player[player_id] or {}
    state.purchase_cooldown_until_by_player[player_id][entry.entryid] =
        game_time() + duration
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
                total = tonumber(entry.purchase_cooldown_seconds) or 0,
                until_time = game_time() + remaining,
            }
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
local function snapshot_context(player_id, reason, mode)
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
        technology_cooldown_remaining = math.max(0,
            (state.technology_cooldown_until_by_team[team] or 0)
                - game_time()),
        technology_cooldown_total = TECHNOLOGY_RESEARCH_DURATION,
        technology_cooldown_until = state.technology_cooldown_until_by_team[team] or 0,
        technology_cooldown_source_group = state.technology_cooldown_source_group_by_team
            and state.technology_cooldown_source_group_by_team[team] or "",
        technology_cooldown_source_entry = state.technology_cooldown_source_entry_by_team
            and state.technology_cooldown_source_entry_by_team[team] or "",
        technology_cooldown_sequence = state.technology_cooldown_sequence_by_team
            and state.technology_cooldown_sequence_by_team[team] or 0,
        wave_state = wave_state,
        ui_mode = mode or state.opened_players[player_id] or "shop",
        research_scope = state.research_scope_by_player[player_id] or "",
        research_source_entindex =
            state.research_source_entindex_by_player[player_id] or -1,
        purchase_cooldowns = purchase_cooldown_snapshot(player_id),
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
        purchase_cooldowns = current.purchase_cooldowns,
    }
    if not values_equal(previous.resources or {}, current.resources or {}) then
        patch.resources = current.resources
    end
    if not values_equal(previous.purchase_cooldowns or {}, current.purchase_cooldowns or {}) then
        patch.purchase_cooldowns = current.purchase_cooldowns
    end
    if previous.ui_mode ~= current.ui_mode
        or previous.config_version ~= current.config_version
        or not values_equal(previous.categories or {}, current.categories or {}) then
        patch.categories = current.categories
    end
    local changed_any = patch.resources ~= nil or patch.categories ~= nil
        or patch.purchase_cooldowns ~= nil
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
    state.pending_push_reason[player_id] = reason or "changed"
    scheduler.after(0.05, function()
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
    if entry.contenttype == "technology" and research_definition then
        local research_remaining = math.max(0,
            (state.technology_cooldown_until_by_team[team] or 0)
                - game_time())
        if research_remaining > 0
            or state.technology_research_transaction_by_team[team] then
            return {
                ok = false,
                error = "已有科技正在研究中",
                error_code = "technology_research_in_progress",
                cooldown_remaining = research_remaining,
            }
        end
    end
    local context = snapshot_context(
        player_id,
        "purchase_validation",
        gold_mine_ability and "gold_mine"
            or state.opened_players[player_id] or "shop"
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
            notify(player_id, failure, "error")
            return { ok = false, error = failure, research_result = started }
        end
        state.technology_cooldown_until_by_team[team] =
            game_time() + TECHNOLOGY_RESEARCH_DURATION
        state.technology_cooldown_source_group_by_team[team] = technology_group
        state.technology_cooldown_source_entry_by_team[team] = entry.entryid
        state.technology_cooldown_sequence_by_team[team] =
            (state.technology_cooldown_sequence_by_team[team] or 0) + 1
        local research_sequence = state.technology_cooldown_sequence_by_team[team]
        state.technology_research_transaction_by_team[team] = {
            transaction_id = started.transaction_id,
            player_id = player_id,
            entry_id = entry.entryid,
            technology_group = technology_group,
            display_name = research_definition.display_name,
            target_level = started.new_level,
            sequence = research_sequence,
        }
        event_bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, {
            team = team,
            researching = 1,
            research_group = technology_group,
            research_target_level = started.new_level,
            source_entindex = tonumber(payload.source_entindex),
        })
        notify(player_id, "正在研究：" .. research_definition.display_name
            .. " Lv." .. tostring(started.new_level))
        push_team(team, "technology_research_started")
        scheduler.after(TECHNOLOGY_RESEARCH_DURATION, function()
            local pending = state.technology_research_transaction_by_team[team]
            if not pending or pending.sequence ~= research_sequence
                or pending.transaction_id ~= started.transaction_id then
                return
            end
            local completed = event_bus.request(
                research_events.UPGRADE_COMMIT_REQUESTED,
                { transaction_id = pending.transaction_id }
            )
            if not completed then
                event_bus.request(
                    research_events.UPGRADE_ROLLBACK_REQUESTED,
                    {
                        transaction_id = pending.transaction_id,
                        error_code = "research_completion_failed",
                    }
                )
            end
            state.technology_research_transaction_by_team[team] = nil
            state.technology_cooldown_until_by_team[team] = 0
            state.technology_cooldown_source_group_by_team[team] = ""
            state.technology_cooldown_source_entry_by_team[team] = ""
            event_bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, {
                team = team,
                researching = 0,
            })
            if completed and completed.success == true then
                state.purchased_count[pending.player_id] =
                    state.purchased_count[pending.player_id] or {}
                state.purchased_count[pending.player_id][pending.entry_id] = 1
                notify(pending.player_id, "已完成研究：" .. pending.display_name
                    .. " Lv." .. tostring(completed.new_level))
                push_team(team, "research_upgrade_completed")
                if next(state.auto_research_by_team[team] or {}) then
                    queue_auto_research(team, 0)
                end
                return
            end
            local failure = completed and completed.error_code
                or "research_completion_failed"
            notify(pending.player_id, "研究失败：" .. failure, "error")
            push_team(team, "research_upgrade_failed")
        end, "shop_technology_cooldown:" .. tostring(team))
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

local function purchase_next_technology(payload)
    local player_id = tonumber(payload.player_id)
    local group = tostring(payload.technology_group or "")
    if not valid_player_id(player_id) or group == "" then
        return { ok = false, error = "technology_request_invalid" }
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

local function run_auto_research(team)
    if state.technology_research_transaction_by_team[team] then
        queue_auto_research(team, AUTO_RESEARCH_RETRY_INTERVAL)
        return
    end
    local bucket = state.auto_research_by_team[team] or {}
    for _, definition in ipairs(research_config.technologies) do
        local group = definition.legacy_group
        local enabled = bucket[group]
        if enabled then
            local player_id = tonumber(enabled.player_id) or team_player(team)
            local building, source_error = validate_research_source(
                player_id,
                enabled.source_entindex,
                definition
            )
            if not building or definition.building_id ~= "advanced_research_lab" then
                bucket[group] = nil
            else
                local research_state = event_bus.request(
                    research_events.STATE_GET_REQUESTED,
                    { player_id = player_id }
                )
                merge_technology_levels(
                    player_id,
                    research_state and research_state.legacy_levels or {}
                )
                local current = tonumber((state.technology_by_player[player_id]
                    or {})[group]) or 0
                if current >= (tonumber(definition.max_level) or 0) then
                    bucket[group] = nil
                else
                    local result = purchase_next_technology({
                        player_id = player_id,
                        technology_group = group,
                        source_entindex = enabled.source_entindex,
                        source = "advanced_auto_research",
                        silent_notification = true,
                    })
                    if not result or result.ok ~= true then
                        queue_auto_research(team, AUTO_RESEARCH_RETRY_INTERVAL)
                    end
                    return
                end
            end
        end
    end
end

queue_auto_research = function(team, delay)
    scheduler.after(delay or 0, function()
        run_auto_research(team)
    end, "shop_auto_research:" .. tostring(team))
end

local function toggle_auto_research(payload)
    local player_id = tonumber(payload and payload.player_id)
    local group = tostring(payload and payload.technology_group or "")
    local definition = research_config.by_legacy_group[group]
    if not valid_player_id(player_id) or not definition
        or definition.building_id ~= "advanced_research_lab" then
        return { ok = false, error = "auto_research_request_invalid" }
    end
    local building, source_error = validate_research_source(
        player_id,
        payload.source_entindex,
        definition
    )
    if not building then return { ok = false, error = source_error } end
    local team = player_team(player_id)
    state.auto_research_by_team[team] = state.auto_research_by_team[team] or {}
    local bucket = state.auto_research_by_team[team]
    if bucket[group] then
        bucket[group] = nil
    else
        bucket[group] = {
            player_id = player_id,
            source_entindex = building.entindex,
        }
        queue_auto_research(team, 0)
    end
    push_team(team, "auto_research_toggled")
    return { ok = true, enabled = bucket[group] ~= nil }
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
    push_team(payload.team, "resource_changed")
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
    reset_state()
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
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resource_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.HERO_SUMMON_STATE_CHANGED, on_player_changed)
    event_bus.subscribe(events.PLAYER_ENTITLEMENT_CHANGED, on_player_changed)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, on_player_changed)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_player_changed)
    event_bus.subscribe(events.MONSTER_KILLED, on_monster_killed)
    event_bus.subscribe(research_events.LEVEL_CHANGED, on_research_level_changed)
    event_bus.subscribe(events.GAME_STARTED, function()
        scheduler.after(15 * 60, function()
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
