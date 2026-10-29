local event_bus = require("core/event_bus")
local events = require("core/events")
local model_scale = require("visual/model_scale")
local config = require("config/tree_config")
local particle_manager = require("core/particle_manager")
local rogue_effect_state = require("systems/rogue_effect_state_service")
local tree_damage_rules = require("systems/tree_damage_rules")
local harvest_feedback = require("systems/harvest_feedback_service")
local registered_lanes = require("systems/registered_wave_lane_view")
local grid_placement = require("systems/grid_placement_system")

local M = {}
local TREE_RESERVATION = "survival_tree_reserved"
local trees_by_player = {}
local trees_by_entity = {}
local rich_level2_rewards = {}
local region_slots = {}
local ordinary_reservations = false
local wall_attack_frame = nil
local walls_by_player = {}
local attacked_targets = nil

local function rich_mode()
    local setup = package.loaded["systems/match_setup_service"]
    local mode = setup and setup.get_mode and setup.get_mode()
    return mode == "rich" or mode == "cold" or mode == "scourge" or mode == "ruins"
end

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function find_player_wall(player_id)
    local response = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = player_id,
    }) or {}
    for _, building in ipairs(response.buildings or response) do
        if building.building_id == "wall" and valid_entity(building.unit) then
            return building.unit
        end
    end
    return nil
end

local function wall_is_under_attack(player_id)
    -- Many workers can land attacks in one simulation frame. Their peaceful
    -- harvest check shares the wall lookup and the same live enemy snapshot;
    -- the next frame sees target changes without delaying resource settlement.
    local frame = GameRules and GameRules.GetGameTime and GameRules:GetGameTime()
    if frame == nil or frame ~= wall_attack_frame then
        wall_attack_frame = frame
        walls_by_player = {}
        attacked_targets = nil
    end
    local wall
    if player_id ~= nil then wall = walls_by_player[player_id] end
    if wall == nil then
        wall = find_player_wall(player_id)
        if frame ~= nil and player_id ~= nil then walls_by_player[player_id] = wall or false end
    end
    if not valid_entity(wall) or not Entities or not Entities.FindAllByClassname then return false end
    if attacked_targets then return attacked_targets[wall] == true end
    local targets = {}
    for _, unit in ipairs(registered_lanes.append(
        Entities:FindAllByClassname("npc_dota_creature") or {})) do
        if valid_entity(unit) and unit:IsAlive()
            and (unit.survival_is_wave_monster == true
                or unit.survival_is_challenge_monster == true)
            and unit.GetAttackTarget then
            local target = unit:GetAttackTarget()
            if target then targets[target] = true end
        end
    end
    if frame ~= nil then attacked_targets = targets end
    return targets[wall] == true
end

local function level_row(level)
    return config.levels[math.max(
        1,
        math.min(config.max_level, tonumber(level) or 1)
    )]
end

local function tree_grid(point)
    point = point or config.spawn_point
    local footprint = config.footprint
    local size = tonumber(config.grid_cell_size) or 64
    local anchor_x = math.floor(point.x / size + 0.5)
    local anchor_y = math.floor(point.y / size + 0.5)
    return {
        grid_x = anchor_x - math.floor(footprint.x / 2),
        grid_y = anchor_y - math.floor(footprint.y / 2),
        footprint = footprint,
    }
end

local function lumber_efficiency_buff(level)
    return math.max(
        0,
        tonumber(config.lumber_efficiency_buff_per_level) or 0
    ) * math.max(0, (tonumber(level) or 1) - 1)
end

local function player_lumber_efficiency_buff(player_id, level)
    return lumber_efficiency_buff(level)
        + (rich_level2_rewards[player_id] and config.rich_level2_reward.lumber_efficiency or 0)
end

