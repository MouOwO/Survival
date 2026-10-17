-- Explicit, bounded Workshop backend diagnostic. require() is inert.
-- Opens only initially closed own advanced labs through existing public routes.
-- Does not spend/add resources, emit simulated events, drive UI or wrap the bus.
local M = {}
local active, last, serial
serial = 0
local RAW_LIMIT, PHASE_SECONDS, WALL_LIMIT = 64, 10, 120
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function read(object, name, ...)
    if not object then return nil end
    local ok, fn = pcall(function() return object[name] end)
    if not ok or type(fn) ~= "function" then return nil end
    local called, value = pcall(fn, object, ...); if called then return value end
end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function game_time()
    local value = read(GameRules, "GetGameTime"); return finite(value) and value or nil
end
local function wall_time()
    if type(Plat_FloatTime) ~= "function" then return nil end
    local ok, value = pcall(Plat_FloatTime)
    if ok and finite(value) then return value end
end
local function authority()
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName() ~= "template_map" then return nil end
    local mode = read(GameRules, "GetGameModeEntity")
    local guard = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not mode or type(guard) ~= "table" or guard.mode ~= mode then return nil end
    local progress = _G.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS
    if type(progress) ~= "number" or read(GameRules, "State_Get") ~= progress then return nil end
    local bus = require("core/event_bus")
    return mode, guard, bus, bus.get_generation()
end
local function same_world(run)
    return read(GameRules, "GetGameModeEntity") == run.mode
        and _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION == run.guard
        and package.loaded["core/event_bus"] == run.bus
        and run.bus.get_generation() == run.generation
end
local function error_row(run, code, id)
    run.errors[code] = (run.errors[code] or 0) + 1
    if #run.error_examples < 16 then run.error_examples[#run.error_examples + 1] = { code = code, player_id = id } end
end
local function state(run) return run.shop._advanced_research_for_test.state() end
local function owned_drawer(run, id)
    local s = state(run)
    return s.opened_players[id] == "research" and s.research_scope_by_player[id] == "advanced"
        and s.research_source_entindex_by_player[id] == run.sources[id]
