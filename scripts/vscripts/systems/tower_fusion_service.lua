local event_bus = require("core/event_bus")
local events = require("core/events")
local routes = require("config/tower_route_config")
local runtime = require("config/generated/tower_fusion_runtime")
local skill_bindings = require("config/generated/ultimate_tower_skill_bindings")
local tower_skills = require("systems/tower_skill_runtime")
local tower_ability_sync = require("systems/tower_ability_sync")

local M = {}

local ultimate_by_player = {}
local state_by_entindex = {}
local wall_by_player = {}
local group_at_wall_by_player = {}
local fusion_in_progress = {}

local function config()
    return runtime.by_id.ultimate_tower or {}
end

local function hero_r_active(player_id)
    local result = event_bus.request(events.HERO_SKILL_STATE_GET_REQUEST, {
        player_id = player_id,
    })
    for _, skill in ipairs(result and result.snapshot
            and result.snapshot.skills or {}) do
        if skill.skill_id == "skill_monkey_king_agility"
            or skill.skill_id == "skill_blademaster_mobility" then
            return skill.locked ~= 1 and (tonumber(skill.level) or 0) > 0
        end
    end
    return false
end

local function refresh_inherited_hero_stats(state, snapshot)
    if not state or not state.unit or state.unit:IsNull()
        or not hero_r_active(state.player_id)
        or not snapshot then return end
    local attack = (tonumber(state.fused_base_attack) or 0)
        + ((tonumber(snapshot.engine_attack_min) or 0)
        + (tonumber(snapshot.engine_attack_max) or 0)) * 0.5
    state.unit:SetBaseDamageMin(math.max(0, attack))
    state.unit:SetBaseDamageMax(math.max(0, attack))
    state.base_attack = math.max(0, attack)
    state.unit.survival_inherited_critical_chance_pct = math.max(0,
        tonumber(snapshot.critical_chance_pct) or 0)
    state.unit.survival_inherited_critical_damage_pct = math.max(100,
        tonumber(snapshot.critical_damage_pct) or 200)
