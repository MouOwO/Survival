local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/lottery_config")
local inventory_aliases = require("config/content_id_aliases")
local profile_service = require("systems/player_profile_service")

local M = {}
local state_by_player = {}
local request_cache = {}
local exchange_cache = {}
local busy_by_player = {}
local hydrating_by_player = {}
local random_seeded = false
local MAP_LEVEL_EFFECT_MARKER_SUFFIX = ":map_level:v1"

local function map_level_effects(item)
    local result = {}
    for _, effect in ipairs(item and item.effects or {}) do
        if tostring(effect.field_id or "") == "map_level" then
            result[#result + 1] = effect
        end
    end
    return result
end

local function item_effect_marker(item_id, copy_index)
    local marker = inventory_aliases.canonical(item_id)
    copy_index = math.max(1, math.floor(tonumber(copy_index) or 1))
    if copy_index > 1 then
        marker = marker .. ":copy:" .. tostring(copy_index)
    end
    return marker
end

local function map_level_effect_marker(item_id, copy_index)
    return item_effect_marker(item_id, copy_index)
        .. MAP_LEVEL_EFFECT_MARKER_SUFFIX
end

local function additional_effect_markers(item, copy_index)
    if #map_level_effects(item) == 0 then return nil end
    return { map_level_effect_marker(item.id, copy_index) }
end

local function seed_random()
    if random_seeded then return end
    random_seeded = true
    local game_time = (GameRules and GameRules.GetGameTime
        and tonumber(GameRules:GetGameTime()) or 0) * 1000
    local wall_clock = (os and type(os.time) == "function" and os.time()) or 0
    math.randomseed(math.floor(game_time + wall_clock))
    math.random(); math.random(); math.random()
end

local function valid_player_id(player_id)
    player_id = tonumber(player_id)
    return player_id ~= nil and player_id >= 0
        and PlayerResource and PlayerResource.IsValidPlayerID
        and PlayerResource:IsValidPlayerID(player_id)
end

local function pool_config(pool_id)
    return config.pools[tostring(pool_id or config.default_pool_id)]
end

local function player_state(player_id)
    player_id = tonumber(player_id)
    state_by_player[player_id] = state_by_player[player_id] or {
        pools = {},
        sequence = 0,
        initialized = false,
        test_tickets_granted = {},
    }
    return state_by_player[player_id]
end

local function selected_pool_state(state, pool)
    state.pools[pool.id] = state.pools[pool.id] or {
        draws = 0,
        pity_counts = {},
    }
    local result = state.pools[pool.id]
    for _, rule in ipairs(pool.pity_rules) do
        result.pity_counts[rule.id] = math.max(0,
            math.floor(tonumber(result.pity_counts[rule.id]) or 0))
    end
    return result
end

local function copy_map(value)
    local result = {}
    for key, raw in pairs(value or {}) do
        local count = math.floor(tonumber(raw) or 0)
        if tostring(key) ~= "" and count > 0 then result[tostring(key)] = count end
    end
    return result
end

local function copy_pity(value)
    local result = {}
    for key, raw in pairs(value or {}) do
        result[tostring(key)] = math.max(0, math.floor(tonumber(raw) or 0))
    end
    return result
end

local function inventory_snapshot(player_id)
    local result = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id })
    return result and result.snapshot or { counts = {} }
end

local function ensure_test_tickets(player_id)
    local state = player_state(player_id)
    local inventory = inventory_snapshot(player_id)
    for content_id, configured_count in pairs(config.test_initial_tickets or {}) do
        if state.test_tickets_granted[content_id] ~= true then
            local current = tonumber(inventory.counts and inventory.counts[content_id]) or 0
            local target = math.max(0, math.floor(tonumber(configured_count) or 0))
            if current < target then
                local result = event_bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
                    player_id = player_id,
                    content_id = content_id,
                    count = target - current,
                    reason = "lottery_initial_test_tickets",
                })
                if not result or result.ok ~= true then return false end
                inventory = result.snapshot or inventory
            end
            state.test_tickets_granted[content_id] = true
        end
    end
    return true
end

