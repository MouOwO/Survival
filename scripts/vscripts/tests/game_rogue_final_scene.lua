-- Manual Tools entry only. No normal addon init, reset, profile write or payment.
-- Creates the scene through real business requests and waits for their actual
-- completion. Native positioning is only used to place the owned builder near
-- a checked construction site. Levels, stats and registrations are never forged.
local M, states = {}, {}
local bus, e = require("core/event_bus"), require("core/events")
local json = require("core/json_encoder")
local routes = require("config/tower_route_config")
local probe = require("tests/game_rogue_builder_probe")
local runtime = require("systems/rogue_effect_runtime_service")

local function tools() return IsInToolsMode and IsInToolsMode() end
local function valid(unit) return unit and not unit:IsNull() and unit:IsAlive() end
local function request(event, payload)
    local ok, value, why = pcall(bus.request, event, payload or {})
    if ok then return value, why end
    return nil, tostring(value)
end
local function compact(value, seen)
    if type(value) == "userdata" then
        local ok, index = pcall(function() return value:entindex() end)
        return ok and index or tostring(value)
    end
    if type(value) ~= "table" then return type(value) ~= "function" and value or nil end
    if value.entindex and type(value.entindex) == "function" then return value:entindex() end
    seen = seen or {}; if seen[value] then return "<cycle>" end; seen[value] = true
    local out = {}; for key, item in pairs(value) do
        if key == "definition" then out.definition_id = type(item) == "table" and item.id or nil
        elseif type(item) ~= "function" then out[key] = compact(item, seen) end
    end
    seen[value] = nil; return out
end
local function wallet(pid)
    local result = request(e.RESOURCE_GET_REQUEST, {player_id = pid}) or {}
    return result.snapshot or result