end

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit.IsAlive and unit:IsAlive()
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function final_row(class_id)
    local route = routes.get_route(class_id) or {}
    return route[#route]
end

local function player_ultimates(player_id)
    local result = {}
    local saved = ultimate_by_player[player_id] or {}
    for _, state in ipairs(saved) do
        if alive(state.unit) then result[#result + 1] = state end
    end
    ultimate_by_player[player_id] = result
    return result
end

local function ultimate_limit()
    return 1
end

local function distance_sq(left, right)
    local delta = left:GetAbsOrigin() - right:GetAbsOrigin()
    return delta.x * delta.x + delta.y * delta.y
end

local function select_towers(caster, player_id, buildings)
    local caster_state
    local candidates = {}
    for _, item in ipairs(buildings or {}) do
        if item.unit == caster then caster_state = item end
        local row = item.tower_class and final_row(item.tower_class) or nil
        if item.player_id == player_id and item.building_id == "arrow_tower"
            and row and tonumber(item.route_level) == tonumber(row.level)
            and tonumber(item.fusion_participated) ~= 1 then
            candidates[item.tower_class] = candidates[item.tower_class] or {}
            candidates[item.tower_class][#candidates[item.tower_class] + 1] = item
        end
    end
    if not caster_state or not caster_state.tower_class
        or tonumber(caster_state.fusion_participated) == 1 then
        return nil, "fusion_caster_invalid"
    end
    local caster_row = final_row(caster_state.tower_class)
    if not caster_row
        or tonumber(caster_state.route_level) ~= tonumber(caster_row.level) then
        return nil, "fusion_caster_not_final"
    end
    local selected = {}
    for _, class_id in ipairs(config().route_ids or {}) do
        local choice
        for _, item in ipairs(candidates[class_id] or {}) do
            if item.unit == caster then
                choice = item
                break
            end
            if not choice or distance_sq(item.unit, caster) < distance_sq(choice.unit, caster)
                or (distance_sq(item.unit, caster) == distance_sq(choice.unit, caster)
                    and item.entindex < choice.entindex) then
                choice = item
            end
        end
        if not choice then return nil, "fusion_route_missing:" .. class_id end
        selected[#selected + 1] = choice
    end
    if #selected ~= 7 then return nil, "fusion_requires_seven_routes" end
    return selected
end

local function eligibility(player_id, buildings)
    local selected = {}
    local routes_ready = {}
    for _, item in ipairs(buildings or {}) do
        local row = item.tower_class and final_row(item.tower_class) or nil
        if item.player_id == player_id and item.building_id == "arrow_tower"
            and row and tonumber(item.route_level) == tonumber(row.level)
            and tonumber(item.fusion_participated) ~= 1
            and not routes_ready[item.tower_class] then
            routes_ready[item.tower_class] = true
            selected[#selected + 1] = item
        end
    end
    local current = #player_ultimates(player_id)
    local maximum = ultimate_limit()
    return {
        ok = true,
        eligible = #selected == #(config().route_ids or {}) and current < maximum,
        route_count = #selected,
        ultimate_count = current,
        maximum = maximum,
    }
end

local function ultimate_skill_ids()
    local result, seen = {}, {}
    for _, binding in ipairs(skill_bindings.rows or {}) do
        if binding.enabled ~= false and not seen[binding.skill_id] then
            seen[binding.skill_id] = true
            result[#result + 1] = binding.skill_id
        end
    end
    return result
end

local function add_ultimate_skills(unit)
    local skill_ids = ultimate_skill_ids()
    for _, skill_id in ipairs(skill_ids) do
        local ability = unit:AddAbility(skill_id)
        if ability then
            ability:SetLevel(1)
            ability:SetHidden(true)
            ability:SetActivated(true)
        end
    end
    tower_skills.apply(unit, skill_ids)
    unit.survival_ultimate_skill_ids = skill_ids
    return skill_ids
end

local function initialize_ultimate(unit, player_id, team_number, selected, position,
    replaced_entindex)
    if unit.SetPlayerID then unit:SetPlayerID(player_id) end
    unit:SetOwner(PlayerResource:GetPlayer(player_id))
    unit:SetControllableByPlayer(player_id, true)
    unit:SetAttackCapability(DOTA_UNIT_CAP_RANGED_ATTACK)
    if unit.SetAcquisitionRange then unit:SetAcquisitionRange(1000) end
    unit.survival_ultimate_tower = true
    unit.survival_player_id = player_id
    unit.survival_display_name = config().display_name or "终极塔"
    local model = config().model_name
    if model and model ~= "" then
        unit:SetModel(model)
        unit:SetOriginalModel(model)
    end

    local maximum, current, armor, attack = 0, 0, 0, 0
    local multiplier = tonumber(config().base_attack_multiplier) or 3
    for _, source in ipairs(selected) do
        maximum = maximum + math.max(0, source.max_health)
        current = current + math.max(0, source.health)
        armor = armor + source.armor
        local base = source.base_attack_damage
        local actual = source.attack_damage
        attack = attack + base * multiplier + math.max(0, actual - base)
    end
    local fused_attack = attack
    local hero_stats_result = event_bus.request(
        events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local hero_stats = hero_stats_result and hero_stats_result.snapshot or {}
    if hero_r_active(player_id) then
        attack = fused_attack + math.max(0,
            ((tonumber(hero_stats.engine_attack_min) or 0)
                + (tonumber(hero_stats.engine_attack_max) or 0)) * 0.5)
        unit.survival_inherited_critical_chance_pct = math.max(0,
            tonumber(hero_stats.critical_chance_pct) or 0)
        unit.survival_inherited_critical_damage_pct = math.max(100,
            tonumber(hero_stats.critical_damage_pct) or 200)
    end
    unit:SetBaseMaxHealth(math.max(1, maximum))
    unit:SetMaxHealth(math.max(1, maximum))
    unit:SetHealth(math.max(1, math.min(maximum, current)))
    unit:SetPhysicalArmorBaseValue(armor)
    unit:SetBaseDamageMin(attack)
    unit:SetBaseDamageMax(attack)
    local attack_speed = math.max(0.01, tonumber(config().base_attack_speed) or 3)
    unit:SetBaseAttackTime(1 / attack_speed)
    unit.survival_attack_speed = attack_speed

    local state = {
        player_id = player_id,
        team_number = team_number,
        unit = unit,
        base_attack = attack,
        fused_base_attack = fused_attack,
        at_wall = false,
        footprint = selected[1].definition
            and selected[1].definition.footprint or { x = 2, y = 2 },
    }
    unit:AddNewModifier(unit, nil, "modifier_tower_attack_effects", {})
    for index, ability_name in ipairs(config().passive_slot_ability_ids or {}) do
        local ability = unit:AddAbility(ability_name)
        if ability then
            ability:SetLevel(1)
            ability:SetHidden(false)
            ability:SetActivated(false)
            ability.survival_passive_slot = index
        end
    end
    for _, ability_name in ipairs(config().utility_ability_ids or {}) do
        local ability = unit:AddAbility(ability_name)
        if ability then
            ability:SetLevel(1)
            ability:SetHidden(false)
            ability:SetActivated(true)
        end
    end
    -- AbilityLayout is the native visible bar size. Add every visible slot
    -- before the hidden runtime skills so the engine's natural indices remain
    -- 0..4 for the aggregate passives and 5..6 for the utility abilities.
    add_ultimate_skills(unit)
    local ignored_entindexes = { [unit:entindex()] = true }
    for _, source in ipairs(selected) do
        ignored_entindexes[source.entindex] = true
    end
    local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = position,
        footprint = state.footprint,
        ignore_entindexes = ignored_entindexes,
        ignore_entindex = replaced_entindex,
        team = team_number,
    })
    if not grid or grid.ok ~= true then
        return nil, grid and grid.error or "fusion_grid_invalid"
    end
    state.grid_x = grid.grid_x
    state.grid_y = grid.grid_y
    state.unit:SetAbsOrigin(grid.world_position or position)
    return state
end

local function prepare_ultimate(player_id, team_number, selected, position,
    replaced_entindex)
    local unit = CreateUnitByName(
        config().unit_name, position, true,
        nil, nil, team_number
    )
    if not valid(unit) then return nil, "fusion_create_failed" end
    local ok, state, error_code = pcall(
        initialize_ultimate,
        unit, player_id, team_number, selected, position, replaced_entindex
    )
    if not ok or not state then
        if valid(unit) then unit:RemoveSelf() end
        if not ok then
            print("[TowerFusion] ultimate initialization failed: " .. tostring(state))
            return nil, "fusion_create_runtime_error"
        end
        return nil, error_code
    end
    return state
end

local function commit_ultimate(state)
    local unit = state.unit
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x,
        grid_y = state.grid_y,
        footprint = state.footprint,
        entindex = unit:entindex(),
    })
    state_by_entindex[unit:entindex()] = state
    ultimate_by_player[state.player_id] = ultimate_by_player[state.player_id] or {}
    ultimate_by_player[state.player_id][#ultimate_by_player[state.player_id] + 1] = state
    event_bus.emit(events.TOWER_FUSION_RUNTIME_CHANGED, {
        unit = unit,
        entindex = unit:entindex(),
        player_id = state.player_id,
        team = state.team_number,
        building_id = "ultimate_tower",
        level = 1,
    })
    return state
end

local function remove_ultimate_state(state)
    if not state then return end
    local entindex = valid(state.unit) and state.unit:entindex() or nil
    if entindex then
        event_bus.request(events.GRID_RELEASE_REQUEST, {
            grid_x = state.grid_x,
            grid_y = state.grid_y,
            footprint = state.footprint,
            entindex = entindex,
        })
        state_by_entindex[entindex] = nil
        event_bus.emit(events.TOWER_FUSION_RUNTIME_REMOVED, {
            entindex = entindex,
            player_id = state.player_id,
        })
    end
    local saved = ultimate_by_player[state.player_id] or {}
    for index = #saved, 1, -1 do
        if saved[index] == state then table.remove(saved, index) end
    end
end

local function move_state(state, destination, grid)
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = state.grid_x,
        grid_y = state.grid_y,
        footprint = state.footprint,
        entindex = state.unit:entindex(),
    })
    state.grid_x = grid.grid_x
    state.grid_y = grid.grid_y
    state.unit:Stop()
    state.unit:SetAbsOrigin(destination)
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x,
        grid_y = state.grid_y,
        footprint = state.footprint,
        entindex = state.unit:entindex(),
    })
    return true
