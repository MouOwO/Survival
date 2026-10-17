-- Manual Tools scene preparation. Reuses the already loaded final_scene module
-- without reloading it or losing its running state. All towers are built,
-- upgraded, classed and fused through their normal production requests.
local M, states = {}, {}
local bus, e = require("core/event_bus"), require("core/events")
local json = require("core/json_encoder")
local routes = require("config/tower_route_config")

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
    if type(value.entindex) == "function" then return value:entindex() end
    seen = seen or {}; if seen[value] then return "<cycle>" end; seen[value] = true
    local out = {}; for key, item in pairs(value) do
        if key == "definition" then out.definition_id = type(item) == "table" and item.id or nil
        elseif type(item) ~= "function" then out[key] = compact(item, seen) end
    end
    seen[value] = nil; return out
end
local function wallet(pid)
    local value = request(e.RESOURCE_GET_REQUEST, {player_id = pid}) or {}
    return value.snapshot or value
end
local function towers(pid)
    local listed = request(e.BUILDING_LIST_REQUEST, {player_id = pid, building_id = "arrow_tower"}) or {}
    return listed.buildings or {}
end
local function query(unit)
    return valid(unit) and request(e.BUILDING_QUERY_REQUEST, {entindex = unit:entindex()}) or nil
end
local function idle(unit)
    return valid(unit) and not unit:HasModifier("modifier_building_under_construction")
        and not require("systems/building_upgrade_process").is_active(unit)
