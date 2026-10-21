local event_bus = require("core/event_bus")
local events = require("core/events")
local content_id_aliases = require("config/content_id_aliases")
local gameplay_stats_config = require("config/generated/player_gameplay_stats")
local profile_service = require("systems/player_profile_service")
local weapon_definitions = require("config/generated/weapon_definitions")
local item_definitions = require("config/generated/item_definitions")

local M = {}
local inventory_by_player = {}
local hydrated_by_player = {}
local normalize_map
local match_inventory_by_player = {}
local profile_refresh_by_player = {}
local mutation_depth_by_player = {}

local function match_item(id)
    return weapon_definitions.by_id[id] ~= nil or item_definitions.by_id[id] ~= nil
end

local function match_bucket(player_id)
    match_inventory_by_player[player_id] = match_inventory_by_player[player_id] or {}
    return match_inventory_by_player[player_id]
end

local function copy_map(value)
    local result = {}
    for key, child in pairs(value or {}) do result[tostring(key)] = child end
    return result
end
local function deep_copy(value)
    if type(value)~='table' then return value end
    local result={};for key,child in pairs(value) do result[key]=deep_copy(child) end;return result
end

local function finite_number(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge
        or value == -math.huge then return nil end
    return value
end

local function apply_gameplay_effects(stats, effects)
    local next_stats = copy_map(stats)
    local changes = {}
    for _, effect in ipairs(effects or {}) do
        local field_id = tostring(effect.field_id or "")
        local delta = finite_number(effect.value)
        local definition = gameplay_stats_config.by_id[field_id]
        if not definition or definition.enabled == false then
            return nil, nil, "gameplay_stat_unknown:" .. field_id
        end
        if delta == nil or delta == 0 then
            return nil, nil, "gameplay_stat_delta_invalid:" .. field_id
        end
        local old_value = finite_number(next_stats[field_id])
        if old_value == nil then
            return nil, nil, "gameplay_stat_value_invalid:" .. field_id
        end
        local next_value = old_value + delta
        if definition.storage_type == "integer"
            and next_value ~= math.floor(next_value) then
            return nil, nil, "gameplay_stat_requires_integer:" .. field_id
        end
        if definition.min_value ~= nil
            and next_value < tonumber(definition.min_value) then
            return nil, nil, "gameplay_stat_below_min:" .. field_id
        end
        if definition.max_value ~= nil
            and next_value > tonumber(definition.max_value) then
            return nil, nil, "gameplay_stat_above_max:" .. field_id
        end
        if field_id == "starjoy_points" then
            require("systems/archive_starjoy_rewards").change(next_stats, old_value, next_value)
        else next_stats[field_id] = next_value end
        changes[#changes + 1] = {
            field_id = field_id,
            delta = delta,
            old_value = old_value,
            new_value = next_value,
        }
    end
    return next_stats, changes
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function bucket(player_id)
    if not hydrated_by_player[player_id] then
        local profile = profile_service.get_profile(player_id)
        local saved = profile and profile.save and profile.save.content_inventory
        inventory_by_player[player_id] = normalize_map(saved or inventory_by_player[player_id] or {})
        for id in pairs(inventory_by_player[player_id]) do
            if match_item(id) then inventory_by_player[player_id][id] = nil end
        end
        hydrated_by_player[player_id] = true
    end
    inventory_by_player[player_id] = inventory_by_player[player_id] or {}
    return inventory_by_player[player_id]
end

local function persist(player_id, counts)
    if type(profile_service.update_save_section) ~= "function" then return true end
    local result = profile_service.update_save_section(
        player_id, "content_inventory", counts, "content_inventory_changed")
    return result and result.ok == true, result and result.error
end

local function snapshot(player_id)
    local counts = {}
    for content_id, count in pairs(bucket(player_id)) do
        if count > 0 then
            counts[content_id] = count
        end
    end
    for content_id, count in pairs(match_bucket(player_id)) do
        if count > 0 then counts[content_id] = count end
    end
    return { player_id = player_id, counts = counts }
end

local function publish(player_id, reason, changes)
    -- This publication already contains the latest authoritative permanent
    -- bucket. A synchronous profile event from our own write must not publish
    -- the same inventory again after the mutation completes.
    profile_refresh_by_player[player_id] = nil
    event_bus.emit(events.CONTENT_INVENTORY_CHANGED, {
        player_id = player_id,
        reason = reason or "changed",
        changes = changes or {},
        snapshot = snapshot(player_id),
    })
end

normalize_map = function(value)
    local result = {}
    for content_id, count in pairs(value or {}) do
        local amount = math.floor(tonumber(count) or 0)
        if content_id ~= "" and amount > 0 then
            local canonical_id = content_id_aliases.canonical(content_id)
            result[canonical_id] = (result[canonical_id] or 0) + amount
        end
    end
    return result
end

local function grant(payload)
    local player_id = tonumber(payload.player_id)
    local content_id = content_id_aliases.canonical(payload.content_id)
    local apply_effects_only = payload.apply_effects_only == true
    local count = math.floor(tonumber(payload.count)
        or (apply_effects_only and 0 or 1))
    if not valid_player_id(player_id) or content_id == "" or count < 0
        or (count == 0 and not apply_effects_only) then
        return { ok = false, error = "inventory_grant_invalid" }
    end
    if match_item(content_id) then
        if apply_effects_only or payload.gameplay_stat_effects ~= nil
            or payload.effect_marker_id ~= nil then
            return { ok = false, error = "match_item_permanent_effect_invalid" }
        end
        local counts = match_bucket(player_id)
        counts[content_id] = (counts[content_id] or 0) + count
        local changes = { [content_id] = count }
        publish(player_id, payload.reason or "match_grant", changes)
        return { ok = true, snapshot = snapshot(player_id), changes = changes }
    end
    local counts = bucket(player_id)
    local before = tonumber(counts[content_id]) or 0
    if apply_effects_only and before <= 0 then
        return { ok = false, error = "inventory_reward_not_owned:" .. content_id }
    end
    local profile = profile_service.get_profile(player_id)
    if not profile or type(profile.save) ~= "table" then
        return { ok = false, error = "profile_not_loaded" }
    end
    local next_counts = copy_map(counts)
    local stackable=require('systems/archive_stackable_items')
    if stackable.definition(content_id) then
        if apply_effects_only then return {ok=true,snapshot=snapshot(player_id),changes={},effect_applied=false,gameplay_stat_changes={}} end
        local archive=deep_copy(profile.save.archive or {})
        local accepted,overflow=stackable.grant({content_inventory=next_counts,
            lottery_applied_item_effects=profile.save.lottery_applied_item_effects},
            archive,profile.save.gameplay_stats,content_id,count)
        local persisted=profile_service.update_save_sections(player_id,
            {content_inventory=next_counts,archive=archive},payload.reason or 'stackable_item_grant')
        if not persisted or persisted.ok~=true then
            return {ok=false,error=persisted and persisted.error or 'inventory_persist_failed'}
        end
        inventory_by_player[player_id]=next_counts;hydrated_by_player[player_id]=true
        local changes=accepted>0 and {[content_id]=accepted} or {}
        publish(player_id,payload.reason or 'grant',changes)
        return {ok=true,snapshot=snapshot(player_id),changes=changes,granted_count=accepted,overflow_count=overflow,
            effect_applied=false,gameplay_stat_changes={}}
    end
    next_counts[content_id] = before + count
    local inventory_changes = count > 0 and { [content_id] = count } or {}
    local replacements = { content_inventory = next_counts }
    local effect_marker_id = tostring(payload.effect_marker_id or "")
    local applied_markers = copy_map(profile.save.lottery_applied_item_effects)
    local gameplay_changes = {}
    local effect_applied = false
    if type(payload.gameplay_stat_effects) == "table"
        and effect_marker_id ~= "" and applied_markers[effect_marker_id] ~= true then
        local next_stats, changes, effect_error = apply_gameplay_effects(
            profile.save.gameplay_stats, payload.gameplay_stat_effects)
        if not next_stats then return { ok = false, error = effect_error } end
        applied_markers[effect_marker_id] = true
        for _, marker_id in ipairs(payload.additional_effect_marker_ids or {}) do
            marker_id = tostring(marker_id or "")
            if marker_id ~= "" then applied_markers[marker_id] = true end
        end
        replacements.gameplay_stats = next_stats
        replacements.lottery_applied_item_effects = applied_markers
        gameplay_changes = changes
        effect_applied = true
    end
    if count == 0 and not effect_applied then
        return {
            ok = true,
            snapshot = snapshot(player_id),
            changes = {},
            effect_applied = false,
            gameplay_stat_changes = {},
        }
    end
    local persisted = profile_service.update_save_sections(
        player_id, replacements, payload.reason or "content_inventory_changed")
    if not persisted or persisted.ok ~= true then
        return { ok = false, error = persisted and persisted.error
            or "inventory_persist_failed" }
    end
    inventory_by_player[player_id] = next_counts
    hydrated_by_player[player_id] = true
    if payload.reason == "challenge_ground_reward_pickup" then
        print(string.format(
            "[CONTENT_INVENTORY_GRANT_COMMIT] player=%s content=%s before=%s after=%s reason=%s",
            tostring(player_id), tostring(content_id), tostring(before),
            tostring(next_counts[content_id]), tostring(payload.reason)))
    end
    publish(player_id, payload.reason or "grant", inventory_changes)
    if effect_applied then
        event_bus.emit(events.UI_DIRTY, {
            player_id = player_id,
            team = PlayerResource:GetTeam(player_id),
            reason = "lottery_gameplay_stats_applied",
        })
        print(string.format(
            "[LOTTERY_EFFECT_APPLIED] player=%s item=%s fields=%s revision=%s",
            tostring(player_id), tostring(effect_marker_id),
            tostring(#gameplay_changes), tostring(persisted.revision)))
    end
    if payload.reason == "challenge_ground_reward_pickup" then
        print(string.format(
            "[CONTENT_INVENTORY_EVENT_EMITTED] player=%s content=%s count=%s reason=%s",
            tostring(player_id), tostring(content_id),
            tostring(next_counts[content_id]), tostring(payload.reason)))
    end
    return {
        ok = true,
        snapshot = snapshot(player_id),
        changes = inventory_changes,
        effect_applied = effect_applied,
        gameplay_stat_changes = gameplay_changes,
        revision = persisted.revision,
    }
end

local function transaction(payload)
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local consume = normalize_map(payload.consume)
    local grant_map = normalize_map(payload.grant)
    local has_match, has_permanent = false, false
    for _, values in ipairs({consume, grant_map}) do
        for id in pairs(values) do
            if match_item(id) then has_match = true else has_permanent = true end
        end
    end
    if has_match and has_permanent then
        return { ok = false, error = "inventory_mixed_storage_transaction" }
    end
    -- Stage first: a rejected permanent write must not consume inputs locally.
    local counts = copy_map(has_match and match_bucket(player_id) or bucket(player_id))
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
    local stackable=require('systems/archive_stackable_items')
    local next_archive
    for content_id, count in pairs(grant_map) do
        local accepted=count
        if stackable.definition(content_id) then
            local profile=profile_service.get_profile(player_id)
            if not profile or not profile.save then return {ok=false,error='profile_not_loaded'} end
            next_archive=next_archive or deep_copy(profile.save.archive or {})
            accepted=stackable.grant({content_inventory=counts,
                lottery_applied_item_effects=profile.save.lottery_applied_item_effects},
                next_archive,profile.save.gameplay_stats,content_id,count)
        else counts[content_id]=(counts[content_id] or 0)+count end
        changes[content_id] = (changes[content_id] or 0) + accepted
    end
    if has_match then
        match_inventory_by_player[player_id] = counts
    else
        local saved, save_error
        if next_archive then
            local result=profile_service.update_save_sections(player_id,
                {content_inventory=counts,archive=next_archive},payload.reason or 'stackable_item_transaction')
            saved=result and result.ok==true;save_error=result and result.error
        else saved,save_error=persist(player_id,counts) end
        if not saved then return { ok = false, error = save_error or "inventory_persist_failed" } end
        inventory_by_player[player_id] = counts
    end
    publish(player_id, payload.reason or "transaction", changes)
    return { ok = true, snapshot = snapshot(player_id), changes = changes }
end

local function publish_profile_refresh(player_id)
    if (mutation_depth_by_player[player_id] or 0) > 0 then return end
    local refresh = profile_refresh_by_player[player_id]
    if not refresh then return end
    profile_refresh_by_player[player_id] = nil
    local counts = bucket(player_id)
    local changes = {}
    for content_id, count in pairs(counts) do
        local change = count - (refresh.before[content_id] or 0)
        if change ~= 0 then changes[content_id] = change end
    end
    for content_id, count in pairs(refresh.before) do
        if counts[content_id] == nil and count ~= 0 then
            changes[content_id] = -count
        end
    end
    if next(changes) then
        -- A profile refresh is a read-only projection, never a local grant or
        -- a write back to the HTTP-authoritative archive.
        publish(player_id, refresh.reason, changes)
    end
end

local function queue_profile_refresh(player_id)
    event_bus.after_dispatch("content_inventory_profile_" .. tostring(player_id),
        function() publish_profile_refresh(player_id) end)
end

local function with_inventory_mutation(handler)
    return function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if not valid_player_id(player_id) then return handler(payload) end
        mutation_depth_by_player[player_id] =
            (mutation_depth_by_player[player_id] or 0) + 1
        local ok, result = pcall(handler, payload)
        local remaining = mutation_depth_by_player[player_id] - 1
        mutation_depth_by_player[player_id] = remaining > 0 and remaining or nil
        -- On success our existing publish consumed the pending projection.
        -- Rejected or throwing writers still release the guard and report any
        -- actual profile change, rather than silencing later purchases.
        if remaining == 0 and profile_refresh_by_player[player_id] then
            queue_profile_refresh(player_id)
        end
        if not ok then error(result, 0) end
        return result
    end
end

local function on_profile_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or not valid_player_id(player_id) then return end
    if not profile_refresh_by_player[player_id] then
        profile_refresh_by_player[player_id] = {
            before = copy_map(inventory_by_player[player_id]),
            reason = "profile:" .. tostring(payload.reason or "changed"),
        }
    end
    -- Other subscribers may read inventory in the same profile dispatch.
    -- Hydrate now, but notify downstream consumers only after all profile
    -- projections finish; nested updates coalesce against the original counts.
    hydrated_by_player[player_id] = false
    bucket(player_id)
    queue_profile_refresh(player_id)
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
    hydrated_by_player = {}
    match_inventory_by_player = {}
    profile_refresh_by_player = {}
    mutation_depth_by_player = {}
    event_bus.handle_request(events.CONTENT_INVENTORY_GRANT_REQUEST, with_inventory_mutation(grant))
    event_bus.handle_request(
        events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
        with_inventory_mutation(transaction)
    )
    event_bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, get_inventory)
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, on_profile_changed)
end

return M