end

local function move_for_player(payload)
    local player_id = tonumber(payload and payload.player_id)
    local state = state_by_entindex[tonumber(payload and payload.entindex) or -1]
    local position = payload and payload.position
    if not state or state.player_id ~= player_id or not alive(state.unit) then
        return { ok = false, error = "ultimate_tower_not_owned" }
    end
    local ability = state.unit:FindAbilityByName("ability_building_blink")
    if not ability or ability:IsNull() or ability:IsHidden()
        or not ability:IsActivated() then
        return { ok = false, error = "move_ability_unavailable" }
    end
    if not position then return { ok = false, error = "invalid_position" } end
    local origin = state.unit:GetAbsOrigin()
    local delta = position - origin
    delta.z = 0
    if delta:Length2D() > 1000 then
        position = origin + delta:Normalized() * 1000
    end
    local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = position,
        footprint = state.footprint,
        ignore_entindex = state.unit:entindex(),
        team = state.unit:GetTeamNumber(),
    })
    if not grid or grid.ok ~= true then
        return { ok = false, error = grid and grid.error
            or "relocation_position_invalid" }
    end
    local moved, move_error = move_state(
        state, grid.world_position or position, grid
    )
    if not moved then return { ok = false, error = move_error } end
    return { ok = true }
end

local function destroy_for_player(payload)
    local player_id = tonumber(payload and payload.player_id)
    local state = state_by_entindex[tonumber(payload and payload.entindex) or -1]
    if not state or state.player_id ~= player_id or not alive(state.unit) then
        return { ok = false, error = "ultimate_tower_not_owned" }
    end
    local ability = state.unit:FindAbilityByName("ability_destroy_arrow_tower")
    if not ability or ability:IsNull() or ability:IsHidden()
        or not ability:IsActivated() then
        return { ok = false, error = "destroy_ability_unavailable" }
    end
    remove_ultimate_state(state)
    if valid(state.unit) then state.unit:ForceKill(false) end
    event_bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
        player_id = player_id,
        ultimate_count = #player_ultimates(player_id),
        maximum = 1,
        reason = "fusion_destroyed",
    })
    return { ok = true }