end
local function record(state, kind, data)
    local item = {time = GameRules:GetGameTime(), kind = kind, data = compact(data)}
    state.report.steps[#state.report.steps + 1] = item
    print("[ROGUE_FUSION_SCENE] " .. json.encode({player_id = state.pid, step = item}))
end
local function finish(state, status, why)
    if state.report.status ~= "running" then return end
    state.report.status, state.report.error, state.report.finished_at = status, why, GameRules:GetGameTime()
    state.report.resources = wallet(state.pid)
    state.report.ultimate = valid(state.ctx.ultimate) and state.ctx.ultimate:entindex() or nil
    record(state, status == "ready" and "fusion_checkpoint_ready" or "fusion_checkpoint_blocked", {
        stage = state.report.stage, error = why, ultimate = state.report.ultimate,
        resources = state.report.resources})
    if state.options.on_complete then pcall(state.options.on_complete, state.report) end
end
local function assertion(state, name, expected, actual)
    state.report.assertions[#state.report.assertions + 1] = {name = name, expected = expected,
        actual = actual, status = actual == expected and "pass" or "fail"}
    return actual == expected
end

local function positions(state, index)
    if state.options.extra_positions and state.options.extra_positions[index] then
        return state.options.extra_positions[index]
    end
    local center = state.ctx.tower:GetAbsOrigin()
    local points, seen = {}, {}
    local function add(x, y, z)
        local key = tostring(x) .. ":" .. tostring(y)
        if not seen[key] then seen[key] = true; points[#points + 1] = Vector(x, y, z) end
    end
    -- Known scene coordinates first, then independent rows and columns around
    -- the actual primary tower. Placement checks reject occupied cells, terrain,
    -- trees and player boundaries without changing any of them.
    add(1024 + index * 256, 5888, 385)
    add(1152 + index * 256, 6400, 385)
    add(-512 - index * 256, 6144, 385)
    for radius = 1, 7 do
        for x = -radius, radius do
            for y = -radius, radius do
                if math.abs(x) == radius or math.abs(y) == radius then
                    add(center.x + x * 256, center.y + y * 256, center.z)
                end
            end
        end
    end
    return points
end

local function ensure_seven(state)
    local roster = towers(state.pid)
    if #roster > 7 then return nil, "scene_contains_more_than_seven_towers" end
    if state.pending_build then
        for _, row in ipairs(roster) do
            if not state.pending_build.before[row.entindex] and idle(row.unit) then
                record(state, "normal_extra_tower_completed", row)
                state.pending_build, state.stage_deadline = nil, nil
                break
            end
        end
        if state.pending_build then return false end
    end
    if #roster == 7 then
        for _, row in ipairs(roster) do if not idle(row.unit) then return false end end
        return true
    end
    local before, attempts = {}, {}
    for _, row in ipairs(roster) do before[row.entindex] = true end
    for _, point in ipairs(positions(state, #roster + 1)) do
        local check = request(e.BUILD_CAN_PLACE_REQUEST, {player_id = state.pid,
            caster = state.ctx.builder, building_id = "arrow_tower", position = point})
        attempts[#attempts + 1] = {position = tostring(point), ok = check and check.ok,
            error = check and check.error}
        if check and check.ok then
            FindClearSpaceForUnit(state.ctx.builder, point + Vector(350, 0, 0), true)
            local result, why = request(e.BUILD_REQUEST, {player_id = state.pid,
                caster = state.ctx.builder, building_id = "arrow_tower", position = point})
            record(state, "normal_extra_tower_requested", {attempts = attempts, result = result, error = why})
            if not result or not result.ok then return nil, result and result.error or why or "build_request_failed" end
            state.pending_build = {before = before}; state.stage_deadline = GameRules:GetGameTime() + 35
            return false
        end
    end
    record(state, "extra_placement_blocked", {attempts = attempts})
    return nil, "no_valid_extra_tower_placement"
end

local function assign_routes(state)
    local roster, assigned, seen = towers(state.pid), {}, {}
    if #roster ~= 7 then return nil, "requires_seven_completed_towers" end
    local primary = query(state.ctx.tower)
    if not primary or primary.player_id ~= state.pid or primary.tower_class ~= "class_5" then
        return nil, "primary_tower_must_be_owned_class_five"
    end
    for _, row in ipairs(roster) do
        if row.tower_class then
            if seen[row.tower_class] then return nil, "duplicate_existing_route:" .. row.tower_class end
            seen[row.tower_class] = true
            assigned[#assigned + 1] = {unit = row.unit, class_index = tonumber(row.tower_class:match("(%d+)$"))}
        end
    end
    for _, row in ipairs(roster) do
        if not row.tower_class then
            local choice
            for index = 1, 7 do if not seen["class_" .. index] then choice = index; break end end
            if not choice then return nil, "no_unused_tower_route" end
            seen["class_" .. choice] = true
            assigned[#assigned + 1] = {unit = row.unit, class_index = choice}
        end
    end
    table.sort(assigned, function(a, b) return a.class_index < b.class_index end)
    state.assigned, state.route_cursor, state.ctx.towers = assigned, 1, {}
    state.report.material_entindexes = {}
    for _, item in ipairs(assigned) do
        state.ctx.towers[#state.ctx.towers + 1] = item.unit
        state.report.material_entindexes[#state.report.material_entindexes + 1] = item.unit:entindex()
    end
    record(state, "authoritative_route_assignment", assigned)
    return true
end

local function upgrade_to(state, item)
    local unit, class_index = item.unit, item.class_index
    local before = query(unit)
    if not before or before.player_id ~= state.pid then return nil, "authoritative_owned_tower_unavailable" end
    if before.tower_class and before.tower_class ~= "class_" .. class_index then return nil, "tower_route_changed_during_setup" end
    if not idle(unit) then return false end
    if state.pending_upgrade then
        local pending = state.pending_upgrade
        if tonumber(before.level) ~= pending.target_level then return nil, "upgrade_completed_at_unexpected_level" end
        if pending.class_index and before.tower_class ~= "class_" .. pending.class_index then return nil, "class_change_not_committed" end
        record(state, "normal_upgrade_completed", {request = pending, actual = before})
        state.pending_upgrade, state.stage_deadline = nil, nil
    end
    local route = routes.get_route("class_" .. class_index)
    if not route then return nil, "invalid_formal_route" end
    local target = #route + 5
    if tonumber(before.level) == target then return true end
    if tonumber(before.level) > target then return nil, "tower_level_exceeds_formal_route" end
    local quote, result, expected, mode, changing
    if not before.tower_class and tonumber(before.level) >= 5 then
        changing, expected = true, 6
        quote = request(e.TOWER_CLASS_CHECK_REQUEST, {player_id = state.pid, tower = unit, class_index = class_index})
        if not quote or not quote.ok then return nil, quote and quote.error or "class_check_unavailable" end
        result = request(e.TOWER_CLASS_REQUEST, {player_id = state.pid, tower = unit, class_index = class_index})
    else
        mode = routes.stage_end_level(before) > tonumber(before.level) and "max" or "one"
        quote = request(e.BUILDING_UPGRADE_QUOTE_REQUEST, {player_id = state.pid, building = unit, upgrade_mode = mode})
        if not quote or not quote.ok then return nil, quote and quote.error or "upgrade_quote_unavailable" end
        expected = tonumber(quote.target_level)
        if not expected or expected <= tonumber(before.level) or expected > target then return nil, "invalid_authoritative_upgrade_quote" end
        result = request(e.BUILDING_UPGRADE_REQUEST, {player_id = state.pid, building = unit,
            upgrade_mode = mode, silent_notification = true})
    end
    record(state, "normal_upgrade_requested", {before = before, quote = quote, result = result,
        class_index = class_index, upgrade_mode = mode, target_level = expected, resources = wallet(state.pid)})
    if not result or not result.ok then return nil, result and result.error or "upgrade_request_failed" end
    state.pending_upgrade = {entindex = unit:entindex(), from_level = before.level,
        target_level = expected, class_index = changing and class_index or nil, upgrade_mode = mode}
    state.stage_deadline = GameRules:GetGameTime() + math.max(15, (tonumber(result.duration) or 1) + 8)
    return false
end

local function think(state)
    GameRules:GetGameModeEntity():SetContextThink("RogueFusionScene_" .. state.pid, function()
        if state.report.status ~= "running" then return nil end
        if not tools() then finish(state, "blocked", "tools_mode_ended"); return nil end
        if GameRules:GetGameTime() > state.deadline then finish(state, "blocked", "fusion_scene_timeout"); return nil end
        local node = state.nodes[state.cursor]
        if not node then finish(state, "ready"); return nil end
        state.report.stage = node.name
        local ok, done, why = pcall(node.run, state)
        if not ok or done == nil then finish(state, "blocked", not ok and tostring(done) or why); return nil end
        if done then state.cursor, state.stage_deadline = state.cursor + 1, nil
        elseif state.stage_deadline and GameRules:GetGameTime() > state.stage_deadline then
            finish(state, "blocked", "stage_timeout:" .. node.name); return nil
        end
        return 0.1
    end, 0.1)
end

function M.progress(pid) return states[tonumber(pid) or 0] and states[tonumber(pid) or 0].report end
function M.context(pid) return states[tonumber(pid) or 0] and states[tonumber(pid) or 0].ctx end
function M.cancel(pid)
    assert(tools(), "requires_tools_mode")
    local state = states[tonumber(pid) or 0]
    if not state then return false end
    finish(state, "blocked", "cancelled_by_runner"); return true
end
function M.resume(pid, options)
    assert(tools(), "requires_tools_mode")
    local state = assert(states[tonumber(pid) or 0], "fusion_scene_not_prepared")
    if state.report.status ~= "blocked" then return state.report end
    for key, value in pairs(options or {}) do state.options[key] = value end
    state.report.status, state.report.error, state.report.finished_at = "running", nil, nil
    state.deadline, state.stage_deadline = GameRules:GetGameTime() + (tonumber(state.options.timeout_seconds) or 180), nil
    think(state); return state.report
end
function M.prepare_fusion(pid, options)
    assert(tools(), "requires_tools_mode")
    pid, options = tonumber(pid) or 0, options or {}
    if states[pid] then return states[pid].report end
    local ctx = options.context or require("tests/game_rogue_final_scene").context(pid)
    assert(ctx and valid(ctx.builder) and valid(ctx.tower), "existing_final_scene_context_required")
    local state = {pid = pid, options = options, ctx = ctx, cursor = 1, nodes = {},
        deadline = GameRules:GetGameTime() + (tonumber(options.timeout_seconds) or 180),
        report = {player_id = pid, status = "running", stage = "waiting_fusion_setup",
            started_at = GameRules:GetGameTime(), steps = {}, assertions = {},
            validation = "normal_business_build_upgrade_class_and_fusion_requests"}}
    states[pid] = state
    local function node(name, fn) state.nodes[#state.nodes + 1] = {name = name, run = fn} end
    node("fund_normal_fusion_account", function(s)
        local before = wallet(pid)
        if before.debug_mode ~= 0 then return nil, "requires_normal_non_debug_wallet" end
        local result = request(e.RESOURCE_ADD_REQUEST, {player_id = pid, team = PlayerResource:GetTeam(pid),
            wood = 40000000, gold = 20000000, reason = "rogue_fusion_scene_setup"})
        record(s, "normal_fusion_funding", {before = before, result = result, after = wallet(pid)})
        if not result or not result.ok then return nil, result and result.error or "resource_add_failed" end
        if not assertion(s, "fusion_wallet_remains_non_debug", 0, wallet(pid).debug_mode) then return nil, "debug_wallet_after_funding" end
        return true
    end)
    node("build_to_seven_native_towers", ensure_seven)
    node("assign_seven_unique_formal_routes", assign_routes)
    node("upgrade_all_routes_authoritatively", function(s)
        local item = s.assigned[s.route_cursor]
        if not item then return true end
        s.report.active_route = {class_index = item.class_index, entindex = item.unit:entindex()}
        local done, why = upgrade_to(s, item)
        if done == nil then return nil, why end
        if done then
            local current = query(item.unit)
            record(s, "route_reached_formal_terminal", current)
            s.route_cursor = s.route_cursor + 1
        end
        return false
    end)
    node("check_real_fusion_eligibility", function(s)
        local eligible = request(e.TOWER_FUSION_ELIGIBILITY_REQUEST, {player_id = pid})
        record(s, "real_fusion_eligibility", eligible)
        if not eligible or not eligible.ok or not eligible.eligible then
            return nil, eligible and eligible.error or "normal_fusion_not_eligible"
        end
        if not assertion(s, "seven_unique_terminal_routes_eligible", 7, eligible.route_count) then return nil, "fusion_route_count_mismatch" end
        return true
    end)
    node("request_real_tower_fusion", function(s)
        local result = request(e.TOWER_FUSION_REQUEST, {caster = s.ctx.tower})
        record(s, "real_tower_fusion_requested", result)
        if not result or not result.ok or not valid(result.unit) then return nil, result and result.error or "native_fusion_result_unavailable" end
        s.ctx.ultimate = result.unit
        if not assertion(s, "ultimate_native_player_identity", pid, tonumber(result.unit.survival_player_id)) then return nil, "ultimate_owner_mismatch" end
        if not assertion(s, "native_result_is_ultimate_tower", true, result.unit.survival_ultimate_tower == true) then return nil, "ultimate_flag_missing" end
        local remaining = {}; for _, row in ipairs(towers(pid)) do remaining[row.entindex] = true end
        local consumed = 0
        for _, index in ipairs(s.report.material_entindexes) do if not remaining[index] then consumed = consumed + 1 end end
        if not assertion(s, "seven_materials_consumed_by_production", 7, consumed) then return nil, "fusion_materials_remain_registered" end
        return true
    end)
    think(state); return state.report
end
M.prepare = M.prepare_fusion
return M