local function sync_owned_item_effects(player_id)
    local inventory = inventory_snapshot(player_id)
    for content_id, count in pairs(inventory.counts or {}) do
        local canonical_id = inventory_aliases.canonical(content_id)
        local item = config.by_id[canonical_id]
        local owned_count = math.min(
            math.max(0, math.floor(tonumber(count) or 0)),
            item and math.max(1, math.floor(tonumber(item.max_owned) or 1)) or 0)
        if item and owned_count > 0 then
            for copy_index = 1, owned_count do
                local result = event_bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
                    player_id = player_id,
                    content_id = canonical_id,
                    count = 0,
                    apply_effects_only = true,
                    effect_marker_id = item_effect_marker(canonical_id, copy_index),
                    additional_effect_marker_ids = additional_effect_markers(
                        item, copy_index),
                    gameplay_stat_effects = item.effects,
                    reason = "lottery_owned_effect_migration",
                })
                if not result or result.ok ~= true then
                    return false, result and result.error
                        or "lottery_owned_effect_migration_failed"
                end
                local level_effects = map_level_effects(item)
                if #level_effects > 0 then
                    local level_result = event_bus.request(
                        events.CONTENT_INVENTORY_GRANT_REQUEST, {
                        player_id = player_id,
                        content_id = canonical_id,
                        count = 0,
                        apply_effects_only = true,
                        effect_marker_id = map_level_effect_marker(
                            canonical_id, copy_index),
                        gameplay_stat_effects = level_effects,
                        reason = "lottery_map_level_effect_migration",
                    })
                    if not level_result or level_result.ok ~= true then
                        return false, level_result and level_result.error
                            or "lottery_map_level_effect_migration_failed"
                    end
                end
            end
        end
    end
    return true
end

local function persist_state(player_id, state)
    local profile = profile_service.get_profile(player_id)
    if not profile or type(profile.save) ~= "table" then return true end
    local pools = {}
    for pool_id, value in pairs(state.pools or {}) do
        pools[pool_id] = {
            draws = math.max(0, math.floor(tonumber(value.draws) or 0)),
            pity_counts = copy_pity(value.pity_counts),
        }
    end
    local value = {
        version = config.version,
        pools = pools,
        test_tickets_granted = state.test_tickets_granted,
    }
    if type(profile_service.update_save_section) == "function" then
        local result = profile_service.update_save_section(
            player_id, "lottery_state", value, "lottery_state_changed")
        return result and result.ok ~= false
    end
    return true
end

local function hydrate(player_id)
    if not valid_player_id(player_id) then return nil end
    local state = player_state(player_id)
    if state.initialized then return state end
    if hydrating_by_player[player_id] then return state end
    hydrating_by_player[player_id] = true
    state.initialized = true
    local profile = profile_service.get_profile(player_id)
    local saved = profile and profile.save and profile.save.lottery_state or nil
    if type(saved) == "table" then
        state.test_tickets_granted = type(saved.test_tickets_granted) == "table"
            and saved.test_tickets_granted or {}
        if type(saved.pools) == "table" then
            for pool_id, value in pairs(saved.pools) do
                local pool = pool_config(pool_id)
                if pool and type(value) == "table" then
                    local current = selected_pool_state(state, pool)
                    current.draws = math.max(0, math.floor(tonumber(value.draws) or 0))
                    current.pity_counts = copy_pity(value.pity_counts)
                    selected_pool_state(state, pool)
                end
            end
        elseif tonumber(saved.draws) ~= nil then
            -- Version-1 migration: the original single pool becomes `map`.
            local map_pool = pool_config("map")
            local current = selected_pool_state(state, map_pool)
            current.draws = math.max(0, math.floor(tonumber(saved.draws) or 0))
            for _, rule in ipairs(map_pool.pity_rules) do
                local legacy = rule.target_quality == "sr"
                    and saved.draws_since_sr or saved.draws_since_ssr
                current.pity_counts[rule.id] = math.max(0,
                    math.floor(tonumber(legacy) or 0))
            end
            if saved.test_tickets_granted == true then
                state.test_tickets_granted.lottery_ticket = true
            end
        end
    end
    local before = {}
    for key, value in pairs(state.test_tickets_granted) do before[key] = value end
    ensure_test_tickets(player_id)
    local effects_synced, effects_error = sync_owned_item_effects(player_id)
    state.effect_sync_error = effects_synced and nil or effects_error
    if not effects_synced then
        print("[LOTTERY_EFFECT_SYNC_ERROR] player=" .. tostring(player_id)
            .. " error=" .. tostring(effects_error))
    end
    local changed = false
    for key, value in pairs(state.test_tickets_granted) do
        if before[key] ~= value then changed = true break end
    end
    if changed then persist_state(player_id, state) end
    hydrating_by_player[player_id] = nil
    return state
