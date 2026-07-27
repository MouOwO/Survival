local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local catalog = require("systems/shop_catalog")
local grant_service = require("systems/shop_grant_service")
local challenge_definitions = require("config/generated/challenge_definitions")
local research_config = require("config/research_technology_config")
local research_events = require("research/research_event_names")
local M = {}
local state = {}
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
    for _, challenge in ipairs(challenge_definitions.rows or {}) do
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
        active_challenge_encounters = active_challenge_encounters(player_id),
        technology_levels = state.technology_by_player,
        research_unlocked = state.research_unlocked[player_id] == true,
        advanced_researcher_unlocked = state.advanced_researcher_unlocked[player_id] == true,
        debug_all_unlocked = state.debug_all_unlocked[player_id] == true,
        ui_mode = mode or state.opened_players[player_id] or "shop",
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
    }
    if not values_equal(previous.resources or {}, current.resources or {}) then
        patch.resources = current.resources
    end
    if previous.ui_mode ~= current.ui_mode
        or previous.config_version ~= current.config_version
        or not values_equal(previous.categories or {}, current.categories or {}) then
        patch.categories = current.categories
    end
    local changed_any = patch.resources ~= nil or patch.categories ~= nil
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
local function push_snapshot(player_id, reason)
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
local function open_shop(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local mode = payload.mode == "research" and "research" or "shop"
    if mode == "research" then
        local team = player_team(player_id)
        if (building_counts(team).building_research_lab or 0) < 1 then
            return { ok = false, error = "请先建造研究所" }
        end
        local source_entindex = tonumber(payload.source_entindex)
        if source_entindex and source_entindex > 0 then
            local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
                entindex = source_entindex,
            })
            if not building
                or building.building_id ~= "building_research_lab"
                or tonumber(building.player_id) ~= player_id then
                return { ok = false, error = "研究所归属验证失败" }
            end
        end
    else
        local summon = summon_snapshot(player_id)
        if summon.hero_summoned ~= 1
            and state.debug_all_unlocked[player_id] ~= true then
            return { ok = false, error = "请先在英雄祭坛召唤英雄" }
        end
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
    local gold_mine_ability = payload.source == "gold_mine_ability"
    if gold_mine_ability then
        local group = entry.definition and entry.definition.technology_group
        if group ~= "gold_mine_efficiency" and group ~= "gold_mine_crit" then
            return { ok = false, error = "gold_mine_technology_invalid" }
        end
        local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
            entindex = tonumber(payload.entindex),
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
    -- Re-entering an unfinished normal challenge only teleports the hero back
    -- to its existing session. It must not charge the entrance fee again and
    -- therefore runs before resource validation. Rebirth encounters retain
    -- their one-completion flow.
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
    local context = snapshot_context(
        player_id,
        "purchase_validation",
        gold_mine_ability and "gold_mine"
            or state.opened_players[player_id] or "shop"
    )
    context.gold_mine_ability = gold_mine_ability
    local purchasable, reason = catalog.evaluate(
        player_id,
        entry,
        context
    )
    if not purchasable then
        return { ok = false, error = reason or "not_purchasable" }
    end
    local technology_group = entry.definition
        and entry.definition.technology_group or ""
    local research_definition = research_config.by_legacy_group[technology_group]
    if entry.contenttype == "technology" and research_definition then
        local current_level = tonumber((state.technology_by_player[player_id]
            or {})[technology_group]) or 0
        local requested_level = tonumber(entry.definition.level) or 0
        if requested_level ~= current_level + 1 then
            return { ok = false, error = "technology_level_invalid" }
        end
        local upgraded = event_bus.request(research_events.UPGRADE_REQUESTED, {
            player_id = player_id,
            tech_id = research_definition.tech_id,
        })
        if not upgraded or upgraded.success ~= true then
            local failure = upgraded and upgraded.error_code
                or "resource_commit_failed"
            notify(player_id, failure, "error")
            return { ok = false, error = failure, research_result = upgraded }
        end
        state.purchased_count[player_id] =
            state.purchased_count[player_id] or {}
        state.purchased_count[player_id][entry.entryid] = 1
        notify(player_id, "研究成功：" .. research_definition.display_name
            .. " Lv." .. tostring(upgraded.new_level))
        push_snapshot(player_id, "research_upgrade_completed")
        local result = { ok = true, entry_id = entry.entryid,
            research_result = upgraded }
        remember_result(player_id, request_id, result)
        return result
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

local function purchase_next_technology(payload)
    local player_id = tonumber(payload.player_id)
    local group = tostring(payload.technology_group or "")
    if not valid_player_id(player_id) or group == "" then
        return { ok = false, error = "technology_request_invalid" }
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
        entindex = payload.entindex,
    })
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
            if state.opened_players[player_id] == "research" then
                state.opened_players[player_id] = nil
            end
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
end
return M
--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx