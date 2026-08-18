local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local routes = require("config/tower_route_config")
local runtime = require("config/generated/tower_fusion_runtime")
local tower_skills = require("systems/tower_skill_runtime")
local tree_damage_rules = require("systems/tree_damage_rules")
local anti_air_rules = require("systems/anti_air_rules")
local tower_combat_rules = require("config/tower_combat_rules")
local tower_ability_sync = require("systems/tower_ability_sync")

local M = {}

local ultimate_by_player = {}
local state_by_id = {}
local wall_by_player = {}
local group_at_wall_by_player = {}
local fusion_in_progress = {}
local next_id = 0

local function config()
    return runtime.by_id.ultimate_tower or {}
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

local function add_proxy_skills(proxy, row)
    for _, skill_id in ipairs(row.skill_ids or {}) do
        local ability = proxy:AddAbility(skill_id)
        if ability then ability:SetLevel(1) end
    end
    tower_skills.apply(proxy, row.skill_ids)
end

local function create_proxy(state, source, row, class_id)
    local proxy = CreateUnitByName(
        config().unit_name, state.unit:GetAbsOrigin(), false,
        state.unit, state.unit, state.unit:GetTeamNumber()
    )
    if not valid(proxy) then return nil end
    proxy:AddNoDraw()
    proxy:SetInvulnerable(true)
    proxy:SetControllableByPlayer(state.player_id, false)
    proxy.survival_ultimate_tower_proxy = true
    proxy.survival_tower_class = class_id
    proxy.survival_super_tower_crit_chance =
        tonumber(source.unit.survival_super_tower_crit_chance) or 0
    proxy.survival_attack_range = source.unit.Script_GetAttackRange
        and source.unit:Script_GetAttackRange()
        or source.unit:GetAttackRange()
    proxy:SetBaseAttackTime(math.max(0.1,
        tonumber(source.unit:GetSecondsPerAttack())
            or tonumber(row.base_attack_speed) or 1))
    proxy:SetBaseDamageMin(state.base_attack)
    proxy:SetBaseDamageMax(state.base_attack)
    proxy:SetAttackCapability(DOTA_UNIT_CAP_RANGED_ATTACK)
    if row.projectile_model and proxy.SetRangedProjectileName then
        proxy:SetRangedProjectileName(row.projectile_model)
        proxy.survival_projectile_model = row.projectile_model
    end
    local projectile_speed = tonumber(source.unit.survival_projectile_speed)
        or (source.unit.GetProjectileSpeed
            and tonumber(source.unit:GetProjectileSpeed()))
        or tower_combat_rules.projectile_speed(row.projectile_speed)
        or tower_combat_rules.projectile_speed(1000)
    if proxy.SetProjectileSpeed then
        proxy:SetProjectileSpeed(projectile_speed)
        proxy.survival_projectile_speed = projectile_speed
    end
    if proxy.SetAcquisitionRange then proxy:SetAcquisitionRange(0) end
    add_proxy_skills(proxy, row)
    proxy:AddNewModifier(proxy, nil, "modifier_tower_attack_effects", {})
    for _, skill_id in ipairs(row.skill_ids or {}) do
        if string.match(skill_id, "^laser_") then
            proxy:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK)
            break
        end
    end
    return {
        proxy = proxy,
        class_id = class_id,
        row = row,
        range = source.unit.Script_GetAttackRange
            and source.unit:Script_GetAttackRange()
            or source.unit:GetAttackRange(),
        interval = math.max(0.1,
            tonumber(source.unit:GetSecondsPerAttack())
                or tonumber(row.base_attack_speed) or 1),
        projectile = row.projectile_model,
        projectile_speed = math.max(1, projectile_speed),
        next_attack_at = GameRules:GetGameTime(),
    }
end