end

local function quality_rank(value)
    return config.quality_rank[value] or 1
end

local function random_quality(pool)
    local total = 0
    for _, quality in ipairs(config.quality_order) do
        total = total + math.max(0, tonumber(pool.quality_weights[quality]) or 0)
    end
    if total <= 0 then return "n" end
    local roll = math.random(1, total)
    local cursor = 0
    for _, quality in ipairs(config.quality_order) do
        cursor = cursor + math.max(0, tonumber(pool.quality_weights[quality]) or 0)
        if roll <= cursor then return quality end
    end
    return "n"
end

local function random_item_for_quality(pool, quality)
    local rows = pool.by_quality[quality] or {}
    local total = 0
    for _, item in ipairs(rows) do total = total + math.max(0, item.item_weight or 0) end
    if total <= 0 then return nil end
    local roll = math.random() * total
    local cursor = 0
    for _, item in ipairs(rows) do
        cursor = cursor + math.max(0, item.item_weight or 0)
        if roll < cursor then return item end
    end
    return rows[#rows]
end

local function draw_one(pool, state, forced_quality)
    local quality = forced_quality or random_quality(pool)
    local item = random_item_for_quality(pool, quality)
    if not item then return nil end
    state.draws = state.draws + 1
    return item
end

local function batch_guarantee(pool, draw_count)
    local selected = nil
    for _, rule in ipairs(pool.pity_rules) do
        if rule.trigger_mode == "batch_only"
            and tonumber(rule.threshold) == tonumber(draw_count)
            and (not selected
                or quality_rank(rule.target_quality)
                    > quality_rank(selected.target_quality)) then
            selected = rule
        end
    end
    return selected
end

local function item_owned_count(counts, item)
    local total = tonumber(counts[item.id]) or 0
    for _, content_id in ipairs(item.ownership_ids or {}) do
        total = total + (tonumber(counts[inventory_aliases.canonical(content_id)]) or 0)
    end
    return total
end

local function item_owned(counts, item)
    return item_owned_count(counts, item) > 0
end

local function item_at_limit(counts, item)
    return item_owned_count(counts, item)
        >= math.max(1, math.floor(tonumber(item.max_owned) or 1))
end

local function convert_duplicate(player_id, item)
    local points = math.max(0, math.floor(tonumber(item.duplicate_points) or 0))
    if points <= 0 then return { ok = true, duplicate = true, converted_points = 0 } end
    local stats_order = require("systems/player_gameplay_stats_order_service")
    local result = stats_order.order(player_id, config.starjoy_stat_id, points)
    if not result or result.ok ~= true then
        return { ok = false, error = "starjoy_points_persist_failed" }
    end
    return { ok = true, duplicate = true, converted_points = points,
        starjoy_points = result.new_value }
end

local function grant_item(player_id, item, counts)
    if item_at_limit(counts, item) then
        return convert_duplicate(player_id, item)
    end
    local copy_index = item_owned_count(counts, item) + 1
    local result = event_bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
        player_id = player_id,
        content_id = inventory_aliases.canonical(item.id),
        count = 1,
        effect_marker_id = item_effect_marker(item.id, copy_index),
        additional_effect_marker_ids = additional_effect_markers(
            item, copy_index),
        gameplay_stat_effects = item.effects,
        reason = "lottery_grant",
    })
    if not result or result.ok ~= true then
        return { ok = false, error = "lottery_item_grant_failed" }
    end
    return { ok = true, duplicate = false, converted_points = 0,
        gameplay_stat_changes = result.gameplay_stat_changes or {} }
end

local function public_pity(pool, state)
    local rows = {}
    for _, rule in ipairs(pool.pity_rules) do
        rows[#rows + 1] = {
            quality = rule.target_quality,
            trigger_mode = rule.trigger_mode,
            batch_size = rule.threshold,
            label = tostring(rule.threshold) .. "连保底 "
                .. string.upper(tostring(rule.target_quality)),
        }
    end
    return rows
end