end

local function plan_group_move(states, target, validate)
    if #states == 0 or not target then
        return nil, "teleport_anchor_missing"
    end
    local origin = states[1].unit:GetAbsOrigin()
    local destinations = {}
    for _, state in ipairs(states) do
        local destination = target + (state.unit:GetAbsOrigin() - origin)
        local ok, error_code = validate(state, destination)
        if not ok then return nil, error_code or "teleport_anchor_invalid" end
        destinations[#destinations + 1] = destination
    end
    return destinations
end

local function fusion_spawn_position(caster, selected)
    if not alive(caster) then return nil, "fusion_caster_invalid" end
    -- Fusion replaces the selected towers at the casting tower's exact origin.
    -- Do not project the result to a nearby free grid cell.
    return caster:GetAbsOrigin()
end

local function sync_fusion_abilities(player_id, buildings)
    local synced = 0
    for _, item in ipairs(buildings or {}) do
        if item.player_id == player_id and item.building_id == "arrow_tower"
            and alive(item.unit) and item.tower_class then
            local row = final_row(item.tower_class)
            if row and tonumber(item.route_level) == tonumber(row.level)
                and tonumber(item.fusion_participated) ~= 1 then
                tower_ability_sync.sync({
                    unit = item.unit,
                    building_id = item.building_id,
                    tower_class = item.tower_class,
                    level = item.level,
                    player_id = player_id,
                    fusion_participated = item.fusion_participated,
                    definition = item.definition,
                }, row)
                synced = synced + 1
            end
        end
    end
    return synced
end

local function fuse(payload)
    local caster = payload and payload.caster
    if not alive(caster) then
        print("[TowerFusion] rejected error=fusion_caster_invalid")
        return { ok = false, error = "fusion_caster_invalid" }
    end
    local player_id = tonumber(caster.survival_player_id)
        or caster:GetPlayerOwnerID()
    if player_id == nil or fusion_in_progress[player_id] then
        print("[TowerFusion] rejected player=" .. tostring(player_id)
            .. " error=fusion_in_progress")
        return { ok = false, error = "fusion_in_progress" }
    end
    fusion_in_progress[player_id] = true
    local function fail(result)
        fusion_in_progress[player_id] = nil
        print("[TowerFusion] failed player=" .. tostring(player_id)
            .. " error=" .. tostring(result and result.error or "unknown"))
        return result
    end
    local listed = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = player_id,
    })
    local eligible = eligibility(player_id, listed and listed.buildings)
    if eligible.ultimate_count >= 1 then
        return fail({ ok = false, error = "ultimate_tower_already_exists" })
    end
    local selected, error_code = select_towers(
        caster, player_id, listed and listed.buildings
    )
    if not selected then
        notify(player_id, error_code, "error")
        return fail({ ok = false, error = error_code })
    end
    sync_fusion_abilities(player_id, listed and listed.buildings)
    local spawn_position, spawn_error = fusion_spawn_position(caster, selected)
    if not spawn_position then
        return fail({ ok = false, error = spawn_error })
    end
    local team_number = caster:GetTeamNumber()
    -- Snapshot material stats before the G-style destruction invalidates their
    -- entity handles. The ultimate is prepared before consuming materials, but
    -- is not registered or allowed to occupy its grid until consumption succeeds.
    for _, item in ipairs(selected) do
        local row = final_row(item.tower_class) or {}
        item.max_health = math.max(0, item.unit:GetMaxHealth())
        item.health = math.max(0, item.unit:GetHealth())
        item.armor = tonumber(item.runtime_armor)
            or item.unit:GetPhysicalArmorBaseValue()
        item.base_attack_damage = tonumber(row.base_attack_damage) or 0
        item.attack_damage = item.unit:GetAverageTrueAttackDamage(item.unit)
    end
    local state, create_error = prepare_ultimate(
        player_id, team_number, selected, spawn_position, caster:entindex()
    )
    if not state then return fail({ ok = false, error = create_error }) end
    local material_entindexes = {}
    for _, item in ipairs(selected) do
        material_entindexes[#material_entindexes + 1] = item.entindex
    end
    local consumed = event_bus.request(events.BUILDING_FUSION_CONSUME_REQUEST, {
        player_id = player_id,
        entindexes = material_entindexes,
    })
    if not consumed or not consumed.ok then
        if valid(state.unit) then state.unit:RemoveSelf() end
        return fail(consumed or { ok = false, error = "fusion_consume_failed" })
    end
    commit_ultimate(state)
    event_bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
        player_id = player_id,
        ultimate_count = #player_ultimates(player_id),
        maximum = 1,
        reason = "fusion_completed",
    })
    notify(player_id, "七塔合一完成")
    fusion_in_progress[player_id] = nil
    print("[TowerFusion] completed player=" .. tostring(player_id)
        .. " entindex=" .. tostring(state.unit:entindex()))
    return { ok = true, unit = state.unit }