local function tree_snapshot(state)
    local tree_level = state.level
    local row = level_row(tree_level)
    return {
        player_id = state.player_id,
        region_id = state.region_id,
        entindex = valid_entity(state.unit) and state.unit:entindex() or -1,
        level = tree_level,
        max_level = config.max_level,
        health = row.health,
        armor = row.armor,
        war3_armor = row.war3_armor,
        minimum_armor = row.minimum_armor,
        war3_minimum_armor = row.war3_minimum_armor,
        lumber_efficiency_buff = player_lumber_efficiency_buff(state.player_id, tree_level),
        rich_level2_wood_per_second = rich_level2_rewards[state.player_id]
            and config.rich_level2_reward.wood_per_second or 0,
    }
end

local function publish_changed(state, reason)
    local snapshot = tree_snapshot(state)
    snapshot.reason = reason or "unknown"
    event_bus.emit(events.TREE_CHANGED, snapshot)
end

local function clear_armor_reduction(tree)
    if tree.HasModifier
        and tree:HasModifier("modifier_research_armor_reduction") then
        tree:RemoveModifierByName("modifier_research_armor_reduction")
    end
end

local function apply_level(tree, level)
    local tree_level = math.max(
        1,
        math.min(config.max_level, tonumber(level) or 1)
    )
    local row = level_row(tree_level)
    clear_armor_reduction(tree)
    local projected = require("combat/endless_stat_projection").prepare(tree, {
        health = row.health, attack = 0,
    })
    projected.health = math.max(1, math.floor(projected.health + 0.5))
    tree:SetBaseMaxHealth(projected.health)
    tree:SetMaxHealth(projected.health)
    tree:SetPhysicalArmorBaseValue(row.armor)
    tree.survival_minimum_armor = row.minimum_armor
    tree.survival_tree_level = tree_level
    tree.survival_level = tree_level
    tree:SetHealth(projected.health)
end

local function reserve_tree_grid(point, entindex)
    local reserved_grid = tree_grid(point)
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = reserved_grid.grid_x,
        grid_y = reserved_grid.grid_y,
        footprint = reserved_grid.footprint,
        entindex = entindex or TREE_RESERVATION,
    })
end

local function socket_available(point, primary, released_entindex)
    local reserved = tree_grid(point)
    local size = tonumber(config.grid_cell_size) or 64
    -- Only four cells per candidate. Empty backup sockets are normal building
    -- ground, so check them before the unconditional GRID_OCCUPY operation.
    for x = reserved.grid_x, reserved.grid_x + reserved.footprint.x - 1 do
        for y = reserved.grid_y, reserved.grid_y + reserved.footprint.y - 1 do
            local occupant = grid_placement.occupant_at_position(
                Vector((x + 0.5) * size, (y + 0.5) * size, point.z)
            )
            if occupant ~= nil and occupant ~= released_entindex
                and not (primary and occupant == TREE_RESERVATION) then
                return false
            end
        end
    end
    return true
end

local function release_tree_grid(state)
    if not state.rich and state.slot == 1 and socket_available(state.point, true, state.entindex) then
        reserve_tree_grid(state.point)
        return
    end
    local reserved = tree_grid(state.point)
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = reserved.grid_x, grid_y = reserved.grid_y,
        footprint = reserved.footprint, entindex = state.entindex,
    })
end

local function release_ordinary_reservations()
    if not ordinary_reservations then return end
    for _, points in pairs(config.spawn_regions) do
        if points[1] and socket_available(points[1], true) then
            local reserved = tree_grid(points[1])
            -- Named reservations have no numeric entity handle. Only clear
            -- their complete footprint while every cell is still ours/empty.
            event_bus.request(events.GRID_RELEASE_REQUEST, {
                grid_x = reserved.grid_x, grid_y = reserved.grid_y,
                footprint = reserved.footprint,
            })
        end
    end
    ordinary_reservations = false
end