end
local function record(state, kind, data)
    local entry = {time = GameRules:GetGameTime(), kind = kind, data = compact(data)}
    state.report.steps[#state.report.steps + 1] = entry
    print("[ROGUE_FINAL_SCENE] " .. json.encode({player_id = state.pid, step = entry}))
end
local function buildings(pid, id)
    local result = request(e.BUILDING_LIST_REQUEST, {player_id = pid, building_id = id}) or {}
    return result.buildings or {}
end
local function query(unit)
    return valid(unit) and request(e.BUILDING_QUERY_REQUEST, {entindex = unit:entindex()}) or nil
end
local function idle(unit)
    return valid(unit) and not unit:HasModifier("modifier_building_under_construction")
        and not require("systems/building_upgrade_process").is_active(unit)
end
local function contexts(state)
    local result = {}
    for key, unit in pairs(state.ctx) do
        if type(unit) == "table" and key == "towers" then
            result.towers = {}; for _, tower in ipairs(unit) do
                result.towers[#result.towers + 1] = tower:entindex()
            end
        elseif valid(unit) then result[key] = unit:entindex() end
    end
    return result
end
local function finish(state, status, reason)
    if state.report.status ~= "running" then return end
    state.report.status, state.report.error = status, reason
    state.report.finished_at = GameRules:GetGameTime()
    state.report.context, state.report.resources = contexts(state), wallet(state.pid)
    record(state, status == "ready" and "checkpoint_ready" or "checkpoint_blocked", {
        error = reason, stage = state.report.stage, context = state.report.context,
        resources = state.report.resources})
    if state.options.on_complete then pcall(state.options.on_complete, state.report) end
end
local function owned_card(pid, id)
    for _, instance in ipairs(runtime.snapshot(pid)) do if instance.card_id == id then return true end end
    return false
end

local function protect_scene_wall(state, enabled)
    local wall = state.ctx.wall
    if not valid(wall) then return nil, "native_test_wall_unavailable" end
    state.wall_protection_requested = enabled == true
    if enabled then
        if type(wall.AddNewModifier) ~= "function" or type(wall.HasModifier) ~= "function" then
            return nil, "native_test_wall_modifier_api_unavailable"
        end
        if not wall:HasModifier("modifier_invulnerable") then
            local ok, modifier = pcall(wall.AddNewModifier, wall, wall, nil, "modifier_invulnerable", {})
            if not ok or not modifier or not wall:HasModifier("modifier_invulnerable") then
                return nil, "native_test_wall_invulnerability_failed"
            end
            state.wall_protection_applied = true
        end
        local navigation = require("systems/wall_navigation_service")
        if type(navigation.create) ~= "function" then return nil, "native_test_wall_navigation_api_unavailable" end
        if not state.wall_navigation_guard then
            local original = navigation.create
            local guard = function(unit, ...)
                -- Normal wall navigation explicitly removes native
                -- invulnerability on each approach. Preserve that production
                -- operation, then restore only this owned Tools fixture before
                -- the actual enemy approach returns. No per-frame polling.
                local result = original(unit, ...)
                if tools() and unit == wall and state.wall_protection_requested and valid(wall)
                    and not wall:HasModifier("modifier_invulnerable") then
                    local ok, modifier = pcall(wall.AddNewModifier, wall, wall, nil, "modifier_invulnerable", {})
                    if not ok or not modifier or not wall:HasModifier("modifier_invulnerable") then
                        state.report.wall_protection_last_error = "native_test_wall_navigation_restore_failed"
                        record(state, "native_tools_wall_protection_blocked", {error = state.report.wall_protection_last_error})
                    else
                        state.wall_protection_applied = true
                        state.wall_protection_restores = (state.wall_protection_restores or 0) + 1
                    end
                end
                return result
            end
            state.wall_navigation_guard, state.wall_navigation_original = guard, original
            navigation.create = guard
        end
    else
        if state.wall_navigation_guard then
            local navigation = require("systems/wall_navigation_service")
            if navigation.create == state.wall_navigation_guard then navigation.create = state.wall_navigation_original end
            state.wall_navigation_guard, state.wall_navigation_original = nil, nil
        end
        if state.wall_protection_applied then
            if type(wall.RemoveModifierByName) ~= "function" then return nil, "native_test_wall_remove_modifier_api_unavailable" end
            wall:RemoveModifierByName("modifier_invulnerable")
            state.wall_protection_applied = false
        end
    end
    local active = type(wall.HasModifier) == "function" and wall:HasModifier("modifier_invulnerable") or false
    state.report.wall_protection = {entindex = wall:entindex(), enabled = active,
        applied_by_scene = state.wall_protection_applied == true,
        navigation_restore_guard = state.wall_navigation_guard ~= nil,
        validation = "native_tools_fixture_prevent_defeat_only",
        restoration = "fresh_map_reload; set_wall_protection(false) for damage consumers"}
    record(state, "native_tools_wall_protection", state.report.wall_protection)
    return true
end

local function extra_tower_positions(index)
    -- A checked two-dimensional search avoids assuming the next tower can use
    -- the same terrain lane. Existing buildings, trees and boundaries still go
    -- through BUILD_CAN_PLACE; this helper never changes terrain or removes trees.
    local points, seen = {}, {}
    local function add(x, y)
        local key = tostring(x) .. ":" .. tostring(y)
        if not seen[key] then seen[key] = true; points[#points + 1] = Vector(x, y, 385) end
    end
    add(1024 + index * 256, 5888)
    add(1152 + index * 256, 6400)
    add(-512 - index * 256, 6144)
    for radius = 1, 5 do
        for x = -radius, radius do
            for y = -radius, radius do
                if math.abs(x) == radius or math.abs(y) == radius then
                    add(1024 + x * 256, 5888 + y * 256)
                end
            end
        end
    end
    return points
end

local function build_node(id, positions, key, extra)
    local requested, existing, waiting_logged = false, {}, false
    return function(state)
        if not requested then
            local roster = buildings(state.pid, id)
            for _, row in ipairs(roster) do existing[row.entindex] = true end
            if not extra then
                for _, row in ipairs(roster) do
                    if valid(row.unit) and tonumber(row.player_id) == state.pid then
                        if not idle(row.unit) then
                            state.stage_deadline = state.stage_deadline or GameRules:GetGameTime() + 35
                            if not waiting_logged then
                                record(state, "waiting_existing_building_completion", {building_id = id, state = row})
                                waiting_logged = true
                            end
                            return false
                        end
                        state.ctx[key] = row.unit
                        record(state, "reuse_completed_building", {building_id = id, state = row})
                        return true
                    end
                end
                local task = state.ctx.builder and state.ctx.builder.survival_build_task
                if task and task.building_id == id then
                    -- A paid construction already requested by the runner must
                    -- finish normally; do not replace it with another order.
                    state.stage_deadline = state.stage_deadline or GameRules:GetGameTime() + 35
                    if not waiting_logged then
                        record(state, "waiting_existing_build_request", {building_id = id})
                        waiting_logged = true
                    end
                    return false
                end
            end
            local points = type(positions) == "function" and positions(state) or positions
            local attempts = {}
            for _, point in ipairs(points or {}) do
                local check = request(e.BUILD_CAN_PLACE_REQUEST, {player_id = state.pid,
                    caster = state.ctx.builder, building_id = id, position = point})
                attempts[#attempts + 1] = {position = tostring(point), ok = check and check.ok,
                    error = check and check.error, cost_quote = check and check.cost_quote}
                if check and check.ok then
                    FindClearSpaceForUnit(state.ctx.builder, point + Vector(350, 0, 0), true)
                    local result, why = request(e.BUILD_REQUEST, {player_id = state.pid,
                        caster = state.ctx.builder, building_id = id, position = point})
                    record(state, "build_requested", {building_id = id, attempts = attempts, result = result, error = why})
                    if not result or not result.ok then return nil, result and result.error or why or "build_request_failed" end
                    requested = true; state.stage_deadline = GameRules:GetGameTime() + 35
                    break
                end
            end
            if not requested then
                record(state, "placement_blocked", {building_id = id, attempts = attempts})
                return nil, "no_valid_placement:" .. id
            end
        end
        for _, row in ipairs(buildings(state.pid, id)) do
            if not existing[row.entindex] and tonumber(row.player_id) == state.pid and idle(row.unit) then
                if extra then state.ctx.towers[#state.ctx.towers + 1] = row.unit
                else state.ctx[key] = row.unit end
                record(state, "build_completed", {building_id = id, state = row})
                return true
            end
        end
        return false
    end
end

local function upgrade_to(state, unit, target_level, class_index)
    local before = query(unit)
    if not before then return nil, "authoritative_building_state_unavailable" end
    if not idle(unit) then return false end
    if state.pending_upgrade then
        local pending = state.pending_upgrade
        if tonumber(before.level) ~= pending.target_level then
            return nil, "actual_upgrade_completed_at_unexpected_level"
        end
        if pending.class_index and before.tower_class ~= "class_" .. pending.class_index then
            return nil, "actual_class_change_did_not_commit"
        end
        record(state, "upgrade_completed", {request = pending, actual_state = before})
        state.pending_upgrade = nil
    end
    if tonumber(before.level) >= target_level then return true end
    local mode, result, quote, expected
    if class_index and not before.tower_class and tonumber(before.level) >= 5 then
        expected = 6
        quote = request(e.TOWER_CLASS_CHECK_REQUEST, {player_id = state.pid,
            tower = unit, class_index = class_index})
        if not quote or not quote.ok then return nil, quote and quote.error or "class_check_unavailable" end
        result = request(e.TOWER_CLASS_REQUEST, {player_id = state.pid,
            tower = unit, class_index = class_index})
    else
        mode = "one"
        if before.building_id == "arrow_tower" then
            local stage_end = routes.stage_end_level(before)
            if stage_end > tonumber(before.level) then mode = "max" end
        end
        quote = request(e.BUILDING_UPGRADE_QUOTE_REQUEST, {player_id = state.pid,
            building = unit, upgrade_mode = mode})
        if not quote or not quote.ok then return nil, quote and quote.error or "upgrade_quote_unavailable" end
        expected = tonumber(quote.target_level)
        result = request(e.BUILDING_UPGRADE_REQUEST, {player_id = state.pid,
            building = unit, upgrade_mode = mode, silent_notification = true})
    end
    record(state, "upgrade_requested", {before = before, mode = mode, class_index = class_index,
        quote = quote, result = result, target_level = expected, resources = wallet(state.pid)})
    if not result or not result.ok then return nil, result and result.error or "upgrade_request_failed" end
    state.pending_upgrade = {entindex = unit:entindex(), from_level = tonumber(before.level),
        target_level = expected, upgrade_mode = mode, class_index = class_index and not before.tower_class
            and tonumber(before.level) >= 5 and class_index or nil}
    state.stage_deadline = GameRules:GetGameTime() + math.max(15, (tonumber(result.duration) or 1) + 8)
    return false
end

local function run_think(state)
    GameRules:GetGameModeEntity():SetContextThink("RogueFinalScene_" .. state.pid, function()
        if state.report.status ~= "running" then return nil end
        if not tools() then finish(state, "blocked", "tools_mode_ended"); return nil end
        if GameRules:GetGameTime() > state.deadline then finish(state, "blocked", "scene_timeout"); return nil end
        local node = state.nodes[state.cursor]
        if not node then finish(state, "ready"); return nil end
        state.report.stage = node.name
        local ok, done, why = pcall(node.run, state)
        if not ok or done == nil then
            finish(state, "blocked", not ok and tostring(done) or why); return nil
        end
        if done then
            state.report.checkpoints[#state.report.checkpoints + 1] = {
                stage = node.name, time = GameRules:GetGameTime(), context = contexts(state)}
            state.cursor, state.stage_deadline = state.cursor + 1, nil
        elseif state.stage_deadline and GameRules:GetGameTime() > state.stage_deadline then
            finish(state, "blocked", "stage_timeout:" .. node.name); return nil
        end
        return 0.1
    end, 0.1)
end

function M.progress(pid) return states[tonumber(pid) or 0] and states[tonumber(pid) or 0].report end
function M.context(pid) return states[tonumber(pid) or 0] and states[tonumber(pid) or 0].ctx end
function M.set_wall_protection(pid, enabled)
    assert(tools(), "requires_tools_mode")
    local state = assert(states[tonumber(pid) or 0], "scene_not_prepared")
    local ok, why = protect_scene_wall(state, enabled == true)
    if not ok then record(state, "native_tools_wall_protection_blocked", {error = why}) end
    return {ok = ok == true, error = why, protection = state.report.wall_protection}
end
function M.cancel(pid)
    local state = states[tonumber(pid) or 0]
    if state then finish(state, "blocked", "cancelled_by_runner"); return true end
    return false
end
function M.resume(pid, options)
    assert(tools(), "requires_tools_mode")
    local state = assert(states[tonumber(pid) or 0], "scene_not_prepared")
    if state.report.status ~= "blocked" then return state.report end
    for key, value in pairs(options or {}) do state.options[key] = value end
    state.report.status, state.report.error, state.report.finished_at = "running", nil, nil
    state.deadline, state.stage_deadline = GameRules:GetGameTime() + (tonumber(state.options.timeout_seconds) or 180), nil
    run_think(state); return state.report
end

function M.prepare(pid, options)
    pid, options = tonumber(pid) or 0, options or {}
    assert(tools(), "requires_tools_mode")
    if states[pid] then return states[pid].report end
    local state = {pid = pid, options = options, ctx = {towers = {}}, cursor = 1,
        deadline = GameRules:GetGameTime() + (tonumber(options.timeout_seconds) or 180), nodes = {},
        report = {player_id = pid, status = "running", stage = "waiting_scene_ready",
            started_at = GameRules:GetGameTime(), steps = {}, checkpoints = {}, assertions = {},
            validation = "normal_business_requests_with_native_tools_builder_positioning"}}
    states[pid] = state
    local function node(name, callback) state.nodes[#state.nodes + 1] = {name = name, run = callback} end
    node("acquire_normal_builder", function(s)
        local response = request(e.BUILDER_GET_REQUEST, {player_id = pid}) or {}
        local account = wallet(pid)
        if not valid(response.builder) or type(account.wood) ~= "number" then return false end
        s.ctx.builder = response.builder
        if account.debug_mode == 1 or account.debug_mode == true then return nil, "requires_fresh_non_debug_wallet" end
        return true
    end)
    -- N1 starts with a builder, not an already built wall. Use the same quote,
    -- placement validation, resource debit, movement and construction as a
    -- player. No funding or wave freeze occurs until this native wall exists.
    node("build_native_wall", build_node("wall", options.wall_positions or {
        Vector(256,6656,385), Vector(-256,6656,385), Vector(1280,6912,385),
        Vector(-512,5888,385), Vector(0,6400,385), Vector(1536,6144,385),
        Vector(-768,6656,385), Vector(1280,5632,385)}, "wall"))
    node("fund_normal_account", function(s)
        local account = wallet(pid)
        if account.debug_mode == 1 or account.debug_mode == true then return nil, "requires_fresh_non_debug_wallet" end
        if not idle(s.ctx.wall) then return nil, "native_test_completed_wall_unavailable" end
        if s.options.protect_wall == false then
            record(s, "native_tools_wall_protection_explicitly_disabled", {
                requested = false, wall_available = valid(s.ctx.wall) == true,
                reason = "explicit caller option; mock cannot provide native modifier protection"})
        else
            local protected, why = protect_scene_wall(s, true)
            if not protected then
                record(s, "native_tools_wall_protection_blocked", {error = why,
                    listed_wall_count = #buildings(pid, "wall"), requires_explicit_mock_option = "protect_wall=false"})
                return nil, why
            end
        end
        require("systems/wave_system").set_dev_mode(true)
        local result = request(e.RESOURCE_ADD_REQUEST, {player_id = pid, team = PlayerResource:GetTeam(pid),
            wood = 10000000, gold = 10000000, reason = "rogue_final_scene_setup"})
        record(s, "normal_resource_funding", {before = account, result = result, after = wallet(pid),
            wave_dev_mode = require("systems/wave_system").is_dev_mode()})
        if not result or not result.ok then return nil, result and result.error or "resource_add_failed" end
        s.report.assertions[#s.report.assertions + 1] = {name = "normal_resource_account_not_debug",
            expected = 0, actual = wallet(pid).debug_mode, status = wallet(pid).debug_mode == 0 and "pass" or "fail"}
        return true
    end)
    node("build_main_city", build_node("main_city", options.city_positions or {
        Vector(768,6144,385), Vector(-512,6144,385), Vector(896,6656,385)}, "city"))
    node("build_base_tower", build_node("arrow_tower", options.tower_positions or {
        Vector(1024,5888,385), Vector(1152,6656,385), Vector(1408,6400,385)}, "tower"))
    node("select_hero_descent", function(s)
        if owned_card(pid, "hero_descent") then record(s, "hero_descent_already_selected", {}); return true end
        local selection = probe.grant("hero_descent", pid, {via_selection = true})
        record(s, "formal_hero_descent_selection", selection)
        if not selection or not selection.ok then return nil, selection and selection.error or "card_selection_failed" end
        return true
    end)
    node("build_free_altar", build_node("hero_altar", options.altar_positions or {
        Vector(256,6016,385), Vector(0,6016,385), Vector(512,5760,385)}, "altar"))
    local summon_started = false
    node("summon_native_doom", function(s)
        local hero = request(e.HERO_SUMMON_GET_REQUEST, {player_id = pid}) or {}
        if hero.ok and valid(hero.unit) then
            if hero.hero_id ~= "hero_doom" then return nil, "existing_hero_is_not_doom" end
            s.ctx.hero = hero.unit
            local owner = tonumber(hero.unit.survival_player_id)
            local engine_owner = hero.unit.GetPlayerOwnerID and tonumber(hero.unit:GetPlayerOwnerID())
            record(s, "native_hero_owner", {entindex = hero.unit:entindex(), hero_id = hero.hero_id,
                survival_player_id = owner, engine_player_id = engine_owner})
            s.report.assertions[#s.report.assertions + 1] = {name = "normal_summoned_hero_authoritative_owner",
                actual = owner, expected = pid, status = owner == pid and "pass" or "fail"}
            if owner ~= pid then return nil, "native_hero_authoritative_owner_mismatch" end
            return true
        end
        if not summon_started then
            local result = request(e.HERO_SUMMON_REQUEST, {player_id = pid, hero_id = "hero_doom",
                debug_bypass = s.options.allow_hero_debug_bypass == true, reason = "rogue_final_scene_setup"})
            record(s, "normal_hero_summon_requested", result)
            if not result or not result.ok then
                s.report.hero_summon_fallback = {normal_error = result and result.error or "summon_handler_unavailable",
                    action = "root may explicitly resume with allow_hero_debug_bypass=true"}
                return nil, result and result.error or "summon_handler_unavailable"
            end
            summon_started = true; s.stage_deadline = GameRules:GetGameTime() + 60
        end
        return false
    end)
    local train_started, prior_workers = false, {}
    node("train_normal_worker", function(s)
        if not train_started then
            for _, row in ipairs(request(e.WORKER_LIST_REQUEST, {player_id = pid}) or {}) do
                prior_workers[row.unit:entindex()] = true
            end
            local result = request(e.WORKER_TRAIN_REQUEST, {player_id = pid, city = s.ctx.city,
                training_id = "train_lumberjack_01"})
            record(s, "normal_worker_training_requested", result)
            if not result or not result.ok then return nil, result and result.error or "training_handler_unavailable" end
            train_started = true; s.stage_deadline = GameRules:GetGameTime() + 15
        end
        for _, row in ipairs(request(e.WORKER_LIST_REQUEST, {player_id = pid}) or {}) do
            if valid(row.unit) and not prior_workers[row.unit:entindex()] then
                s.ctx.worker = row.unit; record(s, "normal_worker_training_completed", row); return true
            end
        end
        return false
    end)
    node("upgrade_city_to_five", function(s) return upgrade_to(s, s.ctx.city, 5) end)
    node("upgrade_tower_final_class_five", function(s)
        local snapshot = query(s.ctx.tower)
        if snapshot and snapshot.tower_class and snapshot.tower_class ~= "class_5" then
            return nil, "existing_tower_route_is_not_class_five"
        end
        return upgrade_to(s, s.ctx.tower, #routes.get_route("class_5") + 5, 5)
    end)
    node("register_primary_tower_context", function(s)
        s.ctx.towers[1] = s.ctx.tower; return true
    end)
    for i = 1, math.max(0, math.min(6, tonumber(options.extra_base_towers) or 0)) do
        local n = i
        node("build_extra_base_tower_" .. n, build_node("arrow_tower", function()
            return options.extra_positions and options.extra_positions[n] or extra_tower_positions(n)
        end, "extra_tower_" .. n, true))
    end
    run_think(state)
    return state.report
end

return M