end
local function merge(previous, payload)
    if payload.full == 1 then return copy(payload) end
    local result = copy(previous)
    for key, value in pairs(payload) do
        if key ~= "changed_entries" and key ~= "removed_entry_ids" then result[key] = copy(value) end
    end
    local by_id = {}; for _, entry in ipairs(result.entries or {}) do by_id[entry.entry_id] = entry end
    for _, entry in ipairs(payload.changed_entries or {}) do by_id[entry.entry_id] = copy(entry) end
    for _, id in ipairs(payload.removed_entry_ids or {}) do by_id[id] = nil end
    result.entries = {}; for _, entry in pairs(by_id) do result.entries[#result.entries + 1] = entry end
    table.sort(result.entries, function(a, b) return (a.sort_order or 0) < (b.sort_order or 0) end)
    return result
end
local function validate(run, id, view)
    if view.player_id ~= id then error_row(run, "private_owner_mismatch", id) end
    if (view.research or {}).source_entindex ~= run.sources[id] then error_row(run, "research_source_mismatch", id) end
    for _, item in ipairs(view.entries or {}) do
        if item.content_type ~= "technology" or not run.config.by_legacy_group[item.technology_group] then
            error_row(run, "unexpected_research_entry", id)
        elseif item.resource_check_on_cast ~= 1 or item.can_afford ~= 1 then
            error_row(run, "wallet_gray_contract_mismatch", id)
        elseif item.prerequisite_met ~= 1 and item.purchasable ~= 0 then
            error_row(run, "prerequisite_gray_mismatch", id)
        elseif item.completed == 1 and item.purchasable ~= 0 then
            error_row(run, "completed_purchase_mismatch", id)
        end
    end
end
local function observe(run, id, payload, initial)
    if active ~= run or not run.sources[id] then return end
    local row = run.phases[run.phase].players[id]
    if payload.player_id ~= id then error_row(run, "payload_owner_mismatch", id) end
    if not initial and payload.full ~= 1 and payload.base_sequence ~= row.view.sequence then
        error_row(run, "private_base_sequence_mismatch", id)
    end
    row.payloads = row.payloads + 1
    if not row.first_payload then row.first_payload = copy(payload) end
    row.last_payload = copy(payload)
    if #run.raw_payloads < RAW_LIMIT then
        run.raw_payloads[#run.raw_payloads + 1] = { phase = run.phase, player_id = id,
            game_time = game_time(), initial_response = initial == true, payload = copy(payload) }
    else run.raw_omitted = run.raw_omitted + 1 end
    row.view = merge(row.view or {}, payload)
    validate(run, id, row.view)
    local entries = row.view.entries or {}
    if not row.initial_entries then row.initial_entries = copy(entries)
    elseif not equal(entries, row.initial_entries) then
        row.non_wallet_changes = row.non_wallet_changes + 1
        if row.business_events == 0 then error_row(run, "unexplained_product_change", id) end
    end
end
local function begin_phase(run, phase)
    run.phase = phase
    local period = { game_started = game_time(), wall_started = wall_time(), players = {} }
    run.phases[phase] = period
    for id = 0, 3 do period.players[id] = { payloads = 0, resource_events = 0,
        business_events = 0, non_wallet_changes = 0, source_entindex = run.sources[id] } end
    for id = 0, 3 do
        local response = run.bus.request(run.events.SHOP_OPEN_REQUEST,
            { player_id = id, mode = "research", source_entindex = run.sources[id] })
        if not response or not response.ok then return false, "public_open_failed_" .. id end
        run.leases[id] = true
        observe(run, id, response.snapshot, true)
    end
    return true
end
function M.stop(reason)
    local run = active
    if not run then return last end
    active = nil
    run.reason, run.game_finished, run.wall_finished = reason or "manual", game_time(), wall_time()
    pcall(function() run.mode:SetContextThink(run.think_name, nil, 0) end)
    for _, token in ipairs(run.tokens) do run.bus.unsubscribe(token) end
    run.tokens = {}
    local current_world = same_world(run)
    run.restore_world_matched = current_world
    if current_world then
        run.probe_counts = run.shop.inspect_research_wallet_probe()
        if run.owns_probe then run.probe_disabled = run.shop.set_research_wallet_probe(false) == true end
        for id = 0, 3 do
            if run.leases[id] and owned_drawer(run, id) then
                local result = run.bus.request(run.events.SHOP_CLOSE_REQUEST, { player_id = id })
                run.closed[id] = result and result.ok == true
                if not run.closed[id] then error_row(run, "public_restore_close_failed", id) end
            elseif run.leases[id] then run.concurrent_context_preserved[id] = true end
        end
    end
    for _, period in pairs(run.phases) do
        period.game_seconds = (period.game_finished or run.game_finished or period.game_started) - period.game_started
        period.wall_seconds = (period.wall_finished or run.wall_finished or period.wall_started) - period.wall_started
        for _, row in pairs(period.players) do
            row.final_entries = copy(row.view and row.view.entries or {})
            row.view = nil
        end
    end
    for id = 0, 3 do
        local off = run.phases.off.players[id]
        local on = run.phases.on and run.phases.on.players[id]
        if on then
            run.comparisons[id] = { business_changed = off.business_events > 0 or on.business_events > 0,
                complete_product_fields_equal = equal(off.initial_entries, on.initial_entries)
                    and equal(off.final_entries, on.final_entries),
                natural_resource_events_off = off.resource_events, natural_resource_events_on = on.resource_events }
        end
    end
    run.completed = run.reason == "completed" and current_world
    run.phase_duration_valid = run.phases.on ~= nil and run.phases.off.game_seconds >= PHASE_SECONDS
        and run.phases.on.game_seconds >= PHASE_SECONDS
    run.coverage_pass = run.completed and run.phase_duration_valid and next(run.errors) == nil
        and (run.probe_counts and run.probe_counts.counts.wallet_reuses or 0) > 0
    for id = 0, 3 do
        local pair = run.comparisons[id]
        run.coverage_pass = run.coverage_pass and pair ~= nil
            and pair.natural_resource_events_off > 0 and pair.natural_resource_events_on > 0
    end
    run.product_stability_proven = run.coverage_pass
    for id, pair in pairs(run.comparisons) do
        run.product_stability_proven = run.product_stability_proven and not pair.business_changed
            and pair.complete_product_fields_equal
            and run.phases.off.players[id].non_wallet_changes == 0
            and run.phases.on.players[id].non_wallet_changes == 0
    end
    run.mode, run.guard, run.bus, run.generation, run.shop, run.events, run.config = nil, nil, nil, nil, nil, nil, nil
    last = run
    print("[MANUAL_RESEARCH_WALLET] stopped reason=" .. tostring(run.reason)
        .. " completed=" .. tostring(run.completed) .. " raw=" .. tostring(#run.raw_payloads))
    return copy(last)
end
function M.inspect()
    local run = active or last
    if not run then return { running = false } end
    local result = {}
    for key, value in pairs(run) do
        if key ~= "mode" and key ~= "guard" and key ~= "bus" and key ~= "generation"
            and key ~= "shop" and key ~= "events" and key ~= "config" and key ~= "tokens" then result[key] = copy(value) end
    end
    result.running = active ~= nil
    return result
end
function M.start()
    if active then return false, "already_running" end
    local mode, guard, bus, generation = authority()
    if not mode then return false, "requires isolated in-progress Workshop template_map server" end
    if not wall_time() or not game_time() or type(mode.SetContextThink) ~= "function" then return false, "native_clock_or_think_unavailable" end
    local shop, events = require("systems/shop_system"), require("core/events")
    if not shop.set_research_wallet_probe or not shop.inspect_research_wallet_probe
        or not shop._advanced_research_for_test then return false, "candidate_api_unavailable" end
    if shop.inspect_research_wallet_probe().enabled then return false, "existing_probe_is_owned_elsewhere" end
    local s = shop._advanced_research_for_test.state()
    local sources = {}
    for id = 0, 3 do
        if not PlayerResource:IsValidPlayerID(id) then return false, "missing_owner_" .. id end
        if s.opened_players[id] or s.pending_push_reason[id] then return false, "existing_drawer_or_pending_push_" .. id end
    end
    local listed = bus.request(events.BUILDING_LIST_REQUEST, {}) or {}
    for _, building in ipairs(listed.buildings or {}) do
        local id, index = tonumber(building.player_id), tonumber(building.entindex)
        if id and id >= 0 and id < 4 and building.building_id == "building_advanced_research_lab"
            and tonumber(building.team) == tonumber(PlayerResource:GetTeam(id))
            and index and tonumber(read(building.unit, "entindex")) == index
            and read(building.unit, "IsNull") == false then
            if not sources[id] or index < sources[id] then sources[id] = index end
        end
    end
    for id = 0, 3 do if not sources[id] then return false, "missing_own_advanced_lab_" .. id end end
    serial = serial + 1
    local run = { mode = mode, guard = guard, bus = bus, generation = generation,
        shop = shop, events = events, config = require("config/research_technology_config"),
        sources = sources, leases = {}, closed = {}, concurrent_context_preserved = {},
        tokens = {}, errors = {}, error_examples = {}, phases = {}, comparisons = {}, raw_payloads = {}, raw_omitted = 0,
        think_name = "manual_research_wallet_" .. serial, game_started = game_time(), wall_started = wall_time(),
        phase_seconds = PHASE_SECONDS, wall_limit_seconds = WALL_LIMIT,
        scope = "server backend four owners; one rendered client, other owners may be bots; no FPS or visible-drawer claim",
        off_full_catalog_builds = "unmeasured: no production wrapping", natural_resources_only = true }
    active = run
    run.tokens[#run.tokens + 1] = bus.subscribe(events.SHOP_STATE_CHANGED, function(p)
        if active ~= run or not same_world(run) then return end
        local id = tonumber(p and p.player_id)
        if id and run.sources[id] and p.snapshot then observe(run, id, p.snapshot, false) end
    end)
    run.tokens[#run.tokens + 1] = bus.subscribe(events.RESOURCE_CHANGED, function(p)
        if active ~= run or not same_world(run) then return end
        local id = tonumber(p and p.player_id)
        if id and run.sources[id] then
            local row = run.phases[run.phase].players[id]; row.resource_events = row.resource_events + 1
            row.latest_resource_payload = copy(p)
        end
    end)
    local business = { events.BUILDING_CREATED, events.BUILDING_CHANGED, events.BUILDING_DESTROYED,
        events.HERO_SUMMON_STATE_CHANGED, events.HERO_PROGRESSION_CHANGED, events.PLAYER_ENTITLEMENT_CHANGED,
        events.CONTENT_INVENTORY_CHANGED, events.PERMANENT_REWARD_EFFECTS_CHANGED,
        events.TECHNOLOGY_RESEARCH_STATE_CHANGED, require("research/research_event_names").LEVEL_CHANGED }
    for _, name in ipairs(business) do
        local team_event = name == events.BUILDING_CREATED or name == events.BUILDING_CHANGED
            or name == events.BUILDING_DESTROYED
        run.tokens[#run.tokens + 1] = bus.subscribe(name, function(p)
            if active ~= run or not same_world(run) then return end
            local owner, team = tonumber(p and p.player_id), tonumber(p and p.team)
            for id, row in pairs(run.phases[run.phase].players) do
                if owner == id or ((team_event or owner == nil) and team == tonumber(PlayerResource:GetTeam(id))) then
                    row.business_events = row.business_events + 1
                end
            end
        end)
    end
    local opened, why = begin_phase(run, "off")
    if not opened then M.stop(why); return false, why end
    local ok, error_value = pcall(function()
        mode:SetContextThink(run.think_name, function()
            if active ~= run then return nil end
            if not same_world(run) then M.stop("world_or_game_changed"); return nil end
            if read(GameRules, "State_Get") ~= _G.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
                M.stop("game_state_changed"); return nil
            end
            local current_game, current_wall = game_time(), wall_time()
            if not current_game or not current_wall or current_game < run.game_started
                or current_wall < run.wall_started then M.stop("native_clock_invalid"); return nil end
            for id = 0, 3 do if not owned_drawer(run, id) then M.stop("drawer_context_changed"); return nil end end
            if current_wall - run.wall_started >= WALL_LIMIT then M.stop("wall_timeout"); return nil end
            local period = run.phases[run.phase]
            if current_game - period.game_started >= PHASE_SECONDS then
                period.game_finished, period.wall_finished = game_time(), wall_time()
                if run.phase == "off" then
                    local enabled, reason = shop.set_research_wallet_probe(true)
                    if not enabled then M.stop(reason); return nil end
                    run.owns_probe = true
                    local success, failure = begin_phase(run, "on")
                    if not success then M.stop(failure); return nil end
                else M.stop("completed"); return nil end
            end
            return 0.25
        end, 0.25)
    end)
    if not ok then M.stop("native_think_failed"); return false, tostring(error_value) end
    return true
end
return M