local function rich_socket(player_id, city, origin)
    local regions = require("systems/rich_region_service")
    local region, reason = regions.region(player_id)
    if not region then return nil, nil, nil, reason end
    release_ordinary_reservations()
    local mode = require("systems/mode_spawn_service").mode()
    local region_id = tostring(mode) .. ":" .. region.id
    region_slots[region_id] = region_slots[region_id] or {}
    local slots, candidates = region_slots[region_id], {}
    local size = tonumber(config.grid_cell_size) or 64
    if mode == "rich" then
        for _, point in ipairs(config.rich_spawn_regions[region.id] or {}) do
            candidates[#candidates + 1] = { point = { x = point.x, y = point.y, z = origin.z } }
        end
    else
        for _, cell in ipairs(region.cells) do
            local point = { x = (cell[1] + math.floor(config.footprint.x / 2)) * size,
                y = (cell[2] + math.floor(config.footprint.y / 2)) * size, z = origin.z }
            local distance = (point.x - origin.x) ^ 2 + (point.y - origin.y) ^ 2
            if distance >= (size * 4) ^ 2 then
                candidates[#candidates + 1] = { point = point, distance = distance }
            end
        end
        table.sort(candidates, function(left, right)
            if left.distance ~= right.distance then return left.distance < right.distance end
            if left.point.x ~= right.point.x then return left.point.x < right.point.x end
            return left.point.y < right.point.y
        end)
    end
    for index, candidate in ipairs(candidates) do
        local point = candidate.point
        local reserved = tree_grid(point)
        if slots[index] == nil and regions.validate_building_footprint(player_id,
            reserved.grid_x * size, reserved.grid_y * size,
            (reserved.grid_x + reserved.footprint.x) * size,
            (reserved.grid_y + reserved.footprint.y) * size)
            and socket_available(point, false) then
            -- Reuse building terrain, occupancy and live hull checks. Searching
            -- once at city creation never moves an existing resource tree.
            local placement = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
                player_id = player_id, position = Vector(point.x, point.y, point.z),
                footprint = config.footprint,
                team = city.GetTeamNumber and city:GetTeamNumber() or DOTA_TEAM_GOODGUYS,
                compact = true,
            })
            if placement and placement.ok == true then
                return region_id, index, placement.world_position or point
            end
        end
    end
    return region_id, nil, nil, "rich_tree_socket_unavailable"
end

local function upgrade_tree(tree)
    local state = trees_by_entity[tree]
    if not valid_entity(tree) or not state then return end
    local previous_level = state.level
    local next_level = math.min(config.max_level, state.level + 1)
    apply_level(tree, next_level)
    state.level = next_level
    local setup = package.loaded["systems/match_setup_service"]
    local reward = previous_level == 1 and next_level == 2
        and setup and setup.get_mode and setup.get_mode() == "rich"
        and not rich_level2_rewards[state.player_id]
    if reward then rich_level2_rewards[state.player_id] = true end
    local reason = next_level > previous_level
        and "tree_level_up" or "tree_max_level_reset"
    publish_changed(state, reason)
    if reward then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = state.player_id, level = "info",
            message = string.format("丰饶之树升至 Lv2：本局永久额外获得伐木效率 +%d，每秒木材 +%d！",
                config.rich_level2_reward.lumber_efficiency, config.rich_level2_reward.wood_per_second),
        })
    end
end