end

function M.teleport_for_player(player_id, hero)
    player_id = tonumber(player_id)
    local states = player_ultimates(player_id)
    local wall = wall_by_player[player_id]
    if #states == 0 then
        return { ok = false, error = "ultimate_tower_missing" }
    end
    local target
    if group_at_wall_by_player[player_id] == true then
        target = alive(hero) and hero:GetAbsOrigin() or nil
    else
        target = valid(wall) and wall:GetAbsOrigin() or nil
    end
    if not target then return { ok = false, error = "teleport_anchor_missing" } end
    local anchor = group_at_wall_by_player[player_id] == true and hero or wall
    local ignored_entindexes = {}
    if valid(anchor) then ignored_entindexes[anchor:entindex()] = true end
    for _, state in ipairs(states) do
        ignored_entindexes[state.unit:entindex()] = true
    end
    local planned_cells = {}
    local planned_grids = {}
    local destinations, move_error = plan_group_move(states, target,
        function(state, destination)
        local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
            position = destination,
            footprint = state.footprint,
            ignore_entindex = valid(anchor) and anchor:entindex()
                or state.unit:entindex(),
            ignore_entindexes = ignored_entindexes,
            team = state.unit:GetTeamNumber(),
        })
        if not grid or grid.ok ~= true then
            return false, grid and grid.error or "teleport_anchor_invalid"
        end
        local footprint = grid.footprint or state.footprint or { x = 1, y = 1 }
        for x = grid.grid_x, grid.grid_x + footprint.x - 1 do
            for y = grid.grid_y, grid.grid_y + footprint.y - 1 do
                local key = tostring(x) .. ":" .. tostring(y)
                if planned_cells[key] then
                    return false, "teleport_group_overlap"
                end
            end
        end
        for x = grid.grid_x, grid.grid_x + footprint.x - 1 do
            for y = grid.grid_y, grid.grid_y + footprint.y - 1 do
                planned_cells[tostring(x) .. ":" .. tostring(y)] = true
            end
        end
        planned_grids[#planned_grids + 1] = grid
        return true
    end)
    if not destinations then
        return { ok = false, error = move_error }
    end
    for index, state in ipairs(states) do
        local grid = planned_grids[index]
        move_state(state, grid.world_position or destinations[index], grid)
    end
    group_at_wall_by_player[player_id] =
        group_at_wall_by_player[player_id] ~= true
    return { ok = true, moved = #states }
end

local function on_building(payload)
    if payload and payload.building_id == "wall"
        and payload.player_id ~= nil and valid(payload.unit) then
        wall_by_player[tonumber(payload.player_id)] = payload.unit
    end
end

local function on_hero_combat_stats_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    for _, state in ipairs(player_ultimates(player_id)) do
        refresh_inherited_hero_stats(state, payload.snapshot)
    end
end

function M.init()
    ultimate_by_player = {}
    state_by_entindex = {}
    wall_by_player = {}
    group_at_wall_by_player = {}
    fusion_in_progress = {}
    event_bus.handle_request(events.TOWER_FUSION_REQUEST, fuse)
    event_bus.handle_request(events.TOWER_FUSION_MOVE_REQUEST, move_for_player)
    event_bus.handle_request(events.TOWER_FUSION_DESTROY_REQUEST,
        destroy_for_player)
    event_bus.handle_request(events.TOWER_FUSION_ELIGIBILITY_REQUEST,
        function(payload)
            local player_id = tonumber(payload and payload.player_id)
            if player_id == nil then
                return { ok = false, eligible = false, error = "invalid_player" }
            end
            local listed = event_bus.request(events.BUILDING_LIST_REQUEST, {
                player_id = player_id,
            })
            return eligibility(player_id, listed and listed.buildings)
        end)
    event_bus.subscribe(events.BUILDING_CREATED, on_building)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building)
    event_bus.subscribe(events.HERO_COMBAT_STATS_CHANGED,
        on_hero_combat_stats_changed)
end

M._test = {
    select_towers = select_towers,
    eligibility = eligibility,
    ultimate_limit = ultimate_limit,
    player_ultimates = player_ultimates,
    plan_group_move = plan_group_move,
    set_player_ultimates = function(player_id, states)
        ultimate_by_player[player_id] = states or {}
    end,
}
return M