local function pool_public(pool, inventory, state)
    local currency = config.currencies[pool.ticket_content_id] or {}
    return {
        id = pool.id,
        display_name = pool.display_name,
        description = pool.description,
        pool_group = pool.pool_group,
        ticket_content_id = pool.ticket_content_id,
        ticket_name = currency.display_name or pool.ticket_content_id,
        tickets = tonumber(inventory.counts and inventory.counts[pool.ticket_content_id]) or 0,
        single_cost = pool.single_cost,
        ten_cost = pool.ten_cost,
        pity = public_pity(pool, state),
    }
end

local function snapshot(player_id, reason, requested_pool_id)
    local state = hydrate(player_id) or player_state(player_id)
    local pool = pool_config(requested_pool_id) or pool_config(config.default_pool_id)
    local pool_state = selected_pool_state(state, pool)
    local inventory = inventory_snapshot(player_id)
    local profile = profile_service.get_profile(player_id)
    local stats = profile and profile.save and profile.save.gameplay_stats or {}
    local items = {}
    for _, item in ipairs(pool.items) do
        items[#items + 1] = {
            id = item.id, name = item.name, description = item.description,
            item_type = item.item_type,
            duration_type = item.duration_type,
            duration_text = item.duration_text,
            quality = item.quality, icon = item.icon,
            icon_type = item.icon_type,
            effect_status = item.effect_status,
            duplicate_points = item.duplicate_points,
            exchange_points = item.exchange_points,
            exchange_enabled = item.exchange_enabled,
            max_owned = item.max_owned,
            owned = item_owned(inventory.counts or {}, item),
            owned_count = item_owned_count(inventory.counts or {}, item),
            at_max_owned = item_at_limit(inventory.counts or {}, item),
        }
    end
    local pools = {}
    for _, candidate in ipairs(config.pool_order) do
        pools[#pools + 1] = pool_public(candidate, inventory,
            selected_pool_state(state, candidate))
    end
    local selected = pool_public(pool, inventory, pool_state)
    return {
        version = config.version,
        reason = reason or "snapshot",
        selected_pool_id = pool.id,
        selected_pool = selected,
        pools = pools,
        items = items,
        starjoy_points = tonumber(stats[config.starjoy_stat_id]) or 0,
        map_level = tonumber(stats.map_level) or 0,
        -- Compatibility fields for the existing Panorama while it transitions
        -- to the selected-pool object.
        ticket_content_id = selected.ticket_content_id,
        ticket_name = selected.ticket_name,
        tickets = selected.tickets,
        single_cost = selected.single_cost,
        ten_cost = selected.ten_cost,
        draws = pool_state.draws,
        pity = selected.pity,
    }
end

local function publish(player_id, reason, pool_id)
    event_bus.emit(events.LOTTERY_CHANGED, {
        player_id = player_id,
        snapshot = snapshot(player_id, reason, pool_id),
    })
end