local function spawn_tree(payload)
    local city = payload and payload.unit
    if not valid_entity(city) then
        print("[TreeSystem] main city entity is unavailable")
        return
    end
    local player_id = tonumber(payload.player_id or city.survival_player_id)
    if player_id == nil or player_id < 0 then return end
    if trees_by_player[player_id] then return end
    local origin = city:GetAbsOrigin()
    local is_rich = rich_mode()
    local region_id, slot, point, reason
    if is_rich then
        region_id, slot, point, reason = rich_socket(player_id, city, origin)
    else
        local center = config.region_center
        region_id = (origin.y >= center.y and "north" or "south")
            .. (origin.x >= center.x and "east" or "west")
        for index, candidate in ipairs(config.spawn_regions[region_id]) do
            if region_slots[region_id][index] == nil and socket_available(candidate, index == 1) then
                slot, point = index, candidate; break
            end
        end
    end
    if not point then
        print("[TreeSystem] no free tree socket in " .. tostring(region_id) .. ":" .. tostring(reason or "occupied"))
        return
    end
    local slots = region_slots[region_id]
    local position = Vector(point.x, point.y, point.z)
    local tree = CreateUnitByName(
        config.unit_name,
        position,
        false,
        nil,
        nil,
        DOTA_TEAM_BADGUYS
    )
    if not tree then
        print("[TreeSystem] failed to create tree")
        return
    end

    tree:SetAbsOrigin(position)
    tree:SetModel(config.model_name)
    tree:SetOriginalModel(config.model_name)
    model_scale.apply(tree, config.model_scale)
    tree:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    tree.survival_tree_owner_id = player_id
    tree.survival_tree_depleted_callback = upgrade_tree
    apply_level(tree, 1)
    if not tree:HasModifier("modifier_tree_progression") then
        require("core/modifier_registry").ensure(tree, "modifier_tree_progression", {})
    end
    local state = { unit = tree, entindex = tree:entindex(), player_id = player_id, level = 1,
        region_id = region_id, slot = slot, point = point, rich = is_rich }
    trees_by_player[player_id] = state
    trees_by_entity[tree] = state
    slots[slot] = player_id
    reserve_tree_grid(point, tree:entindex())

    local snapshot = tree_snapshot(state)
    event_bus.emit(events.TREE_SPAWNED, snapshot)
    publish_changed(state, "tree_spawned")
end

local function on_tree_hit(payload)
    local current_tree = payload.target
    if not valid_entity(current_tree) or not trees_by_entity[current_tree] then return end
    local attacker = payload.attacker
    if not valid_entity(attacker) then return end
    if not tree_damage_rules.is_allowed_tree_attacker(attacker) then return end
    local base_efficiency = payload.source == "hero"
        and config.hero_base_lumber_efficiency
        or payload.base_lumber_efficiency
    local hero_wood_bonus_pct = 0
    if payload.source == "hero" then
        hero_wood_bonus_pct = rogue_effect_state.numeric(payload.player_id,
            "builder_hero_wood_bonus_pct")
    elseif payload.source == "lumberjack" then
        local peaceful = rogue_effect_state.numeric(payload.player_id,
            "builder_peaceful_wood_per_hit")
        if peaceful > 0 and not wall_is_under_attack(payload.player_id) then
            base_efficiency = (tonumber(base_efficiency) or 0)
                + peaceful
        end
        if payload.attacker and payload.attacker.survival_super_lumberjack then
            payload.critical_chance_pct = (tonumber(payload.critical_chance_pct) or 0)
                + rogue_effect_state.numeric(payload.player_id,
                    "builder_super_lumberjack_crit_pct")
        end
    end
    local efficiency = math.max(0, math.floor(
        (tonumber(base_efficiency) or 0) + player_lumber_efficiency_buff(
            payload.player_id, (trees_by_player[payload.player_id] or {}).level)
            * math.max(1, tonumber(payload.fusion_count) or 1)
    ))
    if hero_wood_bonus_pct > 0 then
        efficiency = math.floor(efficiency * (1 + hero_wood_bonus_pct / 100))
    end
    local wood_total_bonus_pct = math.max(
        0, tonumber(payload.wood_total_bonus_pct) or 0
    )
    local next_wood_fraction = nil
    if payload.source == "lumberjack" and wood_total_bonus_pct > 0 then
        local exact = efficiency * (1 + wood_total_bonus_pct / 100)
            + (tonumber(attacker.survival_wood_fraction) or 0)
        efficiency = math.floor(exact + 0.0000001)
        next_wood_fraction = exact - efficiency
    end
    local critical = payload.critical == true
        or payload.source == "lumberjack"
        and RandomFloat(0, 100)
            < math.max(0, tonumber(payload.critical_chance_pct) or 0)
    if critical then
        efficiency = math.floor(efficiency * (
            2 + math.max(0,
                tonumber(payload.critical_yield_bonus_pct) or 0) / 100
        ))
    end
    if tonumber(payload.wood_multiplier_chance_pct)
        and RandomFloat(0, 100) < tonumber(payload.wood_multiplier_chance_pct) then
        efficiency = efficiency * 10
    end
    if efficiency <= 0 then return end
    local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
        player_id = payload.player_id,
        team = payload.team,
        wood = efficiency,
        gold = tonumber(payload.gold_per_hit_flat) or 0,
        reason = payload.source == "hero"
            and "hero_tree_hit" or "lumberjack_hit",
    })
    if not result or result.ok ~= true then return end
    if next_wood_fraction ~= nil then
        attacker.survival_wood_fraction = next_wood_fraction
    end
    local tree_damage_pct = math.max(
        0, tonumber(payload.tree_damage_chance_pct) or 0
    )
    if current_tree:GetHealth() > 1 and tree_damage_pct > 0
        and RandomFloat(0, 100) < tree_damage_pct then
        local amount = math.max(1, math.floor(
            current_tree:GetMaxHealth() * tree_damage_pct / 100
        ))
        local health = current_tree:GetHealth()
        if health > 1 then
            current_tree:SetHealth(math.max(1, health - amount))
        end
        if current_tree:GetHealth() <= 1 then
            event_bus.emit(events.TREE_DEPLETED, {
                attacker = attacker,
                target = current_tree,
                player_id = payload.player_id,
            })
            local callback = current_tree.survival_tree_depleted_callback
            if type(callback) == "function" then callback(current_tree) end
        end
    end
    local player = payload.source ~= "lumberjack" and payload.player_id ~= nil
        and PlayerResource:GetPlayer(payload.player_id) or nil
    local gold_amount = math.max(0, math.floor(
        tonumber(payload.gold_per_hit_flat) or 0
    ))
    if payload.source == "lumberjack" then
        harvest_feedback.add(payload.player_id, attacker, efficiency, gold_amount)
    else
        particle_manager.show_green_number(attacker, efficiency, player)
    end
    if payload.source ~= "lumberjack" and player and gold_amount > 0 then
        CustomGameEventManager:Send_ServerToPlayer(
            player,
            "survival_gold_mine_income_number",
            {
                target_entindex = attacker:entindex(),
                amount = gold_amount,
                critical = 0,
            }
        )
    end