local function create_ultimate(player_id, team_number, selected, position)
    local unit = CreateUnitByName(
        config().unit_name, position, true,
        nil, nil, team_number
    )
    if not valid(unit) then return nil, "fusion_create_failed" end
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
    unit:SetBaseMaxHealth(math.max(1, maximum))
    unit:SetMaxHealth(math.max(1, maximum))
    unit:SetHealth(math.max(1, math.min(maximum, current)))
    unit:SetPhysicalArmorBaseValue(armor)
    unit:SetBaseDamageMin(attack)
    unit:SetBaseDamageMax(attack)

    next_id = next_id + 1
    local state = {
        id = next_id,
        player_id = player_id,
        unit = unit,
        base_attack = attack,
        streams = {},
        at_wall = false,
        footprint = selected[1].definition
            and selected[1].definition.footprint or { x = 2, y = 2 },
    }
    for index, ability_name in ipairs(config().passive_slot_ability_ids or {}) do
        local ability = unit:AddAbility(ability_name)
        if ability then
            ability:SetLevel(1)
            ability:SetHidden(false)
            ability:SetActivated(false)
            ability.survival_passive_slot = index
        end
    end
    state_by_id[state.id] = state
    ultimate_by_player[player_id] = ultimate_by_player[player_id] or {}
    ultimate_by_player[player_id][#ultimate_by_player[player_id] + 1] = state
    return state
end

local function remove_ultimate_state(state)
    if not state then return end
    state_by_id[state.id] = nil
    local saved = ultimate_by_player[state.player_id] or {}
    for index = #saved, 1, -1 do
        if saved[index] == state then table.remove(saved, index) end
    end
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

local function find_target(state, stream)
    local units = FindUnitsInRadius(
        state.unit:GetTeamNumber(), state.unit:GetAbsOrigin(), nil,
        math.max(1, stream.range), DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false
    )
    for _, unit in ipairs(units or {}) do
        if alive(unit) and not tree_damage_rules.is_tree(unit)
            and anti_air_rules.can_attack(stream.proxy, unit) then
            return unit
        end
    end
    return nil
end

local function monkey_r_stats(player_id)
    local skills = event_bus.request(events.HERO_SKILL_STATE_GET_REQUEST, {
        player_id = player_id,
    })
    local active = false
    for _, skill in ipairs(skills and skills.snapshot and skills.snapshot.skills or {}) do
        if skill.skill_id == "skill_monkey_king_agility"
            and skill.locked ~= 1 and (tonumber(skill.level) or 0) > 0 then
            active = true
        end
    end
    if not active then return 0, 0, 1 end
    local stats = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = player_id,
    })
    stats = stats and stats.snapshot or {}
    return ((tonumber(stats.attack_min) or 0)
        + (tonumber(stats.attack_max) or 0)) * 0.5,
        tonumber(stats.critical_chance_pct) or 0,
        (tonumber(stats.critical_damage_pct) or 200) / 100
end

local function fire(state, stream, target)
    local hero_attack, hero_crit_chance, hero_crit_multiplier =
        monkey_r_stats(state.player_id)
    stream.proxy:SetBaseDamageMin(state.base_attack + hero_attack)
    stream.proxy:SetBaseDamageMax(state.base_attack + hero_attack)
    stream.proxy.survival_inherited_critical_chance_pct = hero_crit_chance
    stream.proxy.survival_inherited_critical_damage_pct =
        hero_crit_multiplier * 100
    stream.proxy:PerformAttack(
        target, false, false, true, false, true, false, false
    )
end

local function think()
    local now = GameRules:GetGameTime()
    for id, state in pairs(state_by_id) do
        if not alive(state.unit) then
            for _, stream in ipairs(state.streams or {}) do
                if valid(stream.proxy) then UTIL_Remove(stream.proxy) end
            end
            remove_ultimate_state(state)
            event_bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
                player_id = state.player_id,
                ultimate_count = #player_ultimates(state.player_id),
                maximum = ultimate_limit(),
                reason = "ultimate_tower_removed",
            })
        else
            for index, stream in ipairs(state.streams) do
                stream.index = index
                stream.proxy:SetAbsOrigin(state.unit:GetAbsOrigin())
                if now >= stream.next_attack_at then
                    local target = find_target(state, stream)
                    if target then
                        fire(state, stream, target)
                        stream.next_attack_at = now + math.max(
                            0.1,
                            tonumber(stream.proxy:GetSecondsPerAttack())
                                or stream.interval
                        )
                    end
                end
            end
        end
    end