local function draw(payload)
    local player_id = tonumber(payload and payload.player_id)
    local request_id = tostring(payload and payload.request_id or "")
    local count = math.floor(tonumber(payload and payload.count) or 1)
    local pool = pool_config(payload and payload.pool_id)
    if not valid_player_id(player_id) then return { ok = false, error = "player_id_invalid" } end
    if not pool then return { ok = false, error = "lottery_pool_invalid" } end
    if count ~= 1 and count ~= 10 then return { ok = false, error = "lottery_count_invalid" } end
    if request_id == "" or #request_id > 96 then return { ok = false, error = "lottery_request_id_invalid" } end
    request_cache[player_id] = request_cache[player_id] or {}
    if request_cache[player_id][request_id] then return request_cache[player_id][request_id] end
    if busy_by_player[player_id] then return { ok = false, error = "lottery_player_busy" } end

    local state = hydrate(player_id)
    local current = selected_pool_state(state, pool)
    local inventory = inventory_snapshot(player_id)
    local tickets = tonumber(inventory.counts and inventory.counts[pool.ticket_content_id]) or 0
    local cost = count == 10 and pool.ten_cost or pool.single_cost
    if tickets < cost then
        return { ok = false, error = "lottery_ticket_insufficient", tickets = tickets,
            ticket_name = (config.currencies[pool.ticket_content_id] or {}).display_name }
    end
    local before_draws = current.draws
    local guarantee = batch_guarantee(pool, count)
    local guarantee_hit = false
    busy_by_player[player_id] = true
    local consume = event_bus.request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST, {
        player_id = player_id,
        consume = { [pool.ticket_content_id] = cost },
        grant = {},
        request_id = "lottery_cost:" .. request_id,
        reason = "lottery_draw_cost:" .. pool.id,
    })
    if not consume or consume.ok ~= true then
        busy_by_player[player_id] = nil
        return { ok = false, error = "lottery_ticket_consume_failed" }
    end

    seed_random()
    local results = {}
    local counts = copy_map(inventory.counts)
    for draw_index = 1, count do
        local forced_quality = nil
        if guarantee and draw_index == count and not guarantee_hit then
            -- The guarantee supplies its configured quality exactly. Higher
            -- qualities, especially map-pool UR, remain natural rolls only.
            forced_quality = guarantee.target_quality
        end
        local item = draw_one(pool, current, forced_quality)
        local grant = item and grant_item(player_id, item, counts)
            or { ok = false, error = "lottery_pool_empty" }
        if not grant.ok then
            current.draws = before_draws
            event_bus.request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST, {
                player_id = player_id, consume = {},
                grant = { [pool.ticket_content_id] = cost },
                request_id = "lottery_refund:" .. request_id,
                reason = "lottery_draw_refund:" .. pool.id,
            })
            local failed = { ok = false, error = grant.error }
            request_cache[player_id][request_id] = failed
            busy_by_player[player_id] = nil
            return failed
        end
        if guarantee and quality_rank(item.quality)
            >= quality_rank(guarantee.target_quality) then
            guarantee_hit = true
        end
        counts[item.id] = (counts[item.id] or 0) + (grant.duplicate and 0 or 1)
        results[#results + 1] = {
            id = item.id, name = item.name, quality = item.quality,
            item_type = item.item_type,
            duration_type = item.duration_type,
            duration_text = item.duration_text,
            icon_type = item.icon_type,
            icon = item.icon, description = item.description,
            effect_status = item.effect_status,
            duplicate = grant.duplicate,
            converted_points = grant.converted_points or 0,
            gameplay_stat_changes = grant.gameplay_stat_changes or {},
        }
    end
    local state_persisted = persist_state(player_id, state)
    state.sequence = state.sequence + 1
    local response = {
        ok = true, request_id = request_id, pool_id = pool.id,
        count = count, results = results, state_persisted = state_persisted,
        guarantee_quality = guarantee and guarantee.target_quality or "",
        guarantee_satisfied = guarantee == nil or guarantee_hit,
        snapshot = snapshot(player_id, "draw", pool.id),
    }
    local result_qualities = {}
    for _, result in ipairs(results) do
        result_qualities[#result_qualities + 1] = tostring(result.quality)
    end
    print(string.format(
        "[LOTTERY_DRAW] player=%s pool=%s count=%s results=%s qualities=%s guarantee=%s satisfied=%s tickets=%s draws=%s",
        tostring(player_id), pool.id, tostring(count), tostring(#results),
        table.concat(result_qualities, ","),
        tostring(response.guarantee_quality),
        tostring(response.guarantee_satisfied),
        tostring(response.snapshot.tickets), tostring(response.snapshot.draws)))
    request_cache[player_id][request_id] = response
    publish(player_id, "draw", pool.id)
    busy_by_player[player_id] = nil
    return response
end

local function exchange(payload)
    local player_id = tonumber(payload and payload.player_id)
    local request_id = tostring(payload and payload.request_id or "")
    local item_id = tostring(payload and payload.item_id or "")
    local pool = pool_config(payload and payload.pool_id)
    if not valid_player_id(player_id) then return { ok = false, error = "player_id_invalid" } end
    if not pool then return { ok = false, error = "lottery_pool_invalid" } end
    if request_id == "" or #request_id > 96 then return { ok = false, error = "lottery_request_id_invalid" } end
    local item = pool.by_id[item_id]
    if not item or item.exchange_enabled == false then
        return { ok = false, error = "lottery_item_invalid" }
    end
    exchange_cache[player_id] = exchange_cache[player_id] or {}
    if exchange_cache[player_id][request_id] then return exchange_cache[player_id][request_id] end
    if busy_by_player[player_id] then return { ok = false, error = "lottery_player_busy" } end
    hydrate(player_id)
    local inventory = inventory_snapshot(player_id)
    if item_at_limit(inventory.counts or {}, item) then
        local owned = { ok = false, error = "lottery_item_owned" }
        exchange_cache[player_id][request_id] = owned
        return owned
    end
    local profile = profile_service.get_profile(player_id)
    local stats = profile and profile.save and profile.save.gameplay_stats or {}
    local points = tonumber(stats[config.starjoy_stat_id]) or 0
    local cost = math.max(0, math.floor(tonumber(item.exchange_points) or 0))
    if cost <= 0 then return { ok = false, error = "lottery_exchange_cost_invalid" } end
    if points < cost then
        local result = { ok = false, error = "starjoy_points_insufficient",
            required = cost, current = points }
        exchange_cache[player_id][request_id] = result
        return result
    end
    local copy_index = item_owned_count(inventory.counts or {}, item) + 1
    busy_by_player[player_id] = true
    local stats_order = require("systems/player_gameplay_stats_order_service")
    local debit = stats_order.order(player_id, config.starjoy_stat_id, -cost)
    if not debit or debit.ok ~= true then
        busy_by_player[player_id] = nil
        return { ok = false, error = "starjoy_points_debit_failed" }
    end
    local grant = event_bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
        player_id = player_id, content_id = inventory_aliases.canonical(item.id),
        count = 1,
        effect_marker_id = item_effect_marker(item.id, copy_index),
        additional_effect_marker_ids = additional_effect_markers(
            item, copy_index),
        gameplay_stat_effects = item.effects,
        reason = "lottery_points_exchange:" .. pool.id,
    })
    if not grant or grant.ok ~= true then
        stats_order.order(player_id, config.starjoy_stat_id, cost)
        local failed = { ok = false, error = "lottery_exchange_grant_failed" }
        exchange_cache[player_id][request_id] = failed
        busy_by_player[player_id] = nil
        return failed
    end
    local response = {
        ok = true, request_id = request_id, pool_id = pool.id, cost = cost,
        item = { id = item.id, name = item.name, quality = item.quality,
            item_type = item.item_type,
            duration_type = item.duration_type,
            duration_text = item.duration_text,
            icon_type = item.icon_type,
            icon = item.icon, description = item.description,
            duplicate = false, exchanged = true, converted_points = 0,
            gameplay_stat_changes = grant.gameplay_stat_changes or {} },
        snapshot = snapshot(player_id, "exchange", pool.id),
    }
    exchange_cache[player_id][request_id] = response
    publish(player_id, "exchange", pool.id)
    busy_by_player[player_id] = nil
    return response