end

local function on_building_created(payload)
    if not payload or payload.building_id ~= "main_city" then return end
    if not valid_entity(payload.unit) then return end
    spawn_tree(payload)
end

local function on_player_disconnected(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id ~= nil then harvest_feedback.reset(player_id) end
    local state = player_id and trees_by_player[player_id]
    if not state then return end
    trees_by_player[player_id] = nil
    trees_by_entity[state.unit] = nil
    region_slots[state.region_id][state.slot] = nil
    release_tree_grid(state)
    if valid_entity(state.unit) and UTIL_Remove then UTIL_Remove(state.unit) end
    event_bus.emit(events.TREE_DESTROYED, {
        player_id = player_id, entindex = -1, lumber_efficiency_buff = 0,
    })
end

function M.init()
    harvest_feedback.reset()
    trees_by_player = {}
    trees_by_entity = {}
    rich_level2_rewards = {}
    region_slots = {}
    ordinary_reservations = false
    wall_attack_frame = nil
    walls_by_player = {}
    attacked_targets = nil
    for region_id, points in pairs(config.spawn_regions) do
        region_slots[region_id] = {}
        -- One permanent tree patch per court. Other candidate sockets stay
        -- buildable until an actual additional player's tree occupies them.
        if points[1] and not rich_mode() then
            reserve_tree_grid(points[1])
            ordinary_reservations = true
        end
    end
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.TREE_HIT, on_tree_hit)
    event_bus.subscribe(events.PLAYER_DISCONNECTED, on_player_disconnected)
end

M._level_row_for_test = level_row
M._tree_grid_for_test = tree_grid
M._apply_level_for_test = apply_level
M._upgrade_tree_for_test = function(tree)
    upgrade_tree(tree)
end
M._reset_for_test = function(level, tree, player_id)
    local state = { level = tonumber(level) or 1, unit = tree, player_id = player_id or 0 }
    trees_by_player[state.player_id] = state
    trees_by_entity[tree] = state
end

M._lumber_efficiency_buff_for_test = lumber_efficiency_buff

return M