end

local function fuse(payload)
    local caster = payload and payload.caster
    if not alive(caster) then return { ok = false, error = "fusion_caster_invalid" } end
    local player_id = tonumber(caster.survival_player_id)
        or caster:GetPlayerOwnerID()
    if player_id == nil or fusion_in_progress[player_id] then
        return { ok = false, error = "fusion_in_progress" }
    end
    fusion_in_progress[player_id] = true
    local function fail(result)
        fusion_in_progress[player_id] = nil
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
    -- entity handles. The actual towers must be removed before spawning the
    -- ultimate tower so their attack loops cannot survive the fusion frame.
    for _, item in ipairs(selected) do
        local row = final_row(item.tower_class) or {}
        item.max_health = math.max(0, item.unit:GetMaxHealth())
        item.health = math.max(0, item.unit:GetHealth())
        item.armor = tonumber(item.runtime_armor)
            or item.unit:GetPhysicalArmorBaseValue()
        item.base_attack_damage = tonumber(row.base_attack_damage) or 0
        item.attack_damage = item.unit:GetAverageTrueAttackDamage(item.unit)
    end
    local consumed = event_bus.request(events.BUILDING_FUSION_CONSUME_REQUEST, {
        player_id = player_id,
        entindexes = (function()
            local result = {}
            for _, item in ipairs(listed and listed.buildings or {}) do
                if item.player_id == player_id
                    and item.building_id == "arrow_tower"
                    and alive(item.unit) then
                    result[#result + 1] = item.entindex
                end
            end
            return result
        end)(),
    })
    if not consumed or not consumed.ok then
        return fail(consumed or { ok = false, error = "fusion_consume_failed" })
    end
    local state, create_error = create_ultimate(
        player_id, team_number, selected, spawn_position
    )
    if not state then return fail({ ok = false, error = create_error }) end
    event_bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
        player_id = player_id,
        ultimate_count = #player_ultimates(player_id),
        maximum = 1,
        reason = "fusion_completed",
    })
    notify(player_id, "七塔合一完成")
    fusion_in_progress[player_id] = nil
    return { ok = true, unit = state.unit }
end

function M.on_projectile_hit(_, target, _, data)
    local state = state_by_id[tonumber(data and data.fusion_id)]
    local stream = state and data
        and state.streams[tonumber(data.stream_index)]
    if not state or not stream or not alive(target) then return true end
    local damage = math.max(0, tonumber(data.damage) or 0)
    event_bus.request(events.TOWER_SKILL_DAMAGE_REQUEST, {
        attacker = stream.proxy,
        victim = target,
        damage = damage,
        damage_type = DAMAGE_TYPE_PHYSICAL,
        source_kind = "attack",
        tags = { "ultimate_tower_stream", stream.class_id },
    })
    local multiplier = tonumber(data.critical_multiplier) or 1
    event_bus.emit(events.TOWER_ATTACK_LANDED, {
        tower = stream.proxy,
        target = target,
        damage = damage,
        critical = multiplier > 1,
        critical_multiplier = multiplier,
        critical_source = tonumber(data.critical_source_id) == 1
            and "inherited" or nil,
        skills = tower_skills.get(stream.proxy),
    })
    return true
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
        for _, stream in ipairs(state.streams or {}) do
            if valid(stream.proxy) then
                ignored_entindexes[stream.proxy:entindex()] = true
            end
        end
    end
    local planned_cells = {}
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
        return true
    end)
    if not destinations then
        return { ok = false, error = move_error }
    end
    for index, state in ipairs(states) do
        state.unit:SetAbsOrigin(destinations[index])
        for _, stream in ipairs(state.streams) do
            stream.proxy:SetAbsOrigin(destinations[index])
        end
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

function M.init()
    ultimate_by_player = {}
    state_by_id = {}
    wall_by_player = {}
    group_at_wall_by_player = {}
    fusion_in_progress = {}
    next_id = 0
    event_bus.handle_request(events.TOWER_FUSION_REQUEST, fuse)
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
    scheduler.every(math.max(0.01,
        tonumber(config().target_scan_interval) or 0.05), think,
        "ultimate_tower_streams")
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