end

local function get_snapshot(payload)
    local player_id = tonumber(payload and payload.player_id)
    if not valid_player_id(player_id) then return { ok = false, error = "player_id_invalid" } end
    local pool = pool_config(payload and payload.pool_id)
    if not pool then return { ok = false, error = "lottery_pool_invalid" } end
    return { ok = true, snapshot = snapshot(player_id, "request", pool.id) }
end

function M.init()
    state_by_player, request_cache, exchange_cache, busy_by_player = {}, {}, {}, {}
    hydrating_by_player = {}
    random_seeded = false
    event_bus.handle_request(events.LOTTERY_DRAW_REQUEST, draw)
    event_bus.handle_request(events.LOTTERY_EXCHANGE_REQUEST, exchange)
    event_bus.handle_request(events.LOTTERY_SNAPSHOT_REQUEST, get_snapshot)
    event_bus.subscribe(events.HERO_READY, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if valid_player_id(player_id) then
            hydrate(player_id)
            publish(player_id, "hero_ready", config.default_pool_id)
        end
    end)
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if valid_player_id(player_id) and state_by_player[player_id]
            and not busy_by_player[player_id]
            and not hydrating_by_player[player_id] then
            state_by_player[player_id].initialized = false
            hydrate(player_id)
        end
    end)
    print("[LOTTERY_INIT] pools=map,cultivation,dragon_knight,summer "
        .. "map_ur=0.1%(natural_only) special_ur=10%(provisional) "
        .. "map_ten_pull=exact_SR special_ten_pull=UR singles=no_batch_guarantee")
end

M._test = {
    draw = draw,
    exchange = exchange,
    snapshot = snapshot,
    state = function() return state_by_player end,
}

return M
